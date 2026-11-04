-- SlaveMaker combat/capture coordination. Import has no engine side effects.
-- Engine-specific lethal protection, carrying, conversion and medical recovery
-- are adapters: this module never estimates damage or replaces a creature.
local M = {species='SlaveMaker', native_species='SlaveMakerAnt', tick_interval=0.25, aura_multiplier=1.15}

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
local function finite(n)return type(n)=='number'and n==n and n~=math.huge and n~=-math.huge end
local function number(v)local n=tonumber(unbox(v));return finite(n)and n or nil end
local function equal(a,b)
 return finite(a)and finite(b)and math.abs(a-b)<=math.max(1e-6,math.abs(a)*1e-6,math.abs(b)*1e-6)
end

function M.install(options)
 assert(type(options)=='table'and type(options.native)=='table','slaver_native_required')
 assert(type(options.get_context)=='function'and type(options.get_choices)=='function','slaver_context_required')
 local native,adapter=options.native,options.adapter or{}
 local guard=options.damage_guard or adapter
 local radius=number(options.aura_radius)
 assert(radius and radius>0 and radius<=10000,'slaver_aura_radius_required')
 local interval=number(options.tick_interval)or M.tick_interval
 assert(interval>=0.1 and interval<=1,'slaver_tick_interval_invalid')
 local random=options.random or math.random
 local damage_events=options.damage_events
 local event_pending,event_seen,event_count,event_seen_count={},{},0,0
 local ensure_fire_hook
 local stopped=false
 local registry,fields,pending,hooks,reported={},{},{},{},{}
 local grid,grid_flags,grid_world={},{},nil
 local has_slaves=false
 local next_tick=nil
 local stats={observed=0,rolls=0,guards=0,knockouts=0,conversions=0,wounded=0,medical_guards=0,
  aura_writes=0,ticks=0,event_launches=0,event_hits=0,event_captures=0,event_expired=0,event_native_priority=0,last_error=nil}
 local api={}
 local function failure(err)
  err=tostring(err);stats.last_error=err
  if not reported[err]then
   reported[err]=true;if options.log then pcall(options.log,'[SlaveMaker] '..err)end
  end
  return nil,err
 end
 local function cancel_pending()
  for _,stack in pairs(pending)do for _,t in ipairs(stack)do
   if t then guard.cancel_damage_guard(t.guard)end
  end end
  pending={}
 end
 local function valid(c)return c~=nil and safe(function()return native.valid_object(c)end)==true end
 local function identity(c)
  if not valid(c)then return nil end
  local address=safe(function()return c:GetAddress()end)
  local full=safe(function()return c:GetFullName()end)
  if address==nil or type(full)~='string'then return nil end
  -- A level change is the same actor; native stats may rebuild and are handled
  -- through before_attributes/decorate. Full name also guards address reuse.
  return tostring(address),full
 end
 local function context()
  local ctx=options.get_context()
  local gs=type(ctx)=='table'and(ctx.gs or ctx.game_state)or nil
  if not valid(gs)then return nil end
  return ctx,gs,native.world_id(gs)
 end
 local function owned(c,gs,world)
  return valid(c)and native.world_id(c)==world and native.is_owned(c,gs)==true
 end
 local function alive(c)return valid(c)and(number(safe(function()return c.Health end))or 0)>0 end
 local function species(c)return name(safe(function()return c.CreatureName end))end
 local function master(c)local n=species(c);return n and n:lower()==M.native_species:lower()end
 local function choices(c)
  local value=options.get_choices(c,M.species)
  if value==nil then return{}end
  assert(type(value)=='table','slaver_choices_invalid')
  assert(value.left==nil or value.left=='special_master'or value.left=='follow_step','slaver_left_choice_invalid')
  assert(value.right==nil or value.right=='overseer_drill'or value.right=='overseer_haul','slaver_right_choice_invalid')
  return value
 end
 local function read_state(c)
  if type(adapter.describe_state)=='function'then
   local value=adapter.describe_state(c)
   if type(value)=='table'then return value end
  end
  if type(adapter.is_slave)=='function'and adapter.is_slave(c)==true then return{state='slave'}end
  return nil
 end
 local function is_slave(c,row)
  if type(adapter.is_slave)=='function'then return adapter.is_slave(c)==true end
  return row and row.state=='slave'
 end
 local function active_slave(c,row)
  if not is_slave(c,row)or not alive(c)then return false end
  if type(adapter.is_active_slave)=='function'then return adapter.is_active_slave(c)==true end
  return not row or(row.state~='knocked_out'and row.state~='wounded')
 end
 local function active_overseer(c,row)
  return master(c)and alive(c)and(row.state=='overseer'or(row.state=='slave'and active_slave(c,row)))
 end
 local function each_effect(a,fn)
  if type(a)=='table'and type(a.GetArrayNum)~='function'then for _,v in ipairs(a)do fn(v)end;return end
  local n=a:GetArrayNum();assert(n>=0 and n<=512,'slaver_effect_array_invalid')
  for i=1,n do fn(unbox(a[i]))end
 end
 local function capture_probability(c,gs,world)
  if not alive(c)or not owned(c,gs,world)then return nil end
  if not master(c)or(number(c.CreatureLevel)or 0)<2 then return nil end
  local selected=choices(c)
  return selected.left=='special_master'and 0.5 or 0.25
 end
 local function retire_event(t)
  if t.retired then return end;t.retired=true;event_count=event_count-1
 end
 local function prune_events(now)
  for k,bucket in pairs(event_pending)do
   local keep={}
   for _,t in ipairs(bucket)do
    if not t.retired and(now<t.started or now>t.expires or not valid(t.attacker)or not valid(t.victim))then
     retire_event(t);stats.event_expired=stats.event_expired+1
    end
    if not t.retired then keep[#keep+1]=t end
   end
   if #keep>0 then event_pending[k]=keep else
    event_pending[k]=nil
    if bucket[1]and type(damage_events.unwatch_capture)=='function'then damage_events.unwatch_capture(bucket[1].victim)end
   end
  end
  for k,t in pairs(event_seen)do if now<t.started or now>t.expires then event_seen[k]=nil;event_seen_count=event_seen_count-1 end end
 end
 local function launch_event(c,kind)
  if not damage_events or stopped then return nil end
  local _,gs,world=context();if not gs or not capture_probability(c,gs,world)then return nil end
  local a=c.SelectedAbility;local ability_name=name(a.AbilityName)
  local ability_type=number(a.AbilityType)
  if(kind=='projectile'and ability_type~=2)or(kind=='direct'and(ability_type~=1 or ability_name~='BasicAttack'))then return nil end
  if(number(a.AOERad)or 0)>0 then return nil end
  -- Do not reinterpret an attack that deliberately heals/protects its target.
  local healing=false;each_effect(a.Effects,function(e)
   local t,d=number(e.Type),number(e.Damage)
   if d and d>0 and(t==14 or t==23 or t==30 or t==36)then healing=true end
  end)
  if healing then return nil end
  local v=c.CurrentTarget
  if not alive(v)or native.world_id(v)~=world or number(c.ColonyID)==number(v.ColonyID)
   or c:AmIAlliedWith(v.ColonyID,v.AlliedWithAllNoneColony==true)~=false or adapter.is_capturable(v,c)~=true then return nil end
  local k,s=identity(c);local vk,vs=identity(v)
  local now=number(gs:GetLevelTime());if not k or not vk or not now then return nil end
  local bucket=event_pending[vk]or{}
  for _,t in ipairs(bucket)do
   -- The native base event and its Blueprint override may both be dispatched
   -- for one launch. Probability is drawn only at actual attributed damage.
   if not t.retired and t.kind==kind and t.key==k and t.signature==s and t.ability==ability_name and t.started==now then return t end
  end
  if event_count>=4096 or #bucket>=128 then return nil end
  local watched,why=damage_events.watch_capture(v);assert(watched,why or 'slaver_capture_watch_failed')
  local t={attacker=c,key=k,signature=s,victim=v,victim_key=vk,victim_signature=vs,kind=kind,
   ability=ability_name,damage_type=number(a.DamageType),colony=number(c.ColonyID),victim_colony=number(v.ColonyID),
   world=world,started=now,expires=now+15}
  bucket[#bucket+1]=t;event_pending[vk]=bucket;event_count=event_count+1;stats.event_launches=stats.event_launches+1
  return t
 end
 function api.on_fire_pre(c)
  local ok,result=pcall(launch_event,c,'projectile');if not ok then return failure(result)end;return result
 end
 local projectile_class
 function api.on_attributed_damage(victim,damage,damage_type,causer)
  local original_hp,attempted,ticket=nil,false,nil
  local ok,result=pcall(function()
   if stopped or not damage_events or not valid(victim)or not valid(causer)then return false end
   local vk,vs=identity(victim);local bucket=vk and event_pending[vk];if not bucket then return false end
   local _,gs,world=context();if not gs or native.world_id(victim)~=world or native.world_id(causer)~=world then return false end
   local now=number(gs:GetLevelTime());if not now then return false end
   local type_name=valid(damage_type)and safe(function()return damage_type:GetFullName()end)or''
   local direct_type=type_name:match('^EotUPhysicalDamageType ')and 0 or type_name:match('^EotUVenomDamageType ')and 2 or nil
   -- Passive damage, thorns and unattributed DOT do not borrow an outstanding
   -- shot's credit. Only the two direct damage classes proven in native QA.
   if direct_type==nil or not number(damage)or damage<=0 then return false end
   local attacker,kind,ability_name,projectile_key=causer,'direct',nil,nil
   local causer_key,causer_signature=identity(causer)
   local direct=false
   for _,t in ipairs(bucket)do if not t.retired and t.kind=='direct'and t.key==causer_key and t.signature==causer_signature then direct=true;break end end
   if not direct then
    if not valid(projectile_class)then projectile_class=options.projectile_class or StaticFindObject('/Script/EotU.EotuProjectileLite')end
    if not valid(projectile_class)or causer:IsA(projectile_class)~=true then return false end
    local a=causer.LocalCreatedFromAbility
    if number(a.AbilityType)~=2 or(number(a.AOERad)or 0)>0 or number(a.DamageType)~=direct_type then return false end
    attacker=causer:GetInstigator();kind='projectile';ability_name=name(a.AbilityName)
    projectile_key=causer_key..'|'..causer_signature
    if event_seen[projectile_key]or event_seen_count>=8192 then return false end
   end
   local ak,as=identity(attacker);if not ak then return false end
   for _,t in ipairs(bucket)do
    if not t.retired and t.kind==kind and t.key==ak and t.signature==as and t.victim_signature==vs
     and t.world==world and now>=t.started and now<=t.expires and(kind=='direct'or t.ability==ability_name)then ticket=t;break end
   end
   if not ticket then return false end
   retire_event(ticket);stats.event_hits=stats.event_hits+1
   if projectile_key then event_seen[projectile_key]={started=now,expires=now+15};event_seen_count=event_seen_count+1 end
   -- Consume a shot on its FIRST real hit, including nonlethal hits and failed
   -- rolls. Duplicate broadcasts cannot reroll it or consume another shot.
   original_hp=number(victim.Health);if not original_hp or original_hp>0 then return false end
   if number(attacker.ColonyID)~=ticket.colony or number(victim.ColonyID)~=ticket.victim_colony then return false end
   local probability=capture_probability(attacker,gs,world);if not probability then return false end
   if attacker:AmIAlliedWith(victim.ColonyID,victim.AlliedWithAllNoneColony==true)~=false then return false end
   if damage_events.has_native_rescue_priority(victim,original_hp)then stats.event_native_priority=stats.event_native_priority+1;return false end
   local roll=random();assert(finite(roll)and roll>=0 and roll<1,'slaver_random_invalid');stats.rolls=stats.rolls+1
   if roll>=probability then return false end
   local maximum=number(victim.FullHealth);if not maximum or maximum<=0 then return false end
   attempted=true;victim.Health=math.min(1,maximum)
   assert(number(victim.Health)>0,'slaver_event_health_write_failed')
   assert(adapter.is_capturable(victim,attacker)==true,'slaver_event_target_no_longer_capturable')
   local captured,why=adapter.knockout(victim,attacker,{exact=true,lethal=true,before=original_hp,source=kind})
   assert(captured==true,why or 'slaver_event_knockout_rejected')
   local state=adapter.describe_state(victim);assert(state and state.state=='knocked_out','slaver_event_capture_not_committed')
   local observed,observe_error=api.observe(victim);assert(observed,observe_error or 'slaver_event_capture_not_observed')
   ticket.captured=true;stats.knockouts=stats.knockouts+1;stats.event_captures=stats.event_captures+1
   return true
  end)
  if attempted and(not ok or result~=true)then
   local called,aborted,why=pcall(adapter.abort,victim,'slaver_damage_capture_rollback')
   if not called or aborted~=true then failure(why or aborted)end
   if valid(victim)and ticket and select(2,identity(victim))==ticket.victim_signature then
    local restored,e=pcall(function()victim.Health=original_hp;assert(number(victim.Health)==original_hp,'slaver_event_hp_restore_failed')end)
    if not restored then failure(e)end
   end
  end
  if not ok then return failure(result)end;return result
 end
 local function position(c)
  local p=type(adapter.position)=='function'and adapter.position(c)or c:K2_GetActorLocation()
  if not p then return nil end
  local x,y,z=number(p.X or p.x),number(p.Y or p.y),number(p.Z or p.z)
  if x and y and z then return{x=x,y=y,z=z}end
 end
 local function loaded(c)
  if type(adapter.is_loaded)=='function'then return adapter.is_loaded(c)==true end
  return valid(safe(function()return c:GetHeldActor()end))
 end
 local function write(c,field,value)
  if type(adapter.write_aura_field)=='function'then adapter.write_aura_field(c,field,value)
  elseif field=='OriginalMaxSpeed'then c:ChangeOrigonalMovmentSpeed(value)
  else c[field]=value end
  assert(equal(number(c[field]),value),'slaver_aura_readback:'..field)
 end
 local function restore(c)
  local key,signature=identity(c);if not key then return{changed=false}end
  local previous=fields[key]
  if not previous or previous.signature~=signature then fields[key]=nil;return{changed=false}end
  local changes={}
  for field,row in pairs(previous.fields)do
   local current=number(c[field])
   if equal(current,row.after)and not equal(current,row.base)then
    changes[#changes+1]={field=field,before=current,after=row.base}
   end
  end
  local changed={}
  local ok,err=pcall(function()
   for _,entry in ipairs(changes)do changed[#changed+1]=entry;write(c,entry.field,entry.after)end
  end)
  if not ok then
   local rollback=true
   for i=#changed,1,-1 do local e=changed[i];rollback=pcall(write,c,e.field,e.before)and rollback end
   error(tostring(err)..'; rollback_verified='..tostring(rollback))
  end
  fields[key]=nil
  return{changed=#changes>0,writes=#changes}
 end
 local function cell_key(colony,layer,x,y)return colony..':'..layer..':'..x..':'..y end
 local function nearby(c)
  local colony,layer=number(c.ColonyID),number(c.ColonyLocation)
  local pos=position(c)
  if not colony or not layer or not pos then return false,false end
  local cx,cy=math.floor(pos.x/radius),math.floor(pos.y/radius)
  local possible=grid_flags[colony..':'..layer]or{}
  local attack,haul=false,false
  for dx=-1,1 do for dy=-1,1 do
   local bucket=grid[cell_key(colony,layer,cx+dx,cy+dy)]
   if bucket then for _,entry in ipairs(bucket)do
    local m=entry.creature
    -- The index is at most one interval old. Recheck the live owner, position
    -- and health so a dead/moved/converted overseer never leaves a stale aura.
    if active_overseer(m,entry)and number(m.ColonyID)==colony and number(m.ColonyLocation)==layer then
     local p=position(m)
     if p then
      local x,y,z=pos.x-p.x,pos.y-p.y,pos.z-p.z
      if x*x+y*y+z*z<=radius*radius then
       local selected=entry.right
       attack=attack or selected=='overseer_drill';haul=haul or selected=='overseer_haul'
       if(attack or not possible.attack)and(haul or not possible.haul)then return attack,haul end
      end
     end
    end
   end end
  end end
  return attack,haul
 end
 local function decorate(c,rebase)
  local key,signature=identity(c);if not key then return{changed=false}end
  local _,gs,world=context()
  local row=registry[key]
  if stopped or not gs or not owned(c,gs,world)or not active_slave(c,row)or world~=grid_world then return restore(c)end
  local attack,haul=nearby(c);haul=haul and loaded(c)
  local previous=fields[key]
  if rebase or not previous or previous.signature~=signature then previous={fields={}}end
  local changes,next_fields={},{}
  for _,field in ipairs({'AttackSpeed','OriginalMaxSpeed'})do
   local current=number(c[field]);assert(current and current>=0,'slaver_aura_field_invalid:'..field)
   local prior=previous.fields[field]
   local base=prior and equal(current,prior.after)and prior.base or current
   local selected=field=='AttackSpeed'and attack or field=='OriginalMaxSpeed'and haul
   local desired=selected and base*M.aura_multiplier or base
   assert(finite(desired),'slaver_aura_nonfinite')
   if selected then next_fields[field]={base=base,after=desired}end
   if not equal(current,desired)then changes[#changes+1]={field=field,before=current,after=desired}end
  end
  local changed={}
  local ok,err=pcall(function()
   for _,e in ipairs(changes)do changed[#changed+1]=e;write(c,e.field,e.after)end
  end)
  if not ok then
   local rollback=true
   for i=#changed,1,-1 do local e=changed[i];rollback=pcall(write,c,e.field,e.before)and rollback end
   error(tostring(err)..'; rollback_verified='..tostring(rollback))
  end
  fields[key]=next(next_fields)and{creature=c,signature=signature,fields=next_fields}or nil
  stats.aura_writes=stats.aura_writes+#changes
  return{changed=#changes>0,writes=#changes,attack=attack,haul=haul}
 end
 function api.before_attributes(c)
  local ok,result=pcall(restore,c);if not ok then return failure(result)end;return result
 end
 function api.decorate(c,rebase)
  local ok,result=pcall(decorate,c,rebase);if not ok then return failure(result)end;return result
 end
 function api.observe(c)
  local ok,result=pcall(function()
   if stopped then return false end
   local key,signature=identity(c);if not key then return false end
   local _,gs,world=context();if not gs or native.world_id(c)~=world then return false end
   if grid_world and grid_world~=world then
    local reset,why=api.reset_cache();assert(reset,why);grid_world=world
   end
   local state=read_state(c)
   if not state and not(master(c)and owned(c,gs,world))then return false end
   local row=registry[key]
   if not row or row.signature~=signature then
    row={creature=c,signature=signature,world=world};registry[key]=row;stats.observed=stats.observed+1
   end
   row.state=state and state.state or 'overseer'
   if row.state=='slave'then has_slaves=true end
   if damage_events and owned(c,gs,world)and ensure_fire_hook then ensure_fire_hook(c)end
   return true
  end)
  if not ok then return failure(result)end;return result
 end
 local function guard_ready()
  if type(guard.ready)=='function'and guard.ready()~=true then return false end
  if type(adapter.capture_ready)=='function'and adapter.capture_ready()~=true then return false end
  return type(guard.begin_damage_guard)=='function'and type(guard.end_damage_guard)=='function'
   and type(guard.cancel_damage_guard)=='function'and type(adapter.knockout)=='function'
   and type(guard.resolve_failed_capture)=='function'and type(adapter.is_capturable)=='function'
 end
 function api.on_trigger_pre(c)
  local guard_token
  local ok,result=pcall(function()
   if stopped or not guard_ready()or not alive(c)then return nil end
   local key,signature=identity(c);if not key then return nil end
   local _,gs,world=context();if not gs or native.world_id(c)~=world then return nil end
   local selected=c.SelectedAbility
   if not selected or name(selected.AbilityName)~='BasicAttack'or number(selected.AbilityType)~=1 then return nil end
   local victim=c.CurrentTarget
   if not alive(victim)or native.world_id(victim)~=world then return nil end
   local colony,victim_colony=number(c.ColonyID),number(victim.ColonyID)
   if not colony or not victim_colony or colony==victim_colony then return nil end
   if c:AmIAlliedWith(victim_colony,victim.AlliedWithAllNoneColony==true)~=false then return nil end
   local victim_key,victim_signature=identity(victim);if not victim_key then return nil end
   local victim_row=registry[victim_key]
   if options.medical_delegate~=true and has_slaves and owned(victim,gs,world)and active_slave(victim,victim_row)
    and type(adapter.can_begin_medical)=='function'and type(adapter.medical_begin)=='function'
    and adapter.can_begin_medical(victim)==true then
    guard_token=guard.begin_damage_guard(c,victim,'medical')
    if not guard_token then return nil end
    stats.medical_guards=stats.medical_guards+1
    return{kind='medical',attacker=c,key=key,signature=signature,victim=victim,victim_key=victim_key,
     victim_signature=victim_signature,victim_colony=victim_colony,colony=colony,world=world,guard=guard_token}
   end
   if not owned(c,gs,world)then return nil end
   local probability=capture_probability(c,gs,world);if not probability then return nil end
   if adapter.is_capturable(victim,c)~=true then return nil end
   if damage_events and selected.Effects then
    local has_effects=false;each_effect(selected.Effects,function()has_effects=true end)
    if has_effects then
     local ticket=launch_event(c,'direct')
     return ticket and{kind='capture_event',ticket=ticket}or nil
    end
   end
   -- A preselected Bernoulli roll does not modify nonlethal hits: the native
   -- guard reports exact mitigated lethality, and is removed in this call's
   -- post hook. No low-HP threshold, damage estimate or permanent immunity.
   local roll=random();assert(finite(roll)and roll>=0 and roll<1,'slaver_random_invalid')
   stats.rolls=stats.rolls+1
   if roll>=probability then return nil end
   guard_token=guard.begin_damage_guard(c,victim)
   if not guard_token then return nil end
   stats.guards=stats.guards+1
   return{kind='capture',attacker=c,key=key,signature=signature,victim=victim,victim_key=victim_key,
    victim_signature=victim_signature,victim_colony=victim_colony,colony=colony,world=world,guard=guard_token}
  end)
  if not ok then
   if guard_token then pcall(guard.cancel_damage_guard,guard_token)end
   return failure(result)
  end
  return result
 end
 function api.on_trigger_post(c,token,attack_succeeded)
  if not token then return false end
  if token.kind=='capture_event'then retire_event(token.ticket);return token.ticket.captured==true end
  local released,captured,evidence=false,false,nil
  local ok,result=pcall(function()
   -- End the guard even if the attacker died to thorns, changed ownership,
   -- or the native attack failed. Temporary protection cannot outlive a hit.
   evidence=guard.end_damage_guard(token.guard,attack_succeeded==true)
   released=true
   if type(evidence)~='table'or evidence.lethal~=true or evidence.exact~=true then return false end
   if stopped or attack_succeeded~=true then return false end
   local key,signature=identity(c)
   local vk,vs=identity(token.victim)
   if vk~=token.victim_key or vs~=token.victim_signature then return false end
   local _,gs,world=context()
   if not gs or world~=token.world or not alive(token.victim)then return false end
   if token.kind=='medical'then
    if not owned(token.victim,gs,world)or number(token.victim.ColonyID)~=token.victim_colony then return false end
    if key and(key~=token.key or signature~=token.signature or number(c.ColonyID)~=token.colony)then return false end
    captured=adapter.medical_begin(token.victim)==true
    if captured then stats.wounded=stats.wounded+1;api.observe(token.victim)end
    return captured
   end
   if key~=token.key or signature~=token.signature or not owned(c,gs,world)then return false end
   if number(c.ColonyID)~=token.colony or number(token.victim.ColonyID)~=token.victim_colony then return false end
   captured=adapter.knockout(token.victim,c,evidence)==true
   if not captured then return false end
   stats.knockouts=stats.knockouts+1;api.observe(token.victim)
   return true
  end)
  if not released then pcall(guard.cancel_damage_guard,token.guard)end
  -- Every path after a protected lethal hit, including ownership changes or
  -- an adapter exception, must resolve the ordinary death if capture failed.
  if not captured and type(evidence)=='table'and evidence.lethal==true and evidence.exact==true
   and type(guard.resolve_failed_capture)=='function'then
   local resolved,resolve_error=pcall(guard.resolve_failed_capture,token.guard,evidence)
   if not resolved then return failure(resolve_error)end
  end
  if not ok then return failure(result)end
  return result
 end
 local function snapshot_registry()
  local rows={};for key,row in pairs(registry)do rows[#rows+1]={key=key,row=row}end;return rows
 end
 local function retire_row(key,row)
  -- A destroyed UObject's address may already identify its replacement. Only
  -- retire this generation, never an observation installed by a spawn callback.
  local prior=fields[key]
  if prior and prior.signature==row.signature then
   local k,s=identity(row.creature)
   if k==key and s==row.signature then
    local restored,why=api.before_attributes(row.creature);assert(restored,why)
   end
   if fields[key]==prior then fields[key]=nil end
  end
  if registry[key]==row then registry[key]=nil end
 end
 local function poll_row(key,row,gs,world,now)
  if registry[key]~=row then return end
  local c=row.creature;local k,s=identity(c)
  if k~=key or s~=row.signature or native.world_id(c)~=world then retire_row(key,row);return end
  -- A wounded/knocked-out actor must not carry the previous live aura into a
  -- conversion snapshot. This only writes when that actor actually had ours.
  if fields[key]and(not owned(c,gs,world)or not active_slave(c,row))then
   local restored,why=api.before_attributes(c);assert(restored,why)
  end
  local outcome
  if type(adapter.poll)=='function'then
   local poll_ok,value,why=pcall(adapter.poll,c,row,now)
   if not poll_ok then failure(value)
   elseif value==nil and why then failure(why)
   else outcome=value end
  end
  if type(outcome)=='table'and outcome.creature then
   local replacement=outcome.creature;local nk,ns=identity(replacement)
   if nk~=key or ns~=row.signature then
    assert(nk and native.world_id(replacement)==world and owned(replacement,gs,world),'slaver_replacement_invalid')
    local state=read_state(replacement)
    assert(state and state.state==outcome.state and outcome.state=='slave','slaver_replacement_state_invalid')
    local observed,why=api.observe(replacement);assert(observed,why or 'slaver_replacement_not_observed')
    if row.state~='slave'then stats.conversions=stats.conversions+1 end
    retire_row(key,row)
    return
   end
  end
  local after_key,after_signature=identity(c)
  if after_key~=key or after_signature~=row.signature then retire_row(key,row);return end
  -- Adapter aborts can leave a live original enemy with no capture marker.
  -- Retire that observation instead of polling it forever. An ordinary owned
  -- SlaveMaker remains an overseer even when no capture record exists.
  local state=type(outcome)=='table'and outcome.state and outcome or read_state(c)
  if state then
   if row.state~='slave'and state.state=='slave'then stats.conversions=stats.conversions+1 end
   row.state=state.state
  elseif master(c)and owned(c,gs,world)then row.state='overseer'
  else retire_row(key,row)end
 end
 function api.tick(now)
  local ok,result=pcall(function()
   if stopped then return false end
   now=number(now)or(type(options.clock)=='function'and number(options.clock()))
   assert(now,'slaver_game_clock_required')
   if next_tick and now<next_tick and now>=next_tick-interval*2 then return false end
   next_tick=now+interval;stats.ticks=stats.ticks+1
   local _,gs,world=context()
   if not gs then return false end
   if grid_world and grid_world~=world then
    local reset,why=api.reset_cache();assert(reset,why);next_tick=now+interval
   end
   if damage_events then prune_events(now)end
   -- Clean registered dead captures once per throttled tick, never once per
   -- actor. A cleanup failure must not prevent live polls or aura restoration.
   if type(adapter.prune_dead)=='function'then
    local pruned,value,why=pcall(adapter.prune_dead)
    if not pruned then failure(value)
    elseif value==nil then failure(why or 'slaver_prune_dead_failed')end
   end
   grid={};grid_flags={};grid_world=world;has_slaves=false
   -- Native conversion calls on_slave_ready while polling and can destroy the
   -- original actor. A bounded snapshot avoids mutating a pairs traversal.
   for _,entry in ipairs(snapshot_registry())do
    local polled,why=pcall(poll_row,entry.key,entry.row,gs,world,now)
    if not polled then failure(why)end
   end
   for _,entry in ipairs(snapshot_registry())do
    local key,row=entry.key,entry.row
    local indexed,why=pcall(function()
    local c=row.creature;local k,s=identity(c)
    if registry[key]~=row then return end
    if k~=key or s~=row.signature or native.world_id(c)~=world then retire_row(key,row)
    else
     if row.state=='slave'and alive(c)then has_slaves=true end
     if active_overseer(c,row)and owned(c,gs,world)then
      local colony,layer,p=number(c.ColonyID),number(c.ColonyLocation),position(c)
      if colony and layer and p then
       row.right=choices(c).right
       local flag_key=colony..':'..layer;local flags=grid_flags[flag_key]or{};grid_flags[flag_key]=flags
       flags.attack=flags.attack or row.right=='overseer_drill';flags.haul=flags.haul or row.right=='overseer_haul'
       local cell=cell_key(colony,layer,math.floor(p.x/radius),math.floor(p.y/radius))
       local bucket=grid[cell]or{};grid[cell]=bucket;bucket[#bucket+1]=row
      end
     end
    end
    end)
    if not indexed then failure(why)end
   end
   for _,row in pairs(registry)do api.decorate(row.creature)end
   return true
  end)
  if not ok then return failure(result)end;return result
 end
 function api.forget(c)
  local address=c~=nil and safe(function()return c:GetAddress()end)or nil
  local key=address~=nil and tostring(address)or nil;if not key then return end
  -- Stats rebuild hooks also fire during native spawn. A brand-new untracked
  -- UObject has nothing to restore; do not reflect into its unfinished fields.
  if not registry[key]and not fields[key]and not pending[key]then return true end
  local row=registry[key]
  local _,signature=identity(c)
  if not signature then
   -- A late removal notification for an invalid old wrapper cannot authorize
   -- deleting a currently valid actor at its recycled address.
   if row and valid(row.creature)then return false end
   local prior=fields[key];if prior and valid(prior.creature)then return false end
  elseif row and row.signature~=signature then return false end
  if valid(c)then local restored,err=api.before_attributes(c);if not restored then return nil,err end end
  if not row or registry[key]==row then registry[key]=nil end
  local prior=fields[key];if prior and(not signature or prior.signature==signature)then fields[key]=nil end
  local stack=pending[key]
  if stack then
   for i,t in ipairs(stack)do
    if t and((signature and t.signature==signature)or(not signature and not valid(t.attacker)))then
     local cancelled,err=pcall(guard.cancel_damage_guard,t.guard);if not cancelled then return failure(err)end
     stack[i]=false
    end
   end
   local outstanding=false;for _,t in ipairs(stack)do if t then outstanding=true;break end end
   if not outstanding then pending[key]=nil end
  end
  return true
 end
 function api.status()
  local result={stopped=stopped,hooks={},registered=0,decorated=0,aura_radius=radius,capture_ready=guard_ready(),pending_damage=event_count,seen_projectiles=event_seen_count}
  for k,v in pairs(stats)do result[k]=v end
  for p,v in pairs(hooks)do result.hooks[p]=v end
  for _ in pairs(registry)do result.registered=result.registered+1 end
  for _ in pairs(fields)do result.decorated=result.decorated+1 end
  return result
 end
 function api.reset_cache()
  for _,row in pairs(fields)do
   if valid(row.creature)then
    local restored,err=api.before_attributes(row.creature);if not restored then return nil,err end
   end
  end
  local cancelled,err=pcall(cancel_pending);if not cancelled then return failure(err)end
  if damage_events then
   for _,bucket in pairs(event_pending)do if bucket[1]then damage_events.unwatch_capture(bucket[1].victim)end end
  end
  event_pending,event_seen,event_count,event_seen_count={},{},0,0
  registry={};fields={};grid={};grid_flags={};grid_world=nil;has_slaves=false;next_tick=nil
  return true
 end
 function api.stop()
  local reset,err=api.reset_cache();if not reset then return nil,err end
  stopped=true;return true
 end
 local register=options.register_hook or RegisterHook
 local function hook(path,pre,post)
  if options.register_hooks==false then return end
  local ok,id=pcall(register,path,pre,post)
  hooks[path]=ok and id~=nil
  if not hooks[path]then failure('slaver_hook_failed:'..path..':'..tostring(id))end
 end
 local function tracked_key(c)
  if not valid(c)then return nil end
  local address=safe(function()return c:GetAddress()end)
  if address==nil then return nil end
  local key=tostring(address)
  local row=registry[key]
  -- Most native attacks are unrelated. Avoid GetFullName/string allocation
  -- for each ordinary ant's attack; validate identity only for our registry.
  if not row and not master(c)then
   if options.medical_delegate==true or not has_slaves then return nil end
   local victim=safe(function()return c.CurrentTarget end)
   local address=valid(victim)and safe(function()return victim:GetAddress()end)or nil
   local target=address~=nil and registry[tostring(address)]or nil
   if not target or target.state~='slave'then return nil end
  end
  local _,signature=identity(c)
  if master(c)or(row and row.signature==signature)or has_slaves then return key end
 end
 hook('/Script/EotU.Creature:TriggerAbility',function(receiver)
  if stopped then return end
  local c=unbox(receiver);local key=tracked_key(c);if not key then return end
  local stack=pending[key]or{};pending[key]=stack;stack[#stack+1]=api.on_trigger_pre(c)or false
 end,function(receiver,result)
  if stopped then return end
  local c=unbox(receiver)
  -- GetAddress reads the wrapper's stored pointer without dereferencing the
  -- actor. An attacker destroyed by thorns still owns an outstanding guard
  -- which must be ended; validity is checked before any actor field access.
  local address=c~=nil and safe(function()return c:GetAddress()end)or nil
  local key=address~=nil and tostring(address)or nil;local stack=key and pending[key]
  if not stack or #stack==0 then return end
  local token=table.remove(stack);if #stack==0 then pending[key]=nil end
  if token then api.on_trigger_post(c,token,unbox(result))end
 end)
 if damage_events then
  for _,method in ipairs({'watch_capture','unwatch_capture','set_capture_handler','has_native_rescue_priority'})do
   assert(type(damage_events[method])=='function','slaver_damage_events_required:'..method)
  end
  assert(type(adapter.abort)=='function','slaver_capture_rollback_required')
  damage_events.set_capture_handler(api.on_attributed_damage)
  local function on_fire(receiver)
   if stopped then return end
   local c=unbox(receiver);if not tracked_key(c)then return end
   api.on_fire_pre(c)
  end
  hook('/Script/EotU.Creature:FireProjectile',on_fire)
  local attempted={}
  ensure_fire_hook=function(c)
   if options.register_hooks==false then return end
   local class=safe(function()return c:GetClass()end)
   local full=valid(class)and safe(function()return class:GetFullName()end)
   local path=type(full)=='string'and full:match('^[^ ]+ (/.+)$')
   if not path then return end
   path=path..':FireProjectile';if attempted[path]then return end;attempted[path]=true
   local finder=options.find_function or StaticFindObject
   local exists=safe(function()return finder(path)end)
   if valid(exists)then hook(path,on_fire)end
  end
 end
 return api
end
return M
