-- Adapted nursing gesture on the existing carrier's own skeleton. This does
-- not spawn a medic, replace a mesh, convert ownership, heal, or drop patients.
-- Import is inert. Completion requires the actual non-looping playback end.
local M={schema=1}
-- BEGIN COOKED BUILD CATALOG
local sequences={
 ["/Game/Assets/3DModels/Ants/Units/AfricanStinkAnt/AfricanStinkAnt_Anim_Build.AfricanStinkAnt_Anim_Build"]={skeleton="/Game/Assets/3DModels/Ants/Units/AfricanStinkAnt/AfricanStinkAnt_Skeleton.AfricanStinkAnt_Skeleton",length=4.333333492279053},
 ["/Game/Assets/3DModels/Ants/Units/ArmyAnt/EcitonBurchelliMajor_Anim_Build.EcitonBurchelliMajor_Anim_Build"]={skeleton="/Game/Assets/3DModels/Ants/Units/ArmyAnt/EcitonBurchelliMajor_Skeleton.EcitonBurchelliMajor_Skeleton",length=4.366666793823242},
 ["/Game/Assets/3DModels/Ants/Units/ArmyAnt/EcitonBurchelliMedia_Anim_Build.EcitonBurchelliMedia_Anim_Build"]={skeleton="/Game/Assets/3DModels/Ants/Units/ArmyAnt/EcitonBurchelliMajor_Skeleton.EcitonBurchelliMajor_Skeleton",length=4.366666793823242},
 ["/Game/Assets/3DModels/Ants/Units/ArmyAnt/EcitonBurchelliMinor_Anim_Build.EcitonBurchelliMinor_Anim_Build"]={skeleton="/Game/Assets/3DModels/Ants/Units/ArmyAnt/EcitonBurchelliMajor_Skeleton.EcitonBurchelliMajor_Skeleton",length=4.366666793823242},
 ["/Game/Assets/3DModels/Ants/Units/BigHeadedAnt/BHASoldier_Anim_Build.BHASoldier_Anim_Build"]={skeleton="/Game/Assets/3DModels/Ants/Units/BigHeadedAnt/BHASuperSoldier_Skeleton.BHASuperSoldier_Skeleton",length=4.300000190734863},
 ["/Game/Assets/3DModels/Ants/Units/BigHeadedAnt/BHASuperSoldier_Anim_Build.BHASuperSoldier_Anim_Build"]={skeleton="/Game/Assets/3DModels/Ants/Units/BigHeadedAnt/BHASuperSoldier_Skeleton.BHASuperSoldier_Skeleton",length=4.300000190734863},
 ["/Game/Assets/3DModels/Ants/Units/BigHeadedAnt/BHAWorker_Anim_Build.BHAWorker_Anim_Build"]={skeleton="/Game/Assets/3DModels/Ants/Units/BigHeadedAnt/BHASuperSoldier_Skeleton.BHASuperSoldier_Skeleton",length=4.300000190734863},
 ["/Game/Assets/3DModels/Ants/Units/BlackAnt/FormicaFuscaV2_Anim_Build.FormicaFuscaV2_Anim_Build"]={skeleton="/Game/Assets/3DModels/Ants/Units/BlackAnt/FormicaFuscaV2_Skeleton.FormicaFuscaV2_Skeleton",length=4.633333206176758},
 ["/Game/Assets/3DModels/Ants/Units/BlackAnt/FormicaFusca_Anim_Build.FormicaFusca_Anim_Build"]={skeleton="/Game/Assets/3DModels/Ants/Units/BlackAnt/FormicaFusca_Skeleton.FormicaFusca_Skeleton",length=3.3333332538604736},
 ["/Game/Assets/3DModels/Ants/Units/BulletAnt/BulletAnt_Anim_Build.BulletAnt_Anim_Build"]={skeleton="/Game/Assets/3DModels/Ants/Units/BulletAnt/BulletAnt_Skeleton.BulletAnt_Skeleton",length=4.333333492279053},
 ["/Game/Assets/3DModels/Ants/Units/DriverAnt/DriverAntMediumMajor_Anim_Build.DriverAntMediumMajor_Anim_Build"]={skeleton="/Game/Assets/3DModels/Ants/Units/DriverAnt/DriverAntSoldier_Skeleton.DriverAntSoldier_Skeleton",length=4.333333492279053},
 ["/Game/Assets/3DModels/Ants/Units/DriverAnt/DriverAntSoldier_Anim_Build.DriverAntSoldier_Anim_Build"]={skeleton="/Game/Assets/3DModels/Ants/Units/DriverAnt/DriverAntSoldier_Skeleton.DriverAntSoldier_Skeleton",length=4.333333492279053},
 ["/Game/Assets/3DModels/Ants/Units/DriverAnt/DriverAntWorker_Anim_Build.DriverAntWorker_Anim_Build"]={skeleton="/Game/Assets/3DModels/Ants/Units/DriverAnt/DriverAntSoldier_Skeleton.DriverAntSoldier_Skeleton",length=4.333333492279053},
 ["/Game/Assets/3DModels/Ants/Units/FireAnt/SolenopsisInvictaMajor_Anim_Build.SolenopsisInvictaMajor_Anim_Build"]={skeleton="/Game/Assets/3DModels/Ants/Units/FireAnt/SolenopsisInvictaMinor_Skeleton.SolenopsisInvictaMinor_Skeleton",length=4.300000190734863},
 ["/Game/Assets/3DModels/Ants/Units/FireAnt/SolenopsisInvictaMinor_Anim_Build.SolenopsisInvictaMinor_Anim_Build"]={skeleton="/Game/Assets/3DModels/Ants/Units/FireAnt/SolenopsisInvictaMinor_Skeleton.SolenopsisInvictaMinor_Skeleton",length=4.300000190734863},
 ["/Game/Assets/3DModels/Ants/Units/FormicaEreptor2/FormicaEreptor_Anim_Build.FormicaEreptor_Anim_Build"]={skeleton="/Game/Assets/3DModels/Ants/Units/FormicaEreptor2/FormicaEreptor_Skeleton.FormicaEreptor_Skeleton",length=4.633333206176758},
 ["/Game/Assets/3DModels/Ants/Units/FormicaEreptor3/Formica_Ereptor_Worker_Anim_Build.Formica_Ereptor_Worker_Anim_Build"]={skeleton="/Game/Assets/3DModels/Ants/Units/FormicaEreptor3/Formica_Ereptor_Worker_Skeleton.Formica_Ereptor_Worker_Skeleton",length=3.3333332538604736},
 ["/Game/Assets/3DModels/Ants/Units/LeafCutter2/LeafCutterMajor_Anim_Build.LeafCutterMajor_Anim_Build"]={skeleton="/Game/Assets/3DModels/Ants/Units/LeafCutter2/LeafCutterMajor_Skeleton.LeafCutterMajor_Skeleton",length=4.366666793823242},
 ["/Game/Assets/3DModels/Ants/Units/LeafCutter2/LeafCutterMedia_LeafCutter1_Anim_Build.LeafCutterMedia_LeafCutter1_Anim_Build"]={skeleton="/Game/Assets/3DModels/Ants/Units/LeafCutter2/LeafCutterMajor_Skeleton.LeafCutterMajor_Skeleton",length=4.366666793823242},
 ["/Game/Assets/3DModels/Ants/Units/LeafCutter2/LeafCutterMinima_Anim_Build.LeafCutterMinima_Anim_Build"]={skeleton="/Game/Assets/3DModels/Ants/Units/LeafCutter2/LeafCutterMajor_Skeleton.LeafCutterMajor_Skeleton",length=4.366666793823242},
 ["/Game/Assets/3DModels/Ants/Units/LeafCutter2/LeafCutterMinor_LeafCutter2_Anim_Build.LeafCutterMinor_LeafCutter2_Anim_Build"]={skeleton="/Game/Assets/3DModels/Ants/Units/LeafCutter2/LeafCutterMajor_Skeleton.LeafCutterMajor_Skeleton",length=4.366666793823242},
 ["/Game/Assets/3DModels/Ants/Units/LeafCutter3/Animations/AttaCephalotes_Unit_Anim_Build.AttaCephalotes_Unit_Anim_Build"]={skeleton="/Game/Assets/3DModels/Ants/Units/LeafCutter3/Animations/AttaCephalotes_Unit_Skeleton.AttaCephalotes_Unit_Skeleton",length=4.633333206176758},
 ["/Game/Assets/3DModels/Ants/Units/LittleBlackAnt/LittleBlackAntSoldier_Anim_Build.LittleBlackAntSoldier_Anim_Build"]={skeleton="/Game/Assets/3DModels/Ants/Units/FireAnt/SolenopsisInvictaMinor_Skeleton.SolenopsisInvictaMinor_Skeleton",length=4.300000190734863},
 ["/Game/Assets/3DModels/Ants/Units/LittleBlackAnt/LittleBlackAntWorker_Anim_Build.LittleBlackAntWorker_Anim_Build"]={skeleton="/Game/Assets/3DModels/Ants/Units/FireAnt/SolenopsisInvictaMinor_Skeleton.SolenopsisInvictaMinor_Skeleton",length=4.300000190734863},
 ["/Game/Assets/3DModels/Ants/Units/MatabeleAnt/MatabeleMedic_Anim_Build.MatabeleMedic_Anim_Build"]={skeleton="/Game/Assets/3DModels/Ants/Units/MatabeleAnt/MatabeleSoldier_Skeleton.MatabeleSoldier_Skeleton",length=4.333333492279053},
 ["/Game/Assets/3DModels/Ants/Units/MatabeleAnt/MatabeleSoldier_Anim_Build.MatabeleSoldier_Anim_Build"]={skeleton="/Game/Assets/3DModels/Ants/Units/MatabeleAnt/MatabeleSoldier_Skeleton.MatabeleSoldier_Skeleton",length=4.333333492279053},
 ["/Game/Assets/3DModels/Ants/Units/MatabeleAnt/MatabeleWorker_Anim_Build.MatabeleWorker_Anim_Build"]={skeleton="/Game/Assets/3DModels/Ants/Units/MatabeleAnt/MatabeleSoldier_Skeleton.MatabeleSoldier_Skeleton",length=4.333333492279053},
 ["/Game/Assets/3DModels/Ants/Units/SlaveMaker/VU/FormicaSanguinea_Worker_Anim_Build.FormicaSanguinea_Worker_Anim_Build"]={skeleton="/Game/Assets/3DModels/Ants/Units/SlaveMaker/VU/FormicaSanguinea_Worker_Skeleton.FormicaSanguinea_Worker_Skeleton",length=3.299999952316284},
 ["/Game/Assets/3DModels/Ants/Units/TrapJaw/TrapJaw_Anim_Build.TrapJaw_Anim_Build"]={skeleton="/Game/Assets/3DModels/Ants/Units/TrapJaw/TrapJaw_Skeleton.TrapJaw_Skeleton",length=4.366666793823242},
 ["/Game/Assets/3DModels/Ants/Units/TrapJaw/VU/Trapjaw_Ant_Anim_Build.Trapjaw_Ant_Anim_Build"]={skeleton="/Game/Assets/3DModels/Ants/Units/TrapJaw/VU/Trapjaw_Ant_Skeleton.Trapjaw_Ant_Skeleton",length=4.366666793823242},
 ["/Game/Assets/3DModels/Ants/Units/WoodAnt/WoodAntWorker_Anim_Build.WoodAntWorker_Anim_Build"]={skeleton="/Game/Assets/3DModels/Ants/Units/WoodAnt/WoodAntWorker_Skeleton.WoodAntWorker_Skeleton",length=4.366666793823242},
 ["/Game/Assets/3DModels/Termites/TermiteKing_Anim_Build.TermiteKing_Anim_Build"]={skeleton="/Game/Assets/3DModels/Termites/TermiteWorker_Skeleton.TermiteWorker_Skeleton",length=4.333333492279053},
 ["/Game/Assets/3DModels/Termites/TermiteSoldier_Anim_Build.TermiteSoldier_Anim_Build"]={skeleton="/Game/Assets/3DModels/Termites/TermiteWorker_Skeleton.TermiteWorker_Skeleton",length=4.333333492279053},
 ["/Game/Assets/3DModels/Termites/TermiteWorker_Anim_Build.TermiteWorker_Anim_Build"]={skeleton="/Game/Assets/3DModels/Termites/TermiteWorker_Skeleton.TermiteWorker_Skeleton",length=4.333333492279053},
 ["/Game/DLC/ExplodingAnts_DLC/Meshes/MalaysianExplodingAnts/Units/MalaysianExplodingAntMajorWorker_Anim_Build.MalaysianExplodingAntMajorWorker_Anim_Build"]={skeleton="/Game/DLC/ExplodingAnts_DLC/Meshes/MalaysianExplodingAnts/Units/MalaysianExplodingAntMajorWorker_Skeleton.MalaysianExplodingAntMajorWorker_Skeleton",length=4.300000190734863},
 ["/Game/DLC/ExplodingAnts_DLC/Meshes/MalaysianExplodingAnts/Units/MalaysianExplodingAntMinorWorker_Anim_Build.MalaysianExplodingAntMinorWorker_Anim_Build"]={skeleton="/Game/DLC/ExplodingAnts_DLC/Meshes/MalaysianExplodingAnts/Units/MalaysianExplodingAntMajorWorker_Skeleton.MalaysianExplodingAntMajorWorker_Skeleton",length=4.300000190734863},
 ["/Game/DLC/ExplodingAnts_DLC/Meshes/MalaysianExplodingAnts/Units/MalaysianExplodingAntSoldier_Anim_Build.MalaysianExplodingAntSoldier_Anim_Build"]={skeleton="/Game/DLC/ExplodingAnts_DLC/Meshes/MalaysianExplodingAnts/Units/MalaysianExplodingAntMajorWorker_Skeleton.MalaysianExplodingAntMajorWorker_Skeleton",length=4.300000190734863},
 ["/Game/DLC/ExplodingAnts_DLC/Meshes/NeocapritermesTermites/Units/NeocapritermesTaracua_Worker_Anim_Build.NeocapritermesTaracua_Worker_Anim_Build"]={skeleton="/Game/DLC/ExplodingAnts_DLC/Meshes/NeocapritermesTermites/Units/NeocapritermesTaracua_Worker_Skeleton.NeocapritermesTaracua_Worker_Skeleton",length=2.1666667461395264},
}
local classes={
 ["/Game/Assets/3DModels/Ants/Units/ArmyAnt/EcitonBurchelliMajor_Skeleton_AnimBlueprint.EcitonBurchelliMajor_Skeleton_AnimBlueprint_C"]="/Game/Assets/3DModels/Ants/Units/ArmyAnt/EcitonBurchelliMajor_Anim_Build.EcitonBurchelliMajor_Anim_Build",
 ["/Game/Assets/3DModels/Ants/Units/ArmyAnt/EcitonBurchelliMedia_AnimBlueprint.EcitonBurchelliMedia_AnimBlueprint_C"]="/Game/Assets/3DModels/Ants/Units/ArmyAnt/EcitonBurchelliMedia_Anim_Build.EcitonBurchelliMedia_Anim_Build",
 ["/Game/Assets/3DModels/Ants/Units/ArmyAnt/EcitonBurchelliMinor_AnimBlueprint.EcitonBurchelliMinor_AnimBlueprint_C"]="/Game/Assets/3DModels/Ants/Units/ArmyAnt/EcitonBurchelliMinor_Anim_Build.EcitonBurchelliMinor_Anim_Build",
 ["/Game/Assets/3DModels/Ants/Units/BigHeadedAnt/BHASoldier_AnimBP.BHASoldier_AnimBP_C"]="/Game/Assets/3DModels/Ants/Units/BigHeadedAnt/BHASoldier_Anim_Build.BHASoldier_Anim_Build",
 ["/Game/Assets/3DModels/Ants/Units/BigHeadedAnt/BHASuperSoldier_AnimBP.BHASuperSoldier_AnimBP_C"]="/Game/Assets/3DModels/Ants/Units/BigHeadedAnt/BHASuperSoldier_Anim_Build.BHASuperSoldier_Anim_Build",
 ["/Game/Assets/3DModels/Ants/Units/BigHeadedAnt/BHAWorker_AnimBP.BHAWorker_AnimBP_C"]="/Game/Assets/3DModels/Ants/Units/BigHeadedAnt/BHAWorker_Anim_Build.BHAWorker_Anim_Build",
 ["/Game/Assets/3DModels/Ants/Units/BlackAnt/FormicaFuscaV2_Skeleton_AnimBlueprint.FormicaFuscaV2_Skeleton_AnimBlueprint_C"]="/Game/Assets/3DModels/Ants/Units/BlackAnt/FormicaFuscaV2_Anim_Build.FormicaFuscaV2_Anim_Build",
 ["/Game/Assets/3DModels/Ants/Units/BlackAnt/FormicaFusca_AnimBlueprint.FormicaFusca_AnimBlueprint_C"]="/Game/Assets/3DModels/Ants/Units/BlackAnt/FormicaFusca_Anim_Build.FormicaFusca_Anim_Build",
 ["/Game/Assets/3DModels/Ants/Units/BlackAnt/FormicaFusca_Worker_AnimBlueprint.FormicaFusca_Worker_AnimBlueprint_C"]="/Game/Assets/3DModels/Ants/Units/BlackAnt/FormicaFusca_Anim_Build.FormicaFusca_Anim_Build",
 ["/Game/Assets/3DModels/Ants/Units/BulletAnt/BulletAnt_Skeleton_AnimBlueprint.BulletAnt_Skeleton_AnimBlueprint_C"]="/Game/Assets/3DModels/Ants/Units/BulletAnt/BulletAnt_Anim_Build.BulletAnt_Anim_Build",
 ["/Game/Assets/3DModels/Ants/Units/DriverAnt/DriverAntMediumSoldier_Skeleton_AnimBP.DriverAntMediumSoldier_Skeleton_AnimBP_C"]="/Game/Assets/3DModels/Ants/Units/DriverAnt/DriverAntMediumMajor_Anim_Build.DriverAntMediumMajor_Anim_Build",
 ["/Game/Assets/3DModels/Ants/Units/DriverAnt/DriverAntSoldier_Skeleton_AnimBP.DriverAntSoldier_Skeleton_AnimBP_C"]="/Game/Assets/3DModels/Ants/Units/DriverAnt/DriverAntSoldier_Anim_Build.DriverAntSoldier_Anim_Build",
 ["/Game/Assets/3DModels/Ants/Units/DriverAnt/DriverAntWorker_Skeleton_AnimBP.DriverAntWorker_Skeleton_AnimBP_C"]="/Game/Assets/3DModels/Ants/Units/DriverAnt/DriverAntWorker_Anim_Build.DriverAntWorker_Anim_Build",
 ["/Game/Assets/3DModels/Ants/Units/FireAnt/SolenopsisInvictaMajor_AnimBP.SolenopsisInvictaMajor_AnimBP_C"]="/Game/Assets/3DModels/Ants/Units/FireAnt/SolenopsisInvictaMajor_Anim_Build.SolenopsisInvictaMajor_Anim_Build",
 ["/Game/Assets/3DModels/Ants/Units/FireAnt/SolenopsisInvictaMinor_AnimBP.SolenopsisInvictaMinor_AnimBP_C"]="/Game/Assets/3DModels/Ants/Units/FireAnt/SolenopsisInvictaMinor_Anim_Build.SolenopsisInvictaMinor_Anim_Build",
 ["/Game/Assets/3DModels/Ants/Units/FormicaEreptor2/FormicaEreptor_Skeleton_AnimBlueprint.FormicaEreptor_Skeleton_AnimBlueprint_C"]="/Game/Assets/3DModels/Ants/Units/FormicaEreptor2/FormicaEreptor_Anim_Build.FormicaEreptor_Anim_Build",
 ["/Game/Assets/3DModels/Ants/Units/FormicaEreptor3/Formica_Ereptor_Larry_AnimBP.Formica_Ereptor_Larry_AnimBP_C"]="/Game/Assets/3DModels/Ants/Units/FormicaEreptor3/Formica_Ereptor_Worker_Anim_Build.Formica_Ereptor_Worker_Anim_Build",
 ["/Game/Assets/3DModels/Ants/Units/FormicaEreptor3/Formica_Ereptor_Worker_AnimBP.Formica_Ereptor_Worker_AnimBP_C"]="/Game/Assets/3DModels/Ants/Units/FormicaEreptor3/Formica_Ereptor_Worker_Anim_Build.Formica_Ereptor_Worker_Anim_Build",
 ["/Game/Assets/3DModels/Ants/Units/LeafCutter2/LeafCutterAnimBP_Major.LeafCutterAnimBP_Major_C"]="/Game/Assets/3DModels/Ants/Units/LeafCutter2/LeafCutterMajor_Anim_Build.LeafCutterMajor_Anim_Build",
 ["/Game/Assets/3DModels/Ants/Units/LeafCutter2/LeafCutterAnimBP_Media.LeafCutterAnimBP_Media_C"]="/Game/Assets/3DModels/Ants/Units/LeafCutter2/LeafCutterMedia_LeafCutter1_Anim_Build.LeafCutterMedia_LeafCutter1_Anim_Build",
 ["/Game/Assets/3DModels/Ants/Units/LeafCutter2/LeafCutterAnimBP_Minima.LeafCutterAnimBP_Minima_C"]="/Game/Assets/3DModels/Ants/Units/LeafCutter2/LeafCutterMinima_Anim_Build.LeafCutterMinima_Anim_Build",
 ["/Game/Assets/3DModels/Ants/Units/LeafCutter2/LeafCutterAnimBP_Minor.LeafCutterAnimBP_Minor_C"]="/Game/Assets/3DModels/Ants/Units/LeafCutter2/LeafCutterMinor_LeafCutter2_Anim_Build.LeafCutterMinor_LeafCutter2_Anim_Build",
 ["/Game/Assets/3DModels/Ants/Units/LeafCutter3/Animations/AttaCephalotes_Unit_AnimBP.AttaCephalotes_Unit_AnimBP_C"]="/Game/Assets/3DModels/Ants/Units/LeafCutter3/Animations/AttaCephalotes_Unit_Anim_Build.AttaCephalotes_Unit_Anim_Build",
 ["/Game/Assets/3DModels/Ants/Units/LittleBlackAnt/LittleBlackAnt_Soldier_AnimBP.LittleBlackAnt_Soldier_AnimBP_C"]="/Game/Assets/3DModels/Ants/Units/LittleBlackAnt/LittleBlackAntSoldier_Anim_Build.LittleBlackAntSoldier_Anim_Build",
 ["/Game/Assets/3DModels/Ants/Units/LittleBlackAnt/LittleBlackAnt_Worker_AnimBP.LittleBlackAnt_Worker_AnimBP_C"]="/Game/Assets/3DModels/Ants/Units/LittleBlackAnt/LittleBlackAntWorker_Anim_Build.LittleBlackAntWorker_Anim_Build",
 ["/Game/Assets/3DModels/Ants/Units/MatabeleAnt/MatabeleMedic_AniMBP.MatabeleMedic_AniMBP_C"]="/Game/Assets/3DModels/Ants/Units/MatabeleAnt/MatabeleMedic_Anim_Build.MatabeleMedic_Anim_Build",
 ["/Game/Assets/3DModels/Ants/Units/MatabeleAnt/MatabeleSoldier_AniMBP.MatabeleSoldier_AniMBP_C"]="/Game/Assets/3DModels/Ants/Units/MatabeleAnt/MatabeleSoldier_Anim_Build.MatabeleSoldier_Anim_Build",
 ["/Game/Assets/3DModels/Ants/Units/MatabeleAnt/MatabeleWorker_AniMBP.MatabeleWorker_AniMBP_C"]="/Game/Assets/3DModels/Ants/Units/MatabeleAnt/MatabeleWorker_Anim_Build.MatabeleWorker_Anim_Build",
 ["/Game/Assets/3DModels/Ants/Units/SlaveMaker/VU/FormicaSanguinea_SoldierSlaver_AnimBP.FormicaSanguinea_SoldierSlaver_AnimBP_C"]="/Game/Assets/3DModels/Ants/Units/SlaveMaker/VU/FormicaSanguinea_Worker_Anim_Build.FormicaSanguinea_Worker_Anim_Build",
 ["/Game/Assets/3DModels/Ants/Units/SlaveMaker/VU/FormicaSanguinea_Soldier_AnimBP.FormicaSanguinea_Soldier_AnimBP_C"]="/Game/Assets/3DModels/Ants/Units/SlaveMaker/VU/FormicaSanguinea_Worker_Anim_Build.FormicaSanguinea_Worker_Anim_Build",
 ["/Game/Assets/3DModels/Ants/Units/SlaveMaker/VU/FormicaSanguinea_Worker_AnimBP.FormicaSanguinea_Worker_AnimBP_C"]="/Game/Assets/3DModels/Ants/Units/SlaveMaker/VU/FormicaSanguinea_Worker_Anim_Build.FormicaSanguinea_Worker_Anim_Build",
 ["/Game/Assets/3DModels/Ants/Units/TrapJaw/TrapJaw_Skeleton_AnimBlueprint.TrapJaw_Skeleton_AnimBlueprint_C"]="/Game/Assets/3DModels/Ants/Units/TrapJaw/TrapJaw_Anim_Build.TrapJaw_Anim_Build",
 ["/Game/Assets/3DModels/Ants/Units/TrapJaw/VU/Trapjaw_Ant_AnimBlueprint.Trapjaw_Ant_AnimBlueprint_C"]="/Game/Assets/3DModels/Ants/Units/TrapJaw/VU/Trapjaw_Ant_Anim_Build.Trapjaw_Ant_Anim_Build",
 ["/Game/Assets/3DModels/Ants/Units/WoodAnt/WoodAntWorkerAnimBP.WoodAntWorkerAnimBP_C"]="/Game/Assets/3DModels/Ants/Units/WoodAnt/WoodAntWorker_Anim_Build.WoodAntWorker_Anim_Build",
 ["/Game/Assets/3DModels/Termites/TermiteKing_AnimBP.TermiteKing_AnimBP_C"]="/Game/Assets/3DModels/Termites/TermiteKing_Anim_Build.TermiteKing_Anim_Build",
 ["/Game/Assets/3DModels/Termites/TermiteMajorSoldier_AnimBP.TermiteMajorSoldier_AnimBP_C"]="/Game/Assets/3DModels/Termites/TermiteSoldier_Anim_Build.TermiteSoldier_Anim_Build",
 ["/Game/Assets/3DModels/Termites/TermiteSoldier_AnimBP.TermiteSoldier_AnimBP_C"]="/Game/Assets/3DModels/Termites/TermiteSoldier_Anim_Build.TermiteSoldier_Anim_Build",
 ["/Game/Assets/3DModels/Termites/TermiteSwarmQueen_AnimBP.TermiteSwarmQueen_AnimBP_C"]="/Game/Assets/3DModels/Termites/TermiteKing_Anim_Build.TermiteKing_Anim_Build",
 ["/Game/Assets/3DModels/Termites/TermiteWorker_AnimBP.TermiteWorker_AnimBP_C"]="/Game/Assets/3DModels/Termites/TermiteWorker_Anim_Build.TermiteWorker_Anim_Build",
 ["/Game/DLC/ExplodingAnts_DLC/Meshes/MalaysianExplodingAnts/Units/MalaysianExplodingAntMajorWorker_Skeleton_AnimBlueprint.MalaysianExplodingAntMajorWorker_Skeleton_AnimBlueprint_C"]="/Game/DLC/ExplodingAnts_DLC/Meshes/MalaysianExplodingAnts/Units/MalaysianExplodingAntMajorWorker_Anim_Build.MalaysianExplodingAntMajorWorker_Anim_Build",
 ["/Game/DLC/ExplodingAnts_DLC/Meshes/MalaysianExplodingAnts/Units/MalaysianExplodingAntMinorWorker_Skeleton_AnimBlueprint.MalaysianExplodingAntMinorWorker_Skeleton_AnimBlueprint_C"]="/Game/DLC/ExplodingAnts_DLC/Meshes/MalaysianExplodingAnts/Units/MalaysianExplodingAntMinorWorker_Anim_Build.MalaysianExplodingAntMinorWorker_Anim_Build",
 ["/Game/DLC/ExplodingAnts_DLC/Meshes/MalaysianExplodingAnts/Units/MalaysianExplodingAntSoldier_Skeleton_AnimBlueprint.MalaysianExplodingAntSoldier_Skeleton_AnimBlueprint_C"]="/Game/DLC/ExplodingAnts_DLC/Meshes/MalaysianExplodingAnts/Units/MalaysianExplodingAntSoldier_Anim_Build.MalaysianExplodingAntSoldier_Anim_Build",
 ["/Game/DLC/ExplodingAnts_DLC/Meshes/NeocapritermesTermites/Units/NeocapritermesTaracua_Worker_Skeleton_AnimBlueprint.NeocapritermesTaracua_Worker_Skeleton_AnimBlueprint_C"]="/Game/DLC/ExplodingAnts_DLC/Meshes/NeocapritermesTermites/Units/NeocapritermesTaracua_Worker_Anim_Build.NeocapritermesTaracua_Worker_Anim_Build",
}
-- END COOKED BUILD CATALOG

