# LinkSwift 本地安装向导（纯 PowerShell，无 Python 依赖）
# 由 setup.bat 自动调用；也可手动：powershell -NoProfile -ExecutionPolicy Bypass -File tools\guide-server.ps1 -OpenBrowser
#
# 作用：在 127.0.0.1 上起一个只服务本机的迷你 HTTP 服务
#   1) 渲染安装向导页面
#   2) 用 text/javascript 托管 .user.js，脚本管理器会自动弹安装框
# 只监听回环地址，不对外开放。

param(
    [int]$Port = 18080,
    [switch]$OpenBrowser,
    [switch]$NoBrowser
)

$ErrorActionPreference = 'Stop'

$root       = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $root 'script\linkswift-abdm-v3.user.js'
$logPath    = Join-Path $PSScriptRoot 'guide.log'
$ABDM_PORT  = 15151
$STORE_URL  = 'https://microsoftedge.microsoft.com/addons/detail/liilgpjgabokdklappibcjfablkpcekh'
$CROME_STORE = 'https://chromewebstore.google.com/detail/scriptcat/liilgpjgabokdklappibcjfablkpcekh'

function Write-Log([string]$msg) {
    try {
        $line = '[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'), $msg
        [System.IO.File]::AppendAllText($logPath, $line + "`r`n", (New-Object System.Text.UTF8Encoding($false)))
    } catch { }
}

function Test-LocalPort([int]$p, [int]$timeoutMs = 300) {
    $c = New-Object System.Net.Sockets.TcpClient
    try {
        $iar = $c.BeginConnect('127.0.0.1', $p, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne($timeoutMs)) { return $false }
        $c.EndConnect($iar)
        return $true
    } catch { return $false } finally { $c.Close() }
}

function Get-ScriptMeta {
    $meta = [ordered]@{ exists = $false; name = ''; version = ''; size = 0 }
    if (-not (Test-Path -LiteralPath $scriptPath)) { return $meta }
    $meta.exists = $true
    $meta.size = (Get-Item -LiteralPath $scriptPath).Length
    $head = [System.IO.File]::ReadAllText($scriptPath, [System.Text.Encoding]::UTF8)
    if ($head.Length -gt 8000) { $head = $head.Substring(0, 8000) }
    $m = [regex]::Match($head, '(?m)^//\s*@name\s+(.+)$')
    if ($m.Success) { $meta.name = $m.Groups[1].Value.Trim() }
    $m = [regex]::Match($head, '(?m)^//\s*@version\s+(.+)$')
    if ($m.Success) { $meta.version = $m.Groups[1].Value.Trim() }
    return $meta
}

