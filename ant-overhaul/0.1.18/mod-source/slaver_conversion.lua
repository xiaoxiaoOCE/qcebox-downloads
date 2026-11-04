-- Same-species ColonyCreature -> SwarmCreature transaction. Disabled by default.
-- Native saves cannot restore a foreign NurseryTile under a new colony owner.
local M={schema=1,prefix='EAA_SlaverCopy_v1:',matches={}}
local function pair(source,target)
 local a='/Game/Blueprints/Creatures/'..source
 local b='/Game/Blueprints/Creatures/'..target
 M.matches[a..'.'..source:match('[^/]+$')..'_C']=b..'.'..target:match('[^/]+$')..'_C'
end
for _,name in ipairs({'BlackAnt','BlackAntWorker'})do pair('BlackAnt/'..name,'BlackAnt/Swarm'..name)end
for _,name in ipairs({'FireAntPervasive','FireAntVigorous','FireAntWorker'})do pair('FireAnt/'..name,'FireAnt/Swarm'..name)end
for _,name in ipairs({'BigHeadedMajor','BigHeadedMinor','BigHeadedSuperSoldier'})do pair('BigHeadedAnt/'..name,'BigHeadedAnt/Swarm'..name)end
for _,name in ipairs({'LittleBlackAnt','LittleBlackAntWorker'})do pair('LittleBlackAnt/'..name,'LittleBlackAnt/Swarm'..name)end
for _,name in ipairs({'LeafcutterMajorStun','LeafcutterMajorTaunt','LeafcutterMedia','LeafcutterMinor'})do pair('Leafcutter/'..name,'Leafcutter/Swarm'..name)end
for _,name in ipairs({'MatabeleMedicAnesthetist','MatabeleMedicFastResponder','MatabeleSoldier','MatabeleWorker'})do pair('MatabeleAnt/'..name,'MatabeleAnt/Swarm'..name)end
for _,name in ipairs({'DriverAntLargeSoldier','DriverAntSoldier','DriverAntWorker','StinkAnt'})do pair('OtherColonyCreaturesAfrica/'..name,'African/Swarm'..name)end
for _,name in ipairs({'ArmyAnt','ArmyAntMajor','ArmyAntMedia','TrapjawAnt'})do pair('OtherColonyCreatures/'..name,'Rainforest/Swarm'..name)end
pair('OtherColonyCreatures/SlaveMaker','Forest/SlaveMakerSwarm')
pair('BulletAnt/BulletAnt','BulletAnt/SwarmBulletAnt')
pair('WoodAnt/WoodAntASlow','WoodAnt/SwarmWoodAntA')
pair('WoodAnt/WoodAntBSlow','WoodAnt/SwarmWoodAntB')
pair('WoodAnt/WoodAntSoldier','WoodAnt/SwarmWoodAntSoldier')
for _,name in ipairs({'ExplodingAntSoldier','ExplodingAntMajorSoldier'})do
 local p='/Game/DLC/ExplodingAnts_DLC/Blueprints/ExplodingAnts/'
 M.matches[p..name..'.'..name..'_C']=p..'Swarm'..name..'.Swarm'..name..'_C'
end
M.unsupported={'LeafcutterSuperMajor','WoodAntWorker','TrapJawWorker','ExplodingAntWorker','NarrowHeadedAntRanged','NarrowHeadedAntSoldier'}
local ant_classes={};for a,b in pairs(M.matches)do ant_classes[a]=true;ant_classes[b]=true end
local scalar_fields={'CreatureLevel','FullHealth','AttackDamage','BasicAttackThreatGeneration','AttackSpeed','PointValue',
 'DigAmmount','DigSpeed','PhysicalResist','VenomResist','Armour','Evasion','HealthPerSecond','MaxSingleDamage',
 'Piercing','SlowResist','FoodHarvestTime','FoodCarryMax','PickupTime','TargetRadius','ArrivalDist','ReachableDist',
 'AttackTolDist','ThornsResist','AOEResistance','DamageFromFrontMultiplyer','OriginalMaxSpeed','FoodValue',
 'InitalMeshScale','MeshScaleIncreasePerLevel'}
local bool_fields={'CannotBePickedUp','CannotBeExercuted','CannotBeStunned','CannotBeConfused','CannotFlee',
 'CannotBeStrongPickedUp','CannotBeKnockedBack','IgnoreTileSlows','CombatEvasion','EncumberedWhenCarrying',
 'RandomiseCooldownsOnCombat','ZeroCooldownsOnCombat','CanNotTargetAttackPoints'}
local ability_fields={'AbilityType','MinRange','MaxRange','Damage','DamageType','AOERad','AOEFalloff','Rate','CooldownTimer',
 'Cooldown','CDRefillAllCharges','Charges','FullCharges','TargetLocation','Animation','AnimPlayType','Trigger',
 'TriggerThreshold','HitType','ThreatGeneration','ChanceToUse','UsageLocation','PickupStrength','DoNotTurnToTarget'}
