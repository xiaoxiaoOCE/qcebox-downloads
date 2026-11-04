-- Runtime adapter for the existing EotU colony-buff pipeline.
-- Loading this module does not register hooks, create timers, or modify objects.
local M = {}
M.prefix = "EAA_AllAttributes_v1_"

-- Rates below are for NEW attributes only. Existing native improvement fields
-- must remain in the original game path and must not be included in extras.
M.catalog = {
    { id="Health", title="生命值", buff_type=0, per_point=1, field="FullHealth", supported=true },
    { id="AttackDamage", title="近战攻击伤害", buff_type=1, per_point=0.05, field="AttackDamage", supported=true, scope="basic_attack_only" },
    { id="AttackSpeed", title="攻击速度", buff_type=2, per_point=0.003, field="AttackSpeed", supported=true },
    { id="Piercing", title="物理穿透", buff_type=3, per_point=0.005, field="Piercing", supported=true, effective_cap=0.8, scope="conservative_original_improvement_limit" },
    { id="MovementSpeed", title="移动速度", buff_type=4, per_point=2, field="OriginalMaxSpeed", supported=true, effective_cap=1200 },
    { id="ResourceHarvest", title="搬运数量", buff_type=5, per_point=0.4, field="FoodCarryMax", supported=true, integer=true },
    { id="Armour", title="护甲", buff_type=6, per_point=0.1, field="Armour", supported=true },
    { id="VenomResistance", title="毒液抗性", buff_type=7, per_point=0.005, field="VenomResist", supported=true, native_cap=0.8 },
    { id="PhysicalResistance", title="物理抗性", buff_type=8, per_point=0.005, field="PhysicalResist", supported=true, native_cap=0.8 },
    { id="OutOfCombatEvasion", title="非战斗闪避", buff_type=9, per_point=0.005, field="Evasion", supported=true, scope="native_CombatEvasion_flag_preserved" },
    { id="AreaOfEffectResistance", title="范围伤害抗性", buff_type=10, per_point=0.01, field="AOEResistance", supported=true },
    { id="Range", title="攻击范围", supported=false, reason="requires ability-specific baseline and MaxRange validation" },
    { id="Cooldown", title="技能冷却", supported=false, reason="requires ability-specific baseline and positive cooldown validation" },
    { id="MaxDamageTaken", title="单次伤害上限", supported=false, reason="requires MaxSingleDamage sentinel and baseline validation" },
}
local by_id = {}
for _, stat in ipairs(M.catalog) do by_id[stat.id] = stat end
M.by_id = by_id
function M.lookup(id) return by_id[id] end

local function safe(fn)
    local ok, value = pcall(fn)
    if ok then return value end
    return nil
end

local function unbox(value)
    if value == nil then return nil end
    local inner = safe(function() return value:get() end)
    return inner ~= nil and inner or value
end

local function string_value(value)
    value = unbox(value)
    if type(value) == "string" then return value end
    if value == nil then return nil end
    return safe(function() return value:ToString() end)
end

local function each(array, fn)
    if array == nil then return false, "array missing" end
    if type(array) == "table" and type(array.GetArrayNum) ~= "function" then
        return pcall(function()
            for index, value in ipairs(array) do fn(index, unbox(value)) end
        end)
    end
    local ok, err = pcall(function()
        -- UE4SS's callback-based ForEach can re-enter its Lua stack while an
        -- enum property is pushed. Use the pinned API's 1-based indexed path.
        -- Never probe a sentinel: its out-of-bounds accessor grows the array.
        local count = array:GetArrayNum()
        assert(type(count) == "number" and count >= 0 and count % 1 == 0 and count <= 2147483647, "invalid array length")
        for index = 1, count do fn(index, unbox(array[index])) end
    end)
    return ok, err
end

local engine_valid_function,engine_valid_library
local function wrapper_valid(object)
    return object ~= nil and safe(function() return object:IsValid() end) == true
