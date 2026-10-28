<div align="center">

<img src="docs/assets/banner.svg" alt="Easy SillyTavern · 酒馆一键安装" width="100%">

<p>
  <a href="https://github.com/Horace-Maxwell/Easy-SillyTavern/actions/workflows/check.yml"><img src="https://github.com/Horace-Maxwell/Easy-SillyTavern/actions/workflows/check.yml/badge.svg" alt="check"></a>
  <img src="https://img.shields.io/badge/macOS-10.15%2B-111?logo=apple&logoColor=white" alt="macOS 10.15+">
  <img src="https://img.shields.io/badge/Windows-10%20%7C%2011-0078D4?logo=windows&logoColor=white" alt="Windows 10 | 11">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-e0841c" alt="MIT"></a>
</p>

**给从没装过软件、不会用命令行的人准备的 [SillyTavern（酒馆）](https://github.com/SillyTavern/SillyTavern) 安装器。<br>复制一行字、按一下回车，剩下的它自己看着办。**

**简体中文** · [English](README.en.md)

[Mac 安装](#-mac-安装) · [Windows 安装](#-windows-安装) · [装好之后](#-装好之后) · [遇到问题](#-遇到问题) · [给懂行的人](#-给懂行的人)

</div>

<br>

<div align="center">
<img src="docs/assets/demo.svg" alt="安装过程演示" width="760">
</div>

## ✨ 它会自己帮你做什么

| 特点 | 说明 |
| --- | --- |
| 🧰 **不用装别的** | 不需要 Homebrew、Xcode、Git、Node.js，也不要管理员密码 |
| 🌏 **自己看网络** | 自动测速，国内走 npmmirror / jsDelivr 镜像，国外走官方源；下载的文件都做校验 |
| 🛰️ **认得代理** | 开着「系统代理」时下载和连 AI 都自动走代理；代理软件关了但系统里残留着设置，也能认出来绕开 |
| 💻 **认得这台电脑** | Apple 芯片 / Intel、x64 / ARM、系统版本，自动选对应的 Node.js；硬盘不够会提前说 |
| 🍺 **认得旧酒馆** | 发现官方版、免安装包、STL 启动器留下的聊天记录，问你要不要复制过来，原文件不动 |
| 🛟 **更新不丢记录** | 程序和聊天记录分开放；更新前自动备份，新版本有问题能一键退回 |
| 🩺 **出问题有报告** | 「诊断」生成一份不含密钥和聊天内容的报告，直接发给帮你的人 |

### 和自己手动装比

| | 照官方文档手动装 | Easy SillyTavern |
| --- | :---: | :---: |
| 先装 Git、Node.js | 需要 | **不用** |
| 管理员密码 | 装依赖时一般要 | **不用** |
| 国内下载慢 | 自己找镜像 | **自动测速选源** |
| 更新 | 命令行 `git pull` / `npm install` | **工具箱选 2，先自动备份** |
| 更新后出问题 | 自己想办法 | **一键退回上一版** |
| 换电脑 | 手动拷 `data` 文件夹 | **备份 → 恢复，Mac / Windows 互通** |

> 支持 macOS 10.15 以上、Windows 10 / 11。需要 1.5 GB 空闲硬盘，第一次安装大约下载 200 MB，一般 1～5 分钟装完。

---

## 🍎 Mac 安装

**① 打开「终端」**

按 `⌘ Command + 空格`，输入 `终端`（系统是英文的话输入 `Terminal`），按回车。会出来一个白色或黑色的窗口。

**② 复制下面这一行，粘贴进终端，按回车**

鼠标移到下面的框上，点右上角的复制按钮 📋；然后点一下终端窗口，按 `⌘ Command + V` 粘贴，再按回车。

在国内：

```bash
bash -c "$(curl -fsSL https://fastly.jsdelivr.net/gh/Horace-Maxwell/Easy-SillyTavern@main/mac/easy-st.sh)"
```

在国外，或者开着代理：

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Horace-Maxwell/Easy-SillyTavern/main/mac/easy-st.sh)"
```

**③ 等它装完**

- 如果弹出「“终端”想要访问“桌面”（或“文稿”“下载”）文件夹中的文件」，点 **允许**。它是在找你以前的聊天记录，以及在桌面放图标。点了「不允许」也能装好，只是桌面上不会有图标（见[遇到问题](#-遇到问题)）
- 如果它说找到了以前的聊天记录，输入前面的编号按回车就会复制过来；不需要就直接按回车
- 最后问「现在就启动酒馆吗？」时直接按回车，浏览器会自己打开酒馆

> [!NOTE]
> 整个过程**不会让你输入密码**。如果终端里出现 `Password:`，说明粘贴的不是上面那一行，关掉窗口重来就行。

<details>
<summary><b>不想用终端？</b></summary>
<br>

在本页点绿色的 **Code → Download ZIP** 下载，解压后打开 `mac` 文件夹，双击 **双击安装酒馆**。

第一次 Mac 会拦一下：点「完成」，然后去 **系统设置 → 隐私与安全性**，往下拉，点 **仍要打开**，再输入开机密码（这是 Mac 系统要的，不是安装器要的）。用终端命令就没有这一步，所以更推荐终端。

</details>

---

## 🪟 Windows 安装

**① 打开 PowerShell**

按 `Win + R`，输入 `powershell`，按回车。会出来一个蓝色或黑色的窗口。

**② 复制下面这一行，粘贴进这个窗口，按回车**

点框右上角的复制按钮 📋，然后在窗口里按 `Ctrl + V`（或者点鼠标右键）粘贴，再按回车。

在国内：

```powershell
curl.exe -fsSLo "$env:TEMP\easy-st.ps1" https://fastly.jsdelivr.net/gh/Horace-Maxwell/Easy-SillyTavern@main/windows/easy-st.ps1; if ($?) { powershell -NoProfile -ExecutionPolicy Bypass -File "$env:TEMP\easy-st.ps1" }
```

在国外，或者开着代理：

```powershell
curl.exe -fsSLo "$env:TEMP\easy-st.ps1" https://raw.githubusercontent.com/Horace-Maxwell/Easy-SillyTavern/main/windows/easy-st.ps1; if ($?) { powershell -NoProfile -ExecutionPolicy Bypass -File "$env:TEMP\easy-st.ps1" }
```

**③ 等它装完**。问「现在就启动酒馆吗？」时直接按回车，浏览器会自己打开酒馆。

<details>
<summary><b>不想用 PowerShell？</b></summary>
<br>

在本页点绿色的 **Code → Download ZIP** 下载，**先右键「全部解压缩」**，打开解压出来的 `windows` 文件夹，双击 **双击安装酒馆**。

如果提示「Windows 已保护你的电脑」：点 **更多信息** → **仍要运行**。杀毒软件拦的话选「允许」。

</details>

---

## 🍻 装好之后

桌面上会多两个图标，Mac 和 Windows 一样：

| 图标 | 干什么用 |
| --- | --- |
| **酒馆 SillyTavern** | 双击启动，浏览器会自己打开。用的时候**别关**那个黑色窗口，用完关掉它就退出了（Mac 问你时点「终止」） |
| **酒馆工具箱** | 双击后输入编号使用，见下表 |

<table>
<tr><th>编号</th><th>做什么</th><th>编号</th><th>做什么</th></tr>
<tr><td align="center">1</td><td>启动酒馆</td><td align="center">6</td><td>从备份恢复</td></tr>
<tr><td align="center">2</td><td>检查更新（会先自动备份）</td><td align="center">7</td><td>诊断（出问题时用，在桌面生成报告）</td></tr>
<tr><td align="center">3</td><td>备份聊天记录和设置</td><td align="center">8</td><td>退回上一个版本（更新后出问题时用）</td></tr>
<tr><td align="center">4</td><td>打开数据文件夹（角色卡、聊天记录在这里）</td><td align="center">9</td><td>卸载（会先把聊天记录备份到桌面）</td></tr>
<tr><td align="center">5</td><td>从别的酒馆导入聊天记录</td><td align="center">0</td><td>退出</td></tr>
</table>

### 第一次用：连上 AI

酒馆只是聊天界面，回话的 AI 需要一把「钥匙」（API 密钥），一般在 AI 服务商的网站注册、充值后创建，比如 DeepSeek 开放平台。

1. 点页面最上面一排图标里的**第 2 个（插头 🔌）**
2. 「API」选 **聊天补全**
3. 「聊天补全来源」选你的服务商，比如 **DeepSeek**
4. 把密钥粘贴进去，点 **连接**，下面的圆点变绿就好了
5. 顺手勾上「自动连接到上次的服务器」，以后打开就不用再点

### 换电脑

**旧电脑**：工具箱选 **3 备份**，会弹出备份文件所在的文件夹。把这个文件拷到新电脑的**桌面**或**下载**文件夹里（微信、隔空投送、U 盘都行）。
**新电脑**：装好后在工具箱选 **6 从备份恢复**，选那个文件。Mac 和 Windows 之间也能互相恢复。

---

## 🧯 遇到问题

| 情况 | 怎么办 |
| --- | --- |
| 浏览器没自动打开 | 在浏览器地址栏输入黑色窗口里写的地址，一般是 `http://127.0.0.1:8000` |
| 又双击了一次「酒馆 SillyTavern」 | 没关系，它发现酒馆已经开着，会直接帮你打开网页 |
| Mac 桌面上没有图标 | 打开「访达」，按 `⌘ Command + ⇧ Shift + H`，进 **SillyTavern-Easy** 文件夹，里面也有「酒馆 SillyTavern」和「酒馆工具箱」。想放到桌面的话，按住 `⌥ Option + ⌘ Command` 把它拖到桌面 |
| 连不上 OpenAI / Claude / Gemini | 打开代理软件的「系统代理」，然后**重新启动酒馆**（关掉黑色窗口再双击） |
| 装到一半网断了 | 重新粘贴那一行命令，已经装好的部分会跳过 |
| 更新后酒馆出问题 | 工具箱选 **8 退回上一个版本** |
| 想用手机访问 | 暂时不支持，只能在装酒馆的这台电脑上用 |
| Windows：粘贴后提示「无法识别 curl.exe」或一堆红字 | 确认是在 **PowerShell** 里粘贴的（不是「命令提示符」）；系统太旧的话先装 Windows 更新，或者用上面的 ZIP 方式 |
| Windows：「Windows 已保护你的电脑」 | 点「更多信息」→「仍要运行」 |
| 别的问题 | 工具箱选 **7 诊断**，把桌面上的「酒馆诊断报告」[发到 Issues](https://github.com/Horace-Maxwell/Easy-SillyTavern/issues)，或者发给帮你的人。报告里没有你的密钥和聊天内容 |

> [!IMPORTANT]
> 这是**非官方**项目，和 SillyTavern 开发团队没有关系。安装器的问题请到[本仓库的 Issues](https://github.com/Horace-Maxwell/Easy-SillyTavern/issues) 反馈，不要去打扰官方。

---

## 📦 装了哪些东西

全部在一个文件夹里，不碰系统：

- Mac：`~/SillyTavern-Easy`（在「访达」里按 `⌘⇧H` 就能看到）
- Windows：`%LOCALAPPDATA%\SillyTavern-Easy`，一般是 `C:\Users\你的用户名\AppData\Local\SillyTavern-Easy`。故意不放「文档」「桌面」，免得被 OneDrive 同步

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

卸载：工具箱选 **9 卸载**，它会先把聊天记录备份到桌面再删。

## 🔧 给懂行的人

<details>
<summary>实现细节、环境变量和命令</summary>
<br>

- Mac 脚本：[mac/easy-st.sh](mac/easy-st.sh)，只用 macOS 自带的 bash 3.2 / curl / tar / shasum / ditto
- Windows 脚本：[windows/easy-st.ps1](windows/easy-st.ps1)，兼容 Win10 自带的 Windows PowerShell 5.1，只用系统自带的 curl.exe / robocopy 和 .NET；文件必须是带 BOM 的 UTF-8
- 酒馆从 npm 上的官方 `sillytavern` 包下载（npmjs 或 npmmirror，用 `dist.integrity` 校验），再从 GitHub 拿同版本的 `package-lock.json` 跑 `npm ci --ignore-scripts`
- Node.js 用 `SHASUMS256.txt` 校验；macOS ≥ 13.5 用 Node 24，11～13.4 用 Node 22，10.15 用 Node 20；Windows 10 / 11 用 Node 24（x64 或 arm64，32 位系统用 22）
- 酒馆用 `--configPath` / `--dataRoot` 启动，程序目录可以整个替换
- 常用环境变量：`EST_HOME`（安装位置）、`EST_LANG=zh|en`、`EST_YES=1`（不问问题）、`EST_NO_START=1`、`EST_NO_BROWSER=1`、`EST_NO_SHORTCUTS=1`
- 命令：`easy-st.sh install | start | menu | update | backup | restore | import | doctor | rollback | uninstall`（Windows：`powershell -ExecutionPolicy Bypass -File easy-st.ps1 <命令>`）
- 两边要对齐的行为：[docs/DESIGN.md](docs/DESIGN.md)

</details>

**想帮忙？** 欢迎提 Issue 和 PR。改脚本前先看一眼 [docs/DESIGN.md](docs/DESIGN.md)，Mac 和 Windows 两边的行为要保持一致。

## 📄 许可

本仓库的脚本使用 [MIT](LICENSE) 许可。SillyTavern 本身是 AGPL-3.0，安装时从官方渠道下载，不在本仓库里。

<div align="center">
<br>
<sub>觉得好用的话，点右上角 ⭐ Star，让更多人找到它。</sub>
</div>
