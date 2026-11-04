-- Supplemental skills operate on validated local creature instances only.
-- Importing this module performs no engine calls, hooks, IO, or scans.
local M = {}
M.invulnerable_effect = 'EAA_Trapjaw_Shelter'
M.evasion_multiplier = 0.6
M.invulnerable_seconds = 1.5

local function safe(fn) local ok,v=pcall(fn);if ok then return v end end
local function unbox(v)
 if v==nil then return nil end
 local inner=safe(function()return v:get()end)
 return inner~=nil and inner or v
end
local function name(v)
 v=unbox(v);if type(v)=='string'then return v end
 return v and safe(function()return v:ToString()end)or nil
end
local function finite(v)return type(v)=='number'and v==v and v~=math.huge and v~=-math.huge end
local function number(v)local n=tonumber(unbox(v));return finite(n)and n or nil end
local function equal(a,b)
 if finite(a)and finite(b)then return math.abs(a-b)<=math.max(1e-6,math.abs(a)*1e-6,math.abs(b)*1e-6)end
 return a==b
end
local function escape(v)
 local s=name(v);return s and s:lower():match('^trapjawescape[123]$')~=nil
end
local function each(array,fn)
 assert(array~=nil,'missing_array')
 if type(array)=='table'and type(array.GetArrayNum)~='function'then
  assert(#array<=128,'array_too_large')
  for i,v in ipairs(array)do fn(i,unbox(v))end
 else
  local count=array:GetArrayNum()
  assert(finite(count)and count>=0 and count%1==0 and count<=128,'invalid_array_length')
  for i=1,count do fn(i,unbox(array[i]))end
 end
end
local function find_ability(creature,wanted)
 local found
 each(creature.AbilityList,function(_,a)
  if name(a.AbilityName)==wanted then assert(not found,'duplicate_escape_ability');found=a end
 end)
 return found
end
local function find_heal(ability)
 local found
 each(ability.Effects,function(_,e)
  local n=name(e.EffectName)
  if n and n:lower():match('^trapjawescapeheal[123]$')then
   assert(not found,'duplicate_escape_heal');found=e
  end
 end)
 return found
end

function M.install(options)
 assert(type(options)=='table'and type(options.native)=='table','skill_runtime_dependencies_required')
 assert(type(options.get_context)=='function'and type(options.get_choices)=='function','skill_runtime_context_required')
 local native=options.native
 local stopped=false
 local cache,pending,reported,hooks={},{},{},{}
 local watching,rescuing,armed,attacking={},{},{},{}
 local geometry_helpers={}
 local control={decorations=0,escapes=0,invulnerable=0,lethal_rescues=0,lethal_failures=0,
  reward_armed=0,reward_attacks=0,fallback_jumps=0,fallback_blocked=0,last_error=nil}
 local api={}
 local function valid(o)return o~=nil and safe(function()return native.valid_object(o)end)==true end
 local function failure(err)
  err=tostring(err);control.last_error=err
  if not reported[err]then
   reported[err]=true;if options.log then pcall(options.log,'[SupplementalSkills] '..err)end
  end
  return nil,err
 end
 local function identity(c)
  if not valid(c)then return nil end
  local a=safe(function()return c:GetAddress()end)
  local n=safe(function()return c:GetFullName()end)
  if a==nil or type(n)~='string'then return nil end
  return tostring(a),n..'|'..tostring(number(c.CreatureLevel))
 end
 local function authorized(c,allow_lethal)
  if stopped or not valid(c)then return nil end
  local n=name(c.CreatureName)
  if not n or n:lower()~='trapjawant'then return nil end
  local health=number(c.Health);if not health or(health<=0 and not allow_lethal)then return nil end
  local ctx=options.get_context()
  local gs=type(ctx)=='table'and(ctx.gs or ctx.game_state)or nil
  if not valid(gs)or native.is_owned(c,gs)~=true then return nil end
  local choices=options.get_choices(c)
  if choices==nil then return nil end
  assert(type(choices)=='table','invalid_skill_choices')
  assert(choices.left==nil or choices.left=='recovery'or choices.left=='invulnerable','invalid_left_skill')
  assert(choices.right==nil or choices.right=='evasion'or choices.right=='reward','invalid_right_skill')
  return choices,ctx,gs
 end
 local function fields(c)
  local result={}
  each(c.AbilityList,function(_,a)
   if escape(a.AbilityName)then
    local id=name(a.AbilityName)
    assert(not result[id..':cd'],'duplicate_escape_ability')
    local cd=number(a.Cooldown);assert(cd,'escape_cooldown_unreadable')
    result[id..':cd']={owner=a,field='Cooldown',value=cd,kind='cooldown'}
    local heal=find_heal(a)
    if heal then
     local value=number(heal.Damage);assert(value,'escape_heal_unreadable')
     result[id..':heal']={owner=heal,field='Damage',value=value,kind='heal'}
    end
   end
  end)
  return result
 end
 local function write_fields(c,changes)
  local applied={}
  local ok,err=pcall(function()
   for _,change in ipairs(changes)do
    applied[#applied+1]=change;change.row.owner[change.row.field]=change.after
   end
   local after=fields(c)
   for _,change in ipairs(changes)do
    assert(after[change.key]and equal(after[change.key].value,change.after),'skill_field_readback:'..change.key)
   end
  end)
  if ok then return true end
  local restored=true
  for i=#applied,1,-1 do
   local change=applied[i]
   local good=pcall(function()change.row.owner[change.row.field]=change.before end)
   restored=restored and good
  end
  local checked=safe(function()return fields(c)end)
  for _,change in ipairs(applied)do
   restored=restored and checked~=nil and checked[change.key]~=nil and equal(checked[change.key].value,change.before)
  end
  error(tostring(err)..'; rollback_verified='..tostring(restored))
 end
 local function restore(c)
  local key,signature=identity(c);if not key then return {changed=false}end
  local old=cache[key]
  if not old or old.signature~=signature then cache[key]=nil;return {changed=false}end
  local current,changes=fields(c),{}
  for id,tracked in pairs(old.fields)do
   local row=current[id]
   if row and equal(row.value,tracked.after)and not equal(row.value,tracked.base)then
    changes[#changes+1]={key=id,row=row,before=row.value,after=tracked.base}
   end
  end
  write_fields(c,changes);cache[key]=nil
  return {changed=#changes>0,writes=#changes}
 end
 -- Always bracket extra.apply with before_attributes/decorate. This strips
 -- only our exact last output, so numeric cultivation keeps its own baseline.
 function api.before_attributes(c)
  local ok,result=pcall(restore,c);if not ok then return failure(result)end;return result
 end
 function api.decorate(c,rebase)
  local ok,result=pcall(function()
   local choices=authorized(c)
   if not choices then
    local id=identity(c);if id then watching[id]=nil;armed[id]=nil end
    return restore(c)
   end
   local key,signature=identity(c);assert(key,'skill_identity_unresolved')
   if choices.left=='invulnerable'then
    -- Shared native damage dispatcher registers this exact live instance. A
    -- later corpse cannot become eligible merely by looking like a trapjaw.
    if type(options.watch_damage)=='function'and options.watch_damage(c)==true then
     watching[key]={signature=signature,creature=c,world=native.world_id(c)}
    end
   else watching[key]=nil end
   if choices.right~='reward'then armed[key]=nil end
   local old=cache[key]
   if rebase or not old or old.signature~=signature then old={fields={}}end
   local current,next_fields,changes=fields(c),{},{}
   for id,row in pairs(current)do
    local prior=old.fields[id]
    local base=prior and equal(row.value,prior.after)and prior.base or row.value
    local desired=base
    if row.kind=='cooldown'and choices.right=='evasion'and base>0 then desired=base*M.evasion_multiplier end
    if row.kind=='heal'and choices.left=='recovery'and base>0 then desired=base*2 end
    assert(finite(desired),'skill_nonfinite_value')
    if not equal(desired,base)then next_fields[id]={base=base,after=desired}end
    if not equal(desired,row.value)then changes[#changes+1]={key=id,row=row,before=row.value,after=desired}end
   end
   write_fields(c,changes)
   if next(next_fields)then cache[key]={signature=signature,creature=c,fields=next_fields}else cache[key]=nil end
   if #changes>0 then control.decorations=control.decorations+1 end
   return {changed=#changes>0,writes=#changes}
  end)
  if not ok then return failure(result)end;return result
 end
 local function apply_invulnerable(c,ability)
  local existing
  each(c.Effects,function(_,effect)
   if name(effect.EffectName)==M.invulnerable_effect then existing=effect end
  end)
  if existing then
   assert(number(existing.Type)==18,'owned_invulnerable_type_mismatch')
   existing.Length=M.invulnerable_seconds;existing.Timer=-1
   assert(equal(number(existing.Length),M.invulnerable_seconds),'invulnerable_refresh_failed')
   c.CanBeAttacked=false
   assert(c.CanBeAttacked==false,'invulnerable_immediate_flag_failed')
   return true
  end
  -- UE4SS cannot universally marshal an arbitrary FEffect from a Lua table.
  -- Borrow a per-instance FEffect as a synchronous value parameter, then restore
  -- every touched member even if ApplyEffect throws. Never borrow a DataTable row.
  local carrier=assert(find_heal(ability),'escape_effect_carrier_missing')
  local replacements={EffectName=FName(M.invulnerable_effect),Type=18,Length=M.invulnerable_seconds,
   Interval=-1,Timer=-1,Damage=-1,DamageType=0,SpecialEffect=0,StackType=0,StackMax=1,
   CausingColonyID=number(c.ColonyID),CausingTileID=-1,EventName=FName('None')}
  local saved={}
  for field in pairs(replacements)do
   saved[field]=carrier[field];assert(saved[field]~=nil,'effect_member_unreadable:'..field)
   -- Preserve names as independent values, never a possibly mapped wrapper.
   if field=='EffectName'or field=='EventName'then saved[field]=FName(assert(name(saved[field])))end
  end
  local touched={}
  local ok,err=pcall(function()
   for field,value in pairs(replacements)do touched[#touched+1]=field;carrier[field]=value end
   c:ApplyEffect(carrier)
  end)
  local restored=true
  for i=#touched,1,-1 do
   local field=touched[i];local good=pcall(function()carrier[field]=saved[field]end);restored=restored and good
  end
  for _,field in ipairs(touched)do
   local value=safe(function()return carrier[field]end)
   if field=='EffectName'or field=='EventName'then restored=restored and name(value)==name(saved[field])
   else restored=restored and equal(number(value),number(saved[field]))end
  end
  assert(restored,'invulnerable_carrier_restore_failed')
  if not ok then error(err)end
  local observed=false
  each(c.Effects,function(_,e)
   if name(e.EffectName)==M.invulnerable_effect then observed=number(e.Type)==18 and equal(number(e.Length),M.invulnerable_seconds)end
  end)
  assert(observed,'invulnerable_effect_readback_failed')
  -- Type 18 normally sets this flag on TickEffects. Commit it immediately so
  -- a second hit in this same frame cannot kill the rescued actor. Expiry and
  -- restoration remain owned by the native 1.5-second effect, not a Lua timer.
  c.CanBeAttacked=false
  assert(c.CanBeAttacked==false,'invulnerable_immediate_flag_failed')
  return true
 end
 local function hostile_target(c,target,world)
  if not valid(target)or native.world_id(target)~=world then return false end
  local hp=number(safe(function()return target.Health end))
  local colony=number(safe(function()return target.ColonyID end))
  return hp~=nil and hp>0 and colony~=nil and colony~=number(c.ColonyID)
   and safe(function()return c:AmIAlliedWith(colony,false)end)==false
 end
 local function fallback_jump(c)
  -- Native Trapjaw BP computes its backward direction from CurrentTarget.
  -- Damage-over-time can have no surviving target. Keep the native ability's
  -- charge/heal execution, then use the same bounded landing search in the
  -- direction opposite this ant's own facing, without spawning a fake enemy.
  local function helper(path)
   local result=geometry_helpers[path]
   if not valid(result)then
    local find=options.find_object or StaticFindObject
    assert(type(find)=='function','escape_geometry_lookup_missing')
    result=find(path);assert(valid(result),'escape_geometry_helper_missing:'..path)
    geometry_helpers[path]=result
   end
   return result
  end
  local utilities=helper('/Script/EotU.Default__EotUUtilities')
  local system=helper('/Script/Engine.Default__KismetSystemLibrary')
  local p,f=c:K2_GetActorLocation(),c:GetActorForwardVector()
  local px,py,pz=number(p.X),number(p.Y),number(p.Z)
  local fx,fy,fz=number(f.X),number(f.Y),number(f.Z)
  assert(px and py and pz and fx and fy and fz,'escape_geometry_vector_invalid')
  local length=math.sqrt(fx*fx+fy*fy+fz*fz)
  if length<=1e-6 then return false end
  local zone,freedom=number(c:GetHomeZoneID()),number(c.MovementFreedom)
  assert(zone and freedom,'escape_geometry_zone_invalid')
  local start={X=px,Y=py,Z=pz}
  for distance=400,100,-60 do
   local origin={X=px-fx/length*distance,Y=py-fy/length*distance,Z=pz-fz/length*distance}
   local projected={X=0,Y=0,Z=0}
   local found=utilities:UEotUProjectToGrid(c,origin,projected,1,true,c,false,0,false,false,-1,
    zone,false,freedom,false,true,false)
   if found==true then
    assert(number(projected.X)and number(projected.Y)and number(projected.Z),'escape_projection_invalid')
    -- TraceTypeQuery5 is enum value 4. Debug drawing is disabled as in BP.
    local hit={}
    local blocked=system:LineTraceSingle(c,start,projected,4,false,{},0,hit,true,
     {R=1,G=0,B=0,A=1},{R=0,G=1,B=0,A=1},5)
    assert(type(blocked)=='boolean','escape_trace_result_invalid')
    if not blocked and c:JumpToLocation(projected,false,false,2000,4900)==true then return true end
   end
  end
  return false
 end
 local function restore_escape_selection(c,transaction)
  if transaction.target_location~=nil and name(c.SelectedAbility.AbilityName)==transaction.ability then
   c.SelectedAbility.TargetLocation=transaction.target_location
   transaction.target_location=nil
  end
  if transaction.fallback and valid(c.CurrentTarget)and c.CurrentTarget:GetAddress()==c:GetAddress()then
   c.CurrentTarget=valid(transaction.target)and transaction.target or nil
  end
 end
 local function restore_attack(c,token)
  if not token or token.kind~='reward_attack'or token.restored then return end
  token.restored=true
  if attacking[token.key]==token then attacking[token.key]=nil end
  local key,signature=identity(c)
  if key~=token.key or signature~=token.signature then return end
  -- The boost exists only during the synchronous native attack. Preserve a
  -- replacement stat written by another native action rather than undoing it.
  if equal(number(c.AttackDamage),token.boosted)then
   c.AttackDamage=token.base
   assert(equal(number(c.AttackDamage),token.base),'reward_attack_restore_failed')
  end
 end
 local function restore_nested_attack(c,scope)
  if not scope then return end
  local key,signature=identity(c)
  if key==scope.key and signature==scope.signature and attacking[key]==scope.outer
   and equal(number(c.AttackDamage),scope.outer.base)then
   c.AttackDamage=scope.outer.boosted
   assert(equal(number(c.AttackDamage),scope.outer.boosted),'nested_attack_restore_failed')
  end
 end
 function api.on_trigger_pre(c)
  local attack_token,nested_scope
  local ok,result=pcall(function()
   local choices,ctx,gs=authorized(c);if not choices then return nil end
   local selected=c.SelectedAbility
   if not selected then return nil end
   local key,signature=identity(c);if not key then return nil end
   local outer=attacking[key]
   if outer and outer.signature==signature and equal(number(c.AttackDamage),outer.boosted)then
    nested_scope={key=key,signature=signature,outer=outer}
    c.AttackDamage=outer.base
    assert(equal(number(c.AttackDamage),outer.base),'nested_attack_suppress_failed')
   end
   if not escape(selected.AbilityName)then
    -- Native BasicAttack (type 1) reads AttackDamage and synchronously calls
    -- ApplyDamage. Scope the bonus to that call, including all native damage
    -- mitigation; never apply a second hit or a persistent stat multiplier.
    local charge=armed[key]
    if outer or choices.right~='reward'or not charge or charge.signature~=signature
     or charge.world~=native.world_id(gs)or charge.inflight
     or name(selected.AbilityName)~='BasicAttack'or number(selected.AbilityType)~=1 then return nil end
    if not hostile_target(c,safe(function()return c.CurrentTarget end),native.world_id(gs))then return nil end
    local base=number(c.AttackDamage);if not base or base<=0 then return nil end
    local boosted=base*2;assert(finite(boosted),'reward_attack_nonfinite')
    attack_token={kind='reward_attack',key=key,signature=signature,base=base,boosted=boosted,charge=charge}
    c.AttackDamage=boosted
    assert(equal(number(c.AttackDamage),boosted),'reward_attack_readback_failed')
    charge.inflight=attack_token
    attacking[key]=attack_token
    return attack_token
   end
   local decorated,why=api.decorate(c);assert(decorated,why)
   local id=name(selected.AbilityName);local a=find_ability(c,id)
   if not a or not number(a.Charges)or number(a.Charges)<=0 then return nil end
   -- SelectedAbility is an engine copy; a late hatch/selection must not use an
   -- unmodified heal copied before this instance's decorators were installed.
   local live_heal,selected_heal=find_heal(a),find_heal(selected)
   if live_heal and selected_heal then selected_heal.Damage=live_heal.Damage end
   selected.Cooldown=a.Cooldown
   return {key=key,signature=signature,ability=id,charges=number(a.Charges),rescue=rescuing[key]}
  end)
  if not ok then
   if attack_token then
    local restored,why=pcall(restore_attack,c,attack_token)
    if not restored then failure(why)end
    if attack_token.charge.inflight==attack_token then attack_token.charge.inflight=nil end
   end
   local restored,why=pcall(restore_nested_attack,c,nested_scope);if not restored then failure(why)end
   return failure(result)
  end
  if nested_scope then
   result=result or{kind='nested_scope'}
   result.nested_scope=nested_scope
  end
  return result
 end
 function api.on_trigger_post(c,token)
  if not token or token.finished then return false end
  token.finished=true
  local ok,result=pcall(function()
   restore_nested_attack(c,token.nested_scope)
   if token.kind=='nested_scope'then return false end
   -- Restoration precedes ownership/health checks: the hit may have killed the
   -- attacker by reflection or changed its current skill during a native event.
   if token.kind=='reward_attack'then
    restore_attack(c,token)
    if token.charge.inflight==token then token.charge.inflight=nil end
    if token.native_result==true then
     if armed[token.key]==token.charge then armed[token.key]=nil end
     control.reward_attacks=control.reward_attacks+1
     return true
    end
    return false
   end
   local choices=authorized(c);if not choices then return false end
   local key,signature=identity(c)
   if token.key~=key or token.signature~=signature then return false end
   local ability=find_ability(c,token.ability)
   -- A consumed native charge proves a successful escape, even when the
   -- trigger's return value is not exposed by the loader. No charge, no bonus.
   if not ability or not number(ability.Charges)or number(ability.Charges)>=token.charges then return false end
   control.escapes=control.escapes+1
   if choices.right=='evasion'and number(ability.CooldownTimer)and number(ability.Cooldown)then
    if ability.CooldownTimer>ability.Cooldown and ability.Cooldown>0 then ability.CooldownTimer=ability.Cooldown end
   end
   if choices.right=='reward'then
    armed[key]={signature=signature,creature=c,world=native.world_id(c)}
    control.reward_armed=control.reward_armed+1
   end
   -- Ordinary low-health escapes no longer grant shelter. Only this actor's
   -- in-progress lethal-damage transaction may request the protective effect.
   local rescue=token.rescue
   if rescue and rescuing[key]==rescue and choices.left=='invulnerable'then
    -- ForceUseAbilityOnCreature zeroes this ability's timer before selecting
    -- it. Start its actual decorated cooldown after consuming the ready charge.
    local cooldown=number(ability.Cooldown)
    assert(cooldown and cooldown>0,'lethal_escape_cooldown_unreadable')
    ability.CooldownTimer=cooldown
    assert(equal(number(ability.CooldownTimer),cooldown),'lethal_escape_cooldown_write_failed')
    if rescue.fallback then
     local jumped=fallback_jump(c)
     control[jumped and'fallback_jumps'or'fallback_blocked']=control[jumped and'fallback_jumps'or'fallback_blocked']+1
    end
    apply_invulnerable(c,ability)
    rescue.protected=true
    control.invulnerable=control.invulnerable+1
   end
   return true
  end)
  if not ok then return failure(result)end;return result
 end
 function api.on_damage(c,damage,damage_type,causer,instigator)
  c=unbox(c)
  local transaction
  local ok,result=pcall(function()
   if not number(damage)or number(damage)<=0 then return false end
   local choices,ctx,gs=authorized(c,true)
   if not choices or choices.left~='invulnerable'then return false end
   local key,signature=identity(c);local watched=key and watching[key]
   if not watched or watched.signature~=signature or watched.world~=native.world_id(gs)
    or rescuing[key]then return false end
   -- OnTakeAnyDamage is synchronous: HP has already had the actual mitigated
   -- hit subtracted, while native hurt/death handling has not yet run.
   local hp=number(c.Health);if not hp or hp>0 then return false end
   local ability
   each(c.AbilityList,function(_,a)
    if escape(a.AbilityName)and number(a.Charges)and number(a.Charges)>0 then
     assert(not ability,'multiple_ready_escape_abilities');ability=a
    end
   end)
   -- Ready native abilities retain a positive CooldownTimer. Charges alone
   -- determine readiness; no independent timer, refill, or cooldown bypass.
   if not ability then return false end
   local world=native.world_id(gs)
   local target=unbox(causer)
   if not hostile_target(c,target,world)then target=safe(function()return c.CurrentTarget end)end
   local fallback=not hostile_target(c,target,world)
   if fallback then target=c end
   transaction={key=key,signature=signature,health=hp,ability=name(ability.AbilityName),
    charges=number(ability.Charges),timer=number(ability.CooldownTimer),protected=false,
    in_use=c.AbilityInUse,target=c.CurrentTarget,fallback=fallback}
   rescuing[key]=transaction
   c.Health=1;assert(number(c.Health)==1,'lethal_escape_health_write_failed')
   -- ForceUseAbilityOnCreature otherwise silently retains an in-progress
   -- BasicAttack. Lethal shelter interrupts that action before selecting jump.
   c.AbilityInUse=false
   c:ForceUseAbilityOnCreature(FName(transaction.ability),target)
   assert(name(c.SelectedAbility.AbilityName)==transaction.ability,'lethal_escape_selection_failed')
   -- Rescue does not require the damage source to remain within melee range.
   -- This copy-only flag skips native target/range gating, while the selected
   -- original ability still spends its own charge and applies its native heal.
   transaction.target_location=c.SelectedAbility.TargetLocation
   assert(type(transaction.target_location)=='boolean','escape_target_location_unreadable')
   c.SelectedAbility.TargetLocation=true
   c:TriggerAbility()
   restore_escape_selection(c,transaction)
   local observed=find_ability(c,transaction.ability)
   assert(transaction.protected and observed and number(observed.Charges)
    and number(observed.Charges)<transaction.charges and(number(c.Health)or 0)>0,'lethal_escape_not_completed')
   rescuing[key]=nil
   control.lethal_rescues=control.lethal_rescues+1
   return true
  end)
  if not ok then
   if transaction then
    rescuing[transaction.key]=nil
    control.lethal_failures=control.lethal_failures+1
    local restored,why=pcall(function()
     local key,signature=identity(c)
     if key~=transaction.key or signature~=transaction.signature then return end
     restore_escape_selection(c,transaction)
     c.Health=transaction.health
     if transaction.in_use~=nil then c.AbilityInUse=transaction.in_use end
     if valid(transaction.target)then c.CurrentTarget=transaction.target end
     -- ForceUseAbilityOnCreature can zero a ready ability's timer. Undo that
     -- side effect only if the attempted native escape consumed no charge.
     local a=find_ability(c,transaction.ability)
     if a and number(a.Charges)==transaction.charges and transaction.timer then a.CooldownTimer=transaction.timer end
    end)
    if not restored then failure(why)end
   end
   failure(result);return false
  end
  return result
 end
 -- Kept as an inert compatibility entrypoint for old diagnostic tools. The
 -- reward branch no longer observes kills or resets any ability's cooldown.
 function api.on_kill()return false end
 function api.forget(c)
  local key=identity(c);if key then cache[key]=nil;watching[key]=nil;armed[key]=nil end
 end
 function api.reset_cache()cache={};watching={};armed={}end
 function api.tick()
  -- Prune only actors already decorated. No world/creature enumeration.
  local removed=0
  for key,row in pairs(cache)do
   local id,signature=identity(row.creature)
   if id~=key or signature~=row.signature then cache[key]=nil;removed=removed+1 end
  end
  for _,registry in ipairs({watching,armed})do
   for key,row in pairs(registry)do
    local id,signature=identity(row.creature)
    if id~=key or signature~=row.signature or(number(safe(function()return row.creature.Health end))or 0)<=0 then
     registry[key]=nil;removed=removed+1
    end
   end
  end
  return removed
 end
 function api.status()
  local result={stopped=stopped,hooks={},cached=0,watched=0,armed=0}
  for k,v in pairs(control)do result[k]=v end
  for path,value in pairs(hooks)do result.hooks[path]=value end
  for _ in pairs(cache)do result.cached=result.cached+1 end
  for _ in pairs(watching)do result.watched=result.watched+1 end
  for _ in pairs(armed)do result.armed=result.armed+1 end
  return result
 end
 function api.stop()
  for _,entry in pairs(cache)do
   if valid(entry.creature)then local ok,err=api.before_attributes(entry.creature);if not ok then return nil,err end end
  end
  -- Hook callbacks stay registered but inert. Unregistering UE4SS hooks during
  -- an engine callback has caused access violations in this loader family.
  stopped=true;cache={};watching={};armed={};return true
 end
 local register=options.register_hook or RegisterHook
 local function hook(path,pre,post)
  if options.register_hooks==false then return end
  local ok,a,b=pcall(register,path,pre,post)
  if not ok or a==nil then failure('skill_hook_failed:'..path..':'..tostring(a));hooks[path]=false
  else hooks[path]=true end
 end
 local function callback_key(c)
  if not valid(c)then return nil end
  local species=name(c.CreatureName)
  if not species or species:lower()~='trapjawant'then return nil end
  local address=safe(function()return c:GetAddress()end)
  return address~=nil and tostring(address)or nil
 end
 hook('/Script/EotU.Creature:TriggerAbility',function(receiver)
  if stopped then return end
  local c=unbox(receiver);local key=callback_key(c);if not key then return end
  local stack=pending[key]or{};pending[key]=stack
  stack[#stack+1]=api.on_trigger_pre(c)or false
 end,function(receiver,return_value)
  local c=unbox(receiver);local key=callback_key(c);local stack=key and pending[key]
  if not stack or #stack==0 then return end
  local token=table.remove(stack);if #stack==0 then pending[key]=nil end
  if token then token.native_result=unbox(return_value);api.on_trigger_post(c,token)end
 end)
 return api
end
return M
