ANT OVERHAUL / 蚂蚁大修
Version 0.1.13 for Empires of the Undergrowth

REQUIREMENTS
Windows 64-bit; Steam build 26119497, game release-1.2.1.1.
The installer validates the game files and stops on a different build. Exploding Ants DLC units require the DLC to be owned, installed and authorized by the game. The required UE4SS loader is included.

FEATURES
- Additional applicable stats in the Minor Improvements system, purchased with Royal Jelly. Existing native improvements are retained; inapplicable or effectively capped stats cannot be purchased.
- Improvement pricing starts at 1, increases by 10% per point and caps at 300 per point. Native and extra points in the same upgrade group share the price calculation. A multi-point purchase can cost more than 300. Previous spending is not refunded.
- Choose extra buildable species before each new ordinary story mission or formicarium challenge. The original mission roster remains available. No added-species selection limit or population cap; normal food costs still apply.
- Build extra species such as stink ants, trap-jaw ants and little black ants in the formicarium, improve them in the biology menu and carry their improvements into missions.
- The termite major worker and driver ant worker are excluded from the extra selection/upgrade entries. Compatibility data for older saves is retained.
- Existing skills are used unless explicitly changed for that mission. The roster picker does not reset numerical improvements.
- Version 0.1.13 fixes redundant save hashing during story-mission/difficulty previews. It is not a guarantee of higher combat FPS in every situation.

INSTALLER
1. Close the game and back up the entire %LOCALAPPDATA%\EotU\Saved\SaveGames folder.
2. Run the installer EXE. Confirm or browse to the game folder containing EotU.exe, then click 安装 (Install).
3. Wait for validation and completion, then launch normally through Steam. Hashing the main resource archive can take some time; 日志 opens the log.
The installer does not always require elevation. It stops on conflicting loaders, changed files or incompatible versions. Do not overwrite another mod's loader to bypass a conflict.
An intact installation of this version is recognized. Version 0.1.12 can be updated directly, without uninstalling or pressing F8. Other old versions require their appropriate migration path.

MANUAL ZIP
Use the manual package only for the supported game version and a fresh installation without an existing UE4SS or other loader.
1. Close the game, back up saves and extract the ZIP to a temporary folder.
2. Copy its EotU and AntOverhaul-Manager folders, plus 登记手动安装.cmd, 检查安装.cmd and 卸载模组.cmd, into the game root containing EotU.exe. The resulting path should include EotU\Binaries\Win64\dwmapi.dll.
3. If Windows asks to replace existing files, cancel and check with the installer. Do not overwrite another loader or mod configuration.
4. Run 登记手动安装.cmd (Register Manual Install) to validate and register the copied files. Use 检查安装.cmd (Check Installation) for a lightweight status check and 卸载模组.cmd (Uninstall) for removal. Alternatively, the EXE installer can take over a complete manual installation by selecting the same game root and clicking 安装 (Install).
Manual copying does not perform version checks. Do not extract the entire package into ue4ss\Mods or create an EotU\EotU folder.

CONTROLS AND MISSION SAVES
Open a species' native Minor Improvements window. Confirm or cancel pending purchases, then press F6 for extra attributes. F6 advances pages; F7 returns to the native window and cancels unconfirmed selections. Use the normal plus, minus and purchase controls. Wait for a final success message after queued/save operations.
Every new mission prompts for its roster again. Ordinary story missions and ongoing formicarium challenges do not support saving and resuming the battle midway. Saved formicarium progression and improvements remain separate from a mission battlefield.

SAVES AND UNINSTALLATION
Back up the entire SaveGames folder, including EAA_AllAttributes_v1.tsv, EAA_StoryRoster_v1.tsv and their backup, temporary and pending files. Additional records have no Steam Cloud synchronization guarantee.
ONLY if the game uses a custom -UserDir, specify the actual SaveGames directory during the first installation or manual registration so uninstall preparation is checked against the right records. From PowerShell in the installer's directory, for example (replace the example path):
  & '.\AntOverhaul-0.1.13-Setup.exe' --save-games-root 'D:\MyEotUSaves\Saved\SaveGames'
For the manual ZIP, run this from PowerShell in the game root:
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File '.\AntOverhaul-Manager\ManualManager.ps1' -Action AdoptManual -SaveGamesRoot 'D:\MyEotUSaves\Saved\SaveGames'
The installation record remembers this directory for subsequent uninstall checks. Players using the normal save location do not need these options.
Save normally, exit the game, then click 卸载 (Uninstall) or run 卸载模组.cmd. There is no need to enter each colony and press F6/F8.
The manager checks all improved colonies' current save pairs. Where cleanup is needed, it backs up the entire SaveGames folder before clamping only current HP that exceeds the verified native maximum. Already wounded units below that maximum retain their HP. Story progress, Royal Jelly, native improvements, units, nursery tiles and unrelated save content are preserved. Extra improvement records and historical snapshots remain, with current bindings updated to the cleaned saves.
Backups are kept in EAA-uninstall-backups next to SaveGames; the installer log shows the exact location. Invalid or unmatched records, pending transactions, unsupported versions or unverified unit states stop the operation. If a commit fails, the manager attempts to restore changed files and retains the backup.
Only each colony's current save pair is prepared; historical, automatic and Stage backups are not rewritten. Royal Jelly is not refunded. The original manual F8 preparation remains available.
Playing and saving after uninstall changes the native save's binding to its improvement records. Reinstallation is not guaranteed to restore cultivation seamlessly. Recovery requires native saves and additional records backed up together at the same time.

OBSERVED UNINSTALL BEHAVIOR
In an isolated 17-species test, all 17 ants and their 17 nursery tiles remained after preparation, complete loader removal, a vanilla reload and another native save. All 17 species could naturally replenish using normal food costs. ArmyAnt loaded as ArmyAntMedia, while natural replacement used ArmyAnt again; identical appearance and combat behavior are not established. Nursery upgrading and long-term post-uninstall gameplay were not validated by this test.

THIRD-PARTY COMPONENTS
UE4SS v3.0.1-1183-gcdbc0b66. See ThirdPartyNotices.txt for source and license.
This package does not include the game, DLC content, player saves or test data.
