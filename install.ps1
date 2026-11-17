# LinkSwift + AB Download Manager 一键配置（全新电脑可用，纯 PowerShell）
# 用法：
#   双击 setup.bat            （推荐，会自动接着打开安装向导页）
#   或 powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1
#   自检（只看路径，不改动）：... -File install.ps1 -SelfTest
param([switch]$SelfTest)

$ErrorActionPreference = 'Stop'

$root    = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$dlDir   = Join-Path $root '下载'
$exe     = Join-Path $root 'installer\ABDownloadManager_1.11.4_windows_x64.exe'
$script  = Join-Path $root 'script\linkswift-abdm-v3.user.js'
$tplCfg  = Join-Path $root 'tools\appSettings.template.json'
$tplCat  = Join-Path $root 'tools\categories.template.json'
$gui     = Join-Path $env:LOCALAPPDATA 'ABDownloadManager\ABDownloadManager.exe'
$cli     = Join-Path $env:LOCALAPPDATA 'ABDownloadManager\ABDownloadManagerCli.exe'
$cliAlt  = Join-Path $env:LOCALAPPDATA 'Programs\AB Download Manager\ABDownloadManagerCli.exe'
$cfgDir  = Join-Path $env:USERPROFILE '.abdm\config'
$cfgFile = Join-Path $cfgDir 'appSettings.json'
$catFile = Join-Path $cfgDir 'download_db\categories\categories.json'
$apiKey  = 'linkswift2026'
$port    = 15151
$dlUrl   = 'https://github.com/amir1376/ab-download-manager/releases/download/v1.11.4/ABDownloadManager_1.11.4_windows_x64.exe'

function Step($m) { Write-Host ''; Write-Host "== $m" -ForegroundColor Cyan }
function Info($m) { Write-Host "   $m" }
function Ok($m)   { Write-Host "   [OK] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "   [!]  $m" -ForegroundColor Yellow }
function Bad($m)  { Write-Host "   [X]  $m" -ForegroundColor Red }

function Test-Port([int]$p) {
    $c = New-Object System.Net.Sockets.TcpClient
    try {
        $iar = $c.BeginConnect('127.0.0.1', $p, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne(400)) { return $false }
        $c.EndConnect($iar)
        return $true
    } catch { return $false } finally { $c.Close() }
}
function Wait-Port([int]$p, [int]$seconds) {
    for ($i = 0; $i -lt $seconds; $i++) {
        if (Test-Port $p) { return $true }
        Start-Sleep -Seconds 1
    }
    return $false
}
function Abdm-Cli($arg) {
    $bin = if (Test-Path -LiteralPath $cli) { $cli } elseif (Test-Path -LiteralPath $cliAlt) { $cliAlt } else { $null }
    if (-not $bin) { return }
    try { & $bin gui $arg 2>&1 | Out-Null } catch { }
}
function Set-Prop($obj, $name, $value) {
    if ($obj.PSObject.Properties.Name -contains $name) { $obj.$name = $value }
    else { $obj | Add-Member -NotePropertyName $name -NotePropertyValue $value }
}
function Wait-ProcessGone([string]$name, [int]$seconds) {
    for ($i = 0; $i -lt $seconds; $i++) {
        if (-not (Get-Process $name -ErrorAction SilentlyContinue)) { return $true }
        Start-Sleep -Seconds 1
    }
    return (-not (Get-Process $name -ErrorAction SilentlyContinue))
}

if ($SelfTest) {
    Step '自检（不做任何改动）'
    Info "包目录      : $root"
    Info "系统        : $([System.Environment]::OSVersion.VersionString)  PowerShell $($PSVersionTable.PSVersion)"
    Info "安装包      : $(Test-Path -LiteralPath $exe)   $exe"
    Info "用户脚本    : $(Test-Path -LiteralPath $script)   $script"
    Info "下载目录    : $dlDir"
    Info "ABDM 程序   : $(Test-Path -LiteralPath $gui)   $gui"
    Info "ABDM 命令行 : $(Test-Path -LiteralPath $cli)"
    Info "配置文件    : $(Test-Path -LiteralPath $cfgFile)   $cfgFile"
    Info "配置模板    : $(Test-Path -LiteralPath $tplCfg)"
    Info "分类模板    : $(Test-Path -LiteralPath $tplCat)"
    return
}

Write-Host ''
Write-Host '  LinkSwift + AB Download Manager  一键配置' -ForegroundColor White
Write-Host '  （装下载器 -> 写配置 -> 自检 -> 打开安装向导）' -ForegroundColor DarkGray

# ---------- 0 ----------
Step '0/7  环境检查'
Info "包目录：$root"
if ($root -match '[^\x00-\x7F]') { Warn '路径含中文/非 ASCII 字符，部分场景可能出问题；建议放在纯英文目录下（如 D:\LinkSwift）' } else { Ok '路径正常' }
if (-not (Test-Path -LiteralPath $script)) { Bad "缺少用户脚本：$script（请重新解压整个整合包）"; exit 1 }
Ok '用户脚本就位'

# ---------- 1 ----------
Step '1/7  检查 AB Download Manager'
$installed = (Test-Path -LiteralPath $gui) -or (Test-Path -LiteralPath $cli)
if ($installed) {
    Ok '已安装，跳过安装步骤'
} else {
    if (-not (Test-Path -LiteralPath $exe)) {
        Warn "本地没有安装包，尝试从官方 Releases 下载（约 75MB）..."
        try {
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $exe) | Out-Null
            $old = $ProgressPreference; $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -Uri $dlUrl -OutFile $exe -UseBasicParsing -TimeoutSec 600
            $ProgressPreference = $old
            if (Test-Path -LiteralPath $exe) { Ok '下载完成' } else { throw '下载后文件不存在' }
        } catch {
            Bad "下载失败：$($_.Exception.Message)"
            Info '请手动下载后放进 installer 目录，再重跑本脚本：'
            Info '  https://github.com/amir1376/ab-download-manager/releases'
            exit 1
        }
    }
    Info '正在静默安装（约 1 分钟，不弹窗）...'
    Start-Process -FilePath $exe -ArgumentList '/quiet' -Wait
    Start-Sleep -Seconds 2
    if ((Test-Path -LiteralPath $gui) -or (Test-Path -LiteralPath $cli)) {
        Ok '安装完成'
    } else {
        Bad '安装失败，请手动双击 installer 里的 exe（一路下一步）后重跑'
        exit 1
    }
}

