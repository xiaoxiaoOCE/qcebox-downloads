[CmdletBinding()]
param(
    [ValidateSet('Update','Rollback')][string]$Action='Update',
    [string]$GameRoot='F:\SteamLibrary\steamapps\common\Empires of the Undergrowth',
    [string]$PackageRoot=$PSScriptRoot,
    [string]$FreezeManifest=''
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$utf8=New-Object Text.UTF8Encoding($false)
$recordName='.eotu-allattributes-install.json'
$pendingName='.eotu-allattributes-update-pending.json'
$modId='EotU.AllAttributes.v1'
$toRelease='0.1.18'
$baseModules=@('core.lua','extra.lua','groups.lua','main.lua','native.lua','sha256.lua','ui.lua','roster.lua','roster_catalog.lua','roster_state.lua','roster_runtime.lua','roster_ui.lua','roster_challenge.lua','roster_home.lua','foreign_ui.lua','skills.lua','skills_state.lua','skills_runtime.lua','skills_ui.lua','skills_purchase.lua','slaver_controls_ui.lua','slaver_conversion.lua','slaver_conversion_animation.lua','slaver_damage_guard.lua','slaver_medical.lua','slaver_native.lua','slaver_runtime.lua','slaver_food.lua','slaver_objectives.lua','slaver_balance.lua','unicode_fs.lua')
$addedModules=$baseModules
$replacementModules=$baseModules
$permittedModules=$baseModules
function Child([string]$Root,[string]$Relative){
    if([string]::IsNullOrWhiteSpace($Relative) -or [IO.Path]::IsPathRooted($Relative) -or $Relative -match '(^|[\\/])\.\.?([\\/]|$)|:|[\x00-\x1f]'){throw "Unsafe relative path: $Relative"}
    $base=[IO.Path]::GetFullPath($Root).TrimEnd('\','/')
    $full=[IO.Path]::GetFullPath((Join-Path $base $Relative))
    if(-not $full.StartsWith($base+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Path escaped its root'}
    return $full
}
function No-Link([string]$Path){
    $current=[IO.Path]::GetFullPath($Path)
    while($current){
        if(Test-Path -LiteralPath $current){if((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw "Refusing reparse point: $current"}}
        $parent=Split-Path -Parent $current;if($parent -eq $current){break};$current=$parent
    }
}
function Sha([string]$Path){No-Link $Path;return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Json([string]$Path){No-Link $Path;return (Get-Content -Raw -Encoding UTF8 -LiteralPath $Path|ConvertFrom-Json)}
function Stopped {
    foreach($process in @(Get-Process -Name EotU,EotU-Win64-Shipping -ErrorAction SilentlyContinue)){
        $path=$null;try{$path=$process.Path}catch{}
        if(-not $path){throw '无法确认游戏进程路径。请关闭游戏后再更新；未终止任何进程。'}
        if($path.StartsWith($script:GameRoot+'\',[StringComparison]::OrdinalIgnoreCase)){throw '目标游戏仍在运行。请保存并退出游戏后重试；不需要准备卸载或清除加点。'}
    }
}
function Fresh-Bytes([string]$Path,[byte[]]$Bytes){
    No-Link $Path
    $stream=New-Object IO.FileStream($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try{$stream.Write($Bytes,0,$Bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
}
function Fresh-Json([string]$Path,$Value){Fresh-Bytes $Path ($utf8.GetBytes(($Value|ConvertTo-Json -Depth 12)))}
function Copy-Exact([string]$From,[string]$To,[string]$Hash){
    No-Link $To
    if((Sha $From) -ne $Hash){throw "Source hash mismatch: $From"}
    [IO.File]::Copy($From,$To,$false)
    if((Sha $To) -ne $Hash){throw "Backup/staging hash mismatch: $To"}
}
function Atomic-Replace([string]$From,[string]$To,[string]$Before,[string]$After){
    Stopped
    if((Sha $To) -ne $Before -or (Sha $From) -ne $After){throw 'File changed before replacement; refusing overwrite.'}
    $temp=Child (Split-Path -Parent $To) ('.eaa-'+[Guid]::NewGuid().ToString('N').Substring(0,16)+'.tmp')
    $swapBackup=Child (Split-Path -Parent $To) ('.eaa-old-'+[Guid]::NewGuid().ToString('N').Substring(0,16)+'.tmp')
    No-Link $swapBackup
    if(Test-Path -LiteralPath $swapBackup){throw 'Atomic replacement backup already exists.'}
    try{
        Copy-Exact $From $temp $After
        Stopped
        if((Sha $To) -ne $Before){throw 'Destination changed during staging.'}
        [IO.File]::Replace($temp,$To,$swapBackup)
        if((Sha $swapBackup) -ne $Before){throw 'Atomic preimage backup verification failed.'}
        if((Sha $To) -ne $After){throw 'Atomic replacement verification failed.'}
    }finally{
        if((Test-Path -LiteralPath $temp -PathType Leaf) -and (Sha $temp) -eq $After){Remove-Item -LiteralPath $temp}
        if((Test-Path -LiteralPath $swapBackup -PathType Leaf) -and (Sha $swapBackup) -eq $Before){Remove-Item -LiteralPath $swapBackup}
    }
}
function Atomic-Create([string]$From,[string]$To,[string]$After,[string]$Receipt,[string]$Relative){
    Stopped;No-Link $To
    if(Test-Path -LiteralPath $To){throw 'New module path already exists; refusing overwrite.'}
    $temp=Child (Split-Path -Parent $To) ('.eaa-'+[Guid]::NewGuid().ToString('N').Substring(0,16)+'.tmp')
    try{
        Copy-Exact $From $temp $After
        Stopped;No-Link $To
        if(Test-Path -LiteralPath $To){throw 'New module appeared during staging; preserving it.'}
        [IO.File]::Move($temp,$To)
        if((Sha $To) -ne $After){throw 'New module verification failed.'}
        Fresh-Json $Receipt ([ordered]@{schema=1;path=$Relative;sha256=$After})
    }finally{
        if((Test-Path -LiteralPath $temp -PathType Leaf) -and (Sha $temp) -eq $After){Remove-Item -LiteralPath $temp}
    }
}
function File-Map($Manifest){
    if($Manifest.schema -ne 1 -or $Manifest.modId -cne $modId -or [string]$Manifest.appId -cne '463530' -or [string]$Manifest.buildId -cnotin @('26119497','26412732')){throw 'Unexpected release manifest.'}
    $modules=$baseModules
    switch([string]$Manifest.release){
      '0.1.13'{$modules=$baseModules[0..14]}
      {$_ -in @('0.1.14','0.1.15','0.1.16')}{$modules=$baseModules[0..19]}
      '0.1.17'{$modules=@($Manifest.files|Where-Object {$_.path -like 'EotU/Binaries/Win64/ue4ss/Mods/AllAttributes/Scripts/*.lua'}|ForEach-Object{[IO.Path]::GetFileName($_.path)});if($modules.Count -lt 27 -or $modules.Count -gt 31){throw 'Unrecognized 0.1.17 module count'}}
      '0.1.18'{if([string]$Manifest.buildId -cne '26412732'){throw '0.1.18 requires the tested current game build'}}
      default{throw 'Unsupported source release.'}
    }
    if(@($modules|Where-Object {$_ -cnotin $baseModules}).Count){throw 'Unknown Lua module'}
    $allowed=@('dwmapi.dll','ue4ss/LICENSE','ue4ss/UE4SS-settings.ini','ue4ss/UE4SS.dll','ue4ss/Mods/mods.txt')+@($modules|ForEach-Object{'ue4ss/Mods/AllAttributes/Scripts/'+$_})
    $map=@{}
    foreach($file in @($Manifest.files)){
      $p=[string]$file.path
      if(-not $p.StartsWith('EotU/Binaries/Win64/',[StringComparison]::Ordinal) -or $p.Substring(20) -cnotin $allowed -or $file.sha256 -notmatch '^[0-9a-f]{64}$' -or $file.length -lt 0 -or $map.ContainsKey($p)){throw 'Invalid/duplicate manifest file'}
      [void](Child $script:GameRoot $p);$map[$p]=$file
    }
    if($map.Count -ne $allowed.Count){throw 'Incomplete managed file set'}
    return $map
}
function Verify-Freeze($ToMap){
    # The release owner supplies the final freeze; candidate/source hashes are
    # never embedded in this updater. An unfinished freeze cannot install.
    $freeze=Json $script:FreezeManifest
    if($freeze.schema -ne 1 -or $freeze.state -cne 'frozen' -or $freeze.release -cne $toRelease){throw 'A final frozen 0.1.18 manifest is required; no files changed.'}
    $expected=$baseModules;$seen=@{}
    foreach($property in $freeze.moduleHashes.PSObject.Properties){
        $name=$property.Name;$hash=[string]$property.Value
        if($name -cnotin $expected -or $seen.ContainsKey($name) -or $hash -notmatch '^[0-9a-fA-F]{64}$'){throw 'Invalid final-freeze module set.'}
        $path='EotU/Binaries/Win64/ue4ss/Mods/AllAttributes/Scripts/'+$name
        if($ToMap[$path].sha256 -ne $hash){throw ('Package does not match the final freeze: '+$name)}
        $seen[$name]=$true
    }
    if($seen.Count -ne $expected.Count){throw 'Final freeze must cover all 31 modules.'}
    if($freeze.settingsSha256 -notmatch '^[0-9a-fA-F]{64}$' -or $ToMap['EotU/Binaries/Win64/ue4ss/UE4SS-settings.ini'].sha256 -ne $freeze.settingsSha256){throw 'Settings do not match the final freeze.'}
}
function Read-Spec {
    $bundle=Json (Child $script:PackageRoot 'update.json')
    if($bundle.schema -ne 2 -or $bundle.modId -cne $modId -or $bundle.toRelease -cne $toRelease -or $bundle.toManifest.release -cne $toRelease){throw 'Unexpected update route catalog'}
    $to=File-Map $bundle.toManifest;Verify-Freeze $to
    $manifest=Json (Child $script:PackageRoot 'manifest.json')
    if(($manifest|ConvertTo-Json -Depth 25 -Compress) -cne ($bundle.toManifest|ConvertTo-Json -Depth 25 -Compress)){throw 'Update target differs from package manifest'}
    $record=Json (Child $script:GameRoot $recordName)
    if($Action -eq 'Rollback'){
      $pending=Child $script:GameRoot $pendingName
      if(-not(Test-Path -LiteralPath $pending -PathType Leaf)){throw 'Rollback only recovers an interrupted update; completed downgrade is not supported.'}
      $ref=Json $pending;if($ref.modId -cne $modId){throw 'Unknown pending update'}
      $record=Json (Child (Backup-Path $ref.backup) 'record-before.json')
    }
    $matchedRoutes=@();$ids=@{}
    foreach($route in @($bundle.routes)){
      if($route.id -notmatch '^[A-Za-z0-9_-]{1,80}$' -or $ids.ContainsKey($route.id) -or $route.fromRelease -cne $route.fromManifest.release){throw 'Invalid duplicate route identity'};$ids[$route.id]=$true
      $from=File-Map $route.fromManifest
      if($record.release -cne $route.fromRelease -or [string]$record.buildId -cne [string]$route.fromManifest.buildId -or @($record.files).Count -ne $from.Count){continue}
      $seen=@{};$same=$true
      foreach($f in @($record.files)){if(-not $from.ContainsKey($f.path) -or $seen.ContainsKey($f.path) -or $f.sha256 -cne $from[$f.path].sha256 -or $f.length -ne $from[$f.path].length){$same=$false;break};$seen[$f.path]=$true}
      if($same){$matchedRoutes+=@($route)}
    }
    if($matchedRoutes.Count -ne 1){throw 'No unique supported baseline matches the complete installation record. Preserve files and supply diagnostics.'}
    $route=$matchedRoutes[0];$from=File-Map $route.fromManifest;$expected=@();$seen=@{}
    foreach($p in $from.Keys){if(-not $to.ContainsKey($p)){throw 'Updates cannot remove managed files'}}
    foreach($p in $to.Keys){
      if(-not $from.ContainsKey($p) -or $from[$p].sha256 -cne $to[$p].sha256){
        if($p -cnotin @($permittedModules|ForEach-Object{'EotU/Binaries/Win64/ue4ss/Mods/AllAttributes/Scripts/'+$_})){throw 'Loader/configuration changes are not permitted'};$expected+=@($p)
      }elseif($from[$p].length -ne $to[$p].length){throw 'Unchanged file length differs'}
    }
    foreach($entry in @($route.changes)){
      $p=$entry.path
      if($p -cnotin $expected -or $seen.ContainsKey($p) -or $entry.newSha256 -cne $to[$p].sha256){throw 'Invalid change list'}
      if($from.ContainsKey($p)){if($entry.operation -cne 'replace' -or $entry.oldSha256 -cne $from[$p].sha256){throw 'Invalid replacement preimage'}}
      elseif($entry.operation -cne 'add' -or $null -ne $entry.oldSha256){throw 'Invalid added-file preimage'}
      $seen[$p]=$true
    }
    if($seen.Count -eq 0 -or $seen.Count -ne $expected.Count){throw 'Change list differs from exact manifest delta'}
    foreach($p in $to.Keys){$src=Child (Child $script:PackageRoot 'payload') $p;if((Sha $src) -cne $to[$p].sha256 -or (Get-Item -LiteralPath $src).Length -ne $to[$p].length){throw 'Full target payload integrity failed'}}
    return [pscustomobject]@{schema=1;modId=$modId;fromRelease=$route.fromRelease;toRelease=$toRelease;fromManifest=$route.fromManifest;toManifest=$bundle.toManifest;changes=$route.changes;routeId=$route.id}
}
function Verify-Game($Manifest){
    $paths=@('EotU.exe','EotU/Binaries/Win64/EotU-Win64-Shipping.exe','EotU/Content/Paks/pakchunk0-WindowsNoEditor.pak')
    $seen=@{}
    Write-Host '正在只读核对游戏版本与主资源包，请稍候。'
    foreach($item in @($Manifest.gameChecks)){
        if($item.path -notin $paths -or $seen.ContainsKey($item.path) -or $item.sha256 -notmatch '^[0-9a-fA-F]{64}$'){throw 'Invalid game compatibility list.'}
        $seen[$item.path]=$true
        if((Sha (Child $script:GameRoot $item.path)) -ne $item.sha256){throw 'Game executable/resource differs from the tested build.'}
    }
    if($seen.Count -ne 3){throw 'Incomplete game compatibility list.'}
    $common=Split-Path -Parent $script:GameRoot;$steamApps=Split-Path -Parent $common
    if((Split-Path -Leaf $common) -ne 'common' -or (Split-Path -Leaf $steamApps) -ne 'steamapps'){throw 'Choose the installed Steam game directory.'}
    $acf=Join-Path $steamApps 'appmanifest_463530.acf';No-Link $acf;$text=[IO.File]::ReadAllText($acf)
    if($text -notmatch '"buildid"\s+"(?<build>[0-9]+)"' -or $Matches.build -ne $Manifest.buildId){throw 'Steam build does not match.'}
    if($text -notmatch '"installdir"\s+"(?<dir>[^"\r\n]+)"' -or $Matches.dir -ne (Split-Path -Leaf $script:GameRoot)){throw 'Steam game directory does not match.'}
}
function Verify-Installation($Record,$Manifest){
    if($Record.schema -ne 1 -or $Record.modId -ne $modId -or $Record.gameRoot -ne $script:GameRoot -or $Record.release -ne $Manifest.release -or $Record.buildId -ne $Manifest.buildId -or -not $Record.PSObject.Properties['saveGamesRoot']){throw 'Existing installation record/version does not match the expected release.'}
    $map=File-Map $Manifest;$recordMap=@{}
    foreach($entry in @($Record.files)){
        $p=$entry.path.Replace('\','/')
        if(-not $map.ContainsKey($p) -or $recordMap.ContainsKey($p) -or $entry.sha256 -ne $map[$p].sha256 -or $entry.length -ne $map[$p].length){throw 'Existing installation record has unknown changes.'}
        $recordMap[$p]=$true
        if((Sha (Child $script:GameRoot $p)) -ne $map[$p].sha256 -or (Get-Item -LiteralPath (Child $script:GameRoot $p)).Length -ne $map[$p].length){throw "Installed file changed; preserving it: $p"}
    }
    if($recordMap.Count -ne $map.Count){throw 'Existing installation record is incomplete.'}
}
function Backup-Path([string]$Relative){
    $normal=$Relative.Replace('\','/')
    if($normal -notmatch '^\.eaa-update-backups/[A-Za-z0-9_-]{1,40}$'){throw 'Invalid update backup path.'}
    return Child $script:GameRoot $normal
}
function Backup-Module([string]$Backup,[string]$Area,[string]$Relative){
    $name=[IO.Path]::GetFileName($Relative)
    if($Area -notin @('old','new') -or $name -notin $permittedModules){throw 'Invalid module backup identity.'}
    return Child (Child $Backup $Area) $name
}
function Addition-Receipt([string]$Backup,[string]$Relative){
    $name=[IO.Path]::GetFileName($Relative)
    if($name -notin $addedModules){throw 'Invalid added-module receipt identity.'}
    return Child $Backup ('created-'+$name+'.json')
}
function Recover($Spec,[string]$BackupRelative,[bool]$CheckRosterCompatibility=$false){
    Stopped
    $backup=Backup-Path $BackupRelative
    $journal=Json (Child $backup 'journal.json')
    if($journal.schema -ne 1 -or $journal.modId -ne $modId -or $journal.gameRoot -ne $script:GameRoot -or $journal.fromRelease -ne $Spec.fromRelease -or $journal.toRelease -ne $Spec.toRelease){throw 'Backup journal identity mismatch.'}
    $recordPath=Child $script:GameRoot $recordName
    $oldRecord=Child $backup 'record-before.json';$newRecord=Child $backup 'record-after.json'
    if((Sha $oldRecord) -ne $journal.oldRecordSha256 -or (Sha $newRecord) -ne $journal.newRecordSha256){throw 'Backup record was changed; refusing recovery.'}
    $old=Json $oldRecord;$after=Json $newRecord
    if($old.release -ne $Spec.fromRelease -or $after.release -ne $Spec.toRelease -or $old.gameRoot -ne $script:GameRoot -or $after.gameRoot -ne $script:GameRoot){throw 'Backup record release/target mismatch.'}
    $currentRecordHash=Sha $recordPath
    if($currentRecordHash -notin @($journal.oldRecordSha256,$journal.newRecordSha256)){throw 'Current installation record has unknown changes; no rollback writes performed.'}
    if($CheckRosterCompatibility -and -not(Test-Path -LiteralPath (Child $script:GameRoot $pendingName))){throw 'Only interrupted updates can be rolled back'}
    $fromMap=File-Map $Spec.fromManifest
    $changeMap=@{};foreach($entry in @($Spec.changes)){$changeMap[$entry.path]=$entry}
    foreach($path in $fromMap.Keys){
        $actual=Sha (Child $script:GameRoot $path)
        if($changeMap.ContainsKey($path)){
            $entry=$changeMap[$path]
            if($actual -notin @($entry.oldSha256,$entry.newSha256)){throw "Changed update target must be preserved: $path"}
            if((Sha (Backup-Module $backup 'old' $path)) -ne $entry.oldSha256){throw 'Old module backup hash mismatch.'}
        }elseif($actual -ne $fromMap[$path].sha256){throw "Shared/unmodified file changed; rollback stopped: $path"}
    }
    foreach($entry in @($Spec.changes|Where-Object operation -eq 'add')){
        $target=Child $script:GameRoot $entry.path;No-Link $target
        if((Test-Path -LiteralPath $target) -and (-not(Test-Path -LiteralPath $target -PathType Leaf) -or (Sha $target) -ne $entry.newSha256)){throw "Added module has unknown changes; rollback stopped: $($entry.path)"}
        if(Test-Path -LiteralPath $target){
            $receiptPath=Addition-Receipt $backup $entry.path
            if(-not(Test-Path -LiteralPath $receiptPath -PathType Leaf)){throw "Cannot prove this transaction created the added file; preserving it: $($entry.path)"}
            $receipt=Json $receiptPath
            if($receipt.schema -ne 1 -or $receipt.path -cne $entry.path -or $receipt.sha256 -cne $entry.newSha256){throw 'Added-module ownership receipt changed; recovery stopped before deletion.'}
        }
        if((Sha (Backup-Module $backup 'new' $entry.path)) -ne $entry.newSha256){throw 'Added-module staging backup mismatch.'}
    }
    foreach($entry in @($Spec.changes)){
        $target=Child $script:GameRoot $entry.path
        if($entry.operation -eq 'add'){
            if(Test-Path -LiteralPath $target){Stopped;if((Sha $target) -ne $entry.newSha256){throw 'New module changed before rollback deletion.'};Remove-Item -LiteralPath $target}
        }elseif((Sha $target) -eq $entry.newSha256){Atomic-Replace (Backup-Module $backup 'old' $entry.path) $target $entry.newSha256 $entry.oldSha256}
    }
    if((Sha $recordPath) -eq $journal.newRecordSha256){Atomic-Replace $oldRecord $recordPath $journal.newRecordSha256 $journal.oldRecordSha256}
    Verify-Installation (Json $recordPath) $Spec.fromManifest
    $pending=Child $script:GameRoot $pendingName
    if(Test-Path -LiteralPath $pending){
        $reference=Json $pending
        if($reference.modId -ne $modId -or $reference.backup -ne $BackupRelative){throw 'Pending journal changed; recovered files but kept the marker.'}
        Stopped;Remove-Item -LiteralPath $pending
    }
    Write-Host '已恢复更新前的模组文件和安装记录；存档、加点记录和加载器未改动。'
}

try{
    $script:GameRoot=[IO.Path]::GetFullPath($GameRoot).TrimEnd('\','/')
    $script:PackageRoot=[IO.Path]::GetFullPath($PackageRoot).TrimEnd('\','/')
    if([string]::IsNullOrWhiteSpace($FreezeManifest)){$script:FreezeManifest=Child $script:PackageRoot 'source-freeze.json'}
    else{$script:FreezeManifest=[IO.Path]::GetFullPath($FreezeManifest)}
    No-Link $script:GameRoot;No-Link $script:PackageRoot;Stopped
    $spec=Read-Spec
    $recordPath=Child $script:GameRoot $recordName
    $pendingPath=Child $script:GameRoot $pendingName
    if($Action -eq 'Rollback'){
        $relative=$null
        if(Test-Path -LiteralPath $pendingPath){$reference=Json $pendingPath;if($reference.modId -ne $modId){throw 'Unknown pending journal'};$relative=$reference.backup}
        else{$current=Json $recordPath;if(-not $current.PSObject.Properties['lastUpdateBackup']){throw 'No update backup is linked to this installation.'};$relative=$current.lastUpdateBackup}
        Recover $spec $relative $true
        exit 0
    }
    if(Test-Path -LiteralPath $pendingPath){throw '存在尚未完成的更新。请关闭游戏后先运行“撤回本次更新”。'}
    Verify-Game $spec.toManifest
    $record=Json $recordPath
    Verify-Installation $record $spec.fromManifest
    foreach($entry in @($spec.changes|Where-Object operation -eq 'add')){
        $target=Child $script:GameRoot $entry.path;No-Link $target
        if(Test-Path -LiteralPath $target){throw "New module path is occupied; preserving it: $($entry.path)"}
    }
    Stopped
    $backupRelative='.eaa-update-backups/'+[DateTime]::UtcNow.ToString('yyyyMMddHHmmss')+'-'+[Guid]::NewGuid().ToString('N').Substring(0,8)
    $backup=Backup-Path $backupRelative;No-Link $backup
    if(Test-Path -LiteralPath $backup){throw 'Backup directory already exists.'}
    [void][IO.Directory]::CreateDirectory($backup)
    $oldRecordHash=Sha $recordPath
    Copy-Exact $recordPath (Child $backup 'record-before.json') $oldRecordHash
    foreach($area in @('old','new')){[void][IO.Directory]::CreateDirectory((Child $backup $area))}
    foreach($entry in @($spec.changes)){
        if($entry.operation -eq 'replace'){Copy-Exact (Child $script:GameRoot $entry.path) (Backup-Module $backup 'old' $entry.path) $entry.oldSha256}
        Copy-Exact (Child (Child $script:PackageRoot 'payload') $entry.path) (Backup-Module $backup 'new' $entry.path) $entry.newSha256
    }
    $record.release=$spec.toRelease;$record.files=$spec.toManifest.files;$record.buildId=$spec.toManifest.buildId
    $record|Add-Member -NotePropertyName gameVersion -NotePropertyValue $spec.toManifest.gameVersion -Force
    $record|Add-Member -NotePropertyName lastUpdateBackup -NotePropertyValue $backupRelative -Force
    $record|Add-Member -NotePropertyName updatedUtc -NotePropertyValue ([DateTime]::UtcNow.ToString('o')) -Force
    Fresh-Json (Child $backup 'record-after.json') $record
    $newRecordHash=Sha (Child $backup 'record-after.json')
    $journal=[ordered]@{schema=1;modId=$modId;gameRoot=$script:GameRoot;fromRelease=$spec.fromRelease;toRelease=$spec.toRelease;oldRecordSha256=$oldRecordHash;newRecordSha256=$newRecordHash;changes=$spec.changes}
    Fresh-Json (Child $backup 'journal.json') $journal
    Stopped
    Fresh-Json $pendingPath ([ordered]@{schema=1;modId=$modId;backup=$backupRelative})
    try{
        foreach($entry in @($spec.changes)){
            if($entry.operation -eq 'add'){Atomic-Create (Backup-Module $backup 'new' $entry.path) (Child $script:GameRoot $entry.path) $entry.newSha256 (Addition-Receipt $backup $entry.path) $entry.path}
            else{Atomic-Replace (Backup-Module $backup 'new' $entry.path) (Child $script:GameRoot $entry.path) $entry.oldSha256 $entry.newSha256}
        }
        Atomic-Replace (Child $backup 'record-after.json') $recordPath $oldRecordHash $newRecordHash
        Verify-Installation (Json $recordPath) $spec.toManifest
        Stopped
        Remove-Item -LiteralPath $pendingPath
        $replacedCount=@($spec.changes|Where-Object operation -eq 'replace').Count
        $addedCount=@($spec.changes|Where-Object operation -eq 'add').Count
        $unchangedCount=@($spec.fromManifest.files).Count-$replacedCount
        Write-Host ("已更新至 "+$spec.toRelease+"。替换 "+$replacedCount+" 个模块、新增 "+$addedCount+" 个模块；其余 "+$unchangedCount+" 个受管文件不变；不需要 F8 准备卸载。")
        Write-Host ('旧文件与原安装记录备份：'+$backup)
    }catch{
        $cause=$_
        try{Recover $spec $backupRelative}catch{Write-Host ('自动恢复未完成：'+$_+'. 请保持游戏关闭，运行撤回更新入口；备份和更新日志均已保留。')}
        throw $cause
    }
    exit 0
}catch{Write-Error $_ -ErrorAction Continue;exit 1}
