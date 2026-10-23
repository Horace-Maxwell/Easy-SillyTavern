# Easy SillyTavern 设计说明

Mac 版（`mac/easy-st.sh`）和 Windows 版（`windows/`）各写各的脚本，但**行为要一样**：用户换一台电脑，看到的步骤、文件夹、菜单、提示都一致。这份文档是两边共同的约定，改了行为就同步改这里。

## 目标用户

从没装过软件、不会命令行、可能在国内网络下、可能开着代理的人。所以：

1. 不要求任何前置软件，不要管理员权限
2. 能自己判断的绝不问；必须问的只问「是/否」或「输入编号」
3. 任何失败都给一句人话 + 下一步该做什么（默认是「运行诊断，把报告发给帮你的人」）
4. 重复运行安全：装到一半断了，再跑一次就从断的地方继续

## 安装目录

| 系统 | 默认位置 | 覆盖 |
| --- | --- | --- |
| macOS | `~/SillyTavern-Easy` | `EST_HOME` |
| Windows | `%LOCALAPPDATA%\SillyTavern-Easy`（不放「文档」「桌面」，避开 OneDrive 同步） | `EST_HOME` |

```
SillyTavern-Easy/
├── .easy-sillytavern   标记文件；卸载前必须看到它才删目录
├── easy-st.sh / .ps1   工具箱本体（安装时复制进来）
├── state.env           key=value：REGION、PORT、PROXY=off、SHORTCUTS
├── runtime/node/       私有 Node.js
├── runtime/nogit/      占位 git（仅 Mac 需要）
├── runtime/npmrc       私有 npm 配置（registry、关掉 fund/audit）
├── app/                SillyTavern 程序，更新时整个替换
├── app.prev/           上一个版本，用于退回
├── data/               --dataRoot，用户数据，更新不动
├── config.yaml         --configPath
├── backups/            auto-*（只留 5 份）、manual-*；Mac 是 .tar.gz，Windows 是 .zip
└── logs/st-*.log       最近 5 次运行记录
```

## 安装流程（install）

1. **检查电脑**：系统版本、CPU 架构、剩余空间（< 1.5 GB 就停）、是否已安装（已安装则当作「更新 + 修复」）
2. **选源**：
   - 先找代理（见下），能用就设到 `http(s)_proxy`
   - 并行探测 `registry.npmjs.org/sillytavern/latest` 和 `registry.npmmirror.com/sillytavern/latest`，谁快用谁；npmmirror 快 ⇒ `REGION=cn`
   - Node.js：cn 先 `cdn.npmmirror.com/binaries/node`，否则先 `nodejs.org/dist`，失败换另一个
   - GitHub 小文件（锁文件、分词器、工具箱自更新）：cn 顺序 `fastly.jsdelivr.net` → `cdn.jsdelivr.net` → `raw.githubusercontent.com`，否则反过来
   - **不用第三方 GitHub 加速代理**（ghproxy 之类），没法校验内容
3. **Node.js**：从 `index.json` 取对应大版本的最新版，下载后用 `SHASUMS256.txt` 校验
   - macOS：≥ 13.5 → 24；11～13.4 → 22；10.15 → 20（提示已停止维护）；更旧 → 拒绝
   - Windows：10 / 11 → 24（x64 或 arm64 的 zip；CPU 看注册表里的 `PROCESSOR_ARCHITECTURE`，ARM 电脑上模拟运行的 PowerShell 会谎报 AMD64）；32 位系统 → 22（Node 23 起没有 32 位版）；更旧 → 拒绝
4. **SillyTavern**：取 `sillytavern/latest` 的 `version`、`dist.tarball`、`dist.integrity`，下载后用 integrity 校验，解到 `app.new/`
   - npm 包里没有 `package-lock.json`：从 GitHub 拿 `SillyTavern/SillyTavern@<版本>/package-lock.json`，检查里面的 `version` 一致才用，然后 `npm ci`；拿不到就 `npm install --no-save`
   - npm 参数固定：`--omit=dev --ignore-scripts --no-audit --no-fund`，`NODE_ENV=production`，缓存放 `runtime/npm-cache`（装完删掉），失败换另一个 registry 再试一次
   - 成功后 `app → app.prev`，`app.new → app`
