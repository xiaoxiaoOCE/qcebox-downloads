[CmdletBinding()]
param(
    [ValidateSet('Update','Rollback')][string]$Action='Update',
    [string]$GameRoot='F:\SteamLibrary\steamapps\common\Empires of the Undergrowth',
    [string]$PackageRoot=$PSScriptRoot
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$utf8=New-Object Text.UTF8Encoding($false)
$recordName='.eotu-allattributes-install.json'
$pendingName='.eotu-allattributes-update-pending.json'
$modId='EotU.AllAttributes.v1'
$fromRelease='0.1.12'
$toRelease='0.1.13'
$baseModules=@('core.lua','extra.lua','groups.lua','main.lua','native.lua','sha256.lua','ui.lua','roster.lua','roster_catalog.lua','roster_state.lua','roster_runtime.lua','roster_ui.lua','roster_challenge.lua','roster_home.lua','foreign_ui.lua')
$addedModules=@()
$permittedModules=@('main.lua')+$addedModules
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
    if($Manifest.schema -ne 1 -or $Manifest.modId -ne $modId -or $Manifest.appId -ne '463530' -or $Manifest.buildId -ne '26119497'){throw 'Unexpected release manifest.'}
    $map=@{}
    $allowed=@('dwmapi.dll','ue4ss/LICENSE','ue4ss/UE4SS-settings.ini','ue4ss/UE4SS.dll','ue4ss/Mods/mods.txt')
    $modules=$baseModules
    if($Manifest.release -eq $toRelease){$modules=$baseModules+$addedModules}
    elseif($Manifest.release -ne $fromRelease){throw 'Unexpected manifest release.'}
    $allowed+=@($modules|ForEach-Object{'ue4ss/Mods/AllAttributes/Scripts/'+$_})
    foreach($file in @($Manifest.files)){
        $p=$file.path.Replace('\','/')
        if(-not $p.StartsWith('EotU/Binaries/Win64/',[StringComparison]::Ordinal) -or $p.Substring(20) -notin $allowed -or $file.sha256 -notmatch '^[0-9a-fA-F]{64}$' -or $map.ContainsKey($p)){throw "Invalid/duplicate release file: $p"}
        $map[$p]=$file
    }
    if($map.Count -ne $allowed.Count){throw 'Release manifest must contain its exact known file set.'}
    return $map
}
function Read-Spec {
    $spec=Json (Child $script:PackageRoot 'update.json')
    if($spec.schema -ne 1 -or $spec.modId -ne $modId -or $spec.fromRelease -ne $fromRelease -or $spec.toRelease -ne $toRelease){throw 'Unexpected update route.'}
    if($spec.fromManifest.release -ne $spec.fromRelease -or $spec.toManifest.release -ne $spec.toRelease){throw 'Release metadata mismatch.'}
    $from=File-Map $spec.fromManifest;$to=File-Map $spec.toManifest
    $expected=@()
    foreach($path in $from.Keys){if(-not $to.ContainsKey($path)){throw 'Update cannot remove files.'}}
    foreach($path in $to.Keys){
        if(-not $from.ContainsKey($path)){
            if([IO.Path]::GetFileName($path) -notin $addedModules){throw 'Unexpected added module.'}
            $expected+=$path
        }elseif($from[$path].sha256 -ne $to[$path].sha256){
            if($path -notin @($permittedModules|ForEach-Object{'EotU/Binaries/Win64/ue4ss/Mods/AllAttributes/Scripts/'+$_})){throw 'This home-production update cannot replace other mod/loader components.'}
            $expected+=$path
        }
    }
    $seen=@{}
    foreach($entry in @($spec.changes)){
        $path=$entry.path.Replace('\','/')
        if($path -notin $expected -or $seen.ContainsKey($path) -or $entry.newSha256 -ne $to[$path].sha256){throw 'Invalid change list.'}
        if($from.ContainsKey($path)){
            if($entry.operation -ne 'replace' -or $entry.oldSha256 -ne $from[$path].sha256){throw 'Invalid replacement preimage.'}
        }elseif($entry.operation -ne 'add' -or $null -ne $entry.oldSha256){throw 'Added files must have an absent preimage.'}
        $seen[$path]=$true
        $source=Child (Child $script:PackageRoot 'payload') $path
        if((Sha $source) -ne $entry.newSha256){throw 'Update payload integrity failed.'}
    }
    if($seen.Count -ne 1 -or $seen.Count -ne $expected.Count){throw 'Expected exactly the single reviewed reward-preview performance module; no additions or removals.'}
    return $spec
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
        if(-not $map.ContainsKey($p) -or $recordMap.ContainsKey($p) -or $entry.sha256 -ne $map[$p].sha256){throw 'Existing installation record has unknown changes.'}
        $recordMap[$p]=$true
        if((Sha (Child $script:GameRoot $p)) -ne $map[$p].sha256){throw "Installed file changed; preserving it: $p"}
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
function Assert-OldRosterCompatible($Record){
    # 0.1.12 already reads all four DLC UNIT IDs; this barrier applies only to older targets.
    if([string]$Record.release -ne '0.1.11'){return}
    if(-not $Record.PSObject.Properties['saveGamesRoot'] -or -not [IO.Path]::IsPathRooted([string]$Record.saveGamesRoot)){throw '无法确认选兵记录目录，已停止撤回；未修改文件或存档。'}
    $saveRoot=[IO.Path]::GetFullPath([string]$Record.saveGamesRoot).TrimEnd('\','/');No-Link $saveRoot
    $newIds=@('ExplodingAnt','ExplodingAntMajorSoldier','ExplodingTermite','ExplodingTermiteSoldier')
    foreach($suffix in @('','.bak','.tmp')){
        $path=Child $saveRoot ('EAA_StoryRoster_v1.tsv'+$suffix);No-Link $path
        if(-not(Test-Path -LiteralPath $path)){continue}
        if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw '选兵记录路径不是文件，已停止撤回；未修改文件或存档。'}
        foreach($line in [IO.File]::ReadLines($path)){
            $fields=$line -split "`t"
            if($fields.Count -ge 2 -and $fields[0] -ceq 'UNIT' -and $fields[1] -in $newIds){throw '已有爆炸蚁 DLC 选兵记录（含历史快照或恢复副本），0.1.11 无法读取。请保留 0.1.12；本次未修改模组、选兵记录或存档。'}
        }
    }
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
    if($CheckRosterCompatibility){Assert-OldRosterCompatible $old}
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
    Verify-Game $spec.fromManifest
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
    $record.release=$spec.toRelease;$record.files=$spec.toManifest.files
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
