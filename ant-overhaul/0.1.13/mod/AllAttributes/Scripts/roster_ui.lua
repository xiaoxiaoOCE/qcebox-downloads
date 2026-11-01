-- Story-only adapter around the game's original CustomColonySetup widget.
-- All functions in this module except the numeric Escape mailbox run on the
-- game thread. The backend owns persistence, prices, points and live colonies.
local M = {}
local CUSTOM = '/Game/UI/Wiki/CustomColonySetup.CustomColonySetup_C'
local STORY = '/Game/UI/InGame/FormicariumUI/FormicLevelSetup2.FormicLevelSetup2_C'
local CARD = '/Game/UI/InGame/TechTree/SpeciesEntryCustomColony.SpeciesEntryCustomColony_C'
local MENU = '/Game/UI/InGame/InGameMenu.InGameMenu_C'
local NAMES = {
 LeafcutterMedia='LeafCutterMedia', LeafcutterMajor='LeafCutterMajor',
 SlaveMaker='SlaveMakerAnt', MatabeleMedic='MatabeleAnt', TermiteSoldier='TermiteMinorSoldier',
}
local EXTRA_NAMES = {LeafcutterSuperMajor='LeafcutterSuperMajor',TermiteMajorWorker='TermiteMajorWorker'}
local SKILL_ENTRIES = {[4426]='left',[2705]='left',[2573]='right',[4563]='right'}

-- Pure projection: selected catalog IDs, edited skills and explicit variants.
-- A private native UI struct is never accepted as a payload by this interface.
function M.project(catalog, selected, initial, final, touched, available, variants_touched, dlc_available)
 local payload={selectedIds={},skillOverrides={},variantOverrides={}}
 for id,value in pairs(selected)do
  assert(value==true and catalog.is_selectable(id,dlc_available) and not available[id], 'invalid selected species')
  payload.selectedIds[id]=true
 end
 for id,sides in pairs(touched)do
  local row=assert(catalog.by_id[id], 'unknown skill species')
  if payload.selectedIds[id] then
   for side,explicit in pairs(sides)do
    assert(explicit==true,'skill edit must be explicit')
    local fields=assert(row.skill_pairs and row.skill_pairs[side], 'unknown skill pair')
    for _,field in ipairs(fields)do
     assert(type(initial[field])=='boolean' and type(final[field])=='boolean', 'non-boolean skill value')
     if initial[field]~=final[field] then payload.skillOverrides[field]=final[field] end
    end
    assert(not(final[fields[1]] and final[fields[2]]), 'mutually exclusive skills selected together')
   end
  end
 end
 for id,explicit in pairs(variants_touched or{})do
  local row=assert(catalog.by_id[id], 'unknown variant species')
  assert(explicit==true and row.variant_field, 'invalid explicit variant')
  if payload.selectedIds[id]then
   local value=final[row.variant_field]
   assert(type(value)=='boolean','non-boolean variant value')
   payload.variantOverrides[row.variant_field]=value
  end
 end
 return payload
end