5. **配置**：没有 `config.yaml` 就复制 `app/default/config.yaml`，把 `git.backend` 改成 `builtin`
6. **分词器**：`deepseek qwen2 nemo command-r command-a` 预先下到 `data/_cache/<名字>.json.gz`，失败不报错
7. **导入旧数据**：`data/default-user` 还不存在时，找电脑上别的酒馆数据（见下），列出来让用户选编号，回车跳过
8. **快捷方式**：桌面放「酒馆 SillyTavern」（start）和「酒馆工具箱」（menu）。Mac 在安装目录里也总放一份；往桌面写失败（用户在系统弹窗里点了「不允许」）时提示去安装目录找，并打开那个文件夹
9. 问「现在就启动吗？」，默认是

## 启动（start）

1. 如果「这一份」酒馆已经在跑 → 打开浏览器，退出。判断方法：8000～8019 上监听的进程，工作目录 / 命令行是不是本安装的 `app/`。**别的酒馆占着端口不算**，要换个端口启动
2. 选端口：`state.env` 里的 PORT 空闲就用，否则 8000 起第一个空闲端口
3. 每次启动都重新检测代理；有可用代理就加 `--requestProxyEnabled=true --requestProxyUrl=<代理>`（`state.env` 里 `PROXY=off` 可关掉）
4. `cd app && node server.js --configPath <config.yaml> --dataRoot <data> --port <端口>`，输出同时写到 `logs/`
5. 窗口顶部用中文告诉用户：别关窗口、用完关窗口、浏览器没开就访问哪个地址、是否在走代理
6. 异常退出时提示错误码和诊断；Ctrl+C / 关窗口不算异常

## 代理检测

| 系统 | 从哪读 |
| --- | --- |
| macOS | `scutil --proxy`：HTTPS → HTTP → SOCKS 依次看 `*Enable` |
| Windows | `HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings` 的 `ProxyEnable` / `ProxyServer`（可能是 `host:port`，也可能是 `http=…;https=…`） |

- 环境变量里已有 `https_proxy` 等就直接用
- 读到系统代理后先测端口通不通（Mac 用 `nc -z -G 2`，Windows 用 `Test-NetConnection` 或 `TcpClient`）。**不通就当没有**（代理软件关了但设置残留，是最常见的「全都连不上」原因）
- SOCKS 代理用 `socks5://`，其余用 `http://`

## 找旧数据

找 `…/SillyTavern/data/default-user` 这种结构，排除本安装自己：

- macOS：`~/SillyTavern*/data`、`~/SillyTavern*/SillyTavern/data`，以及桌面、下载、文稿里 6 层以内
- Windows：`%USERPROFILE%\SillyTavern*`、每个本地硬盘根目录的 `X:\SillyTavern*`（往下 2 层），以及桌面、下载、文档里 6 层以内。Windows 上解压出来的文件夹名五花八门（`SillyTavern-release`、`SillyTavern-1.13.0`、`SillyTavern-Launcher\SillyTavern`），所以只认 `…\data\default-user` 结构，不要求上一层叫 `SillyTavern`；跳过 `node_modules`、`.git`、`AppData` 和链接文件夹

每一项显示「N 个角色、M 段聊天」帮用户认。导入是**复制合并**（Mac 用 `ditto`，Windows 用 `robocopy /E`），导入前如果已有数据先自动备份。

恢复备份：列出 `backups/` 和桌面上的 `酒馆数据备份-*` / `SillyTavern-backup-*`。Windows 版同时认 `.zip` 和 Mac 做的 `.tar.gz`，换电脑时直接拷过来就能恢复。

