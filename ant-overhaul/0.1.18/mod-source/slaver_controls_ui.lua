-- Aggregate only adapter-owned slaves inside the original pheromone panels.
-- Reuse native ChamberRep2 cards, portraits, drag operations and group buttons.
-- No room records, ordinary chamber assignments or actor ownership are edited.
local M={}
local PANEL='/Game/UI/InGame/MarkerGroupPanel.MarkerGroupPanel_C'
local CARD='/Game/UI/InGame/ChamberRep2.ChamberRep2_C'
-- These CreatureInformation rows have no PheromonePanelIcon. Reuse their
-- native IconImage instead of allowing the null Slate brush to draw white.
-- Exact paths verified against CreatureInformation and the installed pak.
local ICON_BASE='/Game/UI/InGame/UIUpdate/CharacterIcons/SquareImages/'
M.portrait_fallback={
 BeachTigerBeetle_Small='UI_Creature_BeachTigerBeetle_Adult_Square_Icon',
 SmallBeachWolfSpider='UI_Creature_BeachWolfSpider_Small_Square_Icon',
 BeachWolfSpiderling='UI_Creature_BeachWolfSpiderling_Square_Icon',
 SmallHermitCrab='UI_Creature_HermitCrab_Small_Square_Icon',
 JumpingSpider='UI_Creature_JumpingSpider_Square_Icon',
 RoveBeetleALarva='UI_Creature_RoveBeetle_Larva_Square_Icon',
 RoveBeetleBLarva='UI_Creature_RoveBeetle_PhlocionocerusFulgens_Larva_Square_Icon',
 SpinyDevil_Small='UI_Creature_SpinyBushDevilCricket_Small_Square_Icon',
 SSTigerBeetleSmall='UI_Creature_SixSpottedTigerBeetle_Small_Square_Icon',
 CheckeredBeetleLarva='UI_Creature_CheckeredBeetle_Larva_Square_Icon',
 FBBLarva='UI_Creature_FalseBombardierBeetle_Larva_Square_Icon',
 GreenJumperSpider='UI_Creature_GreenJumperSpider_Square_Icon',
 AfricanTigerBeetleSmall='UI_Creature_AfricanElegantiaTigerBeetle_Small_Square_Icon',
 Earwig='UI_Creature_Earwig_Adult_Square_Icon',
 EarwigJuvenile='UI_Creature_Earwig_Juvenile_Square_Icon',
 YungVelvetWorm='UI_Creature_VelvetWorm_Juvenile_Square_Icon',
 NorthernDunesTigerBeetle_Small='UI_Creature_NorthernDuneTigerBeetle_Small_Square_Icon',
 SmallSandBearWolfSpider='UI_Creature_SandBearWolfSpider_Small_Square_Icon',
}
local function safe(fn)local ok,v=pcall(fn);if ok then return v end end
local function unbox(v)local x=v and safe(function()return v:get()end);return x~=nil and x or v end
local function str(v)v=unbox(v);return type(v)=='string'and v or(v and safe(function()return v:ToString()end))end
local function num(v)local n=tonumber(unbox(v));return n and n==n and n~=math.huge and n~=-math.huge and n or nil end
function M.install(options)
 assert(type(options)=='table'and type(options.native)=='table'and type(options.adapter)=='table')
 assert(type(options.get_context)=='function')
 local native,adapter=options.native,options.adapter
 assert(type(adapter.grouped_rows)=='function'and type(adapter.set_group)=='function')
 local stopped,queued,refreshing,dirty=false,false,false,true
 local last_poll=-math.huge
 local clock=options.clock or os.clock
 local last_signature,last_layout,missing_refresh_signature
 local icons={}
 local epoch,world=0,nil
 local hud,assignment,panels,bindings,hidden,painted=nil,nil,{},{},{},{}
 local retired={}
 local pending_moves,pending_reassign,mouse_queries={},{},{}
 local hooks,reported={},{}
 local querying=false
 local control={}
 local function valid(v)return v~=nil and safe(function()return native.valid_object(v)end)==true end
 local function get(v,k)return valid(v)and safe(function()return v[k]end)or nil end
 local function id(v)return valid(v)and tostring(v:GetAddress())or nil end
 local function same(a,b)local k=id(a);return k~=nil and k==id(b)end
 local function identity(v)return valid(v)and v:GetFullName()or nil end
 local function text(s)return StaticFindObject('/Script/Engine.Default__KismetTextLibrary'):Conv_StringToText(tostring(s))end
 local function report(e)
  e=tostring(e);if not reported[e]then reported[e]=true;if options.log then options.log('[SlaverControls] '..e)end end
  return nil,e
 end
 local function later(fn)
  local token=epoch
  local dispatch=options.defer or function(cb)ExecuteInGameThreadAfterFrames(1,cb)end
  dispatch(function()if not stopped and epoch==token then local ok,e=pcall(fn);if not ok then report(e)end end end)
 end
 local function context()
  local c=options.get_context();local gs=c and(c.gs or c.game_state)
  if not valid(gs)then return nil end
  local pc=c.pc or c.controller or native.get_local_controller(gs)
  if not valid(pc)then return nil end
  return c,gs,pc,native.world_id(gs)
 end
 local function attached(card,panel)return valid(card)and valid(panel)and same(card:GetParent(),panel.GridPanel)end
 local function restore_paint(card)
  local entry=painted[id(card)];if not entry then return end
  if valid(card)and identity(card)==entry.identity then
   card.NumberAntsAlive=entry.alive;card.NumberOfBroodTiles=entry.count
   card.NumberText:SetText(text(entry.text));card.NumberText:SetVisibility(entry.visibility)
   if entry.icon_changed then card:PullInfoFromData()end
  end
  painted[id(card)]=nil
 end
 local function restore_hidden(panel,for_refresh)
  local ctx,gs,pc,w=context()
  local grid=ctx and(ctx.grid or ctx.tile_grid or gs:GetTileGridByColonyID(pc:GetColonyID()))
  for k,r in pairs(hidden)do
   if not panel or same(r.panel,panel)then
    local c=get(r.card,'AssignedSwarmCreature')
    local belongs=valid(grid)and valid(c)and native.world_id(c)==w and(num(c.Health)or 0)>0
     and adapter.is_slave(c)==true and num(grid:GetSwarmCreatureGroupAssignment(c))==num(get(r.panel,'GridId'))
    if belongs and valid(r.card)and identity(r.card)==r.identity and valid(r.panel)and valid(r.panel.GridPanel)then
     if not attached(r.card,r.panel)then r.panel.GridPanel:AddChildToUniformGrid(r.card,r.row,r.column)end
     r.card:SetVisibility(for_refresh and 1 or r.visibility)
    elseif valid(r.card)and identity(r.card)==r.identity then
     -- Native Refresh has already moved or removed this individual. Restoring
     -- its previous panel would resurrect a duplicate in the old group.
     restore_paint(r.card);r.card:RemoveFromParent();hidden[k]=nil
    end
    if not for_refresh then hidden[k]=nil end
   end
  end
 end
 local function reset(restore)
  if restore then
   restore_hidden(nil,false)
   for _,r in pairs(painted)do if valid(r.card)then restore_paint(r.card)end end
  end
  epoch=epoch+1;queued=false;dirty=true;last_signature=nil;last_layout=nil;missing_refresh_signature=nil;hud=nil;assignment=nil;panels={};bindings={};hidden={};painted={}
  control.missing_rows=0
  retired={}
  pending_moves={};pending_reassign={};mouse_queries={}
 end
 local function resolve_ui()
  local ctx,gs,pc,w=context();if not ctx or not w then return nil end
  if world~=w then reset(false);world=w end
  -- The controller can replace the HUD without replacing the world. Always
  -- follow its current instance rather than keeping a still-valid old widget.
  local current_hud=options.get_hud and options.get_hud(ctx)or get(pc:GetHUD(),'TugOfWarWidgetInstance')
  if valid(hud)and not same(hud,current_hud)then reset(true)end
  hud=current_hud
  if not valid(hud)then return nil end
  local current=get(hud,'ChamberAssignment')
  if not valid(current)then return nil end
  if assignment and not same(assignment,current)then reset(true);hud=options.get_hud and options.get_hud(ctx)or get(pc:GetHUD(),'TugOfWarWidgetInstance')end
  assignment=current;panels={}
  for i=0,7 do
   local panel=get(assignment,'MarkerGroupPanel'..i)
   if valid(panel)and valid(get(panel,'GridPanel'))then panels[num(panel.GridId)]=panel end
  end
  return ctx,gs,pc,w
 end
 local function layout_signature()
  local parts={}
  for group,panel in pairs(panels)do
   local grid=panel.GridPanel;local children={}
   for i=0,grid:GetChildrenCount()-1 do children[#children+1]=id(grid:GetChildAt(i))or'none'end
   parts[#parts+1]=group..':'..id(panel)..':'..id(grid)..':'..table.concat(children,',')
  end
  table.sort(parts);return table.concat(parts,'|')
 end
 local function owned_rows(gs,w)
  local rows,by_creature={},{}
  for _,source in ipairs(adapter.grouped_rows())do
   assert(type(source.species)=='string'and type(source.group)=='number','invalid_slave_controls_row')
   local row={species=source.species,group=source.group,creatures={},wounded=0}
   for _,c in ipairs(source.creatures or{})do
    if valid(c)and native.world_id(c)==w and native.is_owned(c,gs)==true and adapter.is_slave(c)==true then
     row.creatures[#row.creatures+1]=c
     local state=adapter.describe_state(c);if state and state.state=='wounded'then row.wounded=row.wounded+1 end
     by_creature[id(c)]=row
    end
   end
   row.count=#row.creatures;if row.count>0 then rows[#rows+1]=row end
  end
  return rows,by_creature
 end
 local function live(record)
  return record and not stopped and valid(record.card)and identity(record.card)==record.identity
   and native.world_id(record.card)==world and attached(record.card,record.panel)
 end
 local function move(record,group,require_native)
  assert(record and(not require_native and live(record)or require_native and valid(record.representative)
   and identity(record.representative)==record.representative_identity),'slave_controls_expired')
  assert(type(group)=='number'and group%1==0 and panels[group]and panels[group]:IsVisible(),'slave_controls_group_unavailable')
  local ctx,gs,_,w=context();assert(ctx and w==world,'slave_controls_world_changed')
  if require_native then
   local grid=ctx.grid or gs:GetTileGridByColonyID(native.get_local_controller(gs):GetColonyID())
   if num(grid:GetSwarmCreatureGroupAssignment(record.representative))~=group then return false end
  end
  local rows=owned_rows(gs,w);local row,species_rows
  species_rows=0
  for _,r in ipairs(rows)do if r.species==record.species then species_rows=species_rows+1;if r.group==record.group then row=r end end end
  assert(row,'slave_controls_cohort_changed');if group==row.group then return true end
  local changed={}
  local ok,e=pcall(function()
   if species_rows==1 and type(adapter.set_species_group)=='function'then
    changed=row.creatures;local accepted,why=adapter.set_species_group(row.species,group);assert(accepted==true,why)
   else for _,c in ipairs(row.creatures)do
    changed[#changed+1]=c;local accepted,why=adapter.set_group(c,group);assert(accepted==true,why)
   end end
  end)
  if not ok then
   local restored=true
   for _,c in ipairs(changed)do local success,value=pcall(adapter.set_group,c,row.group);restored=success and value==true and restored end
   error(tostring(e)..'; group_rollback='..tostring(restored))
  end
  dirty=true
  return true
 end
 local refresh
 local function request()
  dirty=true;if stopped or queued then return end;queued=true
  later(function()
   queued=false
   local moves=pending_moves;pending_moves={}
   for _,job in ipairs(moves)do local ok,e=pcall(move,job.record,job.group,job.native);if not ok then report(e)end end
   mouse_queries={};refresh()
  end)
 end
 local function queue_move(record,group,require_native)
  if not live(record)or group==record.group or not panels[group]then return end
  pending_moves[#pending_moves+1]={record=record,group=group,native=require_native};request()
 end
 local function paint(record,row)
  local card=record.card;local k=id(card)
  if not painted[k]then painted[k]={card=card,identity=identity(card),alive=card.NumberAntsAlive,count=card.NumberOfBroodTiles,
   text=str(card.NumberText:GetText())or'',visibility=card.NumberText:GetVisibility()}end
  card.NumberAntsAlive=row.count-row.wounded;card.NumberOfBroodTiles=row.count
  local label=tostring(row.count-row.wounded)..'/'..row.count
  if str(card.NumberText:GetText())~=label then card.NumberText:SetText(text(label))end
  if num(card.NumberText:GetVisibility())~=0 then card.NumberText:SetVisibility(0)end
  local icon_name=M.portrait_fallback[row.species]
  if icon_name then
   local texture=icons[icon_name]
   if not valid(texture)then
    local path=ICON_BASE..icon_name..'.'..icon_name
    texture=StaticFindObject(path);if not valid(texture)then texture=LoadAsset(path)end
    assert(valid(texture),'slave_controls_portrait_missing:'..row.species);icons[icon_name]=texture
   end
   for _,key in ipairs({'UnitImage','ShadowImage'})do
    local image=get(card,key)
    if valid(image)and not same(safe(function()return image.Brush.ResourceObject end),texture)then
     image:SetBrushFromTexture(texture,false);painted[k].icon_changed=true
    end
   end
  end
 end
 refresh=function(resolved)
  -- A native drop moves its representative synchronously. Finish our queued
  -- cohort move before adopting any native per-individual group changes.
  if stopped or refreshing or #pending_moves>0 then return end;refreshing=true
  local ok,e=pcall(function()
   local gs,w
   if resolved then gs,w=resolved[2],resolved[4]
   else local ctx,pc;ctx,gs,pc,w=resolve_ui()end
   if not gs then return end
   last_poll=clock()
   if type(adapter.reconcile_control_groups)=='function'then
    local synced,why=adapter.reconcile_control_groups();assert(synced,why)
   end
   -- Native death cleanup may remove the capture tag before the corpse widget
   -- goes away. Keep the identity of our own deceased members so only their
   -- swarm cards are removed, even if the corpse UObject is still alive.
   local function note_dead(c)
    if valid(c)and(num(c.Health)or 0)<=0 then retired[id(c)]={creature=c,identity=identity(c)}end
   end
   for _,record in pairs(bindings)do for _,c in ipairs(record.creatures)do note_dead(c)end end
   for _,record in pairs(hidden)do note_dead(get(record.card,'AssignedSwarmCreature'))end
   for k,record in pairs(retired)do
    if not valid(record.creature)or identity(record.creature)~=record.identity then retired[k]=nil end
   end
   local rows,by_creature=owned_rows(gs,w)
   local parts={}
   for _,row in ipairs(rows)do
    local members={};for _,c in ipairs(row.creatures)do members[#members+1]=id(c)end;table.sort(members)
    parts[#parts+1]=row.species..':'..row.group..':'..row.wounded..':'..table.concat(members,',')
   end
   table.sort(parts);local signature=table.concat(parts,'|')
   -- Native swarm cards can appear after Refresh has returned. The actor
   -- roster alone cannot tell us whether those late cards need folding.
   local layout=layout_signature()
   if not dirty and signature==last_signature and layout==last_layout then
    local all_live=true;for _,record in pairs(bindings)do if not live(record)then all_live=false;break end end
    if all_live then return end
   end
   -- A successful conversion/assignment may mark the native HUD dirty without
   -- immediately constructing its swarm cards. Request one original refresh
   -- only when this exact membership lacks a card; never poll-refresh the HUD.
   local represented={}
   local function note(card,group)
    local creature_id=id(get(card,'AssignedSwarmCreature'));local row=by_creature[creature_id]
    if row and row.group==group then represented[creature_id]=true end
   end
   for group,panel in pairs(panels)do for i=0,panel.GridPanel:GetChildrenCount()-1 do note(panel.GridPanel:GetChildAt(i),group)end end
   for _,r in pairs(hidden)do if valid(r.panel)then note(r.card,num(r.panel.GridId))end end
   local missing=false;for creature_id in pairs(by_creature)do if not represented[creature_id]then missing=true;break end end
   if missing and missing_refresh_signature~=signature then
    missing_refresh_signature=signature;assignment:RefreshForMarker()
   end
   -- Reattach detached native individuals before choosing this pass's leaders.
   -- They remain collapsed; the same objects survive native Refresh.
   restore_hidden(nil,true)
   local new_bindings,new_hidden={},{}
   local seen={}
   for group,panel in pairs(panels)do
    local grid=panel.GridPanel;local children={}
    for i=0,grid:GetChildrenCount()-1 do children[#children+1]=grid:GetChildAt(i)end
    for _,card in ipairs(children)do
     local c=get(card,'AssignedSwarmCreature');local row=by_creature[id(c)]
     local dead=retired[id(c)]
     if not row and valid(c)and(num(c.Health)or 0)<=0 and not valid(get(card,'RoomRef'))
      and get(card,'bThisIsScientistHand')~=true and((dead and dead.identity==identity(c))or adapter.is_slave(c)==true)then
      note_dead(c);restore_paint(card);card:RemoveFromParent();hidden[id(card)]=nil
     elseif row and row.group==group and not valid(get(card,'RoomRef'))and get(card,'bThisIsScientistHand')~=true then
      local k=id(card);local rowkey=tostring(group)..':'..row.species
      if not seen[rowkey]then
       seen[rowkey]=true
       local old=hidden[k];if old then card:SetVisibility(old.visibility)end
       local record={card=card,identity=identity(card),panel=panel,species=row.species,group=group,creatures=row.creatures,
        representative=c,representative_identity=identity(c)}
       new_bindings[k]=record;paint(record,row)
      elseif get(card,'bBeingMoved')~=true then
       restore_paint(card)
       local slot=get(card,'Slot');local old=hidden[k]
       new_hidden[k]=old or{card=card,identity=identity(card),panel=panel,visibility=card:GetVisibility(),row=num(get(slot,'Row'))or 0,column=num(get(slot,'Column'))or 0}
       card:SetVisibility(1);card:RemoveFromParent()
      end
     end
    end
    -- Native grid uses three rows per column. Keep ordinary card order intact.
    for i=0,grid:GetChildrenCount()-1 do
     local card=grid:GetChildAt(i);local slot=get(card,'Slot')
     if valid(slot)then
      if num(slot.Row)~=i%3 then slot:SetRow(i%3)end
      if num(slot.Column)~=math.floor(i/3)then slot:SetColumn(math.floor(i/3))end
     end
    end
   end
   for k,r in pairs(painted)do if not new_bindings[k]then restore_paint(r.card)end end
   for k,r in pairs(hidden)do if not new_hidden[k]and valid(r.card)and attached(r.card,r.panel)then r.card:SetVisibility(r.visibility)end end
   bindings,hidden=new_bindings,new_hidden
   dirty=false;last_signature=signature;last_layout=layout_signature()
   control.missing_rows=0;for _,row in ipairs(rows)do if not seen[tostring(row.group)..':'..row.species]then control.missing_rows=control.missing_rows+1 end end
  end)
  refreshing=false;if not ok then return report(e)end;return true
 end
 local function bind_hook(path,pre,post)
  if hooks[path]then return true end
  local register=options.register_hook or RegisterHook
  local function wrap(fn)return fn and function(...)if stopped then return end;local ok,e=pcall(fn,...);if not ok then report(e)end end end
  local ok,a=pcall(register,path,wrap(pre),wrap(post))
  if ok and a~=nil then hooks[path]=true;return true end
  return report('hook unavailable: '..path..' '..tostring(a))
 end
 local function ensure_hooks()
  if options.register_hooks==false then return true end
  local ready=true
  ready=bind_hook(PANEL..':Refresh',function(receiver)
   local panel=unbox(receiver);if same(panels[num(get(panel,'GridId'))],panel)then restore_hidden(panel,true);request()end
  end)and ready
  local function drop(panel,operation)
   panel,operation=unbox(panel),unbox(operation)
   if not same(panels[num(get(panel,'GridId'))],panel)or not valid(get(operation,'TemporaryWidgetII'))then return end
   local record=bindings[id(get(operation,'PreviousChamberRepButton'))]
   queue_move(record,num(panel.GridId),true)
  end
  ready=bind_hook(PANEL..':OnDrop',function(panel,geometry,event,operation)drop(panel,operation)end)and ready
  ready=bind_hook(PANEL..':GamepadOnDrop',drop)and ready
  ready=bind_hook(CARD..':ReassignChamber',function(card,group)
   card=unbox(card);if live(bindings[id(card)])then pending_reassign[id(card)]=num(group)end
  end)and ready
  ready=bind_hook(CARD..':ExecuteUbergraph_ChamberRep2',function(receiver,entry)
   local card=unbox(receiver);local record=bindings[id(card)];if not live(record)then return end
   local offset=num(entry);local group
   if offset==162 then group=pending_reassign[id(card)];pending_reassign[id(card)]=nil
   elseif offset==4896 or offset==3542 or offset==2858 then
    local ids={};for g,p in pairs(panels)do if p:IsVisible()then ids[#ids+1]=g end end;table.sort(ids)
    for i,g in ipairs(ids)do if g==record.group then group=ids[i+(offset==2858 and-1 or 1)];break end end
   else return end
   entry:set(4982);if group~=nil then queue_move(record,group,false)end
  end)and ready
  ready=bind_hook(CARD..':OnMouseButtonUp',function(receiver)
   local card=unbox(receiver);local record=bindings[id(card)]
   if live(record)then local pc=card:GetOwningPlayer();if valid(pc)then mouse_queries[id(pc)]=record;request()end end
  end)and ready
  ready=bind_hook('/Script/Engine.PlayerController:IsInputKeyDown',function(receiver,keyarg)
   if querying then return end
   local pc=unbox(receiver);local record=mouse_queries[id(pc)];local key=unbox(keyarg)
   if not live(record)or not key or str(key.KeyName)~='LeftShift'then return end
   mouse_queries[id(pc)]=nil
   querying=true;local ok,down=pcall(function()return pc:IsInputKeyDown(key)end);querying=false
   if not ok then error(down)end
   if down==true then
    -- Consume only this card's synchronous shift-click query. The native
    -- branch otherwise dereferences RoomRef even for a swarm-only card.
    key.KeyName=FName('None');queue_move(record,num(hud.ActiveMarkerID),false)
   end
  end)and ready
  return ready
 end
 function control.tick()
  if stopped then return false end
  -- Real panel/input events use request() and refresh on the next frame.
  -- Otherwise reconcile late cards, death and external assignments at 4 Hz,
  -- independently of frame rate, without walking all native cards every 5 frames.
  local now=clock()
  if not dirty and now>=last_poll and now-last_poll<0.25 then return false end
  local ok,e=pcall(function()
   local resolved={resolve_ui()};if not resolved[1]then return false end
   if not ensure_hooks()then return false end
   return refresh(resolved)
  end)
  if not ok then return report(e)end;return e
 end
 function control.reassign(card,group)
  local ok,e=pcall(move,bindings[id(card)],group,false);if not ok then return report(e)end;request();return e
 end
 function control.set_individual(card,creature,group)
  local record=bindings[id(card)];if not live(record)then return nil,'slave_controls_expired'end
  local found=false;for _,c in ipairs(record.creatures)do if same(c,creature)then found=true;break end end
  if not found or not panels[group]then return nil,'slave_controls_individual_missing'end
  local ok,e=adapter.set_group(creature,group);if ok then request()end;return ok,e
 end
 function control.status()
  local out={cards=0,hidden=0,missing_rows=control.missing_rows or 0,stopped=stopped,hooks={}}
  for _ in pairs(bindings)do out.cards=out.cards+1 end;for _ in pairs(hidden)do out.hidden=out.hidden+1 end
  for k,v in pairs(hooks)do out.hooks[k]=v end;return out
 end
 function control.stop()
  local old=assignment;reset(true);stopped=true
  if valid(old)then old:RefreshForMarker()end
  return true
 end
 return control
end
return M