function M.install(api)
 assert(type(api)=='table' and type(api.valid_object)=='function')
 for _,name in ipairs({'get_context','validate_request','submit_flags','cancel_request'})do
  assert(type(api[name])=='function','missing roster UI API: '..name)
 end
 local catalog=assert(api.catalog)
 assert(type(catalog.entries)=='table' and type(catalog.by_id)=='table')
 assert(type(catalog.is_selectable)=='function','roster selection policy unavailable')
 local control,armed,restarts,hooks,reported={},{},{},{},{}
 local active,enabled,escape_requests=nil,true,0
 local confirm_requested=nil
 local restart_requested=nil
 local hooks_ready,next_hook_retry=false,0
 local discovery_requested,next_discovery=true,0
 local clock=api.clock or os.clock
 local open,finish,ensure_hooks
 local function unbox(value)
  local ok,result=pcall(function()return value:get()end)
  return ok and result or value
 end
 local function valid(object)
  if object==nil then return false end
  local ok,result=pcall(api.valid_object,object);return ok and result==true
 end
 local function ident(object)return valid(object) and tostring(object:GetAddress()) or nil end
 local function same(a,b)local x=ident(a);return x~=nil and x==ident(b)end
 local function report(message)
  pcall(api.error or print,'[StoryRoster UI] '..tostring(message))
 end
 local function once(key,message)if not reported[key]then reported[key]=true;report(message)end end
 local function safe(label,callback)
  return function(...)
   if not enabled then return end
   local ok,err=pcall(callback,...)
   if not ok then report(label..': '..tostring(err)) end
  end
 end
 local function get(object,key)
  if not valid(object)then return nil end
  local ok,value=pcall(function()return object[key]end);if ok then return value end
 end
 local function text(value)
  return StaticFindObject('/Script/Engine.Default__KismetTextLibrary'):Conv_StringToText(tostring(value))
 end
 local function fname(value)
  local ok,s=pcall(function()return value:ToString()end);return ok and s or tostring(value)
 end
 local function is_class(object,name)
  return valid(object) and fname(object:GetClass():GetFName())==name
 end
 local function attached(object,ignore_own_visibility)
  local cur=object
  for depth=1,24 do
   if not valid(cur)then return false end
   if not(depth==1 and ignore_own_visibility)then
    local ok,visible=pcall(function()return cur:IsVisible()end)
    if ok and not visible then return false end
   end
   local ok,visible=pcall(function()return cur:IsInViewport()end)
   if ok and visible then return true end
   local good,parent=pcall(function()return cur:GetParent()end)
   if good and valid(parent)then cur=parent
   else
    local outer,next_object=pcall(function()return cur:GetOuter()end)
    if not outer or not valid(next_object)or same(next_object,cur)then return false end
    cur=next_object
   end
  end
  return false
 end
 local function context_alive(session)
  if not valid(session.parent)or not valid(session.world)or not valid(session.owner)then return false end
  if not same(session.owner:GetWorld(),session.world)then return false end
  if session.key and fname(get(session.parent,'StoredLevelKey'))~=session.key then return false end
  return api.validate_request(session.ctx)==true
 end
 -- A removed root dialog can retain its UObject Outer (the live HUD). That
 -- ownership is useful while walking embedded widget trees, but cannot prove
 -- that a native confirmation dialog is still mounted after RemoveFromParent.
 local function awaiting_dialog_attached(object)
  if not valid(object)then return false end
  local ok,in_viewport=pcall(function()return object:IsInViewport()end)
  if not(ok and in_viewport)then
   local parent_ok,parent=pcall(function()return object:GetParent()end)
   if not parent_ok or not valid(parent)then return false end
  end
  return attached(object,true)
 end
 local function detach(widget)
  if valid(widget)then widget:SetIsEnabled(false);widget:SetVisibility(1);widget:RemoveFromParent()end
 end
 local function walk(root,callback)
  local seen={}
  local function visit(object)
   local id=ident(object);if not id or seen[id]then return end;seen[id]=true
   local children={}
   local ok,count=pcall(function()return object:GetChildrenCount()end)
   if ok and type(count)=='number'then
    for i=0,count-1 do local child=object:GetChildAt(i);if valid(child)then children[#children+1]=child end end
   end
   local tree=get(object,'WidgetTree')
   if valid(tree)and valid(tree.RootWidget)then children[#children+1]=tree.RootWidget end
   for _,child in ipairs(children)do visit(child)end
   callback(object,fname(object:GetFName()))
  end
  visit(root)
 end
 local function strip_numbers(card)
  card.HideImprovmentsButton=true
  for _,key in ipairs({'LevelButton1','LevelButton2','LevelButton3','Level1Img','Level2Img','Level3Img'})do detach(get(card,key))end
  walk(card,function(object,name)
   name=name:lower()
   if name:find('improv',1,true)or name:find('levelbutton',1,true)
    or name:find('level1',1,true)or name:find('level2',1,true)or name:find('level3',1,true)then detach(object)end
  end)
 end
 local function skill_card_id(card)
  local session=active
  if not session or session.initializing or not valid(card)
   or not same(get(card,'ParentWidget'),session.widget)then return nil end
  local id=session.cards[ident(card)]
  if id then return id end
  for _,row in ipairs(catalog.entries)do
   if row.skill_pairs and same(session.buttons[row.id],card)then
    session.cards[ident(card)]=row.id;return row.id
   end
  end
 end
 local function mark_skill_edit(card,side)
  local id=skill_card_id(card)
  if not id or not catalog.by_id[id].skill_pairs[side]then return end
  active.touched[id]=active.touched[id]or{};active.touched[id][side]=true
 end
 local function notify_cancel(session,reason)
  if session.cancel_notified then return end;session.cancel_notified=true
  if session.on_cancel then pcall(session.on_cancel,reason)end
 end
 finish=function(session,accepted)
  if active~=session then return end
  if confirm_requested==session then confirm_requested=nil end
  active=nil
  if valid(session.widget)then
   local child=get(session.widget,'ActiveOverlayWidget')
   if valid(child)then child:RemoveFromParent()end
   session.widget:RemoveFromParent()
  end
  if not accepted then notify_cancel(session,'cancelled')end
 end
 local function make_extra(session,row,creator,owner)
  local prototype=session.widget.TrapjawAnt
  assert(valid(prototype),'native extra-unit prototype missing')
  local button=creator:Create(owner,prototype:GetClass(),owner)
  assert(valid(button),'native extra-unit creation failed')
  button.CreatureInfoName=FName(EXTRA_NAMES[row.id])
  button.SizeOfIcon=prototype.SizeOfIcon
  button.Toggle=true
  button.HideSizeStripes=prototype.HideSizeStripes
  button:ApplyStyleBasedOnCreatureName()
  local panel=session.widget.ExtraUnitsUniformGridPanel
  local count=panel:GetChildrenCount()
  panel:AddChildToUniformGrid(button,math.floor(count/8),count%8)
  button.TheButton:SetIsChecked(false)
  return button
 end
 local function compact_extra_grid(session,known)
  local panel=get(session.widget,'ExtraUnitsUniformGridPanel')
  assert(valid(panel),'native extra-unit grid missing')
  local layout=StaticFindObject('/Script/UMG.Default__WidgetLayoutLibrary')
  assert(valid(layout),'native widget layout library missing')
  local position=0
  for index=0,panel:GetChildrenCount()-1 do
   local button=panel:GetChildAt(index)
   if valid(button)and known[ident(button)]and button:IsVisible()and same(button:GetParent(),panel)then
    local slot=layout:SlotAsUniformGridSlot(button)
    assert(valid(slot),'native extra-unit grid slot missing')
    slot:SetRow(math.floor(position/8));slot:SetColumn(position%8)
    position=position+1
   end
  end
 end
 local function collect(session)
  assert(context_alive(session)and valid(session.widget),'expired selection')
  local selected,final={},{}
  for _,row in ipairs(catalog.entries)do
   local button=session.buttons[row.id]
   if valid(button)and not session.available[row.id]then
    local checkbox=get(button,'TheButton')
    local chosen=valid(checkbox)and checkbox:IsChecked()or get(button,'Purchased')==true
    if chosen then selected[row.id]=true end
   end
   for _,pair in pairs(row.skill_pairs or {})do
    for _,field in ipairs(pair)do final[field]=session.widget.ColonySetup[field]end
   end
   if row.variant_field then final[row.variant_field]=session.widget.ColonySetup[row.variant_field]end
  end
  return M.project(catalog,selected,session.initial_skills,final,session.touched,session.available,
   session.variants_touched,session.ctx.dlc_available)
 end
 open=function(parent,base_ctx,on_confirm,on_cancel,options)
  options=options or{}
  assert(enabled and not active,'selection already active')
  assert(valid(parent)and type(base_ctx)=='table'and valid(base_ctx.world),'invalid selection source')
  assert(same(base_ctx.source,parent)and api.validate_request(base_ctx)==true,'request source or identity changed')
  assert(type(base_ctx.allowedFlags)=='table','target mission allowedFlags required')
  assert(base_ctx.story_colony~=nil,'read-only current story colony required')
  assert(type(on_confirm)=='function','selection callback required')
  local owner=base_ctx.controller;assert(valid(owner),'local player controller missing')
  local cls=StaticFindObject(CUSTOM);if not valid(cls)then cls=LoadAsset(CUSTOM)end
  assert(valid(cls),'original CustomColonySetup unavailable')
  if not valid(StaticFindObject(CARD))then LoadAsset(CARD)end
  ensure_hooks(true)
  assert(hooks.custom_graph and hooks.card_graph and hooks.skill_purchase,'native selection hooks unavailable')
  local creator=StaticFindObject('/Script/UMG.Default__WidgetBlueprintLibrary')
  local widget=creator:Create(owner,cls,owner);assert(valid(widget),'native selection widget creation failed')
  local session={parent=parent,ctx=base_ctx,world=base_ctx.world,widget=widget,owner=owner,
   on_confirm=on_confirm,on_cancel=on_cancel,kind=options.kind or'start',key=options.key,
   buttons={},cards={},initial_skills={},initial_variants={},initial_levels={},touched={},variants_touched={},
   available={},original=options.original,options=options,initializing=true}
  active=session
  local ok,err=pcall(function()
   -- Seed only private presentation fields, never copy a whole ColonyData.
   widget.ColonySetup.QueenSpecies=0;widget.ColonySetup.WorkerSpecies=0
   widget.AllowSavedFormicariums=false;widget.LockSpeciesSelection=true
   widget.AllowAllFoodColonies=true;widget.AllowAllMulchColonies=true;widget.AllowAllLeafColonies=true
   widget.DisableQueenAbilities=true
   for _,row in ipairs(catalog.entries)do
    widget.ColonySetup[row.flag]=false
    session.available[row.id]=base_ctx.allowedFlags[row.flag]==true
    if row.variant_field then
     local value=base_ctx.story_colony[row.variant_field]
     assert(type(value)=='boolean','missing initial variant '..row.variant_field)
     session.initial_variants[row.variant_field]=value;widget.ColonySetup[row.variant_field]=value
    end
    if row.upgrade_field then
     local value=base_ctx.story_colony[row.upgrade_field]
     assert(type(value)=='number','missing initial upgrade level '..row.upgrade_field)
     session.initial_levels[row.upgrade_field]=value;widget.ColonySetup[row.upgrade_field]=value
    end
    for _,pair in pairs(row.skill_pairs or{})do
     for _,field in ipairs(pair)do
      local value=base_ctx.story_colony[field];assert(type(value)=='boolean','missing initial skill '..field)
      session.initial_skills[field]=value;widget.ColonySetup[field]=value
     end
    end
   end
   -- Original species/ability dialogs are added at 500 by the native card graph.
   -- Keep this parent below them so their native buttons and delegates work.
   widget:AddToViewport(400)
   -- The dropdown's arrow is a separate Image_323 sibling in Overlay_1.
   -- Remove its dedicated label/dropdown row, not just the combo widget.
   local picker=get(widget,'ColonySpeciesDropdown')
   if valid(picker)then
    local overlay=picker:GetParent()
    if valid(overlay)and fname(overlay:GetFName())=='Overlay_1'then
     local row=overlay:GetParent()
     if valid(row)and fname(row:GetFName())=='HorizontalBox_208'then detach(row)else detach(overlay)end
    end
   end
   for _,key in ipairs({'Queen','Worker','ExplodingTermiteWorkerTopRow','ColonySpeciesDropdown','ColonySpeciesText'})do detach(get(widget,key))end
   detach(get(widget,'Image_323'))
   local known={}
   for _,row in ipairs(catalog.entries)do
    local name=row.widget or NAMES[row.id]or row.id
    local button=get(widget,name)
    if not catalog.is_selectable(row.id,session.ctx.dlc_available)then
     -- Removed supplemental choices remain in the catalog for old saves.
     -- Hide an existing native card and never create an extra replacement.
     detach(button)
    else
     if not valid(button)and EXTRA_NAMES[row.id]then button=make_extra(session,row,creator,owner)end
     assert(valid(button),'native roster control missing: '..row.id)
     session.buttons[row.id]=button;known[ident(button)]=true
     local checkbox=get(button,'TheButton')
     if valid(checkbox)then checkbox:SetIsChecked(false)
     else
      button:SetupButton();strip_numbers(button)
      session.cards[ident(button)]=row.id
     end
     if session.available[row.id]then detach(button)end
    end
   end
   -- Native DLC/identity controls outside the approved catalog are not inputs.
   for _,name in ipairs({'ExplodingAntSoldier','ExplodingAntMajorSoldier','ExplodingTermiteWorker',
    'ExplodingTermiteSoldier','NarrowHeadedRanged','NarrowHeadedAntMelee'})do
    local button=get(widget,name);if valid(button)and not known[ident(button)]then detach(button)end
   end
   widget:RefreshTheColonySetup(false)
   -- Constructor/refresh behavior is not a user skill edit; establish the exact
   -- player baseline after initialization and repaint the original skill icons.
   for field,value in pairs(session.initial_skills)do widget.ColonySetup[field]=value end
   for field,value in pairs(session.initial_variants)do widget.ColonySetup[field]=value end
   for field,value in pairs(session.initial_levels)do widget.ColonySetup[field]=value end
   for id in pairs(session.cards)do
    for _,row in ipairs(catalog.entries)do
     local card=session.buttons[row.id]
     if ident(card)==id then card:SetupButton();strip_numbers(card)end
    end
   end
   compact_extra_grid(session,known)
   walk(widget,function(object,name)
    if name=='TextBlock_108'then object:SetText(text('选择本关额外兵种'))end
   end)
   owner.bShowMouseCursor=true;widget:SetKeyboardFocus()
   if valid(options.original)then options.original:SetVisibility(1)end
   session.initializing=false
  end)
  if not ok then finish(session,false);error(err)end
  return true
 end
 local function confirm()
  local session=active
  if not session or session.submitting then return end
  assert(context_alive(session)and attached(session.widget),'selection context expired')
  local payload=collect(session)
  session.submitting=true
  local ok,accepted,why=pcall(session.on_confirm,payload)
  if not ok or accepted~=true then
   session.submitting=false;report('选择未生效：'..tostring(ok and why or accepted));return
  end
  finish(session,true)
  if session.options.resume then
   local resumed,reason=pcall(session.options.resume,session)
   if not resumed then notify_cancel(session,'native_resume_failed');report(reason)end
  end
 end
 local function request_for(parent,kind)
  local ctx,why=api.get_context(parent,kind)
  if not ctx then return nil,why end
  return ctx,function(payload)return api.submit_flags(ctx,payload)end,
   function(reason)return api.cancel_request(ctx,reason)end
 end
 function control.arm(parent,ctx,on_confirm,on_cancel)
  assert(valid(parent)and is_class(parent,'FormicLevelSetup2_C'),'story level setup required')
  local level_type=tonumber(parent.LevelType)
  if level_type==3 or level_type==6 then return nil,'not_a_playable_mission' end
  if not(level_type==1 or level_type==2 or level_type==5 or ctx.allow_same_world==true)then return nil,'unsupported_level_type'end
  ensure_hooks(true);if not hooks.show_dialog then return nil,'show_dialog_hook_missing'end
  local id,key=ident(parent),fname(parent.StoredLevelKey)
  local record=armed[id]
  if not record or record.key~=key then
   record={parent=parent,key=key,original_choice=parent.IsUnitChoice==true};armed[id]=record
  end
  record.ctx,record.on_confirm,record.on_cancel=ctx,on_confirm,on_cancel
  record.refresh=false
  parent.IsUnitChoice=true
  return true
 end
 function control.arm_restart(menu,ctx,on_confirm,on_cancel)
  assert(valid(menu)and is_class(menu,'InGameMenu_C'),'native in-game menu required')
  restarts[ident(menu)]={parent=menu,ctx=ctx,on_confirm=on_confirm,on_cancel=on_cancel}
  return true
 end
 local function accept_native_unit(parent,unit)
  local record=armed[ident(parent)]
  if not record or record.pending or active or not is_class(unit,'UnitSelect_C')then return end
  assert(fname(parent.StoredLevelKey)==record.key,'selected mission changed')
  unit:SetVisibility(1)
  record.pending=unit
 end
 local function begin_pending(record)
  local unit=record.pending;record.pending=nil
  if not valid(unit)or not attached(unit,true)or not valid(record.parent)then return end
  if record.refresh then
   local ctx,accept,cancel=request_for(record.parent,'start')
   if not ctx then
    unit:RemoveFromParent()
    if record.on_cancel then record.on_cancel('context_unavailable')end
    error('current mission selection context unavailable')
   end
   record.ctx,record.on_confirm,record.on_cancel=ctx,accept,cancel
  end
  local function resume(session)
   local parent=record.parent
   if not valid(parent)then return end
   if record.original_choice then
    if valid(unit)then unit:SetVisibility(0);unit:SetKeyboardFocus()end
    record.awaiting={unit=unit,ctx=record.ctx,on_cancel=record.on_cancel}
   else
    local level_type=tonumber(parent.LevelType)
    if level_type==0 or level_type==4 then
     local selector=get(parent,'ParentWidget')
     if is_class(selector,'FormicariumLevelSelect2_C')and same(get(selector,'CurrentlyActiveWidget'),unit)then
      -- Native RemoveCurrentDialogue closes one layer per call. Detaching the
      -- placeholder alone leaves its reference set, so the real launch would
      -- consume its close call on that stale child and leave the level menu up.
      -- ForceClose consumes our child via the native path and clears the ref;
      -- LaunchLevelEvent's own close then removes the menu and restores input.
      selector:ForceClose()
      assert(not same(get(selector,'CurrentlyActiveWidget'),unit),'native selection child did not close')
     end
    end
    if valid(unit)then unit:RemoveFromParent()end
    parent.IsUnitChoice=false
    parent:SetupAndPlayLevel(0)
    if valid(parent)then parent.IsUnitChoice=true end
   end
  end
  local cancelled=false
  local function cancel(reason)
   if cancelled then return end;cancelled=true
   if valid(unit)then unit:RemoveFromParent()end
   if valid(record.parent)and valid(record.parent.PlayButton)then record.parent.PlayButton:SetKeyboardFocus()end
   if record.on_cancel then record.on_cancel(reason)end
  end
  local ok,why=pcall(open,record.parent,record.ctx,record.on_confirm,cancel,{original=unit,key=record.key,resume=resume,kind='start'})
  if not ok then cancel('open_failed');error(why)end
 end
 local function restart_prompt(menu,expected_dialog,expected_hud)
  if active then return end
  if not is_class(menu,'InGameMenu_C')then return end
  local hud=get(menu,'TugOfWarParent')
  local original=get(hud,'CurrentlyActiveDialogue')
  -- Native SwapCurrentDialogue removes the old InGameMenu from the viewport;
  -- its restart delegates still own it. Validate the exact visible replacement
  -- dialog and HUD instead of requiring that removed menu to remain attached.
  if not same(hud,expected_hud)or not same(original,expected_dialog)or not attached(hud)then return end
  if not is_class(original,'DialogueTwoOptionsWithTitle_C')or not attached(original)then return end
  if not same(menu:GetWorld(),original:GetWorld())then return end
  local ctx,accept,cancel=request_for(menu,'restart')
  if not ctx then return end
  control.arm_restart(menu,ctx,accept,cancel)
  local record=restarts[ident(menu)]
  original:SetVisibility(1)
  local cancelled=false
  local function cancelled_restart(reason)
   if cancelled then return end;cancelled=true
   if valid(original)then original:RemoveFromParent()end
   if valid(menu)then menu:RestartRightOption()end
   if record.on_cancel then record.on_cancel(reason)end
  end
  local ok,why=pcall(open,menu,record.ctx,record.on_confirm,cancelled_restart,{original=original,kind='restart',resume=function()
   if valid(original)then original:SetVisibility(0);original:SetKeyboardFocus()end
   record.awaiting=original
  end})
  if not ok then cancelled_restart('open_failed');error(why)end
 end
 local function hook(name,path,callback)
  if hooks[name]then return end
  if not valid(StaticFindObject(path))then hooks_ready=false;return end
  local ok,pre,post=pcall(RegisterHook,path,safe(name,callback))
  if ok and type(pre)=='number'and type(post)=='number'then
   hooks[name]={path,pre,post}
   -- Catch a setup widget that was constructed before its lazy-loaded hook.
   if name=='story_setup'then discovery_requested=true;next_discovery=0 end
  else
   hooks_ready=false
   if not ok then once(name,pre)end
  end
 end
 ensure_hooks=function(immediate)
  if hooks_ready then return end
  local now=clock()
  if not immediate and now<next_hook_retry then return end
  next_hook_retry=now+1
  hooks_ready=true
  hook('custom_graph',CUSTOM..':ExecuteUbergraph_CustomColonySetup',function(receiver,entry)
   -- Blueprint post hooks hold the Blueprint callback mutex. Starting a level
   -- here can enter SaveFormicarium's native Lua hook and deadlock that mutex.
   -- Coalesce clicks; the game-thread tick owns submission and native resume.
   if active and not active.submitting and same(unbox(receiver),active.widget)
    and tonumber(unbox(entry))==12862 then confirm_requested=active end
  end)
  hook('card_graph',CARD..':ExecuteUbergraph_SpeciesEntryCustomColony',function(receiver,entry)
   if not active or active.initializing then return end
   local offset=tonumber(unbox(entry))
   local side=SKILL_ENTRIES[offset]
   local id=active.cards[ident(unbox(receiver))]
   if side then mark_skill_edit(unbox(receiver),side)end
   -- Native SpeciesVariantSelect completed and Purchase already wrote the flag.
   if offset==4582 and id and catalog.by_id[id].variant_field then active.variants_touched[id]=true end
  end)
  -- Native delegate dispatch can execute a card's event wrapper without firing
  -- the ExecuteUbergraph hook. Observe the actual named choices as well.
  for name,side in pairs({AbilitySelectedLeft='left',CustomEventAbilitySelectedRight='right',
   ExitToAdaptationsAndClearLeftAbility='left',ExitToAdaptationsAndClearRightAbility='right'})do
   hook('skill_'..name,CARD..':'..name,function(receiver)mark_skill_edit(unbox(receiver),side)end)
  end
  hook('skill_purchase',CARD..':PurchaseAbility',function(receiver,unpurchase,right_side)
   -- Only an explicit ability option calls this with Unpurchase=false. Species
   -- Purchase and SetupButton do not call it. Native left-clear incorrectly
   -- passes RightSide=true, so its named clear wrapper above owns that case.
   if unbox(unpurchase)~=false then return end
   local right=unbox(right_side)
   if type(right)=='boolean'then mark_skill_edit(unbox(receiver),right and'right'or'left')end
  end)
  hook('variant_choice',CARD..':SelectionCompleted',function(receiver)
   local id=skill_card_id(unbox(receiver))
   if id and catalog.by_id[id].variant_field then active.variants_touched[id]=true end
  end)
  hook('show_dialog',STORY..':ShowDialog',function(receiver,content)
   accept_native_unit(unbox(receiver),unbox(content))
  end)
  hook('story_setup',STORY..':Setup',function(receiver)
   local parent=unbox(receiver)
   if valid(parent)then
    local ctx,accept,cancel=request_for(parent,'start')
    if ctx then
     -- Setup has just populated the genuine native choice flag for this level.
     local previous=armed[ident(parent)]
     if previous then previous.original_choice=parent.IsUnitChoice==true end
     if control.arm(parent,ctx,accept,cancel)then armed[ident(parent)].refresh=true end
    end
   end
  end)
  hook('story_graph',STORY..':ExecuteUbergraph_FormicLevelSetup2',function(receiver,entry)
   local record=armed[ident(unbox(receiver))]
   if record and tonumber(unbox(entry))==5243 then record.awaiting=nil end
  end)
  hook('restart_graph',MENU..':ExecuteUbergraph_InGameMenu',function(receiver,entry)
   local menu,offset=unbox(receiver),tonumber(unbox(entry))
   if offset==16206 then
    -- Context loading and widget creation may enter native Lua hooks. Record
    -- only references while the Blueprint callback mutex is held.
    local hud=get(menu,'TugOfWarParent')
    restart_requested={menu=menu,hud=hud,dialog=get(hud,'CurrentlyActiveDialogue')}
   elseif offset==19239 then
    if restart_requested and same(restart_requested.menu,menu)then restart_requested=nil end
    local record=restarts[ident(menu)];if record then record.awaiting=nil end
   end
  end)
 end
 function control.open(parent,ctx,on_confirm,on_cancel)return open(parent,ctx,on_confirm,on_cancel)end
 function control.cancel(reason)
  confirm_requested=nil
  restart_requested=nil
  if not active then return false end
  local session=active;finish(session,true);notify_cancel(session,reason or'cancelled');return true
 end
 function control.get_active()return active end
 function control.preview()return active and collect(active)or nil end
 function control.tick()
  if not enabled then return end
  ensure_hooks()
  if escape_requests>0 then escape_requests=0;control.cancel('escape')end
  if active and(not context_alive(active)or not attached(active.widget)
   or(active.original and not attached(active.original,true)))then control.cancel('context_expired')end
  local restart=restart_requested;restart_requested=nil
  if restart and not active then
   local ok,why=pcall(restart_prompt,restart.menu,restart.dialog,restart.hud)
   if not ok then report('restart: '..tostring(why))end
  end
  local requested=confirm_requested;confirm_requested=nil
  if requested and active==requested then
   local ok,why=pcall(confirm)
   if not ok then report('confirm: '..tostring(why))end
  end
  for id,record in pairs(armed)do
   if not valid(record.parent)then armed[id]=nil
   elseif fname(record.parent.StoredLevelKey)~=record.key then armed[id]=nil
   elseif record.pending and not active then
    local ok,err=pcall(begin_pending,record)
    if not ok then report(err);if record.on_cancel then pcall(record.on_cancel,'open_failed')end end
   elseif record.awaiting and not awaiting_dialog_attached(record.awaiting.unit)then
    if record.awaiting.on_cancel then pcall(record.awaiting.on_cancel,'native_choice_cancelled')end
    record.awaiting=nil
   end
  end
  for id,record in pairs(restarts)do
   if not valid(record.parent)then restarts[id]=nil
   elseif record.awaiting and not awaiting_dialog_attached(record.awaiting)then
    if record.on_cancel then pcall(record.on_cancel,'restart_confirmation_cancelled')end
    record.awaiting=nil
   end
  end
  -- Setup/ShowDialog hooks handle subsequent native windows immediately.
  -- A full UObject scan is only a bootstrap/lazy-hook fallback, never battle
  -- maintenance. Retry a visible window whose game context is still loading.
  if not active and discovery_requested and clock()>=next_discovery then
   discovery_requested=false;next_discovery=clock()+1
   for _,parent in ipairs(FindAllOf('FormicLevelSetup2_C')or{})do
    if valid(parent)and attached(parent)then
     local record=armed[ident(parent)]
     if not record or record.key~=fname(parent.StoredLevelKey)then
      local ctx,accept,cancel=request_for(parent,'start')
      if ctx and control.arm(parent,ctx,accept,cancel)then armed[ident(parent)].refresh=true end
      if not ctx then discovery_requested=true end
     end
    end
   end
  end
 end
 function control.stop()
  control.cancel('disabled');enabled=false
  for _,record in pairs(armed)do
   if valid(record.pending)then record.pending:RemoveFromParent()end
   if record.awaiting and valid(record.awaiting.unit)then record.awaiting.unit:RemoveFromParent()end
   if(record.pending or record.awaiting)and record.on_cancel then pcall(record.on_cancel,'disabled')end
   if valid(record.parent)and fname(record.parent.StoredLevelKey)==record.key then record.parent.IsUnitChoice=record.original_choice end
  end
  for _,record in pairs(restarts)do
   if valid(record.awaiting)then record.awaiting:RemoveFromParent()end
   if record.awaiting and record.on_cancel then pcall(record.on_cancel,'disabled')end
  end
  for _,data in pairs(hooks)do pcall(UnregisterHook,data[1],data[2],data[3])end
 end
 if RegisterKeyBind and Key and Key.ESCAPE then RegisterKeyBind(Key.ESCAPE,function()escape_requests=escape_requests+1 end)end
 ensure_hooks(true)
 return control
end
return M