## 工具箱菜单（menu）

编号和顺序两边一样：

```
1) 启动酒馆
2) 检查更新         运行中拒绝；先自更新工具箱 → 自动备份 → Node → 酒馆 → 配置 → 分词器 → 快捷方式
3) 备份             data + config.yaml，排除 data/_cache、_webpack、_uploads
4) 打开数据文件夹
5) 从别的酒馆导入
6) 从备份恢复       列 backups/ 里的全部备份，加上桌面和下载文件夹里以 酒馆数据备份- SillyTavern-backup- manual- auto- final- 开头的 .zip / .tar.gz（两边的格式都认）；选编号；恢复前先备份当前
7) 诊断
8) 退回上一个版本   app ⇄ app.prev
9) 卸载             先问要不要备份到桌面（默认要），再确认删除（默认不删）
0) 退出
```

## 诊断报告

存到桌面 `酒馆诊断报告-<时间>.txt` 并打开。内容：工具箱版本、系统、架构、剩余空间、Node / 酒馆版本、state、代理、端口占用、各下载源和 AI 接口（OpenAI、Anthropic、Gemini、DeepSeek）的连通性和耗时、config 里和默认值不同的项（过滤含 pass/token/secret/key 的行）、最近一次运行记录的最后 80 行。用户目录替换成 `~`。**不包含** `secrets.json` 和聊天内容。

## 工具箱自更新

从本仓库 `main` 分支取 `mac/easy-st.sh`（Windows 取 `windows/easy-st.ps1`），版本号 `EST_VERSION` 不同且语法检查通过才覆盖。

## 文案

- 中文为主；系统语言不是中文时用英文。所有提示用 `t "中文" "English"` 这种成对写法
- 面向完全的新手：说「黑色窗口」不说「终端」，说「聊天记录」不说「data 目录」
- 每个错误都以「下一步怎么做」结尾
- Mac 脚本里变量后面紧跟中文时一定写成 `${var}`：系统没设 UTF-8 时 bash 3.2 会把中文字节当成变量名的一部分（CI 不设 LANG，正好能测出来）
- Windows 脚本也一样要写 `${var}`：PowerShell 的变量名允许 Unicode 字母，`"$ver个"` 会被当成变量 `$ver个`。另外 `"$a:$b"` 会被当成驱动器写法，也要写成 `"${a}:$b"`

## Windows 版要注意的地方

下面都是实测踩过的坑。**中文用户名 + 英文系统**（系统 ANSI 编码不是 GBK）是最容易出事的组合，测试时把 `EST_HOME` 设成带中文和空格的路径。

- **入口**：一行 `curl.exe -fsSLo "$env:TEMP\easy-st.ps1" <url>; if ($?) { powershell -NoProfile -ExecutionPolicy Bypass -File "$env:TEMP\easy-st.ps1" }`，另给一个 `双击安装酒馆.bat`（`powershell -NoProfile -ExecutionPolicy Bypass -File easy-st.ps1 install`）。不用 `irm <url> | iex`：
  - `iex` 在用户自己的窗口里跑，脚本里一 `exit` 就把窗口关了，报错也看不到
  - 5.1 的 `irm` 遇到没写 charset 的响应会按 ISO-8859-1 解码，中文全乱
  - `irm` / `WebClient` 会走系统代理，代理软件关了但设置残留时直接下载失败；`curl.exe` 不读系统代理
