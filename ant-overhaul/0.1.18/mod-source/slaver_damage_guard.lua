-- Bracket one synchronous native BasicAttack. No estimated armour/damage.
local M={effect='EAA_Slaver_LethalGuard',floor=2^-100,min_health=2^-20}
local function safe(f)local ok,v=pcall(f);if ok then return v end end
local function unbox(v)local x=v and safe(function()return v:get()end);return x~=nil and x or v end
local function number(v)local n=tonumber(unbox(v));return n and n==n and n~=math.huge and n~=-math.huge and n or nil end
local function name(v)v=unbox(v);return type(v)=='string'and v or(v and safe(function()return v:ToString()end))end
local function each(a,fn)
 if type(a)=='table'and type(a.GetArrayNum)~='function'then for _,v in ipairs(a)do fn(v)end;return end
 local n=a:GetArrayNum();assert(n>=0 and n<=512,'invalid_effect_array')
 for i=1,n do fn(unbox(a[i]))end
end
function M.install(options)
 assert(type(options)=='table'and type(options.native)=='table','guard_native_required')
 local native=options.native
 local active,stopped={},false
 local api={}
 local function valid(c)return c and native.valid_object(c)==true end
 local function key(c)return valid(c)and tostring(c:GetAddress())or nil end
 local function identity(c)return valid(c)and c:GetFullName()or nil end
 local function own(c)
  local found
  each(c.Effects,function(e)if name(e.EffectName)==M.effect then assert(not found,'duplicate_lethal_guard');found=e end end)
  return found
 end
 local function cleanup(token)
  local c=token.victim
  if valid(c)and identity(c)==token.identity then
   each(c.Effects,function(e)
    if name(e.EffectName)~=M.effect then return end
    assert(number(e.Type)==30,'lethal_guard_type_changed')
    -- Zero is no protection: native death check is Health<=0. Expire on the
    -- next normal effect tick without touching any unrelated effect timers.
    e.Damage=0;e.Length=0;e.Timer=0
    assert(number(e.Damage)==0 and number(e.Length)==0,'lethal_guard_cleanup_failed')
   end)
  end
  active[token.key]=nil;token.ended=true
 end
 function api.ready()return not stopped and options.verified==true end
 function api.begin_damage_guard(attacker,victim)
  if not api.ready()or not valid(attacker)or not valid(victim)then return nil end
  local hp,maximum=number(victim.Health),number(victim.FullHealth)
  if not hp or hp<M.min_health or not maximum or maximum<=0 then return nil end
  local selected=attacker.SelectedAbility
  if not selected or name(selected.AbilityName)~='BasicAttack'or number(selected.AbilityType)~=1 then return nil end
  local has_after_effect=false;each(selected.Effects,function()has_after_effect=true end)
  if has_after_effect then return nil end
  local id=key(victim);if not id or active[id]then return nil end
  local conflicting=false
  local own_count=0
  each(victim.Effects,function(e)
   if name(e.EffectName)==M.effect then own_count=own_count+1;if number(e.Type)~=30 then conflicting=true end end
   if number(e.Type)==30 and not(name(e.EffectName)==M.effect and number(e.Damage)==0 and number(e.Length)==0)then conflicting=true end
  end)
  if conflicting or own_count>1 then return nil end
  local token={victim=victim,attacker=attacker,key=id,identity=identity(victim),before=hp,attacker_identity=identity(attacker)}
  active[id]=token
  local ok,err=pcall(function()
   local e=own(victim)
   if e then e.Type=30;e.Damage=M.floor;e.Length=1;e.Timer=-1
   else
    victim:ApplyEffect({EffectName=FName(M.effect),Type=30,Length=1,Interval=-1,Timer=-1,Damage=M.floor,
     DamageType=0,SpecialEffect=0,StackType=0,StackMax=1,CausingColonyID=number(attacker.ColonyID),
     CausingTileID=-1,EventName=FName('None')})
   end
   local observed=assert(own(victim),'lethal_guard_not_applied')
   assert(number(observed.Type)==30 and number(observed.Damage)==M.floor,'lethal_guard_readback_failed')
  end)
  if not ok then cleanup(token);error(err)end
  return token
 end
 function api.end_damage_guard(token,attack_succeeded)
  assert(type(token)=='table'and not token.ended and active[token.key]==token,'invalid_lethal_guard_token')
  local c=token.victim
  local after=valid(c)and identity(c)==token.identity and number(c.Health)or nil
  -- Exact equality, never epsilon: pre Health >= 2^-20 and float32
  -- subtraction cannot produce a positive residue between 0 and 2^-100.
  -- Native Type30 applies its floor AFTER actual mitigated damage and hurt
  -- responses. Existing floors and post-damage basic-attack effects are gated.
  local lethal=after==M.floor
  cleanup(token)
  token.lethal=lethal
  return{exact=true,lethal=lethal,before=token.before,after=after,native_attack_succeeded=attack_succeeded==true}
 end
 function api.cancel_damage_guard(token)
  if type(token)~='table'or token.ended then return false end
  local lethal=valid(token.victim)and identity(token.victim)==token.identity and number(token.victim.Health)==M.floor
  cleanup(token)
  if lethal then api.resolve_failed_capture(token,{exact=true,lethal=true})end
  return true
 end
 function api.resolve_failed_capture(token,evidence)
  if type(evidence)~='table'or evidence.lethal~=true or evidence.exact~=true then return false end
  local c=token.victim
  if not valid(c)or identity(c)~=token.identity then return false end
  if not token.ended then cleanup(token)end
  -- Only the same still-protected hit may be resolved; never kill a target
  -- that a completed capture/another native event has already healed.
  if number(c.Health)~=M.floor then return false end
  local killer=valid(token.attacker)and identity(token.attacker)==token.attacker_identity and token.attacker or nil
  c:KillCreature(killer)
  assert(not valid(c)or(number(c.Health)or 0)<=0,'ordinary_lethal_resolution_failed')
  return true
 end
 function api.stop()
  local pending={};for _,t in pairs(active)do pending[#pending+1]=t end
  for _,t in ipairs(pending)do api.cancel_damage_guard(t)end
  stopped=true;return true
 end
 return api
end
return M
