-- Tier-two player SlaveMaker base adjustment. Called only after native rebuilds
-- and world/birth setup. Optional static preview integration runs through the
-- existing game-thread tick; importing still performs no engine work.
local M={marker='EAA_SlaverBalance_v1',health_delta=10,attack_delta=1.1,
 preview_class='/Game/UI/InGame/CreatureStatList.CreatureStatList_C',
 preview_hook='/Game/UI/InGame/CreatureStatList.CreatureStatList_C:InitialiseDisplayStatsFromData'}
local function safe(f)local ok,v=pcall(f);if ok then return v end end
local function unbox(v)local x=v~=nil and safe(function()return v:get()end);return x~=nil and x or v end
local function name(v)v=unbox(v);return type(v)=='string'and v or v and safe(function()return v:ToString()end)end
local function number(v)local n=tonumber(unbox(v));return n and n==n and math.abs(n)<math.huge and n or nil end
local function equal(a,b)return a and b and math.abs(a-b)<=math.max(1e-5,math.abs(a)*1e-6,math.abs(b)*1e-6)end
local function tags(c)
 local out={};local a=c.Tags
 if type(a)=='table'and type(a.GetArrayNum)~='function'then
  for _,v in ipairs(a)do out[#out+1]=assert(name(v),'balance_tag_unreadable')end
 else
  local n=assert(number(a:GetArrayNum()),'balance_tags_missing');assert(n>=0 and n<=8192,'balance_tags_invalid')
  for i=1,n do out[#out+1]=assert(name(a[i]),'balance_tag_unreadable')end
 end
 return out
end
local function has_marker(a)for _,v in ipairs(a)do if v==M.marker then return true end end;return false end
local function set_tags(c,a)local out={};for i,v in ipairs(a)do out[i]=FName(v)end;c.Tags=out end
function M.install(o)
 assert(type(o)=='table'and type(o.native)=='table'and type(o.get_context)=='function','balance_dependencies_required')
 local native=o.native;local entries,epochs={},{};local stopped=false;local colony_class,active_world
 local control={applied=0,rebuilt=0,errors=0,preview_applied=0,preview_registrations=0};local api={}
 local function valid(c)return c~=nil and safe(function()return native.valid_object(c)end)==true end
 local function key(c)return c~=nil and safe(function()return tostring(c:GetAddress())end)end
 local function fail(e)control.errors=control.errors+1;control.last_error=tostring(e);if o.log then pcall(o.log,'[SlaveMakerBalance] '..tostring(e))end;return nil,tostring(e)end
 local preview_binding,preview_epoch,preview_next,preview_loaded=nil,0,0,false
 local preview_pending,preview_world={},nil
 local function function_key(fn)return valid(fn)and key(fn)..'|'..fn:GetFullName()or nil end
 local function find_preview()return(o.find_function or StaticFindObject)(M.preview_hook)end
 local function retire_preview()
  preview_epoch=preview_epoch+1;preview_pending={}
  local prior=preview_binding;preview_binding=nil
  if prior and function_key(safe(find_preview))==prior.key then
   local ok,e=pcall(o.unregister_hook or UnregisterHook,M.preview_hook,prior.pre,prior.post)
   if not ok then return fail('balance_preview_unregister_failed:'..tostring(e))end
  end
  return true
 end
 local function preview_context()
  local ctx=o.get_context();local gs=ctx and(ctx.gs or ctx.game_state)
  if not valid(gs)then return nil end
  local pc=ctx.pc or ctx.controller or native.get_local_controller(gs)
  if not valid(pc)then return nil end
  local owner=number(pc:GetColonyID());if not owner or owner<0 then return nil end
  local grid=ctx.grid or gs:GetTileGridByColonyID(owner)
  if not valid(grid)or native.is_owned(grid,gs)~=true then return nil end
  return ctx,gs,owner,native.world_id(gs),grid
 end
 local function ensure_preview()
  if o.preview~=true or stopped then return false end
  local now=(o.clock or os.time)();if now<preview_next then return preview_binding~=nil end
  preview_next=now+1
  local ctx,gs,owner,world=preview_context();if not ctx then return false end
  if preview_world and preview_world~=world then preview_pending={}end;preview_world=world
  local fn=find_preview()
  if not valid(fn)and not preview_loaded then
   preview_loaded=true
   local load=o.load_asset or LoadAsset;load(M.preview_class)
   fn=find_preview()
  end
  local identity=function_key(fn)
  if preview_binding and preview_binding.key==identity then return true end
  if preview_binding then local ok,e=retire_preview();assert(ok,e)end
  if not identity then return false end
  local token=preview_epoch
  -- UE4SS invokes the second RegisterHook argument after this Blueprint
  -- function. Its separate third/native-post argument is not invoked here.
  local pre,post=(o.register_hook or RegisterHook)(M.preview_hook,function(receiver,creature_name)
   if stopped or token~=preview_epoch then return end
   local ok,e=pcall(function()
    local widget=unbox(receiver);if not valid(widget)then return end
    local id=key(widget);preview_pending[id]=nil -- Another species reusing this widget cancels old work.
    local species=name(creature_name)
    if not species or species:lower()~='slavemakerant'or widget.LiveStats==true or widget.ShowSimpleInformation==true then return end
    local current,game_state,own,current_world=preview_context()
    if not current or native.world_id(widget)~=current_world then return end
    preview_pending[id]={widget=widget,key=id,full_name=widget:GetFullName(),world=current_world,
     species=species,slot=current.slot,owner=own}
   end)
   if not ok then fail('balance_preview_queue_failed:'..tostring(e))end
  end)
  assert(type(pre)=='number'and type(post)=='number','balance_preview_hook_registration_failed')
  preview_binding={key=identity,pre=pre,post=post};control.preview_registrations=control.preview_registrations+1
  return true
 end
 local function update_preview(job)
  local widget=job.widget;local ctx,gs,owner,world,grid=preview_context()
  if not ctx or world~=job.world or ctx.slot~=job.slot or owner~=job.owner or not valid(widget)
   or key(widget)~=job.key or widget:GetFullName()~=job.full_name or widget.LiveStats==true or widget.ShowSimpleInformation==true
   or native.world_id(widget)~=world then return end
  assert(valid(widget.HealthText),'balance_preview_health_label_missing')
  local default=(o.default_creature or StaticFindObject)('/Script/EotU.Default__Creature')
  assert(valid(default),'balance_preview_default_creature_missing')
  -- GetCreatureStats returns the native stat row, before ApplyColonyBuffs.
  -- Match the latter's actual owned-grid Health entries; do not read a second
  -- copy of the saved allocation or compound a previous displayed result.
  local health_buff=0;local buffs=grid.ColonyBuffs
  local function add_buff(row)
   row=unbox(row)
   local species=row and name(row.CreatureToApply)
   if species and species:lower()=='slavemakerant'and number(row.BuffType)==0 then
    health_buff=health_buff+assert(number(row.BuffValue),'balance_preview_health_buff_invalid')
   end
  end
  if type(buffs)=='table'and type(buffs.GetArrayNum)~='function'then
   for _,row in ipairs(buffs)do add_buff(row)end
  else
   local n=number(buffs:GetArrayNum());assert(n and n>=0 and n<=65536,'balance_preview_buff_array_invalid')
   for i=1,n do add_buff(buffs[i])end
  end
  local health={}
  for level=1,3 do
   local success={};local stats=default:GetCreatureStats(FName('SlaveMakerAnt'),gs,level,owner,success)
   local h=stats and number(stats.Health);assert(h and h>0,'balance_preview_native_health_missing')
   health[level]=h+health_buff+(level==2 and M.health_delta or 0)
   assert(health[level]>0,'balance_preview_adjusted_health_invalid')
  end
  -- Query native colony-adjusted values afresh, never add to the previous text.
  -- Rendering is outside Blueprint hooks to avoid nested callback mutexes.
  local formatted
  if o.format_preview then formatted=o.format_preview(widget,health)
  else
   local out_text,out_zero={},{}
   widget['Form Stat Text'](widget,3,health[1],health[2],health[3],0,false,out_text,out_zero)
   formatted=out_text.ReturnedStatText
   assert(formatted~=nil,'balance_preview_native_formatter_output_missing')
  end
  widget.HealthText:SetText(formatted)
  control.preview_applied=control.preview_applied+1;control.preview_health=health
 end
 function api.tick()
  if o.preview~=true or stopped then return true end
  local ok,e=pcall(function()
   ensure_preview()
   local pending=preview_pending;preview_pending={}
   for _,job in pairs(pending)do update_preview(job)end
  end)
  if not ok then return fail(e)end;return true
 end
 -- Safe even inside deferred-spawn setup: capture identity only. The caller
 -- must not reflect on the unfinished creature until its existing delay ends.
 function api.note_rebuild(c)
  c=unbox(c);local k=key(c);if not k or stopped then return false end
  epochs[k]=(epochs[k]or 0)+1;return true
 end
 local function apply(c)
  if stopped or not valid(c)then return{skipped=true}end
  local cn=name(c.CreatureName)
  if not cn or cn:lower()~='slavemakerant'or number(c.CreatureLevel)~=2 then return{skipped=true}end
  local ctx=o.get_context();local gs=ctx and(ctx.gs or ctx.game_state)
  if not valid(gs)or native.world_id(c)~=native.world_id(gs)or native.is_owned(c,gs)~=true then return{skipped=true}end
  local world=native.world_id(gs)
  if active_world and active_world~=world then entries,epochs={},{} end
  active_world=world
  -- Captured individuals own a frozen cultivation snapshot; never add a new
  -- owner's base adjustment to that saved individual a second time.
  if o.has_snapshot and o.has_snapshot(c)==true then return{skipped=true,preserved_capture=true}end
  local health,full,attack=number(c.Health),number(c.FullHealth),number(c.AttackDamage)
  if not health or health<=0 then return{skipped=true}end
  assert(full and full>0 and attack and attack>=0,'balance_stats_unreadable')
  local k=assert(key(c),'balance_identity_missing');local sig=c:GetFullName()..'|'..tostring(native.world_id(c))
  local prior=entries[k];if prior and prior.signature~=sig then prior=nil end
  local epoch=epochs[k]or 0
  if prior and prior.epoch==epoch then
   -- No native stat rebuild: do not add our delta again after ability-only
   -- notifications, context resets, or another mod's live stat modification.
   return{changed=false,already_applied=true}
  end
  if not valid(colony_class)then colony_class=StaticFindObject('/Script/EotU.ColonyCreature')end
  assert(valid(colony_class),'balance_colony_class_missing')
  local is_colony=c:IsA(colony_class);assert(type(is_colony)=='boolean','balance_class_unknown')
  local scale=is_colony and number(c.SpawnStatScailing)or 1
  assert(scale and scale>0,'balance_spawn_scale_invalid')
  local after_full,after_attack=full+M.health_delta*scale,attack+M.attack_delta*scale
  local before_tags=tags(c);local marked=has_marker(before_tags)
  -- Existing injured units retain current HP. The persistent marker prevents
  -- an injured 80/90 saved unit from looking like a new 80/80 hatch after load.
  local after_health=health
  if not marked and not prior and equal(health,full)then after_health=after_full end
  local next_tags={};for i,v in ipairs(before_tags)do next_tags[i]=v end
  if not marked then next_tags[#next_tags+1]=M.marker end
  local ok,err=pcall(function()
   c.FullHealth=after_full;c.AttackDamage=after_attack
   if after_health~=health then c.Health=after_health end
   if not marked then set_tags(c,next_tags)end
   assert(equal(number(c.FullHealth),after_full)and equal(number(c.AttackDamage),after_attack)
    and equal(number(c.Health),after_health)and has_marker(tags(c)),'balance_readback_failed')
  end)
  if not ok then
   local restored=pcall(function()c.FullHealth=full;c.AttackDamage=attack;c.Health=health;set_tags(c,before_tags)end)
   local checked=restored and equal(number(c.FullHealth),full)and equal(number(c.AttackDamage),attack)and equal(number(c.Health),health)
   error(tostring(err)..'; rollback_verified='..tostring(checked))
  end
  entries[k]={creature=c,signature=sig,epoch=epoch,full=after_full,attack=after_attack,
   full_base=full,attack_base=attack,world=native.world_id(c)}
  control.applied=control.applied+1;if prior then control.rebuilt=control.rebuilt+1 end
  return{changed=true,full_health=after_full,attack_damage=after_attack,health=after_health,scale=scale}
 end
 function api.apply(c)local ok,v=pcall(apply,unbox(c));if not ok then return fail(v)end;return v end
 -- Same-world skill/context refreshes must keep our decoration ledger. Only
 -- expired objects/worlds are discarded; native rebuild epochs remain exact.
 function api.reset_cache()
  local ctx=o.get_context();local gs=ctx and(ctx.gs or ctx.game_state)
  local world=valid(gs)and native.world_id(gs)or nil
  if world and active_world and active_world~=world then entries,epochs={},{} end
  if world then active_world=world end
  if preview_world and world~=preview_world then preview_pending={}end
  preview_world=world
  for k,r in pairs(entries)do
   if not valid(r.creature)or(world and r.world~=world)then entries[k]=nil;epochs[k]=nil end
  end
  return true
 end
 function api.stop()
  local retired,why=retire_preview();if not retired then return nil,why end
  for _,r in pairs(entries)do
   local c=r.creature
   if valid(c)and number(c.CreatureLevel)==2 and equal(number(c.FullHealth),r.full)and equal(number(c.AttackDamage),r.attack)then
    local ok,e=pcall(function()c.FullHealth=r.full_base;c.AttackDamage=r.attack_base;c.Health=math.min(c.Health,r.full_base)end)
    if not ok then return fail(e)end
   end
  end
  stopped=true;entries,epochs={},{};return true
 end
 function api.status()local out={};for k,v in pairs(control)do out[k]=v end;out.stopped=stopped;out.preview_registered=preview_binding~=nil;return out end
 return api
end
return M
