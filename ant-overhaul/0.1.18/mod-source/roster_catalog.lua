-- Static native roster inventory for the installed 1.2.1.1 game.
-- This module only returns data. Presence here is not a runtime test result.
-- Each entry owns a separate brood chamber; workers and queens are not replaced.
local M = { schema = 1, unlimited_population = 0, entries = {}, by_id = {} }

local function class(package)
    return package .. "." .. package:match("([^/]+)$") .. "_C"
end
local function add(id, title, flag, tile, packages, upgrade_field, variant_field, dlc, widget)
    local classes = {}
    for _, package in ipairs(packages) do
        classes[#classes + 1] = class(package:sub(1,6)=="/Game/" and package or "/Game/Blueprints/Creatures/" .. package)
    end
    local row = {id=id, title=title, flag=flag, fields={flag}, tile=tile, classes=classes,
        upgrade_field=upgrade_field, variant_field=variant_field, dlc=dlc, widget=widget}
    M.entries[#M.entries + 1] = row
    M.by_id[id] = row
end

-- One choice per chamber. Variant fields below are metadata, never permission
-- writes: the original mission's selected variant must remain unchanged.
add("BlackAnt", "黑蚁", "bBlackAnt", 3, {"BlackAnt/BlackAnt"}, "BlackAntMaxUpgradeLevel")
add("WoodAnt", "木蚁喷酸兵", "bWoodAnt", 4, {"WoodAnt/WoodAntASlow", "WoodAnt/WoodAntBSlow"}, "WoodAntMaxUpgradeLevel", "bWoodAntVarient")
add("WoodAntMelee", "木蚁近战兵", "bWoodAntMelee", 5, {"WoodAnt/WoodAntSoldier"})
add("LeafcutterMedia", "切叶蚁中型兵", "bLeafcutterMedia", 6, {"Leafcutter/LeafcutterMedia"})
add("LeafcutterMajor", "切叶蚁大型兵", "bLeafcutterMajor", 7, {"Leafcutter/LeafcutterMajorTaunt", "Leafcutter/LeafcutterMajorStun"}, "LeafcutterMaxUpgradeLevel", "bLeafcutterVarient")
add("LeafcutterSuperMajor", "切叶蚁超级兵", "bLeafcutterSuperMajor", 8, {"Leafcutter/LeafcutterSuperMajor"})
add("SlaveMaker", "掠夺蚁", "bSlaveMaker", 11, {"OtherColonyCreatures/SlaveMaker"})
add("TrapjawAnt", "大颚猛蚁", "bTrapjaw", 12, {"OtherColonyCreatures/TrapjawAnt"})
add("ArmyAnt", "军蚁", "bArmyAnt", 13, {"OtherColonyCreatures/ArmyAnt", "OtherColonyCreatures/ArmyAntMedia"})
add("ArmyAntMajor", "大型军蚁", "bArmyAntMajor", 14, {"OtherColonyCreatures/ArmyAntMajor"})
add("FireAnt", "火蚁", "bFireAnt", 15, {"FireAnt/FireAntPervasive", "FireAnt/FireAntVigorous"}, "FireAntMaxUpgradeLevel", "bFireAntVarient")
add("BigHeadedMajor", "大头蚁兵蚁", "bBigHeadedMajor", 16, {"BigHeadedAnt/BigHeadedMajor"})
add("BigHeadedSuperSoldier", "大头蚁超级兵", "bBigHeadedSuperSoldier", 17, {"BigHeadedAnt/BigHeadedSuperSoldier"})
add("LittleBlackAnt", "小黑蚁", "bLittleBlackAnt", 18, {"LittleBlackAnt/LittleBlackAnt"})
add("MatabeleMedic", "马塔贝勒医护蚁", "bMatabeleAnt", 19, {"MatabeleAnt/MatabeleMedicAnesthetist", "MatabeleAnt/MatabeleMedicFastResponder"}, "MatabeleAntMaxUpgradeLevel", "bMatabeleAntVariant")
add("MatabeleSoldier", "马塔贝勒兵蚁", "bMatabeleAntSoldier", 20, {"MatabeleAnt/MatabeleSoldier"})
add("TermiteSoldier", "白蚁小兵", "bTermiteSoldier", 21, {"Termites/TermiteSoldier"})
add("TermiteMajorSoldier", "白蚁大兵", "bTermiteMajorSoldier", 22, {"Termites/TermiteMajorSoldier"})
add("TermiteMajorWorker", "白蚁大工", "bTermiteMajorWorker", 23, {"Termites/TermiteMajorWorker"})
add("DriverAntWorker", "行军蚁工蚁", "bDriverAntWorker", 24, {"OtherColonyCreaturesAfrica/DriverAntWorker"})
add("DriverAntSoldier", "行军蚁兵蚁", "bDriverAntSoldier", 25, {"OtherColonyCreaturesAfrica/DriverAntSoldier"})
add("DriverAntLargeSoldier", "行军蚁大型兵", "bDriverAntLargeSoldier", 26, {"OtherColonyCreaturesAfrica/DriverAntLargeSoldier"})
add("BulletAnt", "子弹蚁", "bBulletAnt", 27, {"BulletAnt/BulletAnt"}, "BulletAntMaxUpgradeLevel")
add("StinkAnt", "臭蚁", "bStinkAnt", 28, {"OtherColonyCreaturesAfrica/StinkAnt"})

-- Exploding Ants DLC has four independent chambers. Its ordinary worker and
-- queens still belong to the original species selection, never extra chambers.
-- IDs match the existing native cultivation and skill groups.
add("ExplodingAnt", "自爆蚁兵蚁", "bExplodingAntSoldier", 29,
    {"/Game/DLC/ExplodingAnts_DLC/Blueprints/ExplodingAnts/ExplodingAntSoldier"},
    "ExplodingAntSoldierMaxUpgradeLevel", nil, "exploding", "ExplodingAntSoldier")
add("ExplodingAntMajorSoldier", "自爆蚁大型兵蚁", "bExplodingAntMajorSoldier", 30,
    {"/Game/DLC/ExplodingAnts_DLC/Blueprints/ExplodingAnts/ExplodingAntMajorSoldier"},
    nil, nil, "exploding", "ExplodingAntMajorSoldier")
add("ExplodingTermite", "自爆白蚁工蚁", "bExplodingTermiteWorker", 31,
    {"/Game/DLC/ExplodingAnts_DLC/Blueprints/ExplodingTermites/ExplodingTermiteWorker"},
    "ExplodingTermiteWorkerMaxUpgradeLevel", nil, "exploding", "ExplodingTermiteWorker")
add("ExplodingTermiteSoldier", "自爆白蚁兵蚁", "bExplodingTermiteSoldier", 32,
    {"/Game/DLC/ExplodingAnts_DLC/Blueprints/ExplodingTermites/ExplodingTermiteSoldier"},
    nil, nil, "exploding", "ExplodingTermiteSoldier")

-- Retain these IDs for old roster/attribute records and native mission content,
-- but no longer offer or grant them as supplemental player choices.
M.by_id.TermiteMajorWorker.supplemental_disabled = true
M.by_id.DriverAntWorker.supplemental_disabled = true
function M.is_selectable(id, dlc_available)
    local row=M.by_id[id]
    if not row or row.supplemental_disabled==true then return false end
    return row.dlc==nil or type(dlc_available)=="table" and dlc_available[row.dlc]==true
end

-- Verified against SpeciesEntryCustomColony.PurchaseAbility. These are ability
-- choices only: never numeric upgrades, chamber permissions, or unit variants.
-- Ability 1/3 form the left mutually exclusive pair; 2/4 form the right pair.
-- This mapping is not the order of fields in FColonyData (WoodAnt differs).
M.skills, M.skill_by_widget, M.skill_fields = {}, {}, {}
local function skills(id, widget, species, subtype, left, right, dlc)
    local row = {id=id, widget=widget, species=species, subtype=subtype,
        skill_pairs={left=left, right=right}, fields={}, dlc=dlc or false}
    for _, pair in ipairs({left, right}) do
        for _, field in ipairs(pair) do
            row.fields[#row.fields + 1] = field
            M.skill_fields[field] = true
        end
    end
    M.skills[#M.skills + 1] = row
    M.skill_by_widget[widget] = row
    if M.by_id[id] then M.by_id[id].skill_pairs = row.skill_pairs end
end

-- Queen/Worker records preserve the native ability UI, not their species.
skills("Queen", "Queen", 0, 1,
    {"bGeneTheifQueenStrongCarpiece", "bGeneTheifQueenResistantCarpiece"},
    {"bGeneTheifQueenSecondWind", "bGeneTheifQueenFierceMother"})
skills("Worker", "Worker", 0, 0,
    {"bGeneTheifWorkerAggressiveBrood", "bGeneTheifWorkerEfficientBrood"},
    {"bGeneTheifWorkerStrongMandibles", "bGeneTheifWorkerStrongCarpiece"})
skills("BlackAnt", "BlackAnt", 1, nil,
    {"bBlackAntDangerous", "bBlackAntMeatWall"},
    {"bBlackAntSelfPreservation", "bBlackAntSelfRepair"})
skills("WoodAnt", "WoodAnt", 2, nil,
    {"bWoodAntCorrosive", "bWoodAntHighPressure"},
    {"bWoodAntCrippling", "bWoodAntWeakening"})
skills("LeafcutterMajor", "LeafCutterMajor", 3, nil,
    {"bLeafcutterDurable", "bLeafcutterShockProof"},
    {"bLeafcutterSharp", "bLeafcutterResilient"})
skills("FireAnt", "FireAnt", 4, nil,
    {"bFireAntSurefooted", "bFireAntEvasive"},
    {"bFireAntLastStand", "bFireAntLastLaugh"})
skills("MatabeleMedic", "MatabeleAnt", 7, nil,
    {"bMatabeleAntSustain", "bMatabeleAntPreserve"},
    {"bMatabeleAntFieldMedic", "bMatabeleAntSurgeon"})
skills("BulletAnt", "BulletAnt", 11, nil,
    {"bBulletAntLeanPupation", "bBulletAntFastRecovery"},
    {"bBulletAntReinforcedCarapace", "bBulletAntSealedCarapace"})
-- Native DLC skills retain their original groups. Chamber selection above is
-- separately gated by the game's own DLC availability result.
skills("ExplodingAnt", "ExplodingAntSoldier", 13, nil,
    {"bExplodingAntSoldierControlledBlast", "bExplodingAntSoldierViolentBlast"},
    {"bExplodingAntSoldierChainReaction", "bExplodingAntSoldierPersistentSecretions"}, true)
skills("ExplodingTermite", "ExplodingTermiteWorker", 14, nil,
    {"bExplodingTermiteWorkerRapidMaturity", "bExplodingTermiteWorkerRapidGladFilling"},
    {"bExplodingTermiteWorkerExtremeToxins", "bExplodingTermiteWorkerExtremeConfusion"}, true)
skills("NarrowHeaded", "NarrowHeadedRanged", 15, nil,
    {"bNarrowHeadedRangedElusive", "bNarrowHeadedRangedKiting"},
    {"bNarrowHeadedRangedSplitStream", "bNarrowHeadedRangedFocusedStream"}, true)
M.skill_by_widget.ExplodingTermiteWorkerTopRow = M.skill_by_widget.ExplodingTermiteWorker

M.protected_colony_fields = {
    "QueenSpecies", "WorkerSpecies", "QueenSkin", "WorkerSkin", "ColonyResourceType",
    "bFoodStore", "bLeafDropOff", "bMulchDropOff", "bTermiteFungus", "bRefuse",
    "bWoodAntVarient", "bLeafcutterVarient", "bFireAntVarient", "bMatabeleAntVariant",
}
M.population = {
    setter = "/Script/EotU.EotUGameState:SetPopCapByID",
    getter = "/Script/EotU.EotUGameState:GetPopCapByID",
    predicate = "/Script/EotU.EotUGameState:IsPlayerAtPopCap",
    field = "PlayersData.PopCap",
    unlimited = 0,
}
M.build_menu = {
    class = "TugOfWarWidgets_C",
    setup = "/Game/UI/InGame/TugOfWarWidgets.TugOfWarWidgets_C:SetupBuildMenuButtons",
    buttons_field = "BuildMenuButtons",
}

return M
