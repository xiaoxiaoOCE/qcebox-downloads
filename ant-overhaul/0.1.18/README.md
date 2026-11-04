# Ant Overhaul 0.1.18 - source review

This directory contains the 56 original files from the published source-review package, plus this README and a local .gitattributes file to preserve source bytes. It is review material, not a playable mod download.

Mod page: https://www.nexusmods.com/empiresoftheundergrowth/mods/29?tab=files

## Release identifiers

- AntOverhaul-0.1.18-Setup.exe: SHA-256 `616deed0f27db00fa9d5c2c1884177a88e0a81ff41dce27893796080280720db`
- AntOverhaul-0.1.18-Manual.zip: SHA-256 `e313a31861f1750793e60b58f860a4db6a5970508dbd21368d1723e090eb5a99`
- Original AntOverhaul-0.1.18-Source-Review.zip: SHA-256 `b4787cfb373859d201ca2704a6911717f8769d8a6d8ff263f1fe967f592511a3`

## Build instructions

Read [BUILD-README.txt](BUILD-README.txt) for the full procedure. Requirements: Windows x64, Windows PowerShell 5.1 and the .NET Framework 4.8 Developer Pack.

Download this source tree and keep the original release Manual.zip outside the source directory. From this directory run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Build-Review.ps1 -ManualZip "C:\Review\AntOverhaul-0.1.18-Manual.zip" -OutputDirectory "C:\Review\Rebuilt-0.1.18"
```

The output directory must not already exist and must be outside the source directory. The script checks source and payload hashes and builds the installer and uninstall helper. It does not execute either output, start the game, or modify player saves. No game installation is required for compilation. Preserve file bytes and line endings: the manifest performs exact hash checks.

Rebuild checks established method and resource equivalence; byte-identical whole-EXE reproduction is not claimed.

## Contents and provenance

- mod-source: all 31 shipped Lua modules.
- installer-source: exact installer and offline uninstall-helper C# sources and artwork.
- manager-source: PowerShell management scripts, ownership/update manifests and save-preparation reference data.
- review-manifest.json: source and release-input hashes.
- ThirdPartyNotices.txt and UE4SS-LICENSE.txt: third-party provenance and license.

The unmodified loader is UE4SS v3.0.1-1183-gcdbc0b66, from https://github.com/UE4SS-RE/RE-UE4SS . Its pinned archive SHA-256 is `e4a47e23e2eeb8379c4fc388d1b1686f01c6c5930d84a2ee4a6a9574b274e681`. Loader binaries are obtained from the separately supplied Manual.zip during rebuilding; they are not recompiled here.

No compiled EXE/DLL, nested archive, player save or runtime log is included in this source tree. Custom code was developed with assistance from OpenAI Codex. Providing sources is not a claim of antivirus clearance or a determination that a detection is false. Game artwork belongs to its respective owners; publication for inspection does not supersede third-party rights or the mod page permissions.