# 检测本机浏览器里是否装了脚本管理器（脚本猫 / 篡改猴）
function Get-ManagerInfo {
    $ids = [ordered]@{
        'liilgpjgabokdklappibcjfablkpcekh' = '脚本猫 ScriptCat'
        'dhdgffkkebhmkfjojejmpbldmpobfkfo' = '篡改猴 Tampermonkey'
        'iikmkjmpaadaobahmlepeloendndfphd' = '篡改猴 Tampermonkey'
    }
    $browsers = @(
        @{ Name = 'Edge';   Path = (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data') },
        @{ Name = 'Chrome'; Path = (Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data') }
    )
    $found = @()
    foreach ($b in $browsers) {
        if (-not (Test-Path -LiteralPath $b.Path)) { continue }
        $profiles = @(Get-ChildItem -LiteralPath $b.Path -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' })
        foreach ($p in $profiles) {
            foreach ($id in $ids.Keys) {
                $extDir = Join-Path $p.FullName ('Extensions\' + $id)
                if (Test-Path -LiteralPath $extDir) {
                    $found += ('{0}（{1}）· {2}' -f $b.Name, $p.Name, $ids[$id])
                }
            }
        }
    }
    return $found
}

function Get-ConfigInfo {
    $cfg = Join-Path $env:USERPROFILE '.abdm\config\appSettings.json'
    $info = [ordered]@{ exists = $false; folder = ''; port = 0; keyOk = $false }
    if (-not (Test-Path -LiteralPath $cfg)) { return $info }
    try {
        $j = [System.IO.File]::ReadAllText($cfg, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        $info.exists = $true
        $info.folder = [string]$j.defaultDownloadFolder
        $info.port = [int]$j.apiPort
        $info.keyOk = ([string]$j.apiAuthKey -eq 'linkswift2026') -and ([bool]$j.apiAuthEnabled)
    } catch { }
    return $info
}

# ---------- HTTP ----------
function Send-Body($stream, [string]$status, [string]$ctype, [byte[]]$body, [hashtable]$extra) {
    $head = "HTTP/1.1 $status`r`nContent-Type: $ctype`r`nContent-Length: $($body.Length)`r`nCache-Control: no-store`r`nConnection: close`r`n"
    if ($extra) { foreach ($k in $extra.Keys) { $head += "$k`: $($extra[$k])`r`n" } }
    $head += "`r`n"
    $hb = [System.Text.Encoding]::ASCII.GetBytes($head)
    $stream.Write($hb, 0, $hb.Length)
    if ($body.Length -gt 0) { $stream.Write($body, 0, $body.Length) }
    $stream.Flush()
}

function Send-Text($stream, [string]$status, [string]$ctype, [string]$text) {
    Send-Body $stream $status $ctype ([System.Text.Encoding]::UTF8.GetBytes($text)) $null
}

function New-Row([bool]$ok, [string]$label, [string]$text) {
    $cls = if ($ok) { 'dot ok' } else { 'dot bad' }
    return "<div class=`"row`"><span class=`"$cls`"></span><span class=`"k`">$label</span><span>$text</span></div>"
}

function Get-StatusObject {
    $meta = Get-ScriptMeta
    $cfg = Get-ConfigInfo
    $mgrs = Get-ManagerInfo
    return [ordered]@{
        abdm_installed = (Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'ABDownloadManager\ABDownloadManager.exe'))
        abdm_listening = (Test-LocalPort $ABDM_PORT)
        abdm_port      = $ABDM_PORT
        config_ok      = ($cfg.exists -and $cfg.keyOk -and $cfg.port -eq $ABDM_PORT)
        config_folder  = $cfg.folder
        script_exists  = $meta.exists
        script_name    = $meta.name
        script_version = $meta.version
        managers       = @($mgrs)
        manager_found  = ($mgrs.Count -gt 0)
        guide_port     = $Port
    }
}

function Get-Page {
    $s = Get-StatusObject
    $meta = Get-ScriptMeta

    $rowAbdmInstalled = New-Row $s.abdm_installed 'ABDM 程序' $(if ($s.abdm_installed) { '已安装（AB Download Manager 1.11.4）' } else { '未安装 —— 先跑一次 setup.bat 的安装部分' })
    $rowAbdmService   = New-Row $s.abdm_listening '下载服务' $(if ($s.abdm_listening) { "正在监听 127.0.0.1:$ABDM_PORT" } else { '未监听 —— 打开 AB Download Manager，或看托盘里它是否被退出了' })
    $rowConfig        = New-Row $s.config_ok '集成配置' $(if ($s.config_ok) { '端口 / 密钥 / 下载目录已就绪' } else { '配置不完整，重跑 setup.bat' })
    $rowScript        = New-Row $s.script_exists '用户脚本' $(if ($s.script_exists) { "文件就绪 $($meta.version)" } else { '脚本文件缺失，重新解压整合包' })

    if ($s.manager_found) {
        $list = ($s.managers -join '<br>')
        $rowManager = New-Row $true '脚本管理器' "已检测到：<br>$list"
        $step0 = ''
    } else {
        $rowManager = New-Row $false '脚本管理器' '未检测到 —— 必须先装一个（脚本猫或篡改猴）'
        $step0 = @"
  <div class="card warn">
    <h2><span class="num">0</span>先装脚本管理器（这台机器上没检测到）</h2>
    <p style="margin:0 0 12px;font-size:14px;color:#374151">
      浏览器扩展没法静默安装，这一步必须你点。装完回到本页刷新，第 1 步才能真正生效。
    </p>
    <a class="btn" href="$STORE_URL" target="_blank" rel="noopener">Edge：安装 脚本猫 ScriptCat</a>
    <a class="btn ghost" href="$CROME_STORE" target="_blank" rel="noopener">Chrome：安装 脚本猫 ScriptCat</a>
    <div class="hint">点「获取」→「添加扩展」。已经装了篡改猴的可以跳过这一步。</div>
  </div>
"@
    }

    $dlHint = if ($s.config_folder) { $s.config_folder } else { '（未配置）' }

    return @"
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>LinkSwift 安装向导</title>
<style>
  :root {
    --bg:#f6f7f9; --card:#fff; --line:#e5e7eb; --text:#1f2328; --muted:#6b7280;
    --ok:#16a34a; --bad:#dc2626; --accent:#2563eb;
  }
  * { box-sizing:border-box; }
  body { margin:0; padding:32px 20px 56px; background:var(--bg); color:var(--text);
    font:15px/1.65 -apple-system,"Segoe UI","Microsoft YaHei",system-ui,sans-serif; }
  .wrap { max-width:780px; margin:0 auto; }
  h1 { font-size:22px; margin:0 0 6px; letter-spacing:.2px; }
  .sub { color:var(--muted); font-size:13.5px; margin-bottom:22px; }
  .card { background:var(--card); border:1px solid var(--line); border-radius:12px; padding:20px 22px; margin-bottom:16px; }
  .card.warn { border-color:#fcd34d; background:#fffbeb; }
  .card h2 { font-size:15px; margin:0 0 14px; display:flex; align-items:center; gap:9px; }
  .num { display:inline-flex; align-items:center; justify-content:center; width:22px; height:22px;
    border-radius:50%; background:var(--accent); color:#fff; font-size:12px; font-weight:600; flex:none; }
  .num.gray { background:#cbd5e1; }
  .row { display:flex; align-items:flex-start; gap:10px; padding:6px 0; font-size:14px; }
  .row .k { color:var(--muted); width:96px; flex:none; }
  .dot { width:9px; height:9px; border-radius:50%; background:#cbd5e1; flex:none; margin-top:8px; }
  .dot.ok { background:var(--ok); box-shadow:0 0 0 3px rgba(22,163,74,.15); }
  .dot.bad { background:var(--bad); box-shadow:0 0 0 3px rgba(220,38,38,.15); }
  code { font-family:Consolas,"Cascadia Mono",monospace; font-size:13px; background:#f3f4f6;
    border:1px solid var(--line); border-radius:6px; padding:2px 7px; word-break:break-all; }
  .btn { display:inline-flex; align-items:center; gap:8px; background:var(--accent); color:#fff;
    text-decoration:none; border:0; border-radius:9px; padding:12px 22px; font-size:15px; font-weight:600;
    cursor:pointer; margin:0 8px 8px 0; }
  .btn:hover { filter:brightness(1.07); }
  .btn.ghost { background:#fff; color:var(--text); border:1px solid var(--line); font-weight:500;
    padding:8px 14px; font-size:13.5px; }
  .hint { color:var(--muted); font-size:13px; margin-top:12px; }
  ul { margin:10px 0 0; padding-left:20px; color:#374151; font-size:13.5px; }
  li { margin:5px 0; }
  .meta { display:flex; gap:22px; flex-wrap:wrap; font-size:13px; color:var(--muted); margin-top:8px; }
  .meta b { color:var(--text); font-weight:600; font-family:Consolas,monospace; }
  footer { color:#9ca3af; font-size:12.5px; text-align:center; margin-top:26px; }
</style>
</head>
<body>
<div class="wrap">
  <h1>LinkSwift 安装向导</h1>
  <div class="sub">网盘直链 → AB Download Manager 多线程下载 · 本机向导，仅监听 127.0.0.1:$Port</div>

  <div class="card">
    <h2><span class="num gray">i</span>环境状态</h2>
    $rowAbdmInstalled
    $rowAbdmService
    $rowConfig
    $rowScript
    $rowManager
    <div class="meta">
      <span>脚本名 <b>$($meta.name)</b></span>
      <span>版本 <b>$($meta.version)</b></span>
      <span>下载目录 <b>$dlHint</b></span>
    </div>
  </div>

$step0
  <div class="card">
    <h2><span class="num">1</span>点一下装脚本</h2>
    <p style="margin:0 0 14px;font-size:14px;color:#374151">
      点下面按钮，脚本管理器会自动弹出安装页，选「安装」即可。
    </p>
    <a class="btn" href="/linkswift-abdm-v3.user.js">安装 LinkSwift (ABDM Key Patch)</a>
    <div class="hint">
      点了没弹安装框、而是下载了文件或显示一堆源码：改用「脚本猫图标 → 管理面板 → 工具 → 导入脚本」，
      选这个文件 <code>$scriptPath</code>，效果一样。
    </div>
  </div>

  <div class="card">
    <h2><span class="num">2</span>核对这两项（出错都错在这）</h2>
    <ul>
      <li>脚本列表里的名字应是 <code>$($meta.name)</code></li>
      <li>版本应是 <code>$($meta.version)</code></li>
      <li>显示成 <code>New Userscript</code> = 没导入成功，回到上一步重来</li>
    </ul>
  </div>

  <div class="card">
    <h2><span class="num">3</span>网盘页里填一次服务地址</h2>
    <p style="margin:0 0 10px;font-size:14px;color:#374151">
      打开任意网盘页面 → <code>Ctrl+F5</code> 强刷 → 右下角出现「下载助手」→ 齿轮 → <b>ABDM 服务设置</b>：
    </p>
    <div class="row"><span class="k">服务主机</span><code>http://127.0.0.1</code></div>
    <div class="row"><span class="k">服务端口</span><code>$ABDM_PORT</code></div>
    <div class="row"><span class="k">存储路径</span><code>留空</code></div>
    <div class="row"><span class="k">API 密钥</span><code>留空</code></div>
    <div class="hint">点「测试」应显示绿色「成功」。主机别写 localhost，本机会先解析到 IPv6 导致推送失败。</div>
  </div>

  <button class="btn ghost" onclick="location.reload()">重新检测状态</button>
  <button class="btn ghost" onclick="closeGuide()">装好了，关闭向导服务</button>
  <footer>向导地址 http://127.0.0.1:$Port/ · 关闭后不影响已经装好的环境</footer>
</div>
<script>
function closeGuide() {
  fetch('/shutdown').then(function () { document.body.innerHTML =
    '<div style="max-width:600px;margin:80px auto;font:15px system-ui;color:#374151">' +
    '<h2 style="color:#16a34a">向导服务已关闭</h2>' +
    '<p>LinkSwift 和 AB Download Manager 已经装好，这个页面和后台服务都不再需要了。' +
    '现在直接去网盘页面按 Ctrl+F5 就能用。</p></div>'; });
}
</script>
</body>
</html>
"@
}

function Handle-Request($client) {
    $stream = $client.GetStream()
    $stream.ReadTimeout = 3000

    # 浏览器会开预连接但迟迟不发数据，别让主循环卡在这
    $deadline = (Get-Date).AddMilliseconds(1200)
    while (-not $stream.DataAvailable -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 20 }
    if (-not $stream.DataAvailable) { return }

    $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::ASCII)
    $requestLine = $reader.ReadLine()
    if ([string]::IsNullOrWhiteSpace($requestLine)) { return }
    while ($true) {
        $line = $reader.ReadLine()
        if ([string]::IsNullOrWhiteSpace($line)) { break }
        if ($null -eq $line) { break }
    }

    $parts = $requestLine.Split(' ')
    $method = $parts[0]
    $rawPath = if ($parts.Length -ge 2) { $parts[1] } else { '/' }
    $path = $rawPath.Split('?')[0]
    Write-Log "$method $path"

    switch ($path) {
        '/' {
            Send-Text $stream '200 OK' 'text/html; charset=utf-8' (Get-Page)
            return
        }
        '/index.html' {
            Send-Text $stream '200 OK' 'text/html; charset=utf-8' (Get-Page)
            return
        }
        '/status' {
            $json = (Get-StatusObject) | ConvertTo-Json -Depth 5 -Compress
            Send-Text $stream '200 OK' 'application/json; charset=utf-8' $json
            return
        }
        '/linkswift-abdm-v3.user.js' {
            if (-not (Test-Path -LiteralPath $scriptPath)) {
                Send-Text $stream '404 Not Found' 'text/plain; charset=utf-8' 'script not found'
                return
            }
            $bytes = [System.IO.File]::ReadAllBytes($scriptPath)
            Send-Body $stream '200 OK' 'text/javascript; charset=utf-8' $bytes @{
                'Content-Disposition' = 'inline; filename="linkswift-abdm-v3.user.js"'
                'X-Content-Type-Options' = 'nosniff'
            }
            return
        }
        '/shutdown' {
            Send-Text $stream '200 OK' 'text/plain; charset=utf-8' 'bye'
            Write-Log 'shutdown requested by page'
            Start-Sleep -Milliseconds 300
            exit 0
        }
        default {
            Send-Text $stream '404 Not Found' 'text/plain; charset=utf-8' 'not found'
            return
        }
    }
}

# ---------- 启动 ----------
if (-not (Test-Path -LiteralPath $scriptPath)) {
    Write-Log "找不到用户脚本: $scriptPath"
    exit 1
}

if (Test-LocalPort $Port) {
    # 端口已占用：若已有实例在跑就直接开页面
    Write-Log "端口 $Port 已被占用，直接打开页面"
    if (-not $NoBrowser) { Start-Process ('http://127.0.0.1:' + $Port + '/') | Out-Null }
    exit 0
}

$listener = $null
$tryPort = $Port
for ($i = 0; $i -lt 20; $i++) {
    try {
        $listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, $tryPort)
        $listener.Start()
        $Port = $tryPort
        break
    } catch {
        $tryPort++
        $listener = $null
    }
}
if (-not $listener) {
    Write-Log '找不到可用端口（18080-18100）'
    exit 2
}

$url = 'http://127.0.0.1:' + $Port + '/'
Write-Log "guide server started on $url pid=$PID"
if (-not $NoBrowser) {
    try { Start-Process $url | Out-Null } catch { Write-Log ('打开浏览器失败: ' + $_.Exception.Message) }
}

while ($true) {
    try {
        $client = $listener.AcceptTcpClient()
    } catch {
        break
    }
    try {
        Handle-Request $client
    } catch {
        Write-Log ('处理请求异常: ' + $_.Exception.Message)
    } finally {
        try { $client.Close() } catch { }
    }
}

try { $listener.Stop() } catch { }
