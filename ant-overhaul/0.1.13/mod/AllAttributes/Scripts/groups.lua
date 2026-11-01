-- Exact native improvement groups for Steam build 26119497 (1.2.1.1).
-- Aliases were read from LookupApplyStatsForLevel CreatureName comparisons.
-- Labels are descriptive Chinese labels, not extracted localization strings.
local M = { list = {
    {["id"]="WoodAntMelee",["title"]="木蚁近战兵",["creature_name"]="WoodAntMelee",["species"]=nil,["subtype"]=nil,["aliases"]={"WoodAntMelee"},["fields"]={"WoodAntMeleeHealthImprovment","WoodAntMeleePhysicalResistanceImprovment","WoodAntMeleeVenomResistanceImprovment","WoodAntMeleeAOEResistanceImprovment"},["native_by_stat"]={["Health"]="WoodAntMeleeHealthImprovment",["PhysicalResistance"]="WoodAntMeleePhysicalResistanceImprovment",["VenomResistance"]="WoodAntMeleeVenomResistanceImprovment",["AreaOfEffectResistance"]="WoodAntMeleeAOEResistanceImprovment"},["native_stats"]={["Health"]=true,["PhysicalResistance"]=true,["VenomResistance"]=true,["AreaOfEffectResistance"]=true}},
    {["id"]="LeafcutterMedia",["title"]="切叶蚁中型工蚁",["creature_name"]="LeafcutterMedia",["species"]=nil,["subtype"]=nil,["aliases"]={"LeafcutterMedia"},["fields"]={"LeafcutterMediaAttackDamageImprovment","LeafcutterMediaPiercingImprovment","LeafcutterMediaArmourImprovment","LeafcutterMediaHealthImprovment"},["native_by_stat"]={["AttackDamage"]="LeafcutterMediaAttackDamageImprovment",["Piercing"]="LeafcutterMediaPiercingImprovment",["Armour"]="LeafcutterMediaArmourImprovment",["Health"]="LeafcutterMediaHealthImprovment"},["native_stats"]={["AttackDamage"]=true,["Piercing"]=true,["Armour"]=true,["Health"]=true}},
    {["id"]="MatabeleSoldier",["title"]="马塔贝勒蚁兵蚁",["creature_name"]="MatabeleSoldier",["species"]=nil,["subtype"]=nil,["aliases"]={"MatabeleSoldier"},["fields"]={"MatabeleSoldierAttackDamageImprovment","MatabeleSoldierAttackSpeedImprovement","MatabeleSoldierMovementSpeedImprovment","MatabeleSoldierHealthImprovment"},["native_by_stat"]={["AttackDamage"]="MatabeleSoldierAttackDamageImprovment",["AttackSpeed"]="MatabeleSoldierAttackSpeedImprovement",["MovementSpeed"]="MatabeleSoldierMovementSpeedImprovment",["Health"]="MatabeleSoldierHealthImprovment"},["native_stats"]={["AttackDamage"]=true,["AttackSpeed"]=true,["MovementSpeed"]=true,["Health"]=true}},
    {["id"]="TermiteSoldier",["title"]="白蚁小型兵蚁",["creature_name"]="TermiteSoldier",["species"]=nil,["subtype"]=nil,["aliases"]={"TermiteSoldier"},["fields"]={"TermiteMinorSoldierAttackDamageImprovment","TermiteMinorSoldierPiercingImprovment","TermiteMinorSoldierPhysicalResistanceImprovment","TermiteMinorSoldierHealthImprovment"},["native_by_stat"]={["AttackDamage"]="TermiteMinorSoldierAttackDamageImprovment",["Piercing"]="TermiteMinorSoldierPiercingImprovment",["PhysicalResistance"]="TermiteMinorSoldierPhysicalResistanceImprovment",["Health"]="TermiteMinorSoldierHealthImprovment"},["native_stats"]={["AttackDamage"]=true,["Piercing"]=true,["PhysicalResistance"]=true,["Health"]=true}},
    {["id"]="TermiteMajorSoldier",["title"]="白蚁大型兵蚁",["creature_name"]="TermiteMajorSoldier",["species"]=nil,["subtype"]=nil,["aliases"]={"TermiteMajorSoldier"},["fields"]={"TermiteMajorSoldierMovementSpeedImprovment","TermiteMajorSoldierAttackDamageImprovment","TermiteMajorSoldierPhysicalResistanceImprovment","TermiteMajorSoldierVenomResistanceImprovment"},["native_by_stat"]={["MovementSpeed"]="TermiteMajorSoldierMovementSpeedImprovment",["AttackDamage"]="TermiteMajorSoldierAttackDamageImprovment",["PhysicalResistance"]="TermiteMajorSoldierPhysicalResistanceImprovment",["VenomResistance"]="TermiteMajorSoldierVenomResistanceImprovment"},["native_stats"]={["MovementSpeed"]=true,["AttackDamage"]=true,["PhysicalResistance"]=true,["VenomResistance"]=true}},
    {["id"]="ExplodingAntMajorSoldier",["title"]="自爆蚁大型兵蚁",["creature_name"]="ExplodingAntMajorSoldier",["species"]=nil,["subtype"]=nil,["aliases"]={"ExplodingAntMajorSoldier"},["fields"]={"ExplodingAntMajorSoldierAttackSpeedImprovment","ExplodingAntMajorSoldierHealthImprovment","ExplodingAntMajorSoldierPhysicalResistanceImprovment","ExplodingAntMajorSoldierMovementSpeedImprovment"},["native_by_stat"]={["AttackSpeed"]="ExplodingAntMajorSoldierAttackSpeedImprovment",["Health"]="ExplodingAntMajorSoldierHealthImprovment",["PhysicalResistance"]="ExplodingAntMajorSoldierPhysicalResistanceImprovment",["MovementSpeed"]="ExplodingAntMajorSoldierMovementSpeedImprovment"},["native_stats"]={["AttackSpeed"]=true,["Health"]=true,["PhysicalResistance"]=true,["MovementSpeed"]=true}},
    {["id"]="ExplodingTermiteSoldier",["title"]="自爆白蚁兵蚁",["creature_name"]="ExplodingTermiteSoldier",["species"]=nil,["subtype"]=nil,["aliases"]={"ExplodingTermiteSoldier"},["fields"]={"ExplodingTermiteSoldierAttackDamageImprovment","ExplodingTermiteSoldierPhysicalResistanceImprovment","ExplodingTermiteSoldierVenomResistanceImprovment","ExplodingTermiteSoldierMovementSpeedImprovment"},["native_by_stat"]={["AttackDamage"]="ExplodingTermiteSoldierAttackDamageImprovment",["PhysicalResistance"]="ExplodingTermiteSoldierPhysicalResistanceImprovment",["VenomResistance"]="ExplodingTermiteSoldierVenomResistanceImprovment",["MovementSpeed"]="ExplodingTermiteSoldierMovementSpeedImprovment"},["native_stats"]={["AttackDamage"]=true,["PhysicalResistance"]=true,["VenomResistance"]=true,["MovementSpeed"]=true}},
    {["id"]="NarrowHeadedAntSoldier",["title"]="窄首蚁兵蚁",["creature_name"]="NarrowHeadedAntSoldier",["species"]=nil,["subtype"]=nil,["aliases"]={"NarrowHeadedAntSoldier"},["fields"]={"NarrowHeadedSoldierAttackDamageImprovment","NarrowHeadedSoldierPiercingImprovment","NarrowHeadedSoldierPhysicalResistanceImprovment","NarrowHeadedSoldierHealthImprovment"},["native_by_stat"]={["AttackDamage"]="NarrowHeadedSoldierAttackDamageImprovment",["Piercing"]="NarrowHeadedSoldierPiercingImprovment",["PhysicalResistance"]="NarrowHeadedSoldierPhysicalResistanceImprovment",["Health"]="NarrowHeadedSoldierHealthImprovment"},["native_stats"]={["AttackDamage"]=true,["Piercing"]=true,["PhysicalResistance"]=true,["Health"]=true}},
    {["id"]="Worker",["title"]="工蚁",["creature_name"]=nil,["species"]=0,["subtype"]=0,["aliases"]={"WorkerAnt","FireAntWorker","MatabeleWorker","LeafcutterMinor","TermiteWorker","TermiteMajorWorker","BigHeadedMinor","ExplodingAntWorker"},["fields"]={"WorkerSpeedImprovment","WorkerHarvestImprovment"},["native_by_stat"]={["MovementSpeed"]="WorkerSpeedImprovment",["ResourceHarvest"]="WorkerHarvestImprovment"},["native_stats"]={["MovementSpeed"]=true,["ResourceHarvest"]=true}},
    {["id"]="Queen",["title"]="蚁后",["creature_name"]=nil,["species"]=0,["subtype"]=1,["aliases"]={"Queen","FireAntQueen","LeafcutterQueen","LittleBlackAntQueen","MatabeleQueen","TermiteQueen","ExplodingTermiteQueen","ExplodingAntQueen"},["fields"]={"QueenHealthImprovment","QueenCDImprovment"},["native_by_stat"]={["Health"]="QueenHealthImprovment",["Cooldown"]="QueenCDImprovment"},["native_stats"]={["Health"]=true,["Cooldown"]=true}},
    {["id"]="BlackAnt",["title"]="黑蚁",["creature_name"]=nil,["species"]=1,["subtype"]=nil,["aliases"]={"BlackAnt"},["fields"]={"BlackAntAttackImprovment","BlackAntPiercingImprovment","BlackAntArmourImprovment","BlackAntHealthImprovment"},["native_by_stat"]={["AttackDamage"]="BlackAntAttackImprovment",["Piercing"]="BlackAntPiercingImprovment",["Armour"]="BlackAntArmourImprovment",["Health"]="BlackAntHealthImprovment"},["native_stats"]={["AttackDamage"]=true,["Piercing"]=true,["Armour"]=true,["Health"]=true}},
    {["id"]="WoodAnt",["title"]="木蚁远程兵",["creature_name"]=nil,["species"]=2,["subtype"]=nil,["aliases"]={"WoodAntA","WoodAntB"},["fields"]={"WoodAntAttackDamageImprovment","WoodAntAttackSpeedImprovment","WoodAntRangeImprovment","WoodAntHealthImprovment"},["native_by_stat"]={["AttackDamage"]="WoodAntAttackDamageImprovment",["AttackSpeed"]="WoodAntAttackSpeedImprovment",["Range"]="WoodAntRangeImprovment",["Health"]="WoodAntHealthImprovment"},["native_stats"]={["AttackDamage"]=true,["AttackSpeed"]=true,["Range"]=true,["Health"]=true}},
    {["id"]="Leafcutter",["title"]="切叶蚁大型工蚁",["creature_name"]=nil,["species"]=3,["subtype"]=nil,["aliases"]={"LeafcutterMajorTaunt","LeafcutterMajorStun"},["fields"]={"LeafcutterHealthImprovment","LeafcutterPhysicalResImprovment","LeafcutterVenomResImprovment","LeafcutterAttackSpeedImprovment"},["native_by_stat"]={["Health"]="LeafcutterHealthImprovment",["PhysicalResistance"]="LeafcutterPhysicalResImprovment",["VenomResistance"]="LeafcutterVenomResImprovment",["AttackSpeed"]="LeafcutterAttackSpeedImprovment"},["native_stats"]={["Health"]=true,["PhysicalResistance"]=true,["VenomResistance"]=true,["AttackSpeed"]=true}},
    {["id"]="FireAnt",["title"]="火蚁",["creature_name"]=nil,["species"]=4,["subtype"]=nil,["aliases"]={"FireAntPervasive","FireAntVigorous"},["fields"]={"FireAntMovementSpeedImprovment","FireAntAOEResistanceImprovment","FireAntAttackDamageImprovment","FireAntPiercingImprovment"},["native_by_stat"]={["MovementSpeed"]="FireAntMovementSpeedImprovment",["AreaOfEffectResistance"]="FireAntAOEResistanceImprovment",["AttackDamage"]="FireAntAttackDamageImprovment",["Piercing"]="FireAntPiercingImprovment"},["native_stats"]={["MovementSpeed"]=true,["AreaOfEffectResistance"]=true,["AttackDamage"]=true,["Piercing"]=true}},
    {["id"]="Matabele",["title"]="马塔贝勒蚁医护兵",["creature_name"]=nil,["species"]=7,["subtype"]=nil,["aliases"]={"MatabeleMedicAnesthetist","MatabeleMedicFastResponder"},["fields"]={"MatabeleAntMovementSpeedImprovment","MatabeleAntAttackDamageImprovment","MatabeleAntPhysicalResistanceImprovment","MatabeleAntVenomResistanceImprovment"},["native_by_stat"]={["MovementSpeed"]="MatabeleAntMovementSpeedImprovment",["AttackDamage"]="MatabeleAntAttackDamageImprovment",["PhysicalResistance"]="MatabeleAntPhysicalResistanceImprovment",["VenomResistance"]="MatabeleAntVenomResistanceImprovment"},["native_stats"]={["MovementSpeed"]=true,["AttackDamage"]=true,["PhysicalResistance"]=true,["VenomResistance"]=true}},
    {["id"]="BulletAnt",["title"]="子弹蚁",["creature_name"]=nil,["species"]=11,["subtype"]=nil,["aliases"]={"BulletAnt"},["fields"]={"BulletAntPiercingImprovment","BulletAntAttackDamageImprovment","BulletAntHealthImprovment","BulletAntMaxSingleDamageImprovment"},["native_by_stat"]={["Piercing"]="BulletAntPiercingImprovment",["AttackDamage"]="BulletAntAttackDamageImprovment",["Health"]="BulletAntHealthImprovment",["MaxDamageTaken"]="BulletAntMaxSingleDamageImprovment"},["native_stats"]={["Piercing"]=true,["AttackDamage"]=true,["Health"]=true,["MaxDamageTaken"]=true}},
    {["id"]="ExplodingAnt",["title"]="自爆蚁兵蚁",["creature_name"]=nil,["species"]=13,["subtype"]=nil,["aliases"]={"ExplodingAntSoldier"},["fields"]={"ExplodingAntSoldierAttackDamageImprovment","ExplodingAntSoldierPiercingImprovment","ExplodingAntSoldierVenomResistanceImprovment","ExplodingAntSoldierMaxDamageTakenImprovment"},["native_by_stat"]={["AttackDamage"]="ExplodingAntSoldierAttackDamageImprovment",["Piercing"]="ExplodingAntSoldierPiercingImprovment",["VenomResistance"]="ExplodingAntSoldierVenomResistanceImprovment",["MaxDamageTaken"]="ExplodingAntSoldierMaxDamageTakenImprovment"},["native_stats"]={["AttackDamage"]=true,["Piercing"]=true,["VenomResistance"]=true,["MaxDamageTaken"]=true}},
    {["id"]="ExplodingTermite",["title"]="自爆白蚁工蚁",["creature_name"]=nil,["species"]=14,["subtype"]=nil,["aliases"]={"ExplodingTermiteWorker"},["fields"]={"ExplodingTermiteWorkerHealthImprovment","ExplodingTermiteWorkerArmourImprovment","ExplodingTermiteWorkerOutOfCombatEvasionImprovment","ExplodingTermiteWorkerMovementSpeedImprovment"},["native_by_stat"]={["Health"]="ExplodingTermiteWorkerHealthImprovment",["Armour"]="ExplodingTermiteWorkerArmourImprovment",["OutOfCombatEvasion"]="ExplodingTermiteWorkerOutOfCombatEvasionImprovment",["MovementSpeed"]="ExplodingTermiteWorkerMovementSpeedImprovment"},["native_stats"]={["Health"]=true,["Armour"]=true,["OutOfCombatEvasion"]=true,["MovementSpeed"]=true}},
    {["id"]="NarrowHeaded",["title"]="窄首蚁远程兵",["creature_name"]=nil,["species"]=15,["subtype"]=nil,["aliases"]={"NarrowHeadedAntRanged"},["fields"]={"NarrowHeadedRangedAttackDamageImprovment","NarrowHeadedRangedMovementSpeedImprovment","NarrowHeadedRangedHealthImprovment","NarrowHeadedRangedVenomResistanceImprovment"},["native_by_stat"]={["AttackDamage"]="NarrowHeadedRangedAttackDamageImprovment",["MovementSpeed"]="NarrowHeadedRangedMovementSpeedImprovment",["Health"]="NarrowHeadedRangedHealthImprovment",["VenomResistance"]="NarrowHeadedRangedVenomResistanceImprovment"},["native_stats"]={["AttackDamage"]=true,["MovementSpeed"]=true,["Health"]=true,["VenomResistance"]=true}},
} }
-- Mod-owned groups for the additional formicarium production chambers. These
-- units have no native improvement fields; their purchases live only in our
-- existing ledger. CreatureName values come from the real native hatch records
-- in analysis/story-roster-final-native-hatches.tsv and home-019-all13-hatched.
-- ArmyAntMedia is a class name: its actual CreatureName is still ArmyAnt.
M.supplemental = {}
local function supplement(id, title, creature_name, inherited_group)
    M.supplemental[#M.supplemental+1] = {
        id=id, title=title, creature_name=creature_name or id,
        aliases={creature_name or id}, fields={}, native_by_stat={}, native_stats={},
        supplemental=true, roster_id=id, inherited_group=inherited_group,
    }
