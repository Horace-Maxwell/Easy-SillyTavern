<div align="center">

<img src="docs/assets/banner-en.svg" alt="Easy SillyTavern" width="100%">

<p>
  <a href="https://github.com/Horace-Maxwell/Easy-SillyTavern/actions/workflows/check.yml"><img src="https://github.com/Horace-Maxwell/Easy-SillyTavern/actions/workflows/check.yml/badge.svg" alt="check"></a>
  <img src="https://img.shields.io/badge/macOS-10.15%2B-111?logo=apple&logoColor=white" alt="macOS 10.15+">
  <img src="https://img.shields.io/badge/Windows-10%20%7C%2011-0078D4?logo=windows&logoColor=white" alt="Windows 10 | 11">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-e0841c" alt="MIT"></a>
</p>

**A [SillyTavern](https://github.com/SillyTavern/SillyTavern) installer for people who have never used a terminal.<br>Paste one line, press Enter, and it takes care of the rest.**

[简体中文](README.md) · **English**

[Mac](#-mac) · [Windows](#-windows) · [After installing](#-after-installing) · [Troubleshooting](#-troubleshooting) · [For developers](#-for-developers)

</div>

<br>

<div align="center">
<img src="docs/assets/demo-en.svg" alt="Installer demo" width="760">
</div>

> [!IMPORTANT]
> This is an **unofficial** project and is not affiliated with the SillyTavern team. Please report installer problems [here](https://github.com/Horace-Maxwell/Easy-SillyTavern/issues), not to the official channels.

## ✨ What it does for you

| Feature | Details |
| --- | --- |
| 🧰 **Nothing else to install** | No Homebrew, Xcode, Git or Node.js, and no admin password |
| 🌏 **Picks the fastest source** | Benchmarks official sources against China mirrors (npmmirror / jsDelivr); every download is checksum-verified |
| 🛰️ **Proxy-aware** | Uses your system proxy for downloads and for SillyTavern's connections to OpenAI / Claude / Gemini; ignores a stale proxy setting left behind by a closed proxy app |
| 💻 **Knows your machine** | Apple silicon or Intel, x64 or ARM, OS version — picks the matching Node.js and checks disk space first |
| 🍺 **Finds your old install** | Spots chats from an official install, a portable build or the STL launcher and offers to copy them over, leaving the originals untouched |
| 🛟 **Safe updates** | App and data live apart; every update is preceded by a backup, and a bad version rolls back in one step |
| 🩺 **Diagnostics** | Generates a report with no API keys or chat content, ready to share with whoever is helping you |

### Compared with a manual install

| | Manual install (official docs) | Easy SillyTavern |
| --- | :---: | :---: |
| Install Git and Node.js first | Yes | **No** |
| Admin password | Usually, for the prerequisites | **No** |
| Updating | `git pull` / `npm install` in a terminal | **Toolbox → 2, with automatic backup** |
| Update broke something | You're on your own | **One-step rollback** |
| Moving to a new computer | Copy the `data` folder by hand | **Backup → Restore, works across Mac and Windows** |

> Supports macOS 10.15+ and Windows 10 / 11. Needs 1.5 GB of free disk space; the first install downloads about 200 MB and takes 1–5 minutes.

---

## 🍎 Mac

**1. Open Terminal**

Press `⌘ Command + Space`, type `Terminal`, press Enter.

**2. Paste this line into Terminal and press Enter**

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Horace-Maxwell/Easy-SillyTavern/main/mac/easy-st.sh)"
```

<sub>In mainland China, use `https://fastly.jsdelivr.net/gh/Horace-Maxwell/Easy-SillyTavern@main/mac/easy-st.sh` instead.</sub>

**3. Wait for it to finish**

- If macOS asks whether Terminal may access your Desktop (or Documents / Downloads), click **Allow**. It's looking for old chats and placing shortcuts on your Desktop. Clicking "Don't Allow" still works, you just won't get Desktop shortcuts
- If it finds existing chats, type the number shown to copy them over, or just press Enter to skip
- When it asks "Start SillyTavern now?", press Enter and your browser opens SillyTavern

> [!NOTE]
> The installer **never asks for a password**. If you see `Password:`, you pasted something else — close the window and try again.

<details>
<summary><b>Prefer not to use Terminal?</b></summary>
<br>

Click the green **Code → Download ZIP** on this page, unzip it, open the `mac` folder and double-click **双击安装酒馆** ("double-click to install").

macOS blocks it the first time: click "Done", then go to **System Settings → Privacy & Security**, scroll down, click **Open Anyway** and enter your login password (macOS asks for it, not the installer). The Terminal method skips this step.

</details>

---

## 🪟 Windows

**1. Open PowerShell**

Press `Win + R`, type `powershell`, press Enter.

**2. Paste this line and press Enter**

```powershell
curl.exe -fsSLo "$env:TEMP\easy-st.ps1" https://raw.githubusercontent.com/Horace-Maxwell/Easy-SillyTavern/main/windows/easy-st.ps1; if ($?) { powershell -NoProfile -ExecutionPolicy Bypass -File "$env:TEMP\easy-st.ps1" }
```

<sub>In mainland China, replace the URL with `https://fastly.jsdelivr.net/gh/Horace-Maxwell/Easy-SillyTavern@main/windows/easy-st.ps1`.</sub>

**3. Wait for it to finish.** When it asks "Start SillyTavern now?", press Enter.

<details>
<summary><b>Prefer not to use PowerShell?</b></summary>
<br>

Click **Code → Download ZIP**, **right-click it and choose "Extract All"**, open the `windows` folder and double-click **双击安装酒馆**.

If you see "Windows protected your PC", click **More info → Run anyway**. If your antivirus asks, choose "Allow".

</details>

---

## 🍻 After installing

Two icons appear on your Desktop:

| Icon | What it does |
| --- | --- |
| **SillyTavern** | Starts SillyTavern and opens your browser. Keep the console window open while you use it; close it to quit |
| **SillyTavern Toolbox** | A numbered menu, see below |

<table>
<tr><th>#</th><th>Action</th><th>#</th><th>Action</th></tr>
<tr><td align="center">1</td><td>Start SillyTavern</td><td align="center">6</td><td>Restore from a backup</td></tr>
<tr><td align="center">2</td><td>Check for updates (backs up first)</td><td align="center">7</td><td>Diagnose (creates a report on the Desktop)</td></tr>
<tr><td align="center">3</td><td>Back up data</td><td align="center">8</td><td>Roll back to the previous version</td></tr>
<tr><td align="center">4</td><td>Open the data folder</td><td align="center">9</td><td>Uninstall (backs up to the Desktop first)</td></tr>
<tr><td align="center">5</td><td>Import data from another SillyTavern</td><td align="center">0</td><td>Quit</td></tr>
</table>

### Connecting an AI

SillyTavern is the chat interface; the replies come from an AI provider, which needs an API key from that provider's website.

1. Click the **plug icon 🔌** (second in the top bar)
2. Set **API** to **Chat Completion**
3. Pick your provider under **Chat Completion Source**
4. Paste your key and click **Connect** — the dot turns green
5. Tick **Auto-connect to Last Server** so you don't have to do this again

### Moving to a new computer

Old computer: Toolbox → **3 Back up**, then copy the backup file to the new computer's **Desktop** or **Downloads**.
New computer: install, then Toolbox → **6 Restore** and pick the file. Mac ↔ Windows works too.

---

## 🧯 Troubleshooting

| Problem | Fix |
| --- | --- |
| Browser didn't open | Visit the address shown in the console window, usually `http://127.0.0.1:8000` |
| Clicked "SillyTavern" twice | Harmless — it notices it's already running and just opens the page |
| No icons on the Mac Desktop | In Finder press `⌘ Command + ⇧ Shift + H`, open **SillyTavern-Easy**; the launchers are in there |
| Can't reach OpenAI / Claude / Gemini behind a proxy | Turn on your proxy app's "system proxy", then restart SillyTavern |
| Network dropped mid-install | Paste the line again; finished parts are skipped |
| Something broke after an update | Toolbox → **8 Roll back** |
| Windows: `curl.exe` not recognized / red errors | Make sure you're in **PowerShell**, not Command Prompt; update Windows or use the ZIP method |
| Anything else | Toolbox → **7 Diagnose**, then attach the report to an [issue](https://github.com/Horace-Maxwell/Easy-SillyTavern/issues). It contains no keys or chats |

---

## 📦 What gets installed

Everything lives in one folder; nothing system-wide is touched:

- Mac: `~/SillyTavern-Easy`
- Windows: `%LOCALAPPDATA%\SillyTavern-Easy` (deliberately not in Documents or Desktop, so OneDrive won't sync it)

```
SillyTavern-Easy/
├── runtime/node/    private Node.js
├── app/             SillyTavern (replaced on update; app.prev is the previous version)
├── data/            chats, characters, settings (never touched by updates)
├── config.yaml      SillyTavern config
├── backups/         backups (.tar.gz on Mac, .zip on Windows)
├── logs/            last 5 run logs
└── easy-st.sh       the toolbox itself (easy-st.ps1 on Windows)
```

## 🔧 For developers

<details>
<summary>Implementation notes, environment variables and commands</summary>
<br>

- Mac: [mac/easy-st.sh](mac/easy-st.sh), uses only what ships with macOS — bash 3.2, curl, tar, shasum, ditto
- Windows: [windows/easy-st.ps1](windows/easy-st.ps1), runs on the Windows PowerShell 5.1 that ships with Windows 10, using only the bundled curl.exe, robocopy and .NET; must be saved as UTF-8 with BOM
- SillyTavern comes from the official `sillytavern` npm package (npmjs or npmmirror, verified against `dist.integrity`), then `npm ci --ignore-scripts` with the matching `package-lock.json` from GitHub
- Node.js is verified against `SHASUMS256.txt`; macOS ≥ 13.5 gets Node 24, 11–13.4 Node 22, 10.15 Node 20; Windows 10 / 11 gets Node 24 (x64 or arm64; Node 22 on 32-bit)
- SillyTavern runs with `--configPath` / `--dataRoot`, so the app folder can be swapped wholesale
- Environment variables: `EST_HOME` (install location), `EST_LANG=zh|en`, `EST_YES=1` (no prompts), `EST_NO_START=1`, `EST_NO_BROWSER=1`, `EST_NO_SHORTCUTS=1`
- Commands: `easy-st.sh install | start | menu | update | backup | restore | import | doctor | rollback | uninstall` (Windows: `powershell -ExecutionPolicy Bypass -File easy-st.ps1 <command>`)
- Behaviour both platforms must share: [docs/DESIGN.md](docs/DESIGN.md)

</details>

Issues and PRs welcome. Read [docs/DESIGN.md](docs/DESIGN.md) before changing a script — Mac and Windows must behave the same.

## 📄 License

The scripts in this repository are [MIT](LICENSE). SillyTavern itself is AGPL-3.0 and is downloaded from official sources at install time; it is not included here.

<div align="center">
<br>
<sub>If this saved you some time, a ⭐ helps others find it.</sub>
</div>