local effect_fields={'Type','Length','Interval','Timer','Damage','DamageType','SpecialEffect','StackType','StackMax','CausingColonyID','CausingTileID'}
local function safe(f)local ok,v=pcall(f);if ok then return v end end
local function unbox(v)local n=v~=nil and safe(function()return v:get()end);return n~=nil and n or v end
local function num(v)local n=tonumber(unbox(v));assert(n and n==n and math.abs(n)<math.huge,'slave_copy_invalid_number');return n end
local function str(v)v=unbox(v);return type(v)=='string'and v or v and safe(function()return v:ToString()end)end
local function each(a,f)
 if type(a)=='table'and type(a.GetArrayNum)~='function'then for i,v in ipairs(a)do f(i,unbox(v))end;return end
 local n=num(a:GetArrayNum());assert(n>=0 and n<=4096,'slave_copy_invalid_array')
 for i=1,n do f(i,unbox(a[i]))end
end
local function path(c)return c:GetClass():GetFullName():match('^[^ ]+ (.+)$')end
local function value(v)
 v=unbox(v);if type(v)=='boolean'then return v end
 return num(v)
end
local function snapshot(c,trace)
 local s={stats={},abilities={}}
 trace('snapshot:scalars:begin')
 for _,k in ipairs(scalar_fields)do trace('snapshot:scalar:'..k);s.stats[k]=num(c[k])end
 for _,k in ipairs(bool_fields)do trace('snapshot:bool:'..k);local v=unbox(c[k]);assert(type(v)=='boolean','slave_copy_invalid_bool:'..k);s.stats[k]=v end
 trace('snapshot:abilities:begin')
 each(c.AbilityList,function(i,a)
  trace('snapshot:ability:'..i..':name')
  local row={AbilityName=assert(str(a.AbilityName),'slave_copy_ability_name'),Effects={}}
  for _,k in ipairs(ability_fields)do trace('snapshot:ability:'..i..':'..k);row[k]=value(a[k])end
  trace('snapshot:ability:'..i..':effects:begin')
  each(a.Effects,function(j,e)
   trace('snapshot:effect:'..i..':'..j..':names')
   local effect={EffectName=assert(str(e.EffectName),'slave_copy_effect_name'),EventName=assert(str(e.EventName),'slave_copy_event_name')}
   for _,k in ipairs(effect_fields)do trace('snapshot:effect:'..i..':'..j..':'..k);effect[k]=num(e[k])end;row.Effects[j]=effect
  end)
  s.abilities[i]=row
 end)
 assert(s.stats.CreatureLevel>=1 and s.stats.CreatureLevel<=3 and s.stats.FullHealth>0,'slave_copy_invalid_level_or_health')
 trace('snapshot:complete')
 return s
end
local function encoded(v)
 if type(v)=='string'then return's'..v:gsub('.',function(c)return string.format('%02x',c:byte())end)end
 if type(v)=='boolean'then return v and'b1'or'b0'end
 return'n'..string.format('%.9g',num(v))
