-- Three extended attributes outside EColonyBuff. No hooks/timers at import.
-- Caller must establish local ownership/same World and finish native setup first.
local M = {}
M.catalog = {
    {id="Range",title="攻击范围",per_point=2,supported=true,field="AttackTolDist",
        scope="positive melee tolerance, ability maximum range and target radius"},
    {id="Cooldown",title="技能冷却",per_point=-0.5,supported=true,minimum=0.1,
        scope="positive ability cooldowns; 0.1 seconds is a mod rule, not a verified native limit"},
    {id="MaxDamageTaken",title="单次伤害上限",per_point=-2,supported=true,minimum=1,field="MaxSingleDamage",
        scope="finite native cap, or current FullHealth when native cap is zero; mod extension"},
}
M.by_id = {}
for _,stat in ipairs(M.catalog) do M.by_id[stat.id]=stat end
function M.lookup(id) return M.by_id[id] end
local cache = {}
local object_validator
function M.set_object_validator(validator)
    assert(type(validator)=="function","object validator must be a function")
    object_validator=validator
end

local function safe(fn)
    local ok,value=pcall(fn)
    return ok and value or nil
end
local function finite(value)
    return type(value)=="number" and value==value and value~=math.huge and value~=-math.huge
end
local function number(value)
    local n=tonumber(value)
    return finite(n) and n or nil
end
local function equal(a,b)
    return finite(a) and finite(b) and math.abs(a-b)<=math.max(1e-6,math.abs(a)*1e-6,math.abs(b)*1e-6)
end
local function unbox(value)
    if value==nil then return nil end
    local inner=safe(function()return value:get()end)
    return inner~=nil and inner or value
end
local function name(value)
    value=unbox(value)
    if type(value)=="string" then return value end
    return value and safe(function()return value:ToString()end) or nil
end
local function valid(value)
    if value==nil or safe(function()return value:IsValid()end)~=true then return false end
    return object_validator~=nil and safe(function()return object_validator(value)end)==true
end
local function each(array,fn)
    if array==nil then return false,"ability_list_missing" end
    return pcall(function()
        if type(array)=="table" and type(array.GetArrayNum)~="function" then
            for i,v in ipairs(array) do fn(i,unbox(v)) end
        else
            local count=array:GetArrayNum()
            assert(type(count)=="number" and count>=0 and count%1==0 and count<=2147483647,"invalid ability array length")
            for i=1,count do fn(i,unbox(array[i])) end
        end
    end)
end
local function identity(creature)
    if not valid(creature) then return nil,"invalid_creature" end
    local address=safe(function()return creature:GetAddress()end)
    local fullname=safe(function()return creature:GetFullName()end)
    local creature_name=name(safe(function()return creature.CreatureName end))
    local level=number(safe(function()return creature.CreatureLevel end))
    if address==nil or type(fullname)~="string" or creature_name==nil or level==nil then
        return nil,"creature_identity_unresolved"
    end
    return tostring(address),fullname.."|"..creature_name.."|"..tostring(level)
end

