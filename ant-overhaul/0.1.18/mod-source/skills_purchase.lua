-- One queued home-skill purchase at a time. Called only from the game thread.
-- A bounded binary journal retains the original native files and sidecars.
-- Recovery refuses any bytes not observed before/after our own transaction.
local M={}
local JOURNAL='EAA_SkillPurchase_v1.bin'
local HEADER='EAA_SKILL_PURCHASE_V1\n'
local SIDECARS={'EAA_AllAttributes_v1.tsv','EAA_CustomSkills_v1.tsv','EAA_StoryRoster_v1.tsv'}
local MAX_BYTES=134217728
local OPTIONS={
 TrapjawAnt={left={recovery=true,invulnerable=true},right={evasion=true,reward=true}},
 SlaveMaker={left={special_master=true,follow_step=true},right={overseer_drill=true,overseer_haul=true}},
}
local function clone(t)if type(t)~='table'then return t end;local r={};for k,v in pairs(t)do r[k]=clone(v)end;return r end
local function safe_slot(s)return type(s)=='string'and #s>0 and #s<=96 and s:match('^[A-Za-z0-9_-]+$')end
local function finite(n)return type(n)=='number'and n==n and n~=math.huge and n~=-math.huge end
local function world(ctx)
 if not ctx then return nil end
 if type(ctx.world)=='number'or type(ctx.world)=='string'then return tostring(ctx.world)end
 local ok,id=pcall(function()return ctx.world:GetAddress()end);return ok and tostring(id)or nil
