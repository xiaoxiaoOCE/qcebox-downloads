-- Formicarium-only supplemental chambers. No timers, hooks, unit scans or I/O.
-- Permissions are a live overlay: native saves retain the original unlocks.
local M={ids={"LeafcutterSuperMajor","SlaveMaker","TrapjawAnt","ArmyAnt","ArmyAntMajor",
 "BigHeadedMajor","BigHeadedSuperSoldier","LittleBlackAnt",
 "DriverAntSoldier","DriverAntLargeSoldier","StinkAnt"}}
M.dlc_ids={"ExplodingAnt","ExplodingAntMajorSoldier","ExplodingTermite","ExplodingTermiteSoldier"}
local function unbox(value)
 local ok,out=pcall(function()return value:get()end)
 if ok and out~=nil then return out end
 return value
end
local function copy(t)local r={};for k,v in pairs(t)do r[k]=type(v)=='table'and copy(v)or v end;return r end
local function keys(t)local r={};for k in pairs(t)do r[#r+1]=k end;table.sort(r);return r end

function M.install(native,catalog,log)
 assert(type(native)=='table'and type(catalog)=='table','home dependencies required')
 local fields={}
 local candidates=copy(M.ids)
 for _,name in ipairs(M.dlc_ids)do candidates[#candidates+1]=name end
 for _,name in ipairs(candidates)do
  local row=assert(catalog.by_id[name],'missing home chamber '..name)
  assert(type(row.flag)=='string'and not fields[row.flag],'invalid home chamber flag')
  fields[row.flag]=name
 end
 local control,active,stopped={last_error=nil},nil,false
 local reported={}
 local function valid(o)return native.valid_object(o)==true end
 local function address(o)
  if not valid(o)then return nil end
  local v=o:GetAddress();return v~=nil and tostring(v)or nil
 end
 local function failure(err)
  control.last_error=tostring(err)
  if not reported[control.last_error]then reported[control.last_error]=true;if log then pcall(log,'[FormicariumRoster] '..control.last_error)end end
  return nil,control.last_error
 end
 local function identity(ctx)
  if type(ctx)~='table'or ctx.is_formicarium~=true then error('home_formicarium_required')end
  if type(ctx.slot)~='string'or ctx.slot==''then error('home_slot_required')end
  local out={slot=ctx.slot,world=address(ctx.world),names={}}
  if not out.world then error('home_world_invalid')end
  for _,field in ipairs({'gs','gm','pc','grid'})do
   out[field]=address(ctx[field]);if not out[field]then error('home_invalid_'..field)end
   if tostring(native.world_id(ctx[field]))~=out.world then error('home_world_mismatch_'..field)end
   out.names[field]=ctx[field]:GetFullName()
   if type(out.names[field])~='string'or out.names[field]==''then error('home_name_invalid_'..field)end
  end
  if address(native.get_local_controller(ctx.gs))~=out.pc then error('home_controller_changed')end
  local colony=tonumber(unbox(ctx.pc:GetColonyID()))
  if not colony or colony~=colony or colony%1~=0 or colony<0 or colony>2147483647 then error('home_colony_invalid')end
  if tonumber(ctx.grid.ColonyID)~=colony or not native.is_owned(ctx.grid,ctx.gs)then error('home_grid_not_owned')end
  if address(unbox(ctx.gs:GetTileGridByColonyID(colony)))~=out.grid then error('home_grid_replaced')end
  if tonumber(ctx.grid.ColonySetup.QueenSpecies)~=0 then error('home_genethief_required')end
  out.colony=colony
  out.key=table.concat({out.slot,out.world,out.gs,out.gm,out.pc,out.grid,tostring(colony),
   out.names.gs,out.names.gm,out.names.pc,out.names.grid},':')
  return out
 end
 local function matching(ctx,wanted)
  local ok,current=pcall(identity,ctx)
  return ok and current.key==wanted.key
 end
 local function read(ctx,field)
  local value=ctx.grid.ColonySetup[field]
  if type(value)~='boolean'then error('home_flag_unreadable:'..field)end
  return value
 end
 local function write(ctx,field,value)
  ctx.grid.ColonySetup[field]=value
  if read(ctx,field)~=value then error('home_flag_readback_failed:'..field)end
 end
 local function current(ctx)
  local ok,wanted=pcall(identity,ctx)
  if not ok then return nil,tostring(wanted)end
  if active and active.identity.key~=wanted.key then active.status='expired';active=nil end
  return wanted
 end
 local function menu(ctx,receipt)
  local owner=ctx.pc:GetHUD()
  local hud=valid(owner)and owner.TugOfWarWidgetInstance or nil
  if not valid(hud)then receipt.menu_pending=true;return false end
  if tostring(native.world_id(hud))~=receipt.identity.world then error('home_hud_world_mismatch')end
  local hud_id=address(hud)
  if not receipt.menu_pending and receipt.hud==hud_id then return false end
  hud:SetupBuildMenuButtons()
  receipt.hud=hud_id;receipt.menu_pending=false;receipt.menu_refreshes=receipt.menu_refreshes+1
  return true
 end
 local function rollback(ctx,wanted,changes,target,expected)
  if not matching(ctx,wanted)then return false end
  local ok=true
  for _,field in ipairs(keys(changes))do
   local change=changes[field]
   if change.attempted then
    local restored=pcall(function()if read(ctx,field)==change[expected]then write(ctx,field,change[target])end end)
    ok=ok and restored
   end
  end
  return ok
 end
 function control.tick(ctx)
  if stopped then return nil,'home_stopped'end
  local wanted,why=current(ctx);if not wanted then return failure(why)end
  if active and #active.masks>0 then
   local mask=active.masks[#active.masks]
   if mask.recovery_pending then
    local restored,reason=control.after_save(mask);if not restored then return nil,reason end
   end
   if #active.masks>0 then return {saving=true,changed=0,menu_refreshed=false}end
  end
  local receipt=active or {ctx=ctx,identity=wanted,changes={},masks={},status='active',menu_pending=true,menu_refreshes=0}
  local delta,available={},{ }
  local ok,err=pcall(function()
   for _,field in ipairs(keys(fields))do
    local name=fields[field]
    if catalog.is_selectable(name,ctx.dlc_available) then
     available[#available+1]=name
     if read(ctx,field)==false then delta[field]={before=false,after=true}end
    elseif receipt.changes[field] and read(ctx,field)==receipt.changes[field].after then
     -- A lost native DLC allowance withdraws only our own overlay. Never
     -- revoke an original permission or remove an existing chamber/creature.
     delta[field]={before=receipt.changes[field].after,after=receipt.changes[field].before}
    end
   end
   if not matching(ctx,wanted)then error('home_changed_before_apply')end
   for _,field in ipairs(keys(delta))do delta[field].attempted=true;write(ctx,field,delta[field].after)end
  end)
  if not ok then return failure(tostring(err)..'; rollback='..tostring(rollback(ctx,wanted,delta,'before','after')))end
  local changed=0
  for field,item in pairs(delta)do
   changed=changed+1
   if item.after==false then receipt.changes[field]=nil
   else receipt.changes[field]=receipt.changes[field]or{before=item.before,after=item.after}end
  end
  receipt.ids=available
  if changed>0 then receipt.menu_pending=true end
  active=receipt
  local refreshed,result=pcall(menu,ctx,receipt)
  if not refreshed then return failure(result)end
  return {changed=changed,menu_refreshed=result,menu_pending=receipt.menu_pending}
 end
 function control.baseline(ctx,values)
  if type(values)~='table'then return nil,'home_profile_table_required'end
  if not active then return values end
  local wanted,why=current(ctx);if not wanted then return nil,why end
  if not active then return values end
  for field,item in pairs(active.changes)do
   if values[field]==item.after then values[field]=item.before end
  end
  return values
 end
 function control.before_save(ctx,skip)
  if stopped or not active then return nil end
  local wanted,why=current(ctx);if not wanted then return failure(why)end
  if not active or next(active.changes)==nil then return nil end
  local receipt=active
  local mask={owner=receipt,ctx=ctx,identity=wanted,changes={},status='preparing'}
  local ok,err=pcall(function()
   for _,field in ipairs(keys(receipt.changes))do
    local item=receipt.changes[field]
    if read(ctx,field)==item.after then mask.changes[field]={before=item.before,after=item.after}end
   end
   if skip~=nil then
    mask.skip=skip;mask.skip_before=unbox(skip)
    if type(mask.skip_before)~='boolean'then error('home_skip_parameter_unreadable')end
    if not mask.skip_before then
     mask.skip_attempted=true;skip:set(true)
     if unbox(skip)~=true then error('home_sync_save_parameter_failed')end
    end
   end
   if not matching(ctx,wanted)or active~=receipt then error('home_changed_before_save')end
   for _,field in ipairs(keys(mask.changes))do
    mask.changes[field].attempted=true;write(ctx,field,mask.changes[field].before)
   end
  end)
  if not ok then
   local restored=rollback(ctx,wanted,mask.changes,'after','before')
   if mask.skip_attempted then
    local reset=pcall(function()mask.skip:set(mask.skip_before);assert(unbox(mask.skip)==mask.skip_before)end)
    restored=restored and reset
   end
   mask.status='failed';return failure(tostring(err)..'; rollback='..tostring(restored))
  end
  mask.status='masked';receipt.masks[#receipt.masks+1]=mask
  return mask
 end
 function control.after_save(mask)
  if mask==nil then return {noop=true,restored=0,conflicts={}}end
  if type(mask)~='table'or mask.status~='masked'then return nil,'home_save_mask_not_active'end
  local receipt=mask.owner
  if active~=receipt or not matching(mask.ctx,mask.identity)then mask.status='expired';return nil,'home_save_context_changed'end
  if receipt.masks[#receipt.masks]~=mask then return nil,'home_save_mask_order'end
  local result={restored=0,conflicts={}}
  local errors={}
  for _,field in ipairs(keys(mask.changes))do
   local item=mask.changes[field]
   local ok,err=pcall(function()
    if read(mask.ctx,field)==item.before then write(mask.ctx,field,item.after);result.restored=result.restored+1
    else result.conflicts[#result.conflicts+1]=field end
   end)
   if not ok then errors[#errors+1]=tostring(err)end
  end
  if #errors>0 then mask.recovery_pending=true;return failure(table.concat(errors,';'))end
  table.remove(receipt.masks);mask.status='restored'
  return result
 end
 function control.suspend(ctx)
  if not active then return {noop=true,restored=0,conflicts={}}end
  -- No live campaign context means the caller has left this world. Retire the
  -- receipt without touching retained UObject wrappers from the old world.
  local next_world=type(ctx)=='table'and address(ctx.world)or nil
  if not ctx or (next_world and next_world~=active.identity.world)then
   active.status='expired';active=nil;return {expired=true,restored=0,conflicts={}}
  end
  local wanted,why=current(ctx);if not wanted then return failure(why)end
  if not active then return {expired=true,restored=0,conflicts={}}end
  local receipt=active
  if #receipt.masks>0 then return nil,'home_save_in_progress'end
  local delta,result={},{restored=0,conflicts={}}
  local ok,err=pcall(function()
   for _,field in ipairs(keys(receipt.changes))do
    local item=receipt.changes[field]
    if read(ctx,field)==item.after then delta[field]={before=item.before,after=item.after}
    else result.conflicts[#result.conflicts+1]=field end
   end
   if not matching(ctx,wanted)then error('home_changed_before_suspend')end
   for _,field in ipairs(keys(delta))do
    delta[field].attempted=true;write(ctx,field,delta[field].before);result.restored=result.restored+1
   end
  end)
  if not ok then return failure(tostring(err)..'; rollback='..tostring(rollback(ctx,wanted,delta,'after','before')))end
  if result.restored>0 then receipt.menu_pending=true end
  local refreshed,out=pcall(menu,ctx,receipt)
  if not refreshed then return failure(out)end
  result.menu_refreshed=out;receipt.status='restored';active=nil
  return result
 end
 function control.stop(ctx)
  local result,why=control.suspend(ctx);if not result then return nil,why end
  stopped=true;return result
 end
 function control.status()
  local flags=0;if active then for _ in pairs(active.changes)do flags=flags+1 end end
  return {stopped=stopped,active=active~=nil,slot=active and active.identity.slot or nil,
   overridden_flags=flags,save_depth=active and #active.masks or 0,
   menu_pending=active and active.menu_pending or false,menu_refreshes=active and active.menu_refreshes or 0,
   error=control.last_error,ids=copy(active and active.ids or M.ids)}
 end
 return control
end
return M