-- Re-enumerate for read-back, so editing a copied struct cannot falsely pass.
local function snapshot(creature,options)
    local values,order,timers={}, {}, {}
    local function add(key,stat,field,owner)
        local value=number(safe(function()return owner[field]end))
        if value~=nil then
            values[key]={key=key,stat=stat,field=field,owner=owner,value=value}
            order[#order+1]=key
        end
    end
    add("AttackTolDist","Range","AttackTolDist",creature)
    -- Always observe it so disabling the option can restore an earlier write.
    add("TargetRadius","Range","TargetRadius",creature)
    add("MaxSingleDamage","MaxDamageTaken","MaxSingleDamage",creature)
    local occurrences={}
    local ok,err=each(safe(function()return creature.AbilityList end),function(_,ability)
        local ability_name=name(ability.AbilityName)
        if not ability_name then error("ability_name_unresolved") end
        occurrences[ability_name]=(occurrences[ability_name] or 0)+1
        local prefix="Ability:"..ability_name..":"..occurrences[ability_name]..":"
        add(prefix.."MaxRange","Range","MaxRange",ability)
        add(prefix.."Cooldown","Cooldown","Cooldown",ability)
        local timer=number(safe(function()return ability.CooldownTimer end))
        if timer~=nil then timers[prefix]=timer end
    end)
    if not ok then return nil,tostring(err) end
    return {values=values,order=order,timers=timers,
        full_health=number(safe(function()return creature.FullHealth end)),
        health=number(safe(function()return creature.Health end))}
end

local function applicable(snap,id)
    if id=="MaxDamageTaken" then
        local row=snap.values.MaxSingleDamage
        if not row then return false,"max_damage_unreadable" end
        if row.value>1 then return true,"finite_cap" end
        if row.value>0 then return false,"finite_cap_saturated" end
        if row.value==0 and snap.full_health and snap.full_health>1 then
            return true,"mod_rule_unlimited_uses_full_health"
        end
        if row.value==0 and snap.full_health and snap.full_health>0 then return false,"full_health_cap_saturated" end
        return false,"unknown_max_damage_sentinel"
    end
    if id=="Range" or id=="Cooldown" then
        for _,key in ipairs(snap.order) do
            local row=snap.values[key]
            -- TargetRadius alone is not evidence of an attack/ability range.
            local minimum=id=="Cooldown" and M.by_id.Cooldown.minimum or 0
            if row.stat==id and key~="TargetRadius" and row.value>minimum then return true end
        end
        return false,id=="Range" and "no_positive_attack_range" or "no_reducible_ability_cooldown"
    end
    return false,"unknown_extra_attribute"
end
function M.is_applicable(creature,id,options)
    if not valid(creature) then return false,"invalid_creature" end
    local snap,err=snapshot(creature,options)
    if not snap then return false,err end
    return applicable(snap,id)
end

local function allocations(points)
    if type(points)~="table" then return nil,"invalid_extra_points" end
    local out={}
    for _,stat in ipairs(M.catalog) do
        local count=points[stat.id] or 0
        if not finite(count) or count<0 or count%1~=0 or count>2147483647 then
            return nil,"invalid_points:"..stat.id
        end
        out[stat.id]=count
    end
    return out
end

-- opts.rebase=true is only safe IMMEDIATELY after native stats AND abilities
-- have been rebuilt without these extras. Ordinary repeated calls omit it.
function M.apply(creature,points,options)
    local counts,err=allocations(points)
    if not counts then return nil,err end
    local key,signature=identity(creature)
    if not key then return nil,signature end
    local snap,snap_err=snapshot(creature,options)
    if not snap then return nil,snap_err end
    local prior=cache[key]
    if not prior or prior.signature~=signature or (options and options.rebase) then prior={fields={}} end
    local next_fields,writes,report={}, {}, {}
    local range_eligible=applicable(snap,"Range")
    for _,field_key in ipairs(snap.order) do
        local row=snap.values[field_key]
        local old=prior.fields[field_key]
        local base=row.value
        -- Recognize only our exact previous output; any external/native change
        -- becomes the new unmodified baseline for this individual field.
        if old and equal(row.value,old.last_written) then base=old.base end
        local count=counts[row.stat]
        local desired=base
        local eligible=false
        if row.stat=="Range" then
            eligible=base>0 and range_eligible
                and (field_key~="TargetRadius" or not options or options.include_target_radius~=false)
            if eligible then desired=base+count*2 end
        elseif row.stat=="Cooldown" then
            -- Already faster native abilities must never be slowed to our floor.
            eligible=base>M.by_id.Cooldown.minimum
            if eligible and count>0 then desired=math.max(0.1,base-count*0.5) end
        elseif row.stat=="MaxDamageTaken" then
            eligible=base>1 or (base==0 and snap.full_health and snap.full_health>1)
            if eligible and count>0 then
                local start=base>0 and base or snap.full_health
                desired=math.max(1,start-count*2)
            end
        end
        if count>0 and eligible then
            next_fields[field_key]={base=base,last_written=desired,points=count}
        end
        if old or (count>0 and eligible) then
            report[#report+1]={field=field_key,stat=row.stat,base=base,before=row.value,after=desired}
            if not equal(row.value,desired) then
                writes[#writes+1]={row=row,before=row.value,after=desired}
            end
        end
    end
    local applied={}
    local function rollback(reason)
        local restored=true
        for i=#applied,1,-1 do
            local change=applied[i]
            local ok=pcall(function()change.row.owner[change.row.field]=change.before end)
            restored=restored and ok
        end
        local checked=snapshot(creature,options)
        if not checked then restored=false
        else
            for _,change in ipairs(applied) do
                local row=checked.values[change.row.key]
                if not row or not equal(row.value,change.before) then restored=false end
            end
        end
        return nil,reason.."; rollback_verified="..tostring(restored)
    end
    for _,change in ipairs(writes) do
        -- Include attempted write in rollback; a binding may mutate then throw.
        applied[#applied+1]=change
        local ok,write_err=pcall(function()change.row.owner[change.row.field]=change.after end)
        if not ok then return rollback("field_write_failed:"..change.row.key..":"..tostring(write_err)) end
    end
    local after,read_err=snapshot(creature,options)
    if not after then return rollback("readback_failed:"..tostring(read_err)) end
    for _,change in ipairs(writes) do
        local row=after.values[change.row.key]
        if not row or not equal(row.value,change.after) then return rollback("field_readback_failed:"..change.row.key) end
    end
    -- Merely observe these protected fields; never restore/change live timers.
    if snap.health~=nil and (after.health==nil or not equal(snap.health,after.health)) then
        return rollback("health_changed_during_extra_apply")
    end
    for timer,value in pairs(snap.timers) do
        if after.timers[timer]==nil or not equal(value,after.timers[timer]) then
            return rollback("cooldown_timer_changed_during_extra_apply:"..timer)
        end
    end
    cache[key]={signature=signature,fields=next_fields,creature=creature}
    return {changed=#writes>0,writes=#writes,fields=report}
end

function M.restore(creature,options)
    return M.apply(creature,{},options)
end
function M.forget(creature)
    local key,err=identity(creature)
    if not key then return nil,err end
    cache[key]=nil
    return true
end
function M.reset_cache() cache={} end
function M.forget_invalid()
    local removed=0
    for key,entry in pairs(cache) do
        if not valid(entry.creature) then cache[key]=nil;removed=removed+1 end
    end
    return removed
end
return M
