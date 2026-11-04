-- Native damage notification for captured units. No periodic health floor,
-- damage estimate, actor scan in damage callbacks, or recursive KillCreature.
local M={hook='/Game/Blueprints/LevelSetup/LevelMethods_BP.LevelMethods_BP_C:PassToUserWidgets'}
local function safe(fn)local ok,v=pcall(fn);if ok then return v end end
local function unbox(v)local n=v~=nil and safe(function()return v:get()end);return n~=nil and n or v end
local function finite(n)return type(n)=='number'and n==n and n~=math.huge and n~=-math.huge end
local function number(v)local n=tonumber(unbox(v));return finite(n)and n or nil end
local function each(a,fn)
 assert(a~=nil,'slave_medical_native_array_missing')
 if type(a)=='table'and type(a.GetArrayNum)~='function'then
  assert(#a<=512,'slave_medical_native_array_large');for _,v in ipairs(a)do fn(unbox(v))end
 else
  local count=number(a:GetArrayNum());assert(count and count>=0 and count%1==0 and count<=512,'slave_medical_native_array_invalid')
  for i=1,count do fn(unbox(a[i]))end
 end
end

function M.install(options)
 assert(type(options)=='table'and type(options.native)=='table','slave_medical_native_required')
 assert(type(options.get_context)=='function'and type(options.adapter)=='table','slave_medical_context_required')
 local native,adapter=options.native,options.adapter
 for _,method in ipairs({'describe_state','can_begin_medical','medical_begin','medical_rollback'})do
  assert(type(adapter[method])=='function','slave_medical_adapter_required:'..method)
 end
 local stopped=false
 local watched,busy,reported={},{},{}
 local cached_world,receiver=nil,nil
 local hook_pre,hook_post,hook_attempt_world=nil,nil,nil
 local hook_attempts_in_world=0
 local capture_handler,skill_damage_handler
 local stats={registered=0,callbacks=0,rescued=0,rejected=0,native_priority_skips=0,failures=0,last_error=nil,hook_registered=false,hook_attempts=0}
 local api={}
 local function failure(err)
  err=tostring(err);stats.failures=stats.failures+1;stats.last_error=err
  if not reported[err]then reported[err]=true;if options.log then pcall(options.log,'[SlaveMedical] '..err)end end
  return nil,err
 end
 local function valid(c)return c~=nil and safe(function()return native.valid_object(c)end)==true end
 local function key(c)
  if not valid(c)then return nil end
  local address=safe(function()return c:GetAddress()end)
  return address~=nil and tostring(address)or nil
 end
 local function signature(c)return valid(c)and safe(function()return c:GetFullName()end)or nil end
 local function context()
  local c=options.get_context()
  local gs=type(c)=='table'and(c.gs or c.game_state)or nil
  if not valid(gs)then return nil end
  return c,gs,native.world_id(gs)
 end
 local function native_rescue_has_priority(c,hp)
  local protected=false
  each(c.Effects,function(e)
   if number(e.Type)==30 and(number(e.Damage)or 0)>0 then protected=true end
  end)
  if protected then return true end
  local maximum=number(c.FullHealth)
  local layer,colony=number(c.ColonyLocation),number(c.ColonyID)
  each(c.AbilityList,function(a)
   local trigger,charges,usage=number(a.Trigger),number(a.Charges),number(a.UsageLocation)
   if charges==nil or charges==0 or(trigger~=2 and trigger~=3)then return end
   local at_location=usage==0 or(usage==1 and layer==-1)or(usage==2 and layer and layer>=0)
    or(usage==3 and colony and colony>=0 and layer==colony)
   if not at_location then return end
   if trigger==3 then
    local threshold=number(a.TriggerThreshold)
    if not maximum or maximum<=0 or not threshold or hp/maximum>threshold then return end
   end
   -- Native hurt processing runs AFTER OnTakeAnyDamage. A ready original
   -- FireAntLastStand must apply its own floor/heal first. Unknown immediate
   -- hurt-heal variants are also left to their original code, not suppressed.
   each(a.Effects,function(e)
    local kind,amount=number(e.Type),number(e.Damage)
    if amount and amount>0 and(kind==30 or kind==14 or kind==23 or kind==36)then protected=true end
   end)
  end)
  return protected
 end
 local function find_receiver(ctx,world)
  if cached_world~=world then
   watched={};busy={};receiver=nil;cached_world=world
  end
  if valid(receiver)and native.world_id(receiver)==world then return receiver end
  -- Discovery is only on registration/restore, never per frame or per hit.
  -- gs.LevelMethods is a TrivialObject binding in this build; resolve the
  -- actual Blueprint instance rather than invoking that unsupported wrapper.
  if type(options.find_receiver)=='function'then receiver=options.find_receiver(ctx,world)
  else
   receiver=FindFirstOf('LevelMethods_BP_C')
   if not valid(receiver)or native.world_id(receiver)~=world then
    receiver=nil
    local list=FindAllOf('LevelMethods_BP_C')or{}
    assert(#list<=128,'slave_medical_receiver_list_too_large')
    for _,candidate in ipairs(list)do
     if valid(candidate)and native.world_id(candidate)==world then receiver=candidate;break end
    end
   end
  end
  assert(valid(receiver)and native.world_id(receiver)==world,'slave_medical_receiver_missing')
  return receiver
 end
 local function ensure_hook(world)
  if options.register_hooks==false or stats.hook_registered then return true end
  if hook_attempt_world~=world then hook_attempt_world=world;hook_attempts_in_world=0 end
  if hook_attempts_in_world>=3 then return nil,'slave_medical_hook_retry_limit'end
  hook_attempts_in_world=hook_attempts_in_world+1;stats.hook_attempts=stats.hook_attempts+1
  -- The Blueprint UFunction does not exist at mod startup in the main menu.
  -- Only register after find_receiver has resolved a live LevelMethods actor.
  -- These bounded attempts happen on slave observation, never on a frame poll.
  local register=options.register_hook or RegisterHook
  local ok,pre,post=pcall(register,M.hook,function(context,victim,damage,kind,instigator,causer)
   api.on_damage(context,victim,damage,kind,instigator,causer)
  end)
  if not ok or pre==nil then return nil,'slave_medical_hook_failed:'..tostring(pre)end
  hook_pre,hook_post=pre,post;stats.hook_registered=true
  return true
 end
 local function watch(c,ctx,world,kind)
  local id=key(c);local full=signature(c);assert(id and type(full)=='string','slave_medical_identity_missing')
  local target=find_receiver(ctx,world)
  local hooked,hook_error=ensure_hook(world);assert(hooked,hook_error)
  if watched[id]and watched[id].signature==full then watched[id][kind]=true;return false end
  local row={creature=c,signature=full,world=world};row[kind]=true;watched[id]=row
  local bound,err=pcall(function()target:RegisterCreatureForHealthDisplay(c)end)
  if not bound then watched[id]=nil;error(err)end
  stats.registered=stats.registered+1;return true
 end
 function api.set_capture_handler(fn)
  assert(fn==nil or type(fn)=='function','slave_capture_handler_invalid')
  capture_handler=fn;return true
 end
 function api.set_skill_damage_handler(fn)
  assert(fn==nil or type(fn)=='function','skill_damage_handler_invalid')
  skill_damage_handler=fn;return true
 end
 function api.watch_skill_damage(c)
  local ok,result=pcall(function()
   if stopped or not valid(c)then return false end
   local ctx,gs,world=context()
   if not gs or native.world_id(c)~=world or native.is_owned(c,gs)~=true or(number(c.Health)or 0)<=0 then return false end
   return watch(c,ctx,world,'skill')~=nil
  end)
  if not ok then return failure(result)end;return result
 end
 function api.watch_capture(c)
  local ok,result=pcall(function()
   if stopped or not valid(c)then return false end
   local ctx,gs,world=context()
   if not gs or native.world_id(c)~=world or(number(c.Health)or 0)<=0 then return false end
   watch(c,ctx,world,'capture');return true
  end)
  if not ok then return failure(result)end;return result
 end
 function api.unwatch_capture(c)
  local id=key(c);local row=id and watched[id]
  if row and row.signature==signature(c)then row.capture=nil end
  return true
 end
 function api.has_native_rescue_priority(c,hp)return native_rescue_has_priority(c,hp)end
 function api.observe(c)
  local ok,result=pcall(function()
   if stopped then return false end
   local id=key(c);if not id then return false end
   local ctx,gs,world=context()
   if not gs or native.world_id(c)~=world or native.is_owned(c,gs)~=true then return false end
   local state=adapter.describe_state(c)
   if type(state)~='table'or(state.state~='slave'and state.state~='wounded')then return false end
   return watch(c,ctx,world,'medical')
  end)
  if not ok then return failure(result)end;return result
 end
 function api.on_damage(actual_receiver,victim,damage,damage_type,instigator,causer)
  if stopped then return false end
  victim=unbox(victim);actual_receiver=unbox(actual_receiver)
  local id=key(victim);local row=id and watched[id]
  if not row or not(row.medical or row.capture or row.skill)or busy[id]then return false end
  local original_hp,attempted=nil,false
  local ok,result=pcall(function()
   if signature(victim)~=row.signature or not valid(actual_receiver)or not valid(receiver)
    or actual_receiver:GetAddress()~=receiver:GetAddress()then return false end
   local _,gs,world=context()
   if not gs or world~=cached_world or row.world~=world or native.world_id(victim)~=world then return false end
   stats.callbacks=stats.callbacks+1
   if row.skill and skill_damage_handler then
    local rescued,why=skill_damage_handler(victim,number(damage),unbox(damage_type),unbox(causer),unbox(instigator))
    if rescued==true then return true end
    if rescued==nil and why then failure(why)end
   end
   if row.capture and capture_handler then
    local captured,why=capture_handler(victim,number(damage),unbox(damage_type),unbox(causer),unbox(instigator))
    if captured==true then return true end
    if captured==nil and why then failure(why)end
   end
   if not row.medical or native.is_owned(victim,gs)~=true then return false end
   original_hp=number(victim.Health)
   -- Native TakeDamage has already subtracted the actual mitigated damage.
   -- Zero HP is lethal too; negative/positive damage values are not estimates.
   if not original_hp or original_hp>0 then return false end
   local state=adapter.describe_state(victim)
   if type(state)~='table'or state.state~='slave'then return false end
   if native_rescue_has_priority(victim,original_hp)then stats.native_priority_skips=stats.native_priority_skips+1;return false end
   -- The true flag authorizes checking the pre-death state with HP<=0. It
   -- never relaxes ownership, native slave state, or living-medic requirements.
   if adapter.can_begin_medical(victim,true)~=true then stats.rejected=stats.rejected+1;return false end
   local maximum=number(victim.FullHealth)
   if not maximum or maximum<=0 then return false end
   busy[id]=true;attempted=true
   victim.Health=math.min(1,maximum)
   assert(number(victim.Health)>0,'slave_medical_health_write_failed')
   local rescued,why=adapter.medical_begin(victim)
   assert(rescued==true,why or 'slave_medical_rescue_rejected')
   local committed=adapter.describe_state(victim)
   assert(type(committed)=='table'and committed.state=='wounded','slave_medical_state_not_committed')
   stats.rescued=stats.rescued+1
   return true
  end)
  if attempted and(not ok or result~=true)then
   -- Roll back only this attempted medical transaction. The adapter restores
   -- its flags, brain and tags; restoring the original negative/zero HP lets
   -- the *current* native damage call finish the ordinary death once.
   local rollback_ok,rollback_result,rollback_error=pcall(adapter.medical_rollback,victim)
   if not rollback_ok or rollback_result~=true then
    failure('slave_medical_rollback_failed:'..tostring(rollback_error or rollback_result))
   end
   if valid(victim)and signature(victim)==row.signature then
    local restored,err=pcall(function()victim.Health=original_hp;assert(number(victim.Health)==original_hp,'slave_medical_hp_rollback_readback')end)
    if not restored then failure(err)end
   end
  end
  busy[id]=nil
  if not ok then return failure(result)end
  return result
 end
 function api.forget(c)
  local id=key(c);if id then watched[id]=nil;busy[id]=nil end
 end
 function api.reset_cache()
  watched={};busy={};cached_world=nil;receiver=nil
  hook_attempt_world=nil;hook_attempts_in_world=0
  return true
 end
 function api.status()
  local result={stopped=stopped,watched=0,world=cached_world}
  for k,v in pairs(stats)do result[k]=v end
  for _ in pairs(watched)do result.watched=result.watched+1 end
  return result
 end
 function api.stop()
  stopped=true;watched={};busy={};receiver=nil;capture_handler=nil;skill_damage_handler=nil
  if stats.hook_registered then
   local unregister=options.unregister_hook or UnregisterHook
   local ok,err=pcall(unregister,M.hook,hook_pre,hook_post)
   if not ok then return failure('slave_medical_hook_unregister_failed:'..tostring(err))end
   hook_pre,hook_post=nil,nil;stats.hook_registered=false
  end
  return true
 end
 return api
end
return M
