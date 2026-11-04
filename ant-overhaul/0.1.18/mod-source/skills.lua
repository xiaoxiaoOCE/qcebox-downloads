-- Custom skill choices, isolated from FColonyData and numerical cultivation.
-- Native-save observation is supplied by main.lua's settled persist path.
local M={}
function M.install(api)
 local fileio=api.fileio or{open=io.open,remove=os.remove,rename=os.rename}
 local native=assert(api.native)
 local store=assert(api.state)
 local control={}
 local state,path,load_error,cache,suspended
 local function clone(t)if type(t)~='table'then return t end local r={};for k,v in pairs(t)do r[k]=clone(v)end;return r end
 local function valid(o)return native.valid_object(o)end
 local function text(v)if type(v)=='string'then return v end;local ok,s=pcall(function()return v:ToString()end);return ok and s or''end
 local function world_id(ctx)
  if not ctx then return nil end
  if type(ctx.world)=='number'or type(ctx.world)=='string'then return tostring(ctx.world)end
  local ok,w=pcall(function()return ctx.world:GetAddress()end);return ok and tostring(w)or nil
 end
 local function identity(ctx)return ctx and ctx.slot and world_id(ctx)and(ctx.slot..':'..world_id(ctx))end
 local function report(why)(api.log or print)('[CustomSkills] '..tostring(why))end
 local function read(p)local f=fileio.open(p,'rb');if not f then return nil end;local b=f:read('*a');f:close();return b end
 local function write(p,b)
  local f,e=fileio.open(p,'wb');if not f then return nil,e end
  local ok,why=f:write(b);if not ok then f:close();return nil,why end
  local flushed,fe=f:flush();local closed,ce=f:close();if not flushed or not closed then return nil,fe or ce end;return true
 end
 local function ensure_store()
  if state then return true end;if load_error then return nil,load_error end
  if api.storage then
   local bytes=api.storage.read()
   if bytes then state,load_error=store.decode(bytes)else state=store.new()end
  else
   local paths=StaticFindObject('/Script/Engine.Default__BlueprintPathsLibrary')
   if not valid(paths)then return nil,'saved_directory_unavailable'end
   local folder=text(paths:ProjectSavedDir()):gsub('\\','/');if folder:sub(-1)~='/'then folder=folder..'/'end
   path=folder..'SaveGames/EAA_CustomSkills_v1.tsv'
   local bytes=read(path);if bytes then state,load_error=store.decode(bytes)else state=store.new()end
  end
  if not state then report(load_error);return nil,load_error end
  return true
 end
 local function save(candidate)
  local bytes,why=store.encode(candidate);if not bytes then return nil,why end
  if api.storage then local ok,e=api.storage.atomic_write(bytes);if ok~=true then return nil,e or'skill_write_failed'end
  else
   local old=read(path)
   local ok,e=write(path..'.tmp',bytes);if not ok then return nil,e end
   if old then
    ok,e=write(path..'.bak',old);if not ok then return nil,e end
    ok,e=fileio.remove(path);if not ok then return nil,e end
   end
   ok,e=fileio.rename(path..'.tmp',path)
   if not ok then if old then write(path,old)end;return nil,e end
  end
  state=candidate;return true
 end
 local function resolve(ctx)
  if suspended then return nil,suspended end
  local key=identity(ctx);if not key then return nil,'skill_context_unavailable'end
  if cache and cache.key==key then return cache end
  if api.is_ready and not api.is_ready(ctx)then return nil,'skill_profile_not_ready'end
  local ok,why=ensure_store();if not ok then return nil,why end
  local fingerprint;ok,fingerprint,why=pcall(api.fingerprint,ctx.slot)
  if not ok then return nil,'skill_profile_not_ready:'..tostring(fingerprint)end
  if not fingerprint then return nil,why or'skill_profile_unavailable'end
  local choices;choices,why=store.lookup(state,ctx.slot,fingerprint)
  if not choices and why~='unknown_skill_fingerprint'then return nil,why end
  cache={key=key,slot=ctx.slot,world=world_id(ctx),anchor=fingerprint,choices=choices or store.empty(),known=choices~=nil}
  return cache
 end
 function control.get_home(ctx)
  local entry,why=resolve(ctx);if not entry then return nil,why end
  return clone(entry.choices)
 end
 function control.set_home(ctx,choices)
  if not ctx or ctx.is_formicarium~=true or ctx.story==true then return nil,'home_skill_selection_required'end
  if api.is_ready and not api.is_ready(ctx)then return nil,'skill_save_not_settled'end
  local normalized,why=store.normalize(choices);if not normalized then return nil,why end
  local entry;entry,why=resolve(ctx);if not entry then return nil,why end
  local readable,actual=pcall(api.fingerprint,ctx.slot);if not readable or actual~=entry.anchor then return nil,'skill_native_save_changed'end
  local candidate;candidate,why=store.capture(state,ctx.slot,entry.anchor,normalized,true)
  if not candidate then return nil,why end
  local ok;ok,why=save(candidate);if not ok then return nil,why end
  entry.choices=clone(normalized);entry.known=true
  if api.on_change then api.on_change(ctx,clone(normalized))end
  return true
 end
 -- main calls this only after a positively observed native save has settled.
 -- Unknown bytes alone never grant a previous colony's choices.
 function control.on_profile_saved(ctx,new_fingerprint,previous_fingerprint)
  if suspended then return nil,suspended end
  -- Story reward/return saves also update the linked home profile. The cache
  -- contains permanent home choices, never the active mission override.
  if not ctx then return true end
  local ok,why=ensure_store();if not ok then return nil,why end
  local choices
  if cache and cache.key==identity(ctx)then
   if cache.anchor==new_fingerprint then return true end
   if previous_fingerprint and cache.anchor~=previous_fingerprint then return nil,'skill_save_anchor_mismatch'end
   choices=cache.choices
   if not cache.known then cache.anchor=new_fingerprint;return true end
  elseif previous_fingerprint then
   choices,why=store.lookup(state,ctx.slot,previous_fingerprint)
   if not choices then return why=='unknown_skill_fingerprint'and true or nil,why end
  else return true end
  local candidate;candidate,why=store.capture(state,ctx.slot,new_fingerprint,choices,false)
  if not candidate then return nil,why end
  ok,why=save(candidate);if not ok then return nil,why end
  cache={key=identity(ctx),slot=ctx.slot,world=world_id(ctx),anchor=new_fingerprint,choices=clone(choices),known=true}
  return true
 end
 function control.get_choices(creature,species)
  species=species or'TrapjawAnt'
  if not(store.supports and store.supports(species)or species=='TrapjawAnt')then return {}end
  if suspended then return {}end
  local ctx=api.get_context and api.get_context();if not ctx then return {}end
  if creature and(not valid(creature)or not native.is_owned(creature,ctx.gs or ctx.game_state))then return {}end
  local choices
  if api.get_mission_choices then choices=api.get_mission_choices(ctx)end
  if choices==nil then
   -- Unknown/legacy mission loads must not silently borrow the latest home
   -- loadout. A new mission gets its frozen choices only after roster commit.
   if not ctx.is_formicarium then return {}end
   choices=control.get_home(ctx)
  end
  return choices and store.flat(choices,species)or{}
 end
 function control.quote_home(ctx,id,side,value)
  if not(store.supports and store.supports(id)or id=='TrapjawAnt')or(side~='left'and side~='right')then return {can_purchase=false,reason='invalid_custom_skill'}end
  local before,why=control.get_home(ctx);if not before then return{can_purchase=false,reason=why}end
  local after=clone(before);after[id]=after[id]or{left='none',right='none'};after[id][side]=value
  local normalized;normalized,why=store.normalize(after);if not normalized then return{can_purchase=false,reason=why}end
  local owned=before[id]and before[id][side]==value or false
  if owned then return{cost=0,can_purchase=true,owned=true}end
  if api.quote_home then return api.quote_home(ctx,id,side,value,clone(before),normalized)end
  return{can_purchase=false,owned=false,reason='skill_price_not_configured'}
 end
 function control.purchase_home(ctx,id,side,value)
  local quote=control.quote_home(ctx,id,side,value)
  if not quote.can_purchase then return nil,quote.reason or'skill_purchase_unavailable'end
  if quote.owned then return true end
  local before,why=control.get_home(ctx);if not before then return nil,why end
  local after=clone(before);after[id]=after[id]or{left='none',right='none'};after[id][side]=value
  if api.purchase_home then return api.purchase_home(ctx,id,side,value,before,after,quote,control.set_home)end
  if quote.cost~=0 then return nil,'skill_purchase_transaction_unavailable'end
  return control.set_home(ctx,after)
 end
 function control.purchase_result(id)
  if api.purchase_result then return api.purchase_result(id)end
  return{phase='failed',error='skill_purchase_transaction_unavailable'}
 end
 function control.status()return{path=path,error=load_error or suspended,suspended=suspended,profile=cache and clone(cache)}end
 function control.on_profile_loaded(ctx,fingerprint)
  if suspended then return nil,suspended end
  local ok,why=ensure_store();if not ok then return nil,why end
  local choices;choices,why=store.lookup(state,ctx.slot,fingerprint)
  if not choices and why~='unknown_skill_fingerprint'then return nil,why end
  cache={key=identity(ctx),slot=ctx.slot,world=world_id(ctx),anchor=fingerprint,choices=choices or store.empty(),known=choices~=nil}
  return true
 end
 function control.invalidate()cache=nil end
 function control.suspend(reason)suspended=tostring(reason or'custom_skills_suspended');return true end
 function control.reload()
  state,path,load_error,cache,suspended=nil,nil,nil,nil,nil
  local ok,why=ensure_store();if not ok then suspended=tostring(why)end
  return ok,why
 end
 control.resume=control.reload
 return control
end
return M
