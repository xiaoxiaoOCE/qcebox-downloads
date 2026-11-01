Ant Overhaul 0.1.13 — source for Nexus Mods moderator review
Installer revision 3 / file version 0.1.13.2
Mod page: https://www.nexusmods.com/empiresoftheundergrowth/mods/29

This package is local review material. It does not claim the quarantined files
are harmless or that a scanner finding is a false positive. It does not alter,
hide, or bypass any scanning mechanism. Please review the source and findings.

Contents
- installer/ui: all six C# WPF installer source files.
- installer/uninstall: AutoPrepare.cs, SavePatcher.cs and exact health-reference
  JSON used by the release. Reference metadata refers to local research files;
  those research/game-asset/save files are intentionally not distributed here.
- installer/backend and ManualManager.ps1: PowerShell management source.
- mod/AllAttributes/Scripts: all 15 Lua modules, byte-identical to release.
- release-management: manifest, frozen hashes, installation/update scripts.
- release-docs: user instructions and original UE4SS MIT license/credits.
- installer/assets: the original installer logos and source provenance.
  Artwork credit records origin; it is not a claim of separate redistribution
  permission or a new license grant over third-party logos.

Build-Installer.original.ps1 is included as the original release builder for
comparison. It expects the private project layout and is NOT the standalone
entry point. Use Build-Review.ps1 for this package.

Build prerequisites
- Windows x64 and Windows PowerShell 5.1.
- .NET Framework 4.8 Developer Pack / targeting reference assemblies.
- The .NET Framework x64 csc.exe included with Windows/.NET Framework.
- The original AntOverhaul-0.1.13-Manual.zip from this release, SHA256:
  db4e3b4709acc94ecfcd5ecfc26127fd27a54fe265ec82217d3c0a816a584a79

Build command (replace paths with your local paths):
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Build-Review.ps1 -ManualArchive 'C:\Review\AntOverhaul-0.1.13-Manual.zip' -OutputDirectory 'C:\Review\BuildOutput'

The output directory must not already exist. The script verifies the input
archive hash, extracts into that new directory, verifies the 20 managed
payload files, and compiles AutoPrepare.exe and the WPF installer from the
included source. It uses the bundled Lua source after checking its identity.
No installed game, Steam login, player saves, network requests, or private
project directories are needed. It does not launch the game or install a mod.

This is a buildable review package, not a bit-for-bit deterministic build
claim. Compiler PE timestamps, assembly identifiers, ZIP timestamps and compression
implementation/runtime differences may change output bytes and sizes. Build receipts state exact generated hashes. Do not upload a rebuilt
binary as if it were the original quarantined file.

UE4SS is an unchanged third-party dependency, reused from the hash-pinned
Manual.zip input rather than compiled by this script.
Version: v3.0.1-1183-gcdbc0b66
Source: https://github.com/UE4SS-RE/RE-UE4SS
Original upstream archive:
https://github.com/UE4SS-RE/RE-UE4SS/releases/download/experimental-latest/UE4SS_v3.0.1-1183-gcdbc0b66.zip
Upstream archive SHA256:
e4a47e23e2eeb8379c4fc388d1b1686f01c6c5930d84a2ee4a6a9574b274e681
Full original MIT notice: release-docs/ThirdPartyNotices.txt.

Behavior relevant to review
- The game loader is a native DLL proxy (dwmapi.dll) and UE4SS.dll. Its purpose
  is to load the Lua mod inside the local game process.
- The installer embeds its own payload.zip as a .NET resource, extracts it to
  a temporary directory, and invokes its bundled PowerShell backend. This is
  the existing shipping layout, openly disclosed for review.
- Install/uninstall scripts copy/remove only managed mod files and maintain
  an installation record. The scripts include integrity/version checks.
- AutoPrepare backs up SaveGames before preparing current colony saves for
  uninstall, changing only eligible excess saved Health and ledger bindings.
- Scripts may be run using ExecutionPolicy Bypass / an encoded command by
  the installer. Their complete source is included for inspection.
- The UI can open the author's Nexus profile in the default browser after
  the user clicks its hyperlink. It is not an automatic download/update path.

The author requested the functionality; mod code, installer UI and supporting
text were generated and revised with OpenAI Codex. The source is supplied for
inspection, not as a blanket license grant for project-specific content.

中文简述
这是供 Nexus 人工复核的本地源码材料，不代表已认定误报或已获得解封。
包含安装器、离线卸载助手、管理脚本及全部 15 个 Lua 模组源码。
构建需要 Windows、PowerShell 5.1、.NET Framework 4.8 Developer Pack，
以及 SHA256 对应的原始 Manual.zip；不需要游戏、存档或作者工作目录。
构建脚本只在新目录编译，不会安装模组或启动游戏。UE4SS 使用原始二进制，
其官方来源和 MIT 许可列于上方。两个徽标的来源记录不等同于再分发授权。
