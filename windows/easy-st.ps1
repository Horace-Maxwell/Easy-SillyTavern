#
# Easy SillyTavern · Windows
# 酒馆 SillyTavern 一键安装 / 启动 / 更新 / 备份 / 诊断
#
#   安装：在 PowerShell 里粘贴 README 里的那一行（下载本文件，再用 powershell -File 运行）
#   之后：双击桌面上的「酒馆 SillyTavern」启动，「酒馆工具箱」做更新、备份、诊断。
#
# 不需要管理员权限，所有东西都装在 %LOCALAPPDATA%\SillyTavern-Easy 里：
#   runtime\node   私有的 Node.js（按 CPU 自动选 x64 / arm64）
#   app\           SillyTavern 程序本体（更新时整个替换）
#   data\          聊天记录、角色卡、设置（更新时不动）
#   config.yaml    酒馆配置
#
# 要兼容 Win10 自带的 Windows PowerShell 5.1，别用 PowerShell 7 才有的写法（?? ?: && 之类）。
# 这个文件必须存成「带 BOM 的 UTF-8」，不然 5.1 会按系统的 ANSI 编码读，中文全乱。
# 字符串里变量后面紧跟中文时一定写成 ${var}：PowerShell 会把中文当成变量名的一部分。
# 给 node 之类的外部程序传参数时别带双引号：5.1 不会转义参数里的双引号。

param([string]$Command = '')

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Continue'
# 在 PowerShell 7 的窗口里运行 powershell.exe 时，会继承 7 的模块路径，
# 5.1 就会去加载 7 的模块，Get-FileHash 这类命令直接找不到。把 7 的路径去掉
if ($PSVersionTable.PSEdition -ne 'Core') {
    $paths = @($env:PSModulePath -split ';' | Where-Object { $_ -and $_ -notmatch '\\PowerShell\\' })
    $paths += "$env:SystemRoot\System32\WindowsPowerShell\v1.0\Modules"
    $env:PSModulePath = ($paths | Select-Object -Unique) -join ';'
}
# 不关掉进度条的话 Invoke-WebRequest、Expand-Archive 会慢几十倍
$ProgressPreference = 'SilentlyContinue'

$EST_VERSION = '0.1.0'

function env_or([string]$name, [string]$default) {
    $v = [Environment]::GetEnvironmentVariable($name)
    if ($v) { $v } else { $default }
}

$EST_REPO = env_or 'EST_REPO' 'Horace-Maxwell/Easy-SillyTavern'
$EST_BRANCH = env_or 'EST_BRANCH' 'main'