end
local function allowed(name,slot)
 if type(name)~='string'or #name>180 or name:find('[^A-Za-z0-9_.-]')then return false end
 for _,n in ipairs(SIDECARS)do if name==n or name==n..'.bak'or name==n..'.tmp'then return true end end
 if name:sub(1,#slot)~=slot then return false end
 local rest=name:sub(#slot+1)
 return rest=='.sav'or rest=='LevelData.sav'or rest:match('^%-backup[1-5]%.sav$')
  or rest:match('^LevelData%-backup[1-5]%.sav$')or rest:match('^Stage[1-5]%.sav$')
  or rest:match('^LevelDataStage[1-5]%.sav$')or rest:match('^NewGamePlus%d+%.sav$')
  or rest:match('^LevelDataNewGamePlus%d+%.sav$')
end
function M.install(api)
 local fileio=api.fileio or{open=io.open,remove=os.remove,rename=os.rename}
 local sequence,pending,busy,blocked=0,nil,false,nil
 local results={}
 local hash_cache,metrics,last_metrics
 -- Only this uninterrupted transaction owns these bytes. Recovery always reads
 -- its journal afresh; a successful flush/rename is required before caching it.
 local journal_known,journal_bytes=false,nil
 local directory
 local function report(why)(api.log or print)('[SkillPurchase] '..tostring(why))end
 local function dir()
  if directory then return directory end
  local root=assert(api.saved_dir(),'saved_directory_unavailable'):gsub('\\','/')
  assert(root:match('^%a:/')or root:sub(1,1)=='/','saved_directory_not_absolute')
  assert(not root:find('/../',1,true),'unsafe_saved_directory')
  if root:sub(-1)~='/'then root=root..'/'end
  directory=root..'SaveGames/';return directory
 end
 local function read(name)
  if api.storage then
   local bytes=api.storage.read(name);if metrics then metrics.read_bytes=metrics.read_bytes+(bytes and #bytes or 0)end
   return bytes
  end
  local f,e,code=fileio.open(dir()..name,'rb');if not f then if code and code~=2 then error(e)end;return nil end
  local bytes=f:read('*a');f:close()
  if metrics then metrics.read_bytes=metrics.read_bytes+(bytes and #bytes or 0)end
  return bytes
 end
 local function exists(name)
  if api.storage then
   if api.storage.exists then return api.storage.exists(name)==true end
   return read(name)~=nil
  end
  local f,e,code=fileio.open(dir()..name,'rb')
  if not f then if code and code~=2 then error(e)end;return false end
  f:close();return true
 end
 local function write(name,bytes)
  if api.storage then local ok,e=api.storage.write(name,bytes);assert(ok==true,e or'write_failed');return true end
  local f,e=fileio.open(dir()..name,'wb');assert(f,e)
  local ok,why=f:write(bytes);if not ok then f:close();error(why)end
  local flushed,fe=f:flush();local closed,ce=f:close();assert(flushed and closed,fe or ce);return true
 end
 local function remove(name)
  if not exists(name)then return true end
  if api.storage then local ok,e=api.storage.remove(name);assert(ok==true,e or'remove_failed');return true end
  local ok,e=fileio.remove(dir()..name);assert(ok,e);return true
 end
 local function atomic(name,bytes)
  local previous
  if name==JOURNAL and journal_known then previous=journal_bytes else previous=read(name)end
  write(name..'.tmp',bytes)
  if api.storage then
   write(name,bytes);remove(name..'.tmp')
   if name==JOURNAL and journal_known then journal_bytes=bytes end
   return true
  end
  if previous then remove(name)end
  local ok,e=fileio.rename(dir()..name..'.tmp',dir()..name)
  if not ok then if previous then write(name,previous)end;error(e)end
  if name==JOURNAL and journal_known then journal_bytes=bytes end
  return true
 end
 local function timed(label,fn,...)
  local started=os.clock();local result=table.pack(pcall(fn,...))
  if metrics then metrics.stages_ms[label]=(metrics.stages_ms[label]or 0)+(os.clock()-started)*1000 end
  if not result[1]then error(result[2],0)end
  return table.unpack(result,2,result.n)
 end
 local function hash(bytes)
  if bytes==nil then return'-'end
  if hash_cache and hash_cache[bytes]then
   if metrics then metrics.hash_reuses=metrics.hash_reuses+1 end
   return hash_cache[bytes]
  end
  local value=api.sha256(bytes)
  if metrics then metrics.hash_calls=metrics.hash_calls+1;metrics.hash_bytes=metrics.hash_bytes+#bytes end
  if hash_cache then hash_cache[bytes]=value end
  return value
 end
 local function encode(j)
  local rows={HEADER,'META\t'..j.id..'\t'..j.slot..'\t'..j.world..'\t'..j.before_fp..'\t'..j.before_balance..'\t'..j.cost..'\t'..j.phase..'\n'}
  for _,f in ipairs(j.files)do
   rows[#rows+1]=table.concat({'FILE',f.name,f.before_hash,f.after_hash,tostring(f.before and #f.before or -1)},'\t')..'\n'
   rows[#rows+1]=(f.before or'')..'\n'
  end
  rows[#rows+1]='END\n';local bytes=table.concat(rows);assert(#bytes<=MAX_BYTES,'skill_journal_too_large');return bytes
 end
 local function decode(bytes)
  assert(type(bytes)=='string'and #bytes<=MAX_BYTES and bytes:sub(1,#HEADER)==HEADER,'invalid_skill_journal')
  local pos=#HEADER+1;local stop=assert(bytes:find('\n',pos,true),'truncated_skill_journal');local meta=bytes:sub(pos,stop-1)
  local id,slot,w,fp,balance,cost,phase=meta:match('^META\t([%d-]+)\t([A-Za-z0-9_-]+)\t([A-Za-z0-9_-]+)\t([a-f0-9:]+)\t(%d+)\t(%d+)\t([a-z_]+)$')
  assert(id and safe_slot(slot)and #fp==129 and fp:sub(65,65)==':'and (phase=='prepared'or phase=='saved'or phase=='committed'or phase=='rollback'),'invalid_skill_journal_metadata')
  local j={id=id,slot=slot,world=w,before_fp=fp,before_balance=tonumber(balance),cost=tonumber(cost),phase=phase,files={}}
  local seen={};pos=stop+1
  while bytes:sub(pos,pos+3)~='END\n'do
   stop=assert(bytes:find('\n',pos,true),'truncated_skill_journal')
   local name,before_hash,after_hash,size=bytes:sub(pos,stop-1):match('^FILE\t([A-Za-z0-9_.-]+)\t([a-f0-9-]+)\t([a-f0-9-]+)\t([%d-]+)$')
   size=tonumber(size)
   assert(name and allowed(name,slot)and not seen[name]and size and size>=-1 and size%1==0 and size<=MAX_BYTES,'unsafe_skill_journal_file')
   assert((before_hash=='-'or #before_hash==64)and(after_hash=='-'or #after_hash==64),'invalid_skill_journal_hash')
   seen[name]=true;pos=stop+1
   local before=size>=0 and bytes:sub(pos,pos+size-1)or nil
   assert(size<0 or #before==size,'truncated_skill_journal_data')
   pos=pos+math.max(size,0);assert(bytes:sub(pos,pos)=='\n','invalid_skill_journal_boundary');pos=pos+1
   assert(hash(before)==before_hash,'skill_backup_hash_mismatch')
   j.files[#j.files+1]={name=name,before=before,before_hash=before_hash,after_hash=after_hash}
   assert(#j.files<=8200,'too_many_skill_backup_files')
  end
  assert(pos+4==#bytes+1,'unexpected_skill_journal_tail');return j
 end
 local function capture(j)
  for _,f in ipairs(j.files)do f.after_hash=hash(read(f.name))end
  atomic(JOURNAL,encode(j))
 end
 local function restore(j,ctx)
  -- Validate the entire write set before touching any file.
  for _,f in ipairs(j.files)do
   assert(allowed(f.name,j.slot),'unsafe_restore_target')
   local current=hash(read(f.name));assert(current==f.before_hash or current==f.after_hash,'unobserved_save_change:'..f.name)
  end
  j.phase='rollback';atomic(JOURNAL,encode(j))
  for _,f in ipairs(j.files)do
   if hash(read(f.name))~=f.before_hash then if f.before then write(f.name,f.before)else remove(f.name)end end
   assert(hash(read(f.name))==f.before_hash,'rollback_verify_failed:'..f.name)
  end
  if ctx then
   assert(ctx.slot==j.slot,'rollback_colony_changed')
   local ok,e=api.set_balance(ctx,j.before_balance);assert(ok~=false,e or'balance_restore_failed')
   if api.reset then local restored,why=api.reset(ctx);assert(restored~=false,why or'profile_reset_failed')end
   assert(api.balance(ctx)==j.before_balance,'balance_restore_readback_failed')
  end
  remove(JOURNAL);return true
 end
 local function file_names(ctx)
  local names,seen={},{}
  local function add(name)assert(allowed(name,ctx.slot),'unsafe_backup_name');if not seen[name]then seen[name]=true;names[#names+1]=name end end
  -- Default SaveFormicarium writes the live pair and five rotating backups.
  -- The audited NoBackup=true path writes only the live pair. Opt out only on
  -- explicit false supplied by that caller; unknown APIs retain full coverage.
  -- Stage/NewGamePlus archives are not part of this operation's write set.
  for _,prefix in ipairs({ctx.slot,ctx.slot..'LevelData'})do
   add(prefix..'.sav')
   if api.save_rotates_backups~=false then for i=1,5 do add(prefix..'-backup'..i..'.sav')end end
  end
  for _,name in ipairs(SIDECARS)do add(name);add(name..'.bak');add(name..'.tmp')end
  if api.list_save_names then for _,name in ipairs(api.list_save_names(ctx)or{})do add(name)end end
  table.sort(names);return names
 end
 local function same(ctx,other)return ctx and other and ctx.slot==other.slot and world(ctx)==world(other)end
 local control={}
 function control.quote(ctx,id,side,value,before)
  if blocked then return{can_purchase=false,reason=blocked}end
  if pending or busy then return{can_purchase=false,reason='skill_purchase_pending'}end
  local choices=OPTIONS[id]
  if not choices or not choices[side]or not choices[side][value]then return{can_purchase=false,reason='invalid_custom_skill'}end
  if not ctx or ctx.is_formicarium~=true or ctx.story==true or not same(ctx,api.get_context())then return{can_purchase=false,reason='home_skill_selection_required'}end
  local owned=before[id] and before[id][side]==value
  local cost=owned and 0 or(side=='left'and 80 or 100)
  local balance=api.balance(ctx)
  return{cost=cost,owned=owned==true,can_purchase=finite(balance)and balance>=cost and balance%1==0,reason=finite(balance)and balance<cost and'蚁皇浆不足'or nil}
 end
 function control.request(ctx,id,side,value,before,after,quote,set_home)
  local fresh=control.quote(ctx,id,side,value,before)
  if not fresh.can_purchase then return nil,fresh.reason or'skill_purchase_unavailable'end
  if fresh.owned then return true end
  local fingerprint=api.fingerprint(ctx.slot);if not fingerprint then return nil,'skill_profile_unavailable'end
  sequence=sequence+1;local job_id=tostring(os.time())..'-'..sequence
  pending={id=job_id,ctx=ctx,slot=ctx.slot,world=world(ctx),before_fp=fingerprint,before_balance=api.balance(ctx),cost=fresh.cost,
   before=clone(before),after=clone(after),set_home=set_home}
  results[job_id]={phase='pending'};return true,'pending',job_id
 end
 function control.result(id)return results[id]and clone(results[id])or{phase='failed',error='unknown_skill_purchase'}end
 function control.tick()
  if not pending or busy or blocked then return end
  local job=pending;pending=nil;busy=true
  hash_cache={};metrics={read_bytes=0,hash_bytes=0,hash_calls=0,hash_reuses=0,stages_ms={}}
  journal_known,journal_bytes=false,nil
  local started=os.clock()
  local journal,mutated,scope_token,scope_started
  local ok,why=pcall(function()
   if api.begin_hash_scope then
    assert(type(api.end_hash_scope)=='function','skill_hash_scope_cleanup_missing')
    scope_token=api.begin_hash_scope();scope_started=true
   end
   assert(same(job.ctx,api.get_context()),'skill_purchase_context_changed')
   assert(timed('fingerprint_before',api.fingerprint,job.slot)==job.before_fp,'skill_native_save_changed')
   assert(api.balance(job.ctx)==job.before_balance,'skill_currency_changed')
   assert(read(JOURNAL)==nil and read(JOURNAL..'.tmp')==nil,'skill_purchase_recovery_pending')
   journal_known=true
   journal={id=job.id,slot=job.slot,world=job.world,before_fp=job.before_fp,before_balance=job.before_balance,cost=job.cost,phase='prepared',files={}}
   timed('prepare_journal',function()
    for _,name in ipairs(file_names(job.ctx))do
     local bytes=read(name);local checksum=hash(bytes)
     journal.files[#journal.files+1]={name=name,before=bytes,before_hash=checksum,after_hash=checksum}
    end
    atomic(JOURNAL,encode(journal))
   end)
   assert(timed('fingerprint_after_backup',api.fingerprint,job.slot)==job.before_fp and api.balance(job.ctx)==job.before_balance,'skill_purchase_changed_during_backup')
   mutated=true;local debit,e=api.set_balance(job.ctx,job.before_balance-job.cost);assert(debit~=false,e or'skill_debit_failed')
   assert(api.balance(job.ctx)==job.before_balance-job.cost,'skill_debit_readback_failed')
   local saved;saved,e=timed('save_native',api.save_native,job.ctx);assert(saved==true,e or'skill_native_save_failed')
   journal.phase='saved';timed('capture_native',capture,journal)
   local fp;fp,e=timed('persist_profile',api.persist,job.ctx);assert(type(fp)=='string',e or'skill_profile_persist_failed')
   timed('capture_profile',capture,journal)
   assert(fp==timed('fingerprint_after_persist',api.fingerprint,job.slot),'skill_saved_fingerprint_changed')
   local chosen;chosen,e=timed('set_skill',job.set_home,job.ctx,job.after);assert(chosen==true,e or'skill_choice_save_failed')
   timed('capture_skill',capture,journal)
   assert(api.balance(job.ctx)==job.before_balance-job.cost,'skill_currency_commit_changed')
   timed('commit_journal',function()journal.phase='committed';atomic(JOURNAL,encode(journal));remove(JOURNAL)end)
  end)
  if ok then results[job.id]={phase='complete',cost=job.cost}
  else
   local failure=tostring(why)
   if journal then
    local restored,restore_error=pcall(function()return timed('rollback',function()
     -- On this live, uninterrupted GT transaction these are observed own writes.
     if mutated then capture(journal)end
     restore(journal,job.ctx)
    end)end)
    if not restored then blocked='skill_purchase_recovery_required:'..tostring(restore_error);failure=failure..'; '..blocked end
   end
   results[job.id]={phase='failed',error=failure};report(failure)
  end
  if scope_started then
   local closed,detail=pcall(api.end_hash_scope,scope_token)
   if closed then metrics.shared_hash=detail
   else
    metrics.hash_scope_cleanup_error=tostring(detail)
    blocked='skill_hash_scope_cleanup_failed';report(blocked..':'..tostring(detail))
   end
  end
  metrics.elapsed_cpu=os.clock()-started;last_metrics=metrics;metrics,hash_cache=nil,nil
  journal_known,journal_bytes=false,nil
  busy=false
 end
 function control.recover(ctx)
  if busy then return true end
  hash_cache={}
  local ok,why=pcall(function()
   local primary,temporary=read(JOURNAL),read(JOURNAL..'.tmp')
   if not primary and not temporary then return end
   local journal
   if primary then journal=decode(primary)end
   if temporary then
    local parsed_ok,parsed=pcall(decode,temporary)
    assert(parsed_ok,'invalid_skill_purchase_tmp:'..tostring(parsed))
    assert(not primary or primary==temporary,'skill_purchase_journal_conflict: main and tmp differ; both retained')
    if not journal then journal=parsed end
   end
   if journal.phase=='committed'then
    for _,f in ipairs(journal.files)do assert(hash(read(f.name))==f.after_hash,'committed_skill_files_changed:'..f.name)end
    remove(JOURNAL);remove(JOURNAL..'.tmp');return
   end
   if ctx then assert(ctx.slot==journal.slot,'pending_skill_purchase_belongs_to_other_colony')end
   restore(journal,ctx)
  end)
  hash_cache=nil
  if not ok then blocked='skill_purchase_recovery_required:'..tostring(why);report(blocked);return nil,blocked end
  blocked=nil;return true
 end
 function control.status()return{pending=pending and pending.id,busy=busy,blocked=blocked,journal=JOURNAL,last_metrics=last_metrics and clone(last_metrics)}end
 return control
end
return M
