-- Food work for registered slaves. Import does not access the engine.
-- Native queries, resource actors, paths and storage transactions are retained;
-- this replaces only the wild Swarm carrying/escape decision branch.
local M={schema=1,interval=0.25,tile_budget=128,query_budget=8,task_timeout=60}
local DCH_EATING='/Game/Assets/3DModels/Beasts/OcypusOlens_Anim_Armature_Eating.OcypusOlens_Anim_Armature_Eating'
-- Verified on the original live meshes, not guessed from control-bone names.
local HEAD_SOCKET={Earwig=true,EarwigJuvenile=true,FBBLarva=true,CheckeredBeetleLarva=true,GreenJumperSpider=true}
local function safe(f)local ok,v=pcall(f);if ok then return v end end
local function unbox(v)local x=v~=nil and safe(function()return v:get()end);return x~=nil and x or v end
local function num(v)local n=tonumber(unbox(v));if n and n==n and math.abs(n)<math.huge then return n end end
local function str(v)v=unbox(v);return type(v)=='string'and v or v and safe(function()return v:ToString()end)end
local function count(a)if type(a)=='table'and type(a.GetArrayNum)~='function'then return #a end;return num(a:GetArrayNum())or 0 end
local function at(a,i)return unbox(a[i])end

function M.install(options)
 assert(type(options)=='table'and type(options.native)=='table'and type(options.adapter)=='table','slave_food_dependencies')
 assert(type(options.get_context)=='function','slave_food_context')
 local native,adapter=options.native,options.adapter
 local jobs,claims,classes,reported,stores,cooldowns,submitted={},{},{},{},{},{},{}
 local world,last_tick,scan_index,search_cursor,stopped=nil,-math.huge,1,1,false
 local totals={picked_up=0,harvested=0,delivered=0,partial_deposits=0,cancelled=0}
 local api={}
 local function valid(o)return o~=nil and safe(function()return native.valid_object(o)end)==true end
 local function key(o)
  if not valid(o)then return nil end
  return safe(function()return tostring(o:GetAddress())..'|'..o:GetFullName()end)
 end
 local function same(a,b)local k=key(a);return k~=nil and k==key(b)end
 local function is_a(o,name)
  if not valid(o)then return false end
  local cls=classes[name];if not valid(cls)then cls=StaticFindObject('/Script/EotU.'..name);classes[name]=cls end
  return valid(cls)and o:IsA(cls)==true
 end
 local function held(c)local v=c:GetHeldActor();return valid(v)and v or nil end
 local function point(o)return o:K2_GetActorLocation()end
 local function distance(a,b)
  local p,q=point(a),point(b);return (num(p.X)-num(q.X))^2+(num(p.Y)-num(q.Y))^2+(num(p.Z)-num(q.Z))^2
 end
 local function position_distance(c,p)
  local q=point(c);return(num(p.X)-num(q.X))^2+(num(p.Y)-num(q.Y))^2+(num(p.Z)-num(q.Z))^2
 end
 local function error_once(e)
  e=tostring(e);if not reported[e]then reported[e]=true;if options.log then pcall(options.log,'[SlaveFood] '..e)end end
 end
 local function context()
  local x=options.get_context();local gs=type(x)=='table'and(x.gs or x.game_state)
  if not valid(gs)then return nil end
  local ctl=native.get_local_controller(gs);if not valid(ctl)then return nil end
  local owner=num(ctl:GetColonyID());if not owner then return nil end
  local grid=x.grid or x.tile_grid or gs:GetTileGridByColonyID(owner)
  if not valid(grid)or native.is_owned(grid,gs)~=true then return nil end
  return{gs=gs,grid=grid,owner=owner,world=native.world_id(gs)}
 end
 local function active(c,ctx)
  return valid(c)and native.world_id(c)==ctx.world and native.is_owned(c,ctx.gs)==true
   and(num(c.Health)or 0)>0 and is_a(c,'SwarmCreature')and adapter.is_active_slave(c)==true
 end
 local function command(c,ctx)
  local s=adapter.describe_state(c);if not s or s.state~='slave'then return nil end
  local group=num(ctx.grid:GetSwarmCreatureGroupAssignment(c))
  if not group or group%1~=0 or group< -1 or group>7 then return nil end
  local marker=group>=0 and ctx.grid:GetCallToArmsByID(group)or nil
  local p=valid(marker)and point(marker)or nil
  return{id=s.id,group=group,gather=ctx.grid:GetGroupFoodGatherByID(group)==true,
   marker=key(marker),x=p and num(p.X),y=p and num(p.Y),z=p and num(p.Z)}
 end
 local function same_command(a,b)
  return a and b and a.id==b.id and a.group==b.group and a.marker==b.marker
   and a.x==b.x and a.y==b.y and a.z==b.z
 end
 local function socket(c)
  local mesh=c.Mesh;if not valid(mesh)then return nil end
  if mesh:DoesSocketExist(FName('Mouth'))==true then return'Mouth'end
  -- The DCH mesh/skeleton contains HeadBone and has no Mouth socket.
  if str(c.CreatureName)=='DCHLarvae'and mesh:DoesSocketExist(FName('HeadBone'))==true then return'HeadBone'end
  if HEAD_SOCKET[str(c.CreatureName)]and mesh:DoesSocketExist(FName('Head'))==true then return'Head'end
  -- Some original beasts have no named mouth/head. Keep native pickup and
  -- attach its resource in front of the actual collision sphere instead of
  -- guessing an IK bone or disabling their food work for a cosmetic reason.
  local sphere=c.SphereComponent
  local radius=valid(sphere)and num(safe(function()return sphere:GetUnscaledSphereRadius()end))
  if radius and radius>0 then return'@SphereFront'end
 end
 local function resource(o,ctx)
  return valid(o)and native.world_id(o)==ctx.world and is_a(o,'Resource')and(num(o.FoodHeld)or 0)>0
 end
 local function restore_animation(j,revoked)
  local a=j.animation;if not a then return end;j.animation=nil
  local c=j.creature;if not valid(c)or not same(c.Mesh,a.mesh)then return end
  -- Return our SingleNode instance even if native damage already killed the
  -- worker. Keep the native dead/wounded animation instead of resurrecting it.
  if a.asset then
   local instance=a.mesh:GetAnimInstance()
   if a.instance and(not same(instance,a.instance)or not same(instance.CurrentAsset,a.asset))then return end
   a.mesh:Stop();a.mesh:SetAnimClass(a.class);a.mesh:SetAnimationMode(a.mode)
   a.mesh.bPauseAnims=a.pause;a.mesh.VisibilityBasedAnimTickOption=a.visibility
   a.mesh.bEnableUpdateRateOptimizations=a.optimise;a.mesh.GlobalAnimRateScale=a.rate
  elseif num(c.CurrentAnimation)~=0 then return end
  if(num(c.Health)or 0)<=0 then c:SetCurrentAnimation(8);return end
  if not revoked and adapter.is_active_slave(c)~=true then return end
  c:SetCurrentAnimation(a.current)
 end
 local function cleanup(j,drop,revoked)
  if j.cleaned then return true end;j.cleaned=true
  jobs[j.key]=nil;if j.target_key and claims[j.target_key]==j then claims[j.target_key]=nil end
  local errors={};local function attempt(f)local ok,e=pcall(f);if not ok then errors[#errors+1]=tostring(e)end end
  attempt(function()restore_animation(j,revoked)end)
  if valid(j.store)then attempt(function()j.store:UnreserveSpaceOnTile(j.creature)end)end
  if valid(j.target)and is_a(j.target,'Resource')and same(j.target.RegisteredCreature,j.creature)then
   attempt(function()j.target.RegisteredCreature=nil end)
  end
  if drop and not j.deposited and valid(j.creature)and resource(held(j.creature),j.ctx)then
   attempt(function()j.creature:DropActor()end)
  end
  if not revoked then attempt(function()local ok,e=adapter.release_work(j.ticket);assert(ok,e)end)end
  if #errors>0 then error(table.concat(errors,'; '))end
  return true
 end
 local function cancel(j,now,reason)
  local ok,e=pcall(cleanup,j,true,false);totals.cancelled=totals.cancelled+1;cooldowns[j.key]=(now or 0)+1
  if not ok then error_once(e)end;if reason then error_once(reason)end
 end
 local function receipt(food)
  local k=key(food);local r=k and submitted[k]
  if r and valid(r.food)and same(r.food,food)then return r end
  if k then submitted[k]=nil end
 end
 local function observe_submissions(ctx)
  for k,r in pairs(submitted)do
   if r.world~=ctx.world then submitted[k]=nil
   elseif not r.complete and(not valid(r.creature)or not same(held(r.creature),r.food))then
    r.complete=true;totals.delivered=totals.delivered+1
   end
   -- An accepted resource is never submitted twice, even after cancellation.
   if r.complete and not valid(r.food)then submitted[k]=nil end
  end
 end
 local function scan_stores(ctx)
  local tiles=ctx.grid.Tiles;local n=count(tiles);if n==0 then stores={};scan_index=1;return end
  local start=os.clock();local done=0
  while done<M.tile_budget and os.clock()-start<0.002 do
   if scan_index>n then scan_index=1 end
   local tile=at(tiles,scan_index);scan_index=scan_index+1;done=done+1
   if valid(tile)and is_a(tile,'UGTile')and native.world_id(tile)==ctx.world then
    local rep=tile:GetFunctionRepresentation();local k=key(rep)
    if k and is_a(rep,'TileFunctionRepresentation')and num(rep:GetColonyID())==ctx.owner
      and rep.CanStoreFood==true and rep:IsBuilt()==true then stores[k]=rep end
   end
   if done>=n then break end
  end
  for k,rep in pairs(stores)do if not valid(rep)or native.world_id(rep)~=ctx.world
   or num(rep:GetColonyID())~=ctx.owner or rep.CanStoreFood~=true or rep:IsBuilt()~=true then stores[k]=nil end end
 end
 local function storage(c,ctx,kind,amount)
  local best,bestd
  for _,rep in pairs(stores)do
   local tile=rep.OwningTile
   if valid(tile)and num(rep.FoodType)==kind and(num(rep:AmountOfUnreservedSpaceOnTile(c,true))or 0)>=amount then
    local d=distance(c,tile);if not bestd or d<bestd then best,bestd=rep,d end
   end
  end
  return best
 end
 local function begin_animation(j)
  local c=j.creature;local mesh=c.Mesh
  assert(valid(mesh),'slave_food_mesh_missing')
  local a={mesh=mesh,current=num(c.CurrentAnimation)or 11};j.animation=a
  if str(c.CreatureName)~='DCHLarvae'then c:SetCurrentAnimation(0);return end
  local asset=classes.eating
  if not valid(asset)then asset=StaticFindObject(DCH_EATING);if not valid(asset)then asset=LoadAsset(DCH_EATING)end;classes.eating=asset end
  assert(valid(asset)and same(asset.Skeleton,mesh.SkeletalMesh.Skeleton),'slave_food_eating_skeleton_mismatch')
  a.mode=num(mesh:GetAnimationMode());a.class=mesh:GetAnimClass()
  assert(a.mode==0 and valid(a.class),'slave_food_animation_busy')
  a.pause=mesh.bPauseAnims;a.visibility=mesh.VisibilityBasedAnimTickOption
  a.optimise=mesh.bEnableUpdateRateOptimizations;a.rate=mesh.GlobalAnimRateScale;a.asset=asset
  mesh.bPauseAnims=false;mesh.VisibilityBasedAnimTickOption=0;mesh.bEnableUpdateRateOptimizations=false;mesh.GlobalAnimRateScale=1
  mesh:PlayAnimation(asset,true);mesh:SetPlayRate(1);mesh:SetPosition(0,false)
  a.instance=mesh:GetAnimInstance()
  assert(valid(a.instance)and same(a.instance.CurrentAsset,asset)and mesh:IsPlaying()==true,'slave_food_eating_not_playing')
 end
 local function attach_food(j,food)
  if j.socket=='Mouth'then return end
  local mesh=j.creature.Mesh;assert(valid(mesh),'slave_food_attachment_mesh_missing')
  local offset
  if j.socket=='@SphereFront'then
   local sphere=j.creature.SphereComponent
   assert(valid(sphere),'slave_food_sphere_missing')
   local radius=num(sphere:GetScaledSphereRadius());assert(radius and radius>0,'slave_food_sphere_radius_invalid')
   local p,f=sphere:K2_GetComponentLocation(),sphere:GetForwardVector()
   local world_point={X=num(p.X)+num(f.X)*radius,Y=num(p.Y)+num(f.Y)*radius,Z=num(p.Z)+num(f.Z)*radius}
   local mathlib=classes.mathlib
   if not valid(mathlib)then mathlib=StaticFindObject('/Script/Engine.Default__KismetMathLibrary');classes.mathlib=mathlib end
   assert(valid(mathlib),'slave_food_math_library_missing')
   offset=mathlib:InverseTransformLocation(mesh:K2_GetComponentToWorld(),world_point)
  else
   offset=mesh:GetSocketTransform(FName(j.socket),2).Translation
  end
  assert(offset and num(offset.X)and num(offset.Y)and num(offset.Z),'slave_food_attachment_offset_invalid')
  -- Native GetHeldActor searches Mesh children attached under the literal
  -- Mouth name, even on meshes without that socket. Never change that identity.
  food:K2_AttachToComponent(mesh,FName('Mouth'),2,2,1,false)
  food:K2_SetActorRelativeLocation(offset,false,{},true)
  local root=food.RootComponent
  assert(valid(root)and same(root:GetAttachParent(),mesh),'slave_food_attachment_parent_mismatch')
  assert(str(root:GetAttachSocketName())=='Mouth','slave_food_attachment_socket_mismatch')
  local p=root.RelativeLocation
  assert(math.abs((num(p.X)or math.huge)-num(offset.X))<0.01 and math.abs((num(p.Y)or math.huge)-num(offset.Y))<0.01
   and math.abs((num(p.Z)or math.huge)-num(offset.Z))<0.01,'slave_food_attachment_offset_mismatch')
  assert(same(held(j.creature),food),'slave_food_native_hold_lost_after_offset')
 end
 local function pickup(j,food)
  local c=j.creature;assert(resource(food,j.ctx),'slave_food_resource_missing')
  assert(not held(c),'slave_food_hands_occupied')
  assert(not valid(food.PickedUpCreature),'slave_food_target_taken')
  assert(num(food.ColonyLocation)==num(c.ColonyLocation),'slave_food_pickup_layer_mismatch')
  c:PickupActor(food);assert(same(held(c),food),'slave_food_native_pickup_failed')
  -- Retain native pickup ownership; only correct the visual attachment.
  attach_food(j,food)
  j.cargo=food;j.stage='carrying';totals.picked_up=totals.picked_up+1
 end
 local function begin(c,cmd,ctx,now)
  local k=key(c);if not k or(cooldowns[k]or 0)>now then return end
  local sk=socket(c);if not sk then error_once('slave_food_socket_unsupported:'..tostring(str(c.CreatureName)));return end
  local cargo=held(c);local kind=num(ctx.gs:GetColonyResourceTypeByID(ctx.owner))
  if kind==nil then error('slave_food_resource_type_unavailable')end
  if cargo and(not resource(cargo,ctx)or receipt(cargo))then return end
  local target
  if not cargo then
   if not storage(c,ctx,kind,1)then return end
   local found_insect={}
   target=c:NearestResource(found_insect,kind,nil,0,true,false,false,nil)
   if not valid(target)then return end
   if native.world_id(target)~=ctx.world or num(target.ColonyLocation)~=num(c.ColonyLocation)
     or num(target.ResourceType)~=kind or(not resource(target,ctx)and not is_a(target,'HarvestableResource'))then return end
   if resource(target,ctx)and(valid(target.PickedUpCreature)or receipt(target))then return end
   if claims[key(target)]then return end
  elseif not storage(c,ctx,num(cargo.ResourceType),1)then return end
  local ticket,why=adapter.acquire_work(c);if not ticket then return end
  local j={key=k,creature=c,ticket=ticket,ctx=ctx,command=cmd,socket=sk,started=now,
   target=target,target_key=key(target),cargo=cargo,stage=cargo and'carrying'or'approach'}
  jobs[k]=j;if j.target_key then claims[j.target_key]=j end
  ticket.on_revoke=function()return cleanup(j,true,true)end
  if cargo then attach_food(j,cargo)end
  if target and resource(target,ctx)then target:RegisterInterest(c)end
  return j
 end
 local function advance(j,ctx,now)
  local c=j.creature
  if j.stage=='approach'then
   local target=j.target;assert(valid(target)and native.world_id(target)==ctx.world,'slave_food_target_lost')
   assert(num(target.ColonyLocation)==num(c.ColonyLocation),'slave_food_target_layer_changed')
   assert(not valid(target.PickedUpCreature),'slave_food_target_taken')
   local pos=point(target);local harvest=is_a(target,'HarvestableResource')
   if harvest then
    if not j.harvest_point or target:IsLocationHarvestable(j.harvest_point)~=true then
     local hp=target:GetHarvestPoint();assert(valid(hp),'slave_food_no_harvest_point')
     local p={X=0,Y=0,Z=0};assert(target:GetHarvestLocation(hp,p)==true,'slave_food_harvest_location_failed')
     j.harvest_point=p
    end
    pos=j.harvest_point
   elseif target:CheckInterest(c)==false then error('slave_food_target_reserved')end
   local range=(num(c.ArrivalDist)or 55)+(num(c.AttackTolDist)or 30)
   if position_distance(c,pos)>range*range then local ok,e=adapter.move_work(j.ticket,target,pos);assert(ok,e);return end
   c:GetController():StopMovement();c.CurrentTarget=target;c.CurrentTargetLocation=pos;c:SetTurnToTarget(target)
   local delay=harvest and num(target:GetHarvestTime(c))or num(c.PickupTime)
   assert(delay and delay>=0 and delay<120,'slave_food_delay_invalid')
   j.ready_at=now+delay;j.stage=harvest and'harvesting'or'picking_up'
   if harvest then begin_animation(j)end
  elseif j.stage=='harvesting'or j.stage=='picking_up'then
   assert(valid(j.target)and num(j.target.ColonyLocation)==num(c.ColonyLocation),'slave_food_target_lost')
   if now<j.ready_at then return end
   assert(not valid(j.target.PickedUpCreature),'slave_food_target_taken')
   local food=j.target
   if j.stage=='harvesting'then
    restore_animation(j,false)
    assert((num(j.target.ResourcesHeld)or 0)>0,'slave_food_harvest_empty')
    local capacity=num(c.FoodCarryMax);assert(capacity and capacity>0,'slave_food_capacity_invalid')
    food=j.target:HarvestResource(math.floor(capacity));assert(resource(food,ctx),'slave_food_harvest_failed')
    totals.harvested=totals.harvested+1
   end
   pickup(j,food)
  elseif j.stage=='carrying'then
   assert(resource(j.cargo,ctx)and same(held(c),j.cargo),'slave_food_cargo_lost')
   local home,why=adapter.return_work_home(j.ticket);assert(type(home)=='table',why)
   if not home.home then return end
   local amount=num(j.cargo.FoodHeld);local kind=num(j.cargo.ResourceType)
   if not valid(j.store)then
    j.store=storage(c,ctx,kind,1);if not j.store then return end
    local free=num(j.store:AmountOfUnreservedSpaceOnTile(c,true))or 0
    assert(free>0,'slave_food_store_became_full')
    j.store:ReserveResourceSpace(c,math.min(amount,free))
   end
   local rep=j.store;local tile=rep.OwningTile
   assert(valid(tile)and native.world_id(tile)==ctx.world and num(rep:GetColonyID())==ctx.owner,'slave_food_store_lost')
   assert(rep:IsBuilt()==true and rep.CanStoreFood==true and num(rep.FoodType)==kind,'slave_food_store_changed')
   local range=(num(c.ArrivalDist)or 55)+(num(c.AttackTolDist)or 30)
   if distance(c,tile)>range*range then local ok,e=adapter.move_work(j.ticket,tile);assert(ok,e);return end
   c:GetController():StopMovement()
   assert(not receipt(j.cargo),'slave_food_already_submitted')
   local cargo_key=assert(key(j.cargo),'slave_food_cargo_missing_before_store')
   local taken=rep:AddFood(j.cargo,false)
   rep:UnreserveSpaceOnTile(c);j.store=nil
   if taken==true then
    j.deposited=true;j.stage='depositing';j.ready_at=now+2
    submitted[cargo_key]={food=j.cargo,creature=c,world=ctx.world,complete=false}
   else
    -- Native AddFood returns ResourceTaken=false after partial storage too.
    -- Its original resource retains the remainder; only observe that change.
    assert(resource(j.cargo,ctx)and same(held(c),j.cargo),'slave_food_partial_cargo_lost')
    local remaining=num(j.cargo.FoodHeld)
    assert(remaining and remaining<=amount,'slave_food_partial_amount_invalid')
    if remaining<amount then totals.partial_deposits=totals.partial_deposits+1;j.started=now end
   end
  elseif j.stage=='depositing'then
   if not same(held(c),j.cargo)then cleanup(j,false,false);cooldowns[j.key]=now+0.5
   elseif now>=j.ready_at then error_once('slave_food_storage_accepted_but_still_held')end
  end
 end
 function api.tick(now)
  if stopped then return true end
  now=num(now);if not now then return nil,'slave_food_time_missing'end
  local ctx=context();if not ctx then api.reset_cache();return true end
  if world~=ctx.world then local ok,e=api.reset_cache();if not ok then return nil,e end;world=ctx.world;last_tick=-math.huge end
  if now-last_tick<M.interval and now>=last_tick then return true end;last_tick=now
  local seen,candidates={},{}
  for _,row in ipairs(adapter.grouped_rows()or{})do for _,c in ipairs(row.creatures or{})do
   local k=key(c)
   if k and not seen[k]then seen[k]=true;candidates[#candidates+1]={key=k,creature=c}end
  end end
  if #candidates==0 and next(jobs)==nil and next(submitted)==nil then return true end
  observe_submissions(ctx)
  local active_count=0
  for _,v in ipairs(candidates)do
   v.active=safe(function()return active(v.creature,ctx)end)==true
   if v.active then active_count=active_count+1 end
  end
  if active_count>0 or next(jobs)~=nil then
   local ok,e=pcall(scan_stores,ctx);if not ok then error_once(e);return nil,tostring(e)end
  end
  local n=#candidates;local budget=math.min(n,M.query_budget)
  local first=n>0 and((search_cursor-1)%n)+1 or 1
  for i,v in ipairs(candidates)do
   local k,c=v.key,v.creature
   -- All existing tasks remain responsive; only idle searches are budgeted.
   if jobs[k]or(i-first+n)%n<budget then
    local called,why=pcall(function()
     local j=jobs[k];local cmd=v.active and command(c,ctx)or nil
     local busy=c.InCombat==true or(c.AbilityInUse==true and not(j and j.animation))
     if j and(j.creature~=c or not adapter.work_active(j.ticket)or not cmd or not cmd.gather
       or not same_command(j.command,cmd)or busy or now-j.started>M.task_timeout)then cancel(j,now);j=nil end
     if not cmd or not cmd.gather or busy or c.Immobile==true or valid(c.PickedUpCreature)then return end
     if ctx.grid:GetGroupAttackByID(cmd.group)==true then
      local enemy=c:NearestEnemyCreatureDirect(num(c.TargetRadius)or 400,false,0,false)
      if valid(enemy)and(num(enemy.Health)or 0)>0 and enemy.CanBeAttacked~=false and c:IsCreatureEnemy(enemy)==true then
       if j then cancel(j,now)end;return
      end
     end
     if not j then j=begin(c,cmd,ctx,now)end
     if j then advance(j,ctx,now)end
    end)
    if not called then if jobs[k]then cancel(jobs[k],now,why)else error_once(why)end end
   end
  end
  search_cursor=n>0 and((first-1+budget)%n)+1 or 1
  local absent={};for k,j in pairs(jobs)do if not seen[k]then absent[#absent+1]=j end end
  for _,j in ipairs(absent)do cancel(j,now)end
  return true
 end
 function api.reset_cache()
  local list={};for _,j in pairs(jobs)do list[#list+1]=j end
  local errors={};for _,j in ipairs(list)do local ok,e=pcall(cleanup,j,true,false);if not ok then errors[#errors+1]=tostring(e)end end
  jobs,claims,stores,cooldowns={},{},{},{};world=nil;scan_index=1;search_cursor=1;last_tick=-math.huge
  if #errors>0 then return nil,table.concat(errors,'; ')end;return true
 end
 function api.stop()local ok,e=api.reset_cache();if not ok then return nil,e end;stopped=true;return true end
 function api.status()
  local n,s,p=0,0,0;for _ in pairs(jobs)do n=n+1 end;for _ in pairs(stores)do s=s+1 end
  for _,r in pairs(submitted)do if not r.complete then p=p+1 end end
  local errors={};for e in pairs(reported)do errors[#errors+1]=e end;table.sort(errors)
  return{active=n,storage_candidates=s,pending_storage=p,stopped=stopped,native_verified=false,
   picked_up=totals.picked_up,harvested=totals.harvested,delivered=totals.delivered,partial_deposits=totals.partial_deposits,cancelled=totals.cancelled,errors=errors}
 end
 return api
end
return M