# 不放「文档」「桌面」：那两个经常被 OneDrive 同步，node_modules 几万个小文件会把同步卡死
$EST_HOME = [IO.Path]::GetFullPath((env_or 'EST_HOME' (Join-Path $env:LOCALAPPDATA 'SillyTavern-Easy'))).TrimEnd('\')
# 桌面可能被 OneDrive 挪走了，要问系统真正的位置
$EST_DESKTOP = env_or 'EST_DESKTOP' ([Environment]::GetFolderPath('Desktop'))
$NODE_DIR = "$EST_HOME\runtime\node"
$APP_DIR = "$EST_HOME\app"
$DATA_DIR = "$EST_HOME\data"
$CONFIG = "$EST_HOME\config.yaml"
$LOG_DIR = "$EST_HOME\logs"
$BACKUP_DIR = "$EST_HOME\backups"
$STATE = "$EST_HOME\state.env"
$SELF = "$EST_HOME\easy-st.ps1"
$MARKER = "$EST_HOME\.easy-sillytavern"
$TMP_ROOT = "$EST_HOME\tmp"
$NODE = "$NODE_DIR\node.exe"
# 直接用 node 跑 npm-cli.js，不经过 npm.cmd：.cmd 遇到中文用户名、空格路径容易出怪问题
$NPM_CLI = "$NODE_DIR\node_modules\npm\bin\npm-cli.js"
$SCRIPT_PATH = $PSCommandPath

$PORT_FIRST = 8000
$PORT_LAST = 8019
# 酒馆运行时会按需下载的分词器，提前放进缓存，免得国内网络第一次用时卡住
$TOKENIZERS = @('deepseek', 'qwen2', 'nemo', 'command-r', 'command-a')

$UTF8 = New-Object Text.UTF8Encoding $false
$UTF8BOM = New-Object Text.UTF8Encoding $true
$INVARIANT = [Globalization.CultureInfo]::InvariantCulture

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch {}
# node 的输出是 UTF-8，PowerShell 按这个编码去解读外部程序的输出
try { [Console]::OutputEncoding = $UTF8 } catch {}

# 后面各个函数会改这些值；先占位，免得 StrictMode 报「变量没设置」
$WIN_MAJOR = 0; $WIN_BUILD = 0; $WIN_NAME = 'Windows'; $WIN_DISPLAY = ''
$ARCH = 'x64'; $FREE_MB = 0; $NODE_MAJOR = ''
$PROXY_URL = ''; $PROXY_SRC = ''; $PROXY_DEAD = ''
$REGION = ''; $NPM_REGISTRY = ''; $NPM_FALLBACK = ''
$NODE_MIRRORS = @(); $GH_ROUTES = @()

# Win10 1803 以后系统自带 curl.exe 和 tar.exe；比 Invoke-WebRequest 快得多，也不会自己去用系统代理
$CURL = ''
if (Test-Path -LiteralPath "$env:SystemRoot\System32\curl.exe") {
    $CURL = "$env:SystemRoot\System32\curl.exe"
} else {
    $found = Get-Command curl.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { $CURL = $found.Path }
}
$TAR = ''
if (Test-Path -LiteralPath "$env:SystemRoot\System32\tar.exe") { $TAR = "$env:SystemRoot\System32\tar.exe" }
# 系统自带的 curl 用 Windows 的证书检查；有些网络查不到证书吊销列表，会把所有 https 都判失败
$CURL_TLS = @()
if ($CURL -and ((& $CURL --help all 2>&1 | Out-String) -match 'ssl-revoke-best-effort')) {
    $CURL_TLS = @('--ssl-revoke-best-effort')
}

# ---------------------------------------------------------------- 输出 ---

$EST_LANG = env_or 'EST_LANG' ''
if (-not $EST_LANG) {
    $EST_LANG = (Get-UICulture).Name
    if ($EST_LANG -notlike 'zh*') { $EST_LANG = (Get-Culture).Name }
}
if ($EST_LANG -like 'zh*') { $EST_LANG = 'zh' } else { $EST_LANG = 'en' }

# t "中文" "English"：按系统语言挑一句
function t([string]$zh, [string]$en = '') {
    if ($EST_LANG -eq 'zh' -or -not $en) { $zh } else { $en }
}

# 只用老控制台字体里也有的符号（√ × !），Win10 的黑色窗口显示不了 ✓ ▶
function step([string]$zh, [string]$en = '') { Write-Host ''; Write-Host ">> $(t $zh $en)" -ForegroundColor Cyan }
function info([string]$zh, [string]$en = '') { Write-Host "  $(t $zh $en)" }
function ok([string]$zh, [string]$en = '') { Write-Host "  √ $(t $zh $en)" -ForegroundColor Green }
function warn([string]$zh, [string]$en = '') { Write-Host "  ! $(t $zh $en)" -ForegroundColor Yellow }
function err([string]$zh, [string]$en = '') { Write-Host "  × $(t $zh $en)" -ForegroundColor Red }

function is_interactive {
    if ($env:EST_YES -eq '1') { return $false }
    try { -not [Console]::IsInputRedirected } catch { $true }
}

function pause {
    if (-not (is_interactive)) { return }
    Write-Host ''
    Write-Host "  $(t '按回车键继续……' 'Press Enter to continue...')" -NoNewline
    [void][Console]::ReadLine()
}

function die([string]$zh, [string]$en = '') {
    err $zh $en
    Write-Host ''
    Write-Host "  $(t '可以双击桌面上的「酒馆工具箱」选「诊断」，把生成的报告发给帮你的人。' 'Run "Diagnose" from the toolbox and send the report to whoever helps you.')"
    pause
    exit 1
}

# ask "问题" "question" 默认值(y/n)：返回 $true 表示「是」。非交互时用默认值。
function ask([string]$zh, [string]$en, [string]$def = 'y') {
    if (-not (is_interactive)) { return ($def -eq 'y') }
    if ($def -eq 'y') { $hint = '[Y/n]' } else { $hint = '[y/N]' }
    Write-Host "  $(t $zh $en) $hint " -NoNewline
    $reply = [Console]::ReadLine()
    if ($null -eq $reply) { $reply = '' }
    $reply = $reply.Trim()
    if ($reply -match '^(y|是|好|要)') { return $true }
    if ($reply -match '^(n|否|不)') { return $false }
    return ($def -eq 'y')
}

# 读一个编号；不是数字就返回 0
function read_number([string]$zh, [string]$en) {
    Write-Host "  $(t $zh $en) " -NoNewline
    $s = [Console]::ReadLine()
    $n = 0
    if ($s -and [int]::TryParse($s.Trim(), [ref]$n)) { $n } else { 0 }
}

function set_title([string]$zh, [string]$en) {
    try { $Host.UI.RawUI.WindowTitle = (t $zh $en) } catch {}
}

# 报告和提示里把用户目录换成 ~，免得把用户名发出去
function tilde([string]$s) {
    if ($env:USERPROFILE) { $s -replace [regex]::Escape($env:USERPROFILE), '~' } else { $s }
}

function stamp { Get-Date -Format 'yyyyMMdd-HHmmss' }

# --------------------------------------------------------------- 文件 ---

function ensure_dir([string]$p) { [void][IO.Directory]::CreateDirectory($p) }

function new_tmp {
    $d = "$TMP_ROOT\" + [guid]::NewGuid().ToString('N').Substring(0, 8)
    ensure_dir $d
    $d
}

# 删文件夹。node_modules 里路径很深，PowerShell 5.1 的 Remove-Item 经常删不干净，
# 所以优先用我们自己的 node 删；要删的正好包含 node 本身时用 rd
function remove_dir([string]$p) {
    if (-not (Test-Path -LiteralPath $p)) { return }
    $p = [IO.Path]::GetFullPath($p).TrimEnd('\')
    if ((Test-Path -LiteralPath $NODE) -and -not $NODE_DIR.StartsWith($p, [StringComparison]::OrdinalIgnoreCase)) {
        & $NODE -e "require('fs').rmSync(process.argv[1],{recursive:true,force:true,maxRetries:5})" $p 2>&1 | Out-Null
    }
    if (Test-Path -LiteralPath $p) { cmd.exe /d /c rd /s /q $p 2>&1 | Out-Null }
    if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue }
}

# 改文件夹名字。杀毒软件刚扫完新文件时会短暂占着，多试几次
function move_dir([string]$from, [string]$to) {
    for ($i = 0; $i -lt 20; $i++) {
        try { [IO.Directory]::Move($from, $to); return $true } catch { Start-Sleep -Milliseconds 500 }
    }
    $false
}

function size_text([string]$f) {
    '{0:N1} MB' -f ((Get-Item -LiteralPath $f).Length / 1MB)
}

# 只留最新的几个
function prune([string]$dir, [string]$filter, [int]$keep) {
    Get-ChildItem -LiteralPath $dir -Filter $filter -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -Skip $keep |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

function open_folder([string]$p) { Start-Process explorer.exe -ArgumentList "`"$p`"" }

# --------------------------------------------------------------- 状态 ---

function state_get([string]$key) {
    $v = ''
    if (Test-Path -LiteralPath $STATE) {
        foreach ($line in [IO.File]::ReadAllLines($STATE)) {
            if ($line.StartsWith("$key=")) { $v = $line.Substring($key.Length + 1) }
        }
    }
    $v
}

function state_set([string]$key, [string]$value) {
    ensure_dir $EST_HOME
    $lines = @()
    if (Test-Path -LiteralPath $STATE) {
        $lines = @([IO.File]::ReadAllLines($STATE) | Where-Object { -not $_.StartsWith("$key=") })
    }
    $lines += "$key=$value"
    [IO.File]::WriteAllLines($STATE, [string[]]$lines, $UTF8)
}

function is_installed { (Test-Path -LiteralPath $NODE) -and (Test-Path -LiteralPath "$APP_DIR\server.js") }

function st_version([string]$dir = $APP_DIR) {
    try { [string]([IO.File]::ReadAllText("$dir\package.json") | ConvertFrom-Json).version } catch { '' }
}

function node_version {
    if (Test-Path -LiteralPath $NODE) {
        try {
            $v = & $NODE -v 2>$null
            if ($LASTEXITCODE -eq 0) { return [string]$v }
        } catch {}
    }
    ''
}

# -------------------------------------------------------- 系统检测 ---

function regval([string]$path, [string]$name) {
    try { (Get-ItemProperty -LiteralPath $path -Name $name -ErrorAction Stop).$name } catch { $null }
}

function detect_system {
    $cv = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    # 别用 [Environment]::OSVersion：程序没声明兼容 Win10 时它会谎报 6.2
    $script:WIN_MAJOR = [int](regval $cv 'CurrentMajorVersionNumber')
    $script:WIN_BUILD = [int](regval $cv 'CurrentBuild')
    $script:WIN_DISPLAY = [string](regval $cv 'DisplayVersion')
    if (-not $WIN_DISPLAY) { $script:WIN_DISPLAY = [string](regval $cv 'ReleaseId') }
    if ($WIN_MAJOR -ge 10) {
        # Win11 的注册表里 ProductName 还写着 Windows 10，只能看版本号
        if ($WIN_BUILD -ge 22000) { $script:WIN_NAME = 'Windows 11' } else { $script:WIN_NAME = 'Windows 10' }
    } else {
        $script:WIN_NAME = [string](regval $cv 'ProductName')
    }

    # 看系统真正的 CPU，而不是当前 PowerShell 的：ARM 电脑上 x64 模拟运行时环境变量会说 AMD64
    $cpu = [string](regval 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' 'PROCESSOR_ARCHITECTURE')
    if (-not $cpu) { $cpu = $env:PROCESSOR_ARCHITECTURE }
    switch ($cpu) {
        'ARM64' { $script:ARCH = 'arm64' }
        'x86' { $script:ARCH = 'x86' }
        default { $script:ARCH = 'x64' }
    }

    try {
        $drive = New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($EST_HOME))
        $script:FREE_MB = [int]($drive.AvailableFreeSpace / 1MB)
    } catch {
        $script:FREE_MB = 999999
    }

    # Node.js 24 最低要 Win10；32 位系统 Node 23 以后就没有了，只能用 22
    if ($WIN_MAJOR -ge 10) {
        if ($ARCH -eq 'x86') { $script:NODE_MAJOR = '22' } else { $script:NODE_MAJOR = '24' }
    } else {
        $script:NODE_MAJOR = ''
    }
}

# ---------------------------------------------------------- 代理检测 ---

function tcp_open([string]$hostname, [int]$port) {
    $c = New-Object Net.Sockets.TcpClient
    try {
        $ar = $c.BeginConnect($hostname, $port, $null, $null)
        if ($ar.AsyncWaitHandle.WaitOne(2000) -and $c.Connected) { $c.EndConnect($ar); return $true }
        return $false
    } catch {
        return $false
    } finally {
        $c.Close()
    }
}

# 读「设置 → 网络 → 代理」（Clash、v2rayN 等开了「系统代理」就会写在这里）。
# 命令行里的程序默认不走系统代理，这里把它找出来，并确认代理软件真的开着。
function detect_proxy {
    $script:PROXY_URL = ''
    $script:PROXY_SRC = ''
    $script:PROXY_DEAD = ''
    # Windows 的环境变量不分大小写，https_proxy 和 HTTPS_PROXY 是同一个
    foreach ($v in @($env:HTTPS_PROXY, $env:ALL_PROXY)) {
        if ($v) { $script:PROXY_URL = $v; $script:PROXY_SRC = 'env'; return }
    }
    if ((state_get 'PROXY') -eq 'off') { return }

    $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
    if ((regval $key 'ProxyEnable') -ne 1) { return }
    $server = [string](regval $key 'ProxyServer')
    if (-not $server) { return }

    # 可能是 127.0.0.1:7890，也可能是 http=127.0.0.1:7890;https=…;socks=…
    $kind = 'http'
    $addr = ''
    if ($server.Contains('=')) {
        $map = @{}
        foreach ($part in $server.Split(';')) {
            $kv = $part.Split('=', 2)
            if ($kv.Count -eq 2) { $map[$kv[0].Trim().ToLower()] = $kv[1].Trim() }
        }
        if ($map['https']) { $addr = $map['https'] }
        elseif ($map['http']) { $addr = $map['http'] }
        elseif ($map['socks']) { $addr = $map['socks']; $kind = 'socks5' }
    } else {
        $addr = $server.Split(';')[0].Trim()
    }
    $addr = ($addr -replace '^[A-Za-z0-9]+://', '').TrimEnd('/')
    if ($addr -notmatch '^(.+):(\d+)$') { return }
    $h = $Matches[1]
    $p = [int]$Matches[2]
    # 代理软件关了但系统代理没清掉时，所有连接都会失败，这种情况当作没有代理
    if (-not (tcp_open $h $p)) {
        $script:PROXY_DEAD = "${kind}://$addr"
        return
    }
    $script:PROXY_URL = "${kind}://$addr"
    $script:PROXY_SRC = 'system'
}

function apply_proxy {
    if ($PROXY_URL -and $PROXY_SRC -eq 'system') {
        $env:HTTP_PROXY = $PROXY_URL
        $env:HTTPS_PROXY = $PROXY_URL
        $env:ALL_PROXY = $PROXY_URL
        $env:NO_PROXY = 'localhost,127.0.0.1,::1'
    }
    # 没有 curl.exe 时用 Invoke-WebRequest，它默认走系统代理；系统代理是死的就得让它直连
    try {
        if ($PROXY_URL -like 'http://*') {
            [Net.WebRequest]::DefaultWebProxy = New-Object Net.WebProxy $PROXY_URL
        } elseif ($PROXY_DEAD) {
            [Net.WebRequest]::DefaultWebProxy = $null
        }
    } catch {}
}

# ---------------------------------------------------------- 网络选源 ---

# 并行探测一组地址，返回 @{ 地址 = '状态码 秒数' }，连不上是 '000 0'
function probe_all([string[]]$urls) {
    $res = @{}
    if ($CURL) {
        $jobs = @()
        foreach ($u in $urls) {
            $psi = New-Object Diagnostics.ProcessStartInfo
            $psi.FileName = $CURL
            $psi.Arguments = '-s -o NUL -r 0-0 --connect-timeout 5 --max-time 8 ' + ($CURL_TLS -join ' ') +
                ' -w "%{http_code} %{time_total}" "' + $u + '"'
            $psi.UseShellExecute = $false
            $psi.RedirectStandardOutput = $true
            $psi.CreateNoWindow = $true
            $jobs += , @($u, [Diagnostics.Process]::Start($psi))
        }
        foreach ($j in $jobs) {
            $out = $j[1].StandardOutput.ReadToEnd()
            $j[1].WaitForExit()
            if ($out -match '^\d{3} [\d.]+') { $res[$j[0]] = $Matches[0] } else { $res[$j[0]] = '000 0' }
        }
    } else {
        foreach ($u in $urls) {
            $sw = [Diagnostics.Stopwatch]::StartNew()
            $code = 0
            try {
                $code = [int](Invoke-WebRequest -Uri $u -UseBasicParsing -TimeoutSec 8 -ErrorAction Stop).StatusCode
            } catch {
                try { $code = [int]$_.Exception.Response.StatusCode } catch {}
            }
            $res[$u] = '{0:000} {1}' -f $code, $sw.Elapsed.TotalSeconds.ToString('0.000', $INVARIANT)
        }
    }
    $res
}

# 打印最快能连上的那个地址；都连不上就返回空
function pick_fastest([string[]]$urls) {
    $r = probe_all $urls
    $best = ''
    $bestT = [double]::MaxValue
    foreach ($u in $urls) {
        $parts = $r[$u].Split(' ')
        if ($parts[0] -match '^[23]') {
            $tm = [double]::Parse($parts[1], $INVARIANT)
            if ($tm -lt $bestT) { $best = $u; $bestT = $tm }
        }
    }
    $best
}

function choose_sources {
    step '检测网络，挑最快的下载源' 'Checking the network and picking the fastest mirrors'
    detect_proxy
    if ($PROXY_URL) {
        ok "发现代理 ${PROXY_URL}，下载会走代理" "Using proxy $PROXY_URL"
    } elseif ($PROXY_DEAD) {
        warn "系统代理设置成了 ${PROXY_DEAD}，但它没在运行，先不走代理" "System proxy $PROXY_DEAD is set but not running; ignoring it"
    }
    apply_proxy

    $npmOfficial = 'https://registry.npmjs.org'
    $npmCn = 'https://registry.npmmirror.com'
    $winner = pick_fastest @("$npmOfficial/sillytavern/latest", "$npmCn/sillytavern/latest")
    if ($winner.StartsWith($npmOfficial)) {
        $script:NPM_REGISTRY = $npmOfficial; $script:NPM_FALLBACK = $npmCn; $script:REGION = 'global'
    } elseif ($winner.StartsWith($npmCn)) {
        $script:NPM_REGISTRY = $npmCn; $script:NPM_FALLBACK = $npmOfficial; $script:REGION = 'cn'
    } else {
        die '连不上网络（npm 官方源和国内镜像都打不开）。请检查网络后重试。' 'No network: neither npmjs.org nor npmmirror.com is reachable.'
    }

    $nodeOfficial = 'https://nodejs.org/dist'
    $nodeCn = 'https://cdn.npmmirror.com/binaries/node'
    # GitHub 上的小文件：国内优先走 jsDelivr
    if ($REGION -eq 'cn') {
        $script:NODE_MIRRORS = @($nodeCn, $nodeOfficial)
        $script:GH_ROUTES = @('jsd-fastly', 'jsd', 'raw')
        ok '使用国内镜像（npmmirror）' 'Using China mirrors (npmmirror)'
    } else {
        $script:NODE_MIRRORS = @($nodeOfficial, $nodeCn)
        $script:GH_ROUTES = @('raw', 'jsd', 'jsd-fastly')
        ok '使用官方源' 'Using official sources'
    }
    state_set 'REGION' $REGION
}

# gh_urls 仓库 版本 文件路径：按 GH_ROUTES 的顺序列出这个文件的几个下载地址
function gh_urls([string]$repo, [string]$ref, [string]$path) {
    foreach ($r in $GH_ROUTES) {
        switch ($r) {
            'raw' { "https://raw.githubusercontent.com/$repo/$ref/$path" }
            'jsd' { "https://cdn.jsdelivr.net/gh/$repo@$ref/$path" }
            'jsd-fastly' { "https://fastly.jsdelivr.net/gh/$repo@$ref/$path" }
        }
    }
}

function download([string]$url, [string]$out, [bool]$quiet) {
    if ($CURL) {
        if ($quiet) {
            & $CURL -fsSL --connect-timeout 8 --max-time 60 @CURL_TLS -o $out $url 2>$null
        } else {
            & $CURL -fL --connect-timeout 10 --retry 2 --retry-delay 2 --progress-bar @CURL_TLS -o $out $url
        }
        return ($LASTEXITCODE -eq 0)
    }
    if ($quiet) { $limit = 60 } else { $limit = 1800 }
    try {
        Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing -TimeoutSec $limit -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

# fetch 目标文件 地址列表 [-Quiet]：依次尝试，成功一个就停。-Quiet 用于小文件，不显示进度
function fetch([string]$dest, [string[]]$urls, [switch]$Quiet) {
    $part = "$dest.part"
    foreach ($u in $urls) {
        if (-not $u) { continue }
        Remove-Item -LiteralPath $part -Force -ErrorAction SilentlyContinue
        if (download $u $part $Quiet.IsPresent) {
            Move-Item -LiteralPath $part -Destination $dest -Force
            return $true
        }
        if (-not $Quiet) { warn "这个地址下载失败，换一个：$u" "Download failed, trying next: $u" }
    }
    Remove-Item -LiteralPath $part -Force -ErrorAction SilentlyContinue
    $false
}

# --------------------------------------------------------- 安装 Node ---

# 解 zip。PowerShell 5.1 底下的 .NET 不认 260 个字符以上的路径，所以解压的地方要尽量短；
# 不行再用 tar.exe，但它只认系统 ANSI 编码的路径（英文系统上的中文用户名会变成 ??），
# 所以让它在 zip 所在的文件夹里用相对路径干活
function unzip([string]$zip, [string]$dest) {
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [IO.Compression.ZipFile]::ExtractToDirectory($zip, $dest)
        return $true
    } catch {
        remove_dir $dest
    }
    if (-not $TAR) { return $false }
    $dir = Split-Path -Parent $zip
    $rel = $dest
    if ($dest.StartsWith("$dir\", [StringComparison]::OrdinalIgnoreCase)) { $rel = $dest.Substring($dir.Length + 1) }
    ensure_dir $dest
    Push-Location -LiteralPath $dir
    try {
        & $TAR -xf (Split-Path -Leaf $zip) -C $rel 2>&1 | Out-Null
        $LASTEXITCODE -eq 0
    } finally {
        Pop-Location
    }
}

function install_node {
    step '准备 Node.js（酒馆的运行环境）' 'Setting up Node.js'
    $cur = node_version
    if ($cur -match "^v$NODE_MAJOR\.") {
        ok "已经有 Node.js ${cur}，跳过" "Node.js $cur already installed"
        return
    }

    $tmp = new_tmp
    $ver = ''
    foreach ($base in $NODE_MIRRORS) {
        # index.json 一行一个版本，从新到旧排；挑这个大版本里第一个有 Windows zip 的
        if (fetch "$tmp\index.json" @("$base/index.json") -Quiet) {
            foreach ($line in [IO.File]::ReadAllLines("$tmp\index.json")) {
                if ($line -match "`"version`":`"(v$NODE_MAJOR\.[0-9.]+)`"" -and $line.Contains("`"win-$ARCH-zip`"")) {
                    $ver = $Matches[1]
                    break
                }
            }
            if ($ver) { break }
        }
    }
    if (-not $ver) { die '查不到 Node.js 的版本列表，网络可能不稳定，请稍后重试。' 'Could not get the Node.js version list.' }

    $file = "node-$ver-win-$ARCH.zip"
    info "下载 Node.js ${ver}（${ARCH}，约 35 MB）" "Downloading Node.js $ver ($ARCH, ~35 MB)"
    $got = $false
    foreach ($base in $NODE_MIRRORS) {
        if ((fetch "$tmp\$file" @("$base/$ver/$file")) -and (fetch "$tmp\SHASUMS256.txt" @("$base/$ver/SHASUMS256.txt") -Quiet)) {
            $got = $true
            break
        }
    }
    if (-not $got) { die 'Node.js 下载失败，请检查网络后重试。' 'Node.js download failed.' }

    $want = ''
    foreach ($line in [IO.File]::ReadAllLines("$tmp\SHASUMS256.txt")) {
        $f = $line.Trim() -split '\s+'
        if ($f.Count -ge 2 -and $f[1] -eq $file) { $want = $f[0].ToLower() }
    }
    $have = file_hash "$tmp\$file" ([Security.Cryptography.SHA256]::Create())
    $have = (($have | ForEach-Object { $_.ToString('x2') }) -join '')
    if (-not $want -or $want -ne $have) { die 'Node.js 安装包校验不通过（文件可能下坏了），请重试。' 'Node.js checksum mismatch.' }

    # zip 里是一层 node-v…-win-x64 文件夹，解到 runtime\x 后把这一层挪成 runtime\node（路径越短越好）
    ensure_dir "$EST_HOME\runtime"
    $stage = "$EST_HOME\runtime\x"
    remove_dir $stage
    if (-not (unzip "$tmp\$file" $stage)) { die 'Node.js 解压失败。' 'Failed to unpack Node.js.' }
    $inner = @(Get-ChildItem -LiteralPath $stage -Directory)
    remove_dir "$NODE_DIR.new"
    if ($inner.Count -ne 1 -or -not (move_dir $inner[0].FullName "$NODE_DIR.new")) { die 'Node.js 解压失败。' 'Failed to unpack Node.js.' }
    remove_dir $stage
    remove_dir $NODE_DIR
    if (Test-Path -LiteralPath $NODE_DIR) {
        die '旧的 Node.js 删不掉，可能酒馆还开着。请关掉所有酒馆窗口后重试。' 'Could not replace Node.js; close SillyTavern and try again.'
    }
    if (-not (move_dir "$NODE_DIR.new" $NODE_DIR)) { die 'Node.js 安装失败。' 'Failed to install Node.js.' }
    remove_dir $tmp
    $v = node_version
    if (-not $v) { die 'Node.js 装好了但运行不了。' 'Node.js was installed but does not run.' }
    ok "Node.js $v 安装完成" "Node.js $v installed"
}

# ------------------------------------------------------ 安装 SillyTavern ---

# 只用我们自己的 npm 配置和缓存，避开用户 .npmrc 里可能的怪设置
function npm_env {
    ensure_dir "$EST_HOME\runtime"
    [IO.File]::WriteAllText("$EST_HOME\runtime\npmrc", "registry=$NPM_REGISTRY`nfund=false`naudit=false`nupdate-notifier=false`n", $UTF8)
    $env:NPM_CONFIG_USERCONFIG = "$EST_HOME\runtime\npmrc"
    $env:NPM_CONFIG_CACHE = "$EST_HOME\runtime\npm-cache"
    if (-not $env:Path.StartsWith("$NODE_DIR;")) { $env:Path = "$NODE_DIR;$env:Path" }
}

# 返回 @{ Version; Url; Sri }，查不到返回 $null
function st_latest_meta {
    $tmp = new_tmp
    try {
        foreach ($reg in @($NPM_REGISTRY, $NPM_FALLBACK)) {
            if (fetch "$tmp\latest.json" @("$reg/sillytavern/latest") -Quiet) {
                try {
                    $j = [IO.File]::ReadAllText("$tmp\latest.json") | ConvertFrom-Json
                    if ($j.version -and $j.dist.tarball -and $j.dist.integrity) {
                        return @{ Version = [string]$j.version; Url = [string]$j.dist.tarball; Sri = [string]$j.dist.integrity }
                    }
                } catch {}
            }
        }
        $null
    } finally {
        remove_dir $tmp
    }
}

# 算文件的哈希，返回字节。不用 Get-FileHash：它在模块里，模块路径一乱就没了
function file_hash([string]$file, $algorithm) {
    $s = [IO.File]::OpenRead($file)
    try { , $algorithm.ComputeHash($s) } finally { $s.Dispose() }
}

# npm 的 integrity：「算法-base64」
function verify_integrity([string]$file, [string]$sri) {
    $i = $sri.IndexOf('-')
    if ($i -lt 1) { return $false }
    switch ($sri.Substring(0, $i)) {
        'sha512' { $h = [Security.Cryptography.SHA512]::Create() }
        'sha384' { $h = [Security.Cryptography.SHA384]::Create() }
        'sha256' { $h = [Security.Cryptography.SHA256]::Create() }
        default { return $false }
    }
    [Convert]::ToBase64String((file_hash $file $h)) -eq $sri.Substring($i + 1)
}

# 解 .tar.gz。优先用 npm 自带的 tar 库：中文路径、长路径都没问题；不行再用系统的 tar.exe
function extract_tgz([string]$file, [string]$dest, [int]$strip) {
    ensure_dir $dest
    $lib = "$NODE_DIR\node_modules\npm\node_modules\tar"
    if ((Test-Path -LiteralPath $NODE) -and (Test-Path -LiteralPath $lib)) {
        & $NODE -e "require(process.argv[1]).x({file:process.argv[2],cwd:process.argv[3],strip:+process.argv[4],sync:true})" $lib $file $dest $strip 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { return $true }
    }
    if ($TAR) {
        & $TAR -xzf $file -C $dest --strip-components $strip 2>&1 | Out-Null
        return ($LASTEXITCODE -eq 0)
    }
    $false
}

# install_st [force]：装最新版酒馆；已经是最新版就跳过
function install_st([string]$mode = '') {
    step '下载酒馆 SillyTavern' 'Downloading SillyTavern'
    npm_env
    $meta = st_latest_meta
    if (-not $meta) { die '查不到酒馆的最新版本，网络可能不稳定，请稍后重试。' 'Could not look up the latest SillyTavern version.' }
    $ver = $meta.Version
    $cur = st_version
    if ($cur -eq $ver -and (Test-Path -LiteralPath "$APP_DIR\node_modules") -and $mode -ne 'force') {
        ok "已经是最新版 $ver" "Already on the latest version $ver"
        return
    }
    if ($cur) { info "当前版本 $cur → 最新版本 $ver" "Current $cur → latest $ver" }

    $new = "$APP_DIR.new"
    $tmp = new_tmp
    info "下载酒馆 ${ver}（约 40 MB）" "Downloading SillyTavern $ver (~40 MB)"
    # 两个源的包是同一个文件，完整性校验值一样
    if (-not (fetch "$tmp\st.tgz" @($meta.Url, "$NPM_FALLBACK/sillytavern/-/sillytavern-$ver.tgz"))) {
        die '酒馆下载失败，请检查网络后重试。' 'SillyTavern download failed.'
    }
    if (-not (verify_integrity "$tmp\st.tgz" $meta.Sri)) {
        die '酒馆安装包校验不通过（文件可能下坏了），请重试。' 'SillyTavern package checksum mismatch.'
    }

    remove_dir $new
    if (-not (extract_tgz "$tmp\st.tgz" $new 1)) { die '酒馆解压失败。' 'Failed to unpack SillyTavern.' }

    # npm 上的包不带 package-lock.json，去 GitHub 拿对应版本的锁文件，保证装的依赖和官方一致
    $lockOk = $false
    if (fetch "$tmp\package-lock.json" (gh_urls 'SillyTavern/SillyTavern' $ver 'package-lock.json') -Quiet) {
        & $NODE -e 'process.exit(require(process.argv[1]).version===process.argv[2]?0:1)' "$tmp\package-lock.json" $ver 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Copy-Item -LiteralPath "$tmp\package-lock.json" -Destination "$new\package-lock.json" -Force
            $lockOk = $true
        }
    }

    step '安装酒馆需要的组件（1～3 分钟）' 'Installing dependencies (1-3 minutes)'
    $npmArgs = @('--omit=dev', '--ignore-scripts', '--no-audit', '--no-fund', '--loglevel=error')
    $npmOk = $false
    $env:NODE_ENV = 'production'
    Push-Location -LiteralPath $new
    try {
        for ($try = 1; $try -le 2; $try++) {
            if ($lockOk) {
                & $NODE $NPM_CLI ci @npmArgs
            } else {
                & $NODE $NPM_CLI install --no-save @npmArgs
            }
            if ($LASTEXITCODE -eq 0) { $npmOk = $true; break }
            if ($try -eq 2) { break }
            # 第一次失败就换另一个源再试
            warn '安装组件失败，换个源再试一次' 'npm failed, retrying with the other registry'
            $swap = $NPM_REGISTRY
            $script:NPM_REGISTRY = $NPM_FALLBACK
            $script:NPM_FALLBACK = $swap
            npm_env
        }
    } finally {
        Pop-Location
        Remove-Item Env:\NODE_ENV -ErrorAction SilentlyContinue
    }
    if (-not $npmOk) { die '酒馆的组件没装上。' "Failed to install SillyTavern's dependencies." }
    remove_dir "$EST_HOME\runtime\npm-cache"
    remove_dir $tmp

    # 换上新版本；旧版本留一份，新版本出问题时可以退回
    remove_dir "$APP_DIR.prev"
    if ((Test-Path -LiteralPath $APP_DIR) -and -not (move_dir $APP_DIR "$APP_DIR.prev")) {
        die '旧版本的酒馆文件被占用，换不了。请关掉所有酒馆窗口后重试。' 'The old SillyTavern folder is in use; close SillyTavern and try again.'
    }
    if (-not (move_dir $new $APP_DIR)) { die '新版本的酒馆放不进去。' 'Could not move the new SillyTavern into place.' }
    ok "酒馆 $ver 安装完成" "SillyTavern $ver installed"
}

# ------------------------------------------------------------- 配置 ---

function write_config {
    ensure_dir $DATA_DIR
    ensure_dir $LOG_DIR
    ensure_dir $BACKUP_DIR
    if (-not (Test-Path -LiteralPath $CONFIG)) {
        $text = [IO.File]::ReadAllText("$APP_DIR\default\config.yaml")
        # 没装 Git 的电脑占大多数，统一用酒馆内置的 git 功能装扩展
        $text = $text -replace '(?m)^  backend: auto(\r?)$', '  backend: builtin$1'
        [IO.File]::WriteAllText($CONFIG, $text, $UTF8)
        ok '已生成配置文件' 'Config created'
    }
    if (-not (Test-Path -LiteralPath $MARKER)) { [IO.File]::WriteAllText($MARKER, '') }
}

function seed_tokenizers {
    ensure_dir "$DATA_DIR\_cache"
    $missing = @($TOKENIZERS | Where-Object {
            $f = "$DATA_DIR\_cache\$_.json.gz"
            -not ((Test-Path -LiteralPath $f) -and (Get-Item -LiteralPath $f).Length -gt 0)
        })
    if ($missing.Count -eq 0) { return }
    step '预先下载分词器（让字数统计更准）' 'Pre-downloading tokenizers'
    foreach ($name in $missing) {
        if (fetch "$DATA_DIR\_cache\$name.json.gz" (gh_urls 'SillyTavern/SillyTavern-Tokenizers' 'main' "$name.json.gz") -Quiet) {
            ok $name
        } else {
            warn "$name 没下载到，不影响使用" "$name skipped (not required)"
        }
    }
}

# ------------------------------------------------------ 导入旧数据 ---

# 在 dir 下面最多 depth 层里找 …\data\default-user
function scan_dir([string]$dir, [int]$depth, $found) {
    if ([IO.Directory]::Exists("$dir\data\default-user")) { $found.Add("$dir\data") }
    if ($depth -le 0) { return }
    try { $subs = [IO.Directory]::GetDirectories($dir) } catch { return }
    foreach ($s in $subs) {
        $name = [IO.Path]::GetFileName($s)
        if ($name -in @('node_modules', '.git', 'public', 'AppData', '$RECYCLE.BIN', 'System Volume Information')) { continue }
        # 酒馆自己的 data 文件夹里面不用再往下翻了
        if ([IO.Directory]::Exists("$s\default-user")) { continue }
        # 跳过「我的音乐」这类链接文件夹，它们会绕回别处，还经常没权限
        try { if ([IO.File]::GetAttributes($s) -band [IO.FileAttributes]::ReparsePoint) { continue } } catch { continue }
        scan_dir $s ($depth - 1) $found
    }
}

# 找这台电脑上别的酒馆（官方安装、免安装包、STL 启动器……）的数据文件夹
function find_old_data {
    $found = New-Object 'Collections.Generic.List[string]'
    # 用户目录和各个盘根目录下的 SillyTavern*：SillyTavern、SillyTavern-release、SillyTavern-Launcher\SillyTavern…
    $tops = @(Get-ChildItem -LiteralPath $env:USERPROFILE -Directory -Filter 'SillyTavern*' -ErrorAction SilentlyContinue)
    foreach ($d in [IO.DriveInfo]::GetDrives()) {
        if ($d.DriveType -eq 'Fixed' -and $d.IsReady) {
            $tops += @(Get-ChildItem -LiteralPath $d.RootDirectory.FullName -Directory -Filter 'SillyTavern*' -ErrorAction SilentlyContinue)
        }
    }
    foreach ($d in $tops) { scan_dir $d.FullName 2 $found }

    $downloads = [string](regval 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders' '{374DE290-123F-4565-9164-39C4925E467B}')
    if (-not $downloads) { $downloads = "$env:USERPROFILE\Downloads" }
    # data\default-user 最深在第 6 层
    foreach ($d in @($EST_DESKTOP, $downloads, [Environment]::GetFolderPath('MyDocuments'))) {
        if ($d -and [IO.Directory]::Exists($d)) { scan_dir $d 4 $found }
    }

    $seen = @{}
    foreach ($p in $found) {
        $full = [IO.Path]::GetFullPath($p)
        if ($full.StartsWith("$EST_HOME\", [StringComparison]::OrdinalIgnoreCase)) { continue }
        if ($seen.ContainsKey($full.ToLower())) { continue }
        $seen[$full.ToLower()] = 1
        $full
    }
}

# 这个数据文件夹里有多少聊天和角色，帮用户认出是哪一个
function describe_data([string]$dir) {
    $chats = 0
    $chars = 0
    foreach ($u in @(Get-ChildItem -LiteralPath $dir -Directory -ErrorAction SilentlyContinue)) {
        if (Test-Path -LiteralPath "$($u.FullName)\chats") {
            $chats += @(Get-ChildItem -LiteralPath "$($u.FullName)\chats" -Filter '*.jsonl' -Recurse -File -ErrorAction SilentlyContinue).Count
        }
        if (Test-Path -LiteralPath "$($u.FullName)\characters") {
            $chars += @(Get-ChildItem -LiteralPath "$($u.FullName)\characters" -Filter '*.png' -File -ErrorAction SilentlyContinue).Count
        }
    }
    t "$chars 个角色、$chats 段聊天" "$chars characters, $chats chats"
}

function import_data([string]$src, [string]$label = '') {
    if (Test-Path -LiteralPath "$DATA_DIR\default-user") {
        info '先把现在的数据备份一下' 'Backing up current data first'
        [void](do_backup 'auto')
    }
    ensure_dir $DATA_DIR
    # robocopy 合并复制，原文件不动；中文文件名、长路径都没问题。返回值 8 以上才是出错
    & robocopy.exe $src $DATA_DIR /E /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { return $false }
    if (-not $label) { $label = tilde $src }
    ok "已导入：$label" "Imported: $label"
    $true
}

function offer_import([string]$mode = '') {
    $list = @(find_old_data)
    if ($list.Count -eq 0) {
        if ($mode -eq 'menu') { info '没有找到别的酒馆数据。' 'No other SillyTavern data found.' }
        return
    }
    step '发现这台电脑上已经有酒馆的聊天记录' 'Found existing SillyTavern data on this PC'
    for ($i = 0; $i -lt $list.Count; $i++) {
        Write-Host ('   {0}) {1}  ' -f ($i + 1), (tilde $list[$i])) -NoNewline
        Write-Host "($(describe_data $list[$i]))" -ForegroundColor DarkGray
    }
    info '导入是「复制」，原来的文件不会被改动。' 'Importing copies the files; the originals stay untouched.'
    if (-not (is_interactive)) {
        info '（非交互模式，跳过导入）' '(non-interactive, skipping import)'
        return
    }
    $n = read_number '要导入哪一个？输入编号，直接回车跳过：' 'Import which one? Enter a number, or press Enter to skip:'
    if ($n -lt 1 -or $n -gt $list.Count) { info '跳过导入' 'Skipped'; return }
    if (-not (import_data $list[$n - 1])) { err '导入失败。' 'Import failed.' }
}

# --------------------------------------------------------- 快捷方式 ---

function script_version([string]$file) {
    $m = Select-String -LiteralPath $file -Pattern "^\`$EST_VERSION = '([^']+)'" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($m) { $m.Matches[0].Groups[1].Value } else { '' }
}

# 带 BOM、能解析、有版本号，才算是一个完好的工具箱
function script_ok([string]$file) {
    try {
        $b = [IO.File]::ReadAllBytes($file)
        if ($b.Length -lt 3 -or $b[0] -ne 0xEF -or $b[1] -ne 0xBB -or $b[2] -ne 0xBF) { return $false }
        $tokens = $null
        $errors = $null
        [void][Management.Automation.Language.Parser]::ParseFile($file, [ref]$tokens, [ref]$errors)
        (@($errors).Count -eq 0) -and [bool](script_version $file)
    } catch {
        $false
    }
}

function install_self {
    ensure_dir $EST_HOME
    $me = $SCRIPT_PATH
    if (-not $me -or -not (Test-Path -LiteralPath $me)) { return }
    if ([IO.Path]::GetFullPath($me) -eq [IO.Path]::GetFullPath($SELF)) { return }
    if (script_ok $me) {
        Copy-Item -LiteralPath $me -Destination $SELF -Force
        Unblock-File -LiteralPath $SELF -ErrorAction SilentlyContinue
    }
}

# 建 .lnk。不用 WScript.Shell：它按系统 ANSI 编码处理路径，英文系统上遇到中文用户名、
# 中文快捷方式名会存成 ?? 甚至直接存不了。这里先写一个空的 .lnk 文件头，
# 再用 Shell.Application（全程 Unicode）把内容填进去
function new_shortcut([string]$path, [string]$target, [string]$arguments, [string]$workdir, [string]$icon, [string]$desc) {
    $head = New-Object byte[] 80
    $head[0] = 0x4C
    ([guid]'00021401-0000-0000-C000-000000000046').ToByteArray().CopyTo($head, 4)
    $head[60] = 1
    [IO.File]::WriteAllBytes($path, $head)
    $link = (New-Object -ComObject Shell.Application).NameSpace((Split-Path -Parent $path)).ParseName((Split-Path -Leaf $path)).GetLink
    $link.Path = $target
    $link.Arguments = $arguments
    $link.WorkingDirectory = $workdir
    $link.Description = $desc
    if ($icon -and (Test-Path -LiteralPath $icon)) { $link.SetIconLocation($icon, 0) }
    $link.Save()
}

# 桌面快捷方式直接指向 powershell.exe，不经过 .bat：
# 少一层 cmd，按 Ctrl+C 时不会再问「终止批处理操作吗(Y/N)?」，杀毒软件也不爱拦
function make_shortcuts {
    if ($env:EST_NO_SHORTCUTS -eq '1') { return }
    if (-not $EST_DESKTOP -or -not (Test-Path -LiteralPath $EST_DESKTOP)) { return }
    $icon = "$EST_HOME\sillytavern.ico"
    if (Test-Path -LiteralPath "$APP_DIR\public\favicon.ico") {
        Copy-Item -LiteralPath "$APP_DIR\public\favicon.ico" -Destination $icon -Force
    }
    $startName = t '酒馆 SillyTavern' 'SillyTavern'
    $toolsName = t '酒馆工具箱' 'SillyTavern Toolbox'
    $start = "$EST_DESKTOP\$startName.lnk"
    $tools = "$EST_DESKTOP\$toolsName.lnk"
    $ps = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    try {
        new_shortcut $start $ps "-NoProfile -ExecutionPolicy Bypass -File `"$SELF`" start" $EST_HOME $icon (t '启动酒馆' 'Start SillyTavern')
        new_shortcut $tools $ps "-NoProfile -ExecutionPolicy Bypass -File `"$SELF`" menu" $EST_HOME $icon (t '更新、备份、诊断、卸载' 'Update, back up, diagnose, uninstall')
    } catch {
        warn '桌面快捷方式没建好，可以在工具箱里重新「检查更新」试试。' 'Could not create the Desktop shortcuts.'
        return
    }
    state_set 'SHORTCUTS' "$start|$tools"
    ok "桌面上放好了「${startName}」和「${toolsName}」" 'Shortcuts created on the Desktop'
}

# ------------------------------------------------------------- 启动 ---

# 正在监听的端口和进程：@{ Port; Owner }
function listeners {
    $rows = @()
    try {
        foreach ($c in @(Get-NetTCPConnection -State Listen -ErrorAction Stop)) {
            $rows += New-Object psobject -Property @{ Port = [int]$c.LocalPort; Owner = [int]$c.OwningProcess }
        }
    } catch {
        foreach ($line in @(netstat.exe -ano -p TCP) + @(netstat.exe -ano -p TCPv6)) {
            if ($line -match '^\s*TCP\s+\S*:(\d+)\s+\S*:0\s+\S+\s+(\d+)\s*$') {
                $rows += New-Object psobject -Property @{ Port = [int]$Matches[1]; Owner = [int]$Matches[2] }
            }
        }
    }
    $rows
}

# 正在运行的「这一份」酒馆的端口。别的酒馆（比如用户自己另装的一份）占着端口不算：
# 看监听端口的进程命令行里是不是我们的 app\server.js
function st_running_port {
    if (-not (Test-Path -LiteralPath $APP_DIR)) { return '' }
    $want = "$APP_DIR\server.js"
    $mine = @(listeners | Where-Object { $_.Port -ge $PORT_FIRST -and $_.Port -le $PORT_LAST } | Sort-Object Port)
    foreach ($l in $mine) {
        $cmdline = ''
        try { $cmdline = [string](Get-CimInstance Win32_Process -Filter "ProcessId=$($l.Owner)" -ErrorAction Stop).CommandLine } catch {}
        if ($cmdline) {
            if ($cmdline.IndexOf($want, [StringComparison]::OrdinalIgnoreCase) -ge 0) { return [string]$l.Port }
        } else {
            try { if ((Get-Process -Id $l.Owner -ErrorAction Stop).Path -eq $NODE) { return [string]$l.Port } } catch {}
        }
    }
    ''
}

# 光看有没有人监听不够：Hyper-V / WSL 会整段保留端口（常见 7900～8000），
# 那些端口谁也监听不了，所以真去占一下试试
function port_free([int]$port, $busy) {
    if ($busy -contains $port) { return $false }
    $l = New-Object Net.Sockets.TcpListener ([Net.IPAddress]::Loopback, $port)
    try { $l.Start(); $true } catch { $false } finally { try { $l.Stop() } catch {} }
}

function free_port {
    $busy = @(listeners | ForEach-Object { $_.Port })
    $pref = state_get 'PORT'
    if ($pref -match '^\d+$' -and (port_free ([int]$pref) $busy)) { return $pref }
    foreach ($p in $PORT_FIRST..$PORT_LAST) {
        if (port_free $p $busy) { return [string]$p }
    }
    ''
}

function cmd_start {
    set_title '酒馆 SillyTavern（用的时候别关这个窗口）' 'SillyTavern (keep this window open)'
    if (-not (is_installed)) { die '酒馆还没装好，请重新运行安装命令。' 'SillyTavern is not installed yet.' }

    $port = st_running_port
    if ($port) {
        ok '酒馆已经在运行，已在浏览器里打开。这个窗口可以关掉。' 'SillyTavern is already running; opened it in your browser.'
        if ($env:EST_NO_BROWSER -ne '1') { Start-Process "http://127.0.0.1:$port/" }
        Start-Sleep -Seconds 3
        exit 0
    }
    $port = free_port
    if (-not $port) {
        die "端口 ${PORT_FIRST}～$PORT_LAST 都被占用了，重启电脑后再试。" "Ports $PORT_FIRST-$PORT_LAST are all busy. Restart your PC and try again."
    }
    if ($port -ne [string]$PORT_FIRST) { warn "$PORT_FIRST 端口被别的程序占了，这次用 $port" "Port $PORT_FIRST is busy, using $port" }

    $extra = @()
    detect_proxy
    if ($PROXY_URL) {
        # 让酒馆连 OpenAI、Claude、Gemini 这些接口时也走代理
        $extra += '--requestProxyEnabled=true'
        $extra += "--requestProxyUrl=$PROXY_URL"
    }
    if ($env:EST_NO_BROWSER -eq '1') { $extra += '--browserLaunchEnabled=false' }
    if (-not $env:Path.StartsWith("$NODE_DIR;")) { $env:Path = "$NODE_DIR;$env:Path" }

    $ver = st_version
    try { Clear-Host } catch {}
    Write-Host ''
    Write-Host '  ================================================'
    Write-Host (t "      酒馆 SillyTavern $ver 正在启动……" "      Starting SillyTavern $ver...")
    Write-Host ''
    Write-Host (t '   · 启动好后浏览器会自动打开' '   · Your browser will open by itself')
    Write-Host (t '   · 用的时候【不要关掉】这个窗口' '   · Keep this window open while you use it')
    Write-Host (t '   · 用完直接关掉这个窗口就行' '   · Close this window when you are done')
    Write-Host (t "   · 浏览器没打开的话，手动访问 http://127.0.0.1:$port" "   · If the browser does not open: http://127.0.0.1:$port")
    if ($PROXY_URL) { Write-Host (t "   · 已自动使用代理 $PROXY_URL" "   · Using proxy $PROXY_URL") }
    Write-Host '  ================================================'
    Write-Host (t '   （下面滚动的英文是运行记录，不用管）' '   (The log below is for troubleshooting.)')
    Write-Host ''

    ensure_dir $LOG_DIR
    prune $LOG_DIR 'st-*.log' 4
    $log = "$LOG_DIR\st-$(stamp).log"
    Set-Location -LiteralPath $APP_DIR
    $env:NODE_ENV = 'production'
    $writer = New-Object IO.StreamWriter($log, $true, $UTF8)
    $writer.AutoFlush = $true
    $code = 0
    try {
        # 用 app\server.js 的完整路径启动，st_running_port 靠它认出「这一份」酒馆
        & $NODE "$APP_DIR\server.js" --configPath $CONFIG --dataRoot $DATA_DIR --port $port @extra 2>&1 | ForEach-Object {
            $line = "$_"
            Write-Host $line
            $writer.WriteLine($line)
        }
        $code = $LASTEXITCODE
    } finally {
        $writer.Close()
    }

    Write-Host ''
    # -1073741510 是 Ctrl+C 结束时 Windows 给的退出码
    if ($code -ne 0 -and $code -ne 130 -and $code -ne -1073741510) {
        err "酒馆意外退出了（错误码 ${code}）。" "SillyTavern exited unexpectedly (code $code)."
        info "运行记录：$log" "Log: $log"
        info '可以打开「酒馆工具箱」选「诊断」生成报告。' 'Run Diagnose from the toolbox for a report.'
    } else {
        ok '酒馆已关闭。' 'SillyTavern stopped.'
    }
    pause
    exit $code
}

# ------------------------------------------------------------- 备份 ---

# 把 data 和 config.yaml 打成 zip。用 .NET 自己写：中文文件名一律存 UTF-8，换台电脑也不乱码。
# 缓存类的文件夹不备份，能自己重新生成。返回没备份上的文件数（被别的程序锁住的）
function zip_data([string]$zipPath) {
    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
    $skipped = 0
    $base = "$EST_HOME\"
    $exclude = @('data\_cache\', 'data\_webpack\', 'data\_uploads\')
    $zip = [IO.Compression.ZipFile]::Open($zipPath, [IO.Compression.ZipArchiveMode]::Create)
    try {
        $files = @([IO.Directory]::GetFiles($DATA_DIR, '*', [IO.SearchOption]::AllDirectories))
        if (Test-Path -LiteralPath $CONFIG) { $files += $CONFIG }
        foreach ($file in $files) {
            $rel = $file.Substring($base.Length)
            $skip = $false
            foreach ($e in $exclude) { if ($rel.StartsWith($e, [StringComparison]::OrdinalIgnoreCase)) { $skip = $true } }
            if ($skip) { continue }
            try {
                [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $file, $rel.Replace('\', '/'), [IO.Compression.CompressionLevel]::Fastest)
            } catch {
                $skipped++
            }
        }
    } finally {
        $zip.Dispose()
    }
    $skipped
}

# do_backup [auto|manual|final]：打包到 backups\，返回文件路径；自动备份只留最近 5 份
function do_backup([string]$kind = 'manual') {
    if (-not (Test-Path -LiteralPath $DATA_DIR)) { return $null }
    ensure_dir $BACKUP_DIR
    $f = "$BACKUP_DIR\$kind-$(stamp).zip"
    try {
        $skipped = zip_data $f
        if ($skipped -gt 0) { warn "有 $skipped 个文件正被占用，没备份上" "$skipped file(s) were in use and skipped" }
    } catch {
        Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue
        return $null
    }
    prune $BACKUP_DIR 'auto-*.zip' 5
    $f
}

function cmd_backup {
    step '备份聊天记录和设置' 'Backing up your data'
    $f = do_backup 'manual'
    if (-not $f) { die '备份失败。' 'Backup failed.' }
    ok "备份好了：${f}（$(size_text $f)）" "Backup saved: $f ($(size_text $f))"
    Start-Process explorer.exe -ArgumentList "/select,`"$f`""
}

function backup_list {
    $items = @()
    $items += @(Get-ChildItem -Path "$BACKUP_DIR\*" -Include '*.zip', '*.tar.gz' -File -ErrorAction SilentlyContinue)
    if ($EST_DESKTOP -and (Test-Path -LiteralPath $EST_DESKTOP)) {
        # Mac 版做的 .tar.gz 备份也认，换电脑时直接拷过来就能恢复
        $items += @(Get-ChildItem -Path "$EST_DESKTOP\*" -Include '酒馆数据备份-*.zip', '酒馆数据备份-*.tar.gz', 'SillyTavern-backup-*.zip', 'SillyTavern-backup-*.tar.gz' -File -ErrorAction SilentlyContinue)
    }
    $items | Sort-Object LastWriteTime -Descending
}

function cmd_restore {
    if (st_running_port) { die '请先关掉酒馆再恢复。' 'Close SillyTavern first.' }
    $list = @(backup_list)
    if ($list.Count -eq 0) { info '还没有备份。' 'No backups yet.'; return }
    step '选一个备份恢复（越靠上越新）' 'Pick a backup to restore (newest first)'
    for ($i = 0; $i -lt $list.Count; $i++) {
        Write-Host ('   {0}) {1}  ' -f ($i + 1), $list[$i].Name) -NoNewline
        Write-Host "($(size_text $list[$i].FullName))" -ForegroundColor DarkGray
    }
    if (-not (is_interactive)) { return }
    $n = read_number '输入编号，直接回车取消：' 'Enter a number, or press Enter to cancel:'
    if ($n -lt 1 -or $n -gt $list.Count) { return }
    $f = $list[$n - 1]
    $tmp = new_tmp
    if ($f.Name -like '*.zip') { $okx = unzip $f.FullName $tmp } else { $okx = extract_tgz $f.FullName $tmp 0 }
    if (-not $okx -or -not (Test-Path -LiteralPath "$tmp\data")) {
        remove_dir $tmp
        die '这个备份文件打不开。' 'Cannot read this backup.'
    }
    # 恢复前 import_data 会先把现在的数据再备份一份，恢复错了还能回来
    if (-not (import_data "$tmp\data" $f.Name)) { err '恢复失败。' 'Restore failed.' }
    remove_dir $tmp
}

# ------------------------------------------------------------- 更新 ---

function self_update {
    $tmp = new_tmp
    if (fetch "$tmp\easy-st.ps1" (gh_urls $EST_REPO $EST_BRANCH 'windows/easy-st.ps1') -Quiet) {
        $newVer = script_version "$tmp\easy-st.ps1"
        # 先检查能不能解析，下坏了或者被网页替换了都不会覆盖
        if ($newVer -and $newVer -ne $EST_VERSION -and (script_ok "$tmp\easy-st.ps1")) {
            Copy-Item -LiteralPath "$tmp\easy-st.ps1" -Destination $SELF -Force
            ok "工具箱已更新到 $newVer" "Toolbox updated to $newVer"
        }
    }
    remove_dir $tmp
}

function cmd_update {
    if (-not (is_installed)) { die '酒馆还没装好，请重新运行安装命令。' 'SillyTavern is not installed yet.' }
    if (st_running_port) { die '酒馆正在运行。请先关掉酒馆的黑色窗口，再来更新。' 'SillyTavern is running. Close it first.' }
    detect_system
    choose_sources
    self_update
    step '更新前先自动备份' 'Backing up before updating'
    $f = do_backup 'auto'
    if ($f) { ok $f } else { warn '备份失败，继续更新（聊天记录不会被更新动到）' 'Backup failed; continuing' }
    install_node
    install_st
    write_config
    seed_tokenizers
    make_shortcuts
    remove_dir $TMP_ROOT
    ok '更新完成' 'Update finished'
}

function cmd_rollback {
    if (-not (Test-Path -LiteralPath "$APP_DIR.prev")) { die '没有可以退回的旧版本。' 'No previous version to roll back to.' }
    if (st_running_port) { die '请先关掉酒馆再退回。' 'Close SillyTavern first.' }
    $cur = st_version
    $prev = st_version "$APP_DIR.prev"
    if (-not (ask "从 $cur 退回到 ${prev}？" "Roll back from $cur to ${prev}?" 'y')) { return }
    remove_dir "$APP_DIR.rollback"
    if (-not (move_dir $APP_DIR "$APP_DIR.rollback")) { die '酒馆文件被占用，退不回去。' 'SillyTavern files are in use.' }
    if (-not (move_dir "$APP_DIR.prev" $APP_DIR)) {
        [void](move_dir "$APP_DIR.rollback" $APP_DIR)
        die '退回失败。' 'Rollback failed.'
    }
    [void](move_dir "$APP_DIR.rollback" "$APP_DIR.prev")
    ok "已退回到 $prev" "Rolled back to $prev"
}

# ------------------------------------------------------------- 诊断 ---

function cmd_doctor {
    detect_system
    if ($EST_DESKTOP -and (Test-Path -LiteralPath $EST_DESKTOP)) {
        $report = "$EST_DESKTOP\$(t '酒馆诊断报告' 'SillyTavern-diagnostics')-$(stamp).txt"
    } else {
        ensure_dir $EST_HOME
        $report = "$EST_HOME\diagnostics.txt"
    }
    step '正在检查……' 'Checking...'
    $out = New-Object 'Collections.Generic.List[string]'
    $out.Add("Easy SillyTavern $EST_VERSION diagnostics  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
    $out.Add("$WIN_NAME $WIN_DISPLAY build=$WIN_BUILD  arch=$ARCH  ps=$($PSVersionTable.PSVersion)  free=${FREE_MB}MB  lang=$EST_LANG  curl=$([bool]$CURL)  tar=$([bool]$TAR)")
    $inst = 'no'
    if (is_installed) { $inst = 'yes' }
    $out.Add("home=$(tilde $EST_HOME)  installed=$inst")
    $nv = node_version
    if (-not $nv) { $nv = 'none' }
    $out.Add("node=$nv  want_major=$NODE_MAJOR")
    $prev = 'no'
    if (Test-Path -LiteralPath "$APP_DIR.prev") { $prev = 'yes' }
    $out.Add("sillytavern=$(st_version)  prev=$prev")
    $st = ''
    if (Test-Path -LiteralPath $STATE) { $st = [IO.File]::ReadAllLines($STATE) -join ' ' }
    $out.Add("state: $(tilde $st)")
    detect_proxy
    $out.Add("proxy=$(if ($PROXY_URL) { $PROXY_URL } else { 'none' }) src=$PROXY_SRC dead=$PROXY_DEAD")
    $rp = st_running_port
    if (-not $rp) { $rp = 'none' }
    $out.Add("running_port=$rp")
    $ls = @(listeners)
    foreach ($p in 8000..8002) {
        $who = ''
        foreach ($l in @($ls | Where-Object { $_.Port -eq $p } | Select-Object -First 1)) {
            $name = '?'
            try { $name = (Get-Process -Id $l.Owner -ErrorAction Stop).ProcessName } catch {}
            $who = "$name pid=$($l.Owner)"
        }
        $out.Add("port ${p}: $who")
    }
    $out.Add('--- network (http_code seconds)')
    apply_proxy
    $urls = @(
        'https://registry.npmjs.org/sillytavern/latest', 'https://registry.npmmirror.com/sillytavern/latest',
        'https://nodejs.org/dist/index.json', 'https://cdn.npmmirror.com/binaries/node/index.json',
        'https://raw.githubusercontent.com/SillyTavern/SillyTavern/release/package.json',
        'https://fastly.jsdelivr.net/gh/SillyTavern/SillyTavern@release/package.json',
        'https://api.openai.com', 'https://api.anthropic.com', 'https://generativelanguage.googleapis.com',
        'https://api.deepseek.com')
    $res = probe_all $urls
    foreach ($u in $urls) { $out.Add("$u $($res[$u])") }
    $out.Add('--- config (non-default keys)')
    if ((Test-Path -LiteralPath $CONFIG) -and (Test-Path -LiteralPath "$APP_DIR\default\config.yaml")) {
        $def = @{}
        foreach ($line in [IO.File]::ReadAllLines("$APP_DIR\default\config.yaml")) { $def[$line] = 1 }
        $diff = @([IO.File]::ReadAllLines($CONFIG) | Where-Object { -not $def.ContainsKey($_) -and $_ -notmatch 'pass|token|secret|key' })
        foreach ($line in ($diff | Select-Object -First 30)) { $out.Add("> $line") }
    }
    $out.Add('--- last log')
    $last = Get-ChildItem -LiteralPath $LOG_DIR -Filter 'st-*.log' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($last) {
        foreach ($line in @(Get-Content -LiteralPath $last.FullName -Tail 80 -Encoding UTF8)) { $out.Add((tilde $line)) }
    }
    # 带 BOM，老版本的记事本才认得出是 UTF-8
    [IO.File]::WriteAllLines($report, [string[]]$out, $UTF8BOM)
    ok "报告在：$report" "Report saved: $report"
    info '报告里没有你的 API 密钥和聊天内容，可以放心发给别人。' 'The report contains no API keys or chats.'
    Start-Process notepad.exe -ArgumentList "`"$report`""
}

# ------------------------------------------------------------- 卸载 ---

function cmd_uninstall {
    if (-not (Test-Path -LiteralPath $MARKER)) {
        die "$EST_HOME 不是 Easy SillyTavern 的安装目录，不敢删。" "$EST_HOME does not look like an Easy SillyTavern install; refusing to delete it."
    }
    if (st_running_port) { die '请先关掉酒馆再卸载。' 'Close SillyTavern first.' }
    step '卸载酒馆' 'Uninstall'
    if ((Test-Path -LiteralPath "$DATA_DIR\default-user") -and
        (ask '先把聊天记录和角色卡备份到桌面吗？（强烈建议）' 'Save your chats and characters to the Desktop first? (recommended)' 'y')) {
        $keep = do_backup 'final'
        if (-not $keep) { die '备份失败，没有卸载。' 'Backup failed; nothing was removed.' }
        if ($EST_DESKTOP -and (Test-Path -LiteralPath $EST_DESKTOP)) {
            $dest = "$EST_DESKTOP\$(t '酒馆数据备份' 'SillyTavern-backup')-$(stamp).zip"
            try { Move-Item -LiteralPath $keep -Destination $dest -ErrorAction Stop; $keep = $dest } catch {}
        }
        if ($keep.StartsWith("$EST_HOME\", [StringComparison]::OrdinalIgnoreCase)) {
            die "备份没法放到桌面（${keep}），为了安全没有卸载。" "Could not move the backup to the Desktop; nothing was removed."
        }
        ok "备份在：$keep" "Backup: $keep"
    }
    if (-not (ask "确定删除 $EST_HOME 吗？" "Delete ${EST_HOME}?" 'n')) { info '已取消' 'Cancelled'; return }
    $s = state_get 'SHORTCUTS'
    foreach ($lnk in $s.Split('|')) {
        if ($lnk) { Remove-Item -LiteralPath $lnk -Force -ErrorAction SilentlyContinue }
    }
    Set-Location -LiteralPath $env:USERPROFILE
    # 先趁 node 还在，用它删 app 这些路径很深的文件夹，最后再删 node 自己
    foreach ($child in @(Get-ChildItem -LiteralPath $EST_HOME -Force -ErrorAction SilentlyContinue)) {
        if ($child.Name -eq 'runtime') { continue }
        if ($child.PSIsContainer) { remove_dir $child.FullName } else { Remove-Item -LiteralPath $child.FullName -Force -ErrorAction SilentlyContinue }
    }
    remove_dir $EST_HOME
    if (Test-Path -LiteralPath $EST_HOME) {
        warn "有些文件没删掉，可以重启电脑后手动删除：$EST_HOME" "Some files could not be removed: $EST_HOME"
    } else {
        ok '已卸载。' 'Uninstalled.'
    }
    pause
    exit 0
}

# ------------------------------------------------------------- 菜单 ---

function cmd_menu {
    set_title '酒馆工具箱' 'SillyTavern Toolbox'
    while ($true) {
        try { Clear-Host } catch {}
        Write-Host ''
        Write-Host "  ==============  $(t '酒馆工具箱' 'SillyTavern Toolbox')  =============="
        Write-Host "  $(t '酒馆版本' 'Version'): $(st_version)    $(t '工具箱' 'Toolbox'): $EST_VERSION"
        Write-Host ''
        Write-Host "   1) $(t '启动酒馆' 'Start SillyTavern')"
        Write-Host "   2) $(t '检查更新' 'Check for updates')"
        Write-Host "   3) $(t '备份聊天记录和设置' 'Back up data')"
        Write-Host "   4) $(t '打开数据文件夹（角色卡、聊天记录在这里）' 'Open the data folder')"
        Write-Host "   5) $(t '从别的酒馆导入聊天记录' 'Import data from another SillyTavern')"
        Write-Host "   6) $(t '从备份恢复' 'Restore from a backup')"
        Write-Host "   7) $(t '诊断（出问题时用，生成报告）' 'Diagnose (creates a report)')"
        Write-Host "   8) $(t '退回上一个版本' 'Roll back to the previous version')"
        Write-Host "   9) $(t '卸载' 'Uninstall')"
        Write-Host "   0) $(t '退出' 'Quit')"
        Write-Host ''
        Write-Host "  $(t '输入数字后按回车：' 'Choose:') " -NoNewline
        $c = [Console]::ReadLine()
        if ($null -eq $c) { exit 0 }
        switch ($c.Trim()) {
            '1' { cmd_start }
            '2' { cmd_update; pause }
            '3' { cmd_backup; pause }
            '4' { if (Test-Path -LiteralPath "$DATA_DIR\default-user") { open_folder "$DATA_DIR\default-user" } else { ensure_dir $DATA_DIR; open_folder $DATA_DIR } }
            '5' { offer_import 'menu'; pause }
            '6' { cmd_restore; pause }
            '7' { cmd_doctor; pause }
            '8' { cmd_rollback; pause }
            '9' { cmd_uninstall; pause }
            '0' { exit 0 }
            'q' { exit 0 }
        }
    }
}

# ------------------------------------------------------------- 安装 ---

function cmd_install {
    set_title '安装酒馆 SillyTavern' 'Installing SillyTavern'
    Write-Host ''
    Write-Host '  ================================================'
    Write-Host (t '      酒馆 SillyTavern 一键安装' '      SillyTavern one-click installer')
    Write-Host (t '      不需要管理员权限，全程大约 2～5 分钟' '      No admin rights needed, about 2-5 minutes')
    Write-Host '  ================================================'
    detect_system
    step '检查这台电脑' 'Checking this PC'
    $chip = $ARCH
    if ($ARCH -eq 'arm64') { $chip = t 'ARM 芯片' 'ARM' } elseif ($ARCH -eq 'x86') { $chip = t '32 位' '32-bit' }
    info "$WIN_NAME $WIN_DISPLAY ($WIN_BUILD) · $chip"
    if (-not $NODE_MAJOR) {
        die "这台电脑的系统太旧了（${WIN_NAME}），酒馆最低需要 Windows 10。" "$WIN_NAME is too old; SillyTavern needs Windows 10 or newer."
    }
    if ($ARCH -eq 'x86') {
        warn '32 位系统只能用 Node.js 22，以后可能装不了新版酒馆，建议换 64 位系统。' '32-bit Windows: falling back to Node.js 22.'
    }
    if ($FREE_MB -lt 1500) {
        die "硬盘空间不够，至少需要 1.5 GB，现在只剩 ${FREE_MB} MB。" "Not enough disk space: need 1.5 GB, have $FREE_MB MB."
    }
    if (is_installed) {
        # Windows 上运行中的程序文件删不掉，不先关掉的话换版本会失败
        if (st_running_port) { die '酒馆正在运行。请先关掉酒馆的黑色窗口，再来安装。' 'SillyTavern is running. Close it first.' }
        ok "之前已经装过（$(st_version)），这次会检查更新并修复" "Already installed ($(st_version)); updating and repairing"
    }
    ok '可以安装' 'Ready to install'

    choose_sources
    install_self
    install_node
    install_st
    write_config
    seed_tokenizers
    if (-not (Test-Path -LiteralPath "$DATA_DIR\default-user")) { offer_import }
    make_shortcuts
    remove_dir $TMP_ROOT

    Write-Host ''
    Write-Host '  ================================================' -ForegroundColor Green
    Write-Host "  $(t '  安装完成！以后双击桌面上的「酒馆 SillyTavern」就能用。' '  Done! Double-click "SillyTavern" on your Desktop to start it.')" -ForegroundColor Green
    Write-Host '  ================================================' -ForegroundColor Green
    if ($env:EST_NO_START -eq '1') { return }
    if (ask '现在就启动酒馆吗？' 'Start SillyTavern now?' 'y') {
        cmd_start
    }
    pause
}

function usage {
    Write-Host "Easy SillyTavern $EST_VERSION (Windows)"
    Write-Host 'usage: easy-st.ps1 [install|start|menu|update|backup|restore|import|doctor|rollback|uninstall]'
}

# 没料到的错误也给一句人话，并且停住窗口，不要一闪就没了
trap {
    err "出了意外的错误：$($_.Exception.Message)" "Unexpected error: $($_.Exception.Message)"
    Write-Host "  $($_.InvocationInfo.PositionMessage)" -ForegroundColor DarkGray
    Write-Host ''
    Write-Host "  $(t '可以双击桌面上的「酒馆工具箱」选「诊断」，把生成的报告和这个窗口的截图发给帮你的人。' 'Run "Diagnose" from the toolbox and send the report and a screenshot of this window to whoever helps you.')"
    pause
    exit 1
}

$cmd = $Command
if (-not $cmd) {
    if ((is_installed) -and (Test-Path -LiteralPath $SELF)) { $cmd = 'menu' } else { $cmd = 'install' }
}
switch ($cmd) {
    'install' { cmd_install }
    'start' { detect_system; cmd_start }
    'menu' { detect_system; cmd_menu }
    'update' { cmd_update; pause }
    'backup' { cmd_backup }
    'import' { offer_import 'menu' }
    'restore' { cmd_restore }
    'doctor' { cmd_doctor }
    'rollback' { cmd_rollback }
    'uninstall' { cmd_uninstall }
    'version' { Write-Output $EST_VERSION }
    default { usage; exit 2 }
}
