-- Native skill cards and native choice/confirmation dialogs for custom skills.
-- This module owns presentation only; callbacks own payment and persistence.
local M = {}
local HOME='/Game/UI/InGame/TechTree/SpeciesEntry.SpeciesEntry_C'
local ROSTER='/Game/UI/InGame/TechTree/SpeciesEntryCustomColony.SpeciesEntryCustomColony_C'
local OPTIONS='/Game/UI/InGame/TechTree/AbilityOptionSelect.AbilityOptionSelect_C'
local CONFIRM='/Game/UI/InGame/TechTree/PurchaseConfirm.PurchaseConfirm_C'
local ICON_BASE='/Game/UI/InGame/TechTree/AbilityImages/'
M.options={
 left={
  {id='recovery',title='快速恢复',description='回跳时的生命恢复量提高100%（变为原来的2倍）。',icon='fast_recovery'},
  {id='invulnerable',title='暂避锋芒',description='受到致命伤害且回跳不在冷却时，保留1点生命，立即回跳并获得1.5秒无敌。与回跳共用冷却；回跳冷却期间不会保命。',icon='AbilitySelf_Preservation'},
 },
 right={
  {id='evasion',title='危险回避',description='回跳的冷却时间减少40%。',icon='AbilityEvasive'},
  {id='reward',title='捕鼠夹',description='回跳后的下一次攻击造成自身攻击力200%（2倍）的伤害。',icon='AbilityDangerous'},
 },
}
M.ids={'TrapjawAnt','SlaveMaker'}
M.species={
 TrapjawAnt={title='大颚猛蚁',portrait='UI_Creature_TrapJaw_Square_Icon',prefix='EAA_Trapjaw_',options=M.options},
 SlaveMaker={title='奴隶制造者兵蚁',portrait='UI_Creature_FormicaSanguinea_SlaveMaker_Square_Icon',prefix='EAA_SlaveMaker_',
  summary='二阶起，打出致命一击时，有25%的概率将可俘虏敌人击晕。运至女王身旁后可转化为奴隶。',
  options={
   left={
    {id='special_master',title='特调奴隶主',description='二阶及以上时，致命一击对可俘虏敌人的击晕概率由25%提高至50%。',icon='AbilityCrippling'},
    {id='follow_step',title='强敌俘获',description='三阶及以上时，打出致命一击有25%的概率将可俘虏的中型生物击晕。',icon='AbilitySharp'},
   },
   right={
    {id='overseer_drill',title='监工督战',description='本单位存活时，附近友方奴隶的攻击速度提高15%。同类加成不叠加。',icon='AbilityRoyal_Decree'},
    {id='overseer_haul',title='协同搬运',description='本单位存活时，附近友方奴隶的负重移动速度提高15%（搬运物品或单位时）。同类加成不叠加。',icon='AbilityNimble'},
   },
  }},
}
function M.supports(id)return M.species[id]~=nil end
function M.definition(id)return M.species[id]end
function M.copy_choices(value)
 local result={}
 for _,id in ipairs(M.ids)do local sides=value and value[id]or{};result[id]={left=sides.left or'none',right=sides.right or'none'}end
 return result
