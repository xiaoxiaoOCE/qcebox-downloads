-- Story roster coordinator. All engine work stays on the game thread.
-- The native mission writes its own saves; this module only writes its exact-
-- fingerprint sidecar, never native save bytes or the attribute-points ledger.
local M = {}

function M.install(api)
 local native,catalog,store,view,runtime,sha = api.native,api.catalog,api.state,api.ui,api.runtime,api.sha256
 local policy=assert(store.policy_from_catalog(catalog))
 local control={last_error=nil}
 local requests,sequence,pending,active={},0,nil,nil
 local load_receipt
 local challenge
 local saved_dir,ledger_path,state,load_error=nil,nil,nil,nil
 local hooks,reported={},{}
 local enabled=true
 local ensure_hooks
 local next_hooks,next_maintenance=0,0
 local clock=api.clock or os.clock
 local dlc_cache
 local function valid(o)return native.valid_object(o)end
 local function unbox(v)local ok,x=pcall(function()return v:get()end);return ok and x or v end
 local function text(v)
  if type(v)=='string'then return v end
  if v==nil then return '' end
  local ok,s=pcall(function()return v:ToString()end);return ok and s or ''
 end
 local function get(o,k)
  if not valid(o)then return nil end
  local ok,v=pcall(function()return o[k]end);return ok and v or nil
 end
 local function id(o)return valid(o)and tostring(o:GetAddress())or nil end
 local function same(a,b)local x=id(a);return x~=nil and x==id(b)end
 local function clone(t)
  if type(t)~='table'then return t end
  local c={};for k,v in pairs(t)do c[k]=clone(v)end;return c
 end
 -- This is the original game's DLC check, including its AssetRegistry label
 -- lookup. Cache a completed boolean per world; missing late-loaded UI classes
 -- retry at most once a second. Never infer entitlement from creature classes.
 local function dlc_availability(world)
  local world_key=id(world)
  if not dlc_cache or dlc_cache.world~=world_key then
   dlc_cache={world=world_key,known=false,next_probe=0,probes=0,value={exploding=false}}
  end
  if dlc_cache.known or clock()<dlc_cache.next_probe then return clone(dlc_cache.value)end
  dlc_cache.next_probe=clock()+1
  for _,path in ipairs({'/Game/UI/InGame/TechTree/SpeciesEntry.Default__SpeciesEntry_C',
   '/Game/UI/Wiki/CustomColonySetup.Default__CustomColonySetup_C'})do
   local receiver=StaticFindObject(path)
   if valid(receiver)then
    local out={}
    dlc_cache.probes=dlc_cache.probes+1
    local ok=pcall(function()receiver:DoWeHaveExplodingDLC(out)end)
    if ok and type(out.Yes)=='boolean'then
     dlc_cache.value.exploding=out.Yes
     dlc_cache.known=true
     break
    end
   end
  end
  return clone(dlc_cache.value)
 end
 local function report(message)
  control.last_error=tostring(message)
  if not reported[control.last_error]then
   reported[control.last_error]=true
   (api.log or print)('[StoryRoster] '..control.last_error)
  end
 end
 local home=assert(api.home).install(native,catalog,report)
 local function safe_name(n)return type(n)=='string'and #n>0 and #n<=96 and n:match('^[A-Za-z0-9_-]+$')end
 local function map_name(value)
  local s=text(value):gsub('\\','/'):match('^[^?]*')or ''
  return (s:match('([^/]+)$')or s):lower()
 end
 local function read(path)
  local f=io.open(path,'rb');if not f then return nil end
  local bytes=f:read('*a');f:close();return bytes
 end
 local function write(path,bytes)
  local f,e=io.open(path,'wb');if not f then return nil,e end
  local ok,why=f:write(bytes);if not ok then f:close();return nil,why end
  local flushed,fe=f:flush();local closed,ce=f:close()
  if not flushed or not closed then return nil,fe or ce end
  return true
 end
 local function atomic_write(bytes)
  local old=read(ledger_path)
  local ok,e=write(ledger_path..'.tmp',bytes);if not ok then return nil,e end
  if old then
   ok,e=write(ledger_path..'.bak',old);if not ok then return nil,e end
   ok,e=os.remove(ledger_path);if not ok then return nil,e end
  end
  ok,e=os.rename(ledger_path..'.tmp',ledger_path)
  if not ok and old then write(ledger_path,old)end
  return ok,e
 end
 local function ensure_store()
  if state then return true end
  if load_error then return nil,load_error end
  local paths=StaticFindObject('/Script/Engine.Default__BlueprintPathsLibrary')
  if not valid(paths)then return nil,'saved_directory_unavailable' end
  saved_dir=text(paths:ProjectSavedDir()):gsub('\\','/')
  if saved_dir:sub(-1)~='/'then saved_dir=saved_dir..'/'end
  ledger_path=saved_dir..'SaveGames/EAA_StoryRoster_v1.tsv'
  local bytes=read(ledger_path)
  if bytes then
   state,load_error=store.decode(bytes,policy)
   if not state then report('选兵记录无法读取：'..tostring(load_error));return nil,load_error end
  else state=store.new()end
  return true
 end
 local function file_hash(slot)
  if not safe_name(slot)or not saved_dir then return nil end
  local bytes=read(saved_dir..'SaveGames/'..slot..'.sav')
  if not bytes or #bytes<16 then return nil end
  if api.validate_native_save and not api.validate_native_save(bytes)then return nil end
  return sha(bytes)
 end
 local function live_context()
  local gs,gm=FindFirstOf('EotUGameState'),FindFirstOf('EotUGameMode')
  if not valid(gs)or not valid(gm)then return nil end
  local world=gs:GetWorld()
  if not valid(world)or not same(gm:GetWorld(),world)then return nil end
  local pc=native.get_local_controller(gs);if not valid(pc)then return nil end
  -- Use the game's authoritative colony registry instead of a world-wide scan.
  local colony=tonumber(unbox(pc:GetColonyID()))
  if not colony or colony<0 or colony%1~=0 then return nil end
  local grid=unbox(gs:GetTileGridByColonyID(colony))
  if not valid(grid)or not native.is_owned(grid,gs)then return nil end
  local setup=get(gm,'LevelSetupSave')
  local slot=text(get(gm,'FormicariumName'))
  if slot==''and valid(setup)then slot=text(setup.LinkedFormicSave)end
  if not safe_name(slot)then return nil end
  local formic=FindFirstOf('EotUFormicariumGameMode')
  local is_formic=valid(formic)and same(formic:GetWorld(),world)
  local game_type=tonumber(get(gm,'GameType'))
  if not is_formic and game_type~=0 and game_type~=1 then return nil end
  local mission=''
  local methods=get(gm,'LevelMethods')
  if valid(methods)then mission=text(get(methods,'LevelName'))end
  local ctx={gs=gs,gm=gm,pc=pc,grid=grid,world=world,game_state=gs,game_mode=gm,controller=pc,
   slot=slot,missionKey=mission,setup=setup,is_formicarium=is_formic,
   story=not is_formic or(active and active.challenge and id(active.ctx.world)==id(world))or false,
   dlc_available=dlc_availability(world)}
  ctx.after_skill_refresh=function()
   if api.sync_attributes then api.sync_attributes()end
  end
  ctx.capture_profile=function()
   return api.points_signature and api.points_signature()or 'unavailable'
  end
  return ctx
 end
 local function same_context(ctx,other)
  return ctx and other and ctx.slot==other.slot and same(ctx.world,other.world)
   and same(ctx.grid,other.grid)and same(ctx.gs,other.gs)and same(ctx.pc,other.pc)
 end
 local function story_values(ctx)
  local source=ctx.grid.ColonySetup
  local source_ng=tonumber(ctx.gm.NewGamePlusLevel)
  if not ctx.is_formicarium then
   local lib=StaticFindObject('/Script/Engine.Default__GameplayStatics')
   local saved=valid(lib)and lib:LoadGameFromSlot(ctx.slot,0)or nil
   local class=StaticFindObject('/Script/EotU.FormicSave')
   if not valid(saved)or not valid(class)or not saved:IsA(class)then return nil,'campaign_profile_unavailable' end
   source=saved.ColonySetup;source_ng=tonumber(saved.NewGamePlusLevel)
  end
  local values={}
  for _,row in ipairs(catalog.entries)do
   values[row.flag]=source[row.flag]
   if row.variant_field then values[row.variant_field]=source[row.variant_field]end
   if row.upgrade_field then values[row.upgrade_field]=tonumber(source[row.upgrade_field])end
  end
  for field in pairs(catalog.skill_fields)do values[field]=source[field]end
  for _,group in ipairs(api.groups.list)do for _,field in ipairs(group.fields)do values[field]=tonumber(source[field])end end
  if ctx.is_formicarium then
   local restored,why=home.baseline(ctx,values)
   if not restored then return nil,why end
  end
  return values,source_ng
 end
 local function request_key(parent,kind,ctx)
  return id(parent)..':'..kind..':'..ctx.slot..':'..ctx.missionKey..':'..id(ctx.world)
 end
 local function get_context(parent,kind)
  if not enabled or not valid(parent)then return nil end
  local ctx=live_context();if not ctx then return nil end
  if kind=='start'then
   if not ctx.is_formicarium then return nil end
   local level_type=tonumber(parent.LevelType)
   -- Type 3 enters New Game Plus; type 4 moves the formicarium/settles story.
   if level_type~=0 and level_type~=1 and level_type~=2 and level_type~=5 then return nil end
   ctx.missionKey=text(parent.StoredLevelKey)
  elseif kind=='restart'then
   if ctx.is_formicarium or ctx.missionKey==''then return nil end
  else return nil end
  if ctx.missionKey==''then return nil end
  local ok=ensure_store();if not ok then return nil end
  local key=request_key(parent,kind,ctx)
  local old=requests[key]
  if old and not old.consumed and not old.cancelled then return old end
  local values,source_ng=story_values(ctx)
  if not values then report(source_ng);return nil end
  sequence=sequence+1
  local request={token=sequence,world=ctx.world,controller=ctx.pc,source=parent,slot=ctx.slot,
   missionKey=ctx.missionKey,kind=kind,story_colony=values,source_ng=source_ng,allowedFlags={},_ctx=ctx,
   dlc_available=clone(ctx.dlc_available)}
  if kind=='start'and tonumber(parent.LevelType)==0 then
   request.allow_same_world=true;request.gate_stage=tonumber(parent.GateStage)
  end
  requests[key]=request
  return request
 end
 local function validate_request(request)
  if type(request)~='table'or request.cancelled or request.consumed or not valid(request.source)then return false end
  local now=live_context()
  if not same_context(request._ctx,now)then return false end
  if request.kind=='start'and text(request.source.StoredLevelKey)~=request.missionKey then return false end
  return true
 end
 local function cancel_request(request,reason)
  if type(request)=='table'then
   request.cancelled=true
   if pending and pending.token==request.token then pending=nil end
  end
 end
 local function submit_flags(request,payload)
  if not validate_request(request)then return nil,'关卡已改变，请重新选择。' end
  ensure_hooks()
  local selection,why=store.validate_selection(payload,policy)
  if not selection then return nil,why end
  local wanted=clone(request.story_colony)
  for flag,value in pairs(selection.skillOverrides)do wanted[flag]=value end
  for _,row in ipairs(catalog.skills)do
   for _,pair in pairs(row.skill_pairs)do
    if(selection.skillOverrides[pair[1]]~=nil or selection.skillOverrides[pair[2]]~=nil)
     and wanted[pair[1]]and wanted[pair[2]]then return nil,'同一侧只能选择一个技能。' end
   end
  end
  -- Home production is not a mission loadout. Withdraw its flags before the
  -- native launch can copy ColonySetup; cancellation resumes home maintenance.
  if request.kind=='start'and not request.allow_same_world then
   local restored,why=home.suspend(request._ctx)
   if not restored then return nil,'养殖箱生产列表暂未能安全切换：'..tostring(why)end
  end
  request.consumed=true
  local maps={}
  if request.kind=='start'then
   for _,key in ipairs({'NormalLevelAsset','HardLevelAsset'})do
    local n=map_name(get(request.source,key));if n~=''then maps[n]=true end
   end
  else maps[map_name(request.world:GetFName())]=true end
  pending={token=request.token,source_world=id(request.world),slot=request.slot,missionKey=request.missionKey,
   selection=selection,kind=request.kind,source_values=clone(request.story_colony),maps=maps,
   source_context=request._ctx,source_ng=request.source_ng,committed=false,
   same_world=request.allow_same_world==true,gate_stage=request.gate_stage}
  return true
 end
 local function runtime_selection(selection)
  local ids={};for value in pairs(selection.selectedIds)do ids[#ids+1]=value end;table.sort(ids)
  return {selectedIds=ids,skillOverrides=clone(selection.skillOverrides),variantOverrides=clone(selection.variantOverrides or{})}
 end
 local function resolved_selection(chosen,ctx)
  local result=clone(chosen.selection)
  result.variantOverrides=result.variantOverrides or{}
  for selected in pairs(result.selectedIds)do
   local row=catalog.by_id[selected]
   if row.variant_field then
    local field=row.variant_field
    if not chosen.same_world and ctx.grid.ColonySetup[row.flag]then result.variantOverrides[field]=ctx.grid.ColonySetup[field]
    elseif result.variantOverrides[field]==nil then result.variantOverrides[field]=chosen.source_values[field]end
   end
   for _,pair in pairs(row.skill_pairs or{})do
    local left=result.skillOverrides[pair[1]]
    local right=result.skillOverrides[pair[2]]
    if left==nil then left=chosen.source_values[pair[1]]end
    if right==nil then right=chosen.source_values[pair[2]]end
    if type(left)~='boolean'or type(right)~='boolean'or(left and right)then return nil,'invalid_inherited_skill_pair' end
    result.skillOverrides[pair[1]],result.skillOverrides[pair[2]]=left,right
   end
  end
  return result
 end
 local function apply_selection(ctx,selection,origin,values,source_ng)
  if origin=='challenge'then
   local hooks=challenge.ensure_hooks(ctx)
   if not hooks.ready then return nil,hooks.reason end
  end
  if not values then values,source_ng=story_values(ctx)end
  if not values then return nil,source_ng end
  local selected=runtime_selection(selection)
  local points,why
  if not ctx.is_formicarium then
   points,why=runtime.inherit_points(ctx,selected,values,source_ng)
   if not points then return nil,why end
  end
  local receipt;receipt,why=runtime.apply(ctx,selected)
  if not receipt then if points then runtime.restore_points(ctx,points)end;return nil,why end
  active={ctx=ctx,selection=clone(selection),receipt=receipt,points=points,origin=origin,challenge=origin=='challenge'}
  if api.sync_attributes then api.sync_attributes()end
  return true
 end
 local function restore_active(ctx)
  if not active or not same_context(active.ctx,ctx)then return true end
  local ok,why
  if not active.roster_restored then
   ok,why=runtime.restore(ctx,active.receipt)
   if not ok then return nil,why end
   active.roster_restored=true
  end
  if active.points and not active.points_restored then
   ok,why=runtime.restore_points(ctx,active.points)
   if not ok then return nil,why end
   active.points_restored=true
  end
  return true
 end
 local function save_receipt(entry)
  if not active or not entry or not safe_name(entry.slot)then return end
  local slot=entry.slot
  local now=live_context()
  if active~=entry.active or not same_context(entry.ctx,now)or not same_context(active.ctx,now)or now.is_formicarium then return end
  local hash=file_hash(slot);if not hash then report('原生保存尚不可读取，未绑定选兵记录。');return end
  if hash==entry.before then return end
  local record={kind='save',native_slot=slot,fingerprint=hash,campaign_slot=now.slot,mission_key=now.missionKey,
   selectedIds=clone(active.selection.selectedIds),skillOverrides=clone(active.selection.skillOverrides),
   variantOverrides=clone(active.selection.variantOverrides or{})}
  local next_state,why=store.capture(state,record,policy)
  if not next_state then report('选兵保存绑定失败：'..tostring(why));return end
  local ok,err=store.save(next_state,{atomic_write=atomic_write},policy)
  if not ok then report('选兵记录写入失败：'..tostring(err));return end
  state=next_state
 end
 local function hook(name,path,pre,post)
  if hooks[name]or not valid(StaticFindObject(path))then return end
  local ok,a,b=pcall(RegisterHook,path,pre,post)
  if ok then hooks[name]={path,a,b}else report(name..': '..tostring(a))end
 end
 ensure_hooks=function()
  local gate_path='/Game/UI/InGame/TugOfWarWidgets.TugOfWarWidgets_C:LaunchLevelEvent'
  if not hooks.gate_start and valid(StaticFindObject(gate_path))then
   local ok,a,b=pcall(RegisterHook,gate_path,function(receiver,gate)
    if not pending or not pending.same_world then return end
    local hud=unbox(receiver)
    if valid(hud)and id(hud:GetWorld())==pending.source_world and tonumber(unbox(gate))==pending.gate_stage then
     pending.started=true
    end
   end)
   if ok then hooks.gate_start={gate_path,a,b}else report(a)end
  end
  local levels={}
  hook('save_level','/Script/EotU.EotUGameMode:SaveLevel',function(receiver,slot)
   local ctx=live_context();local allowed=active and same_context(active.ctx,ctx)and same(unbox(receiver),ctx.gm)
   local name=text(unbox(slot))
   levels[#levels+1]=allowed and safe_name(name)and{slot=name,before=file_hash(name),ctx=ctx,active=active}or false
  end,function()
   local slot=table.remove(levels);if slot then save_receipt(slot)end
  end)
  hook('start_commit','/Script/EotU.EotUGameMode:SetupLoadingScreen',function(receiver,map)
   if not pending then return end
   local now=live_context()
   if not now or not same_context(pending.source_context,now)or not same(unbox(receiver),now.gm)then return end
   local target=map_name(unbox(map))
   if pending.maps[target]then
    pending.committed=true;pending.setup_hash=file_hash('LevelSetup')
   else pending=nil end
  end,function()end)
  -- Native RestartGame reuses LevelSetup and bypasses SetupLoadingScreen.
  -- Commit only after the native confirmation has reached the current GM.
  hook('restart_commit','/Script/Engine.GameMode:RestartGame',function(receiver)
   if not pending or pending.kind~='restart' then return end
   local now=live_context()
   if not now or not same_context(pending.source_context,now)or not same(unbox(receiver),now.gm)then return end
   pending.committed=true;pending.setup_hash=file_hash('LevelSetup')
  end,function()end)
  hook('restore_level','/Script/EotU.EotUGameMode:RestoreLevelSave',function()end,function(receiver)
   if load_receipt and id(unbox(receiver))==load_receipt.mode then load_receipt.restored=true
   elseif active and same(unbox(receiver),active.ctx.gm)then
    -- A restore without an observed source may not reuse the previous choices.
    local now=live_context()
    if now then local ok,why=restore_active(now);if not ok then report(why)end end
    active=nil;load_receipt={mode=id(unbox(receiver)),world=now and id(now.world),unknown=true}
   end
  end)
  hook('load_level','/Script/EotU.EotUGameMode:LoadLevel',function(receiver,slot)
   local now=live_context()
   if not now or now.is_formicarium or not same(unbox(receiver),now.gm)then return end
   if not ensure_store()then return end
   local name=text(unbox(slot));local hash=file_hash(name)
   local record=hash and state and store.lookup(state,{kind='save',native_slot=name,fingerprint=hash,
    campaign_slot=now.slot,mission_key=now.missionKey},policy)or nil
   if active then
    local ok,why=restore_active(now)
    if not ok then
     report(why)
     load_receipt={mode=id(now.gm),world=id(now.world),slot=name,fingerprint=hash,record=record,cleanup=active}
     pending=nil;return
    end
   end
   active,pending=nil,nil
   load_receipt={mode=id(now.gm),world=id(now.world),slot=name,fingerprint=hash,record=record}
   if record then
    local ok,why=apply_selection(now,{selectedIds=record.selectedIds,skillOverrides=record.skillOverrides,
     variantOverrides=record.variantOverrides or{}},'load_before_units')
    if not ok then report('读档选兵预恢复失败：'..tostring(why))end
   end
  end,function(receiver)
   if load_receipt and id(unbox(receiver))==load_receipt.mode then
    load_receipt.restored=true
    if active then active.receipt.menu_pending=true end
   end
  end)
 end
 control.ui=view.install({valid_object=valid,catalog=catalog,get_context=get_context,
  validate_request=validate_request,submit_flags=submit_flags,cancel_request=cancel_request,error=report})
 challenge=api.challenge.install({valid=valid,get_active=function()return active end,get_context=live_context,
  log=report,finish=function(ctx)
   local ok,why=restore_active(ctx);if not ok then return nil,why end
   active=nil;return true
  end})
 control.before_formic_save=function(receiver,skip)
  local ctx=live_context()
  if not ctx or not ctx.is_formicarium or not same(unbox(receiver),ctx.gm)then return nil end
  local mask={}
  if active and active.challenge and same_context(active.ctx,ctx)then
   local why;mask.challenge,why=challenge.before_save(receiver,skip)
   if why then return nil,why end
  end
  local why;mask.home,why=home.before_save(ctx,skip)
  if why then
   if mask.challenge then challenge.after_save(mask.challenge)end
   return nil,why
  end
  return (mask.home or mask.challenge)and mask or nil
 end
 control.after_formic_save=function(mask)
  if not mask then return {noop=true}end
  local errors={}
  if mask.home then local ok,why=home.after_save(mask.home);if not ok then errors[#errors+1]=tostring(why)end end
  if mask.challenge then local ok,why=challenge.after_save(mask.challenge);if not ok then errors[#errors+1]=tostring(why)end end
  if #errors>0 then return nil,table.concat(errors,'; ')end
  return {restored=true}
 end
 control.challenge_status=challenge.status
 function control.tick()
  if not enabled then return end
  local now=clock()
  if now>=next_hooks then next_hooks=now+1;ensure_hooks()end
  challenge.tick()
  control.ui.tick()
  -- Input and end-of-challenge queues above remain responsive. A settled
  -- battle needs only an occasional world/cap check, not global discovery
  -- and receipt validation every five rendered frames.
  local urgent=(pending and(pending.committed or pending.started))or load_receipt
   or(active and active.receipt.menu_pending)
  if not urgent and now<next_maintenance then return end
  next_maintenance=now+0.5
  local ctx=live_context()
  if not ctx then
   local menu_pc=FindFirstOf('MainMenuPlayerController_C')
   if pending and valid(menu_pc)and valid(menu_pc:GetWorld())and id(menu_pc:GetWorld())~=pending.source_world then pending=nil end
   if pending and not valid(pending.source_context.world)and not pending.committed then pending=nil end
   return
  end
  if load_receipt and((load_receipt.world and load_receipt.world~=id(ctx.world))or load_receipt.mode~=id(ctx.gm))then load_receipt=nil end
  if active and not same_context(active.ctx,ctx)then active=nil end
  if load_receipt and load_receipt.cleanup then
   if not same_context(load_receipt.cleanup.ctx,ctx)then active=nil;load_receipt=nil
   else
    local ok,why=restore_active(ctx)
    if not ok then report(why);return end
    active=nil;load_receipt.cleanup=nil
   end
  end
  if ctx.is_formicarium then
   if pending and pending.source_world~=id(ctx.world)then pending=nil end
   if not(pending and not pending.same_world)
    and (not api.is_home_ready or api.is_home_ready(ctx))
    and (not api.is_save_settled or api.is_save_settled())then
    local ok,why=home.tick(ctx)
    if not ok then report('养殖箱额外兵种：'..tostring(why))end
   end
   if pending and pending.same_world and pending.started and pending.slot==ctx.slot and ctx.gm.InMission then
    if api.is_save_settled and not api.is_save_settled()then return end
    ctx.story=true
    local chosen=pending
    local selected,why=resolved_selection(chosen,ctx)
    local ok
    if selected then ok,why=apply_selection(ctx,selected,'challenge',chosen.source_values,chosen.source_ng)end
    if ok then pending=nil else report('挑战选兵尚未生效：'..tostring(why))end
   end
   if active and active.challenge and same_context(active.ctx,ctx)then
    ctx.story=true
    if active.receipt.menu_pending then runtime.finalize(ctx,active.receipt)end
    if tonumber(ctx.gs:GetPopCapByID(ctx.grid.ColonyID))~=0 then ctx.gs:SetPopCapByID(ctx.grid.ColonyID,0)end
   end
   return
  end
  if not ensure_store()then return end
  if pending and pending.source_world~=id(ctx.world)and(not pending.committed or pending.slot~=ctx.slot
   or(ctx.missionKey~=''and pending.missionKey~=ctx.missionKey))then pending=nil end
  if pending and pending.committed and pending.slot==ctx.slot and pending.missionKey==ctx.missionKey and pending.source_world~=id(ctx.world)then
   if not valid(ctx.setup)then return end
   local load_slot=text(ctx.setup.SaveGameToLoad)
   if not pending.setup_hash or file_hash('LevelSetup')~=pending.setup_hash or(load_slot~=''and load_slot:lower()~='none')then
    pending=nil;report('本次开局记录与实际载入不符，未把临时选择套用到存档。');return
   end
   local chosen=pending
   local selected,why=resolved_selection(chosen,ctx)
   local ok
   if selected then ok,why=apply_selection(ctx,selected,'new_mission',chosen.source_values,chosen.source_ng)end
   if ok then pending=nil else report('本关选兵尚未生效：'..tostring(why))end
  elseif not active and load_receipt then
   if load_receipt.restored and load_receipt.record and load_receipt.record.campaign_slot==ctx.slot
    and load_receipt.record.mission_key==ctx.missionKey and file_hash(load_receipt.slot)==load_receipt.fingerprint then
    local r=load_receipt.record
    local ok,why=apply_selection(ctx,{selectedIds=r.selectedIds,skillOverrides=r.skillOverrides,
     variantOverrides=r.variantOverrides or{}},'observed_load')
    if ok then load_receipt=nil else report(why)end
   end
  end
  if active and same_context(active.ctx,ctx)then
   if active.receipt.menu_pending then runtime.finalize(ctx,active.receipt)end
   if tonumber(ctx.gs:GetPopCapByID(ctx.grid.ColonyID))~=0 then ctx.gs:SetPopCapByID(ctx.grid.ColonyID,0)end
  end
 end
 function control.status()
  return {pending=pending and clone(pending),active=active and {slot=active.ctx.slot,missionKey=active.ctx.missionKey,
   origin=active.origin,selection=clone(active.selection)},home=home.status(),error=control.last_error}
 end
 function control.stop()
  control.ui.stop();enabled=false
  if active then
   local now=live_context()
   if same_context(active.ctx,now)then local ok,why=restore_active(now);if not ok then report(why);return nil,why end end
  end
  active,pending=nil,nil
  local restored,why=home.stop(live_context())
  if not restored then report(why);return nil,why end
  if challenge.stop then challenge.stop()end
  for _,h in pairs(hooks)do pcall(UnregisterHook,h[1],h[2],h[3])end
  return true
 end
 control.get_context=get_context
 control.get_live_context=live_context
 control.dlc_status=function()
  return dlc_cache and {world=dlc_cache.world,known=dlc_cache.known,probes=dlc_cache.probes,
   available=clone(dlc_cache.value)}or{known=false,probes=0,available={exploding=false}}
 end
 control.submit_flags=submit_flags
 ensure_hooks()
 return control
end
return M
