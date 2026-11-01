-- Extra home-species cultivation cards inside the original Biology screen.
-- Called on the game thread by the existing maintenance loop. This module only
-- owns UI widgets; the ordinary attribute API owns points, payment and saving.
local M = {}
local TREE = '/Game/UI/InGame/TechTree/TechTree2.TechTree2_C'
local BUTTON = '/Game/UI/InGame/TechTree/SpeciesEntry.SpeciesEntry_C'
local ICON_BASE = '/Game/UI/InGame/UIUpdate/CharacterIcons/SquareImages/'
-- IconImage entries from the installed CreatureInformation table.
local ICONS = {
 LeafcutterSuperMajor='UI_Creature_AttaCephalotes_SuperMajor_Square_Icon',
 SlaveMaker='UI_Creature_FormicaSanguinea_SlaveMaker_Square_Icon',
 TrapjawAnt='UI_Creature_TrapJaw_Square_Icon',
 ArmyAnt='UI_Creature_EcitonBurchelli_ArmyAnt_Media_Square_Icon',
 ArmyAntMajor='UI_Creature_EcitonBurchelli_ArmyAnt_Major_Square_Icon',
 BigHeadedMajor='UI_Creature_BigHeadedAnt_Soldier_Square_Icon',
 BigHeadedSuperSoldier='UI_Creature_BigHeadedAnt_SuperSoldier_Square_Icon',
 LittleBlackAnt='UI_Creature_LittleBlackAntSoldier_Square_Icon',
 TermiteMajorWorker='UI_Creature_MacrotermesBellicosus_Worker_Major_Square_Icon',
 DriverAntWorker='UI_Creature_DriverAnt_Worker_Square_Icon',
 DriverAntSoldier='UI_Creature_DriverAnt_Soldier_Square_Icon',
 DriverAntLargeSoldier='UI_Creature_DriverAnt_Major_Square_Icon',
 StinkAnt='UI_Creature_AfricanStinkAnt_Square_Icon',
}