end
local function valid(object)
    if not wrapper_valid(object) then return false end
    if not wrapper_valid(engine_valid_function) or not wrapper_valid(engine_valid_library) then
        engine_valid_function=safe(function()return StaticFindObject("/Script/Engine.KismetSystemLibrary:IsValid")end)
        engine_valid_library=safe(function()return StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")end)
    end
    if not wrapper_valid(engine_valid_function) or not wrapper_valid(engine_valid_library) then return false end
    -- Explicit UFunction invocation bypasses UObject:IsValid's Lua method.
    -- The latter still accepts an actor marked PendingKill after DestroyActor.
    return safe(function()return engine_valid_function(engine_valid_library,object)end)==true
end
M.valid_object=valid

local function object_id(object)
    if object == nil then return nil end
    local address = safe(function() return object:GetAddress() end)
    if address ~= nil then return tostring(address) end
    return safe(function() return object:GetFullName() end)
end

local function world_id(object)
    local world = safe(function() return object:GetWorld() end)
    if valid(world) then return object_id(world) end
    -- Some UE4SS bindings expose GetOuter but no UObject.GetWorld wrapper.
    local outer = object
    for _=1,8 do
        outer = safe(function() return outer:GetOuter() end)
        if not valid(outer) then return nil end
        local cls = safe(function() return outer:GetClass() end)
        local name = cls and string_value(safe(function() return cls:GetFName() end))
        if name == "World" then return object_id(outer) end
    end
    return nil
end

function M.get_local_controller(game_state)
    -- Index zero is the local player selected by the engine. Never enumerate
    -- arbitrary controllers: AI colony IDs must not authorize buff writes.
    local gameplay = safe(function() return StaticFindObject("/Script/Engine.Default__GameplayStatics") end)
    if not valid(gameplay) then return nil,"gameplay_statics_unresolved" end
    local controller = safe(function() return gameplay:GetPlayerController(game_state,0) end)
    if not valid(controller) then return nil,"local_controller_unresolved" end
    local is_local = safe(function() return controller:IsLocalController() end)
    if is_local == false then return nil,"controller_is_not_local" end
    -- Some UE4SS builds cannot bind IsLocalController; the engine's local-player
    -- lookup above remains the authority. Same-world check is always required.
    if world_id(controller) ~= world_id(game_state) then return nil,"controller_world_mismatch" end
    return controller
end

function M.is_owned(object, game_state)
    if not valid(object) or not valid(game_state) then return false, "invalid_object" end
    local source_world, state_world = world_id(object), world_id(game_state)
    if source_world == nil or state_world == nil then return false, "world_unresolved" end
    if source_world ~= state_world then return false, "different_world" end
    local controller,why=M.get_local_controller(game_state)
    if controller==nil then return false,why end
    local local_id=tonumber(unbox(safe(function() return controller:GetColonyID() end)))
    if local_id==nil then return false,"local_colony_unresolved" end
    local id = tonumber(safe(function() return object.ColonyID end))
    if id == nil or id~=local_id then return false, "not_player_owned" end
    return true
end

local function plain_rows(array)
    local rows = {}
    local ok, err = each(array, function(_, row)
        local creature = string_value(row.CreatureToApply)
        local name = string_value(row.BuffName)
        local kind, value = tonumber(row.BuffType), tonumber(row.BuffValue)
        if creature == nil or name == nil or kind == nil or value == nil then
            error("cannot faithfully read existing FColonyBuff")
        end
        rows[#rows+1] = { CreatureToApply=creature, BuffType=kind, BuffName=name, BuffValue=value }
    end)
    if not ok then return nil, tostring(err) end
    return rows
end

local function is_ours(name) return name:sub(1,#M.prefix) == M.prefix end

-- Pure planning function. Input/output FName fields are strings.
function M.build_buff_plan(existing_rows, extras_by_creature)
    if type(existing_rows) ~= "table" or type(extras_by_creature) ~= "table" then
        return nil, "expected existing rows and extra allocations"
    end
    local out = {}
    for _, row in ipairs(existing_rows) do
        if type(row.BuffName) ~= "string" then return nil, "existing row name is not a string" end
        if not is_ours(row.BuffName) then
            out[#out+1] = { CreatureToApply=row.CreatureToApply, BuffType=row.BuffType, BuffName=row.BuffName, BuffValue=row.BuffValue }
        end
    end
    local names = {}
    for name in pairs(extras_by_creature) do
        if type(name) ~= "string" or #name==0 or #name>512 then return nil, "invalid CreatureName" end
        names[#names+1] = name
    end
    table.sort(names)
    for _, name in ipairs(names) do
        local allocations = extras_by_creature[name]
        if type(allocations) ~= "table" then return nil, "invalid allocations for "..name end
        for id, points in pairs(allocations) do
            if type(points) ~= "number" or points~=points or points<0 or points>2147483647 or points%1~=0 then
                return nil, "invalid point count for "..name.."/"..tostring(id)
            end
            local stat = by_id[id]
            if points>0 and (stat==nil or not stat.supported) then return nil, "unsupported attribute "..tostring(id) end
        end
        for _, stat in ipairs(M.catalog) do
            local points = allocations[stat.id] or 0
            if points>0 then
                local amount = points * stat.per_point
                if stat.integer then amount=math.floor(amount+0.5) end
                if amount~=0 then
                    out[#out+1] = {
                        CreatureToApply=name, BuffType=stat.buff_type,
                        BuffName=M.prefix..name.."_"..stat.id, BuffValue=amount,
                    }
                end
            end
        end
    end
    return out
end

local function rows_equal(a,b)
    if #a~=#b then return false end
    for i,row in ipairs(a) do
        local other=b[i]
        -- FName equality is case-insensitive; its display spelling is whichever
        -- spelling Unreal interned first (e.g. LeafCutterMinor).
        if row.CreatureToApply:lower()~=other.CreatureToApply:lower() or row.BuffType~=other.BuffType or row.BuffName:lower()~=other.BuffName:lower() then return false end
        -- BuffValue is serialized as float32 by Unreal.
        if math.abs(row.BuffValue-other.BuffValue)>math.max(1e-6,math.abs(row.BuffValue)*1e-6) then return false end
    end
    return true
end

local function engine_rows(rows)
    local out={}
    for _,row in ipairs(rows) do
        out[#out+1]={ CreatureToApply=FName(row.CreatureToApply), BuffType=row.BuffType, BuffName=FName(row.BuffName), BuffValue=row.BuffValue }
    end
    return out
end

-- Mutates only an owned colony's array, preserving every other mod/game entry.
-- Repeated calls with the same allocation return changed=false.
function M.sync_grid(grid, extras, game_state)
    local allowed,reason=M.is_owned(grid,game_state)
    if not allowed then return nil,reason end
    local existing,err=plain_rows(safe(function() return grid.ColonyBuffs end))
    if existing==nil then return nil,err end
    local planned,plan_err=M.build_buff_plan(existing,extras)
    if planned==nil then return nil,plan_err end
    if rows_equal(existing,planned) then return {changed=false,rows=#planned} end
    local ok,write_err=pcall(function() grid.ColonyBuffs=engine_rows(planned) end)
    if not ok then return nil,"buff assignment failed: "..tostring(write_err) end
    local verified,read_err=plain_rows(safe(function() return grid.ColonyBuffs end))
    if verified==nil or not rows_equal(planned,verified) then
        local restored,restore_err=pcall(function() grid.ColonyBuffs=engine_rows(existing) end)
        return nil,"buff verification failed: "..tostring(read_err).."; restored="..tostring(restored).." "..tostring(restore_err)
    end
    return {changed=true,rows=#planned}
end

local refreshing={}
local colony_creature_class
-- Native LookupApplyStatsForLevel(true) adds current HP again for a Health buff.
-- Preserve the prior current HP explicitly, even if the native call fails.
function M.refresh_creature(creature,game_state)
    local allowed,reason=M.is_owned(creature,game_state)
    if not allowed then return nil,reason end
    local key=object_id(creature)
    if key==nil then return nil,"creature_identity_unresolved" end
    if refreshing[key] then return nil,"refresh_reentrant" end
    local before_health=tonumber(safe(function() return creature.Health end))
    local before_full=tonumber(safe(function() return creature.FullHealth end))
    if before_health==nil or before_full==nil or before_health~=before_health or before_full<=0 then return nil,"health_unresolved" end
    if before_health<=0 then return nil,"not_alive" end
    if not valid(colony_creature_class) then
        colony_creature_class=safe(function()return StaticFindObject("/Script/EotU.ColonyCreature")end)
    end
    if not valid(colony_creature_class) then return nil,"colony_creature_class_unresolved" end
    local is_colony=safe(function()return creature:IsA(colony_creature_class)end)
    if type(is_colony)~="boolean" then return nil,"creature_class_unresolved" end
    local spawn_scale=1
    if is_colony then
        spawn_scale=tonumber(safe(function()return creature.SpawnStatScailing end))
        if not spawn_scale or spawn_scale~=spawn_scale or spawn_scale<=0 or spawn_scale==math.huge then
            return nil,"spawn_stat_scaling_unresolved"
        end
    end
    refreshing[key]=true
    local ok,err=pcall(function()
        creature:LookupApplyStatsForLevel(true)
        -- Native ColonyCreature.ChangeCreatureLevel applies spawn scaling after
        -- rebuilding stats. This narrower refresh rebuilds only scalar stats:
        -- preserve rehabilitation scaling without rebuilding or rescaling the
        -- already-live abilities/effects and their cooldown timers.
        if spawn_scale~=1 then creature:ScaleStats(spawn_scale,true,true,false,false,false) end
    end)
    local new_full=tonumber(safe(function() return creature.FullHealth end))
    local restored,restore_err=false,"FullHealth became invalid"
    if new_full~=nil and new_full==new_full and new_full>0 then
        restored,restore_err=pcall(function() creature.Health=math.min(before_health,new_full) end)
    end
    refreshing[key]=nil
    if not ok then return nil,"native refresh failed: "..tostring(err).."; health restored="..tostring(restored) end
    if not restored then return nil,"health preservation failed: "..tostring(restore_err) end
    return { health_before=before_health, full_health_before=before_full, health_after=math.min(before_health,new_full), full_health_after=new_full }
end

function M.refresh_creatures(creatures,game_state)
    local result={refreshed=0,skipped=0,errors={}}
    local ok,err=each(creatures,function(_,creature)
        local entry,why=M.refresh_creature(creature,game_state)
        if entry then result.refreshed=result.refreshed+1
        else result.skipped=result.skipped+1; result.errors[why]=(result.errors[why] or 0)+1 end
    end)
    if not ok then return nil,tostring(err) end
    return result
end

-- These three need separate per-ability application; never sell inert points.
function M.extra_attribute_applicability(creature,stat_id)
    if not valid(creature) then return false,"invalid_creature" end
    if stat_id=="MaxDamageTaken" then
        local value=tonumber(safe(function() return creature.MaxSingleDamage end))
        return false,(value and value>0) and "finite_cap_present; adapter_not_enabled" or "unlimited_or_unknown_sentinel; adapter_not_enabled"
    end
    if stat_id=="Range" or stat_id=="Cooldown" then
        local found={}
        local ok=each(safe(function() return creature.AbilityList end),function(_,ability)
            local value=tonumber(stat_id=="Range" and ability.MaxRange or ability.Cooldown)
            local name=string_value(ability.AbilityName)
            if value and value>0 and name then found[#found+1]=name end
        end)
        return false,ok and (#found>0 and "abilities_present; adapter_not_enabled" or "no_positive_ability_value") or "ability_list_unreadable",found
    end
    local stat=by_id[stat_id]
    return stat~=nil and stat.supported or false,stat and stat.scope or nil
end

M.read_buff_rows=plain_rows
M.world_id=world_id
return M
