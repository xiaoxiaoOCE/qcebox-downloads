-- Native slave transport/control adapter. Import performs no engine work.
-- Capture is gated until the caller has validated this adapter in the isolated
-- game. ActorTags, not UObject addresses, hold the saveable state.
local M={schema=1,prefix='EAA_Slaver_v1:',point_prefix='EAA_SlaverPoint_v1:',layer_prefix='EAA_SlaverLayer_v1:',collision_prefix='EAA_SlaverCollision_v1:',pickup_distance=130,queen_distance=220}
local function safe(f)local ok,v=pcall(f);if ok then return v end end
local function unbox(v)local x=v~=nil and safe(function()return v:get()end);return x~=nil and x or v end
local function num(v)local n=tonumber(unbox(v));if n and n==n and math.abs(n)<math.huge then return n end end
local function str(v)v=unbox(v);return type(v)=='string'and v or v and safe(function()return v:ToString()end)end
local function each(a,f)
 if type(a)=='table'and type(a.GetArrayNum)~='function'then for i,v in ipairs(a)do f(i,unbox(v))end;return end
 local n=num(a:GetArrayNum());assert(n and n>=0 and n<=65536,'invalid_array')
 for i=1,n do f(i,unbox(a[i]))end
end
local ants={Worker=true,WorkerAnt=true,FireAntWorker=true,BigHeadedMinor=true,BlackAnt=true,
 WoodAntA=true,WoodAntB=true,WoodAntASlow=true,WoodAntBSlow=true,WoodAntMelee=true,
 WoodAntSoldier=true,LeafcutterMinor=true,LeafcutterMedia=true,LeafcutterMajorTaunt=true,
 LeafcutterMajorStun=true,LeafcutterSuperMajor=true,SlaveMakerAnt=true,SlaveMaker=true,TrapjawAnt=true,ArmyAnt=true,
 ArmyAntMedia=true,ArmyAntMajor=true,FireAntPervasive=true,FireAntVigorous=true,
 BigHeadedMajor=true,BigHeadedSuperSoldier=true,LittleBlackAnt=true,LittleBlackAntWorker=true,
 MatabeleWorker=true,MatabeleSoldier=true,MatabeleMedicAnesthetist=true,MatabeleMedicFastResponder=true,
 DriverAntWorker=true,DriverAntSoldier=true,DriverAntLargeSoldier=true,BulletAnt=true,StinkAnt=true,
 ExplodingAntWorker=true,ExplodingAntSoldier=true,ExplodingAntMajorSoldier=true,
 NarrowHeadedAntRanged=true,NarrowHeadedAntSoldier=true}
local small={SpinyDevil_Small=true,RoveBeetleALarva=true,RoveBeetleBLarva=true,DCHLarvae=true,
 EarwigJuvenile=true,BeachWolfSpiderling=true,NorthernDunesTigerBeetle_Small=true,
 SmallBeachWolfSpider=true,AfricanTigerBeetleSmall=true,GreenJumperSpider=true,YungVelvetWorm=true,
 CheckeredBeetleLarva=true,BeachTigerBeetle_Small=true,FBBLarva=true,JumpingSpider=true,Earwig=true,
 SmallHermitCrab=true,SSTigerBeetleSmall=true,SmallSandBearWolfSpider=true}
M.ant_names=ants;M.small_names=small
-- Exact class paths from DT_FreeplayCreatures: SizeTier=Medium (1), bIsUber=false.
-- Class identity, not actor scale, display name or a QA sample, defines this set.
-- DLC entries only classify already-existing actors; nothing is loaded or unlocked.
local medium_classes={
 ['/Game/Blueprints/Creatures/African/AfricanTigerBeetle.AfricanTigerBeetle_C']=true,
 ['/Game/Blueprints/Creatures/African/AlligatorbackScorpionJuvanile.AlligatorbackScorpionJuvanile_C']=true,
 ['/Game/Blueprints/Creatures/African/GiantAfricanMantisJuvenile.GiantAfricanMantisJuvenile_C']=true,
 ['/Game/Blueprints/Creatures/African/HuntsmanSpider.HuntsmanSpider_C']=true,
 ['/Game/Blueprints/Creatures/African/RainbowLizardJuvenile.RainbowLizardJuvenile_C']=true,
 ['/Game/Blueprints/Creatures/Beach/MediumBeachWolfSpider.MediumBeachWolfSpider_C']=true,
 ['/Game/Blueprints/Creatures/Beach/MediumHermitCrabSmallCol.MediumHermitCrabSmallCol_C']=true,
 ['/Game/Blueprints/Creatures/Beach/MediumSandBearWolfSpider.MediumSandBearWolfSpider_C']=true,
 ['/Game/Blueprints/Creatures/Forest/DevilsCoachHorseAdult.DevilsCoachHorseAdult_C']=true,
 ['/Game/Blueprints/Creatures/Rainforest/Harvestman_Small.Harvestman_Small_C']=true,
 ['/Game/Blueprints/Creatures/Rainforest/PMYung.PMYung_C']=true,
 ['/Game/Blueprints/Creatures/Rainforest/RoveBeetleA.RoveBeetleA_C']=true,
 ['/Game/Blueprints/Creatures/Rainforest/RoveBeetleB.RoveBeetleB_C']=true,
 ['/Game/Blueprints/Creatures/Rainforest/SpinyDevil_Medium.SpinyDevil_Medium_C']=true,
 ['/Game/Blueprints/Creatures/Rainforest/WhipSpiderling_Small.WhipSpiderling_Small_C']=true,
 ['/Game/Blueprints/Creatures/Swamp/CheckeredBeetle.CheckeredBeetle_C']=true,
 ['/Game/Blueprints/Creatures/Swamp/DwarfSalamander.DwarfSalamander_C']=true,
 ['/Game/Blueprints/Creatures/Swamp/SSTigerBeetle.SSTigerBeetle_C']=true,
 ['/Game/Blueprints/Creatures/Swamp/WaspMantidfly.WaspMantidfly_C']=true,
 ['/Game/Blueprints/Creatures/SwampIncludingDemo/BombardierBeetle.BombardierBeetle_C']=true,
 ['/Game/DLC/NarrowHeadedAnt_DLC/Blueprints/Creatures/AnguisFragillis/AnguisFragilis_Juvenille.AnguisFragilis_Juvenille_C']=true,
 ['/Game/DLC/NarrowHeadedAnt_DLC/Blueprints/Creatures/ApodemusSylvaticus_Juvenile.ApodemusSylvaticus_Juvenile_C']=true,
 ['/Game/DLC/NarrowHeadedAnt_DLC/Blueprints/Creatures/BufoBufo/BufoBufo_Juvenille.BufoBufo_Juvenille_C']=true,
 ['/Game/DLC/NarrowHeadedAnt_DLC/Blueprints/Creatures/CarabusProbelmaticus/CarabusProblematicus_Mature.CarabusProblematicus_Mature_C']=true,
 ['/Game/DLC/NarrowHeadedAnt_DLC/Blueprints/Creatures/CicindelaCampestris/GreenTigerBeetle.GreenTigerBeetle_C']=true,
 ['/Game/DLC/NarrowHeadedAnt_DLC/Blueprints/Creatures/GonatodesCaudiscutatus.GonatodesCaudiscutatus_C']=true,
 ['/Game/DLC/NarrowHeadedAnt_DLC/Blueprints/Creatures/OcpusOlens/OcypusOlens_Mature.OcypusOlens_Mature_C']=true,
 ['/Game/DLC/NarrowHeadedAnt_DLC/Blueprints/Creatures/PardosaAmentata/PardosaAmentata_Female_Mother.PardosaAmentata_Female_Mother_C']=true,
}
M.medium_classes=medium_classes
local frozen_fields={'Immobile','CanBeAttacked','NoCombat','NoneBTControl','DontRotate','CorpseDespawn','DoNotProjectLoadedLocation'}
local function encode_flags(c)
 local v=0;for i,k in ipairs(frozen_fields)do if c[k]==true then v=v+2^(i-1)end end;return v