# ---------- 2 ----------
Step '2/7  准备下载目录'
New-Item -ItemType Directory -Force -Path $dlDir | Out-Null
Ok "下载目录：$dlDir"

if (-not (Test-Path -LiteralPath $cfgFile)) {
    Info '首次运行，先启动一次以生成配置文件...'
    Abdm-Cli 'start-if-not-started'
    $got = $false
    for ($i = 0; $i -lt 60; $i++) {
        if (Test-Path -LiteralPath $cfgFile) { $got = $true; break }
        Start-Sleep -Seconds 1
    }
    if ($got) { Ok '配置文件已生成' } else { Warn '等待超时，稍后用内置模板写入' }
}

# ---------- 3 ----------
Step '3/7  关闭下载器以便写配置'
Abdm-Cli 'exit'
$gone = Wait-ProcessGone 'ABDownloadManager' 40
if (-not $gone) { Warn '进程没退干净，配置可能写不进去；可手动退出托盘图标后重跑' } else { Ok '下载器已退出' }
Start-Sleep -Milliseconds 500

# ---------- 4 ----------
Step '4/7  写入配置（端口 / 密钥 / 下载目录）'
New-Item -ItemType Directory -Force -Path $cfgDir | Out-Null

if (-not (Test-Path -LiteralPath $cfgFile)) {
    if (Test-Path -LiteralPath $tplCfg) {
        Copy-Item -LiteralPath $tplCfg -Destination $cfgFile -Force
        Ok '用内置模板生成了配置文件'
    } else {
        Bad "配置文件不存在且无模板：$cfgFile"
        Info '请手动打开一次 AB Download Manager（让它初始化），然后重跑 setup.bat'
        exit 1
    }
}

$bak = "$cfgFile.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
Copy-Item -LiteralPath $cfgFile -Destination $bak -Force
Info "原配置已备份：$bak"

$json = [System.IO.File]::ReadAllText($cfgFile, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
Set-Prop $json 'apiEnabled' $true
Set-Prop $json 'apiPort' $port
Set-Prop $json 'apiAuthKey' $apiKey
Set-Prop $json 'apiAuthEnabled' $true
Set-Prop $json 'defaultDownloadFolder' $dlDir
$out = ConvertTo-Json -InputObject $json -Depth 10
[System.IO.File]::WriteAllText($cfgFile, $out, (New-Object System.Text.UTF8Encoding($false)))
$check = [System.IO.File]::ReadAllText($cfgFile, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
if ($check.apiAuthKey -ne $apiKey -or $check.apiPort -ne $port) {
    Bad '写入校验失败，请重跑一次 setup.bat'
    exit 1
}
Ok "配置已写入（端口 $port，密钥 $apiKey）"

# ---------- 5 ----------
Step '5/7  分类目录指向下载目录'
if (Test-Path -LiteralPath $catFile) {
    $cats = [System.IO.File]::ReadAllText($catFile, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    foreach ($c in $cats) { $c.path = "$dlDir\$($c.name)" }
    $catOut = ConvertTo-Json -InputObject @($cats) -Depth 10
    [System.IO.File]::WriteAllText($catFile, $catOut, (New-Object System.Text.UTF8Encoding($false)))
    Ok '分类目录已全部指向下载目录'
} elseif (Test-Path -LiteralPath $tplCat) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $catFile) | Out-Null
    $cats = [System.IO.File]::ReadAllText($tplCat, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    foreach ($c in $cats) { $c.path = "$dlDir\$($c.name)" }
    [System.IO.File]::WriteAllText($catFile, (ConvertTo-Json -InputObject @($cats) -Depth 10), (New-Object System.Text.UTF8Encoding($false)))
    Ok '用模板创建了分类配置'
} else {
    Warn '没有分类配置，跳过（不影响基本下载）'
}

# ---------- 6 ----------
Step '6/7  启动并自检'
Abdm-Cli 'start-if-not-started'
if (-not (Wait-Port $port 60)) {
    Bad "服务没有起来（端口 $port 未监听）。手动打开 AB Download Manager 看看有没有报错"
} else {
    Ok "本地服务已监听 127.0.0.1:$port"
    try {
        $r = Invoke-WebRequest -Uri "http://127.0.0.1:$port/ping" -Method Post `
            -Headers @{ 'X-Api-Key' = $apiKey } -Body '1' -UseBasicParsing -TimeoutSec 10
        if ($r.Content -match 'pong') { Ok '鉴权 + 连通正常（pong）' } else { Warn "返回内容异常：$($r.Content)" }
    } catch {
        Warn "自检请求失败：$($_.Exception.Message)"
    }
}

# ---------- 7 ----------
Step '7/7  下一步：浏览器里装脚本'
Info '马上会自动打开安装向导页（http://127.0.0.1:18080/），照着点即可'
Write-Host ''
Write-Host '  下载器这部分已经配好了。' -ForegroundColor Green
Write-Host ''
