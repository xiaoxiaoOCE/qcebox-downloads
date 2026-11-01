# Ant Overhaul — source for Nexus Mods review

Source and build instructions for **Ant Overhaul 0.1.13**, installer revision 3 (file version 0.1.13.2), by **Miossstry**.

[Mod page](https://www.nexusmods.com/empiresoftheundergrowth/mods/29?tab=files)

The original downloads are quarantined by Nexus Mods. When reported, VirusTotal showed **7/71** detections for the installer and **5/67** for the manual ZIP. These materials support review; they do not establish that the detections are false positives or that the files are safe. Keep the original quarantined uploads available for moderator review.

## Original files under review

| File | SHA256 |
| --- | --- |
| `AntOverhaul-0.1.13-Setup.exe` | `0f7398d02425df6e33736ae07843b5beea2709e4651f8f4820a73f32f262df8a` |
| `AntOverhaul-0.1.13-Manual.zip` | `db4e3b4709acc94ecfcd5ecfc26127fd27a54fe265ec82217d3c0a816a584a79` |

## Build and inspect

Start with [REVIEW-README.txt](REVIEW-README.txt), then use [Build-Review.ps1](Build-Review.ps1). Requirements are Windows x64, Windows PowerShell 5.1, the .NET Framework 4.8 Developer Pack, and the original manual ZIP with the hash above.

The review build compiles the WPF installer and offline uninstall helper. It requires no installed game or player saves and performs no installation. Existing build results are recorded in [BUILD-VERIFICATION.json](BUILD-VERIFICATION.json). A successful build is not a byte-identical reproduction claim or a security verdict.

The repository includes six installer C# files, two uninstall-helper C# files, management PowerShell scripts, all 15 released Lua modules, and source inventories. It contains no compiled executable, player save, or extracted game package. UE4SS is reused from the original input archive, not rebuilt here.

## Credits and scope

UE4SS v3.0.1-1183-gcdbc0b66 is an unchanged third-party dependency. See [its upstream project](https://github.com/UE4SS-RE/RE-UE4SS) and [the included MIT notice](release-docs/ThirdPartyNotices.txt).

Installer artwork provenance is recorded under `installer/assets`. These records identify the original artwork and do not establish additional redistribution or reuse permission.

The mod-specific code, installer UI and supporting text were generated and revised with OpenAI Codex according to the author's requirements. These source materials are supplied to make the implementation inspectable while moderator/vendor review is pending.
