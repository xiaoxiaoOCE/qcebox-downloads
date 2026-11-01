[CmdletBinding()]
param(
    [ValidateSet('Install','Uninstall','Status','Launch')][string]$Action = 'Status',
    [string]$GameRoot = 'F:\SteamLibrary\steamapps\common\Empires of the Undergrowth',
    [string]$PackageRoot = $PSScriptRoot,
    [string]$SaveGamesRoot = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'EotU\Saved\SaveGames')
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$modId = 'EotU.AllAttributes.v1'
$recordName = '.eotu-allattributes-install.json'
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Resolve-Child([string]$Root, [string]$Relative) {
    if ([string]::IsNullOrWhiteSpace($Relative) -or [IO.Path]::IsPathRooted($Relative) -or
        $Relative -match '(^|[\\/])\.\.?([\\/]|$)|:|[\x00-\x1f]') { throw "Unsafe relative path: $Relative" }
    $base = [IO.Path]::GetFullPath($Root).TrimEnd('\','/')
    $full = [IO.Path]::GetFullPath((Join-Path $base $Relative))
    if (-not $full.StartsWith($base + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw "Path is outside target: $Relative" }
    return $full
}
function Assert-NoReparse([string]$Path) {
    $current = [IO.Path]::GetFullPath($Path)
    while ($current) {
        if (Test-Path -LiteralPath $current) {
            if ((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Refusing a reparse point: $current" }
        }
        $parent = Split-Path -Parent $current
        if ($parent -eq $current) { break }
        $current = $parent
    }
}
function Hash-File([string]$Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Read-Json([string]$Path) { return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json) }
function Assert-Stopped {
    $running = @(Get-Process -Name 'EotU','EotU-Win64-Shipping' -ErrorAction SilentlyContinue)
    foreach ($process in $running) {
        $path = $null
        try { $path = $process.Path } catch { }
        if (-not $path) { throw 'Cannot verify a running game process path. Close the game before retrying.' }
        if ($path.StartsWith($script:GameRoot + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) {
            throw 'Please close this installation of Empires of the Undergrowth, then retry.'
        }
    }
}
function Get-RecordPath { return Resolve-Child $script:GameRoot $recordName }
function Release-Modules([string]$Release) {
    $lua=@('core.lua','extra.lua','groups.lua','main.lua','native.lua','sha256.lua','ui.lua')
    if($Release -in @('0.1.6','0.1.7','0.1.8')){return $lua+@('roster.lua','roster_catalog.lua','roster_state.lua','roster_runtime.lua','roster_ui.lua','roster_challenge.lua')}
    if($Release -eq '0.1.9'){return $lua+@('roster.lua','roster_catalog.lua','roster_state.lua','roster_runtime.lua','roster_ui.lua','roster_challenge.lua')+@('roster_home.lua')}
    if($Release -in @('0.1.10','0.1.11','0.1.12','0.1.13')){return (Release-Modules '0.1.9')+@('foreign_ui.lua')}
    if($Release -notmatch '^0\.1\.[0-5]$'){throw 'Unsupported installation release.'}
    return $lua
}
function Assert-AllowedPayload([string]$Relative,[string]$Release) {
    $p = $Relative.Replace('\','/')
    $prefix = 'EotU/Binaries/Win64/'
    if (-not $p.StartsWith($prefix, [StringComparison]::Ordinal)) { throw "Payload outside game binaries: $p" }
    $tail = $p.Substring($prefix.Length)
    $fixed = @('dwmapi.dll','ue4ss/UE4SS.dll','ue4ss/UE4SS-settings.ini','ue4ss/LICENSE','ue4ss/Mods/mods.txt')
    $lua = @(Release-Modules $Release)
    if ($fixed -contains $tail) { return }
    if ($tail.StartsWith('ue4ss/Mods/AllAttributes/Scripts/', [StringComparison]::Ordinal) -and
        $lua -contains $tail.Substring('ue4ss/Mods/AllAttributes/Scripts/'.Length)) { return }
    throw "File is not on the installer allowlist: $p"
}
function Read-Manifest {
    $manifest = Read-Json (Resolve-Child $script:PackageRoot 'manifest.json')
    if ($manifest.schema -ne 1 -or $manifest.modId -ne $modId -or $manifest.appId -ne '463530') { throw 'Unexpected package manifest.' }
    $seen = @{}
    foreach ($entry in @($manifest.files)) {
        Assert-AllowedPayload $entry.path $manifest.release
        $normalized=$entry.path.Replace('\','/')
        if ($entry.sha256 -notmatch '^[a-fA-F0-9]{64}$' -or $seen.ContainsKey($normalized)) { throw 'Invalid/duplicate package file.' }
        $seen[$normalized] = $true
        $source = Resolve-Child (Resolve-Child $script:PackageRoot 'payload') $entry.path
        Assert-NoReparse $source
        if (-not (Test-Path -LiteralPath $source -PathType Leaf) -or (Hash-File $source) -ne $entry.sha256) { throw "Package integrity check failed: $($entry.path)" }
    }
    if ($seen.Count -ne (5+@(Release-Modules $manifest.release).Count)) { throw 'Expected the exact version-specific release file set.' }
    return $manifest
}
function Assert-GameVersion($Manifest) {
    if (-not (Test-Path -LiteralPath $script:GameRoot -PathType Container)) { throw 'Game folder does not exist.' }
    Assert-NoReparse $script:GameRoot
    Write-Host '正在核对游戏版本、可执行文件和主资源包，请稍候。'
    $seenChecks = @{}
    foreach ($check in @($Manifest.gameChecks)) {
        if ($check.path -notin @('EotU.exe','EotU/Binaries/Win64/EotU-Win64-Shipping.exe','EotU/Content/Paks/pakchunk0-WindowsNoEditor.pak')) { throw 'Unexpected game version check.' }
        if ($seenChecks.ContainsKey($check.path) -or $check.sha256 -notmatch '^[a-fA-F0-9]{64}$') { throw 'Invalid/duplicate game compatibility check.' }
        $seenChecks[$check.path] = $true
        $exe = Resolve-Child $script:GameRoot $check.path
        Assert-NoReparse $exe
        if (-not (Test-Path -LiteralPath $exe -PathType Leaf) -or (Hash-File $exe) -ne $check.sha256) { throw "Game version differs from the tested build: $($check.path). No files changed." }
    }
    if ($seenChecks.Count -ne 3) { throw 'Incomplete executable/resource version checks.' }
    $commonDir = Split-Path -Parent $script:GameRoot
    $steamApps = Split-Path -Parent $commonDir
    if ((Split-Path -Leaf $commonDir) -ne 'common' -or (Split-Path -Leaf $steamApps) -ne 'steamapps') { throw 'Choose the installed Steam game folder under steamapps/common.' }
    $acf = Join-Path $steamApps 'appmanifest_463530.acf'
    Assert-NoReparse $acf
    if (-not (Test-Path -LiteralPath $acf -PathType Leaf)) { throw 'Steam game manifest is missing.' }
    $content = Get-Content -LiteralPath $acf -Raw
    if ($content -notmatch '"buildid"\s+"(?<build>[0-9]+)"' -or $Matches.build -ne $Manifest.buildId) { throw 'Steam build differs from the tested build. No files changed.' }
    if ($content -notmatch '"installdir"\s+"(?<dir>[^"\r\n]+)"' -or $Matches.dir -ne (Split-Path -Leaf $script:GameRoot)) { throw 'Steam installation folder does not match the manifest.' }
}
function Read-Record {
    $path = Get-RecordPath
    Assert-NoReparse $path
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    $record = Read-Json $path
    if ($record.schema -ne 1 -or $record.modId -ne $modId -or $record.gameRoot -ne $script:GameRoot) { throw 'Invalid installation record; refusing to change files.' }
    if (-not $record.PSObject.Properties['saveGamesRoot'] -or -not [IO.Path]::IsPathRooted($record.saveGamesRoot)) { throw 'Installation record has no valid save directory; no files changed.' }
    Assert-NoReparse $record.saveGamesRoot
    if (@($record.files).Count -ne (5+@(Release-Modules $record.release).Count)) { throw 'Incomplete installation record; refusing to change files.' }
    $seen = @{}
    foreach ($entry in @($record.files)) {
        Assert-AllowedPayload $entry.path $record.release
        $normalized = $entry.path.Replace('\','/')
        if ($entry.sha256 -notmatch '^[a-fA-F0-9]{64}$' -or $seen.ContainsKey($normalized)) { throw 'Invalid/duplicate installation file hash.' }
        $seen[$normalized] = $true
        [void](Resolve-Child $script:GameRoot $entry.path)
    }
    foreach ($relative in @($record.createdDirectories)) {
        $p = $relative.Replace('\','/')
        if ($p -notmatch '^EotU/Binaries/Win64/ue4ss(?:/Mods(?:/AllAttributes(?:/Scripts)?)?)?$') { throw 'Invalid created-directory record.' }
        [void](Resolve-Child $script:GameRoot $relative)
    }
    return $record
}
function Write-Record($Record) {
    $path = Get-RecordPath
    $stream = New-Object IO.FileStream($path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        $bytes = $utf8.GetBytes(($Record | ConvertTo-Json -Depth 8))
        $stream.Write($bytes,0,$bytes.Length)
        $stream.Flush($true)
    } finally { $stream.Dispose() }
}
function Install-Mod {
    Assert-Stopped
    $manifest = Read-Manifest
    Assert-GameVersion $manifest
    if (Read-Record) { throw 'An installation record already exists. Use Status or Uninstall first.' }
    $bin = Resolve-Child $script:GameRoot 'EotU/Binaries/Win64'
    foreach ($conflict in @('dwmapi.dll','ue4ss','UE4SS.dll','UE4SS-settings.ini','Mods')) {
        $path = Resolve-Child $bin $conflict
        Assert-NoReparse $path
        if (Test-Path -LiteralPath $path) { throw "Existing loader/mod content must be preserved: $path. Nothing was overwritten." }
    }
    foreach ($entry in @($manifest.files)) {
        $target = Resolve-Child $script:GameRoot $entry.path
        Assert-NoReparse $target
        if (Test-Path -LiteralPath $target) { throw "Existing file must be preserved: $target" }
    }
    $createdFiles = New-Object System.Collections.Generic.List[object]
    $createdDirs = New-Object System.Collections.Generic.List[string]
    $plannedDirs = @('EotU/Binaries/Win64/ue4ss','EotU/Binaries/Win64/ue4ss/Mods','EotU/Binaries/Win64/ue4ss/Mods/AllAttributes','EotU/Binaries/Win64/ue4ss/Mods/AllAttributes/Scripts')
    Assert-NoReparse $script:SaveGamesRoot
    $record = [ordered]@{schema=1;modId=$modId;release=$manifest.release;gameRoot=$script:GameRoot;saveGamesRoot=$script:SaveGamesRoot;buildId=$manifest.buildId;installedUtc=[DateTime]::UtcNow.ToString('o');files=@($manifest.files);createdDirectories=$plannedDirs}
    # Journal the exact absent targets before copying, so an interrupted install is reversible.
    Write-Record $record
    $journalHash = Hash-File (Get-RecordPath)
    try {
        foreach ($relative in $plannedDirs) {
            $dir = Resolve-Child $script:GameRoot $relative
            Assert-NoReparse $dir
            if (Test-Path -LiteralPath $dir) { throw "Unexpected directory appeared during installation: $dir" }
            [void][IO.Directory]::CreateDirectory($dir)
            $createdDirs.Add($relative)
        }
        foreach ($entry in @($manifest.files)) {
            $source = Resolve-Child (Resolve-Child $script:PackageRoot 'payload') $entry.path
            $target = Resolve-Child $script:GameRoot $entry.path
            Assert-NoReparse $target
            [IO.File]::Copy($source,$target,$false)
            $createdFiles.Add($entry)
            if ((Hash-File $target) -ne $entry.sha256) { throw "Installed hash mismatch: $($entry.path)" }
        }
        Write-Output 'Installed and hash-verified. Original game executables, PAKs and saves were not changed.'
    } catch {
        $cause = $_
        foreach ($entry in @($createdFiles.ToArray())) {
            $target = Resolve-Child $script:GameRoot $entry.path
            Assert-NoReparse $target
            if ((Test-Path -LiteralPath $target -PathType Leaf) -and (Hash-File $target) -eq $entry.sha256) { Remove-Item -LiteralPath $target }
        }
        foreach ($relative in @($createdDirs.ToArray() | Sort-Object Length -Descending)) {
            $dir = Resolve-Child $script:GameRoot $relative
            Assert-NoReparse $dir
            if ((Test-Path -LiteralPath $dir -PathType Container) -and @(Get-ChildItem -LiteralPath $dir -Force).Count -eq 0) { [IO.Directory]::Delete($dir,$false) }
        }
        $remaining = @($manifest.files | Where-Object { Test-Path -LiteralPath (Resolve-Child $script:GameRoot $_.path) })
        if ($remaining.Count -eq 0 -and (Hash-File (Get-RecordPath)) -eq $journalHash) { Remove-Item -LiteralPath (Get-RecordPath) }
        throw $cause
    }
}
function Read-BoundedLines([string]$Path) {
    Assert-NoReparse $Path
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.PSIsContainer -or $item.Length -gt 8388608) { throw 'Invalid or oversized mod save metadata; no files changed.' }
    $strictUtf8 = New-Object Text.UTF8Encoding($false,$true)
    $text = [IO.File]::ReadAllText($Path,$strictUtf8).Replace("`r`n","`n")
    if (-not $text.EndsWith("`n") -or $text.Contains("`r") -or $text.Contains([string][char]0)) { throw 'Invalid mod save metadata format; no files changed.' }
    $lines = @($text.Substring(0,$text.Length-1).Split([char]"`n"))
    if ($lines.Count -gt 100000) { throw 'Mod save metadata has too many records; no files changed.' }
    return ,$lines
}
function Test-Count([string]$Value,[bool]$Positive) {
    if ($Value -notmatch '^(0|[1-9][0-9]{0,9})$') { return $false }
    $number = [long]$Value
    return $number -le 2147483647 -and ((-not $Positive) -or $number -gt 0)
}
function Read-UpgradeSlots([string]$Ledger) {
    $lines = Read-BoundedLines $Ledger
    if ($lines.Count -lt 2 -or $lines[0] -ne "EOTU_ALL_ATTRIBUTES`t1" -or $lines[1] -notmatch '^REV\t(0|[1-9][0-9]{0,9})$' -or -not (Test-Count $Matches[1] $false)) { throw 'Invalid upgrade ledger header; no files changed.' }
    $slots = @{}
    for ($i=2; $i -lt $lines.Count; $i++) {
        $f = @($lines[$i].Split([char]"`t"))
        if ($f.Count -lt 3 -or $f[1] -notmatch '^[A-Za-z0-9_-]{1,64}$') { throw 'Invalid ledger slot record; no files changed.' }
        $slot = $f[1]
        switch ($f[0]) {
            'SLOT' {
                if ($f.Count -ne 3 -or $f[2] -cnotmatch '^[0-9a-f]{64}:[0-9a-f]{64}$' -or $slots.ContainsKey($slot)) { throw 'Invalid/duplicate ledger slot; no files changed.' }
                $slots[$slot] = @{anchor=$f[2];points=@{};snapshots=@{}}
            }
            'SNAP' {
                if ($f.Count -ne 3 -or -not $slots.ContainsKey($slot) -or $f[2] -cnotmatch '^[0-9a-f]{64}:[0-9a-f]{64}$' -or $slots[$slot].snapshots.ContainsKey($f[2])) { throw 'Invalid ledger snapshot; no files changed.' }
                $slots[$slot].snapshots[$f[2]] = @{}
            }
            { $_ -in @('POINT','SNAPPOINT') } {
                $offset = 0
                if ($f[0] -eq 'SNAPPOINT') { $offset = 1 }
                if ($f.Count -ne (5+$offset) -or -not $slots.ContainsKey($slot)) { throw 'Invalid ledger point record; no files changed.' }
                $species=$f[2+$offset];$stat=$f[3+$offset];$count=$f[4+$offset]
                if ($species -notmatch '^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$' -or $stat -notmatch '^[A-Za-z0-9][A-Za-z0-9_.:-]{0,63}$' -or -not (Test-Count $count $true)) { throw 'Invalid ledger point value; no files changed.' }
                $points=$slots[$slot].points
                if ($offset -eq 1) {
                    if (-not $slots[$slot].snapshots.ContainsKey($f[2])) { throw 'Unknown ledger snapshot; no files changed.' }
                    $points=$slots[$slot].snapshots[$f[2]]
                }
                $key=$species+"`t"+$stat
                if ($points.ContainsKey($key)) { throw 'Duplicate ledger point; no files changed.' }
                $points[$key]=[long]$count
            }
            default { throw 'Unknown upgrade ledger record; no files changed.' }
        }
    }
    foreach ($slot in $slots.Keys) {
        $data=$slots[$slot]
        if (-not $data.snapshots.ContainsKey($data.anchor)) { throw 'Ledger lacks its saved snapshot; no files changed.' }
        $snapshot=$data.snapshots[$data.anchor]
        if ($data.points.Count -ne $snapshot.Count) { throw 'Ledger current points do not match its saved snapshot; no files changed.' }
        foreach ($key in $data.points.Keys) { if (-not $snapshot.ContainsKey($key) -or $snapshot[$key] -ne $data.points[$key]) { throw 'Ledger points differ from saved snapshot; no files changed.' } }
    }
    return $slots
}
function Assert-UninstallPrepared($Record) {
    $saveRoot=[IO.Path]::GetFullPath($Record.saveGamesRoot).TrimEnd('\','/')
    Assert-NoReparse $saveRoot
    $ledger=Resolve-Child $saveRoot 'EAA_AllAttributes_v1.tsv'
    if (Test-Path -LiteralPath ($ledger+'.pending')) { throw 'A mod purchase/save is pending. Recover it in game before uninstalling; no files changed.' }
    if (-not (Test-Path -LiteralPath $ledger)) {
        foreach ($suffix in @('.bak','.tmp')) { if (Test-Path -LiteralPath ($ledger+$suffix)) { throw 'Upgrade ledger is missing but recovery data exists. Recover the ledger before uninstalling; no files changed.' } }
        if (Test-Path -LiteralPath (Resolve-Child $saveRoot 'EAA_AllAttributes_v1.uninstall-ready.tsv')) { throw 'Upgrade ledger is missing while an uninstall marker remains. Recover the matching ledger before uninstalling; no files changed.' }
        return
    }
    $slots=Read-UpgradeSlots $ledger
    $active=@($slots.Keys|Where-Object {$slots[$_].points.Count -gt 0})
    if ($active.Count -eq 0) { return }
    $marker=Resolve-Child $saveRoot 'EAA_AllAttributes_v1.uninstall-ready.tsv'
    $instruction='请分别载入列出的殖民地蚁巢，打开小幅改进窗口按 F6，确认没有待购买点数后按 F8 准备卸载，然后退出游戏并重试。'
    if (-not (Test-Path -LiteralPath $marker -PathType Leaf)) { throw ("Uninstall preparation is required for: "+($active -join ', ')+". "+$instruction+" No files changed.") }
    $lines=Read-BoundedLines $marker
    if ($lines.Count -lt 1 -or $lines[0] -ne 'EAA_UNINSTALL_READY_V1') { throw 'Invalid uninstall preparation marker; no files changed.' }
    $ready=@{}
    for ($i=1;$i -lt $lines.Count;$i++) {
        $f=@($lines[$i].Split([char]"`t"))
        if ($f.Count -ne 3 -or $f[0] -ne 'SLOT' -or $f[1] -notmatch '^[A-Za-z0-9_-]{1,64}$' -or $f[2] -cnotmatch '^[0-9a-f]{64}:[0-9a-f]{64}$' -or $ready.ContainsKey($f[1])) { throw 'Invalid/duplicate uninstall preparation record; no files changed.' }
        $ready[$f[1]]=$f[2]
    }
    foreach ($slot in $active) {
        if (-not $ready.ContainsKey($slot) -or $ready[$slot] -cne $slots[$slot].anchor) { throw ("Colony "+$slot+" has not been prepared for this saved upgrade state. "+$instruction+" No files changed.") }
        $main=Resolve-Child $saveRoot ($slot+'.sav');$level=Resolve-Child $saveRoot ($slot+'LevelData.sav')
        Assert-NoReparse $main;Assert-NoReparse $level
        if (-not(Test-Path -LiteralPath $main -PathType Leaf) -or -not(Test-Path -LiteralPath $level -PathType Leaf)) { throw ("Prepared colony save pair is missing: "+$slot+". No files changed.") }
        $actual=(Hash-File $main)+':'+(Hash-File $level)
        if ($actual -cne $ready[$slot]) { throw ("Colony "+$slot+" changed after uninstall preparation. "+$instruction+" No files changed.") }
    }
}
function Uninstall-Mod {
    Assert-Stopped
    $record = Read-Record
    if (-not $record) { throw 'No installation record exists; nothing was removed.' }
    Assert-UninstallPrepared $record
    $preserved = New-Object System.Collections.Generic.List[string]
    $removed = 0
    # Validate every target before the first removal. Never follow links or delete outside the game.
    foreach ($entry in @($record.files)) { Assert-NoReparse (Resolve-Child $script:GameRoot $entry.path) }
    foreach ($relative in @($record.createdDirectories)) { Assert-NoReparse (Resolve-Child $script:GameRoot $relative) }
    # The loader is shared infrastructure. Never remove it underneath newly added mods
    # or a user-edited loader configuration. Reject before deleting even one file.
    $managedPaths = @{}
    foreach ($entry in @($record.files)) { $managedPaths[$entry.path.Replace('\','/')] = $true }
    $managedDirs = @{}
    foreach ($relative in @($record.createdDirectories)) { $managedDirs[$relative.Replace('\','/')] = $true }
    $modsRoot = Resolve-Child $script:GameRoot 'EotU/Binaries/Win64/ue4ss/Mods'
    if (Test-Path -LiteralPath $modsRoot -PathType Container) {
        $pendingDirs = New-Object System.Collections.Generic.Stack[string]
        $pendingDirs.Push($modsRoot)
        while ($pendingDirs.Count -gt 0) {
            $parent = $pendingDirs.Pop()
            Assert-NoReparse $parent
            foreach ($item in @(Get-ChildItem -LiteralPath $parent -Force)) {
                Assert-NoReparse $item.FullName
                $relative = $item.FullName.Substring($script:GameRoot.Length + 1).Replace('\','/')
                if ($item.PSIsContainer) {
                    if (-not $managedDirs.ContainsKey($relative)) { throw "Additional mod directory detected: $relative. Uninstall stopped before any deletion to preserve the shared loader." }
                    $pendingDirs.Push($item.FullName)
                } elseif (-not $managedPaths.ContainsKey($relative)) {
                    throw "Additional mod file detected: $relative. Uninstall stopped before any deletion to preserve the shared loader."
                }
            }
        }
    }
    foreach ($entry in @($record.files)) {
        $relative = $entry.path.Replace('\','/')
        if ($relative.StartsWith('EotU/Binaries/Win64/ue4ss/Mods/AllAttributes/',[StringComparison]::Ordinal)) { continue }
        $target = Resolve-Child $script:GameRoot $entry.path
        if ((Test-Path -LiteralPath $target) -and (-not (Test-Path -LiteralPath $target -PathType Leaf) -or (Hash-File $target) -ne $entry.sha256)) {
            throw "Shared loader/configuration changed: $relative. Uninstall stopped before any deletion; all mods and their loader were preserved."
        }
    }
    foreach ($entry in @($record.files)) {
        $target = Resolve-Child $script:GameRoot $entry.path
        if (-not (Test-Path -LiteralPath $target)) { continue }
        if (-not (Test-Path -LiteralPath $target -PathType Leaf) -or (Hash-File $target) -ne $entry.sha256) { $preserved.Add($entry.path); continue }
        Remove-Item -LiteralPath $target
        $removed++
    }
    foreach ($relative in @($record.createdDirectories | Sort-Object Length -Descending)) {
        $dir = Resolve-Child $script:GameRoot $relative
        if ((Test-Path -LiteralPath $dir -PathType Container) -and @(Get-ChildItem -LiteralPath $dir -Force).Count -eq 0) { [IO.Directory]::Delete($dir,$false) }
    }
    if ($preserved.Count -gt 0) {
        Write-Output "Removed $removed unchanged installed files. Preserved changed files and the installation record:"
        $preserved | Write-Output
        throw 'Uninstall was partial because installed files were changed. Saves and mod data were preserved.'
    }
    Remove-Item -LiteralPath (Get-RecordPath)
    Write-Output "Uninstalled $removed matching files. Original files, saves, mod upgrade records, and unknown/generated files were preserved."
}
function Show-Status {
    $record = Read-Record
    if (-not $record) { Write-Host 'Not installed by this package.'; return $false }
    $bad = @()
    foreach ($entry in @($record.files)) {
        $target = Resolve-Child $script:GameRoot $entry.path
        Assert-NoReparse $target
        if (-not (Test-Path -LiteralPath $target -PathType Leaf) -or (Hash-File $target) -ne $entry.sha256) { $bad += $entry.path }
    }
    if ($bad.Count) { $bad | Write-Host; throw 'Installation is missing files or has changed; launch refused.' }
    Write-Host "Installed release $($record.release); all $(@($record.files).Count) file hashes match."
    return $true
}

try {
    $script:GameRoot = [IO.Path]::GetFullPath($GameRoot).TrimEnd('\','/')
    $script:PackageRoot = [IO.Path]::GetFullPath($PackageRoot).TrimEnd('\','/')
    $script:SaveGamesRoot = [IO.Path]::GetFullPath($SaveGamesRoot).TrimEnd('\','/')
    switch ($Action) {
        'Install' { Install-Mod }
        'Uninstall' { Uninstall-Mod }
        'Status' { [void](Show-Status) }
        'Launch' {
            Assert-Stopped
            $manifest = Read-Manifest
            Assert-GameVersion $manifest
            if (-not (Show-Status)) { throw 'Install this package before launching.' }
            Start-Process -FilePath 'steam://rungameid/463530' | Out-Null
            Write-Output 'Launch request sent to Steam.'
        }
    }
    exit 0
} catch { Write-Error $_ -ErrorAction Continue; exit 1 }