local function safe(f)local ok,v=pcall(f);if ok then return v end end
local function unbox(v)local x=v~=nil and safe(function()return v:get()end);return x~=nil and x or v end
local function num(v)local n=tonumber(unbox(v));if n and n==n and math.abs(n)<math.huge then return n end end

function M.install(options)
 assert(type(options)=='table'and type(options.native)=='table','conversion_animation_dependencies')
 assert(type(options.get_context)=='function','conversion_animation_context')
 local native=options.native
 local active,assets,reported={},{},{}
 local stopped=false
 local api={}
 local function valid(v)return v~=nil and safe(function()return native.valid_object(v)end)==true end
 local function id(v)return valid(v)and safe(function()return tostring(v:GetAddress())end)end
 local function same(a,b)local k=id(a);return k~=nil and k==id(b)end
 local function path(v)
  if not valid(v)then return nil end
  local n=safe(function()return v:GetFullName()end)
  return type(n)=='string'and(n:match(' (%/.+)$')or n:match('^(%/.+)$'))or nil
 end
 local function failure(e)
  e=tostring(e)
  if not reported[e]then reported[e]=true;if options.log then pcall(options.log,'[SlaveConversionAnimation] '..e)end end
  return nil,e
 end
 local function alive(v)return valid(v)and(num(v.Health)or 0)>0 end
 local function context()
  local c=options.get_context();local gs=type(c)=='table'and(c.gs or c.game_state)
  return valid(gs)and gs or nil
 end
 local function resolve(c)
  assert(valid(c),'conversion_carrier_invalid')
  local mesh=c.Mesh;assert(valid(mesh),'conversion_carrier_mesh_missing')
  local skmesh=mesh.SkeletalMesh;assert(valid(skmesh),'conversion_skeletal_asset_missing')
  local skeleton=path(skmesh.Skeleton);assert(skeleton,'conversion_skeleton_missing')
  local cls=mesh:GetAnimClass();local chosen=classes[path(cls)]
  if not chosen then
   -- Only an unambiguous original Build on the exact same skeleton is allowed.
   -- This supports e.g. StinkAnt's cooked Build despite its graph omitting it.
   for p,s in pairs(sequences)do if s.skeleton==skeleton then
    assert(chosen==nil,'conversion_build_ambiguous');chosen=p
   end end
  end
  local spec=chosen and sequences[chosen]
  assert(spec and spec.skeleton==skeleton,'conversion_build_unsupported:'..tostring(skeleton))
  return mesh,cls,chosen,spec
 end
 local function load(p)
  local a=assets[p]
  if not valid(a)then
   a=options.load_asset and options.load_asset(p)or StaticFindObject(p)
   if not valid(a)and not options.load_asset then a=LoadAsset(p)end
   assert(valid(a),'conversion_build_asset_missing:'..p);assets[p]=a
  end
  return a
 end
 local function restore(t)
  if t.restored then return true end
  local errors={}
  local function attempt(f)local ok,e=pcall(f);if not ok then errors[#errors+1]=tostring(e)end end
  if valid(t.mesh)then
   -- Restore the original Blueprint before resuming the reserved carrier AI.
   attempt(function()t.mesh:Stop()end)
   attempt(function()t.mesh:SetAnimClass(t.before.anim_class);t.mesh:SetAnimationMode(t.before.mode)end)
   for k,v in pairs(t.before.mesh)do attempt(function()t.mesh[k]=v end)end
  end
  if valid(t.carrier)then
   for k,v in pairs(t.before.creature)do attempt(function()t.carrier[k]=v end)end
   attempt(function()t.carrier:SetCurrentAnimation(t.before.current_animation)end)
  end
  if #errors>0 then return failure('conversion_animation_restore_failed:'..table.concat(errors,';'))end
  t.restored=true;active[t.key]=nil;return true
 end
 function api.supports(c)
  local ok,mesh,cls,p,spec=pcall(resolve,c)
  if not ok then return false,tostring(mesh)end
  return true,{sequence=p,skeleton=spec.skeleton,length=spec.length}
 end
 function api.begin(carrier,patient)
  local t
  local ok,result=pcall(function()
   assert(not stopped,'conversion_animation_stopped')
   local gs=context();assert(gs,'conversion_world_missing')
   assert(alive(carrier)and alive(patient),'conversion_actor_not_alive')
   assert(native.world_id(carrier)==native.world_id(gs)and native.world_id(patient)==native.world_id(gs),'conversion_world_mismatch')
   assert(native.is_owned(carrier,gs)==true,'conversion_carrier_not_owned')
   assert(num(carrier.ColonyLocation)==num(patient.ColonyLocation),'conversion_layer_mismatch')
   assert(same(carrier:GetHeldActor(),patient),'conversion_patient_not_held')
   local key=id(carrier);assert(key and not active[key],'conversion_carrier_busy')
   local mesh,cls,p,spec=resolve(carrier)
   local mode=num(mesh:GetAnimationMode());assert(mode==0 and valid(cls),'conversion_carrier_animation_busy')
   local a=load(p);assert(path(a.Skeleton)==spec.skeleton,'conversion_loaded_skeleton_mismatch')
   local length=num(a.SequenceLength);assert(length and length>0 and math.abs(length-spec.length)<0.001,'conversion_sequence_length_changed')
   local ctl=carrier:GetController();assert(valid(ctl),'conversion_controller_missing')
   t={key=key,carrier=carrier,patient=patient,mesh=mesh,asset=a,sequence=p,length=length,
      world=native.world_id(gs),state='running',last_position=0,advanced=false,
      last_progress_time=num(safe(function()return gs:GetLevelTime()end)),
      before={mode=mode,anim_class=cls,current_animation=num(carrier.CurrentAnimation)or 11,
       creature={AbilityInUse=carrier.AbilityInUse,Immobile=carrier.Immobile,DontRotate=carrier.DontRotate},
       mesh={bPauseAnims=mesh.bPauseAnims,VisibilityBasedAnimTickOption=mesh.VisibilityBasedAnimTickOption,
        bEnableUpdateRateOptimizations=mesh.bEnableUpdateRateOptimizations,GlobalAnimRateScale=mesh.GlobalAnimRateScale}}}
   active[key]=t
   ctl:StopMovement()
   carrier.Immobile=true;carrier.DontRotate=true;carrier.AbilityInUse=true
   carrier:UnsetAnimationOptimised();carrier:SetCurrentAnimation(1)
   mesh.bPauseAnims=false;mesh.VisibilityBasedAnimTickOption=0
   mesh.bEnableUpdateRateOptimizations=false;mesh.GlobalAnimRateScale=1
   mesh:PlayAnimation(a,false);mesh:SetPlayRate(1);mesh:SetPosition(0,false)
   local instance=mesh:GetAnimInstance()
   assert(valid(instance)and same(instance.CurrentAsset,a),'conversion_playback_asset_rejected')
   assert(num(mesh:GetAnimationMode())==1 and mesh:IsPlaying()==true,'conversion_playback_not_started')
   t.instance=instance
   return t
  end)
  if not ok then
   if t then local restored,why=restore(t);if not restored then return failure(tostring(result)..'; '..tostring(why))end end
   return failure(result)
  end
  return result
 end
 function api.poll(t)
  if type(t)~='table'or(t.restored and t.state~='completed')then return failure('conversion_ticket_inactive')end
  if t.state=='completed'then return 'completed'end
  local ok,result=pcall(function()
   assert(not stopped and active[t.key]==t,'conversion_ticket_not_registered')
   local gs=context();assert(gs and native.world_id(gs)==t.world,'conversion_world_changed')
   assert(alive(t.carrier)and alive(t.patient),'conversion_actor_lost')
   assert(native.is_owned(t.carrier,gs)==true,'conversion_carrier_owner_changed')
   assert(same(t.carrier:GetHeldActor(),t.patient),'conversion_patient_lost')
   assert(same(t.carrier.Mesh,t.mesh),'conversion_mesh_changed')
   assert(num(t.mesh:GetAnimationMode())==1,'conversion_animation_interrupted')
   local instance=t.mesh:GetAnimInstance()
   assert(same(instance,t.instance)and same(instance.CurrentAsset,t.asset),'conversion_sequence_interrupted')
   local pos=num(t.mesh:GetPosition());assert(pos and pos>=0,'conversion_position_unavailable')
   assert(pos+0.000001>=t.last_position,'conversion_playback_rewound')
   local now=num(safe(function()return gs:GetLevelTime()end))
   if pos>t.last_position then t.advanced=true;t.last_progress_time=now end;t.last_position=pos
   local playing=t.mesh:IsPlaying();assert(type(playing)=='boolean','conversion_playing_state_unavailable')
   -- Small float tolerance only covers sequence-end representation; no clock
   -- or expected-duration test can award a conversion without real playback.
   if not playing then
    assert(t.advanced and pos>=t.length-0.000001,'conversion_playback_stopped_early')
    local restored,why=restore(t);assert(restored,why);t.state='completed';return 'completed'
   end
   -- Game time does not advance while paused. A stuck clip may fail and
   -- restore the carrier, but elapsed time alone can never award completion.
   assert(not(now and t.last_progress_time and now-t.last_progress_time>math.max(5,t.length*2)),
    'conversion_playback_stalled')
   return 'running'
  end)
  if not ok then t.state='failed';local restored,why=restore(t);return failure(tostring(result)..(restored and''or'; '..tostring(why)))end
  return result
 end
 function api.cancel(t)
  if type(t)~='table'then return failure('conversion_ticket_invalid')end
  if t.restored then return true end
  t.state='cancelled';return restore(t)
 end
 function api.reset_cache()
  local list={};for _,t in pairs(active)do list[#list+1]=t end
  for _,t in ipairs(list)do local ok,e=api.cancel(t);if not ok then return nil,e end end
  assets={};return true
 end
 function api.stop()local ok,e=api.reset_cache();if not ok then return nil,e end;stopped=true;return true end
 function api.status()
  local n=0;for _ in pairs(active)do n=n+1 end
  return{active=n,stopped=stopped}
 end
 return api
end
return M