- **文件编码**：`easy-st.ps1` 必须是带 BOM 的 UTF-8，否则 5.1 按 ANSI 读；自更新和安装时复制前都检查 BOM + 语法。`.bat` 是 CRLF、无 BOM，`chcp 65001` 之前只能有英文
- **PowerShell 版本**：兼容 5.1，别用 7 才有的语法；先设 `[Net.ServicePointManager]::SecurityProtocol = Tls12`。从 PowerShell 7 窗口里启动 `powershell.exe` 会继承 7 的 `PSModulePath`，5.1 就找不到 `Get-FileHash` 之类模块里的命令：启动时把 `\PowerShell\` 的路径去掉，哈希用 .NET 算
- **下载**：用 `curl.exe`（Win10 1803+ 自带），支持的话加 `--ssl-revoke-best-effort`（有些网络查不到证书吊销列表，会让所有 https 失败）；没有 curl 才退回 `Invoke-WebRequest`（设 `$ProgressPreference = 'SilentlyContinue'`，不然慢几十倍）。并行测速直接起几个 `curl.exe` 进程
- **系统自带的 `tar.exe` 不认 ANSI 编码以外的路径**（英文系统上 `C:\Users\张三` 会变成 `C:\Users\??`），压缩包里的中文文件名也一样。所以：
  - 酒馆的 `.tgz` 和 Mac 备份的 `.tar.gz` 用 npm 自带的 tar 库解（`node -e "require('<node>/node_modules/npm/node_modules/tar').x(...)"`），`tar.exe` 只做后备
  - Node 的 zip 用 .NET `ZipFile.ExtractToDirectory`
  - 备份用 .NET `ZipArchive` 一个个文件写（文件名一律 UTF-8），不用 `tar.exe` 也不用 `Compress-Archive`（慢、不能排除文件夹）
- **路径长度**：5.1 底下的 .NET 不认 260 字符以上的路径。Node 的 zip 解到 `runtime\x` 这种短路径再整个改名；删 `node_modules` 用我们自己的 node（`fs.rmSync`），删 node 自己时用 `rd /s /q`
- **改名重试**：杀毒软件刚扫完的新文件夹会短暂被占用，`app.new → app` 这类改名要重试几次
- **运行中的文件删不掉**：酒馆开着时换不了 Node 和 app，所以 install 发现已安装且正在运行就让用户先关掉
- **桌面快捷方式**：桌面位置用 `[Environment]::GetFolderPath('Desktop')`（可能被 OneDrive 挪走）。**不用 `WScript.Shell`**：它按 ANSI 存路径，中文快捷方式名存不了，中文用户名会变成 `??`。做法是先写一个 80 字节的空 `.lnk` 文件头，再用 `Shell.Application` 的 `GetLink` 填内容（全程 Unicode）。快捷方式直接指向 `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<安装目录>\easy-st.ps1" start|menu`，不经过 `.bat`：少一层 cmd，Ctrl+C 时不会再问「终止批处理操作吗(Y/N)?」。图标复制 `app\public\favicon.ico` 到安装目录，更新、退回时不会丢
- **判断「这一份」酒馆在运行**：`Get-NetTCPConnection -State Listen` 拿端口和 PID（失败时解析 `netstat -ano`），再用 `Get-CimInstance Win32_Process` 看命令行是否包含本安装的 `app\server.js`。所以启动时要用 `app\server.js` 的完整路径
- **选端口**：Hyper-V / WSL 会整段保留端口（常见 7900～8000），这些端口谁也监听不了但 `netstat` 里看不到，所以除了看监听列表，还要真的用 `TcpListener` 占一下试试
- **启动**：`node … 2>&1 | ForEach-Object { 显示; 写日志 }`，先把 `[Console]::OutputEncoding` 设成 UTF-8，不然 node 输出的中文路径会乱。`$ErrorActionPreference` 保持 `Continue`，否则 5.1 遇到 stderr 就抛异常
- **窗口一闪就没**：从快捷方式打开的窗口，脚本一结束就关。所以所有出错路径（`die` 和兜底的 `trap`）都要先「按回车键继续」
- **杀毒软件 / SmartScreen** 可能拦 `.bat`，README 里写清楚「更多信息 → 仍要运行」
- **输出符号**：Win10 老控制台字体没有 ✓ ▶，用 `√ × ! >>`