function M.install(api)
 assert(type(api)=='table' and type(api.resolve_group)=='function')
 local native,groups,ui=assert(api.native),assert(api.groups),assert(api.ui)
 assert(type(groups.supplemental)=='table' and type(ui.open_external)=='function')
 local catalog=assert(api.catalog)
 assert(type(catalog.is_selectable)=='function','roster selection policy unavailable')
 local visible_groups={}
 for _,row in ipairs(groups.supplemental)do
  if catalog.is_selectable(row.roster_id or row.id)then visible_groups[#visible_groups+1]=row end
 end
 local control,records,pending,hooks,reported={},{},{},{},{}
 local card_owners,inner_owners,focus_stack={},{},{}
 local enabled,discovery,next_retry,last_completion=true,true,0,nil
 local clock=api.clock or os.clock
 local function valid(object) return object~=nil and native.valid_object(object)==true end
 local function get(object,key)
  if not valid(object)then return nil end
  local ok,value=pcall(function()return object[key]end);return ok and value or nil
 end
 local function ident(object)return valid(object)and tostring(object:GetAddress())or nil end
 local function same(a,b)local id=ident(a);return id~=nil and id==ident(b)end
 local function report(message)pcall(api.log or print,'[ForeignCultivation UI] '..tostring(message))end
 local function once(key,message)if not reported[key]then reported[key]=true;report(message)end end
 local function unbox(value)local ok,out=pcall(function()return value:get()end);return ok and out or value end
 local function mounted(tree)
  if not valid(tree)then return false end
  local ok,visible=pcall(function()return tree:IsVisible()end)
  if not ok or not visible then return false end
  local rooted,in_view=pcall(function()return tree:IsInViewport()end)
  if rooted and in_view then return true end
  local good,parent=pcall(function()return tree:GetParent()end)
  if not good or not valid(parent)then return false end
  for _=1,20 do
   if not valid(parent)or not parent:IsVisible()then return false end
   local view,is_view=pcall(function()return parent:IsInViewport()end)
   if view and is_view then return true end
   local has,next_parent=pcall(function()return parent:GetParent()end)
   if has and valid(next_parent)then parent=next_parent
   else
    local outer,next_outer=pcall(function()return parent:GetOuter()end)
    if not outer or not valid(next_outer)or same(parent,next_outer)then return false end
    parent=next_outer
   end
  end
  return false
 end
 local function load(path)
  local value=StaticFindObject(path)
  if not valid(value)then value=LoadAsset(path)end
  assert(valid(value),'UI asset missing: '..path)
  return value
 end
 local function restore_mouse_scroll(record)
  local guard=record.mouse_scroll
  record.mouse_scroll=nil
  if guard and valid(guard.scroll)then guard.scroll:SetScrollWhenFocusChanges(guard.mode)end
 end
 local function mouse_scroll(record,button)
  local scroll=get(record.tree,'CoreScrollBox')
  if not valid(scroll)then return end
  local guard=record.mouse_scroll
  if not guard then
   guard={scroll=scroll,mode=scroll.ScrollWhenFocusChanges}
   record.mouse_scroll=guard
  end
  guard.card_id=ident(button)
  scroll:SetScrollWhenFocusChanges(0)
 end
 local function owned_card(button)
  local owned=card_owners[ident(button)]
  if not owned then return nil end
  local record=owned.record
  if not mounted(record.tree)or not valid(record.world)
   or not same(record.tree:GetWorld(),record.world)
   or not same(button,record.buttons[owned.row.id])
   or not same(button:GetWorld(),record.world)
   or not same(button:GetParent(),record.panel)then return nil end
  return owned
 end
 local function queue_open(owned,button)
  local record=owned.record
  if record.open_pending or ui.get_active()or ui.get_queued()then return end
  record.open_pending=button
  -- The native graph first exits through HexEnabled=false. Open on the next
  -- game frame, never from the 30-frame maintenance timer or inside that graph.
  ExecuteInGameThreadAfterFrames(1,function()
   if not enabled or record.open_pending~=button then return end
   record.open_pending=nil
   if owned_card(button)~=owned or ui.get_active()or ui.get_queued()then return end
   local ok,err=pcall(function()
    local ctx,why=api.resolve_group(owned.row.id,record.tree)
    if not ctx then report('培养记录暂不可用：'..tostring(why));return end
    local opened,reason=ui.open_external(ctx,record.tree,record.icons[owned.row.id])
    if not opened then report('培养窗口未打开：'..tostring(reason))end
   end)
   if not ok then report('培养窗口未打开：'..tostring(err))end
  end)
 end
 local function forget(record)
  -- Keep creation IDs: an expired UObject no longer exposes its old address.
  for _,id in ipairs(record.card_ids or{})do
   if card_owners[id]and card_owners[id].record==record then card_owners[id]=nil end
  end
  if inner_owners[record.inner_id]==record then inner_owners[record.inner_id]=nil end
  record.open_pending=nil
  restore_mouse_scroll(record)
 end
 local function remove(record)
  forget(record)
  for _,button in pairs(record.buttons or{})do
   if valid(button)then pcall(function()button:RemoveFromParent()end)end
  end
  if valid(record.inner)and record.original_rows then
   pcall(function()
    record.inner.MaxRows=record.original_rows
    record.inner:HorizontalAlignment();record.inner:VerticalAlignment()
    if valid(record.tree)then record.tree:RegenerateHexBG()end
   end)
  end
 end
 local function reflow(record)
  local inner,panel,tree=record.inner,record.panel,record.tree
  local layout=StaticFindObject('/Script/UMG.Default__WidgetLayoutLibrary')
  -- Measure the original tree's responsive row spacing before adding rows.
  -- Using the expanded row count would compress all cards into one screen.
  inner.MaxRows=record.original_rows
  inner:VerticalAlignment()
  local positions={}
  for index=0,record.original_count-1 do
   local child=panel:GetChildAt(index)
   if valid(child)and child:IsVisible()then
    local slot=layout:SlotAsGridSlot(child)
    local y=valid(slot)and tonumber(slot.Nudge.Y)
    if y then positions[#positions+1]=y end
   end
  end
  table.sort(positions)
  local spacing=tonumber(inner.RowHeight)or 200
  for index=2,#positions do
   local gap=positions[index]-positions[index-1]
   if gap>1 then spacing=math.max(spacing,gap);break end
  end
  inner.MaxRows=record.original_rows+math.ceil(#visible_groups/tonumber(inner.MaxColumns))
  inner:HorizontalAlignment()
  local count,columns=panel:GetChildrenCount(),tonumber(inner.MaxColumns)
  local visible_rows={}
  for index=0,count-1 do
   local child=panel:GetChildAt(index)
   if valid(child)and child:IsVisible()then visible_rows[math.floor(index/columns)]=true end
  end
  local position,visible=0,0
  for logical=0,math.ceil(count/columns)-1 do
   if visible_rows[logical]then
    for index=logical*columns,math.min(count-1,(logical+1)*columns-1)do
     local child=panel:GetChildAt(index)
     if valid(child)then
      local slot=layout:SlotAsGridSlot(child)
      assert(valid(slot),'Biology grid slot expired')
      slot:SetNudge({X=slot.Nudge.X,Y=position})
     end
    end
    position=position+spacing;visible=visible+1
   end
  end
  local scale=tonumber(layout:GetViewportScale(tree))
  assert(scale and scale>0,'invalid UI viewport scale')
  inner.SpeciesRowHeightSize=math.ceil(spacing*scale)
  inner.RowVisibilityCountForHexes=visible
  tree:RegenerateHexBG()
  record.viewport_x,record.viewport_y=inner.LastViewportSize.X,inner.LastViewportSize.Y
 end
 local function attach(tree)
  local id=assert(ident(tree),'invalid Biology root')
  if records[id]then return records[id]end
  if not mounted(tree)then return nil,'tree_not_mounted' end
  local first=visible_groups[1]
  local ctx,why=api.resolve_group(first.id,tree)
  if not ctx then return nil,why end
  local inner=get(tree,'TreeInner')
  local panel=get(inner,'SpeciesGridPanel_1')or get(inner,'SpeciesGridPanel')
  assert(valid(inner)and valid(panel),'Biology species grid unavailable')
  local owner=tree:GetOwningPlayer()
  assert(valid(owner),'Biology owner unavailable')
  local creator=StaticFindObject('/Script/UMG.Default__WidgetBlueprintLibrary')
  assert(valid(creator),'widget factory unavailable')
  local layout=StaticFindObject('/Script/UMG.Default__WidgetLayoutLibrary')
  assert(valid(layout),'widget layout library unavailable')
  local cls=load(BUTTON)
  local columns=tonumber(inner.MaxColumns)
  local rows=tonumber(inner.MaxRows)
  assert(columns and columns>=1 and columns<=12 and rows and rows>=1 and rows<=50,'invalid Biology grid dimensions')
  local record={tree=tree,inner=inner,panel=panel,buttons={},icons={},card_ids={},inner_id=ident(inner),original_rows=rows,
   original_count=panel:GetChildrenCount(),world=tree:GetWorld()}
  local ok,err=pcall(function()
   for index,row in ipairs(visible_groups)do
    assert(row.supplemental==true and ICONS[row.id],'unknown supplemental species')
    local button=creator:Create(owner,cls,owner)
    assert(valid(button),'cultivation card creation failed')
    record.buttons[row.id]=button
    local icon_name=ICONS[row.id]
    local icon=load(ICON_BASE..icon_name..'.'..icon_name)
    record.icons[row.id]=icon
    button.SpeciesIdentifier=255
    button.SpeciesSubtypeIdentifer=0
    button.SpeciesName=FName(row.creature_name)
    button.ParentWidget=tree
    button.SecondaryCast=true
    panel:AddChildToGrid(button,rows+math.floor((index-1)/columns),(index-1)%columns)
    button['Set Main Hex'](button,true,true,icon)
    button['Set Ability Button States'](button,false,false,false,false,true)
    button:SetLevelButtonsStates(0,true)
    button.Purchased=true
    button.EntryAbilitiesHidden=true
    button.HideImprovmentsButton=false
    button.MinImprovementsLock:SetVisibility(1)
    button.HexLockout:SetVisibility(1)
    button.MinorImprovementsSizeBox:SetVisibility(0)
    button.MinorImprovementsHex:SetVisibility(0)
    button.MinorImprovementsHex:SetIsEnabled(true)
    button.Plus:SetVisibility(3)
    -- This gate is checked before the native branch creates its improvements
    -- widget. Only these supplemental cards route their plus event to our API;
    -- there are deliberately no invented ColonySetup improvement properties.
    button.HexEnabled=false
    local card_id=assert(ident(button),'cultivation card expired')
    record.card_ids[#record.card_ids+1]=card_id
    card_owners[card_id]={record=record,row=row}
    local textlib=StaticFindObject('/Script/Engine.Default__KismetTextLibrary')
    button.MinorImprovementsHex:SetToolTipText(textlib:Conv_StringToText(row.title..' · 培养属性'))
   end
   inner.MaxRows=rows+math.ceil(#visible_groups/columns)
   -- The native tree intentionally stores every item in grid cell 0,0 and
   -- positions them with per-slot Nudge. Reuse its responsive placement.
   reflow(record)
  end)
  if not ok then remove(record);error(err)end
  records[id]=record
  inner_owners[ident(inner)]=record
  report('已加入 '..#visible_groups..' 个额外蚁种培养入口')
  return record
 end
 local function ensure_hooks()
  if (hooks.viewport and hooks.player_screen and hooks.card_graph and hooks.focus
   and hooks.mouse_preview and hooks.key_preview)or clock()<next_retry then return end
  next_retry=clock()+2
  -- Native mounting UFunctions are observed even when Blueprint Construct is
  -- entered directly through its event graph and bypasses its named wrapper.
  for name,path in pairs({viewport='/Script/UMG.UserWidget:AddToViewport',
    player_screen='/Script/UMG.UserWidget:AddToPlayerScreen',construct=TREE..':Construct'})do
   if not hooks[name]and valid(StaticFindObject(path))then
    local ok,pre,post=pcall(RegisterHook,path,function()end,function(receiver)
     if not enabled then return end
     local tree=unbox(receiver);local id=ident(tree)
     if not id then return end
     local good,class_name=pcall(function()
      local value=tree:GetClass():GetFName()
      return type(value)=='string'and value or value:ToString()
     end)
     if good and class_name=='TechTree2_C'then pending[id]=tree end
    end)
    if ok and type(pre)=='number'and type(post)=='number'then
     hooks[name]={path,pre,post};discovery=true
    end
   end
  end
  local graph=BUTTON..':ExecuteUbergraph_SpeciesEntry'
  if not hooks.card_graph and valid(StaticFindObject(graph))then
   local ok,pre,post=pcall(RegisterHook,graph,function(receiver,entry)
    if not enabled then return end
    local button=unbox(receiver);local owned=owned_card(button)
    local offset=tonumber(unbox(entry))
    if not owned then return end
    if offset==30275 then mouse_scroll(owned.record,button)
    elseif offset==30492 then
     local guard=owned.record.mouse_scroll
     if guard and guard.card_id==ident(button)then restore_mouse_scroll(owned.record)end
    elseif offset==18606 or offset==28334 then
     button.HexEnabled=false;button.Purchased=true
     if offset==28334 then restore_mouse_scroll(owned.record)end
     queue_open(owned,button)
    end
   end,function()end)
   if ok and type(pre)=='number'and type(post)=='number'then hooks.card_graph={graph,pre,post}end
  end
  local focus='/Script/UMG.Widget:SetFocus'
  if not hooks.focus and valid(StaticFindObject(focus))then
   local ok,pre,post=pcall(RegisterHook,focus,function(receiver)
    local entry={}
    if enabled then
     local record=inner_owners[ident(unbox(receiver))]
     local scroll=record and get(record.tree,'CoreScrollBox')
     if record and mounted(record.tree)and valid(scroll)then
      entry.scroll=scroll;entry.mode=scroll.ScrollWhenFocusChanges
      scroll:SetScrollWhenFocusChanges(0)
     end
    end
    focus_stack[#focus_stack+1]=entry
   end,function()
    local entry=table.remove(focus_stack)
    if entry and valid(entry.scroll)then entry.scroll:SetScrollWhenFocusChanges(entry.mode)end
   end)
   if ok and type(pre)=='number'and type(post)=='number'then hooks.focus={focus,pre,post}end
  end
  -- Slate focuses a Button on mouse-down before its release delegate runs.
  -- Preview input separates that mouse-only suppression from keyboard/gamepad
  -- navigation, which must retain the native animated scroll behavior.
  for name,path in pairs({mouse_preview='/Script/UMG.UserWidget:OnPreviewMouseButtonDown',
    key_preview='/Script/UMG.UserWidget:OnPreviewKeyDown'})do
   if not hooks[name]and valid(StaticFindObject(path))then
    local ok,pre,post=pcall(RegisterHook,path,function(receiver)
     if not enabled then return end
     local widget=unbox(receiver);local owned=owned_card(widget)
     if name=='mouse_preview'then
      if owned then mouse_scroll(owned.record,widget)end
     else
      local id=ident(widget)
      local record=owned and owned.record or inner_owners[id]or records[id]
      if record then restore_mouse_scroll(record)end
     end
    end,function()end)
    if ok and type(pre)=='number'and type(post)=='number'then hooks[name]={path,pre,post}end
   end
  end
 end
 function control.tick()
  if not enabled then return false end
  ensure_hooks()
  if discovery then
   discovery=false
   for _,tree in ipairs(FindAllOf('TechTree2_C')or{})do
    local id=ident(tree);if id then pending[id]=tree end
   end
  end
  for id,tree in pairs(pending)do
   if not valid(tree)then pending[id]=nil
   elseif mounted(tree)then
    local ok,record,why=pcall(attach,tree)
    if ok and record then pending[id]=nil
    elseif not ok then once('attach:'..id,record);pending[id]=nil
    elseif why~='tree_not_mounted'then once('context:'..tostring(why),why)end
   end
  end
  local completion=ui.last_completion and ui.last_completion.job_id
  local completed=completion~=nil and completion~=last_completion
  if completed then last_completion=completion end
  for id,record in pairs(records)do
   if not valid(record.tree)or not valid(record.world)or not same(record.tree:GetWorld(),record.world)then
    forget(record)
    records[id]=nil
   elseif mounted(record.tree)then
    if record.viewport_x~=record.inner.LastViewportSize.X or record.viewport_y~=record.inner.LastViewportSize.Y then
     reflow(record)
    end
    if completed then
     record.tree:RefreshAfterPurchase()
     reflow(record)
    end
   end
  end
  return true
 end
 function control.stop()
  enabled=false
  for _,record in pairs(records)do remove(record)end
  for _,hook in pairs(hooks)do pcall(UnregisterHook,hook[1],hook[2],hook[3])end
  records,pending={},{}
  return true
 end
 function control.status()
  local result={trees=0,cards=0}
  for _,record in pairs(records)do
   if valid(record.tree)then
    result.trees=result.trees+1
    for _,button in pairs(record.buttons)do if valid(button)then result.cards=result.cards+1 end end
   end
  end
  return result
 end
 return control
end
return M
