[CmdletBinding()]
param(
    [ValidateSet('Inspect','Install','Uninstall','AdoptManual')][string]$Action='Inspect',
    [AllowEmptyString()][string]$GameRoot='',
    [string]$PackageRoot=$PSScriptRoot,
    [Parameter(Mandatory=$true)][string]$ResultPath,
    [string]$SaveGamesRoot=(Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'EotU\Saved\SaveGames')
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$utf8=New-Object Text.UTF8Encoding($false)
[Console]::OutputEncoding=$utf8
$OutputEncoding=$utf8
$release='0.1.18'
$recordName='.eotu-allattributes-install.json'
$details=New-Object 'System.Collections.Generic.List[string]'
$result=[ordered]@{success=$false;message='';installed=$false;release='';gameRoot=$GameRoot;details=@();status='unknown';canInstall=$false;canUninstall=$false}
$exitCode=1
function Child([string]$Root,[string]$Relative) {
    if([string]::IsNullOrWhiteSpace($Relative) -or [IO.Path]::IsPathRooted($Relative) -or $Relative -match '(^|[\\/])\.\.?([\\/]|$)|:|[\x00-\x1f]'){throw '文件路径不安全，未继续操作。'}
    $base=[IO.Path]::GetFullPath($Root).TrimEnd('\','/')
    $full=[IO.Path]::GetFullPath((Join-Path $base $Relative))
    if(-not $full.StartsWith($base+'\',[StringComparison]::OrdinalIgnoreCase)){throw '文件路径超出目标目录。'}
    return $full
}
function NoLink([string]$Path) {
    $current=[IO.Path]::GetFullPath($Path)
    while($current){
        if(Test-Path -LiteralPath $current){if((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw '目标包含链接或目录联接，为保留原文件已停止。'}}
        $parent=Split-Path -Parent $current;if($parent -eq $current){break};$current=$parent
    }
}
function Sha([string]$Path){
    NoLink $Path
    $stream=[IO.File]::OpenRead($Path);$hasher=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($hasher.ComputeHash($stream))).Replace('-','').ToLowerInvariant()}
    finally{$stream.Dispose();$hasher.Dispose()}
}
function Json([string]$Path){NoLink $Path;return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)}
function Log([string]$Text){$script:details.Add($Text);Write-Output $Text}
function ExpectedPaths {
    $base='EotU/Binaries/Win64/'
    @('dwmapi.dll','ue4ss/UE4SS.dll','ue4ss/UE4SS-settings.ini','ue4ss/LICENSE','ue4ss/Mods/mods.txt')|ForEach-Object{$base+$_}
    @('core.lua','extra.lua','groups.lua','main.lua','native.lua','sha256.lua','ui.lua','roster.lua','roster_catalog.lua','roster_state.lua','roster_runtime.lua','roster_ui.lua','roster_challenge.lua','roster_home.lua','foreign_ui.lua','skills.lua','skills_state.lua','skills_runtime.lua','skills_ui.lua','skills_purchase.lua','slaver_controls_ui.lua','slaver_conversion.lua','slaver_conversion_animation.lua','slaver_damage_guard.lua','slaver_medical.lua','slaver_native.lua','slaver_runtime.lua','slaver_balance.lua','slaver_food.lua','slaver_objectives.lua','unicode_fs.lua')|ForEach-Object{$base+'ue4ss/Mods/AllAttributes/Scripts/'+$_}
}
function ReadManifest {
    $m=Json (Child $script:PackageRoot 'manifest.json')
    if($m.schema -ne 1 -or $m.modId -ne 'EotU.AllAttributes.v1' -or $m.appId -ne '463530' -or $m.release -ne $script:release){throw '安装包清单版本不正确。'}
    $allowed=@(ExpectedPaths);$seen=@{}
    foreach($f in @($m.files)){
        $p=$f.path.Replace('\','/')
        if($p -cnotin $allowed -or $seen.ContainsKey($p) -or $f.sha256 -notmatch '^[a-fA-F0-9]{64}$'){throw '安装包受管文件清单不完整或不正确。'}
        $seen[$p]=$true;[void](Child $script:GameRoot $p)
    }
    if($seen.Count -ne 36){throw '安装包必须包含完整的 36 个受管文件。'}
    return $m
}
function ReadRecord {
    $path=Child $script:GameRoot $script:recordName
    if(-not(Test-Path -LiteralPath $path)){return $null}
    $r=Json $path
    if($r.schema -ne 1 -or $r.modId -ne 'EotU.AllAttributes.v1' -or $r.gameRoot -ne $script:GameRoot){throw '安装记录不匹配，未改动已有文件。'}
    return $r
}
function SupportedUpdateRelease([string]$InstalledRelease) {
    if($InstalledRelease -eq $script:release){return $true}
    $path=Child $script:PackageRoot 'update.json'
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){return $false}
    $update=Json $path
    if($update.schema -ne 2 -or $update.modId -ne 'EotU.AllAttributes.v1' -or $update.toRelease -ne $script:release){throw '更新清单版本不正确。'}
    return @($update.routes | Where-Object {$_.fromRelease -eq $InstalledRelease}).Count -gt 0
}
function UpdateState {
    if(-not $script:GameRoot){return}
    $path=Child $script:GameRoot $script:recordName
    $script:result.installed=Test-Path -LiteralPath $path -PathType Leaf
    if($script:result.installed){$r=ReadRecord;$script:result.release=[string]$r.release}
}
function AssertStopped {
    foreach($p in @(Get-Process -Name EotU,EotU-Win64-Shipping -ErrorAction SilentlyContinue)){
        $path=$null;try{$path=$p.Path}catch{}
        if(-not $path){throw '无法确认游戏进程位置，请关闭游戏后重试。'}
        if($path.StartsWith($script:GameRoot+'\',[StringComparison]::OrdinalIgnoreCase)){throw '游戏仍在运行，请正常保存并退出后重试。'}
    }
}
function CheckGame($Manifest,[bool]$Full) {
    if(-not(Test-Path -LiteralPath $script:GameRoot -PathType Container)){throw '请选择已安装的地下蚁国游戏目录。'}
    NoLink $script:GameRoot
    foreach($p in @('EotU.exe','EotU/Binaries/Win64/EotU-Win64-Shipping.exe')){
        $path=Child $script:GameRoot $p;NoLink $path
        if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw '该目录缺少地下蚁国的可执行文件，请选择含 EotU.exe 的游戏根目录。'}
    }
    $common=Split-Path -Parent $script:GameRoot;$apps=Split-Path -Parent $common
    if((Split-Path -Leaf $common) -ne 'common' -or (Split-Path -Leaf $apps) -ne 'steamapps'){throw '请选择 Steam 库中 steamapps/common 下的游戏目录。'}
    $acf=Join-Path $apps 'appmanifest_463530.acf';NoLink $acf
    if(-not(Test-Path -LiteralPath $acf -PathType Leaf)){throw '未找到地下蚁国的 Steam 安装记录。'}
    $text=Get-Content -LiteralPath $acf -Raw
    if($text -notmatch '"buildid"\s+"(?<id>[0-9]+)"' -or $Matches.id -ne $Manifest.buildId){throw ('该游戏版本与模组支持的 Steam 构建 '+$Manifest.buildId+' 不同，未改动文件。')}
    if($text -notmatch '"installdir"\s+"(?<dir>[^"\r\n]+)"' -or $Matches.dir -ne (Split-Path -Leaf $script:GameRoot)){throw 'Steam 安装记录与所选目录不一致。'}
    if(-not $Full){return}
    Log '正在核对游戏版本和主资源包，请稍候。'
    $checks=@{}
    foreach($c in @($Manifest.gameChecks)){
        if($c.path -cnotin @('EotU.exe','EotU/Binaries/Win64/EotU-Win64-Shipping.exe','EotU/Content/Paks/pakchunk0-WindowsNoEditor.pak') -or $checks.ContainsKey($c.path) -or $c.sha256 -notmatch '^[a-fA-F0-9]{64}$'){throw '游戏兼容性清单不正确。'}
        $checks[$c.path]=$true;$path=Child $script:GameRoot $c.path
        if(-not(Test-Path -LiteralPath $path -PathType Leaf) -or (Sha $path) -ne $c.sha256){throw ('游戏文件与已验证版本不一致：'+$c.path+'。未改动文件。')}
    }
    if($checks.Count -ne 3){throw '缺少游戏版本完整性检查。'}
}
function AllTargetsMatch($Manifest) {
    foreach($f in @($Manifest.files)){$p=Child $script:GameRoot $f.path;if(-not(Test-Path -LiteralPath $p -PathType Leaf) -or (Sha $p) -ne $f.sha256){return $false}}
    return $true
}
function AssertManualExclusive($Manifest) {
    $allowed=@{};foreach($f in @($Manifest.files)){$allowed[$f.path.Replace('\','/')]=$true}
    $dirs=@('EotU/Binaries/Win64/ue4ss','EotU/Binaries/Win64/ue4ss/Mods','EotU/Binaries/Win64/ue4ss/Mods/AllAttributes','EotU/Binaries/Win64/ue4ss/Mods/AllAttributes/Scripts')
    $bin=Child $script:GameRoot 'EotU/Binaries/Win64'
    foreach($name in @('UE4SS.dll','UE4SS-settings.ini','Mods')){if(Test-Path -LiteralPath (Child $bin $name)){throw '检测到其他加载器布局，手动登记已停止，现有文件保留。'}}
    $pending=New-Object 'System.Collections.Generic.Stack[string]';$pending.Push((Child $script:GameRoot $dirs[0]))
    while($pending.Count){
        $dir=$pending.Pop();NoLink $dir
        foreach($item in @(Get-ChildItem -LiteralPath $dir -Force)){
            NoLink $item.FullName;$rel=$item.FullName.Substring($script:GameRoot.Length+1).Replace('\','/')
            if($item.PSIsContainer){if($rel -cnotin $dirs){throw ('检测到额外模组或共享目录，无法安全登记：'+$rel)};$pending.Push($item.FullName)}
            elseif(-not $allowed.ContainsKey($rel) -and $rel -cnotin @('EotU/Binaries/Win64/ue4ss/UE4SS.log','EotU/Binaries/Win64/ue4ss/UE4SS.log.old')){throw ('检测到未受管的加载器文件，无法安全登记：'+$rel)}
        }
    }
}
function Adopt($Manifest) {
    AssertStopped
    if(ReadRecord){throw '已有安装记录，请使用检查或卸载入口。'}
    CheckGame $Manifest $true
    if(-not(AllTargetsMatch $Manifest)){throw '手动安装文件不完整或已被修改；请先完整复制 ZIP 中的 EotU 文件夹，且不要覆盖其他加载器。未登记、未删除文件。'}
    AssertManualExclusive $Manifest
    NoLink $script:SaveGamesRoot
    $r=[ordered]@{schema=1;modId='EotU.AllAttributes.v1';release=$Manifest.release;gameRoot=$script:GameRoot;saveGamesRoot=$script:SaveGamesRoot;buildId=$Manifest.buildId;installedUtc=[DateTime]::UtcNow.ToString('o');files=@($Manifest.files);createdDirectories=@('EotU/Binaries/Win64/ue4ss','EotU/Binaries/Win64/ue4ss/Mods','EotU/Binaries/Win64/ue4ss/Mods/AllAttributes','EotU/Binaries/Win64/ue4ss/Mods/AllAttributes/Scripts');installationMethod='verified-manual-copy'}
    $path=Child $script:GameRoot $script:recordName;NoLink $path
    $stream=New-Object IO.FileStream($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try{$bytes=$script:utf8.GetBytes(($r|ConvertTo-Json -Depth 8));$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
    Log '已核对并登记手动复制的 36 个模组文件；未改动游戏存档。'
}
function QuotePS([string]$Value){return "'"+$Value.Replace("'","''")+"'"}
function UninstallPreflight($Record) {
    # Complete the shared-loader checks before any automatic save preparation.
    AssertStopped
    $paths=@{};$dirs=@{}
    foreach($file in @($Record.files)){$paths[$file.path.Replace('\','/')]=$true;NoLink (Child $script:GameRoot $file.path)}
    foreach($dir in @($Record.createdDirectories)){$dirs[$dir.Replace('\','/')]=$true;NoLink (Child $script:GameRoot $dir)}
    $mods=Child $script:GameRoot 'EotU/Binaries/Win64/ue4ss/Mods'
    if(Test-Path -LiteralPath $mods -PathType Container) {
        $stack=New-Object 'System.Collections.Generic.Stack[string]';$stack.Push($mods)
        while($stack.Count){
            $parent=$stack.Pop();NoLink $parent
            foreach($item in @(Get-ChildItem -LiteralPath $parent -Force)) {
                NoLink $item.FullName;$relative=$item.FullName.Substring($script:GameRoot.Length+1).Replace('\','/')
                if($item.PSIsContainer){if(-not $dirs.ContainsKey($relative)){throw ('检测到其他模组目录，未修改存档或卸载：'+$relative)};$stack.Push($item.FullName)}
                elseif(-not $paths.ContainsKey($relative)){throw ('检测到其他模组文件，未修改存档或卸载：'+$relative)}
            }
        }
    }
}
function PrepareAutomatically($Record,$Manifest) {
    $helper=Child $script:PackageRoot 'AutoPrepare.exe'
    $reference=Child $script:PackageRoot 'health-reference.json'
    foreach($path in @($helper,$reference)){NoLink $path;if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw '安装器缺少自动卸载组件，请重新下载完整安装器。'}}
    $saveRoot=[IO.Path]::GetFullPath([string]$Record.saveGamesRoot).TrimEnd('\','/');NoLink $saveRoot
    foreach($name in @('EAA_SkillPurchase_v1.bin','EAA_SkillPurchase_v1.bin.tmp')){
        $path=Child $saveRoot $name;NoLink $path
        if(Test-Path -LiteralPath $path){throw '技能购买尚待恢复，请先启动当前模组版本完成恢复并退出，再卸载。存档与模组均已保留。'}
    }
    if(-not(Test-Path -LiteralPath $saveRoot)){
        Log '尚无存档目录，无需准备存档。'
        return
    }
    $planResult=Join-Path ([IO.Path]::GetTempPath()) ('AntOverhaul-prepare-'+[Guid]::NewGuid().ToString('N')+'.json')
    try {
        Log '正在检查所有已加点殖民地的当前存档…'
        $oldPreference=$ErrorActionPreference
        try{$ErrorActionPreference='Continue';$output=@(& $helper --save-root $saveRoot --reference $reference --result $planResult 2>&1);$code=$LASTEXITCODE}
        finally{$ErrorActionPreference=$oldPreference}
        if(-not(Test-Path -LiteralPath $planResult)){throw ('自动卸载检查未返回结果：'+($output -join ' '))}
        $plan=Json $planResult
        if($code -ne 0 -or -not $plan.success){throw ([string]$plan.message)}
        if(-not $plan.requiresPreparation){Log ([string]$plan.message);return}
        if($Record.release -ne $script:release){throw '请先用本安装器更新至 0.1.18，再自动卸载。现有存档和模组均保留。'}
        CheckGame $Manifest $true
        AssertStopped
        Log '正在备份存档并自动清理额外属性，无需进入游戏按 F6/F8…'
        $oldPreference=$ErrorActionPreference
        try{$ErrorActionPreference='Continue';$output=@(& $helper --save-root $saveRoot --reference $reference --result $planResult --apply 2>&1);$code=$LASTEXITCODE}
        finally{$ErrorActionPreference=$oldPreference}
        $prepared=Json $planResult
        if($prepared.PSObject.Properties['backupPath'] -and $prepared.backupPath){Log ('存档备份：'+[string]$prepared.backupPath)}
        if($code -ne 0 -or -not $prepared.success){throw ([string]$prepared.message)}
        Log ([string]$prepared.message)
    } finally {
        if(Test-Path -LiteralPath $planResult){Remove-Item -LiteralPath $planResult}
    }
}
function RunManaged([string]$File,[string]$Mode) {
    $path=Child $script:PackageRoot $File;NoLink $path
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw ('安装包缺少管理组件：'+$File)}
    $command='$OutputEncoding=[Console]::OutputEncoding=New-Object Text.UTF8Encoding($false); Import-Module (Join-Path $PSHOME Modules/Microsoft.PowerShell.Utility/Microsoft.PowerShell.Utility.psd1) -ErrorAction Stop; & '+(QuotePS $path)+' -Action '+(QuotePS $Mode)+' -GameRoot '+(QuotePS $script:GameRoot)+' -PackageRoot '+(QuotePS $script:PackageRoot)
    if($File -eq 'Manage-Mod.ps1'){$command+=' -SaveGamesRoot '+(QuotePS $script:SaveGamesRoot)}
    $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $engine=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $old=$ErrorActionPreference
    try{
        $ErrorActionPreference='Continue'
        $lines=@(& $engine -NoLogo -NoProfile -NonInteractive -OutputFormat Text -ExecutionPolicy Bypass -EncodedCommand $encoded 2>&1)
        $code=$LASTEXITCODE
    }finally{$ErrorActionPreference=$old}
    foreach($line in $lines){Log ([string]$line)}
    if($code -ne 0){throw '操作未完成。请查看下方详细原因；安装记录、准备卸载状态或已有文件需要先处理。'}
}
try {
    $PackageRoot=[IO.Path]::GetFullPath($PackageRoot).TrimEnd('\','/');NoLink $PackageRoot
    $SaveGamesRoot=[IO.Path]::GetFullPath($SaveGamesRoot).TrimEnd('\','/')
    $ResultPath=[IO.Path]::GetFullPath($ResultPath);NoLink $ResultPath
    if(-not [string]::IsNullOrWhiteSpace($GameRoot)){$GameRoot=[IO.Path]::GetFullPath($GameRoot).TrimEnd('\','/')}
    else{$GameRoot=''}
    $result.gameRoot=$GameRoot
    foreach($protected in @($GameRoot,$SaveGamesRoot)){
        if($protected -and ($ResultPath.Equals($protected,[StringComparison]::OrdinalIgnoreCase) -or $ResultPath.StartsWith($protected+'\',[StringComparison]::OrdinalIgnoreCase))){throw '结果文件不能写入游戏目录或存档目录。'}
    }
    if(-not $GameRoot){
        if($Action -ne 'Inspect'){throw '请先选择游戏目录。'}
        $result.message='请选择地下蚁国的游戏目录。';$result.status='choose-folder'
    }else{
        $manifest=ReadManifest
        if($Action -eq 'Inspect'){
            UpdateState
            if($result.installed){
                $result.status='installed';$result.canUninstall=$true
                $result.canInstall=SupportedUpdateRelease $result.release
                $result.message='已找到蚂蚁大修 '+$result.release+'；实际操作时会核对文件完整性。'
                if(-not $result.canInstall){$result.message='已找到蚂蚁大修 '+$result.release+'；本安装器没有该版本的已验证更新路径。现有文件已保留。'}
                try{CheckGame $manifest $false}catch{
                    $details.Add([string]$_.Exception.Message)
                    $result.status='installed-incompatible';$result.canInstall=$false
                    $result.message='已找到模组安装记录，但游戏版本或目录状态已变化。可以尝试安全卸载，暂不允许安装或更新。'
                }
            }else{
                CheckGame $manifest $false
                $hasFiles=Test-Path -LiteralPath (Child $GameRoot 'EotU/Binaries/Win64/dwmapi.dll')
                $result.status=if($hasFiles){'unregistered'}else{'not-installed'}
                $result.canInstall=$true
                $result.message=if($hasFiles){'检测到未登记的加载器文件；安装时将核对是否为完整手动安装。'}else{'游戏目录已识别，可以安装蚂蚁大修。'}
            }
        }elseif($Action -eq 'AdoptManual'){
            Adopt $manifest;$result.message='手动安装已登记，可以使用本包的检查和卸载入口。';$result.status='installed'
        }elseif($Action -eq 'Install'){
            AssertStopped
            $r=ReadRecord
            if($r){
                if($r.release -eq $release){
                    RunManaged 'Manage-Mod.ps1' 'Status'
                    if(-not(AllTargetsMatch $manifest)){throw '当前文件不匹配本发布包；未覆盖安装。'}
                    $result.message='蚂蚁大修 0.1.18 已安装，全部受管文件完整。'
                }elseif(SupportedUpdateRelease ([string]$r.release)){
                    if(-not(Test-Path -LiteralPath (Child $PackageRoot 'payload') -PathType Container)){throw '手动包不能原地更新旧版，请使用完整 EXE 安装器。'}
                    CheckGame $manifest $true
                    RunManaged 'Update-Mod.ps1' 'Update';$result.message='已从 '+$r.release+' 更新至 '+$release+'，原有存档与培养记录保留。'
                }else{throw ('当前安装为 '+$r.release+'，本安装器没有该版本的已验证更新路径；未卸载或覆盖旧版。')}
            }elseif(AllTargetsMatch $manifest){
                Adopt $manifest;$result.message='已识别完整手动安装并登记，模组文件没有被覆盖。'
            }else{
                if(-not(Test-Path -LiteralPath (Child $PackageRoot 'payload') -PathType Container)){throw '手动包需要先将完整 EotU 文件夹复制到游戏根目录，再运行登记入口。'}
                RunManaged 'Manage-Mod.ps1' 'Install';$result.message='蚂蚁大修安装完成，可以从 Steam 正常启动游戏。'
            }
            $result.status='installed'
        }else{
            # A GUI failure should not leave a half-uninstalled package when a user edited a Lua file.
            RunManaged 'Manage-Mod.ps1' 'Status'
            $record=ReadRecord
            if(-not $record){throw '没有本模组安装记录，未卸载任何文件。'}
            UninstallPreflight $record
            PrepareAutomatically $record $manifest
            RunManaged 'Manage-Mod.ps1' 'Uninstall';$result.message='模组已卸载，游戏存档和培养记录已保留。';$result.status='not-installed'
        }
        UpdateState
        if($Action -ne 'Inspect'){$result.canInstall=$true;$result.canUninstall=$result.installed}
    }
    $result.success=$true;$exitCode=0
}catch{
    $result.message=[string]$_.Exception.Message;$result.status='error'
    $details.Add([string]$_)
    try{UpdateState}catch{$details.Add([string]$_)}
}finally{
    $result.details=@($details.ToArray())
    try{
        # Refuse protected destinations even when validation above has failed.
        foreach($protected in @($GameRoot,$SaveGamesRoot)){
            if($protected -and ($ResultPath.Equals($protected,[StringComparison]::OrdinalIgnoreCase) -or $ResultPath.StartsWith($protected+'\',[StringComparison]::OrdinalIgnoreCase))){throw 'Unsafe result destination'}
        }
        NoLink $ResultPath
        $parent=Split-Path -Parent $ResultPath
        if(-not(Test-Path -LiteralPath $parent -PathType Container)){[void][IO.Directory]::CreateDirectory($parent)}
        [IO.File]::WriteAllText($ResultPath,($result|ConvertTo-Json -Depth 10),$utf8)
    }catch{Write-Error ('无法写入操作结果：'+[string]$_) -ErrorAction Continue;$exitCode=1}
}
exit $exitCode
