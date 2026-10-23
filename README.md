# Easy SillyTavern · 酒馆一键安装

给**从没装过软件、不会用命令行**的人准备的 [SillyTavern（酒馆）](https://github.com/SillyTavern/SillyTavern) 安装器。复制一行字、按一下回车，剩下的它自己看着办。

- **不用装别的**：不需要 Homebrew、Xcode、Git、Node.js，也不要管理员密码
- **自己看网络**：自动测速，国内走 npmmirror / jsDelivr 镜像，国外走官方源；下载的文件都做校验
- **认得代理**：开着 Clash、Surge、v2rayN 这类「系统代理」时，下载和酒馆连 OpenAI / Claude / Gemini 都会自动走代理；代理软件没开却残留了系统代理设置的话，也能认出来并绕开
- **认得这台电脑**：Mac 是 Apple 芯片还是 Intel、Windows 是 x64 还是 ARM，系统版本多少，自动选对应的 Node.js；硬盘空间不够会提前说
- **认得旧酒馆**：发现电脑上已经有酒馆（官方版、免安装包、STL 启动器）的聊天记录，会问你要不要复制过来，原来的文件不动
- **更新不丢记录**：程序和聊天记录分开放；更新前自动备份，新版本有问题还能一键退回
- **出问题有报告**：「诊断」会生成一份不含密钥和聊天内容的报告，直接发给帮你的人

支持 **Mac**（macOS 10.15 以上）和 **Windows**（Windows 10 / 11）：[Mac 安装](#mac-安装3-步) · [Windows 安装](#windows-安装3-步)

---

## Mac 安装（3 步）

**1. 打开「终端」**：按 `⌘ Command + 空格`，输入 `终端`，按回车。

**2. 复制下面一行，粘贴进终端，按回车**（按 `⌘ Command + V` 粘贴）：

在国内：

```bash
bash -c "$(curl -fsSL https://fastly.jsdelivr.net/gh/Horace-Maxwell/Easy-SillyTavern@main/mac/easy-st.sh)"
```

在国外，或者开着代理：

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Horace-Maxwell/Easy-SillyTavern/main/mac/easy-st.sh)"
```

**3. 等它装完**（一般 1～5 分钟）。问「现在就启动酒馆吗？」时直接按回车，浏览器会自己打开酒馆。

装好以后，桌面上会多两个图标：

| 图标 | 干什么用 |
| --- | --- |
| **酒馆 SillyTavern** | 双击启动酒馆。用的时候别关那个黑色窗口，用完关掉它就行 |
| **酒馆工具箱** | 更新、备份、恢复、导入旧记录、诊断、退回旧版本、卸载 |

### 不想用终端？

也可以在本页点绿色的 **Code → Download ZIP** 下载，解压后打开 `mac` 文件夹，双击 **双击安装酒馆**。
第一次 Mac 会拦一下：点「完成」，然后去 **系统设置 → 隐私与安全性**，往下拉，点 **仍要打开**。
（用上面的终端命令就没有这一步。）

---

## Windows 安装（3 步）

**1. 打开 PowerShell**：按 `Win + R`，输入 `powershell`，按回车。会出来一个蓝色或黑色的窗口。

**2. 复制下面一行，粘贴进这个窗口，按回车**（按 `Ctrl + V` 或者点鼠标右键就是粘贴）：

在国内：

```powershell
curl.exe -fsSLo "$env:TEMP\easy-st.ps1" https://fastly.jsdelivr.net/gh/Horace-Maxwell/Easy-SillyTavern@main/windows/easy-st.ps1; if ($?) { powershell -NoProfile -ExecutionPolicy Bypass -File "$env:TEMP\easy-st.ps1" }
```

在国外，或者开着代理：

```powershell
curl.exe -fsSLo "$env:TEMP\easy-st.ps1" https://raw.githubusercontent.com/Horace-Maxwell/Easy-SillyTavern/main/windows/easy-st.ps1; if ($?) { powershell -NoProfile -ExecutionPolicy Bypass -File "$env:TEMP\easy-st.ps1" }
```

**3. 等它装完**（一般 1～5 分钟）。问「现在就启动酒馆吗？」时直接按回车，浏览器会自己打开酒馆。

装好以后桌面上同样会多「酒馆 SillyTavern」和「酒馆工具箱」两个图标，用法和 Mac 一样。

### 不想用 PowerShell？

在本页点绿色的 **Code → Download ZIP** 下载，**先右键「全部解压缩」**，打开解压出来的 `windows` 文件夹，双击 **双击安装酒馆**。
如果蓝色窗口提示「Windows 已保护你的电脑」：点 **更多信息** → **仍要运行**。杀毒软件拦的话选「允许」。

---

## 装好之后

**连上 AI**：酒馆只是聊天界面，回话的 AI 需要 API 密钥。点页面顶上第 2 个图标（插头 🔌）→「API」选「聊天补全」→ 选你的服务商（比如 DeepSeek）→ 粘贴密钥 → 点「连接」，圆点变绿就好了。

**聊天记录在哪**：Mac 在 `~/SillyTavern-Easy/data`，Windows 在 `%LOCALAPPDATA%\SillyTavern-Easy\data`。工具箱里选「打开数据文件夹」可以直接打开。

**换电脑**：工具箱里「备份」，把备份文件拷到新电脑，新电脑装好后在工具箱里「从备份恢复」。Mac 的备份（`.tar.gz`）放到 Windows 桌面上也能恢复。

## 常见问题

| 情况 | 怎么办 |
| --- | --- |
| 浏览器没自动打开 | 浏览器地址栏输入黑色窗口里写的地址，一般是 `http://127.0.0.1:8000` |
| 再双击「酒馆 SillyTavern」没反应 | 它已经在运行了，会直接帮你打开网页；看看浏览器 |
| 连不上 OpenAI / Claude / Gemini | 打开代理软件的「系统代理」，然后**重新启动酒馆**（关掉黑色窗口再双击） |
| 装到一半网断了 | 重新粘贴那行命令，已经下好的部分会跳过 |
| Windows：粘贴后提示「无法识别 curl.exe」或一堆红字 | 确认是在 **PowerShell** 里粘贴的（不是「命令提示符」）；系统太旧的话先装 Windows 更新，或者用上面的 ZIP 方式 |
| Windows：「Windows 已保护你的电脑」 | 点「更多信息」→「仍要运行」 |
| 别的问题 | 工具箱选「诊断」，把桌面上的「酒馆诊断报告」发给帮你的人 |

## 装了哪些东西

全部在一个文件夹里，不碰系统：Mac 是 `~/SillyTavern-Easy`，Windows 是 `%LOCALAPPDATA%\SillyTavern-Easy`（一般是 `C:\Users\你的用户名\AppData\Local\SillyTavern-Easy`，故意不放「文档」「桌面」，免得被 OneDrive 同步）。

```
SillyTavern-Easy/
├── runtime/node/    私有的 Node.js
├── app/             酒馆程序（更新时整个换掉；app.prev 是上一个版本）
├── data/            聊天记录、角色卡、设置（更新时不动）
├── config.yaml      酒馆配置
├── backups/         备份（Mac 是 .tar.gz，Windows 是 .zip）
├── logs/            运行记录（最近 5 次）
└── easy-st.sh       工具箱本体（Windows 是 easy-st.ps1）
```

卸载：工具箱选「卸载」，它会先把聊天记录备份到桌面再删。

## 给懂行的人

- Mac 脚本：[mac/easy-st.sh](mac/easy-st.sh)，只用 macOS 自带的 bash 3.2 / curl / tar / shasum
- Windows 脚本：[windows/easy-st.ps1](windows/easy-st.ps1)，兼容 Win10 自带的 Windows PowerShell 5.1，只用系统自带的 curl.exe / robocopy 和 .NET；文件必须是带 BOM 的 UTF-8
- 酒馆从 npm 上的官方 `sillytavern` 包下载（npmjs 或 npmmirror，用 `dist.integrity` 校验），再从 GitHub 拿同版本的 `package-lock.json` 跑 `npm ci --ignore-scripts`
- Node.js 用 `SHASUMS256.txt` 校验；macOS ≥ 13.5 用 Node 24，11～13.4 用 Node 22，10.15 用 Node 20；Windows 10 / 11 用 Node 24（x64 或 arm64，32 位系统用 22）
- 酒馆用 `--configPath` / `--dataRoot` 启动，程序目录可以整个替换
- 常用环境变量：`EST_HOME`（安装位置）、`EST_LANG=zh|en`、`EST_YES=1`（不问问题）、`EST_NO_START=1`、`EST_NO_BROWSER=1`、`EST_NO_SHORTCUTS=1`
- 命令：`easy-st.sh install | start | menu | update | backup | restore | import | doctor | rollback | uninstall`（Windows：`powershell -ExecutionPolicy Bypass -File easy-st.ps1 <命令>`）
- 两边要对齐的行为：[docs/DESIGN.md](docs/DESIGN.md)

## 许可

本仓库的脚本使用 MIT 许可。SillyTavern 本身是 AGPL-3.0，安装时从官方渠道下载，不在本仓库里。
