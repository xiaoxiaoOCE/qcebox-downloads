[CmdletBinding()]
param([ValidateSet('Inspect','AdoptManual','Uninstall')][string]$Action='Inspect',[string]$SaveGamesRoot='')
$ErrorActionPreference='Stop'
$gameRoot=[IO.Directory]::GetParent($PSScriptRoot).FullName
$resultPath=Join-Path ([IO.Path]::GetTempPath()) ('AntOverhaul-result-'+[Guid]::NewGuid().ToString('N')+'.json')
$backend=Join-Path $PSScriptRoot 'Backend.ps1'
$powershell=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
try {
    if(-not(Test-Path -LiteralPath (Join-Path $gameRoot 'EotU.exe') -PathType Leaf)) {
        throw '请先将 EotU 文件夹、AntOverhaul-Manager 文件夹和三个管理入口一起复制到游戏根目录（与 EotU.exe 同级）。'
    }
    Write-Host ('目标游戏目录：'+$gameRoot)
    if($Action -eq 'Uninstall') {
        Write-Host '请先退出游戏。将自动备份并处理已加点殖民地的当前存档，再卸载模组；无需进入游戏按 F6/F8。'
        if((Read-Host '确认卸载蚂蚁大修？输入 Y 继续') -notmatch '^[yY]$') { Write-Host '已取消。'; exit 0 }
    }
    $arguments=@('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$backend,'-Action',$Action,'-GameRoot',$gameRoot,'-PackageRoot',$PSScriptRoot,'-ResultPath',$resultPath)
    if(-not [string]::IsNullOrWhiteSpace($SaveGamesRoot)){$arguments+=@('-SaveGamesRoot',$SaveGamesRoot)}
    & $powershell @arguments
    $childCode=$LASTEXITCODE
    if(Test-Path -LiteralPath $resultPath) {
        $result=Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8 | ConvertFrom-Json
        Write-Host ''
        Write-Host $result.message
        foreach($detail in @($result.details)) { Write-Host $detail }
        if(-not $result.success) { exit 1 }
    } elseif($childCode -eq 0) { throw '没有收到管理结果，请查看上面的错误信息。' }
    exit $childCode
} catch {
    Write-Host ('操作未完成：'+$_.Exception.Message) -ForegroundColor Red
    exit 1
} finally {
    if(Test-Path -LiteralPath $resultPath) { Remove-Item -LiteralPath $resultPath }
}