end
function M.install(api)
 local valid=assert(api.valid_object)
 local control,bindings,hooks,icons,focus_guards,skill_slots={},{},{},{},{},{}
 local active,enabled=nil,true
 local function get(o,k)if not valid(o)then return nil end;local ok,v=pcall(function()return o[k]end);return ok and v or nil end
 local function unbox(v)local ok,x=pcall(function()return v:get()end);return ok and x or v end
 local function identity(o)return valid(o)and tostring(o:GetAddress())or nil end
 local function same(a,b)local id=identity(a);return id~=nil and id==identity(b)end
 local function report(v)pcall(api.log or print,'[CustomSkills UI] '..tostring(v))end
 local function text(s)return StaticFindObject('/Script/Engine.Default__KismetTextLibrary'):Conv_StringToText(tostring(s))end
 local function load(path)
  local value=StaticFindObject(path);if not valid(value)then value=LoadAsset(path)end
  assert(valid(value),'skill UI asset unavailable: '..path);return value
 end
 local function texture(name)
  if not valid(icons[name])then icons[name]=load(ICON_BASE..name..'.'..name)end
  return icons[name]
 end
 local function live(record)
  return enabled and record and bindings[identity(record.card)]==record and valid(record.world)
   and same(record.card:GetWorld(),record.world)and record.options.alive()==true
 end
 local function forget_slots(record)
  for _,id in ipairs(record and record.slot_ids or{})do
   if skill_slots[id]and skill_slots[id].record==record then skill_slots[id]=nil end
  end
 end
 local function skill_overlay(record,key)
  local widget=get(record.card,key)
  if record.options.kind=='roster'and valid(widget)then return widget:GetParent()end
  return widget
 end
 local function track_slots(record)
  record.slot_ids={}
  local keys=record.options.kind=='home'and{'Ability1Hex','Ability2Hex'}or{'Ability1HexLeft','Ability2HexRight'}
  for _,key in ipairs(keys)do
   local id=identity(get(skill_overlay(record,key),'Slot'))
   assert(id,'skill canvas slot unavailable')
   skill_slots[id]={record=record,key=key,native_layer=-1};record.slot_ids[#record.slot_ids+1]=id
  end
  if record.options.kind=='roster'then
   record.main_hex=record.card.MainSpeciesHex:GetParent()
   assert(valid(record.main_hex)and record.main_hex:GetFullName():match('[%.:]MainHexOverlay$'),'native roster main hex unavailable')
   record.roster_hit_canvas=record.main_hex:GetParent()
   assert(valid(record.roster_hit_canvas)
    and same(record.roster_hit_canvas,skill_overlay(record,'Ability1HexLeft'):GetParent())
    and same(record.roster_hit_canvas,skill_overlay(record,'Ability2HexRight'):GetParent()),'native roster skill canvas unavailable')
   record.roster_rest_right=tonumber(skill_overlay(record,'Ability2HexRight').Slot:GetOffsets().Left)
   return
  end
  -- MainHex is a native named child, not an exposed Blueprint property.
  local canvas=record.card.Ability1Hex:GetParent()
  assert(valid(canvas),'skill canvas unavailable')
  for index=0,canvas:GetChildrenCount()-1 do
   local child=canvas:GetChildAt(index)
   if valid(child)and child:GetFullName():match('[%.:]MainHex$')then record.main_hex=child;break end
  end
  assert(valid(record.main_hex),'native main hex unavailable')
 end
 local function invoke(label,fn)
  local ok,err=pcall(fn);if not ok then report(label..': '..tostring(err))end
 end
 local function later(fn)
  ExecuteInGameThreadAfterFrames(1,function()if enabled then invoke('action',fn)end end)
 end
 local function visibility(widget,value)
  if valid(widget)and widget:GetVisibility()~=value then widget:SetVisibility(value)end
 end
 local function home_controls(record,restyle)
  if not live(record)or record.options.kind~='home'or not record.presentation then return end
  if record.restoring then return end
  record.restoring=true
  local ok,err=pcall(function()
  local card=record.card
  -- Native progression assumes level 1-3 and two native purchases. These
  -- supplemental cards have level 0 and independent skill records, so its
  -- visibility gate must not decide whether the actual mouse targets exist.
  card.EntryAbilitiesHidden=false;card.HideImprovmentsButton=false
  local rows=record.definition.options
  card.Ability1Owned=record.presentation.left_choice==rows.left[1].id
  card.Ability3Owned=record.presentation.left_choice==rows.left[2].id
  card.Ability2Owned=record.presentation.right_choice==rows.right[1].id
  card.Ability4Owned=record.presentation.right_choice==rows.right[2].id
  -- Raise the native stack together: skills -1/0 -> 0/1, main 0 -> 1,
  -- plus 1 -> 2. Resting skills stay behind the ant; native hover brings them
  -- to its shared layer, retaining both the original overlap and click order.
  for _,entry in ipairs({{record.main_hex,1},{get(card,'MinorImprovementsSizeBox'),2}})do
   local slot=get(entry[1],'Slot')
   if valid(slot)and tonumber(slot.ZOrder)~=entry[2]then slot:SetZOrder(entry[2])end
  end
  for _,side in ipairs({'left','right'})do
   local left=side=='left'
   local overlay=get(card,left and'Ability1Hex'or'Ability2Hex')
   local button=get(card,left and'AbilityHexLeft'or'AbilityHexRight')
   local slot=get(overlay,'Slot')
   local owned=skill_slots[identity(slot)]
   local layer=owned and owned.native_layer+1 or 0
   if valid(slot)and tonumber(slot.ZOrder)~=layer then slot:SetZOrder(layer)end
   visibility(overlay,4) -- SelfHitTestInvisible keeps child buttons clickable.
   visibility(button,0)
   if valid(button)and not button:GetIsEnabled()then button:SetIsEnabled(true)end
   for _,key in ipairs(left and{'Ability1HexBase','Ability1Border'}or{'Ability2HexBase','Ability2Border'})do visibility(get(card,key),3)end
   local image=get(card,left and'AbImgLeft'or'AbImgRight')
   local selected=record.presentation[side]
   visibility(image,selected and 3 or 1)
   if restyle and selected and valid(image)then image:SetBrushFromTexture(selected,false);image:SetRenderOpacity(1)end
  end
  local plus,lock=get(card,'MinorImprovementsHex'),get(card,'MinImprovementsLock')
  -- Reapply the game's own active plus style, independently of skill ownership.
  local locked=valid(lock)and lock:GetVisibility()~=1 and lock:GetVisibility()~=2
  if valid(plus)then
   if restyle or locked or not plus:GetIsEnabled()then plus:SetStyle(card.LevelButtonActive)end
   if not plus:GetIsEnabled()then plus:SetIsEnabled(true)end
  end
  visibility(get(card,'MinorImprovementsSizeBox'),0);visibility(plus,0)
  visibility(lock,1);visibility(get(card,'Plus'),3)
  end)
  record.restoring=false
  if not ok then error(err)end
 end
 local function queue_home_controls(record)
  if not live(record)or record.options.kind~='home'or record.restore_queued or record.restoring then return end
  record.restore_queued=true
  later(function()
   record.restore_queued=false
   home_controls(record,true)
  end)
 end
 local function roster_controls(record,restyle)
  if not live(record)or record.options.kind~='roster'or not record.presentation or record.restoring then return end
  record.restoring=true
  local ok,err=pcall(function()
   local card=record.card
   local chosen=record.options.is_selected==nil or record.options.is_selected()==true
   local selection_changed=record.roster_selected~=chosen or card.Purchased~=chosen
   card.Purchased=chosen
   if selection_changed then
    -- Native selection paints HexBase/SpeciesHex; replacing this button's
    -- original transparent frame with SpeciesButtonActive covers the portrait.
    card:UpdatePurchaseVisuals(false)
    record.roster_selected=chosen
   end
   -- Keep hover over the native card's whole existing canvas. Otherwise a
   -- pointer entering the expanded right wing starts FocusAnimation at zero,
   -- loses the inward-moving button, and repeatedly enters/leaves the card.
   -- The transparent canvas handles no clicks; child buttons retain priority.
   visibility(record.roster_hit_canvas,0)
   visibility(record.main_hex,4);visibility(card.MainSpeciesHex,0)
   if not card.MainSpeciesHex:GetIsEnabled()then card.MainSpeciesHex:SetIsEnabled(true)end
   local main_slot=get(record.main_hex,'Slot')
   if valid(main_slot)and tonumber(main_slot.ZOrder)~=1 then main_slot:SetZOrder(1)end
   for _,side in ipairs({'left','right'})do
    local left=side=='left'
    local key=left and'Ability1HexLeft'or'Ability2HexRight'
    local button=get(card,key);local overlay=skill_overlay(record,key)
    local slot=get(overlay,'Slot');local owned=skill_slots[identity(slot)]
    local layer=owned and owned.native_layer+1 or 0
    if valid(slot)and tonumber(slot.ZOrder)~=layer then slot:SetZOrder(layer)end
    visibility(overlay,4);visibility(button,0)
    if valid(button)and button:GetIsEnabled()~=chosen then button:SetIsEnabled(chosen)end
    for _,name in ipairs(left and{'Ability1HexBase','Ability1HexBorder'}or{'Ability2HexBase','Ability2HexBorder'})do visibility(get(card,name),3)end
    local image=get(card,left and'Ab1ImgLeft'or'Ab2ImgRight');local selected=record.presentation[side]
    visibility(image,selected and 3 or 2)
    if valid(image)then
     if image:GetIsEnabled()~=chosen then image:SetIsEnabled(chosen)end
     if restyle and selected then image:SetBrushFromTexture(selected,false)end
    end
   end
  end)
  record.restoring=false
  if not ok then error(err)end
 end
 local function queue_roster_controls(record)
  if not live(record)or record.options.kind~='roster'or record.restore_queued or record.restoring then return end
  record.restore_queued=true
  later(function()record.restore_queued=false;roster_controls(record,true)end)
 end
 local function paint(record)
  if not live(record)then return end
  local card,options=record.card,record.options
  local definition=record.definition;local rows=definition.options
  local choices=assert(options.get_choices(),'custom skill choices unavailable')
  card.LeftAbility1Image=texture(rows.left[1].icon)
  card.LeftAbility3Image=texture(rows.left[2].icon)
  card.RightAbility2Image=texture(rows.right[1].icon)
  card.RightAbility4Image=texture(rows.right[2].icon)
  -- Names deliberately do not alias native ColonySetup fields or purchases.
  card.LeftAbility1Name=FName(definition.prefix..rows.left[1].id);card.LeftAbility3Name=FName(definition.prefix..rows.left[2].id)
  card.RightAbility2Name=FName(definition.prefix..rows.right[1].id);card.RightAbility4Name=FName(definition.prefix..rows.right[2].id)
  card.Ability1Owned=choices.left==rows.left[1].id;card.Ability3Owned=choices.left==rows.left[2].id
  card.Ability2Owned=choices.right==rows.right[1].id;card.Ability4Owned=choices.right==rows.right[2].id
  if options.kind=='home'then
   -- Keep the native single-side artwork, including its unpurchased empty
   -- hex. The combined renderer hides both sides at StoredMaxLevel == 0.
   local left=card.Ability1Owned and card.LeftAbility1Image or card.Ability3Owned and card.LeftAbility3Image or nil
   local right=card.Ability2Owned and card.RightAbility2Image or card.Ability4Owned and card.RightAbility4Image or nil
   record.presentation={left=left,right=right,left_choice=choices.left,right_choice=choices.right}
   card:SetAbilityButtonState(left~=nil,card.AbilityHexLeft,card.AbImgLeft,left,false,card.Ability1HexBase,card.Ability1Hex)
   card:SetAbilityButtonState(right~=nil,card.AbilityHexRight,card.AbImgRight,right,false,card.Ability2HexBase,card.Ability2Hex)
   home_controls(record,true)
  else
   record.presentation={left=card.Ability1Owned and card.LeftAbility1Image or card.Ability3Owned and card.LeftAbility3Image or nil,
    right=card.Ability2Owned and card.RightAbility2Image or card.Ability4Owned and card.RightAbility4Image or nil}
   card['Set Ability Button States'](card,card.Ability1Owned,card.Ability3Owned,card.Ability2Owned,card.Ability4Owned,false)
   roster_controls(record,true)
  end
  local chosen=options.is_selected==nil or options.is_selected()==true
  for side,rows in pairs(definition.options)do
   local button=get(card,options.kind=='home'and(side=='left'and'AbilityHexLeft'or'AbilityHexRight')
    or(side=='left'and'Ability1HexLeft'or'Ability2HexRight'))
   if valid(button)then
    button:SetIsEnabled(chosen)
    local title=side=='left'and'左侧技能'or'右侧技能'
    for _,row in ipairs(rows)do if row.id==choices[side]then title=row.title end end
    button:SetToolTipText(text(title..'：'..rows[1].title..' / '..rows[2].title))
   end
  end
 end
 local function release_focus(guard)
  if not guard or focus_guards[guard.id]~=guard then return end
  focus_guards[guard.id]=nil
  if valid(guard.scroll)and valid(guard.world)and same(guard.scroll:GetWorld(),guard.world)
   and get(guard.scroll,'ScrollWhenFocusChanges')==0 then
   guard.scroll:SetScrollWhenFocusChanges(guard.mode)
  end
 end
 local function hold_focus(record)
  if not live(record)then return end
  local scroll=record.options.scroll
  if not valid(scroll)then return end
  local id=identity(scroll);local previous=focus_guards[id]
  local mode=previous and previous.mode or get(scroll,'ScrollWhenFocusChanges')
  if mode==nil then return end
  local guard={id=id,scroll=scroll,world=scroll:GetWorld(),mode=mode,offset=scroll:GetScrollOffset()}
  focus_guards[id]=guard
  scroll:SetScrollWhenFocusChanges(0)
  return guard
 end
 local function finish_focus(guard)
  if not guard or focus_guards[guard.id]~=guard then return end
  -- All synchronous changes here came from removing/refocusing the dialog;
  -- no user input can interleave inside this game-thread callback.
  if valid(guard.scroll)and same(guard.scroll:GetWorld(),guard.world)
   and guard.scroll:GetScrollOffset()~=guard.offset then guard.scroll:SetScrollOffset(guard.offset)end
  -- Slate processes focus scrolling later. Keep NoScroll through two frames,
  -- but never overwrite offsets during that wait: the user may scroll again.
  later(function()later(function()release_focus(guard)end)end)
 end
 local function close(session)
  if active~=session then return end
  local guard=hold_focus(session.record)
  active=nil
  if valid(session.widget)then session.widget:RemoveFromParent()end
  if live(session.record)then
   local parent=session.record.options.parent
   if valid(parent)and same(get(parent,'ActiveOverlayWidget'),session.widget)then parent.ActiveOverlayWidget=nil end
   if session.record.options.on_close then session.record.options.on_close()end
   local card=session.record.card
   local button=get(card,session.record.options.kind=='home'and(session.side=='left'and'AbilityHexLeft'or'AbilityHexRight')
    or(session.side=='left'and'Ability1HexLeft'or'Ability2HexRight'))
   if valid(button)then pcall(function()button:SetKeyboardFocus()end)end
  end
  finish_focus(guard)
 end
 local function make_widget(path,record)
  local cls=load(path)
  local creator=load('/Script/UMG.Default__WidgetBlueprintLibrary')
  local owner=record.card:GetOwningPlayer();assert(valid(owner),'skill dialog owner missing')
  local widget=creator:Create(owner,cls,owner);assert(valid(widget),'skill dialog creation failed')
  return widget
 end
 local function mount(session)
  session.widget:AddToViewport(1100)
  local parent=session.record.options.parent
  if session.record.options.kind=='roster'and valid(parent)then parent.ActiveOverlayWidget=session.widget end
 end
 local function complete(session,value)
  if active~=session or not live(session.record)then close(session);return end
  local ok,why,job=session.record.options.choose(session.side,value)
  if ok~=true then
   report(why or'skill selection refused')
   local label=get(session.widget,'WarningText')or get(session.widget,'Cost')
   if valid(label)then label:SetText(text(tostring(why or'技能选择未保存，请重试。')));label:SetVisibility(0)end
   session.busy=false;return
  end
  if why=='pending'then
   assert(job and type(session.record.options.purchase_result)=='function','skill transaction result unavailable')
   session.transaction=job;session.busy=true
   local label=get(session.widget,'WarningText')or get(session.widget,'Cost')
   if valid(label)then label:SetText(text('正在保存技能选择，请稍候……'));label:SetVisibility(0)end
   for _,key in ipairs({'ConfirmButton','CancelButton','UnitOption1','UnitOption2','Close'})do
    local button=get(session.widget,key);if valid(button)then button:SetIsEnabled(false)end
   end
   return
  end
  if session.record.options.on_complete then session.record.options.on_complete()end
  paint(session.record);close(session)
 end
 local function quote(record,side,value)
  if record.options.kind~='home'then return {cost=0,can_purchase=true}end
  local result=record.options.quote and record.options.quote(side,value)
  assert(type(result)=='table'and type(result.cost)=='number'and result.cost>=0,'skill price unavailable')
  return result
 end
 local function show_confirm(previous,value,price)
  local record,side=previous.record,previous.side
  close(previous)
  if not live(record)then return end
  local widget=make_widget(CONFIRM,record)
  -- The original payment graph is never used. The owned graph hook below
  -- redirects both buttons to our callback before PerformThePurchase runs.
  widget.Cost=0;widget.Species=255;widget.SpecialPurchaseName=FName('EAA_CustomSkill')
  widget.ConfirmButton.ButtonText=text('确定');widget.ConfirmButton.InStyle=widget.PurchaseButtonStyle
  widget.CancelButton.ButtonText=text('取消');widget.CancelButton.InStyle=widget.CancelButtonStyle
  local session={record=record,widget=widget,side=side,value=value,kind='confirm'};active=session
  mount(session)
  widget.ConfirmButton.TextBlock_143:SetText(text('确定'))
  widget.CancelButton.TextBlock_143:SetText(text('取消'))
  widget.ConfirmButton.Button:SetStyle(widget.PurchaseButtonStyle)
  widget.CancelButton.Button:SetStyle(widget.CancelButtonStyle)
  widget.ConfirmButton.Button:SetKeyboardFocus()
  local title=value
  for _,row in ipairs(record.definition.options[side])do if row.id==value then title=row.title end end
  widget.ConfText:SetText(text('花费 '..tostring(price.cost)..' 蚁皇浆选择“'..title..'”？'))
  local choices=record.options.get_choices()
  widget.WarningText:SetText(text(choices[side]~='none'and'将替换本侧已选择的技能，原费用不退还。'or''))
  widget.WarningText:SetVisibility(choices[side]~='none'and 0 or 1)
 end
 local function choose_option(session,index)
  if active~=session or session.busy or not live(session.record)then return end
  local value=assert(session.record.definition.options[session.side][index]).id
  if session.record.options.get_choices()[session.side]==value then close(session);return end
  local price=quote(session.record,session.side,value)
  if price.can_purchase~=true then
   report(price.reason or'蚁皇浆不足')
   -- The native option callback removes its window after broadcasting. Reopen
   -- this owned dialog on the next frame with a visible reason instead of
   -- accepting a selection that the transaction service cannot commit.
   close(session)
   control.open(session.record.card,session.side,price.reason or'蚁皇浆不足')
   return
  end
  if session.record.options.kind=='home'and price.cost>0 then show_confirm(session,value,price)
  else session.busy=true;complete(session,value)end
 end
 function control.open(card,side,notice)
  local record=bindings[identity(card)]
  if not live(record)or not record.definition.options[side]then return nil,'skill_card_expired'end
  if active then return nil,'skill_dialog_open'end
  if record.options.can_open and not record.options.can_open()then return nil,'another_dialog_open'end
  if record.options.is_selected and not record.options.is_selected()then return nil,'species_not_selected'end
  local widget=make_widget(OPTIONS,record)
  local rows=record.definition.options[side]
  widget.UnitOption1NameText=text(rows[1].title);widget.UnitOption2NameText=text(rows[2].title)
  widget.UnitOption1DescriptionText=text(rows[1].description);widget.UnitOption2DescriptionText=text(rows[2].description)
  widget.UnitOption1Image=texture(rows[1].icon);widget.UnitOption2Image=texture(rows[2].icon)
  local price=quote(record,side,rows[1].id)
  -- A selected first option quotes zero; both choices still have a common
  -- purchase price, so show the alternative's quote when necessary.
  if record.options.kind=='home'and price.cost==0 then price=quote(record,side,rows[2].id)end
  widget.CostOfChoice=price.cost;widget.HideCost=record.options.kind~='home'
  local session={record=record,side=side,widget=widget,kind='options'};active=session
  mount(session)
  widget.UnitOption1:SetKeyboardFocus()
  if notice then widget.Cost:SetText(text(notice));widget.Cost:SetVisibility(0)end
  return true
 end
 local function hook(name,path,fn,after)
  if hooks[name]then return end
  assert(valid(StaticFindObject(path)),'skill UI function missing: '..path)
  local pre,post=RegisterHook(path,function(...)local args={...};invoke(name,function()fn(table.unpack(args))end)end,
   function(...)if after then local args={...};invoke(name..' post',function()after(table.unpack(args))end)end end)
  assert(type(pre)=='number'and type(post)=='number','skill UI hook unavailable: '..path)
  hooks[name]={path,pre,post}
 end
 local function ensure_hooks(kind)
  load(OPTIONS);load(CONFIRM)
  hook('options',OPTIONS..':ExecuteUbergraph_AbilityOptionSelect',function(receiver,entry)
   local session=active
   if not session or session.kind~='options'or not same(unbox(receiver),session.widget)then return end
   local offset=tonumber(unbox(entry))
   if offset==1073 or offset==1112 then
    -- Prevent native Close Widget from retiring the UI before the deferred
    -- transaction has finished or an insufficient-funds message is displayed.
    entry:set(1294)
    later(function()choose_option(session,offset==1073 and 1 or 2)end)
   elseif offset==883 or offset==1151 then
    -- Own removal too: native Close Widget would remove the dialog before
    -- our deferred scroll guard has been installed.
    entry:set(1294)
    later(function()close(session)end)
   end
  end)
  hook('confirm',CONFIRM..':ExecuteUbergraph_PurchaseConfirm',function(receiver,entry)
   local session=active
   if not session or session.kind~='confirm'or not same(unbox(receiver),session.widget)then return end
   local offset=tonumber(unbox(entry))
   if offset==234 or offset==162 then
    entry:set(244)
    if not session.busy then session.busy=true;later(function()complete(session,session.value)end)end
   elseif offset==229 or offset==224 or offset==200 then
    entry:set(244)
    if not session.transaction then later(function()close(session)end)end
   end
  end)
  local path=kind=='home'and HOME or ROSTER
  load(path)
  local function queue_home(receiver)
   local record=bindings[identity(unbox(receiver))]
   if record then queue_home_controls(record)end
  end
   -- Shift only the two owned animation tracks by one layer. Cache the last
   -- native value so maintenance retains the final hover state after playback.
   hook('home-skill-layer','/Script/UMG.CanvasPanelSlot:SetZOrder',function(receiver,order)
    local slot=unbox(receiver);local owned=skill_slots[identity(slot)]
    if not owned or not live(owned.record)or owned.record.restoring then return end
    local overlay=skill_overlay(owned.record,owned.key)
    if not same(get(overlay,'Slot'),slot)then return end
    local requested=tonumber(unbox(order))
    if requested==-1 or requested==0 then owned.native_layer=requested;order:set(requested+1)end
   end)
  if kind=='home'then
   -- These native functions also run outside ExecuteUbergraph (focus/hover
   -- bindings and RefreshAfterPurchase). Blueprint POST hooks do not fire on
   -- this UE4SS build: queue a single next-frame repair from PRE, after native
   -- rendering, without sidecar reads or world/asset searches.
   for _,name in ipairs({'Set Ability Button States','SetLevelButtonsStates','LevelButtonVisibilitySwitch',
    'GetImprovementsButtonVisibility','Set Main Hex','SetupButton'})do
    hook('home-render:'..name,path..':'..name,queue_home)
   end
  else
   -- The native card briefly reports Leave/Enter while moving onto its wing.
   -- Coalesce that transition at the native animation call: the Blueprint
   -- graph hook runs after PlayAnimation and cannot prevent its restart.
   hook('roster-hover','/Script/UMG.UserWidget:PlayAnimation',function(receiver,animation,start,loops,mode,speed,restore)
    local card=unbox(receiver);local record=bindings[identity(card)]
    if not live(record)or record.options.kind~='roster'or record.replaying_hover then return end
    local target=unbox(animation)
    if not same(target,get(card,'FocusAnimation'))then return end
    local direction=tonumber(unbox(mode))
    if direction==0 then
     record.hover_epoch=(record.hover_epoch or 0)+1
     local slot=get(skill_overlay(record,'Ability2HexRight'),'Slot')
     local x=valid(slot)and tonumber(slot:GetOffsets().Left)
     -- Popup focus can collapse the native animation independently of the
     -- remembered hover event. A resting card must always be allowed to open.
     local expanded=x and record.roster_rest_right and math.abs(x-record.roster_rest_right)>0.01
     if record.roster_hovered and expanded then animation:set(nil)else record.roster_hovered=true end
    elseif direction==1 then
     local args={unbox(start),unbox(loops),direction,unbox(speed),unbox(restore)}
     animation:set(nil)
     record.hover_epoch=(record.hover_epoch or 0)+1
     local epoch,deadline=record.hover_epoch,os.clock()+0.04
     local function settle()
      if not live(record)or record.hover_epoch~=epoch or card:IsHovered()then return end
      if os.clock()<deadline then later(settle);return end
      record.roster_hovered=false;record.replaying_hover=true
      local ok,err=pcall(function()card:PlayAnimation(target,table.unpack(args))end)
      record.replaying_hover=false
      if not ok then error(err)end
     end
     later(settle)
    end
   end)
   for _,name in ipairs({'Set Ability Button States','SetLevelButtonsStates','Set Main Hex','SetupButton','UpdatePurchaseVisuals'})do
    hook('roster-render:'..name,path..':'..name,function(receiver)
     local record=bindings[identity(unbox(receiver))];if record then queue_roster_controls(record)end
    end)
   end
  end
  hook(kind,path..':ExecuteUbergraph_'..(kind=='home'and'SpeciesEntry'or'SpeciesEntryCustomColony'),function(receiver,entry)
   local card=unbox(receiver);local record=bindings[identity(card)]
   if not live(record)or record.options.kind~=kind then return end
   if kind=='home'then queue_home_controls(record)end
   local offset=tonumber(unbox(entry))
   -- Controller/named wrappers enter the graph at a Jump instruction. A
   -- RegisterHook callback observes the entry only, not its internal target.
   local left=kind=='home'and(offset==11230 or offset==14034)or kind=='roster'and(offset==2705 or offset==17800)
   local right=kind=='home'and(offset==12472 or offset==14039)or kind=='roster'and(offset==4563 or offset==17795)
   if left or right then
    entry:set(kind=='home'and 37032 or 17805)
    later(function()
     if live(record)then
      local opened,reason=control.open(card,left and'left'or'right')
      if not opened then report('skill window not opened: '..tostring(reason))end
     end
    end)
   elseif kind=='roster'and(offset==7114 or offset==17790 or offset==14555)then
    entry:set(17805)
    later(function()if live(record)and not active and record.options.toggle then record.options.toggle();paint(record)end end)
   end
  end)
 end
 function control.bind(card,options)
  assert(valid(card)and(options.kind=='home'or options.kind=='roster'),'invalid custom skill card')
  assert(type(options.alive)=='function'and type(options.get_choices)=='function'and type(options.choose)=='function')
  local definition=assert(M.definition(options.species_id or'TrapjawAnt'),'unknown custom skill species')
  ensure_hooks(options.kind)
  forget_slots(bindings[identity(card)])
  local record={card=card,world=card:GetWorld(),options=options,definition=definition};bindings[identity(card)]=record
  track_slots(record)
  paint(record);return true
 end
 function control.refresh(card)local record=bindings[identity(card)];if record then paint(record)end end
 function control.unbind(card)
  local id=identity(card);local record=bindings[id]
  if active and active.record==record then close(active)end
  forget_slots(record)
  if id then bindings[id]=nil end
 end
 function control.cancel(force)
  if active then if force or not active.transaction then close(active)end;return true end
  return false
 end
 function control.get_active()return active end
 function control.tick()
  if active and not live(active.record)then close(active)end
  if active and active.transaction then
   local session=active
   local result=session.record.options.purchase_result(session.transaction)
   if result and result.phase=='complete'then
    if session.record.options.on_complete then session.record.options.on_complete()end
    paint(session.record);close(session)
   elseif result and result.phase=='failed'then
    session.transaction=nil;session.busy=false
    report(result.error or'skill purchase failed')
    local label=get(session.widget,'WarningText')or get(session.widget,'Cost')
    if valid(label)then label:SetText(text('技能购买未完成，请返回后重试。'));label:SetVisibility(0)end
    local cancel=get(session.widget,'CancelButton');if valid(cancel)then cancel:SetIsEnabled(true)end
   end
  end
  for id,record in pairs(bindings)do
   if not live(record)then forget_slots(record);bindings[id]=nil
   elseif record.options.kind=='home'then home_controls(record,false)
   else roster_controls(record,false)end
  end
 end
 function control.stop()
  control.cancel(true)
  for _,guard in pairs(focus_guards)do release_focus(guard)end
  enabled=false
  for _,data in pairs(hooks)do pcall(UnregisterHook,data[1],data[2],data[3])end
  bindings,hooks,skill_slots={},{},{}
 end
 return control
end
return M
