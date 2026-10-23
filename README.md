# Easy SillyTavern · 酒馆一键安装

给**从没装过软件、不会用命令行**的人准备的 [SillyTavern（酒馆）](https://github.com/SillyTavern/SillyTavern) 安装器。复制一行字、按一下回车，剩下的它自己看着办。

- **不用装别的**：不需要 Homebrew、Xcode、Git、Node.js，也不要管理员密码
- **自己看网络**：自动测速，国内走 npmmirror / jsDelivr 镜像，国外走官方源；下载的文件都做校验
- **认得代理**：开着 Clash、Surge 这类「系统代理」时，下载和酒馆连 OpenAI / Claude / Gemini 都会自动走代理；代理软件没开却残留了系统代理设置的话，也能认出来并绕开
- **认得这台 Mac**：Apple 芯片还是 Intel、macOS 版本多少，自动选对应的 Node.js；硬盘空间不够会提前说
- **认得旧酒馆**：发现电脑上已经有酒馆（官方版、免安装包、STL 启动器）的聊天记录，会问你要不要复制过来，原来的文件不动
- **更新不丢记录**：程序和聊天记录分开放；更新前自动备份，新版本有问题还能一键退回
- **出问题有报告**：「诊断」会生成一份不含密钥和聊天内容的报告，直接发给帮你的人

> Windows 版在做，见 [windows/](windows/)。

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

## 装好之后

**连上 AI**：酒馆只是聊天界面，回话的 AI 需要 API 密钥。点页面顶上第 2 个图标（插头 🔌）→「API」选「聊天补全」→ 选你的服务商（比如 DeepSeek）→ 粘贴密钥 → 点「连接」，圆点变绿就好了。

**聊天记录在哪**：`~/SillyTavern-Easy/data`。工具箱里选「打开数据文件夹」可以直接打开。

**换电脑**：工具箱里「备份」，把备份文件拷到新电脑，新电脑装好后在工具箱里「从备份恢复」。

## 常见问题

| 情况 | 怎么办 |
| --- | --- |
| 浏览器没自动打开 | 浏览器地址栏输入黑色窗口里写的地址，一般是 `http://127.0.0.1:8000` |
| 再双击「酒馆 SillyTavern」没反应 | 它已经在运行了，会直接帮你打开网页；看看浏览器 |
| 连不上 OpenAI / Claude / Gemini | 打开代理软件的「系统代理」，然后**重新启动酒馆**（关掉黑色窗口再双击） |
| 装到一半网断了 | 重新粘贴那行命令，已经下好的部分会跳过 |
| 别的问题 | 工具箱选「诊断」，把桌面上的「酒馆诊断报告」发给帮你的人 |

## 装了哪些东西

全部在 `~/SillyTavern-Easy` 里，不碰系统：

```
~/SillyTavern-Easy/
├── runtime/node/    私有的 Node.js
├── app/             酒馆程序（更新时整个换掉；app.prev 是上一个版本）
├── data/            聊天记录、角色卡、设置（更新时不动）
├── config.yaml      酒馆配置
├── backups/         备份
├── logs/            运行记录（最近 5 次）
└── easy-st.sh       工具箱本体
```

卸载：工具箱选「卸载」，它会先把聊天记录备份到桌面再删。

## 给懂行的人

- 脚本：[mac/easy-st.sh](mac/easy-st.sh)，只用 macOS 自带的 bash 3.2 / curl / tar / shasum
- 酒馆从 npm 上的官方 `sillytavern` 包下载（npmjs 或 npmmirror，用 `dist.integrity` 校验），再从 GitHub 拿同版本的 `package-lock.json` 跑 `npm ci --ignore-scripts`
- Node.js 用 `SHASUMS256.txt` 校验；macOS ≥ 13.5 用 Node 24，11～13.4 用 Node 22，10.15 用 Node 20
- 酒馆用 `--configPath` / `--dataRoot` 启动，程序目录可以整个替换
- 常用环境变量：`EST_HOME`（安装位置）、`EST_LANG=zh|en`、`EST_YES=1`（不问问题）、`EST_NO_START=1`、`EST_NO_BROWSER=1`、`EST_NO_SHORTCUTS=1`
- 命令：`easy-st.sh install | start | menu | update | backup | restore | import | doctor | rollback | uninstall`
- 设计和 Windows 版要对齐的行为：[docs/DESIGN.md](docs/DESIGN.md)

## 许可

本仓库的脚本使用 MIT 许可。SillyTavern 本身是 AGPL-3.0，安装时从官方渠道下载，不在本仓库里。