end
supplement("LeafcutterSuperMajor", "切叶蚁超级兵")
supplement("SlaveMaker", "掠夺蚁", "SlaveMakerAnt")
supplement("TrapjawAnt", "大颚猛蚁")
supplement("ArmyAnt", "军蚁")
supplement("ArmyAntMajor", "大型军蚁")
supplement("BigHeadedMajor", "大头蚁兵蚁")
supplement("BigHeadedSuperSoldier", "大头蚁超级兵")
supplement("LittleBlackAnt", "小黑蚁")
supplement("TermiteMajorWorker", "白蚁大工", nil, "Worker")
supplement("DriverAntWorker", "行军蚁工蚁")
supplement("DriverAntSoldier", "行军蚁兵蚁")
supplement("DriverAntLargeSoldier", "行军蚁大型兵")
supplement("StinkAnt", "非洲臭猛蚁")

-- list remains the native field inventory. all includes independent mod groups
-- without making native-field collectors probe properties that do not exist.
M.all = {}
for _, group in ipairs(M.list) do M.all[#M.all+1] = group end
for _, group in ipairs(M.supplemental) do M.all[#M.all+1] = group end
M.by_id, M.by_creature = {}, {}
local canonical={}
for _, group in ipairs(M.all) do
    M.by_id[group.id] = group
    for _, name in ipairs(group.aliases) do M.by_creature[name] = group;canonical[name:lower()]=name end
end
function M.canonical_name(name)return type(name)=="string" and (canonical[name:lower()] or name) or name end
setmetatable(M.by_creature,{__index=function(t,k)return type(k)=="string" and rawget(t,M.canonical_name(k)) or nil end})

-- Membership, unlike exact resolution, includes the legacy Worker alias for
-- TermiteMajorWorker. Existing Worker purchases must keep affecting it.
function M.matches(group, name)
    if type(group)=="string" then group=M.by_id[group] end
    if type(group)~="table" or type(name)~="string" then return false end
    name=M.canonical_name(name)
    for _,alias in ipairs(group.aliases or {}) do if alias==name then return true end end
    return false
end

-- Exact actor/UI names take precedence over the species fallback.
function M.resolve(species, subtype, creature_name)
    if creature_name and M.by_creature[creature_name] then return M.by_creature[creature_name] end
    for _, group in ipairs(M.list) do
        if group.creature_name == nil and group.species ~= nil and group.species == species
            and (group.subtype == nil or group.subtype == subtype) then return group end
    end
    return nil, "unknown_improvement_group"
end

-- Input is ledger points[group.id][stat.id]; output is for native.sync_grid.
-- Existing native improvement counts must never be included in this input.
function M.expand(points_by_group)
    if type(points_by_group) ~= "table" then return nil, "invalid_group_points" end
    local out = {}
    for key, points in pairs(points_by_group) do
        local group = M.by_id[key]
        if not group or type(points) ~= "table" then return nil, "unknown_or_invalid_group:"..tostring(key) end
        for stat,count in pairs(points) do
            if group.native_by_stat[stat] then return nil, "native_attribute_in_extra_ledger:"..key.."/"..stat end
            if type(stat)~="string" or type(count)~="number" or count~=count or count<0
                or count>2147483647 or count%1~=0 then return nil,"invalid_group_point:"..key end
        end
        for _, name in ipairs(group.aliases) do
            local merged = out[name] or {}
            for stat, count in pairs(points) do
                local total=(merged[stat] or 0)+count
                if total>2147483647 then return nil,"merged_point_overflow:"..name.."/"..stat end
                merged[stat]=total
            end
            out[name] = merged
        end
    end
    return out
end
return M
