[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Split-Path -Parent $PSScriptRoot
$release='0.1.13'
$package=Join-Path $root ('delivery\EotU-AllAttributes-'+$release)
$freezePath=Join-Path $root ('analysis\release-freeze-'+$release+'.json')
$freeze=Get-Content -LiteralPath $freezePath -Raw -Encoding UTF8 | ConvertFrom-Json
$manifest=Get-Content -LiteralPath (Join-Path $package 'manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if($freeze.state -ne 'frozen' -or $freeze.release -ne $release -or $manifest.release -ne $release -or @($manifest.files).Count -ne 20){throw 'Unexpected frozen release'}
function Sha([string]$path) { (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Child([string]$base,[string]$relative) {
    if([IO.Path]::IsPathRooted($relative) -or $relative -match '(^|[\\/])\.\.?([\\/]|$)|:'){throw 'Unsafe relative path'}
    $path=[IO.Path]::GetFullPath((Join-Path $base $relative))
    if(-not $path.StartsWith([IO.Path]::GetFullPath($base).TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Path escaped build directory'}
    return $path
}
foreach($f in $manifest.files) {
    $src=Child (Join-Path $package 'payload') $f.path
    if((Sha $src) -ne $f.sha256 -or (Get-Item -LiteralPath $src).Length -ne $f.length){throw ('Frozen payload changed: '+$f.path)}
}
foreach($m in $freeze.moduleHashes.PSObject.Properties) {
    if((Sha (Join-Path $package ('payload\EotU\Binaries\Win64\ue4ss\Mods\AllAttributes\Scripts\'+$m.Name))) -ne $m.Value){throw 'Lua source differs from validated freeze'}
}
if((Sha (Join-Path $package 'payload\EotU\Binaries\Win64\ue4ss\UE4SS-settings.ini')) -ne $freeze.settingsSha256){throw 'Runtime settings changed'}
$build=Join-Path $root ('installer-build\'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[Guid]::NewGuid().ToString('N').Substring(0,6))
$embedded=Join-Path $build 'embedded'
$manual=Join-Path $build 'manual'
$out=Join-Path $root ('delivery\AntOverhaul-'+$release)
$manager=Join-Path $manual 'AntOverhaul-Manager'
New-Item -ItemType Directory -Path $embedded,$manager,$out -Force | Out-Null
$utf8=New-Object Text.UTF8Encoding($false)
$bom=New-Object Text.UTF8Encoding($true)
$references='C:\Program Files (x86)\Reference Assemblies\Microsoft\Framework\.NETFramework\v4.8'
$csc=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$healthReference=Join-Path $PSScriptRoot 'uninstall\health-reference.json'
if((Get-Content -LiteralPath $healthReference -Raw -Encoding UTF8 | ConvertFrom-Json).status -ne 'validated'){throw 'Native health reference has not passed validation'}
function Write-PS([string]$src,[string]$dst){[IO.File]::WriteAllText($dst,[IO.File]::ReadAllText($src),$bom)}
Copy-Item -LiteralPath (Join-Path $package 'payload') -Destination $embedded -Recurse
Copy-Item -LiteralPath (Join-Path $package 'payload\EotU') -Destination $manual -Recurse
foreach($target in @($embedded,$manager)) {
    foreach($file in @('manifest.json','source-freeze.json','Manage-Mod.ps1','Update-Mod.ps1','update.json','ThirdPartyNotices.txt')) {
        Copy-Item -LiteralPath (Join-Path $package $file) -Destination (Join-Path $target $file)
    }
    Write-PS (Join-Path $PSScriptRoot 'backend\Backend.ps1') (Join-Path $target 'Backend.ps1')
    Copy-Item -LiteralPath $healthReference -Destination (Join-Path $target 'health-reference.json')
}
$helper=Join-Path $embedded 'AutoPrepare.exe'
$helperRefs=@('mscorlib.dll','System.dll','System.Core.dll','System.IO.Compression.dll','System.Web.Extensions.dll') | ForEach-Object {'/reference:'+(Join-Path $references $_)}
& $csc /nologo /noconfig /nostdlib+ /target:exe /platform:x64 /optimize+ /debug- /langversion:5 ('/out:'+$helper) @helperRefs (Join-Path $PSScriptRoot 'uninstall\SavePatcher.cs') (Join-Path $PSScriptRoot 'uninstall\AutoPrepare.cs')
if($LASTEXITCODE -ne 0){throw 'Automatic uninstall helper compile failed'}
Copy-Item -LiteralPath $helper -Destination (Join-Path $manager 'AutoPrepare.exe')
$logoNotice="`r`nInstaller artwork: Empires of the Undergrowth Steam library logo (App ID 463530).`r`nNexus Mods icon: original icon from https://help.nexusmods.com/, used to identify the author's profile link.`r`nOriginal artwork is used unchanged; rights remain with its respective owners. This is an unofficial mod.`r`n"
[IO.File]::AppendAllText((Join-Path $embedded 'ThirdPartyNotices.txt'),$logoNotice,$utf8)
Copy-Item -LiteralPath (Join-Path $embedded 'ThirdPartyNotices.txt') -Destination (Join-Path $out 'ThirdPartyNotices.txt') -Force
Write-PS (Join-Path $PSScriptRoot 'ManualManager.ps1') (Join-Path $manager 'ManualManager.ps1')
foreach($entry in @(@('登记手动安装.cmd','AdoptManual'),@('检查安装.cmd','Inspect'),@('卸载模组.cmd','Uninstall'))) {
    $body="@echo off`r`nchcp 65001 >nul`r`nsetlocal DisableDelayedExpansion`r`n`"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe`" -NoLogo -NoProfile -ExecutionPolicy Bypass -File `"%~dp0AntOverhaul-Manager\ManualManager.ps1`" -Action "+$entry[1]+"`r`nset result=%errorlevel%`r`npause`r`nexit /b %result%`r`n"
    [IO.File]::WriteAllText((Join-Path $manual $entry[0]),$body,$utf8)
}
foreach($file in @('使用说明.txt','README.txt')) {
    foreach($target in @($embedded,$manual,$out)){Copy-Item -LiteralPath (Join-Path $PSScriptRoot ('docs\'+$file)) -Destination (Join-Path $target $file) -Force}
}
Copy-Item -LiteralPath (Join-Path $package 'ThirdPartyNotices.txt') -Destination (Join-Path $manual 'ThirdPartyNotices.txt')
Add-Type -AssemblyName System.IO.Compression.FileSystem
$payloadZip=Join-Path $build 'payload.zip'
[IO.Compression.ZipFile]::CreateFromDirectory($embedded,$payloadZip,[IO.Compression.CompressionLevel]::Optimal,$false)
$references='C:\Program Files (x86)\Reference Assemblies\Microsoft\Framework\.NETFramework\v4.8'
$refs=@('mscorlib.dll','System.dll','System.Core.dll','System.Xaml.dll','System.Drawing.dll','System.IO.Compression.dll','System.IO.Compression.FileSystem.dll','System.Windows.Forms.dll','System.Web.Extensions.dll','WindowsBase.dll','PresentationCore.dll','PresentationFramework.dll') | ForEach-Object { '/reference:'+(Join-Path $references $_) }
$csc=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$exe=Join-Path $build ('AntOverhaul-'+$release+'-Setup.exe')
$logo=Join-Path $PSScriptRoot 'assets\EotU-Steam-Logo.png'
if((Sha $logo) -ne 'ad5d7e8993476b29aa50d3348810abf407e17f6e3f135303aa6e3e5b09021462'){throw 'Steam logo differs from original reference'}
$nexusIcon=Join-Path $PSScriptRoot 'assets\NexusMods-Icon.png'
if((Sha $nexusIcon) -ne 'c03d6fd060e08be9855ac8a68f105feb41344d0370d40c28d6ba7e6db1cb21be'){throw 'Nexus Mods icon differs from original reference'}
$options=@('/nologo','/noconfig','/nostdlib+','/target:winexe','/platform:x64','/optimize+','/debug-','/langversion:5',('/win32manifest:'+(Join-Path $PSScriptRoot 'app.manifest')),('/resource:'+$payloadZip+',AntOverhaul.Payload.zip'),('/resource:'+$logo+',AntOverhaul.EotUSteamLogo.png'),('/resource:'+$nexusIcon+',AntOverhaul.NexusModsIcon.png'),('/out:'+$exe))+$refs
$sources=@(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'ui') -Filter '*.cs' -File | Sort-Object Name | ForEach-Object FullName)
if($sources.Count -lt 3){throw 'Missing installer UI sources'}
& $csc @options @sources
if($LASTEXITCODE -ne 0){throw 'Installer compile failed'}
$manualZip=Join-Path $build ('AntOverhaul-'+$release+'-Manual.zip')
[IO.Compression.ZipFile]::CreateFromDirectory($manual,$manualZip,[IO.Compression.CompressionLevel]::Optimal,$false)
foreach($src in @($exe,$manualZip)) {
    $dst=Join-Path $out ([IO.Path]::GetFileName($src))
    if(Test-Path -LiteralPath $dst){Copy-Item -LiteralPath $dst -Destination (Join-Path $build ('previous-'+[IO.Path]::GetFileName($src)))}
    Copy-Item -LiteralPath $src -Destination $dst -Force
}
$artifacts=@($exe,$manualZip) | ForEach-Object { [ordered]@{name=[IO.Path]::GetFileName($_);sha256=(Sha $_);bytes=(Get-Item -LiteralPath $_).Length} }
[IO.File]::WriteAllText((Join-Path $out 'SHA256SUMS.txt'),(($artifacts | ForEach-Object {$_.sha256+' *'+$_.name}) -join "`r`n")+"`r`n",$utf8)
$sourceHashes=@(Get-ChildItem -LiteralPath $PSScriptRoot -Recurse -File | Where-Object {$_.FullName -notmatch '\\\.validation\\' -and $_.Extension -in @('.cs','.ps1','.py','.txt','.md','.manifest','.png','.json')} | Sort-Object FullName | ForEach-Object { @{path=$_.FullName.Substring($PSScriptRoot.Length+1).Replace('\','/');sha256=(Sha $_.FullName)} })
$result=[ordered]@{release=$release;installerRevision=3;automaticUninstall=$true;builtAt=(Get-Date).ToString('o');output=$out;build=$build;embedded=$embedded;manual=$manual;sourceFreezeSHA256=(Sha $freezePath);payloadFiles=20;luaFiles=15;autoPrepareSHA256=(Sha $helper);healthReferenceSHA256=(Sha $healthReference);nexusProfile='https://www.nexusmods.com/profile/Miossstry';nexusIconSHA256=(Sha $nexusIcon);artifacts=$artifacts;installerSources=$sourceHashes;officialGameModified=$false}
[IO.File]::WriteAllText((Join-Path $root 'analysis\installer-build-0.1.13.json'),($result | ConvertTo-Json -Depth 8),$utf8)
$result | ConvertTo-Json -Depth 3
