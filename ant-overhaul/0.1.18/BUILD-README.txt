ANT OVERHAUL 0.1.18 - SOURCE AND REBUILD REVIEW PACKAGE

Purpose
This package makes the shipped mod scripts, installer and automatic uninstall
helper readable, and provides a small standalone rebuild entry point. It does
not install the mod, start the game, change saves, or send data over the network.
It contains no nested archive, compiled executable, private player save, or log.

Inputs and requirements
1. Windows x64, Windows PowerShell 5.1, .NET Framework 4.8 Developer Pack.
2. The separately published AntOverhaul-0.1.18-Manual.zip. Keep it outside this
   source directory. Its exact SHA-256 is pinned in review-manifest.json.
3. No game installation, development workspace, private analysis evidence,
   Steam login, Nexus account or internet connection is needed for this rebuild.

Rebuild (run from the directory containing this README)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Build-Review.ps1 -ManualZip "C:\Review\AntOverhaul-0.1.18-Manual.zip" -OutputDirectory "C:\Review\Rebuilt-0.1.18"

Choose an output directory that does not already exist and is outside this
source directory. The script checks all readable source hashes, the external
Manual ZIP hash, all 36 managed payload files, and all 31 Lua sources before
building AutoPrepare.exe and AntOverhaul-0.1.18-Setup.exe. The supplied framework
reference directory can be overridden with -FrameworkReferenceDirectory.
Read rebuild-result.json for the resulting hashes. The build does NOT run either
executable. A build failure leaves its work directory intact for examination.

Reproduction scope
The installer and helper use the exact release source, artwork, compiler flags,
and hash-verified published payload. The original .NET Framework compiler and
ZIP pipeline include build-time metadata, so byte-identical EXE reproduction
is not claimed. The generated installer contains a payload ZIP resource by
design; this review ZIP and the public Manual ZIP contain no nested archives.
The three unchanged third-party loader files are taken from the supplied Manual
ZIP, not recompiled. They are pinned to the official UE4SS release below.

Source map
mod-source/                  All 31 shipped Lua modules, byte-for-byte.
manager-source/              Shipped PowerShell manager/backend/update code,
                             ownership/update manifests, health reference.
installer-source/ui/         Six exact C# sources selected for release 0.1.18.
installer-source/uninstall/  Automatic preparation and bounded save patcher.
installer-source/assets/     Original Steam logo and Nexus icon used in the UI.
Build-Review.ps1             Standalone rebuild entry point.
review-manifest.json         Source hashes and published input hashes.

Behavior relevant to review
The installer verifies game version/hash compatibility, stages the documented
UE4SS loader and Lua mod, and records ownership. Updates accept only known full
old managed-file hashes and retain an interrupted-operation recovery path.
Uninstall preparation backs up and processes supported saves locally before
removing owned files. It does not upload saves. The installer opens the author's
Nexus page only when its profile link is clicked. Consult the readable source
and PLAYER-README.txt for exact behavior and limitations; this package does not
assert that any antivirus detection is necessarily a false positive.

Third-party loader
Official project: https://github.com/UE4SS-RE/RE-UE4SS
Version: v3.0.1-1183-gcdbc0b66
Archive: https://github.com/UE4SS-RE/RE-UE4SS/releases/download/experimental-latest/UE4SS_v3.0.1-1183-gcdbc0b66.zip
Archive SHA-256: e4a47e23e2eeb8379c4fc388d1b1686f01c6c5930d84a2ee4a6a9574b274e681
UE4SS source and license remain upstream; see UE4SS-LICENSE.txt and
ThirdPartyNotices.txt. Artwork remains the property of its respective owners.
This is an unofficial mod. Providing sources for inspection does not grant
additional rights to third-party artwork or supersede the mod page permissions.

中文说明
这是 0.1.18 的精简源码复核包，不是给普通玩家使用的安装包。
将正式发布的 Manual.zip 单独放在源码包外，按上面的命令即可在新的目录中
重建安装器与 AutoPrepare；不需要原开发目录、游戏、私人分析文件或网络。
脚本只校验和编译，不运行安装器、不改正式游戏或存档。源码包内不含嵌套
压缩包、编译程序、玩家存档或日志。EXE 会带有编译时间等元数据，因此不
承诺重建文件与原版逐字节相同；代码、图像、编译选项和载荷均有哈希校验。
源码开放供复核不等于已确认杀毒误报，也不改变第三方素材权利和模组页权限。
