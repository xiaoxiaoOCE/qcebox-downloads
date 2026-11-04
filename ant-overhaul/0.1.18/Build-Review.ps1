[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ManualZip,
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [string]$FrameworkReferenceDirectory='C:\Program Files (x86)\Reference Assemblies\Microsoft\Framework\.NETFramework\v4.8'
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
function Sha([string]$p){return (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant()}
function Child([string]$base,[string]$relative){
    if([IO.Path]::IsPathRooted($relative) -or $relative -match '(^|[\\/])\.\.?([\\/]|$)|:|[\x00-\x1f]'){throw 'Unsafe relative path'}
    $root=[IO.Path]::GetFullPath($base).TrimEnd('\','/')
    $p=[IO.Path]::GetFullPath((Join-Path $root $relative))
    if(-not $p.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Path escaped root'}
    return $p
}
function NoLink([string]$p){
    $p=[IO.Path]::GetFullPath($p)
    while($p){if((Test-Path -LiteralPath $p) -and ((Get-Item -LiteralPath $p -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Reparse points are not accepted'};$next=Split-Path -Parent $p;if($next -eq $p){break};$p=$next}
}
function CopyFile([string]$from,[string]$to){[void][IO.Directory]::CreateDirectory((Split-Path -Parent $to));[IO.File]::Copy($from,$to,$false)}
$source=[IO.Path]::GetFullPath($PSScriptRoot)
$manualArchive=[IO.Path]::GetFullPath($ManualZip)
$output=[IO.Path]::GetFullPath($OutputDirectory)
NoLink $source;NoLink $manualArchive;NoLink $output
if(Test-Path -LiteralPath $output){throw 'Output directory already exists; choose a new empty location'}
if($output.StartsWith($source.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Choose an output outside this source package'}
$review=Get-Content -LiteralPath (Join-Path $source 'review-manifest.json') -Raw -Encoding UTF8|ConvertFrom-Json
if($review.schema -ne 1 -or $review.release -cne '0.1.18'){throw 'Wrong review package'}
if((Sha $manualArchive) -cne $review.manual.sha256){throw 'Manual ZIP differs from the published input pinned by this review package'}
$sourceFiles=@(Get-ChildItem -LiteralPath $source -Recurse -File)
if($sourceFiles.Count -ne @($review.files).Count+1){throw 'Review source tree contains missing or extra files'}
foreach($f in $review.files){$p=Child $source $f.path;NoLink $p;if((Sha $p) -cne $f.sha256 -or (Get-Item -LiteralPath $p).Length -ne $f.length){throw ('Review source differs: '+$f.path)}}
$csc=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if(-not(Test-Path -LiteralPath $csc -PathType Leaf)){throw '.NET Framework 4.x C# compiler is required'}
if(-not(Test-Path -LiteralPath (Join-Path $FrameworkReferenceDirectory 'PresentationFramework.dll') -PathType Leaf)){throw '.NET Framework 4.8 Developer Pack reference assemblies are required'}
[void][IO.Directory]::CreateDirectory($output)
$manual=Join-Path $output 'build\manual'
$embedded=Join-Path $output 'build\embedded'
[void][IO.Directory]::CreateDirectory($manual)
[void][IO.Directory]::CreateDirectory($embedded)
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip=[IO.Compression.ZipFile]::OpenRead($manualArchive)
$seen=@{}
try{
    foreach($e in $zip.Entries){
        if($e.FullName.EndsWith('/')){continue}
        if($seen.ContainsKey($e.FullName)){throw 'Duplicate archive path'};$seen[$e.FullName]=$true
        if($e.FullName -match '\.(zip|7z|rar|tar|gz)$'){throw 'Nested archives are not expected'}
        $p=Child $manual $e.FullName
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $p))
        [IO.Compression.ZipFileExtensions]::ExtractToFile($e,$p,$false)
    }
}finally{$zip.Dispose()}
$manager=Join-Path $manual 'AntOverhaul-Manager'
$manifest=Get-Content -LiteralPath (Join-Path $manager 'manifest.json') -Raw -Encoding UTF8|ConvertFrom-Json
if($manifest.release -cne '0.1.18' -or @($manifest.files).Count -ne 36 -or @($manifest.files|Where-Object {$_.path.EndsWith('.lua')}).Count -ne 31){throw 'Unexpected published payload manifest'}
foreach($f in $manifest.files){$p=Child $manual $f.path;if((Sha $p) -cne $f.sha256 -or (Get-Item -LiteralPath $p).Length -ne $f.length){throw ('Published payload differs: '+$f.path)}}
foreach($f in @($manifest.files|Where-Object {$_.path.EndsWith('.lua')})){
    $p=Join-Path $source ('mod-source\'+[IO.Path]::GetFileName($f.path))
    if((Sha $p) -cne $f.sha256){throw 'Readable Lua sources do not match published payload'}
}
foreach($file in @('Backend.ps1','ManualManager.ps1','Manage-Mod.ps1','Update-Mod.ps1','health-reference.json')){
    if((Sha (Join-Path $source ('manager-source\'+$file))) -cne (Sha (Join-Path $manager $file))){throw ('Manager source differs from published file: '+$file)}
}
[void][IO.Directory]::CreateDirectory((Join-Path $embedded 'payload'))
Copy-Item -LiteralPath (Join-Path $manual 'EotU') -Destination (Join-Path $embedded 'payload') -Recurse
foreach($file in @('manifest.json','source-freeze.json','Manage-Mod.ps1','Update-Mod.ps1','update.json','ThirdPartyNotices.txt','Backend.ps1','health-reference.json')){CopyFile (Join-Path $manager $file) (Join-Path $embedded $file)}
foreach($file in @('README.txt','使用说明.txt')){CopyFile (Join-Path $manual $file) (Join-Path $embedded $file)}
$notice="`r`nInstaller artwork: Empires of the Undergrowth Steam library logo (App ID 463530).`r`nNexus Mods icon: original icon from https://help.nexusmods.com/, used to identify the author's profile link.`r`nOriginal artwork is used unchanged; rights remain with its respective owners. This is an unofficial mod.`r`n"
[IO.File]::AppendAllText((Join-Path $embedded 'ThirdPartyNotices.txt'),$notice,(New-Object Text.UTF8Encoding($false)))
$helper=Join-Path $output 'AutoPrepare.exe'
$helperRefs=@('mscorlib.dll','System.dll','System.Core.dll','System.IO.Compression.dll','System.Web.Extensions.dll')|ForEach-Object {'/reference:'+(Join-Path $FrameworkReferenceDirectory $_)}
& $csc /nologo /noconfig /nostdlib+ /target:exe /platform:x64 /optimize+ /debug- /langversion:5 ('/out:'+$helper) @helperRefs (Join-Path $source 'installer-source\uninstall\SavePatcher.cs') (Join-Path $source 'installer-source\uninstall\AutoPrepare.cs')
if($LASTEXITCODE -ne 0){throw 'Automatic uninstall helper compilation failed'}
CopyFile $helper (Join-Path $embedded 'AutoPrepare.exe')
$payloadZip=Join-Path $output 'build\payload.zip'
[IO.Compression.ZipFile]::CreateFromDirectory($embedded,$payloadZip,[IO.Compression.CompressionLevel]::Optimal,$false)
$refs=@('mscorlib.dll','System.dll','System.Core.dll','System.Xaml.dll','System.Drawing.dll','System.IO.Compression.dll','System.IO.Compression.FileSystem.dll','System.Windows.Forms.dll','System.Web.Extensions.dll','WindowsBase.dll','PresentationCore.dll','PresentationFramework.dll')|ForEach-Object {'/reference:'+(Join-Path $FrameworkReferenceDirectory $_)}
$exe=Join-Path $output 'AntOverhaul-0.1.18-Setup.exe'
$options=@('/nologo','/noconfig','/nostdlib+','/target:winexe','/platform:x64','/optimize+','/debug-','/langversion:5',('/win32manifest:'+(Join-Path $source 'installer-source\app.manifest')),('/resource:'+$payloadZip+',AntOverhaul.Payload.zip'),('/resource:'+(Join-Path $source 'installer-source\assets\EotU-Steam-Logo.png')+',AntOverhaul.EotUSteamLogo.png'),('/resource:'+(Join-Path $source 'installer-source\assets\NexusMods-Icon.png')+',AntOverhaul.NexusModsIcon.png'),('/out:'+$exe))+$refs
$ui=@(Get-ChildItem -LiteralPath (Join-Path $source 'installer-source\ui') -Filter '*.cs' -File|Sort-Object Name|ForEach-Object FullName)
if($ui.Count -ne 6){throw 'Expected exactly six installer UI source files'}
& $csc @options @ui
if($LASTEXITCODE -ne 0){throw 'Installer compilation failed'}
$result=[ordered]@{schema=1;release='0.1.18';passed=$true;manualSha256=(Sha $manualArchive);managedFiles=36;luaFiles=31;sourceFiles=@($review.files).Count;rebuiltInstallerSha256=(Sha $exe);rebuiltAutoPrepareSha256=(Sha $helper);binaryIdenticalReproductionClaimed=$false;note='The original .NET Framework compiler and ZIP pipeline include build-time metadata. This rebuild uses the same code, verified published payload, resources and compiler switches; byte-for-byte binary equality is not claimed.';gameOrSavesModified=$false;networkAccessUsed=$false}
[IO.File]::WriteAllText((Join-Path $output 'rebuild-result.json'),($result|ConvertTo-Json -Depth 8),(New-Object Text.UTF8Encoding($false)))
$result|ConvertTo-Json -Depth 8