end
local function decoded(v)
 local t,s=v:sub(1,1),v:sub(2)
 if t=='b'then assert(s=='0'or s=='1','slave_copy_tag_bool');return s=='1'end
 if t=='n'then return num(s)end
 assert(t=='s'and #s%2==0 and not s:find('[^0-9a-fA-F]'),'slave_copy_tag_string')
 return(s:gsub('..',function(c)return string.char(tonumber(c,16))end))
end
local function persisted(s)
 local out={};local function add(k,v)local t=M.prefix..k..':'..encoded(v);assert(#t<900,'slave_copy_tag_too_long');out[#out+1]=t end
 add('H:A',#s.abilities)
 for k,v in pairs(s.stats)do add('S:'..k,v)end
 for i,a in ipairs(s.abilities)do
  add('H:E:'..i,#a.Effects)
  for k,v in pairs(a)do if k~='Effects'then add('A:'..i..':'..k,v)end end
  for j,e in ipairs(a.Effects)do for k,v in pairs(e)do add('E:'..i..':'..j..':'..k,v)end end
 end
 if s.visual then
  for k,v in pairs(s.visual)do
   if k=='materials'then for i,p in ipairs(v)do add('V:material:'..i,p)end else add('V:'..k,v)end
  end
 end
 assert(#out<=2048,'slave_copy_snapshot_too_large');table.sort(out);return out
end
local dormant={Charges=0,FullCharges=0,ChanceToUse=0,Cooldown=-1,CooldownTimer=-1,CDRefillAllCharges=true,Trigger=0}
local dormant_effect_prefix='EAA_SlaverDormant_'
local dormant_effect_fields={Damage=0,Length=0,Timer=0,Interval=-1,SpecialEffect=15}
local known_profile_effects={WoodAntCorrosiveSlow=0,WoodAntWeakeningSlow=13}
local function native_rows(c)
 local rows={};each(c.AbilityList,function(i,a)rows[i]=a end)
 assert(#rows<=128,'slave_copy_ability_overflow');return rows
end
local function ability_slot(rows,name,occurrence)
 local count=0
 for i,a in ipairs(rows)do if str(a.AbilityName)==name then count=count+1;if count==occurrence then return i end end end
end
local function restore_snapshot(c,s,keep_timers,trace)
 trace('restore:begin')
 local rows=native_rows(c);local timers,seen={},{}
 for _,a in ipairs(rows)do
  local name=assert(str(a.AbilityName));seen[name]=(seen[name]or 0)+1
  timers[name]=timers[name]or{};timers[name][seen[name]]={CooldownTimer=num(a.CooldownTimer),Charges=num(a.Charges)}
 end
 local occurrences,slots,abilities,used={},{},{},{}
 for i,a in ipairs(s.abilities)do
  local name=a.AbilityName;occurrences[name]=(occurrences[name]or 0)+1
  local occurrence=occurrences[name];local slot=ability_slot(rows,name,occurrence)
  if not slot then
   -- Native InjectAbility copies the complete data-table row, including its
   -- nested effects. Its position is zero-based and lacks bounds checking.
   -- Append only at Num; never assign a Lua table to the nested native array.
   local n=#rows;assert(n<128,'slave_copy_ability_overflow')
   trace('restore:InjectAbility:'..name..':begin');c:InjectAbility(FName(name),n)
   rows=native_rows(c) -- The native insertion may invalidate every old wrapper.
   assert(#rows==n+1 and str(rows[n+1].AbilityName)==name,'slave_copy_native_injection_failed:'..name)
   trace('restore:InjectAbility:'..name..':end');slot=assert(ability_slot(rows,name,occurrence))
  end
  slots[i]=slot;used[slot]=true
  local row={Effects={}}
  for _,k in ipairs(ability_fields)do assert(a[k]~=nil,'slave_copy_ability_field_missing');row[k]=a[k]end
  local previous=timers[name]and timers[name][occurrence]
  if keep_timers and previous then row.CooldownTimer=previous.CooldownTimer;row.Charges=previous.Charges end
  for j,e in ipairs(a.Effects)do local er={};for _,k in ipairs(effect_fields)do er[k]=num(e[k])end;row.Effects[j]=er end
  abilities[i]=row
 end
 -- Resolve effects only after ALL native insertions, so no stale wrapper is
 -- retained across a TArray relocation. Match native effects by stable names;
 -- native own-colony lookup may append the two known WoodAnt profile effects.
 local effects,extra_effects={},{ }
 for i,a in ipairs(s.abilities)do
  local es,used_effects={},{};each(rows[slots[i]].Effects,function(j,e)es[j]=e end);effects[i]={}
  for j,e in ipairs(a.Effects)do
   local slot
   for k,candidate in ipairs(es)do
    if not used_effects[k]and str(candidate.EffectName)==e.EffectName and str(candidate.EventName)==e.EventName then slot=k;break end
   end
   assert(slot,'slave_copy_effect_layout_mismatch:'..a.AbilityName)
   used_effects[slot]=true;effects[i][j]={slot=slot,row=es[slot]}
  end
  for j,e in ipairs(es)do if not used_effects[j]then
   local name=assert(str(e.EffectName));local original=name
   if original:sub(1,#dormant_effect_prefix)==dormant_effect_prefix then original=original:sub(#dormant_effect_prefix+1)end
   assert(known_profile_effects[original]~=nil and num(e.Type)==known_profile_effects[original],
    'slave_copy_effect_layout_mismatch:'..a.AbilityName)
   extra_effects[#extra_effects+1]={ability=slots[i],slot=j,row=e,name=dormant_effect_prefix..original,event=assert(str(e.EventName))}
  end end
 end
 -- Type0's native tick can apply damage BEFORE checking an expired Length.
 -- Zero Damage first; Type13 also becomes neutral with zero magnitude.
 -- A private name prevents this inert entry replacing a real same-name debuff
 -- already applied by another unit. None=15; SpecialEffect0 is GreenGlow.
 for _,entry in ipairs(extra_effects)do
  entry.row.Damage=0
  entry.row.EffectName=FName(entry.name)
  for k,v in pairs(dormant_effect_fields)do entry.row[k]=v end
 end
 for k,v in pairs(s.stats)do trace('restore:scalar:'..k);c[k]=v end
 for i,a in ipairs(abilities)do
  for _,k in ipairs(ability_fields)do trace('restore:ability:'..i..':'..k);rows[slots[i]][k]=a[k]end
  for j,e in ipairs(a.Effects)do for _,k in ipairs(effect_fields)do effects[i][j].row[k]=e[k]end end
 end
 -- Own-colony profile lookup can inject skills that this captured individual
 -- never had. Keep native storage intact but make those entries inert: both
 -- normal selection and out-of-combat self-casts require nonzero charges;
 -- zero FullCharges prevents cooldown/refill code from re-enabling them.
 for i,a in ipairs(rows)do if not used[i]then for k,v in pairs(dormant)do a[k]=v end end end
 trace('restore:readback:begin')
 local function equal_value(actual,expected,label)
  actual=value(actual)
  if type(expected)=='boolean'then assert(actual==expected,'slave_copy_readback:'..label)
  else assert(math.abs(num(actual)-expected)<=math.max(1e-5,math.abs(expected)*1e-5),'slave_copy_readback:'..label)end
 end
 for k,v in pairs(s.stats)do equal_value(c[k],v,k)end
 local fresh=native_rows(c);assert(#fresh==#rows,'slave_copy_readback_ability_count')
 for i,a in ipairs(s.abilities)do
  local actual=fresh[slots[i]];assert(str(actual.AbilityName)==a.AbilityName,'slave_copy_readback_ability_name')
  for _,k in ipairs(ability_fields)do equal_value(actual[k],abilities[i][k],'ability:'..i..':'..k)end
  local actual_effects={};each(actual.Effects,function(j,e)actual_effects[j]=e end)
  for j,saved in ipairs(a.Effects)do
   local e=assert(actual_effects[effects[i][j].slot],'slave_copy_readback_effect_missing')
   assert(str(e.EffectName)==saved.EffectName and str(e.EventName)==saved.EventName,'slave_copy_readback_effect_name')
   for _,k in ipairs(effect_fields)do equal_value(e[k],saved[k],'effect:'..i..':'..j..':'..k)end
  end
 end
 for _,entry in ipairs(extra_effects)do
  local es={};each(fresh[entry.ability].Effects,function(j,e)es[j]=e end);local e=assert(es[entry.slot])
  assert(str(e.EffectName)==entry.name and str(e.EventName)==entry.event,'slave_copy_dormant_effect_name')
  for k,v in pairs(dormant_effect_fields)do equal_value(e[k],v,'dormant_effect:'..entry.ability..':'..entry.slot..':'..k)end
 end
 for i,a in ipairs(fresh)do if not used[i]then for k,v in pairs(dormant)do equal_value(a[k],v,'dormant:'..i..':'..k)end end end
 trace('restore:MaxWalkSpeed:begin');c.CreatureMovement.MaxWalkSpeed=s.stats.OriginalMaxSpeed;trace('restore:complete')
end
function M.install(options)
 local native=assert(options.native,'slave_conversion_native_required');local api={};local class_cache={}
 local pending,queued,attempted={},{},{}
 local function trace(label)if type(options.trace)=='function'then pcall(options.trace,label)end end
 local function valid(c)return c~=nil and safe(function()return native.valid_object(c)end)==true end
 local function request_path(p)
  if not p then return false end
  local cls=class_cache[p];if not valid(cls)then cls=StaticFindObject(p);class_cache[p]=cls end
  if valid(cls)or queued[p]or attempted[p]then return true end
  queued[p]=true;pending[#pending+1]=p;return true
 end
 local function resolve(c)
  local p=M.matches[path(c)];if not p then return nil,'slave_conversion_species_unmapped'end
  local cls=class_cache[p];if not valid(cls)then cls=StaticFindObject(p);class_cache[p]=cls end
  if not valid(cls)then return nil,'slave_conversion_class_not_loaded'end;return cls
 end
 local function asset_path(object)
  assert(valid(object),'slave_copy_visual_object_missing')
  local p=object:GetFullName():match('^[^ ]+ (/.+)$')
  assert(p and p:match('^/Game/')and not p:find(':',1,true),'slave_copy_visual_not_asset')
  return p
 end
 local function material_parent(material)
  local depth=0
  while valid(material)and material:GetClass():GetFullName()=='Class /Script/Engine.MaterialInstanceDynamic'do
   depth=depth+1;assert(depth<=8,'slave_copy_material_parent_depth');material=material.Parent
  end
  return asset_path(material)
 end
 local function parameter(material,array,name)
  local result,count=nil,0
  each(material[array],function(_,p)
   local info=p.ParameterInfo
   if str(info.Name)==name and num(info.Association)==2 and num(info.Index)==-1 then result=p.ParameterValue;count=count+1 end
  end)
  assert(count==1,'slave_copy_material_parameter_missing:'..name);return result
 end
 local function crab_materials(c)
  local body,shell=c.CrabMID,c.ShellMID;assert(valid(c.Shell)and valid(body)and valid(shell),'slave_copy_crab_material_missing')
  assert(body:GetAddress()==c.Mesh:GetMaterial(0):GetAddress()and shell:GetAddress()==c.Shell:GetMaterial(0):GetAddress(),'slave_copy_crab_material_binding')
  assert(body:GetClass():GetFullName()=='Class /Script/Engine.MaterialInstanceDynamic'and shell:GetClass():GetFullName()=='Class /Script/Engine.MaterialInstanceDynamic','slave_copy_crab_not_dynamic')
  return body,shell
 end
 local function visual_snapshot(c)
  local mesh=c.Mesh;assert(valid(mesh),'slave_copy_visual_mesh_missing')
  local scale=mesh.RelativeScale3D
  -- Native Swarm load adds NG+ scale levels again. Restore each captured
  -- individual's actual mesh size independently of that native rebuild.
  local v={sx=num(scale.X),sy=num(scale.Y),sz=num(scale.Z)}
  local name=str(c.CreatureName)
  if name=='SmallHermitCrab'then
   local body,shell=crab_materials(c)
   v.crab_random=num(parameter(body,'ScalarParameterValues','RandomVal'))
   v.shell_random=num(parameter(shell,'ScalarParameterValues','RandomVal'))
   v.shell_texture=asset_path(parameter(shell,'TextureParameterValues','BaseColourOpacity'))
  end
  local earwig=name=='Earwig'or name=='EarwigJuvenile'
  if not earwig and not ant_classes[path(c)]then return v end
  v.mesh=asset_path(mesh.SkeletalMesh);v.anim_class=asset_path(mesh:GetAnimClass());v.mode=num(mesh:GetAnimationMode())
  v.materials={};assert(v.mode==0,'slave_copy_visual_layout_invalid')
  -- Preserve stable material parents, not actor-owned MID object names.
  v.material_count=num(mesh:GetNumMaterials());v.materials={}
  assert(v.mode==0 and v.material_count>=0 and v.material_count<=16 and v.material_count%1==0,'slave_copy_visual_layout_invalid')
  for i=1,v.material_count do v.materials[i]=material_parent(mesh:GetMaterial(i-1))end
  return v
 end
 local visual_fields={mesh=true,anim_class=true,mode=true,sx=true,sy=true,sz=true,material_count=true,crab_random=true,shell_random=true,shell_texture=true}
 local function visual_tags(c)
  local v
  each(c.Tags,function(_,tag)
   local text=str(tag);if not text or text:sub(1,#M.prefix+2)~=M.prefix..'V:'then return end
   v=v or{materials={}};text=text:sub(#M.prefix+3)
   local index,encoded_path=text:match('^material:(%d+):(.+)$')
   if index then
    index=tonumber(index);assert(index>=1 and index<=16,'slave_copy_visual_material_index')
    v.materials[index]=decoded(encoded_path)
   else
    local k,value=text:match('^([%w_]+):(.+)$');assert(visual_fields[k],'slave_copy_visual_unknown_field')
    v[k]=decoded(value)
   end
  end)
  if not v then return nil end
  local function check_path(p)assert(type(p)=='string'and p:match('^/Game/')and not p:find(':',1,true),'slave_copy_visual_invalid_path')end
  for _,k in ipairs({'sx','sy','sz'})do local scale=num(v[k]);assert(scale>0 and scale<=100,'slave_copy_visual_scale_invalid')end
  if v.crab_random~=nil or v.shell_random~=nil or v.shell_texture~=nil then
   assert(num(v.crab_random)>=0 and num(v.crab_random)<=1 and num(v.shell_random)>=0 and num(v.shell_random)<=1,'slave_copy_crab_random_invalid')
   check_path(v.shell_texture)
  end
  if v.mesh~=nil or v.anim_class~=nil or v.mode~=nil or v.material_count~=nil or next(v.materials)then
   check_path(v.mesh);check_path(v.anim_class)
   assert(v.mode==0,'slave_copy_visual_mode_invalid')
   if v.material_count~=nil then
    local n=num(v.material_count);assert(n>=0 and n<=16 and n%1==0 and #v.materials==n,'slave_copy_visual_material_count')
    for i=1,n do check_path(v.materials[i])end
   else assert(next(v.materials)==nil,'slave_copy_visual_material_count')end
  end
  return v
 end
 local function request_visual(v)
  if not v then return false end
  if v.shell_texture then request_path(v.shell_texture)end
  if v.mesh then request_path(v.mesh);request_path(v.anim_class);for _,p in ipairs(v.materials)do request_path(p)end end
  return v.mesh~=nil or v.shell_texture~=nil
 end
 local function visual_assets(v)
  if not v or(not v.mesh and not v.shell_texture)then return true end
  local function resident(p)
   local a=class_cache[p];if not valid(a)then a=StaticFindObject(p);class_cache[p]=a end
   assert(valid(a)or not attempted[p],'slave_copy_visual_asset_load_failed:'..p)
   return valid(a)and a or nil
  end
  local resolved={materials={}};local ready=true
  if v.mesh then
   resolved.mesh=resident(v.mesh);resolved.anim_class=resident(v.anim_class)
   ready=resolved.mesh~=nil and resolved.anim_class~=nil
   for i,p in ipairs(v.materials)do resolved.materials[i]=resident(p);if not resolved.materials[i]then ready=false end end
  end
  if v.shell_texture then resolved.shell_texture=resident(v.shell_texture);if not resolved.shell_texture then ready=false end end
  if not ready then request_visual(v);return nil end
  if v.mesh then
   assert(resolved.mesh:GetFullName():match('^SkeletalMesh '),'slave_copy_visual_mesh_type')
   assert(resolved.anim_class:GetFullName():match('^AnimBlueprintGeneratedClass '),'slave_copy_visual_animation_type')
  end
  if v.shell_texture then assert(resolved.shell_texture:GetFullName():match('^Texture2D '),'slave_copy_shell_texture_type')end
  for _,a in ipairs(resolved.materials)do
   local kind=a:GetFullName():match('^(%S+) ')
   assert(kind=='Material'or kind=='MaterialInstanceConstant','slave_copy_visual_material_type')
  end
  return resolved
 end
 local function restore_visual(c,v,resolved)
  if not v then return end
  local mesh=c.Mesh;assert(valid(mesh),'slave_copy_visual_mesh_missing')
  if v.mesh then
   local changed=asset_path(mesh.SkeletalMesh)~=v.mesh
   if changed then trace('restore:visual:mesh');mesh:SetSkeletalMesh(resolved.mesh,true)end
   if changed or asset_path(mesh:GetAnimClass())~=v.anim_class then trace('restore:visual:animation');mesh:SetAnimClass(resolved.anim_class)end
   if num(mesh:GetAnimationMode())~=v.mode then mesh:SetAnimationMode(v.mode)end
   for i,p in ipairs(v.materials)do
    local old=mesh:GetMaterial(i-1)
    if material_parent(old)~=p then
     if old:GetClass():GetFullName()=='Class /Script/Engine.MaterialInstanceDynamic'then
      -- Keep current native team-colour parameters when restoring the original
      -- worker/soldier material parent. Never freeze an enemy team's colour.
      local scalar,vector={},{}
      each(old.ScalarParameterValues,function(_,x)local info=x.ParameterInfo;if num(info.Association)==2 and num(info.Index)==-1 then scalar[#scalar+1]={name=str(info.Name),value=num(x.ParameterValue)}end end)
      each(old.VectorParameterValues,function(_,x)local info=x.ParameterInfo;if num(info.Association)==2 and num(info.Index)==-1 then local a=x.ParameterValue;vector[#vector+1]={name=str(info.Name),value={R=num(a.R),G=num(a.G),B=num(a.B),A=num(a.A)}}end end)
      local alias=safe(function()return c.DynamicMaterialInstance end)
      local linked=valid(alias)and alias:GetAddress()==old:GetAddress()
      local made=mesh:CreateDynamicMaterialInstance(i-1,resolved.materials[i],FName('None'))
      assert(valid(made),'slave_copy_dynamic_material_create_failed')
      for _,x in ipairs(scalar)do made:SetScalarParameterValue(FName(x.name),x.value)end
      for _,x in ipairs(vector)do made:SetVectorParameterValue(FName(x.name),x.value)end
      if linked then c.DynamicMaterialInstance=made end
     else mesh:SetMaterial(i-1,resolved.materials[i])end
    end
   end
   assert(asset_path(mesh.SkeletalMesh)==v.mesh and asset_path(mesh:GetAnimClass())==v.anim_class,'slave_copy_visual_readback')
   if v.material_count~=nil then assert(num(mesh:GetNumMaterials())==v.material_count,'slave_copy_visual_material_readback')end
   for i,p in ipairs(v.materials)do assert(material_parent(mesh:GetMaterial(i-1))==p,'slave_copy_visual_material_readback')end
  end
  mesh:SetRelativeScale3D({X=v.sx,Y=v.sy,Z=v.sz})
  local scale=mesh.RelativeScale3D
  for axis,k in pairs({X='sx',Y='sy',Z='sz'})do assert(math.abs(num(scale[axis])-v[k])<1e-5,'slave_copy_visual_scale_readback')end
  if v.shell_texture then
   local body,shell=crab_materials(c)
   body:SetScalarParameterValue(FName('RandomVal'),v.crab_random)
   shell:SetScalarParameterValue(FName('RandomVal'),v.shell_random)
   shell:SetTextureParameterValue(FName('BaseColourOpacity'),resolved.shell_texture)
   assert(math.abs(num(parameter(body,'ScalarParameterValues','RandomVal'))-v.crab_random)<1e-5 and math.abs(num(parameter(shell,'ScalarParameterValues','RandomVal'))-v.shell_random)<1e-5,'slave_copy_crab_random_readback')
   assert(asset_path(parameter(shell,'TextureParameterValues','BaseColourOpacity'))==v.shell_texture,'slave_copy_shell_texture_readback')
  end
 end
 -- Request from the existing creature-observation pass; call preload_step
 -- from a bounded non-combat setup tick. No asset loads occur in can_convert,
 -- lethal damage callbacks, snapshot restore, or the actual queen conversion.
 function api.request(c)
  local ok,result=pcall(function()
   if not valid(c)then return false end
   local counterpart=request_path(M.matches[path(c)])
   local visual=request_visual(visual_tags(c));return counterpart or visual
  end)
  if not ok then return nil,tostring(result)end;return result
 end
 function api.preload_step(limit)
  local ok,result=pcall(function()
   limit=limit or 1;assert(type(limit)=='number'and limit>=1 and limit<=4 and limit%1==0,'slave_copy_preload_bound')
   local report={loaded=0,failed={},pending=0}
   for _=1,limit do
    local p=table.remove(pending,1);if not p then break end
    queued[p]=nil;attempted[p]=true
    local cls=StaticFindObject(p)
    if not valid(cls)then
     local loader=options.load_asset or LoadAsset
     local loaded,object=pcall(loader,p)
     if loaded then cls=object else report.failed[#report.failed+1]={path=p,error=tostring(object)}end
    end
    if valid(cls)then class_cache[p]=cls;report.loaded=report.loaded+1
    elseif #report.failed==0 or report.failed[#report.failed].path~=p then report.failed[#report.failed+1]={path=p,error='slave_conversion_class_not_loaded'}end
   end
   report.pending=#pending;return report
  end)
  if not ok then return nil,tostring(result)end;return result
 end
 -- A copied creature already contains its complete individual native and
 -- extended stat allocation. Callers must not run extra.apply on it again.
 -- A native stats rebuild must finish first, then restore() replaces the
 -- rebuilt values once while preserving current HP and ability timers.
 function api.has_snapshot(c)
  if not valid(c)then return false end
  local ok,result=pcall(function()
   local found=false;each(c.Tags,function(_,t)local s=str(t);if s and s:sub(1,#M.prefix)==M.prefix then found=true end end)
   return found
  end)
  if not ok then return nil,tostring(result)end;return result
 end
 function api.can_convert(c)
  if options.verified~=true or not valid(c)then return false end
  local ok,cls=pcall(resolve,c);return ok and valid(cls)
 end
 function api.apply_team_colour(c,grid)
  local ok,result=pcall(function()
   assert(valid(c)and valid(grid),'slave_team_colour_context_invalid')
   if not ant_classes[path(c)]then return false end
   assert(num(c.ColonyID)==num(grid.ColonyID),'slave_team_colour_owner_mismatch')
   local colour=grid:GetTeamColour(false)
   local value={R=num(colour.R),G=num(colour.G),B=num(colour.B),A=num(colour.A)}
   local mesh=c.Mesh;assert(valid(mesh),'slave_team_colour_mesh_missing')
   local count=num(mesh:GetNumMaterials());assert(count>=0 and count<=16 and count%1==0,'slave_team_colour_material_count')
   for i=0,count-1 do
    local material=mesh:GetMaterial(i)
    if valid(material)and material:GetClass():GetFullName()=='Class /Script/Engine.MaterialInstanceDynamic'then
     material:SetVectorParameterValue(FName('TeamColour'),value)
     local actual=parameter(material,'VectorParameterValues','TeamColour')
     for _,axis in ipairs({'R','G','B','A'})do assert(math.abs(num(actual[axis])-value[axis])<1e-5,'slave_team_colour_readback')end
    end
   end
   return true
  end)
  if not ok then return nil,tostring(result)end;return result
 end
 function api.capture_snapshot(c)
  local previous,writing
  local ok,result=pcall(function()
   assert(valid(c)and num(c.Health)>0,'slave_copy_source_not_alive')
   local existing,why=api.has_snapshot(c);assert(existing~=nil,why)
   if existing then return false end
   local before=snapshot(c,trace);before.visual=visual_snapshot(c);local ts={}
   previous={}
   each(c.Tags,function(_,t)local n=FName(assert(str(t),'slave_copy_tag_name_missing'));ts[#ts+1]=n;previous[#previous+1]=n end)
   for _,t in ipairs(persisted(before))do ts[#ts+1]=FName(t)end
   trace('capture_snapshot:Tags:write:begin');writing=true;c.Tags=ts;trace('capture_snapshot:Tags:write:end')
   assert(api.has_snapshot(c)==true,'slave_copy_tag_readback_failed')
   return true
  end)
  if not ok then
   if writing and previous and valid(c)then safe(function()c.Tags=previous end)end
   return nil,tostring(result)
  end;return result
 end
 function api.discard_snapshot(c)
  local ok,result=pcall(function()
   assert(valid(c),'slave_copy_source_invalid');local ts={}
   each(c.Tags,function(_,t)local n=assert(str(t));if n:sub(1,#M.prefix)~=M.prefix then ts[#ts+1]=FName(n)end end)
   c.Tags=ts;assert(api.has_snapshot(c)==false,'slave_copy_discard_readback_failed');return true
  end)
  if not ok then return nil,tostring(result)end;return result
 end
 function api.prepare(source,ctx)
  local made
  local ok,result=pcall(function()
   trace('prepare:validate:begin')
   assert(options.verified==true,'slave_conversion_not_validated')
   assert(valid(source),'slave_conversion_source_invalid')
   assert(num(source.Health)>0,'slave_conversion_source_not_alive')
   local cls,reason=resolve(source);assert(cls,reason)
   trace('prepare:resolve:done')
   local before=snapshot(source,trace);before.visual=visual_snapshot(source)
   local resolved_visual=assert(visual_assets(before.visual),'slave_copy_assets_not_loaded')
   local source_name=str(source.CreatureName)
   local helper=StaticFindObject('/Script/Engine.Default__GameplayStatics');assert(valid(helper),'slave_conversion_spawn_helper')
   trace('prepare:transform:begin');local transform=source:GetTransform();trace('prepare:transform:end')
   trace('prepare:BeginDeferredActorSpawnFromClass:begin')
   made=helper:BeginDeferredActorSpawnFromClass(source,cls,transform,1,nil);assert(valid(made),'slave_conversion_spawn_failed')
   trace('prepare:BeginDeferredActorSpawnFromClass:end')
   made.ColonyID=ctx.owner;made.ColonyLocation=num(source.ColonyLocation);made.CreatureLevel=before.stats.CreatureLevel
   made.Immobile=true;made.CanBeAttacked=false;made.NoCombat=true;made.NoneBTControl=true
   trace('prepare:FinishSpawningActor:begin')
   made=helper:FinishSpawningActor(made,transform);assert(valid(made),'slave_conversion_finish_failed')
   trace('prepare:FinishSpawningActor:end')
   -- Several native counterpart classes only auto-possess placed actors.
   -- A deferred runtime spawn therefore needs its own normal AI controller.
   trace('prepare:controller:begin')
   local controller=made:GetController()
   if not valid(controller)then
    made:SpawnDefaultController();controller=made:GetController()
   end
   assert(valid(controller),'slave_conversion_controller_missing')
   local brain=controller.BrainComponent
   assert(valid(brain),'slave_conversion_brain_missing')
   local prepared_brain={controller=controller,brain=brain,was_running=brain:IsRunning()==true}
   controller:StopMovement();brain:StopLogic('Ant Overhaul prepared conversion')
   trace('prepare:controller:stopped')
   assert(str(made.CreatureName)==source_name,'slave_conversion_name_mismatch')
   trace('prepare:mesh:begin');local a,b=source.Mesh.SkeletalMesh,made.Mesh.SkeletalMesh
   assert(valid(a)and valid(b)and a:GetFullName()==b:GetFullName(),'slave_conversion_mesh_mismatch')
   trace('prepare:mesh:end');trace('prepare:ChangeColonyID:begin')
   made:ChangeColonyID(ctx.owner,0,true);trace('prepare:ChangeColonyID:end')
   restore_snapshot(made,before,false,trace);restore_visual(made,before.visual,resolved_visual)
   trace('prepare:Health:begin');made.Health=made.FullHealth
   trace('prepare:Tags:build:begin')
   local ts={};each(source.Tags,function(_,t)local n=assert(str(t));if n:sub(1,#M.prefix)~=M.prefix then ts[#ts+1]=FName(n)end end)
   for _,t in ipairs(persisted(before))do ts[#ts+1]=FName(t)end
   trace('prepare:Tags:write:begin');made.Tags=ts;trace('prepare:Tags:write:end')
   local tx={creature=made,source=source,snapshot=before,prepared_brain=prepared_brain,committed=false}
   function tx.rollback()
    if tx.committed then return nil,'slave_conversion_already_committed'end
    if valid(made)then made:K2_DestroyActor()end;return true
   end
   function tx.commit()
    assert(not tx.committed and valid(made)and valid(source),'slave_conversion_commit_invalid')
    source:K2_DestroyActor()
    assert(not valid(source),'slave_conversion_source_not_destroyed');tx.committed=true;return true
   end
   trace('prepare:ready');return tx
  end)
  if not ok then if valid(made)then safe(function()made:K2_DestroyActor()end)end;return nil,tostring(result)end
  return result
 end
 function api.restore(c)
  local ok,result=pcall(function()
   local s={stats={},abilities={}};local count=0;local ability_count;local effect_counts={}
   local allowed_stats={};for _,k in ipairs(scalar_fields)do allowed_stats[k]=true end;for _,k in ipairs(bool_fields)do allowed_stats[k]=true end
   local allowed_abilities={AbilityName=true};for _,k in ipairs(ability_fields)do allowed_abilities[k]=true end
   local allowed_effects={EffectName=true,EventName=true};for _,k in ipairs(effect_fields)do allowed_effects[k]=true end
   each(c.Tags,function(_,tag)
    local text=str(tag);if not text or text:sub(1,#M.prefix)~=M.prefix then return end
    count=count+1;assert(count<=2048,'slave_copy_tag_overflow');text=text:sub(#M.prefix+1)
    if text:sub(1,2)=='V:'then return end
    local header=text:match('^H:A:(.+)$');if header then ability_count=decoded(header);assert(type(ability_count)=='number'and ability_count>=0 and ability_count<=128 and ability_count%1==0,'slave_copy_invalid_count');return end
    local hi,hv=text:match('^H:E:(%d+):(.+)$');if hi then effect_counts[tonumber(hi)]=decoded(hv);return end
    local k,v=text:match('^S:([%w_]+):(.+)$')
    if k then assert(allowed_stats[k],'slave_copy_unknown_stat');s.stats[k]=decoded(v);return end
    local i,ak,av=text:match('^A:(%d+):([%w_]+):(.+)$')
    if i then i=tonumber(i);assert(i>=1 and i<=128 and allowed_abilities[ak],'slave_copy_unknown_ability_field');s.abilities[i]=s.abilities[i]or{Effects={}};s.abilities[i][ak]=decoded(av);return end
    local ei,ej,ek,ev=text:match('^E:(%d+):(%d+):([%w_]+):(.+)$');assert(ei,'slave_copy_invalid_tag')
    ei,ej=tonumber(ei),tonumber(ej);assert(ei>=1 and ei<=128 and ej>=1 and ej<=128 and allowed_effects[ek],'slave_copy_unknown_effect_field')
    s.abilities[ei]=s.abilities[ei]or{Effects={}};s.abilities[ei].Effects[ej]=s.abilities[ei].Effects[ej]or{};s.abilities[ei].Effects[ej][ek]=decoded(ev)
   end)
   if count==0 then return false end
   for _,k in ipairs(scalar_fields)do num(s.stats[k])end;for _,k in ipairs(bool_fields)do assert(type(s.stats[k])=='boolean','slave_copy_missing_bool')end
   assert(ability_count~=nil,'slave_copy_missing_count')
   for i=1,ability_count do
    local a=assert(s.abilities[i],'slave_copy_missing_ability');assert(type(a.AbilityName)=='string','slave_copy_missing_ability_name')
    local ec=effect_counts[i];assert(type(ec)=='number'and ec>=0 and ec<=128 and ec%1==0,'slave_copy_invalid_effect_count')
    for j=1,ec do assert(a.Effects[j],'slave_copy_missing_effect')end
    assert(#a.Effects==ec,'slave_copy_extra_effects')
   end
   assert(#s.abilities==ability_count,'slave_copy_extra_abilities')
   s.visual=visual_tags(c)
   local resolved=visual_assets(s.visual)
   if not resolved then return false end
   local hp=num(c.Health);restore_snapshot(c,s,true,trace);c.Health=math.min(hp,c.FullHealth)
   restore_visual(c,s.visual,resolved);return true
  end)
  if not ok then return nil,tostring(result)end
  if result==false and api.has_snapshot(c)==true then return false,'slave_copy_assets_pending'end
  return result
 end
 return api
end
return M
