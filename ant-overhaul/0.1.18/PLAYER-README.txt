ANT OVERHAUL / 蚂蚁大修 0.1.18
Empires of the Undergrowth
Author: https://www.nexusmods.com/profile/Miossstry

REQUIREMENTS
Windows 64-bit; Steam build 26412732. The installer and management tools require .NET Framework 4.8 (runtime) and Windows PowerShell 5.1. The required UE4SS loader is included.
Exploding Ants DLC species require the DLC to be owned, installed and authorized by the game. No game or DLC files are supplied. Installer controls and custom skill labels currently use Chinese; this file explains the controls in English.

INSTALLER (RECOMMENDED)
1. Save normally, exit the game and back up the entire %LOCALAPPDATA%\EotU\Saved\SaveGames folder.
2. Run AntOverhaul-0.1.18-Setup.exe and select the game root containing EotU.exe.
3. Click 安装 (Install), wait for game/file validation and completion, then launch normally through Steam.
The installer stops on an unsupported build, changed managed files or a conflicting loader. Do not delete another mod or force an overwrite to bypass validation.

UPDATING
Recognized intact installations of 0.1.13–0.1.17 can update after exact file verification. A locally modified installation is not supported merely because its version number matches.
Save, exit and back up first. Use the 0.1.18 installer on the original game directory; do not uninstall first or press F8. Updating does not rewrite player saves.
If verification fails, retain the detailed log. Do not mix old/new files or delete EAA records. Downgrading after playing the new version is not guaranteed.

MANUAL ZIP (FRESH INSTALLATIONS)
1. Exit the game, back up saves and extract AntOverhaul-0.1.18-Manual.zip to a temporary folder.
2. Copy EotU, AntOverhaul-Manager, 登记手动安装.cmd, 检查安装.cmd and 卸载模组.cmd into the game root containing EotU.exe.
3. The result should include EotU\Binaries\Win64\dwmapi.dll. Do not place the package inside ue4ss\Mods or create EotU\EotU.
4. Run 登记手动安装.cmd (Register Manual Install) to verify/register it. 检查安装.cmd checks the installation later.
Cancel if an existing loader or replacement prompt is encountered; use the installer to inspect it. Existing Ant Overhaul installations should use the installer update route, not mixed manual copies.

FEATURES AND CONTROLS
- Choose additional species before each new story mission or formicarium challenge. Original mission species remain available. No extra-species selection limit or population cap; normal construction and hatching food costs apply.
- Build additional formicarium species and improve them through Biology. Their numerical improvements carry into missions.
- Numerical improvements start at 1 Royal Jelly, increase by 10% per point and cap at 300 per point. Native and additional points share the appropriate upgrade-group calculation. A multi-point purchase can exceed 300.
- In native Minor Improvements, first confirm/cancel pending choices, then press F6 for extra stats. F6 advances pages; F7 returns and cancels unconfirmed selections. Wait for the final result while saving.
- Click the side skill buttons on Trapjaw/Slave-maker cards. Permanent purchases or switches cost 80 Royal Jelly on the left and 100 on the right. Selecting the current choice or cancelling is free. Pre-mission overrides are free, affect only that mission and do not reset numerical cultivation.

CURRENT SKILLS
Trapjaw: Fast Recovery doubles retreat healing. Brief Respite saves the ant at 1 HP on lethal damage only when retreat is ready, immediately retreats and grants 1.5 seconds of invulnerability; no protection during retreat cooldown. Danger Avoidance reduces that cooldown by 40%. Mousetrap empowers the next normal attack after retreat to 200% of attack damage, without stacking. Mousetrap replaces Hunting Reward and retains its existing purchase records.
Slave-maker: tier-two base stats are 90 HP/5.5 attack. From tier two, a lethal hit has a 25% chance to knock out an eligible target for transport to the queen and conversion. Left choices: Specialist Slave Master raises the chance to 50%, or Greater Prey enables eligible medium targets at tier three. Right choices: +15% attack speed or carrying movement speed for nearby friendly slaves while the skill holder lives; identical bonuses do not stack. Greater Prey no longer grants capture attacks to slaves.
With an available Matabele medic, eligible slaves can become wounded and await carrying/treatment. Captive state is retained through formicarium save/reload.

SAVES
Back up all of SaveGames, not just Colony*.sav. Include EAA_AllAttributes_v1.tsv, EAA_CustomSkills_v1.tsv, EAA_StoryRoster_v1.tsv and their backup, temporary and pending files. Steam Cloud synchronization of additional records is not guaranteed.
Ordinary story missions and ongoing formicarium challenges do not support saving/resuming the battle midway. Starting a mission again prompts for a new roster.
This version fixes Chinese save-path access and New Game Plus synchronization. It does not automatically rebind arbitrary pre-existing mismatched records. If improvements remain unavailable or a mismatch is reported, retain UE4SS.log and a complete save copy; do not delete the records.

CUSTOM SAVE LOCATION
Only if you changed the game's save location with -UserDir, specify the actual SaveGames folder on first installation. From PowerShell, replacing the sample path:
  & '.\AntOverhaul-0.1.18-Setup.exe' --save-games-root 'D:\MyEotUSaves\Saved\SaveGames'
For manual registration, run from PowerShell in the game root:
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File '.\AntOverhaul-Manager\ManualManager.ps1' -Action AdoptManual -SaveGamesRoot 'D:\MyEotUSaves\Saved\SaveGames'
The normal save location requires neither option.

UNINSTALLATION
1. Save normally and exit the game.
2. Click 卸载模组 (Uninstall Mod) or run 卸载模组.cmd. No per-colony F6/F8 steps are needed.
3. The manager checks current saves, backs them up when preparation is needed, prepares supported saves and removes its managed mod files. Saves and improvement records are retained. Unsupported data, mismatched records or unfinished purchases stop removal; read the details.
Do not delete the loader DLL as a substitute for uninstalling. Royal Jelly is not refunded. Continued vanilla use of every extra unit, captured slave, nursery and behavior is not guaranteed. Playing/saving after removal can break the correspondence with retained records; keep matching native saves and mod records from before uninstalling.
Uninstall backups are stored in EAA-uninstall-backups beside SaveGames; the installer details show the actual path.

REPORTING A PROBLEM
Include the mod version, Steam game build, reproduction steps, screenshot and EotU\Binaries\Win64\ue4ss\UE4SS.log. For save-specific issues, preserve a complete SaveGames copy before sending it privately; do not publish personal saves.

THIRD-PARTY COMPONENTS
UE4SS v3.0.1-1183-gcdbc0b66; see ThirdPartyNotices.txt for source and license.
Player saves, test scripts and the game itself are not included. Performance fixes address identified mod overhead, not a universal FPS guarantee.
