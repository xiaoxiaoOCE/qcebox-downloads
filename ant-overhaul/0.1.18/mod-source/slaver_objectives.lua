-- 1.1 New Home keeps spawned enemies in its own objective array. Its original
-- CheckVictory tests IsValid + IsInPlay, not allegiance. A converted captive
-- therefore needs to leave that enemy list while remaining alive and owned.
-- TileSurfers and all native victory/reward logic remain authoritative.
local M={hook='/Game/Levels/Formicarium/Stage1/1-1-NewHome.1-1-NewHome_C:CheckVictory',
 class='/Game/Levels/Formicarium/Stage1/1-1-NewHome.1-1-NewHome_C',
 world='/Game/Levels/Formicarium/Stage1/1-1-NewHome.1-1-NewHome'}
local function safe(fn)local ok,v=pcall(fn);if ok then return v end end
local function unbox(v)local value=v~=nil and safe(function()return v:get()end);return value~=nil and value or v end
local function number(v)local n=tonumber(unbox(v));return n and n==n and math.abs(n)<math.huge and n or nil end
function M.install(options)
 assert(type(options)=='table'and type(options.native)=='table'and type(options.adapter)=='table')
 assert(type(options.get_context)=='function'and type(options.adapter.describe_state)=='function')
 local native,adapter=options.native,options.adapter
 local stopped,epoch,binding,attempt_key,attempts=false,0,nil,nil,0
 local probe_world,next_probe,last_probe=nil,-math.huge,-math.huge
 local clock=options.clock or os.clock
 local busy,reported={},{}
 local stats={checks=0,removed=0,writes=0,registrations=0,errors=0}
 local api={}
 local function valid(v)return v~=nil and safe(function()return native.valid_object(v)end)==true end
 local function key(v)
  if not valid(v)then return nil end
  local address=safe(function()return v:GetAddress()end);local name=safe(function()return v:GetFullName()end)
  return address and type(name)=='string'and tostring(address)..'|'..name or nil
 end
 local function report(e)
  e=tostring(e)
  if not reported[e]then
   reported[e]=true;stats.errors=stats.errors+1
   if options.log then pcall(options.log,'[SlaverObjectives] '..e)end
  end
  return nil,e
 end
 local function current_function()
  return(options.find_function or StaticFindObject)(M.hook)
 end
 local function context()
  local c=options.get_context();local gs=type(c)=='table'and(c.gs or c.game_state)
  if not valid(gs)then return nil end
  local pc=c.pc or c.controller or native.get_local_controller(gs)
  if not valid(pc)then return nil end
  local owner=number(pc:GetColonyID());local world=native.world_id(gs)
  if not world or not owner or owner<0 or owner%1~=0 then return nil end
  return gs,world,owner,c
 end
 local function array(a)
  local out={}
  if type(a)=='table'and type(a.GetArrayNum)~='function'then
   for i,v in ipairs(a)do out[i]=unbox(v)end
  else
   local n=number(a:GetArrayNum());assert(n and n>=0 and n<=65536,'objective_array_invalid')
   for i=1,n do
    local value=unbox(a[i])
    -- Let the native check prune null entries first. A Lua table cannot retain
    -- a nil array element without changing the remaining native indices.
    if value==nil then return nil end
    out[i]=value
   end
  end
  return out
 end
 local function same_array(a,b)
  if not a or#a~=#b then return false end
  for i,v in ipairs(a)do
   if v~=b[i]then
    local ka,kb=safe(function()return v:GetAddress()end),safe(function()return b[i]:GetAddress()end)
    if ka==nil or kb==nil or tostring(ka)~=tostring(kb)then return false end
   end
  end
  return true
 end
 local function filter(receiver)
  receiver=unbox(receiver)
  local gs,world,owner=context();if not gs or not valid(receiver)or native.world_id(receiver)~=world then return end
  local cls=receiver:GetClass();if not valid(cls)then return end
  local class_name=cls:GetFullName()
  if class_name~='BlueprintGeneratedClass '..M.class and class_name~=M.class then return end
  local receiver_key=key(receiver);if not receiver_key or busy[receiver_key]then return end
  busy[receiver_key]=true
  local ok,why=pcall(function()
   stats.checks=stats.checks+1
   local original=array(receiver.SpawnedEnemies);if not original then return end
   local keep,removed={},0
   for _,creature in ipairs(original)do
    local captured=false
    if valid(creature)and native.world_id(creature)==world and native.is_owned(creature,gs)==true then
     local record=adapter.describe_state(creature)
     captured=type(record)=='table'and(record.state=='slave'or record.state=='wounded')
      and number(record.owner)==owner and type(record.id)=='string'and record.id~=''
    end
    if captured then removed=removed+1 else keep[#keep+1]=creature end
   end
   if removed==0 then return end
   local changed,error_message=pcall(function()
    receiver.SpawnedEnemies=keep
    assert(same_array(array(receiver.SpawnedEnemies),keep),'objective_array_readback_failed')
   end)
   if not changed then
    local restored=pcall(function()
     receiver.SpawnedEnemies=original
     assert(same_array(array(receiver.SpawnedEnemies),original),'objective_array_rollback_readback_failed')
    end)
    error(tostring(error_message)..'; rollback='..tostring(restored))
   end
   stats.removed=stats.removed+removed;stats.writes=stats.writes+1
  end)
  busy[receiver_key]=nil
  if not ok then report(why)end
 end
 local function retire()
  epoch=epoch+1;local old=binding;binding=nil;busy={}
  if not old then return true end
  -- UnregisterHook resolves its path again. Never pass an old function's IDs
  -- to a replacement UFunction after map reload; the old closure is now inert.
  local current=safe(current_function)
  if key(current)==old.key then
   local unregister=options.unregister_hook or UnregisterHook
   local ok,why=pcall(unregister,M.hook,old.pre,old.post)
   if not ok then return report('objective_hook_unregister_failed:'..tostring(why))end
  end
  return true
 end
 function api.tick()
  if stopped then return false end
  local ok,result=pcall(function()
   local gs,world,owner,ctx=context();if not gs then return false end
   if probe_world~=world then
    if binding then local retired,why=retire();assert(retired,why)end
    probe_world=world;next_probe=-math.huge;last_probe=-math.huge;attempt_key=nil;attempts=0
   end
   -- Other levels cannot execute this exact level-script function. Avoid
   -- repeated global negative lookups while playing elsewhere or in the lab.
   local world_object=ctx.world or gs:GetWorld()
   if not valid(world_object)or world_object:GetFullName()~='World '..M.world then
    if binding then local retired,why=retire();assert(retired,why)end
    return false
   end
   -- A live bound UFunction is stable within its world. A reload invalidates
   -- it or changes the world; neither needs a global path lookup every frame.
   if binding and key(binding.object)==binding.key then return true end
   if binding then local retired,why=retire();assert(retired,why)end
   local now=clock()
   if now>=last_probe and now<next_probe then return false end
   last_probe=now;next_probe=now+1
   local fn=current_function();local identity=key(fn)
   if not identity then attempt_key=nil;attempts=0;return false end
   if attempt_key~=identity then attempt_key=identity;attempts=0 end
   if attempts>=3 then return false end
   attempts=attempts+1
   local token=epoch;local register=options.register_hook or RegisterHook
   local pre,post=register(M.hook,function(receiver)
    if stopped or token~=epoch then return end
    local called,why=pcall(filter,receiver);if not called then report(why)end
   end)
   assert(pre~=nil,'objective_hook_registration_failed')
   binding={object=fn,key=identity,pre=pre,post=post};stats.registrations=stats.registrations+1
   return true
  end)
  if not ok then return report(result)end;return result
 end
 function api.reset_cache()
  local ok,why=retire();attempt_key=nil;attempts=0;probe_world=nil;next_probe=-math.huge;last_probe=-math.huge;return ok,why
 end
 function api.stop()stopped=true;return api.reset_cache()end
 function api.status()
  local out={stopped=stopped,registered=binding~=nil,hook=M.hook}
  for k,v in pairs(stats)do out[k]=v end;return out
 end
 return api
end
return M