end
local function flag(v,i)return math.floor(v/2^(i-1))%2==1 end

function M.install(options)
 assert(type(options)=='table'and type(options.native)=='table','slaver_adapter_dependencies')
 assert(type(options.get_context)=='function','slaver_adapter_context')
 local native=options.native
 local records,carriers,reported,class_cache,moves,work_tickets={},{},{},{},{},{}
 local candidate_epoch,candidate_world,candidate_cells,medics=nil,nil,{},{}
 local sequence=0;local stopped=false
 local api={}
 local function valid(c)return c~=nil and safe(function()return native.valid_object(c)end)==true end
 local function key(c)
  if not valid(c)then return nil end
  local a=safe(function()return c:GetAddress()end);local n=safe(function()return c:GetFullName()end)
  if a and n then return tostring(a)..'|'..n end
 end
 local function failure(e)
  e=tostring(e);if not reported[e]then reported[e]=true;if options.log then pcall(options.log,'[SlaveNative] '..e)end end
  return nil,e
 end
 local function slave_ready(c)
  if type(options.on_slave_ready)=='function'then
   local ok,err=pcall(options.on_slave_ready,c)
   if not ok then failure('slave_ready_callback_failed:'..tostring(err))end
  end
 end
 local function context()
  local c=options.get_context();local gs=type(c)=='table'and(c.gs or c.game_state)
  if not valid(gs)then return nil end
  local controller=native.get_local_controller(gs);if not valid(controller)then return nil end
  local owner=num(controller:GetColonyID());if not owner then return nil end
  local grid=c.grid or c.tile_grid or gs:GetTileGridByColonyID(owner)
  if not valid(grid)or native.is_owned(grid,gs)~=true then return nil end
  local queen=grid.ColonyQueen
  if not valid(queen)or(num(queen.Health)or 0)<=0 then return nil end
  return{gs=gs,grid=grid,queen=queen,owner=owner,world=native.world_id(gs)}
 end
 local function same_world(c,ctx)return valid(c)and native.world_id(c)==ctx.world end
 local function location(c)return c:K2_GetActorLocation()end
 local function dist2(a,b)
  local p,q=location(a),location(b)
  local x,y,z=num(p.X)-num(q.X),num(p.Y)-num(q.Y),num(p.Z)-num(q.Z)
  return x*x+y*y+z*z
 end
 local function alive(c)return valid(c)and(num(c.Health)or 0)>0 end
 local function is_a(c,path)
  local cls=class_cache[path]
  if not valid(cls)then cls=StaticFindObject(path);class_cache[path]=cls end
  return valid(cls)and c:IsA(cls)==true
 end
 local function swarm(c)return is_a(c,'/Script/EotU.SwarmCreature')end
 local function colony(c)return is_a(c,'/Script/EotU.ColonyCreature')end
 local function held(c)local h=safe(function()return c:GetHeldActor()end);return valid(h)and h or nil end
 local function tags(c)
  local out={};each(c.Tags,function(_,v)local n=str(v);assert(n,'unreadable_actor_tag');out[#out+1]=n end);return out
 end
 local function write_tag(r,remove)
  local out={};for _,t in ipairs(tags(r.creature))do
   if t:sub(1,#M.prefix)~=M.prefix and t:sub(1,#M.layer_prefix)~=M.layer_prefix
    and t:sub(1,#M.collision_prefix)~=M.collision_prefix then out[#out+1]=FName(t)end
  end
  if not remove then
   r.layer=assert(num(r.creature.ColonyLocation),'slave_saved_layer_invalid')
   assert(r.layer>=-1 and r.layer%1==0,'slave_saved_layer_invalid')
   local t=M.prefix..string.format('%s:%d:%d:%d:%d:%s',r.state,r.owner,r.group,r.origin,r.flags,r.id)
   out[#out+1]=FName(t)
   out[#out+1]=FName(M.layer_prefix..string.format('%d',r.layer))
   if r.collision_enabled~=nil then out[#out+1]=FName(M.collision_prefix..(r.collision_enabled and'1'or'0'))end
  end
  r.creature.Tags=out
  if not remove then
   local found=false;for _,t in ipairs(tags(r.creature))do if t:sub(1,#M.prefix)==M.prefix then found=true end end
   assert(found,'slave_tag_write_failed')
  end
 end
 local function stop_brain(c)
  local controller=c:GetController();assert(valid(controller),'slave_controller_missing')
  local brain=controller.BrainComponent
  local info={controller=controller,brain=valid(brain)and brain or nil}
  controller:StopMovement()
  if info.brain then info.was_running=safe(function()return brain:IsRunning()end)~=false;brain:StopLogic('Ant Overhaul captive task')end
  return info
 end
 local function resume_brain(info)
  if info and valid(info.controller)then info.controller:StopMovement()end
  if info and info.was_running and valid(info.brain)then info.brain:RestartLogic()end
 end
 local function release_work(ticket)
  if type(ticket)~='table'or work_tickets[ticket.key]~=ticket then return true end
  work_tickets[ticket.key]=nil;moves[ticket.key]=nil
  local cleaned,clean_error=true,nil
  if type(ticket.on_revoke)=='function'then cleaned,clean_error=pcall(ticket.on_revoke,ticket)end
  local c=ticket.creature
  local resumed,resume_error=true,nil
  if valid(c)and key(c)==ticket.key then
   resumed,resume_error=pcall(function()
    if alive(c)then resume_brain(ticket.brain)
    elseif valid(ticket.brain.controller)then ticket.brain.controller:StopMovement()end
   end)
  end
  assert(cleaned and resumed,'slave_work_release_failed:'..tostring(clean_error or resume_error))
  return true
 end
 local function restore_flags(r)
  for i,k in ipairs(frozen_fields)do r.creature[k]=flag(r.flags,i)end
  if r.collision_enabled~=nil then
   r.creature:SetActorEnableCollision(r.collision_enabled)
   assert(r.creature:GetActorEnableCollision()==r.collision_enabled,'slave_collision_restore_failed')
   r.collision_enabled=nil
  end
 end
 local function wake_animation(r)
  local c=r.creature;local mesh=c.Mesh
  assert(valid(mesh),'slave_wake_mesh_missing')
  local mode=num(mesh:GetAnimationMode());local cls=mesh:GetAnimClass()
  local previous=r.animation
  if previous and valid(previous.mesh)and key(previous.mesh)==key(mesh)then mode=previous.mode;cls=previous.class end
  assert(mode~=nil,'slave_wake_animation_mode_missing')
  c:ForceLeaveCombat();c.AbilityInUse=false;c:SetCurrentAnimation(11)
  if mode==0 then
   assert(valid(cls),'slave_wake_animation_class_missing')
   local ok,err=pcall(function()
    -- The native death state has no transition back into active combat.
    -- Recreate only this existing mesh's AnimBP instance once on revival.
    mesh:SetAnimationMode(1)
    if not valid(mesh:GetAnimClass())or key(mesh:GetAnimClass())~=key(cls)then mesh:SetAnimClass(cls)end
    mesh:SetAnimationMode(mode)
    assert(num(mesh:GetAnimationMode())==mode and key(mesh:GetAnimClass())==key(cls),'slave_wake_animation_readback_failed')
   end)
   if not ok then safe(function()mesh:SetAnimClass(cls);mesh:SetAnimationMode(mode)end);error(err)end
  end
  r.animation=nil
 end
 local function freeze(r)
  local c=r.creature
  release_work(work_tickets[key(c)])
  if not r.brain then r.brain=stop_brain(c)end
  if not r.animation then
   local mesh=c.Mesh;assert(valid(mesh),'slave_freeze_mesh_missing')
   r.animation={mesh=mesh,mode=num(mesh:GetAnimationMode()),class=mesh:GetAnimClass()}
  end
  c:ForceLeaveCombat();c.Immobile=true;c.CanBeAttacked=false;c.NoCombat=true;c.NoneBTControl=true
  c.DontRotate=true;c.CorpseDespawn=false
  -- Queen danger checks use a physical overlap and only test HP/allegiance.
  -- Pending captives retain their enemy identity until conversion, so exclude
  -- just these immobilised actors from that query; restore on every exit.
  if r.state=='knocked_out'then
   if r.collision_enabled==nil then
    r.collision_enabled=c:GetActorEnableCollision()
    assert(type(r.collision_enabled)=='boolean','slave_collision_state_unavailable')
   end
   c:SetActorEnableCollision(false)
   assert(c:GetActorEnableCollision()==false,'slave_collision_freeze_failed')
  end
  -- Pending captives still belong to their enemy swarm/nursery. That owner's
  -- saved layer may differ after real tunnel travel. Keep the actual saved
  -- world transform, then restore our per-individual layer after native load.
  c.DoNotProjectLoadedLocation=true
  c:SetCurrentAnimation(8)
 end
 local function release_carrier(r)
  local b=r.carrier
  if not b then return end
  local cancel_error
  if r.treatment_ticket and options.treatment then
   local called,ok,why=pcall(options.treatment.cancel,r.treatment_ticket)
   if not called or ok~=true then cancel_error=tostring(called and why or ok)end
   r.treatment_ticket=nil
  end
  if valid(b.creature)then
   if held(b.creature)==r.creature then b.creature:DropActor()end
   for k,v in pairs(b.before)do b.creature[k]=v end
   resume_brain(b.brain)
  end
  moves[b.key]=nil;carriers[b.key]=nil;r.carrier=nil
  if cancel_error then error('slave_treatment_cancel_failed:'..cancel_error)end
 end
 local function abort(r,reason)
  local released,release_error=pcall(release_carrier,r)
  if valid(r.creature)then
   if r.converting then
    if swarm(r.creature)then r.creature:ChangeColonyID(r.owner_before_conversion,0,true)
    else r.creature.ColonyID=r.owner_before_conversion;r.creature:ResetCollisionSettings()end
    r.converting=nil
   end
   restore_flags(r);wake_animation(r)
   resume_brain(r.brain);r.brain=nil
   if r.state=='wounded'then r.state='slave';write_tag(r)
   else
    write_tag(r,true);records[r.key]=nil
    if options.conversion and type(options.conversion.discard_snapshot)=='function'then
     local removed,why=options.conversion.discard_snapshot(r.creature);assert(removed,why)
    end
   end
  else records[r.key]=nil end
  if not released then reason=tostring(reason)..'; '..tostring(release_error)end
  return failure(reason)
 end
 local function move(c,target)
  assert(valid(target),'slave_move_target_missing')
  local ctl=c:GetController();assert(valid(ctl),'slave_move_controller_missing')
  -- Native UpdateMovementGoal dereferences the game's path component. Check
  -- it first; a controller alone is insufficient to make that call safe.
  assert(valid(ctl.PathFollowingComponent)and is_a(ctl.PathFollowingComponent,'/Script/EotU.CreaturePathFollowingComponent'),'slave_path_component_missing')
  c.CurrentTarget=target;c.CurrentTargetLocation=location(target)
  local k,target_key=key(c),key(target)
  local previous=moves[k]
  local ctx=context();local now=ctx and num(safe(function()return ctx.gs:GetLevelTime()end))
  local pos=location(c)
  if previous and previous.target==target_key and not previous.explicit and valid(previous.proxy)then
   local moved=previous.position and((pos.X-previous.position.X)^2+(pos.Y-previous.position.Y)^2+(pos.Z-previous.position.Z)^2)>100
   if moved then previous.position={X=pos.X,Y=pos.Y,Z=pos.Z};previous.progress_at=now end
   local status=num(safe(function()return ctl:GetMoveStatus()end))
   local retry=now and previous.requested_at and(now-previous.requested_at>=1)
    and(status==0 or(previous.progress_at and now-previous.progress_at>=2))
   if not retry then c:UpdateMovementGoal(location(target));return end
   ctl:StopMovement()
  end
  -- Use the exact path entrypoint of MoveToCreatureTarget's Blueprint. The
  -- general AIController.MoveToActor wrapper failed in an actual Lab4 carry;
  -- it is not an authority for this game's custom path-following component.
  local helper=class_cache.move_helper
  if not valid(helper)then helper=StaticFindObject('/Script/AIModule.Default__AIBlueprintHelperLibrary');class_cache.move_helper=helper end
  assert(valid(helper),'slave_move_helper_missing')
  c:SetCurrentAnimation(11)
  local proxy=helper:CreateMoveToProxyObject(c,c,{X=0,Y=0,Z=0},target,num(c.ArrivalDist)or 55,false)
  assert(valid(proxy),'slave_move_proxy_failed')
  moves[k]={target=target_key,proxy=proxy,requested_at=now,progress_at=now,position={X=pos.X,Y=pos.Y,Z=pos.Z}}
 end
 local function travel_home(c,ctx)
  local layer=num(c.ColonyLocation)
  if layer==num(ctx.queen.ColonyLocation)then move(c,ctx.queen);return end
  local entering=layer==-1
  local route=entering and ctx.grid or ctx.gs:GetTileGridByColonyID(layer)
  assert(valid(route),'slave_tunnel_grid_missing')
  local entrance=entering and route.SurfaceTunnel or route.UndergroundTunnel
  local exit=entering and route.UndergroundTunnel or route.SurfaceTunnel
  assert(valid(entrance)and valid(exit),'slave_tunnel_missing')
  -- This is the native tunnel transition radius (TransferToMyUG uses 800).
  -- We first walk to the real entry; only the tunnel itself changes layers.
  if dist2(c,entrance)>(entering and 800*800 or 220*220)then move(c,entrance);return end
  local utilities=class_cache.utilities
  if not valid(utilities)then utilities=StaticFindObject('/Script/EotU.Default__EotUUtilities');class_cache.utilities=utilities end
  assert(valid(utilities),'slave_tunnel_utilities_missing')
  local destination={X=0,Y=0,Z=0};local found
  if entering then
   found=utilities:EotURandomSpawnPoint(c,location(exit),destination,150,c:GetClass(),-3,false,0)
  else
   found=utilities:EotURandomPoint(c,exit:GetRandomSpawnPoint(),destination,num(exit.HoleRadius)or 150,true,c,
    false,0,0,false,false,false,{X=0,Y=0},0,c:GetHomeZoneID(),false,num(c.MovementFreedom)or 0)
  end
  assert(found==true and num(destination.X)and num(destination.Y)and num(destination.Z),'slave_tunnel_no_valid_exit')
  local target_layer=entering and ctx.owner or -1
  c:GetController():StopMovement();moves[key(c)]=nil
  c:PhaseOut(0.2,false)
  assert(c:SetActorLocationAndColonyLocation(destination,target_layer)==true,'slave_tunnel_transition_failed')
  -- The held creature is attached spatially; preserve its explicit save layer.
  local cargo=held(c);if cargo then cargo.ColonyLocation=target_layer end
  assert(num(c.ColonyLocation)==target_layer,'slave_tunnel_layer_readback_failed')
 end
 local function candidate_list()
  local a=type(options.candidates)=='function'and options.candidates()or{}
  assert(type(a)=='table'and #a<=65536,'slave_candidates_invalid');return a
 end
 local function supported_carrier(c)
  return colony(c)or(swarm(c)and api.is_active_slave(c)==true)
 end
 local function available(c,r,ctx,medic)
  if not alive(c)or c==r.creature or not same_world(c,ctx)or native.is_owned(c,ctx.gs)~=true then return false end
  if num(c.ColonyLocation)~=num(r.creature.ColonyLocation)or carriers[key(c)]or work_tickets[key(c)]or held(c)then return false end
  if c.Immobile==true or c.AbilityInUse==true or valid(safe(function()return c.PickedUpCreature end))then return false end
  if options.treatment and options.treatment.supports(c)~=true then return false end
  local n=str(c.CreatureName)
  if medic then return(n=='MatabeleMedicAnesthetist'or n=='MatabeleMedicFastResponder')and supported_carrier(c)end
  return supported_carrier(c)and ants[n]==true
 end
 local function cell_key(layer,x,y)return layer..':'..x..':'..y end
 local function rebuild_candidates(ctx,now)
  now=num(safe(function()return ctx.gs:GetLevelTime()end))or now or 0
  now=math.floor(now*4)
  if candidate_epoch==now and candidate_world==ctx.world then return end
  candidate_epoch=now;candidate_world=ctx.world;candidate_cells={};medics={}
  for _,c in ipairs(candidate_list())do
   local n=valid(c)and str(c.CreatureName)
   local friendly=alive(c)and same_world(c,ctx)and num(c.ColonyID)==ctx.owner
   local supported=friendly and ants[n]and supported_carrier(c)
   if supported and(n=='MatabeleMedicAnesthetist'or n=='MatabeleMedicFastResponder')then medics[#medics+1]=c end
   if supported and c.Immobile~=true then
    local k=key(c)
    if k and not carriers[k]and not work_tickets[k]and not held(c)then
     local p=location(c);local x,y,z=num(p.X),num(p.Y),num(p.Z);local layer=num(c.ColonyLocation)
     if x and y and z and layer then
      local bucket_key=cell_key(layer,math.floor(x/600),math.floor(y/600))
      local bucket=candidate_cells[bucket_key]or{};candidate_cells[bucket_key]=bucket
      bucket[#bucket+1]={creature=c,x=x,y=y,z=z}
     end
    end
   end
  end
 end
 local function find_carrier(r,ctx,now)
  rebuild_candidates(ctx,now)
  local p=location(r.creature);local x,y,z=num(p.X),num(p.Y),num(p.Z)
  local layer=num(r.creature.ColonyLocation);local cx,cy=math.floor(x/600),math.floor(y/600)
  local selected,best
  for dx=-2,2 do for dy=-2,2 do
   for _,row in ipairs(candidate_cells[cell_key(layer,cx+dx,cy+dy)]or{})do
    local d=(row.x-x)^2+(row.y-y)^2+(row.z-z)^2
    if(not best or d<best)and available(row.creature,r,ctx,r.state=='wounded')then selected,best=row.creature,d end
   end
  end end
  return selected
 end
 local function reserve(c,r)
  local k=key(c);assert(k and not carriers[k]and not work_tickets[k],'slave_carrier_reserved')
  local b={creature=c,key=k,before={NoCombat=c.NoCombat,NoneBTControl=c.NoneBTControl,DontHarvest=c.DontHarvest}}
  carriers[k]=r;r.carrier=b
  b.brain=stop_brain(c);c:ForceLeaveCombat();c.NoCombat=true;c.DontHarvest=true
 end
 local function pickup(r)
  local c,v=r.carrier.creature,r.creature
  assert(dist2(c,v)<=M.pickup_distance*M.pickup_distance,'slave_pickup_too_far')
  assert(not held(c),'slave_carrier_not_empty')
  v.PickedUpCreature=c
  c:PickupActor(v)
  assert(held(c)==v,'slave_native_pickup_failed')
  v.ColonyLocation=num(c.ColonyLocation)
  assert(num(v.ColonyLocation)==num(c.ColonyLocation),'slave_pickup_layer_readback_failed')
  r.carrier.loaded=true;r.stage='carried';write_tag(r)
 end
 local function own_swarm_point(r,ctx)
  local c=r.creature;local old=safe(function()return c.SwarmPoint end)
  local tag=M.point_prefix..r.id
  if valid(old)and is_a(old,'/Script/EotU.Swarm')then
   for _,t in ipairs(tags(old))do if t==tag and num(old.ColonyID)==ctx.owner then r.point=old;return old end end
   -- FSwarmSaveState omits ActorTags. The creature's stable tag survives and
   -- points back to its native saved swarm. Reuse only a private one-member
   -- anchor with our complete saved configuration, never an enemy group.
   if num(old.ColonyID)==ctx.owner and num(old.SwarmTemperament)==11 and old.bNeverKillSwarm==true
    and old.bSwarmRespawn==false and num(old.iSwarmMaxSize)==0 and old.AddToFreeplayDirectorList==false
    and old.bNeverAttackColony==true and old.bNeverAttackEnemies==true then
    local count,member=0,nil;each(old.SwarmCreatures,function(_,v)count=count+1;member=v end)
    if count==1 and key(member)==key(c)then
     local saved_tags={};for _,t in ipairs(tags(old))do saved_tags[#saved_tags+1]=FName(t)end
     saved_tags[#saved_tags+1]=FName(tag);old.Tags=saved_tags;r.point=old;return old
    end
   end
  end
  -- A separate native swarm anchor is necessary: RefreshControllableSwarmTargets
  -- moves SwarmPoint itself. Moving the enemy's shared anchor would command its
  -- uncaptured members as well. No creature or brood tile is spawned here.
  local helper=class_cache.spawn_helper
  if not valid(helper)then helper=StaticFindObject('/Script/Engine.Default__GameplayStatics');class_cache.spawn_helper=helper end
  local cls=class_cache.swarm_class
  if not valid(cls)then cls=StaticFindObject('/Game/Blueprints/AI/Swarm/Swarm_BP.Swarm_BP_C');class_cache.swarm_class=cls end
  assert(valid(helper)and valid(cls),'slave_swarm_spawn_api_missing')
  local transform=c:GetTransform();local point
  local ok,err=pcall(function()
   point=helper:BeginDeferredActorSpawnFromClass(c,cls,transform,1,nil)
   assert(valid(point),'slave_swarm_spawn_failed')
   point.ColonyID=ctx.owner;point.ColonyLocation=num(c.ColonyLocation);point.SwarmTemperament=11
   point.bNeverKillSwarm=true;point.bSwarmRespawn=false;point.iSwarmMaxSize=0
   point.bNeverAttackColony=true;point.bNeverAttackEnemies=true;point.bAvoidAntNests=false
   point.LeashCreatures=false;point.AddToFreeplayDirectorList=false;point.DisableStandardSave=false
   point.Tags={FName(tag)}
   local finished=helper:FinishSpawningActor(point,transform)
   assert(valid(finished),'slave_swarm_finish_failed');point=finished
   point:RegisterSwarmCreature(c);c.SwarmPoint=point
   assert(valid(c.SwarmPoint)and key(c.SwarmPoint)==key(point),'slave_swarm_readback_failed')
   if valid(old)and is_a(old,'/Script/EotU.Swarm')then old:DeRegisterSwarmCreature(c)end
  end)
  if not ok then
   if valid(c)then c.SwarmPoint=valid(old)and old or nil end
   if valid(point)then safe(function()point:DeRegisterSwarmCreature(c);point:K2_DestroyActor()end)end
   error(err)
  end
  r.point=point;return point
 end
 local function own_control(r,ctx)
  local c=r.creature
  if swarm(c)then
   own_swarm_point(r,ctx)
   ctx.grid:AddControllableSwarmCreature(c)
   ctx.grid:SetSwarmCreatureGroupAssignment(c,r.group)
   assert(num(ctx.grid:GetSwarmCreatureGroupAssignment(c))==r.group,'slave_group_readback_failed')
   ctx.grid:RefreshControllableSwarmTargets()
   if not r.team_colour_applied and options.conversion and type(options.conversion.apply_team_colour)=='function'then
    local applied,why=options.conversion.apply_team_colour(c,ctx.grid);assert(applied~=nil,why)
    r.team_colour_applied=true
   end
  elseif colony(c)then
   -- Keep the original actor and its original nursery membership. Our brain
   -- stays reserved so it cannot follow the enemy nursery's worker tasks.
   assert(options.colony_control_verified==true,'slave_colony_control_not_validated')
   if not r.brain then r.brain=stop_brain(c)end
  else error('slave_unsupported_native_class')end
 end
 local function convert(r,ctx)
  local c=r.creature
  assert(r.carrier and r.carrier.loaded and held(r.carrier.creature)==c,'slave_delivery_without_carrier')
  assert(num(r.carrier.creature.ColonyLocation)==num(ctx.queen.ColonyLocation),'slave_queen_layer_mismatch')
  assert(dist2(r.carrier.creature,ctx.queen)<=M.queen_distance*M.queen_distance,'slave_delivery_too_far')
  local original,oldkey,oldbrain,oldstate,oldpoint=c,r.key,r.brain,r.state,r.point
  local tx
  if colony(c)then
   assert(options.conversion and options.conversion.can_convert(c)==true,'slave_colony_conversion_not_validated')
   local why;tx,why=options.conversion.prepare(c,ctx);assert(tx,why)
  elseif oldstate=='knocked_out'and options.conversion then
   -- Native Swarm restore also recalculates stats under the new owner. Preserve
   -- the original individual before its first ownership change. Medical
   -- revival must retain this first snapshot, not capture temporary buffs.
   local captured,why=options.conversion.capture_snapshot(c);assert(captured~=nil,why)
  end
  r.converting=true;r.owner_before_conversion=num(c.ColonyID)
  local ok,err=pcall(function()
   release_carrier(r)
   if tx then
    c=tx.creature;r.creature=c;r.key=assert(key(c));r.brain=assert(tx.prepared_brain,'slave_conversion_brain_missing');r.point=nil
    assert(valid(r.brain.controller)and valid(r.brain.brain),'slave_conversion_brain_invalid')
    -- prepare() already paused the new controller. Reading IsRunning again
    -- would mistake that pause for an originally stopped AI. Transfer the
    -- captured individual's prior running state to its same-species actor.
    if oldbrain then r.brain.was_running=oldbrain.was_running end
   end
   assert(swarm(c),'slave_conversion_requires_swarm')
   c:ChangeColonyID(ctx.owner,0,true)
   assert(num(c.ColonyID)==ctx.owner,'slave_owner_change_failed')
   restore_flags(r);c.CanBeAttacked=true;c.NoCombat=false;c.Immobile=false;c.NoneBTControl=false
   c.Health=c.FullHealth;wake_animation(r);c.CanRecieveMedicalTreatment=false
   own_control(r,ctx)
   r.state='slave';r.stage=nil;r.owner=ctx.owner;write_tag(r)
   resume_brain(r.brain);r.brain=nil
   if tx then tx.commit()end
  end)
  if not ok then
   if tx then
    -- Remove the uncommitted replacement from native controls before disposal.
    safe(function()
     local keep={};each(ctx.grid.ControllableSwarmCreatures,function(_,a)
      if valid(a.Creature)and key(a.Creature)~=key(c)then keep[#keep+1]={Creature=a.Creature,GroupAssignment=num(a.GroupAssignment)}end
     end);ctx.grid.ControllableSwarmCreatures=keep
     if valid(r.point)then r.point:DeRegisterSwarmCreature(c);r.point:K2_DestroyActor()end
    end)
    tx.rollback();r.creature=original;r.key=oldkey;r.brain=oldbrain;r.state=oldstate;r.point=oldpoint;r.converting=nil
   end
   error(err)
  end
  if tx then records[oldkey]=nil;records[r.key]=r end
  r.converting=nil
  r.medical_transaction=nil;slave_ready(c)
  return true
 end
 local function load_record(c)
  local k=key(c);if not k then return nil end
  if records[k]then return records[k]end
  local saved_tags=tags(c);local saved_layer,saved_collision
  for _,t in ipairs(saved_tags)do
   if t:sub(1,#M.layer_prefix)==M.layer_prefix then
    local l=t:sub(#M.layer_prefix+1);assert(l:match('^-?%d+$'),'slave_layer_tag_invalid')
    saved_layer=assert(num(l),'slave_layer_tag_invalid');assert(saved_layer>=-1,'slave_layer_tag_invalid')
   elseif t:sub(1,#M.collision_prefix)==M.collision_prefix then
    local value=t:sub(#M.collision_prefix+1);assert(value=='0'or value=='1','slave_collision_tag_invalid')
    saved_collision=value=='1'
   end
  end
  for _,t in ipairs(saved_tags)do
   if t:sub(1,#M.prefix)==M.prefix then
    local state,owner,group,origin,flags,id=t:sub(#M.prefix+1):match('^([a-z_]+):(-?%d+):(-?%d+):(-?%d+):(%d+):([%w_-]+)$')
    if state and(state=='slave'or state=='knocked_out'or state=='wounded')then
     local r={creature=c,key=k,state=state,owner=tonumber(owner),group=tonumber(group),origin=tonumber(origin),flags=tonumber(flags),id=id,loaded=true,layer=saved_layer or num(c.ColonyLocation),collision_enabled=saved_collision}
     records[k]=r;return r
    end
   end
  end
 end
 local function native_candidate(c,ctx,attacker)
  local class_object=c:GetClass()
  local class_path=safe(function()return class_object:GetFullName():match('^[^ ]+ (.+)$')end)
  local medium=medium_classes[class_path]==true
  local n=str(c.CreatureName);if not ants[n]and not small[n]and not medium then return false end
  -- follow_step keeps its persistent ID, but no longer grants captive attacks.
  -- Both permanent and mission choices reach this adapter through get_choices.
  if medium then
   if str(attacker.CreatureName)~='SlaveMakerAnt'or(num(attacker.CreatureLevel)or 0)<3
    or type(options.get_choices)~='function'then return false end
   local selected=options.get_choices(attacker,'SlaveMaker')
   if type(selected)~='table'or selected.left~='follow_step'then return false end
  end
  if c.DisableStandardSave==true or c.Immobile==true or c.CanBeAttacked~=true then return false end
  if not same_world(c,ctx)or is_a(c,'/Script/EotU.QueenCreature')or is_a(c,'/Script/EotU.CreatureAttackPoint')then return false end
  if not swarm(c)and not colony(c)then return false end
  if colony(c)and(not options.conversion or options.conversion.can_convert(c)~=true)then return false end
  if(small[n]or medium)and((num(c.AttackDamage)or 0)<=0 or c.HarmlessCreature==true)then return false end
  local class=str(class_object:GetFName())or''
  if class:find('Queen')or class:find('King')or class:find('Termite')or class:find('Uber')or class:find('Titan')or class:find('Boss')then return false end
  for _,t in ipairs(tags(c))do
   local low=t:lower();if low:find('objective')or low:find('script')or low:find('missioncritical')or low:find('quest')then return false end
  end
  return true
 end
 function api.capture_ready()return not stopped and options.verified==true and type(options.candidates)=='function'end
 function api.is_capturable(victim,attacker)
  local ok,result=pcall(function()
   local ctx=context();if not ctx or not alive(victim)or not alive(attacker)or not api.capture_ready()then return false end
   if native.is_owned(attacker,ctx.gs)~=true or load_record(victim)then return false end
   if victim:AmIAlliedWith(ctx.owner,false)~=false then return false end
   return native_candidate(victim,ctx,attacker)
  end)
  if not ok then failure(result);return false end;return result
 end
 function api.knockout(victim,attacker,evidence)
  local ok,result=pcall(function()
   local ctx=context();assert(ctx,'slave_context_missing')
   assert(api.is_capturable(victim,attacker),'slave_capture_not_authorized')
   sequence=sequence+1
   local r={creature=victim,key=key(victim),state='knocked_out',owner=ctx.owner,origin=num(victim.ColonyID),
    group=-1,flags=encode_flags(victim),id=tostring(os.time())..'_'..tostring(sequence),evidence=evidence}
   local applied,err=pcall(function()
    -- Save the living individual's original stats/abilities/appearance before
    -- it can be saved while carried. Native load rebuilds even enemy Swarms
    -- under NG+; waiting until queen delivery would capture those new values.
    -- This only reads reflected fields and writes flat Tags, with no loads.
    if options.conversion then
     local copied,why=options.conversion.capture_snapshot(victim);assert(copied~=nil,why)
    end
    freeze(r);write_tag(r)
   end)
   if not applied then abort(r,'slave_freeze_failed:'..tostring(err));return false end
   records[r.key]=r;return true
  end)
  if not ok then return failure(result)end;return result
 end
 function api.describe_state(c)
  local ok,r=pcall(load_record,c);if not ok then failure(r);return nil end
  if r then return{state=r.state,owner=r.owner,group=r.group,id=r.id,stage=r.stage}end
 end
 function api.is_slave(c)local s=api.describe_state(c);return s~=nil and(s.state=='slave'or s.state=='wounded')end
 function api.is_active_slave(c)local s=api.describe_state(c);return s~=nil and s.state=='slave'and alive(c)end
 function api.position(c)return location(c)end
 function api.is_loaded(c)return held(c)~=nil end
 function api.set_group(c,group)
  local ok,result=pcall(function()
   assert(type(group)=='number'and group%1==0 and group>=-1 and group<=7,'slave_group_invalid')
   local r=assert(load_record(c),'slave_record_missing');local ctx=assert(context(),'slave_context_missing')
   assert(r.owner==ctx.owner and native.is_owned(c,ctx.gs)==true,'slave_group_not_owned')
   release_work(work_tickets[key(c)])
   r.group=group;own_control(r,ctx);write_tag(r);return true
  end)
  if not ok then return failure(result)end;return result
 end
 function api.work_active(ticket)
  if type(ticket)~='table'or work_tickets[ticket.key]~=ticket then return false end
  local c=ticket.creature;local r=records[ticket.key];local ctx=context()
  return ctx~=nil and alive(c)and key(c)==ticket.key and same_world(c,ctx)
   and r~=nil and r.state=='slave'and not r.loaded and r.owner==ctx.owner
   and native.is_owned(c,ctx.gs)==true and not carriers[ticket.key]
   and c.Immobile~=true and not valid(safe(function()return c.PickedUpCreature end))
 end
 function api.acquire_work(c)
  local ok,result=pcall(function()
   local r=assert(load_record(c),'slave_work_record_missing');local ctx=assert(context(),'slave_context_missing')
   local k=assert(key(c),'slave_work_invalid_actor')
   assert(not stopped and r.state=='slave'and not r.loaded and alive(c)and same_world(c,ctx)
    and r.owner==ctx.owner and native.is_owned(c,ctx.gs)==true and swarm(c),'slave_work_not_active')
   assert(not carriers[k]and not work_tickets[k]and c.Immobile~=true and c.InCombat~=true
    and c.AbilityInUse~=true and not valid(safe(function()return c.PickedUpCreature end)),'slave_work_busy')
   local ticket={creature=c,key=k,world=ctx.world,owner=ctx.owner,brain=stop_brain(c)}
   work_tickets[k]=ticket;return ticket
  end)
  if not ok then return failure(result)end;return result
 end
 function api.release_work(ticket)
  local ok,result=pcall(release_work,ticket);if not ok then return failure(result)end;return result
 end
 function api.move_work(ticket,target,position)
  local ok,result=pcall(function()
   assert(api.work_active(ticket),'slave_work_expired');local c=ticket.creature
   assert(valid(target)and native.world_id(target)==ticket.world,'slave_work_target_invalid')
   if not position then move(c,target);return true end
   assert(num(position.X)and num(position.Y)and num(position.Z),'slave_work_position_invalid')
   local ctl=c:GetController()
   assert(valid(ctl)and valid(ctl.PathFollowingComponent)and is_a(ctl.PathFollowingComponent,'/Script/EotU.CreaturePathFollowingComponent'),'slave_path_component_missing')
   c.CurrentTarget=target;c.CurrentTargetLocation=position
   local previous=moves[ticket.key]
   local ctx=context();local now=ctx and num(safe(function()return ctx.gs:GetLevelTime()end));local pos=location(c)
   if previous and previous.target==key(target)and previous.explicit and valid(previous.proxy)then
    local moved=previous.position and((pos.X-previous.position.X)^2+(pos.Y-previous.position.Y)^2+(pos.Z-previous.position.Z)^2)>100
    if moved then previous.position={X=pos.X,Y=pos.Y,Z=pos.Z};previous.progress_at=now end
    local status=num(safe(function()return ctl:GetMoveStatus()end))
    local retry=now and previous.requested_at and now-previous.requested_at>=1
     and(status==0 or(previous.progress_at and now-previous.progress_at>=2))
    if not retry then c:UpdateMovementGoal(position);return true end
    ctl:StopMovement()
   end
   local helper=class_cache.move_helper
   if not valid(helper)then helper=StaticFindObject('/Script/AIModule.Default__AIBlueprintHelperLibrary');class_cache.move_helper=helper end
   assert(valid(helper),'slave_move_helper_missing');c:SetCurrentAnimation(11)
   local proxy=helper:CreateMoveToProxyObject(c,c,position,nil,num(c.ArrivalDist)or 55,false)
   assert(valid(proxy),'slave_move_proxy_failed')
   moves[ticket.key]={target=key(target),proxy=proxy,explicit=true,requested_at=now,progress_at=now,
    position={X=pos.X,Y=pos.Y,Z=pos.Z}};return true
  end)
  if not ok then return failure(result)end;return result
 end
 function api.return_work_home(ticket)
  local ok,result=pcall(function()
   assert(api.work_active(ticket),'slave_work_expired');local ctx=assert(context(),'slave_context_missing')
   local c=ticket.creature
   if num(c.ColonyLocation)~=num(ctx.queen.ColonyLocation)then travel_home(c,ctx)end
   return{home=num(c.ColonyLocation)==num(ctx.queen.ColonyLocation),owner=ctx.owner,queen=ctx.queen,grid=ctx.grid}
  end)
  if not ok then return failure(result)end;return result
 end
 local function command_colony(r,ctx)
  local c=r.creature
  if (num(c.Health)or 0)<=0 or c.AbilityInUse==true then return end
  local attack=ctx.grid:GetGroupAttackByID(r.group)~=false
  local enemy=attack and c:NearestEnemyCreatureDirect(num(c.TargetRadius)or 400,false,0,false)
  if alive(enemy)and c:IsCreatureEnemy(enemy)==true then
   c:EnterCombat(enemy);c.CurrentTarget=enemy;c:SelectAbility()
   if c:TargetWithinAbilityRange(false,enemy)==true then c:UseAbility()else move(c,enemy)end
  else
   c:ForceLeaveCombat()
   local marker=r.group>=0 and ctx.grid:GetCallToArmsByID(r.group)or nil
   local target=valid(marker)and marker or ctx.queen
    if dist2(c,target)>180*180 then move(c,target)else c:GetController():StopMovement();moves[key(c)]=nil end
  end
 end
 function api.poll(c,_,now)
  local r
  local ok,result=pcall(function()
   r=load_record(c);if not r then return nil end
   local ctx=context();if not ctx or not same_world(c,ctx)or r.owner~=ctx.owner then return nil end
   if r.loaded then
    if r.restore_retry and(num(now)or 0)<r.restore_retry then return api.describe_state(c)end
    r.loaded=false
    if r.layer~=num(c.ColonyLocation)then
     assert(r.layer==-1 or valid(ctx.gs:GetTileGridByColonyID(r.layer)),'slave_restore_layer_missing')
     assert(c:SetActorLocationAndColonyLocation(location(c),r.layer)==true,'slave_restore_layer_failed')
     assert(num(c.ColonyLocation)==r.layer,'slave_restore_layer_readback_failed')
    end
    if options.conversion then
     local restored,why=options.conversion.restore(c)
     if restored==false and why=='slave_copy_assets_pending'then
      r.loaded=true;return api.describe_state(c)
     end
     if restored==nil then
      -- A native profile rebuild can differ from an older capture snapshot.
      -- A restore error is not a failed new capture: retain the saved actor
      -- and capture ID rather than aborting back to its former enemy owner.
      r.loaded=true;r.restore_retry=(num(now)or 0)+2
      failure('slave_saved_snapshot_restore_failed:'..tostring(why));return api.describe_state(c)
     end
     r.restore_retry=nil
    end
    if r.state~='slave'then
     freeze(r)
     local carrying=safe(function()return c.PickedUpCreature end)
     if alive(carrying)and native.is_owned(carrying,ctx.gs)==true and held(carrying)==c
      and num(carrying.ColonyLocation)==r.layer and not carriers[key(carrying)]then
      reserve(carrying,r);r.carrier.loaded=true;r.stage='carried'
     end
    else own_control(r,ctx);slave_ready(c)end
   end
   if r.state=='slave'then
    if r.layer~=num(c.ColonyLocation)then write_tag(r)end
    if colony(c)then command_colony(r,ctx)end
    return api.describe_state(c)
   end
   assert(alive(c),'slave_incapacitated_actor_died')
   c:SetCurrentAnimation(8)
   if r.carrier and(not alive(r.carrier.creature)or native.is_owned(r.carrier.creature,ctx.gs)~=true)then release_carrier(r)end
   if not r.carrier then
    local selected=find_carrier(r,ctx,now)
    if selected then reserve(selected,r)else return api.describe_state(c)end
   end
   local carrier=r.carrier.creature
   if not r.carrier.loaded then
    if dist2(carrier,c)<=M.pickup_distance*M.pickup_distance then pickup(r)else move(carrier,c)end
   elseif held(carrier)~=c then release_carrier(r)
   elseif num(carrier.ColonyLocation)==num(ctx.queen.ColonyLocation)and dist2(carrier,ctx.queen)<=M.queen_distance*M.queen_distance then
    if options.treatment then
     if r.treatment_retry and(num(now)or 0)<r.treatment_retry then return api.describe_state(c)end
     if not r.treatment_ticket then
      local ticket,why=options.treatment.begin(carrier,c);assert(ticket,why or 'slave_treatment_begin_failed')
      r.treatment_ticket=ticket;r.stage='treating'
     end
     local progress,why=options.treatment.poll(r.treatment_ticket)
     if progress~='running'and progress~='completed'then
      -- Keep the captured individual pending when an interrupted/stalled clip
      -- fails. Restore the carrier before retrying; never award a conversion.
      local cancelled,cancel_error=options.treatment.cancel(r.treatment_ticket);assert(cancelled,cancel_error)
      r.treatment_ticket=nil;r.treatment_retry=(num(now)or 0)+2;r.stage='carried';moves[key(carrier)]=nil
      failure(why or'slave_treatment_failed');return api.describe_state(c)
     end
     if progress=='completed'then convert(r,ctx)end
    else convert(r,ctx)end
   else
    if r.treatment_ticket then
     -- Treatment immobilises the carrier. A displaced queen/carrier must
     -- release that animation lock before requesting the return path.
     local cancelled,why=options.treatment.cancel(r.treatment_ticket);assert(cancelled,why)
     r.treatment_ticket=nil;r.stage='carried';moves[key(carrier)]=nil
    end
    travel_home(carrier,ctx)
    if r.layer~=num(c.ColonyLocation)then write_tag(r)end
   end
   local result=api.describe_state(r.creature)
   if result and r.creature~=c then result.creature=r.creature end
   return result
  end)
  if not ok then if r then abort(r,'slave_poll_failed:'..tostring(result))else failure(result)end end
  return ok and result or nil
 end
 function api.medical_begin(c)
  local r
  local ok,result=pcall(function()
   r=assert(load_record(c),'slave_record_missing');local ctx=assert(context(),'slave_context_missing')
   assert(r.state=='slave'and native.is_owned(c,ctx.gs)==true,'slave_medical_not_owned')
   assert(api.can_begin_medical(c,true),'slave_no_live_medic')
   r.medical_transaction={flags=r.flags,brain=r.brain,current_flags=encode_flags(c),stage=r.stage}
   r.flags=r.medical_transaction.current_flags;r.state='wounded';freeze(r);write_tag(r);return true
  end)
  if not ok then
   if r and r.medical_transaction then api.medical_rollback(c)end
   return failure(result)
  end;return result
 end
 function api.medical_rollback(c)
  local ok,result=pcall(function()
   local r=load_record(c);if not r or not r.medical_transaction then return true end
   local previous=r.medical_transaction
   local released,release_error=pcall(release_carrier,r)
   r.flags=previous.current_flags;restore_flags(r)
   if r.brain~=previous.brain then resume_brain(r.brain)end
   r.brain=previous.brain;r.flags=previous.flags;r.state='slave';r.stage=previous.stage
   wake_animation(r);write_tag(r);r.medical_transaction=nil
   if not released then error(release_error)end
   return true
  end)
  if not ok then return failure(result)end;return result
 end
 function api.can_begin_medical(c,allow_lethal)
  local ok,result=pcall(function()
   if not api.capture_ready()or not valid(c)or not num(c.Health)or(not allow_lethal and not alive(c))then return false end
   local r=load_record(c);if not r or r.state~='slave'then return false end
   local ctx=context();if not ctx or native.is_owned(c,ctx.gs)~=true then return false end
   rebuild_candidates(ctx,0)
   for _,medic in ipairs(medics)do
    if alive(medic)and num(medic.ColonyID)==ctx.owner and same_world(medic,ctx)then return true end
   end
   return false
  end)
  if not ok then failure(result);return false end;return result
 end
 function api.prune_dead()
  local ok,result=pcall(function()
   local ctx=context();if not ctx then return{removed=0,anchors_removed=0}end
   local dead,addresses={},{}
   for k,r in pairs(records)do
    local current=valid(r.creature)and key(r.creature)==k
    if not current or(not alive(r.creature)and same_world(r.creature,ctx))then
     dead[#dead+1]={key=k,record=r,current=current}
     local address=k:match('^(.-)|');addresses[address]=addresses[address]or{};addresses[address][k]=true
    end
   end
   if #dead==0 then return{removed=0,anchors_removed=0}end
   local report={removed=0,anchors_removed=0}
   -- Rebuild the native flat assignment array once for this batch. Do not
   -- rebuild nested creature abilities or touch any living unrelated entry.
   local keep,changed={},false
   each(ctx.grid.ControllableSwarmCreatures,function(_,a)
    local actor=a.Creature;local address=actor and safe(function()return actor:GetAddress()end)
    local retired=address and addresses[tostring(address)]
    if retired and(not valid(actor)or retired[key(actor)])then changed=true
    elseif valid(actor)then keep[#keep+1]={Creature=actor,GroupAssignment=num(a.GroupAssignment)}
    else changed=true end
   end)
   if changed then ctx.grid.ControllableSwarmCreatures=keep;ctx.grid:RefreshControllableSwarmTargets()end
   for _,entry in ipairs(dead)do
    local r=entry.record;release_work(work_tickets[entry.key]);release_carrier(r)
    local c=entry.current and r.creature or nil;local point=r.point or(valid(c)and safe(function()return c.SwarmPoint end))
    local owned_point=false
    if valid(point)and same_world(point,ctx)and is_a(point,'/Script/EotU.Swarm')and num(point.ColonyID)==r.owner then
     for _,tag in ipairs(tags(point))do if tag==M.point_prefix..r.id then owned_point=true;break end end
    end
    if owned_point then
     local others=0
     each(point.SwarmCreatures,function(_,member)
      if valid(member)and(not valid(c)or key(member)~=key(c))then others=others+1 end
     end)
     assert(others==0,'slave_dead_point_has_other_members')
     if valid(c)then
      point:DeRegisterSwarmCreature(c)
      if valid(c.SwarmPoint)and key(c.SwarmPoint)==key(point)then c.SwarmPoint=nil end
     end
     local remaining=0;each(point.SwarmCreatures,function()remaining=remaining+1 end)
     if remaining>0 then
      local utilities=class_cache.utilities
      if not valid(utilities)then utilities=StaticFindObject('/Script/EotU.Default__EotUUtilities');class_cache.utilities=utilities end
      assert(valid(utilities),'slave_cleanup_utilities_missing')
      utilities:RemoveCreaturesNotInPlayFromSwarmPoint(point)
      remaining=0;each(point.SwarmCreatures,function()remaining=remaining+1 end)
     end
     assert(remaining==0,'slave_dead_point_not_empty')
     point:K2_DestroyActor();assert(not valid(point),'slave_dead_point_not_destroyed')
     report.anchors_removed=report.anchors_removed+1
    end
    if valid(c)then write_tag(r,true)end
    records[entry.key]=nil;report.removed=report.removed+1
   end
   return report
  end)
  if not ok then return failure(result)end;return result
 end
 -- The native UI may move individual swarm cards before our aggregate card
 -- exists. Adopt those assignments only when the UI has drained queued cohort
 -- moves; grouped_rows/describe_state must retain their side-effect-free view.
 function api.reconcile_control_groups()
  local ok,result=pcall(function()
   local ctx=context();if not ctx then return{changed=0}end;local assignments={}
   each(ctx.grid.ControllableSwarmCreatures,function(_,entry)
    local c,group=entry.Creature,num(entry.GroupAssignment)
    if valid(c)and group and group%1==0 and group>=-1 and group<=7 then assignments[key(c)]=group end
   end)
   local changed=0
   for _,r in pairs(records)do
    local c=r.creature;local group=assignments[r.key]
    if group~=nil and group~=r.group and not r.loaded and(r.state=='slave'or r.state=='wounded')
     and alive(c)and key(c)==r.key and same_world(c,ctx)and native.is_owned(c,ctx.gs)==true then
     release_work(work_tickets[r.key])
     local previous=r.group;r.group=group
     local saved,why=pcall(write_tag,r)
     if not saved then r.group=previous;error(why)end
     changed=changed+1
    end
   end
   return{changed=changed}
  end)
  if not ok then return failure(result)end;return result
 end
 function api.grouped_rows()
  local out={};for _,r in pairs(records)do if alive(r.creature)and key(r.creature)==r.key and(r.state=='slave'or r.state=='wounded')then
   local species=str(r.creature.CreatureName);local k=species..':'..r.group
   local row=out[k]or{species=species,group=r.group,count=0,wounded=0,creatures={}};out[k]=row
   row.count=row.count+1;if r.state=='wounded'then row.wounded=row.wounded+1 end;row.creatures[#row.creatures+1]=r.creature
  end end;local list={};for _,r in pairs(out)do list[#list+1]=r end
  table.sort(list,function(a,b)if a.group~=b.group then return a.group<b.group end;return a.species<b.species end);return list
 end
 function api.set_species_group(species,group)
  for _,r in pairs(records)do if valid(r.creature)and str(r.creature.CreatureName)==species and(r.state=='slave'or r.state=='wounded')then
   local ok,err=api.set_group(r.creature,group);if not ok then return nil,err end
  end end;return true
 end
 function api.abort(c,reason)
  local r=load_record(c);if not r then return true end
  local ok,result=pcall(abort,r,reason or 'slave_task_cancelled')
  if not ok then return failure(result)end;return true
 end
 function api.status()
  local result={capture_ready=api.capture_ready(),colony_control_verified=options.colony_control_verified==true,
   knocked_out=0,slave=0,wounded=0,carrying=0,errors={}}
  for _,r in pairs(records)do if valid(r.creature)then
   result[r.state]=(result[r.state]or 0)+1;if r.carrier and r.carrier.loaded then result.carrying=result.carrying+1 end
  end end
  for e in pairs(reported)do result.errors[#result.errors+1]=e end
  return result
 end
 function api.reset_cache()
  local errors={}
  for _,ticket in pairs(work_tickets)do
   local ok,why=pcall(release_work,ticket);if not ok then errors[#errors+1]=tostring(why);failure(why)end
  end
  for _,r in pairs(records)do
   local released,release_error=pcall(release_carrier,r)
   local restored,restore_error=pcall(function()if valid(r.creature)then restore_flags(r);resume_brain(r.brain)end end)
   if not released then errors[#errors+1]=tostring(release_error);failure(release_error)end
   if not restored then errors[#errors+1]=tostring(restore_error);failure(restore_error)end
  end
  records={};carriers={};moves={};work_tickets={};candidate_epoch=nil;candidate_world=nil;candidate_cells={};medics={}
  if #errors>0 then return nil,table.concat(errors,'; ')end
  return true
 end
 function api.stop()
  stopped=true
  return api.reset_cache()
 end
 return api
end
return M
