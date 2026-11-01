[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ManualArchive,
    [string]$OutputDirectory=(Join-Path $PSScriptRoot 'review-build')
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$expectedArchive='db4e3b4709acc94ecfcd5ecfc26127fd27a54fe265ec82217d3c0a816a584a79'
$ManualArchive=[IO.Path]::GetFullPath($ManualArchive)
$OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory)
if((Get-FileHash -LiteralPath $ManualArchive -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expectedArchive){throw 'Use the original 0.1.13 Manual.zip matching the documented SHA256.'}
if(Test-Path -LiteralPath $OutputDirectory){throw 'OutputDirectory already exists; choose a new empty destination.'}
$framework=Join-Path ${env:ProgramFiles(x86)} 'Reference Assemblies\Microsoft\Framework\.NETFramework\v4.8'
$csc=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if(-not(Test-Path -LiteralPath (Join-Path $framework 'PresentationFramework.dll'))){throw 'Install .NET Framework 4.8 Developer Pack reference assemblies.'}
if(-not(Test-Path -LiteralPath $csc)){throw '.NET Framework x64 C# compiler is unavailable.'}
New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
$manual=Join-Path $OutputDirectory 'manual'
$embedded=Join-Path $OutputDirectory 'embedded'
New-Item -ItemType Directory -Path $embedded | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::ExtractToDirectory($ManualArchive,$manual)
$manager=Join-Path $manual 'AntOverhaul-Manager'
$manifest=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'release-management\manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach($file in $manifest.files){
    $path=Join-Path $manual $file.path
    if((Get-FileHash -LiteralPath $path).Hash -ne $file.sha256){throw ('Original manual payload mismatch: '+$file.path)}
}
$luaTarget=Join-Path $manual 'EotU\Binaries\Win64\ue4ss\Mods\AllAttributes\Scripts'
foreach($lua in Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'mod\AllAttributes\Scripts') -Filter '*.lua' -File){
    $target=Join-Path $luaTarget $lua.Name
    if((Get-FileHash -LiteralPath $lua.FullName).Hash -ne (Get-FileHash -LiteralPath $target).Hash){throw ('Supplied Lua differs from reviewed release: '+$lua.Name)}
    Copy-Item -LiteralPath $lua.FullName -Destination $target -Force
}
$bom=New-Object Text.UTF8Encoding($true)
function CopyPS([string]$source,[string]$destination){[IO.File]::WriteAllText($destination,[IO.File]::ReadAllText($source),$bom)}
CopyPS (Join-Path $PSScriptRoot 'installer\backend\Backend.ps1') (Join-Path $manager 'Backend.ps1')
CopyPS (Join-Path $PSScriptRoot 'installer\ManualManager.ps1') (Join-Path $manager 'ManualManager.ps1')
foreach($name in @('Manage-Mod.ps1','Update-Mod.ps1','manifest.json','source-freeze.json','update.json')){
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot ('release-management\'+$name)) -Destination (Join-Path $manager $name) -Force
}
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'installer\uninstall\health-reference.json') -Destination (Join-Path $manager 'health-reference.json') -Force
$helper=Join-Path $manager 'AutoPrepare.exe'
$helperRefs=@('mscorlib.dll','System.dll','System.Core.dll','System.IO.Compression.dll','System.Web.Extensions.dll') | ForEach-Object {'/reference:'+(Join-Path $framework $_)}
& $csc /nologo /noconfig /nostdlib+ /target:exe /platform:x64 /optimize+ /debug- /langversion:5 ('/out:'+$helper) @helperRefs (Join-Path $PSScriptRoot 'installer\uninstall\SavePatcher.cs') (Join-Path $PSScriptRoot 'installer\uninstall\AutoPrepare.cs')
if($LASTEXITCODE -ne 0){throw 'AutoPrepare compilation failed'}
New-Item -ItemType Directory -Path (Join-Path $embedded 'payload') | Out-Null
Copy-Item -LiteralPath (Join-Path $manual 'EotU') -Destination (Join-Path $embedded 'payload') -Recurse
foreach($name in @('manifest.json','source-freeze.json','Manage-Mod.ps1','Update-Mod.ps1','update.json','Backend.ps1','health-reference.json','AutoPrepare.exe')){
    Copy-Item -LiteralPath (Join-Path $manager $name) -Destination (Join-Path $embedded $name)
}
foreach($name in @('README.txt','使用说明.txt','ThirdPartyNotices.txt')){
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot ('release-docs\'+$name)) -Destination (Join-Path $embedded $name)
}
$payload=Join-Path $OutputDirectory 'payload.zip'
[IO.Compression.ZipFile]::CreateFromDirectory($embedded,$payload,[IO.Compression.CompressionLevel]::Optimal,$false)
$refs=@('mscorlib.dll','System.dll','System.Core.dll','System.Xaml.dll','System.Drawing.dll','System.IO.Compression.dll','System.IO.Compression.FileSystem.dll','System.Windows.Forms.dll','System.Web.Extensions.dll','WindowsBase.dll','PresentationCore.dll','PresentationFramework.dll') | ForEach-Object {'/reference:'+(Join-Path $framework $_)}
$setup=Join-Path $OutputDirectory 'AntOverhaul-0.1.13-Setup.exe'
$options=@('/nologo','/noconfig','/nostdlib+','/target:winexe','/platform:x64','/optimize+','/debug-','/langversion:5',('/win32manifest:'+(Join-Path $PSScriptRoot 'installer\app.manifest')),('/resource:'+$payload+',AntOverhaul.Payload.zip'),('/resource:'+(Join-Path $PSScriptRoot 'installer\assets\EotU-Steam-Logo.png')+',AntOverhaul.EotUSteamLogo.png'),('/resource:'+(Join-Path $PSScriptRoot 'installer\assets\NexusMods-Icon.png')+',AntOverhaul.NexusModsIcon.png'),('/out:'+$setup))+$refs
$sources=@(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'installer\ui') -Filter '*.cs' -File | Sort-Object Name | ForEach-Object FullName)
& $csc @options @sources
if($LASTEXITCODE -ne 0){throw 'Installer compilation failed'}
$rebuiltManual=Join-Path $OutputDirectory 'AntOverhaul-0.1.13-Manual.zip'
[IO.Compression.ZipFile]::CreateFromDirectory($manual,$rebuiltManual,[IO.Compression.CompressionLevel]::Optimal,$false)
$result=[ordered]@{purpose='Source review build only; no installation or game execution';release='0.1.13';installerRevision=3;inputArchiveSHA256=$expectedArchive;compiledSources=@($sources | ForEach-Object {[IO.Path]::GetFileName($_)})+@('AutoPrepare.cs','SavePatcher.cs');ue4ssRecompiled=$false;gameFilesRequired=$false;byteIdenticalReproductionClaimed=$false;artifacts=@($setup,$helper,$rebuiltManual) | ForEach-Object {@{name=[IO.Path]::GetFileName($_);sha256=(Get-FileHash -LiteralPath $_).Hash.ToLowerInvariant();bytes=(Get-Item -LiteralPath $_).Length}}}
$result | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'build-result.json') -Encoding UTF8
$result | ConvertTo-Json -Depth 7
