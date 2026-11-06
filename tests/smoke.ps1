# 把一份真实安装从头走到尾：安装、启动、隐私、备份恢复、接着装、更新、卸载。
# 全部装在临时文件夹里，不碰这台电脑上已有的安装。
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\smoke.ps1
#
# 文件夹名字故意带中文和空格，能测出路径没加引号的问题。
# 这个文件也要存成带 BOM 的 UTF-8，不然 5.1 读不对中文。
# 判断结果看退出码和留下的文件，不看输出的文字：子进程的中文输出经过控制台代码页，靠不住。

$ErrorActionPreference = 'Continue'
$script = (Resolve-Path "$PSScriptRoot\..\windows\easy-st.ps1").Path
$work = Join-Path $env:TEMP ('est-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
[void][IO.Directory]::CreateDirectory($work)

$env:USERPROFILE = "$work\home"
$env:EST_HOME = "$work\home\酒馆 测试"
$env:EST_DESKTOP = "$work\home\Desktop"
$env:EST_LANG = 'zh'
$env:EST_YES = '1'
$env:EST_NO_START = '1'
$env:EST_NO_BROWSER = '1'
[void][IO.Directory]::CreateDirectory($env:EST_DESKTOP)

$script:fails = 0
function pass([string]$what) { Write-Host "ok    $what" }
function fail([string]$what) { Write-Host "FAIL  $what"; $script:fails++ }
function check([string]$what, [bool]$good) { if ($good) { pass $what } else { fail $what } }

# 跑一条工具箱命令，输出写进文件，返回退出码。超过 limit 秒还没结束算失败，返回 -1
function run([string]$name, [string[]]$arguments, [int]$limit = 600) {
    $list = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$script`"") + $arguments
    $p = Start-Process powershell -PassThru -WindowStyle Hidden -ArgumentList $list `
        -RedirectStandardOutput "$work\$name.log" -RedirectStandardError "$work\$name.err"
    # 先取一次 Handle，不然 5.1 拿不到 ExitCode
    [void]$p.Handle
    if (-not $p.WaitForExit($limit * 1000)) {
        Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
        return -1
    }
    $p.ExitCode
}

function http_code([string]$url) {
    try { [int](Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 5).StatusCode } catch { 0 }
}

$started = $null
$mock = $null
try {
    # ------------------------------------------------------------ 安装 ---
    $code = run 'install' @('install')
    if ($code -ne 0 -or -not (Test-Path -LiteralPath "$env:EST_HOME\app\server.js")) {
        Get-Content -LiteralPath "$work\install.log" -Encoding UTF8 -Tail 40
        fail '安装'
        exit 1
    }
    pass '安装'
    $config = "$env:EST_HOME\config.yaml"
    check '酒馆日志级别不是 DEBUG' ([IO.File]::ReadAllText($config) -match '(?m)^  minLogLevel: 1')
    check '桌面快捷方式' (Test-Path -LiteralPath "$env:EST_DESKTOP\酒馆 SillyTavern.lnk")
    check '安装文件夹里也有一份' (Test-Path -LiteralPath "$env:EST_HOME\酒馆工具箱.lnk")
    $programs = [Environment]::GetFolderPath('Programs')
    check '开始菜单快捷方式' (Test-Path -LiteralPath "$programs\酒馆 SillyTavern.lnk")

    # -------------------------------------------------------- 启动 ---
    # 模拟 v0.1.0 留下的状态：DEBUG 级别，旧记录里有聊天内容
    $text = [IO.File]::ReadAllText($config) -replace '(?m)^  minLogLevel: 1', '  minLogLevel: 0'
    [IO.File]::WriteAllText($config, $text)
    [void][IO.Directory]::CreateDirectory("$env:EST_HOME\logs")
    [IO.File]::WriteAllText("$env:EST_HOME\logs\st-20200101-000000.log", 'OLD_PRIVATE_CHAT')

    $started = Start-Process powershell -PassThru -WindowStyle Hidden -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$script`"", 'start')
    $port = 0
    for ($i = 0; $i -lt 120 -and -not $port; $i++) {
        foreach ($p in 8000..8019) {
            if ((http_code "http://127.0.0.1:$p/") -eq 200) { $port = $p; break }
        }
        Start-Sleep -Seconds 1
    }
    if (-not $port) {
        Get-ChildItem -LiteralPath "$env:EST_HOME\logs" -Filter 'st-*.log' | Sort-Object LastWriteTime | Select-Object -Last 1 | Get-Content -Tail 30 -Encoding UTF8
        fail '启动后网页打得开'
        exit 1
    }
    pass "启动后网页打得开（端口 $port）"
    # 没认出来的话会再开一份，一直不退出
    check '重复启动不会开第二份' ((run 'again' @('start') 60) -eq 0)
    check '旧版 DEBUG 配置被改掉' ([IO.File]::ReadAllText($config) -match '(?m)^  minLogLevel: 1')
    check '旧记录里的聊天内容被清掉' (-not (Select-String -Path "$env:EST_HOME\logs\*.log" -Pattern 'OLD_PRIVATE_CHAT' -Quiet))

    # -------------------------------------------------------- 隐私 ---
    # 发一句真的聊天给一个假的 AI 接口，确认它进不了运行记录和诊断报告
    $node = "$env:EST_HOME\runtime\node\node.exe"
    $mockJs = "$work\mock.js"
    [IO.File]::WriteAllText($mockJs, @'
require('http').createServer((q, r) => {
    q.resume();
    q.on('end', () => {
        r.setHeader('content-type', 'application/json');
        r.end(JSON.stringify({ id: 'x', object: 'chat.completion', model: 'm',
            choices: [{ index: 0, finish_reason: 'stop', message: { role: 'assistant', content: 'MOCK_REPLY' } }] }));
    });
}).listen(9911, '127.0.0.1');
'@)
    $mock = Start-Process $node -PassThru -WindowStyle Hidden -ArgumentList "`"$mockJs`""
    Start-Sleep -Seconds 1
    $session = $null
    $token = (Invoke-RestMethod -Uri "http://127.0.0.1:$port/csrf-token" -SessionVariable session -UseBasicParsing).token
    $body = '{"chat_completion_source":"custom","custom_url":"http://127.0.0.1:9911/v1","model":"m","stream":false,"messages":[{"role":"user","content":"PRIVATE_CHAT_MARKER"}]}'
    $reply = ''
    try {
        $reply = (Invoke-WebRequest -Uri "http://127.0.0.1:$port/api/backends/chat-completions/generate" -Method Post -WebSession $session `
            -Headers @{ 'X-CSRF-Token' = $token } -ContentType 'application/json' -Body $body -UseBasicParsing).Content
    } catch {}
    check '聊天请求真的发出去了' ($reply -match 'MOCK_REPLY')
    Start-Sleep -Seconds 1
    check '聊天内容不进运行记录' (-not (Select-String -Path "$env:EST_HOME\logs\*.log" -Pattern 'PRIVATE_CHAT_MARKER' -Quiet))

    $portProc = (Get-NetTCPConnection -State Listen -LocalPort $port).OwningProcess | Select-Object -First 1
    Stop-Process -Id $portProc -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Stop-Process -Id $mock.Id -Force -ErrorAction SilentlyContinue
    $mock = $null

    check '诊断能跑完' ((run 'doctor' @('doctor')) -eq 0)
    Get-Process notepad -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    $report = @(Get-ChildItem -LiteralPath $env:EST_DESKTOP -Filter '酒馆诊断报告-*.txt') | Select-Object -First 1
    check '诊断报告生成了' ([bool]$report)
    if ($report) { check '诊断报告里没有聊天内容' (-not (Select-String -LiteralPath $report.FullName -Pattern 'PRIVATE_CHAT_MARKER' -Quiet)) }

    # ---------------------------------------------------- 备份恢复 ---
    $chat = "$env:EST_HOME\data\default-user\chats\alice\a.jsonl"
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $chat))
    [IO.File]::WriteAllText($chat, '{"mes":"keep me"}')
    check '备份能跑完' ((run 'backup' @('backup')) -eq 0)
    Remove-Item -LiteralPath $chat -Force
    $env:EST_ANSWERS = '1'
    [void](run 'restore' @('restore'))
    $env:EST_ANSWERS = ''
    check '从备份恢复' (Test-Path -LiteralPath $chat)

    # ------------------------------------------- 接着装、更新 ---
    # 模拟装到一半被打断：程序都在，但最后一步没走完。这时再运行要接着装，不能进工具箱
    $state = "$env:EST_HOME\state.env"
    $kept = @([IO.File]::ReadAllLines($state) | Where-Object { $_ -notmatch '^(SETUP|SHORTCUTS)=' })
    [IO.File]::WriteAllLines($state, [string[]]$kept)
    # 进工具箱的话没人按键会一直等着，所以这里也能看出走的是哪条路
    check '被打断后再运行会接着装' ((run 'resume' @() 300) -eq 0)
    check '走完后记下了' ([IO.File]::ReadAllText($state) -match '(?m)^SETUP=done')

    check '检查更新' ((run 'update' @('update')) -eq 0)

    # ------------------------------------------------------------ 卸载 ---
    $env:EST_ANSWERS = 'y y'
    [void](run 'uninstall' @('uninstall'))
    $env:EST_ANSWERS = ''
    check '安装文件夹删掉了' (-not (Test-Path -LiteralPath "$env:EST_HOME\app"))
    $backup = @(Get-ChildItem -LiteralPath $env:EST_DESKTOP -Filter '酒馆数据备份-*.zip') | Select-Object -First 1
    check '备份留在桌面' ([bool]$backup)
    check '桌面快捷方式删掉了' (-not (Test-Path -LiteralPath "$env:EST_DESKTOP\酒馆 SillyTavern.lnk"))
    check '开始菜单快捷方式删掉了' (-not (Test-Path -LiteralPath "$programs\酒馆 SillyTavern.lnk"))
} finally {
    if ($mock) { Stop-Process -Id $mock.Id -Force -ErrorAction SilentlyContinue }
    if ($started) { Stop-Process -Id $started.Id -Force -ErrorAction SilentlyContinue }
    Get-Process node -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

Write-Host ''
if ($script:fails -gt 0) {
    foreach ($log in @(Get-ChildItem -LiteralPath $work -Include '*.log', '*.err' -Recurse -File -ErrorAction SilentlyContinue)) {
        Write-Host "--- $($log.Name)"
        Get-Content -LiteralPath $log.FullName -Encoding UTF8 -Tail 15
    }
}
if ($script:fails -eq 0) {
    Write-Host '全部通过'
} else {
    Write-Host "$($script:fails) 项没通过"
    exit 1
}
