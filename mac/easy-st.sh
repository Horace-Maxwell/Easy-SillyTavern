#!/bin/bash
#
# Easy SillyTavern · macOS / Linux / Android (Termux)
# 酒馆 SillyTavern 一键安装 / 启动 / 更新 / 备份 / 诊断
#
#   安装：bash -c "$(curl -fsSL <本文件的地址>)"
#   之后：双击桌面上的「酒馆 SillyTavern」启动，「酒馆工具箱」做更新、备份、诊断。
#         Linux 在应用菜单里找；手机上打开 Termux 输入 tavern、tavern-tools。
#
# 文件放在 mac/ 下是历史原因：装好的工具箱都从这个路径自更新，别搬走。
#
# 不需要 Homebrew、Xcode、管理员密码。所有东西都装在 ~/SillyTavern-Easy 里：
#   runtime/node   私有的 Node.js（按芯片和系统版本自动选；Termux 用 pkg 装的）
#   app/           SillyTavern 程序本体（更新时整个替换）
#   data/          聊天记录、角色卡、设置（更新时不动）
#   config.yaml    酒馆配置
#
# macOS 上只用系统自带的 bash 3.2、curl、tar、shasum，别加 bash 4 以后才有的写法。

set -u

EST_VERSION="0.2.0"
EST_REPO="${EST_REPO:-Horace-Maxwell/Easy-SillyTavern}"
EST_BRANCH="${EST_BRANCH:-main}"

EST_ISSUES="https://github.com/$EST_REPO/issues"

if [ "$(uname -s)" = Darwin ]; then
    PLATFORM=mac
elif [ "$(uname -o 2>/dev/null)" = Android ]; then
    PLATFORM=termux
else
    PLATFORM=linux
fi

# 写进快捷方式和用来查语法的 bash。Termux 上没有 /bin/bash
BASH_BIN=/bin/bash
[ -x "$BASH_BIN" ] || BASH_BIN="$BASH"

# 放快捷方式、诊断报告、卸载前备份的地方
default_desktop() {
    case "$PLATFORM" in
        mac) printf '%s' "$HOME/Desktop" ;;
        # 中文系统上桌面是 ~/桌面，要问系统
        linux) xdg-user-dir DESKTOP 2>/dev/null || printf '%s' "$HOME/Desktop" ;;
        # 手机上没有桌面。开了存储权限就放「下载」，用户在文件管理器里看得到
        termux) if [ -d "$HOME/storage/downloads" ]; then printf '%s' "$HOME/storage/downloads"; else printf '%s' "$HOME"; fi ;;
    esac
}

EST_HOME="${EST_HOME:-$HOME/SillyTavern-Easy}"
EST_DESKTOP="${EST_DESKTOP:-$(default_desktop)}"
NODE_DIR="$EST_HOME/runtime/node"
# Termux 用 pkg 装的 Node.js，官方编译的跑不了（安卓的 C 库不一样）
[ "$PLATFORM" = termux ] && NODE_DIR="${PREFIX:-/data/data/com.termux/files/usr}"
NOGIT_DIR="$EST_HOME/runtime/nogit"
APP_DIR="$EST_HOME/app"
DATA_DIR="$EST_HOME/data"
CONFIG="$EST_HOME/config.yaml"
LOG_DIR="$EST_HOME/logs"
BACKUP_DIR="$EST_HOME/backups"
STATE="$EST_HOME/state.env"
SELF="$EST_HOME/easy-st.sh"
MARKER="$EST_HOME/.easy-sillytavern"
RUN_INFO="$EST_HOME/run.info"
NODE="$NODE_DIR/bin/node"
NPM="$NODE_DIR/bin/npm"

PORT_FIRST=8000
PORT_LAST=8019
# 酒馆运行时会按需下载的分词器，提前放进缓存，免得国内网络第一次用时卡住
TOKENIZERS="deepseek qwen2 nemo command-r command-a"

export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

# ---------------------------------------------------------------- 输出 ---

detect_lang() {
    local v="${EST_LANG:-}"
    if [ -z "$v" ]; then
        case "$PLATFORM" in
            mac) v="$(defaults read -g AppleLocale 2>/dev/null)" ;;
            # Termux 里 LANG 永远是 en_US，手机的语言要问安卓
            termux) v="$(getprop persist.sys.locale 2>/dev/null)"
                    [ -n "$v" ] || v="$(getprop ro.product.locale 2>/dev/null)" ;;
        esac
    fi
    printf '%s' "${v:-${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}}"
}

case "$(detect_lang)" in
    zh*|*zh_*|*zh-*) EST_LANG=zh ;;
    *) EST_LANG=en ;;
esac

# t "中文" "English"：按系统语言挑一句
t() { if [ "$EST_LANG" = zh ]; then printf '%s' "$1"; else printf '%s' "${2:-$1}"; fi; }

if [ -t 1 ]; then
    C_R=$'\033[31m'; C_G=$'\033[32m'; C_Y=$'\033[33m'; C_B=$'\033[36m'; C_D=$'\033[2m'; C_0=$'\033[0m'
else
    C_R=; C_G=; C_Y=; C_B=; C_D=; C_0=
fi
step() { printf '\n%s▶ %s%s\n' "$C_B" "$(t "$1" "${2:-}")" "$C_0"; }
info() { printf '  %s\n' "$(t "$1" "${2:-}")"; }
ok()   { printf '  %s✓ %s%s\n' "$C_G" "$(t "$1" "${2:-}")" "$C_0"; }
warn() { printf '  %s! %s%s\n' "$C_Y" "$(t "$1" "${2:-}")" "$C_0"; }
err()  { printf '  %s✗ %s%s\n' "$C_R" "$(t "$1" "${2:-}")" "$C_0"; }

pause() {
    [ -t 0 ] || return 0
    printf '\n  %s' "$(t "按回车键继续……" "Press Enter to continue...")"
    read -r _ || true
}

# 「酒馆工具箱」在这个系统上怎么打开
toolbox_hint() {
    if [ "$PLATFORM" = termux ]; then
        t "输入 tavern-tools 打开工具箱" "Run tavern-tools to open the toolbox"
    else
        t "打开「酒馆工具箱」" "Open the toolbox"
    fi
}

die() {
    err "$@"
    # 第一次安装失败时工具箱还不存在，不能叫用户去开它
    if setup_done; then
        printf '\n  %s\n' "$(t "$(toolbox_hint)，选「诊断」，把生成的报告发给帮你的人。" \
            "$(toolbox_hint), choose Diagnose, and send the report to whoever helps you.")"
    else
        printf '\n  %s\n  %s\n' "$(t "可以再运行一次安装命令，已经装好的部分会跳过。" \
            "You can run the install command again; finished steps are skipped.")" \
            "$(t "还不行的话，把这个窗口截图发给帮你的人，或者发到：" \
            "If it still fails, send a screenshot of this window to whoever helps you, or post it at:") $EST_ISSUES"
    fi
    pause
    exit 1
}

# 能不能问用户问题。EST_ANSWERS="1 y" 是给自动测试用的：依次代答，不用真的敲键盘
has_input() { [ -n "${EST_ANSWERS:-}" ] || [ -t 0 ]; }

read_reply() {
    if [ -n "${EST_ANSWERS:-}" ]; then
        REPLY_TEXT="${EST_ANSWERS%% *}"
        case "$EST_ANSWERS" in
            *" "*) EST_ANSWERS="${EST_ANSWERS#* }" ;;
            *) EST_ANSWERS="" ;;
        esac
        return 0
    fi
    read -r REPLY_TEXT || REPLY_TEXT=""
}

# ask "问题" "question" 默认值(y/n)：返回 0 表示「是」。非交互时用默认值。
ask() {
    local def="${3:-y}" hint
    if [ -z "${EST_ANSWERS:-}" ]; then
        if [ "${EST_YES:-}" = 1 ]; then [ "$def" = y ]; return; fi
        if [ ! -t 0 ]; then [ "$def" = y ]; return; fi
    fi
    if [ "$def" = y ]; then hint="[Y/n]"; else hint="[y/N]"; fi
    printf '  %s %s ' "$(t "$1" "$2")" "$hint"
    read_reply
    case "$REPLY_TEXT" in
        [Yy]*|是*|好*|要*) return 0 ;;
        [Nn]*|否*|不*) return 1 ;;
        *) [ "$def" = y ] ;;
    esac
}

# --------------------------------------------------------------- 状态 ---

state_get() { [ -f "$STATE" ] && sed -n "s/^$1=//p" "$STATE" | tail -n 1; }
state_set() {
    mkdir -p "$EST_HOME"
    if [ -f "$STATE" ]; then
        grep -v "^$1=" "$STATE" > "$STATE.tmp" || true
        mv "$STATE.tmp" "$STATE"
    fi
    printf '%s=%s\n' "$1" "$2" >> "$STATE"
}

is_installed() { [ -x "$NODE" ] && [ -f "$APP_DIR/server.js" ] && [ -f "$CONFIG" ]; }
# 安装走完了最后一步。v0.1.0 不记 SETUP，看它写过的 SHORTCUTS
setup_done() { is_installed && { [ "$(state_get SETUP)" = "done" ] || [ -n "$(state_get SHORTCUTS)" ]; }; }
st_version() { sed -n 's/^ *"version": *"\([^"]*\)".*/\1/p' "$APP_DIR/package.json" 2>/dev/null | head -n 1; }

# -------------------------------------------------------- 系统检测 ---

detect_system() {
    FREE_MB=$(( $(df -Pk "$HOME" | awk 'NR==2 {print $4}') / 1024 ))
    UNSUPPORTED=""
    HAS_CLT=1
    ROSETTA=0
    case "$PLATFORM" in
        mac) detect_mac ;;
        linux) detect_linux ;;
        termux) detect_termux ;;
    esac
}

detect_mac() {
    NODE_OS=darwin
    MACHINE="$(t "这台 Mac" "this Mac")"
    MAC_VER="$(sw_vers -productVersion 2>/dev/null)"
    MAC_MAJOR="${MAC_VER%%.*}"
    MAC_MINOR="$(printf '%s' "$MAC_VER" | cut -d. -f2)"
    [ -n "$MAC_MINOR" ] || MAC_MINOR=0
    # 用 hw.optional.arm64 而不是 uname -m：终端开了 Rosetta 时 uname 会说 x86_64
    if [ "$(sysctl -n hw.optional.arm64 2>/dev/null)" = 1 ]; then ARCH=arm64; else ARCH=x64; fi
    ROSETTA="$(sysctl -n sysctl.proc_translated 2>/dev/null || echo 0)"
    if xcode-select -p >/dev/null 2>&1; then HAS_CLT=1; else HAS_CLT=0; fi
    SYS_DESC="macOS $MAC_VER · $( [ "$ARCH" = arm64 ] && t "Apple 芯片" "Apple silicon" || t "Intel 芯片" "Intel" )"

    # Node.js 各大版本支持的最低 macOS；酒馆要求 Node 20 以上
    if [ "$MAC_MAJOR" -ge 14 ] || { [ "$MAC_MAJOR" -eq 13 ] && [ "$MAC_MINOR" -ge 5 ]; }; then
        NODE_MAJOR=24
    elif [ "$MAC_MAJOR" -ge 11 ]; then
        NODE_MAJOR=22
    elif [ "$MAC_MAJOR" -eq 10 ] && [ "$MAC_MINOR" -ge 15 ]; then
        NODE_MAJOR=20
    else
        NODE_MAJOR=""
        UNSUPPORTED="$(t "这台 Mac 的系统太旧了（${MAC_VER}），酒馆最低需要 macOS 10.15。" \
            "macOS $MAC_VER is too old; SillyTavern needs macOS 10.15 or newer.")"
    fi
}

detect_linux() {
    NODE_OS=linux
    MACHINE="$(t "这台电脑" "this computer")"
    local machine distro glibc
    machine="$(uname -m)"
    distro="$(. /etc/os-release 2>/dev/null; printf '%s' "${PRETTY_NAME:-Linux}")"
    SYS_DESC="$distro · $machine"
    case "$machine" in
        x86_64|amd64)  ARCH=x64;    NODE_MAJOR=24 ;;
        aarch64|arm64) ARCH=arm64;  NODE_MAJOR=24 ;;
        # Node.js 24 起没有 32 位 ARM 版了（比如 32 位系统的树莓派）
        armv7l|armv8l) ARCH=armv7l; NODE_MAJOR=22 ;;
        *) ARCH="$machine"; NODE_MAJOR=""
           UNSUPPORTED="$(t "Node.js 没有 $machine 版本，这台电脑装不了酒馆。" "Node.js has no $machine build.")" ;;
    esac
    # 官方的 Node.js 要 glibc 2.28 以上；Alpine 这类 musl 系统跑不了
    glibc="$(getconf GNU_LIBC_VERSION 2>/dev/null | awk '{print $2}')"
    if [ -z "$glibc" ]; then
        UNSUPPORTED="$(t "这个系统不是 glibc 的（比如 Alpine），官方 Node.js 跑不了。请换 Ubuntu、Debian、Fedora 这类系统。" \
            "This system does not use glibc (Alpine, for example), so the official Node.js cannot run.")"
    elif ! awk -v v="$glibc" 'BEGIN { split(v, a, "."); exit !(a[1] > 2 || (a[1] == 2 && a[2] >= 28)) }'; then
        UNSUPPORTED="$(t "这个系统太旧了（glibc ${glibc}），Node.js 最低需要 glibc 2.28，比如 Ubuntu 20.04、Debian 10。" \
            "glibc $glibc is too old; Node.js needs 2.28 or newer (Ubuntu 20.04, Debian 10).")"
    fi
    command -v curl >/dev/null 2>&1 || UNSUPPORTED="$(t "还没有 curl。先在终端里运行 sudo apt install curl（Fedora 用 dnf，Arch 用 pacman），再重新安装。" \
        "curl is missing. Run sudo apt install curl (dnf on Fedora, pacman on Arch), then try again.")"
}

detect_termux() {
    NODE_OS=android
    NODE_MAJOR=termux
    MACHINE="$(t "这台手机" "this phone")"
    ARCH="$(uname -m)"
    SYS_DESC="Android $(getprop ro.build.version.release 2>/dev/null) · $ARCH"
}

# ---------------------------------------------------------- 代理检测 ---

# 读「系统设置 → 网络 → 代理」（Clash、Surge 等开了「系统代理」就会写在这里）。
# 终端里的程序默认不走系统代理，这里把它找出来，并确认代理软件真的开着。
detect_proxy() {
    PROXY_URL=""
    PROXY_SRC=""
    if [ -n "${https_proxy:-${HTTPS_PROXY:-${all_proxy:-${ALL_PROXY:-}}}}" ]; then
        PROXY_URL="${https_proxy:-${HTTPS_PROXY:-${all_proxy:-${ALL_PROXY:-}}}}"
        PROXY_SRC="env"
        return 0
    fi
    [ "$(state_get PROXY)" = off ] && return 0
    [ "$PLATFORM" = mac ] || return 0

    local dump host port kind
    dump="$(scutil --proxy 2>/dev/null)" || return 0
    get() { printf '%s\n' "$dump" | awk -v k="$1" '$1 == k {print $3; exit}'; }
    if [ "$(get HTTPSEnable)" = 1 ]; then
        host="$(get HTTPSProxy)"; port="$(get HTTPSPort)"; kind=http
    elif [ "$(get HTTPEnable)" = 1 ]; then
        host="$(get HTTPProxy)"; port="$(get HTTPPort)"; kind=http
    elif [ "$(get SOCKSEnable)" = 1 ]; then
        host="$(get SOCKSProxy)"; port="$(get SOCKSPort)"; kind=socks5
    else
        return 0
    fi
    [ -n "$host" ] && [ -n "$port" ] || return 0
    # 代理软件关了但系统代理没清掉时，所有连接都会失败，这种情况当作没有代理
    if ! nc -z -G 2 "$host" "$port" >/dev/null 2>&1; then
        PROXY_DEAD="$kind://$host:$port"
        return 0
    fi
    PROXY_URL="$kind://$host:$port"
    PROXY_SRC=system
}

# 代理地址里可能带账号密码，屏幕和诊断报告上都不显示
safe_url() { printf '%s' "$1" | sed 's#//[^/@]*@#//***@#'; }

apply_proxy() {
    if [ -n "$PROXY_URL" ] && [ "$PROXY_SRC" = system ]; then
        export http_proxy="$PROXY_URL" https_proxy="$PROXY_URL" all_proxy="$PROXY_URL"
        export HTTP_PROXY="$PROXY_URL" HTTPS_PROXY="$PROXY_URL" ALL_PROXY="$PROXY_URL"
        export no_proxy="localhost,127.0.0.1,::1" NO_PROXY="localhost,127.0.0.1,::1"
    fi
}

# ---------------------------------------------------------- 网络选源 ---

# 并行探测一组地址，打印最快能连上的那个；都连不上就什么都不打印
pick_fastest() {
    local tmp i=0 u code tm best="" best_t=999
    tmp="$(mktemp -d)"
    for u in "$@"; do
        ( curl -s -o /dev/null -r 0-0 --connect-timeout 5 --max-time 8 \
              -w '%{http_code} %{time_total}\n' "$u" > "$tmp/$i" 2>/dev/null ) &
        i=$((i + 1))
    done
    wait
    i=0
    for u in "$@"; do
        read -r code tm < "$tmp/$i" 2>/dev/null || code=000
        case "$code" in
            2*|3*)
                if awk -v a="$tm" -v b="$best_t" 'BEGIN { exit !(a < b) }'; then best="$u"; best_t="$tm"; fi ;;
        esac
        i=$((i + 1))
    done
    rm -rf "$tmp"
    printf '%s' "$best"
}

choose_sources() {
    step "检测网络，挑最快的下载源" "Checking the network and picking the fastest mirrors"
    detect_proxy
    if [ -n "$PROXY_URL" ]; then
        ok "发现代理 $(safe_url "$PROXY_URL")，下载会走代理" "Using proxy $(safe_url "$PROXY_URL")"
    elif [ -n "${PROXY_DEAD:-}" ]; then
        warn "系统代理设置成了 ${PROXY_DEAD}，但它没在运行，先不走代理" \
            "System proxy $PROXY_DEAD is set but not running; ignoring it"
    fi
    apply_proxy

    local npm_official="https://registry.npmjs.org" npm_cn="https://registry.npmmirror.com"
    local winner
    winner="$(pick_fastest "$npm_official/sillytavern/latest" "$npm_cn/sillytavern/latest")"
    case "$winner" in
        "$npm_official"*) NPM_REGISTRY="$npm_official"; NPM_FALLBACK="$npm_cn"; REGION=global ;;
        "$npm_cn"*)       NPM_REGISTRY="$npm_cn"; NPM_FALLBACK="$npm_official"; REGION=cn ;;
        *) die "连不上网络（npm 官方源和国内镜像都打不开）。请检查网络后重试。" \
               "No network: neither npmjs.org nor npmmirror.com is reachable." ;;
    esac

    local node_official="https://nodejs.org/dist" node_cn="https://cdn.npmmirror.com/binaries/node"
    if [ "$REGION" = cn ]; then NODE_MIRRORS="$node_cn $node_official"; else NODE_MIRRORS="$node_official $node_cn"; fi

    # GitHub 上的小文件：国内优先走 jsDelivr
    if [ "$REGION" = cn ]; then
        GH_ROUTES="jsd-fastly jsd raw"
    else
        GH_ROUTES="raw jsd jsd-fastly"
    fi
    if [ "$REGION" = cn ]; then
        ok "使用国内镜像（npmmirror）" "Using China mirrors (npmmirror)"
    else
        ok "使用官方源" "Using official sources"
    fi
    state_set REGION "$REGION"
}

# gh_urls 仓库 版本 文件路径：按 GH_ROUTES 的顺序列出这个文件的几个下载地址
gh_urls() {
    local repo="$1" ref="$2" path="$3" r
    for r in $GH_ROUTES; do
        case "$r" in
            raw)        printf '%s\n' "https://raw.githubusercontent.com/$repo/$ref/$path" ;;
            jsd)        printf '%s\n' "https://cdn.jsdelivr.net/gh/$repo@$ref/$path" ;;
            jsd-fastly) printf '%s\n' "https://fastly.jsdelivr.net/gh/$repo@$ref/$path" ;;
        esac
    done
}

# fetch 目标文件 地址1 地址2 …：依次尝试，成功一个就停
fetch() {
    local dest="$1" u
    shift
    for u in "$@"; do
        [ -n "$u" ] || continue
        rm -f "$dest.part"
        if curl -fL --connect-timeout 10 --retry 2 --retry-delay 2 --progress-bar -o "$dest.part" "$u"; then
            mv "$dest.part" "$dest"
            return 0
        fi
        warn "这个地址下载失败，换一个：$u" "Download failed, trying next: $u"
    done
    rm -f "$dest.part"
    return 1
}

# 小文件静默下载
fetch_quiet() {
    local dest="$1" u
    shift
    for u in "$@"; do
        [ -n "$u" ] || continue
        if curl -fsSL --connect-timeout 8 --max-time 60 -o "$dest.part" "$u" 2>/dev/null; then
            mv "$dest.part" "$dest"
            return 0
        fi
    done
    rm -f "$dest.part"
    return 1
}

# --------------------------------------------------------- 安装 Node ---

node_major_installed() { [ -x "$NODE" ] && "$NODE" -p 'process.versions.node.split(".")[0]' 2>/dev/null; }

sha256_of() {
    if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1"; else sha256sum "$1"; fi | awk '{print $1}'
}

# Termux 的软件包要先 upgrade，不然新包和旧的系统库对不上，node 一启动就报错
install_node_termux() {
    [ -x "$NODE" ] && "$NODE" -v >/dev/null 2>&1 && {
        ok "已经有 Node.js $("$NODE" -v)，跳过" "Node.js $("$NODE" -v) already installed"
        return 0
    }
    info "用 Termux 自带的 pkg 安装 Node.js（几分钟，看网速）" "Installing Node.js with pkg (a few minutes)"
    export DEBIAN_FRONTEND=noninteractive
    pkg upgrade -y -o Dpkg::Options::=--force-confold && pkg install -y nodejs-lts \
        || die "Node.js 装不上。试试运行 termux-change-repo 换个下载源，再重新安装。" \
               "Could not install Node.js. Run termux-change-repo to pick another mirror, then try again."
    "$NODE" -v >/dev/null 2>&1 || die "Node.js 装好了但运行不了。" "Node.js was installed but does not run."
    ok "Node.js $("$NODE" -v) 安装完成" "Node.js $("$NODE" -v) installed"
}

install_node() {
    step "准备 Node.js（酒馆的运行环境）" "Setting up Node.js"
    if [ "$PLATFORM" = termux ]; then
        install_node_termux
        return
    fi
    if [ "$(node_major_installed)" = "$NODE_MAJOR" ]; then
        ok "已经有 Node.js $("$NODE" -v)，跳过" "Node.js $("$NODE" -v) already installed"
        return 0
    fi

    local tmp base ver file
    tmp="$(mktemp -d)"
    for base in $NODE_MIRRORS; do
        # index.json 一行一个版本，从新到旧排
        if fetch_quiet "$tmp/index.json" "$base/index.json"; then
            ver="$(grep -o "\"version\":\"v$NODE_MAJOR\.[0-9.]*\"" "$tmp/index.json" | head -n 1 | cut -d'"' -f4)"
            [ -n "$ver" ] && break
        fi
    done
    [ -n "${ver:-}" ] || die "查不到 Node.js 的版本列表，网络可能不稳定，请稍后重试。" \
        "Could not get the Node.js version list."

    file="node-$ver-$NODE_OS-$ARCH.tar.gz"
    info "下载 Node.js ${ver}（${ARCH}，约 50 MB）" "Downloading Node.js $ver ($ARCH, ~50 MB)"
    local got=""
    for base in $NODE_MIRRORS; do
        if fetch "$tmp/$file" "$base/$ver/$file" && fetch_quiet "$tmp/SHASUMS256.txt" "$base/$ver/SHASUMS256.txt"; then
            got="$base"
            break
        fi
    done
    [ -n "$got" ] || die "Node.js 下载失败，请检查网络后重试。" "Node.js download failed."

    local want have
    want="$(awk -v f="$file" '$2 == f {print $1}' "$tmp/SHASUMS256.txt")"
    have="$(sha256_of "$tmp/$file")"
    [ -n "$want" ] && [ "$want" = "$have" ] || die "Node.js 安装包校验不通过（文件可能下坏了），请重试。" \
        "Node.js checksum mismatch."

    mkdir -p "$EST_HOME/runtime"
    rm -rf "$NODE_DIR.new"
    mkdir -p "$NODE_DIR.new"
    tar -xzf "$tmp/$file" -C "$NODE_DIR.new" --strip-components 1 || die "Node.js 解压失败。" "Failed to unpack Node.js."
    rm -rf "$NODE_DIR"
    mv "$NODE_DIR.new" "$NODE_DIR"
    rm -rf "$tmp"
    "$NODE" -v >/dev/null 2>&1 || die "Node.js 装好了但运行不了。" "Node.js was installed but does not run."
    ok "Node.js $("$NODE" -v) 安装完成" "Node.js $("$NODE" -v) installed"
}

# ------------------------------------------------------ 安装 SillyTavern ---

# 只用我们自己的 npm 配置和缓存，避开用户 ~/.npmrc 里可能的怪设置和 sudo 留下的权限问题
npm_env() {
    mkdir -p "$EST_HOME/runtime"
    printf 'registry=%s\nfund=false\naudit=false\nupdate-notifier=false\n' "$NPM_REGISTRY" > "$EST_HOME/runtime/npmrc"
    export NPM_CONFIG_USERCONFIG="$EST_HOME/runtime/npmrc"
    export NPM_CONFIG_CACHE="$EST_HOME/runtime/npm-cache"
    export PATH="$NODE_DIR/bin:$PATH"
}

# 从 npm 的回应里挑最新的、这台电脑的 Node.js 跑得动的正式版。
# 旧系统只能用旧 Node.js，酒馆哪天提高了要求，这些电脑要留在还能跑的版本上，不能装坏
ST_PICK='
    let s = ""; process.stdin.on("data", c => s += c).on("end", () => {
        const j = JSON.parse(s), have = +process.versions.node.split(".")[0];
        const need = v => +(((v.engines && v.engines.node) || "").match(/\d+/) || [0])[0];
        const num = v => v.version.split(".").map(Number);
        const best = (j.versions ? Object.values(j.versions) : [j])
            .filter(v => !v.version.includes("-") && need(v) <= have)
            .sort((a, b) => num(b)[0] - num(a)[0] || num(b)[1] - num(a)[1] || num(b)[2] - num(a)[2])[0];
        if (!best) process.exit(1);
        console.log(best.version, best.dist.tarball, best.dist.integrity);
    });'

# 打印 "版本 下载地址 完整性校验值"。先看 latest，不合适再翻全部版本
st_latest_meta() {
    local reg doc json
    for reg in "$NPM_REGISTRY" "$NPM_FALLBACK"; do
        for doc in sillytavern/latest sillytavern; do
            json="$(curl -fsSL --connect-timeout 8 --max-time 60 "$reg/$doc" 2>/dev/null)" || continue
            printf '%s' "$json" | "$NODE" -e "$ST_PICK" 2>/dev/null && return 0
        done
    done
    return 1
}

verify_integrity() {
    "$NODE" -e '
        const [file, sri] = process.argv.slice(1);
        const i = sri.indexOf("-");
        const h = require("crypto").createHash(sri.slice(0, i)).update(require("fs").readFileSync(file)).digest("base64");
        process.exit(h === sri.slice(i + 1) ? 0 : 1);' "$1" "$2"
}

# install_st [force]：装最新版酒馆；已经是最新版就跳过
install_st() {
    step "下载酒馆 SillyTavern" "Downloading SillyTavern"
    npm_env
    local meta ver url sri cur
    meta="$(st_latest_meta)" || die "查不到酒馆的最新版本，网络可能不稳定，请稍后重试。" \
        "Could not look up the latest SillyTavern version."
    read -r ver url sri <<EOF
$meta
EOF
    cur="$(st_version)"
    if [ "$cur" = "$ver" ] && [ -d "$APP_DIR/node_modules" ] && [ "${1:-}" != force ]; then
        ok "已经是最新版 $ver" "Already on the latest version $ver"
        return 0
    fi
    [ -n "$cur" ] && info "当前版本 $cur → 最新版本 $ver" "Current $cur → latest $ver"

    local tmp new="$APP_DIR.new"
    tmp="$(mktemp -d)"
    info "下载酒馆 ${ver}（约 40 MB）" "Downloading SillyTavern $ver (~40 MB)"
    # 两个源的包是同一个文件，完整性校验值一样
    fetch "$tmp/st.tgz" "$url" "$NPM_FALLBACK/sillytavern/-/sillytavern-$ver.tgz" \
        || die "酒馆下载失败，请检查网络后重试。" "SillyTavern download failed."
    verify_integrity "$tmp/st.tgz" "$sri" || die "酒馆安装包校验不通过（文件可能下坏了），请重试。" \
        "SillyTavern package checksum mismatch."

    rm -rf "$new"
    mkdir -p "$new"
    tar -xzf "$tmp/st.tgz" -C "$new" --strip-components 1 || die "酒馆解压失败。" "Failed to unpack SillyTavern."

    # npm 上的包不带 package-lock.json，去 GitHub 拿对应版本的锁文件，保证装的依赖和官方一致
    local lock_ok=0
    # shellcheck disable=SC2046
    if fetch_quiet "$tmp/package-lock.json" $(gh_urls SillyTavern/SillyTavern "$ver" package-lock.json); then
        if "$NODE" -e 'const l = require(process.argv[1]); process.exit(l.version === process.argv[2] ? 0 : 1)' \
                "$tmp/package-lock.json" "$ver" 2>/dev/null; then
            cp "$tmp/package-lock.json" "$new/package-lock.json"
            lock_ok=1
        fi
    fi

    step "安装酒馆需要的组件（1～3 分钟）" "Installing dependencies (1-3 minutes)"
    local npm_args="--omit=dev --ignore-scripts --no-audit --no-fund --loglevel=error"
    local ok_npm=0
    for _ in 1 2; do
        if [ "$lock_ok" = 1 ]; then
            # shellcheck disable=SC2086
            (cd "$new" && NODE_ENV=production "$NPM" ci $npm_args) && { ok_npm=1; break; }
        else
            # shellcheck disable=SC2086
            (cd "$new" && NODE_ENV=production "$NPM" install --no-save $npm_args) && { ok_npm=1; break; }
        fi
        # 第一次失败就换另一个源再试
        warn "安装组件失败，换个源再试一次" "npm failed, retrying with the other registry"
        local swap="$NPM_REGISTRY"; NPM_REGISTRY="$NPM_FALLBACK"; NPM_FALLBACK="$swap"
        npm_env
    done
    [ "$ok_npm" = 1 ] || die "酒馆的组件没装上。" "Failed to install SillyTavern's dependencies."
    rm -rf "$EST_HOME/runtime/npm-cache" "$tmp"

    # 换上新版本；旧版本留一份，新版本出问题时可以退回
    rm -rf "$APP_DIR.prev"
    [ -d "$APP_DIR" ] && mv "$APP_DIR" "$APP_DIR.prev"
    mv "$new" "$APP_DIR"
    ok "酒馆 $ver 安装完成" "SillyTavern $ver installed"
}

# ------------------------------------------------------------- 配置 ---

# 酒馆默认的 DEBUG 级别会把发给 AI 的完整聊天内容写进运行记录，而诊断报告带着运行记录的末尾。
# 改成 INFO。v0.1.0 留下的旧记录里可能有聊天内容，趁改配置时一起删掉。
# 启动时也要跑：旧工具箱自更新后，那一次更新走的还是旧代码
quiet_logs() {
    [ -f "$CONFIG" ] && grep -q '^  minLogLevel: 0' "$CONFIG" || return 0
    sed 's/^  minLogLevel: 0/  minLogLevel: 1/' "$CONFIG" > "$CONFIG.tmp" && mv "$CONFIG.tmp" "$CONFIG"
    rm -f "$LOG_DIR"/st-*.log
}

write_config() {
    mkdir -p "$DATA_DIR" "$LOG_DIR" "$BACKUP_DIR"
    if [ ! -f "$CONFIG" ]; then
        # 没装苹果开发者工具的 Mac 上一调用系统 git 就弹窗，没装 Git 的电脑也不少，
        # 统一用酒馆内置的 git 功能装扩展
        sed 's/^  backend: auto$/  backend: builtin/' "$APP_DIR/default/config.yaml" > "$CONFIG"
        ok "已生成配置文件" "Config created"
    fi
    quiet_logs

    # 没装开发者工具时，/usr/bin/git 只是个会弹窗的空壳，给酒馆一个直接返回失败的占位 git
    mkdir -p "$NOGIT_DIR"
    printf '#!/bin/sh\nexit 1\n' > "$NOGIT_DIR/git"
    chmod +x "$NOGIT_DIR/git"
    touch "$MARKER"
}

seed_tokenizers() {
    mkdir -p "$DATA_DIR/_cache"
    local name missing=""
    for name in $TOKENIZERS; do
        [ -s "$DATA_DIR/_cache/$name.json.gz" ] || missing="$missing $name"
    done
    [ -n "$missing" ] || return 0
    step "预先下载分词器（让字数统计更准）" "Pre-downloading tokenizers"
    for name in $missing; do
        # shellcheck disable=SC2046
        if fetch_quiet "$DATA_DIR/_cache/$name.json.gz" $(gh_urls SillyTavern/SillyTavern-Tokenizers main "$name.json.gz"); then
            ok "$name"
        else
            warn "$name 没下载到，不影响使用" "$name skipped (not required)"
        fi
    done
}

# ------------------------------------------------------ 导入旧数据 ---

# 找这台 Mac 上别的酒馆（官方安装、免安装包、STL 启动器……）的数据文件夹
find_old_data() {
    local d
    {
        for d in "$HOME"/SillyTavern*/data "$HOME"/SillyTavern*/SillyTavern/data; do
            [ -d "$d/default-user" ] && printf '%s\n' "$d"
        done
        find "$EST_DESKTOP" "$HOME/Downloads" "$HOME/Documents" -maxdepth 6 -type d \
            -path '*/SillyTavern/data/default-user' 2>/dev/null | sed 's#/default-user$##'
    } | grep -v "^$EST_HOME/" | awk '!seen[$0]++'
}

# 把 src 里的东西合并复制到 dest，原文件不动
merge_copy() {
    if [ "$PLATFORM" = mac ]; then ditto "$1" "$2"; else cp -R "$1/." "$2/"; fi
}

# 这个数据文件夹里有多少聊天和角色，帮用户认出是哪一个
describe_data() {
    local chats chars
    chats="$(find "$1" -path '*/chats/*' -name '*.jsonl' 2>/dev/null | wc -l | tr -d ' ')"
    chars="$(find "$1"/*/characters -maxdepth 1 -name '*.png' 2>/dev/null | wc -l | tr -d ' ')"
    t "$chars 个角色、$chats 段聊天" "$chars characters, $chats chats"
}

import_data() {
    local src="$1"
    if [ -d "$DATA_DIR/default-user" ]; then
        info "先把现在的数据备份一下" "Backing up current data first"
        do_backup auto >/dev/null || true
    fi
    mkdir -p "$DATA_DIR"
    merge_copy "$src" "$DATA_DIR" || return 1
    ok "已导入：${2:-$src}" "Imported: ${2:-$src}"
}

offer_import() {
    local list n src i=1 choice
    list="$(find_old_data)"
    [ -n "$list" ] || { [ "${1:-}" = menu ] && info "没有找到别的酒馆数据。" "No other SillyTavern data found."; return 0; }
    n="$(printf '%s\n' "$list" | wc -l | tr -d ' ')"
    step "发现${MACHINE}上已经有酒馆的聊天记录" "Found existing SillyTavern data on $MACHINE"
    printf '%s\n' "$list" | while IFS= read -r src; do
        printf '   %s) %s  %s(%s)%s\n' "$i" "${src/#$HOME/~}" "$C_D" "$(describe_data "$src")" "$C_0"
        i=$((i + 1))
    done
    info "导入是「复制」，原来的文件不会被改动。" "Importing copies the files; the originals stay untouched."
    if { [ "${EST_YES:-}" = 1 ] && [ -z "${EST_ANSWERS:-}" ]; } || ! has_input; then
        info "（非交互模式，跳过导入）" "(non-interactive, skipping import)"
        return 0
    fi
    printf '  %s ' "$(t "要导入哪一个？输入编号，直接回车跳过：" "Import which one? Enter a number, or press Enter to skip:")"
    read_reply
    choice="$REPLY_TEXT"
    case "$choice" in
        ''|*[!0-9]*) info "跳过导入" "Skipped"; return 0 ;;
    esac
    [ "$choice" -ge 1 ] && [ "$choice" -le "$n" ] || { info "跳过导入" "Skipped"; return 0; }
    import_data "$(printf '%s\n' "$list" | sed -n "${choice}p")"
}

# --------------------------------------------------------- 快捷方式 ---

install_self() {
    mkdir -p "$EST_HOME"
    # 不能用 $0：bash -c 运行时 $0 是 /bin/bash 本身
    local me="${BASH_SOURCE[0]:-}"
    rm -f "$SELF.new"
    if [ -n "$me" ] && [ -f "$me" ]; then
        [ "$(cd "$(dirname "$me")" && pwd)/$(basename "$me")" = "$SELF" ] && return 0
        cp "$me" "$SELF.new"
    elif [ -n "${BASH_EXECUTION_STRING:-}" ]; then
        # 通过 bash -c "$(curl …)" 运行时，脚本内容就在这个变量里
        printf '%s\n' "$BASH_EXECUTION_STRING" > "$SELF.new"
    fi
    if [ -f "$SELF.new" ] && grep -q '^EST_VERSION=' "$SELF.new" && "$BASH_BIN" -n "$SELF.new" 2>/dev/null; then
        mv "$SELF.new" "$SELF"
    else
        rm -f "$SELF.new"
    fi
    chmod +x "$SELF" 2>/dev/null
}

# write_launchers 文件夹：在这个文件夹里放「启动」和「工具箱」两个可以双击的文件
write_launchers() {
    local start tools
    start="$1/$(t "酒馆 SillyTavern" "SillyTavern").command"
    tools="$1/$(t "酒馆工具箱" "SillyTavern Toolbox").command"
    { printf '#!%s\n# Easy SillyTavern：启动酒馆\nexec "%s" "%s" start\n' "$BASH_BIN" "$BASH_BIN" "$SELF" > "$start" &&
      printf '#!%s\n# Easy SillyTavern：更新、备份、诊断、卸载\nexec "%s" "%s" menu\n' "$BASH_BIN" "$BASH_BIN" "$SELF" > "$tools" &&
      chmod +x "$start" "$tools"; } 2>/dev/null || return 1
    LAUNCHERS="$start|$tools"
}

# write_commands 文件夹：放 tavern 和 tavern-tools 两个命令
write_commands() {
    mkdir -p "$1" 2>/dev/null || return 1
    { printf '#!%s\nexec "%s" "%s" start\n' "$BASH_BIN" "$BASH_BIN" "$SELF" > "$1/tavern" &&
      printf '#!%s\nexec "%s" "%s" menu\n' "$BASH_BIN" "$BASH_BIN" "$SELF" > "$1/tavern-tools" &&
      chmod +x "$1/tavern" "$1/tavern-tools"; } 2>/dev/null
}

# desktop_entry 名字 命令：打印一个 .desktop 文件
desktop_entry() {
    cat <<EOF
[Desktop Entry]
Type=Application
Name=$1
Exec=$BASH_BIN "$SELF" $2
Path=$EST_HOME
Icon=$EST_HOME/icon.png
Terminal=true
Categories=Network;Chat;
EOF
}

make_shortcuts_linux() {
    local dir bin="$HOME/.local/bin" apps="$HOME/.local/share/applications" made="" f
    write_commands "$bin" && made="$bin/tavern|$bin/tavern-tools"
    cp "$APP_DIR/public/img/apple-icon-144x144.png" "$EST_HOME/icon.png" 2>/dev/null
    for dir in "$apps" "$EST_DESKTOP"; do
        [ "$dir" = "$apps" ] && mkdir -p "$dir" 2>/dev/null
        [ -d "$dir" ] || continue
        desktop_entry "$(t "酒馆 SillyTavern" "SillyTavern")" start > "$dir/easy-sillytavern.desktop" 2>/dev/null || continue
        desktop_entry "$(t "酒馆工具箱" "SillyTavern Toolbox")" menu > "$dir/easy-sillytavern-tools.desktop" 2>/dev/null || continue
        for f in "$dir/easy-sillytavern.desktop" "$dir/easy-sillytavern-tools.desktop"; do
            chmod +x "$f"
            # GNOME 的桌面图标不信任就双击不了
            gio set "$f" metadata::trusted true >/dev/null 2>&1
            made="$made|$f"
        done
    done
    state_set SHORTCUTS "${made#|}"
    ok "应用菜单里放好了「$(t "酒馆 SillyTavern" "SillyTavern")」和「$(t "酒馆工具箱" "SillyTavern Toolbox")」" \
        "Added SillyTavern and its toolbox to your applications menu"
}

make_shortcuts_termux() {
    write_commands "$NODE_DIR/bin" || return 0
    state_set SHORTCUTS "$NODE_DIR/bin/tavern|$NODE_DIR/bin/tavern-tools"
    ok "命令放好了：tavern 启动酒馆，tavern-tools 打开工具箱" "Commands ready: tavern starts it, tavern-tools opens the toolbox"
}

make_shortcuts() {
    [ "${EST_NO_SHORTCUTS:-}" = 1 ] && return 0
    case "$PLATFORM" in
        linux) make_shortcuts_linux; return ;;
        termux) make_shortcuts_termux; return ;;
    esac
    # 安装文件夹里总放一份，桌面上的被删了或者没放成，也能从这里找到
    write_launchers "$EST_HOME"
    # 第一次往桌面写文件时 macOS 会问「终端想访问桌面文件夹」，点了「不允许」就会失败
    if [ -d "$EST_DESKTOP" ] && write_launchers "$EST_DESKTOP"; then
        state_set SHORTCUTS "$LAUNCHERS"
        ok "桌面上放好了「$(t "酒馆 SillyTavern" "SillyTavern")」和「$(t "酒馆工具箱" "SillyTavern Toolbox")」" \
            "Shortcuts created on the Desktop"
    else
        warn "没能在桌面放图标（可能点了「不允许」）。以后打开「访达」，按 ⌘⇧H，进「SillyTavern-Easy」文件夹，双击里面的「酒馆 SillyTavern」" \
            "Could not put shortcuts on the Desktop. Open Finder, press Cmd+Shift+H, go into SillyTavern-Easy and double-click \"SillyTavern\"."
        open "$EST_HOME" 2>/dev/null
    fi
}

# ------------------------------------------------------------- 启动 ---

# 这个进程的命令行
proc_cmdline() {
    if [ "$PLATFORM" = mac ]; then
        ps -p "$1" -o command= 2>/dev/null
    else
        { tr '\0' ' ' < "/proc/$1/cmdline"; } 2>/dev/null
    fi
}

# 打印正在运行的「这一份」酒馆的端口。启动时把进程号和端口记在 run.info 里，退出时删掉；
# 窗口被强行关掉时文件还在，所以要看这个进程号现在还是不是酒馆（重启后可能被别的程序用了）。
# 不靠 lsof 扫端口：手机和不少 Linux 上没有 lsof，安卓也不让看别的进程的端口
st_running_port() {
    local pid port
    [ -f "$RUN_INFO" ] || return 1
    read -r pid port < "$RUN_INFO" || return 1
    [ -n "$pid" ] && [ -n "$port" ] || return 1
    case "$(proc_cmdline "$pid")" in
        *server.js*) printf '%s' "$port" ;;
        *) return 1 ;;
    esac
}

# 连得上就是有程序在听。bash 自带，不依赖 lsof
port_busy() { (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null; }

open_url() {
    case "$PLATFORM" in
        mac) open "$1" ;;
        *) xdg-open "$1" >/dev/null 2>&1 & ;;
    esac
}

# 打开文件夹或文件。打不开也没关系，路径已经显示在屏幕上了；手机上就不打开了
show_path() {
    case "$PLATFORM" in
        mac) open "$@" 2>/dev/null ;;
        linux) case "$1" in
                   -R) xdg-open "$(dirname "$2")" >/dev/null 2>&1 & ;;
                   -e) xdg-open "$2" >/dev/null 2>&1 & ;;
                   *) xdg-open "$1" >/dev/null 2>&1 & ;;
               esac ;;
    esac
}

free_port() {
    local p pref
    pref="$(state_get PORT)"
    if [ -n "$pref" ] && ! port_busy "$pref"; then printf '%s' "$pref"; return 0; fi
    for p in $(seq "$PORT_FIRST" "$PORT_LAST"); do
        port_busy "$p" || { printf '%s' "$p"; return 0; }
    done
    return 1
}

cmd_start() {
    printf '\033]0;%s\007' "$(t "酒馆 SillyTavern（用的时候别关这个窗口）" "SillyTavern (keep this window open)")"
    is_installed || die "酒馆还没装好，请重新运行安装命令。" "SillyTavern is not installed yet."

    local port
    if port="$(st_running_port)"; then
        ok "酒馆已经在运行，已在浏览器里打开。这个窗口可以关掉。" \
            "SillyTavern is already running; opened it in your browser."
        [ "${EST_NO_BROWSER:-}" = 1 ] || open_url "http://127.0.0.1:$port/"
        exit 0
    fi
    port="$(free_port)" || die "端口 ${PORT_FIRST}～$PORT_LAST 都被占用了，重启电脑后再试。" \
        "Ports $PORT_FIRST-$PORT_LAST are all busy. Restart your device and try again."
    [ "$port" != "$PORT_FIRST" ] && warn "$PORT_FIRST 端口被别的程序占了，这次用 $port" \
        "Port $PORT_FIRST is busy, using $port"
    quiet_logs

    local extra=""
    detect_proxy
    if [ -n "$PROXY_URL" ]; then
        # 让酒馆连 OpenAI、Claude、Gemini 这些接口时也走代理
        extra="--requestProxyEnabled=true --requestProxyUrl=$PROXY_URL"
    fi
    [ "${EST_NO_BROWSER:-}" = 1 ] && extra="$extra --browserLaunchEnabled=false"
    [ "$HAS_CLT" = 1 ] || export PATH="$NOGIT_DIR:$PATH"
    export PATH="$NODE_DIR/bin:$PATH"

    local keep_hint stop_hint
    case "$PLATFORM" in
        mac) keep_hint="$(t "用的时候【不要关掉】这个窗口" "Keep this window open while you use it")"
             stop_hint="$(t "用完直接关掉这个窗口（问你时点「终止」）" "Close this window when you are done")" ;;
        linux) keep_hint="$(t "用的时候【不要关掉】这个窗口" "Keep this window open while you use it")"
               stop_hint="$(t "用完按 Ctrl+C，或者直接关掉这个窗口" "Press Ctrl+C or close this window when you are done")" ;;
        termux) keep_hint="$(t "用的时候别把 Termux 从后台划掉，通知栏的 Termux 通知也别关" "Do not swipe Termux away while you use it")"
                stop_hint="$(t "用完回到 Termux，按屏幕下方的 CTRL，再按 C" "Back in Termux, tap CTRL then C when you are done")"
                termux-wake-lock 2>/dev/null ;;
    esac

    clear 2>/dev/null
    cat <<EOF

  ================================================
$(t "      酒馆 SillyTavern $(st_version) 正在启动……" "      Starting SillyTavern $(st_version)...")

$(t "   · 启动好后浏览器会自动打开" "   · Your browser will open by itself")
   · $keep_hint
   · $stop_hint
$(t "   · 浏览器没打开的话，手动访问 http://127.0.0.1:$port" "   · If the browser does not open: http://127.0.0.1:$port")
EOF
    [ -n "$PROXY_URL" ] && printf '%s\n' "$(t "   · 已自动使用代理 $(safe_url "$PROXY_URL")" "   · Using proxy $(safe_url "$PROXY_URL")")"
    cat <<EOF
  ================================================
$(t "   （下面滚动的英文是运行记录，不用管）" "   (The log below is for troubleshooting.)")

EOF

    mkdir -p "$LOG_DIR"
    ls -1t "$LOG_DIR"/st-*.log 2>/dev/null | tail -n +6 | while IFS= read -r f; do rm -f "$f"; done
    local log
    log="$LOG_DIR/st-$(date +%Y%m%d-%H%M%S).log"

    cd "$APP_DIR" || die "找不到酒馆程序文件夹。" "SillyTavern folder missing."
    # 用 sh 先记下自己的进程号再 exec 成 node：st_running_port 靠它认出这一份酒馆
    # shellcheck disable=SC2016,SC2086
    NODE_ENV=production sh -c 'echo "$$ $1" > "$2"; shift 2; exec "$@"' sh "$port" "$RUN_INFO" \
        "$NODE" server.js --configPath "$CONFIG" --dataRoot "$DATA_DIR" --port "$port" $extra 2>&1 | tee -a "$log"
    local code="${PIPESTATUS[0]}"
    rm -f "$RUN_INFO"
    [ "$PLATFORM" = termux ] && termux-wake-unlock 2>/dev/null

    echo ""
    if [ "$code" -ne 0 ] && [ "$code" -ne 130 ] && [ "$code" -ne 143 ]; then
        err "酒馆意外退出了（错误码 ${code}）。" "SillyTavern exited unexpectedly (code $code)."
        info "运行记录：$log" "Log: $log"
        info "可以打开「酒馆工具箱」选「诊断」生成报告。" "Run diagnose from the toolbox for a report."
    else
        ok "酒馆已关闭。" "SillyTavern stopped."
    fi
    pause
    exit "$code"
}

# ------------------------------------------------------------- 备份 ---

# do_backup [auto]：把 data 和 config.yaml 打包到 backups/，自动备份只留最近 5 份
do_backup() {
    [ -d "$DATA_DIR" ] || return 1
    mkdir -p "$BACKUP_DIR"
    local kind="${1:-manual}" f
    f="$BACKUP_DIR/$kind-$(date +%Y%m%d-%H%M%S).tar.gz"
    # 缓存类的文件夹不备份，能自己重新生成
    tar -czf "$f" -C "$EST_HOME" --exclude 'data/_cache' --exclude 'data/_webpack' --exclude 'data/_uploads' \
        data config.yaml 2>/dev/null || { rm -f "$f"; return 1; }
    ls -1t "$BACKUP_DIR"/auto-*.tar.gz 2>/dev/null | tail -n +6 | while IFS= read -r old; do rm -f "$old"; done
    printf '%s' "$f"
}

cmd_backup() {
    step "备份聊天记录和设置" "Backing up your data"
    local f
    f="$(do_backup manual)" || die "备份失败。" "Backup failed."
    ok "备份好了：${f}（$(du -h "$f" | awk '{print $1}')）" "Backup saved: $f"
    warn "备份里有你的聊天记录和 API 密钥，只拷给自己，别发给别人。" \
        "This backup contains your chats and API keys. Keep it to yourself."
    show_path -R "$f"
    # 手机的文件管理器看不到 Termux 里面，要拷到「下载」才拿得出来
    if [ "$PLATFORM" = termux ]; then
        if [ -d "$HOME/storage/downloads" ]; then
            cp "$f" "$HOME/storage/downloads/" && ok "手机的「下载」文件夹里也放了一份" "Also copied to your phone's Downloads folder"
        else
            info "想把备份拿到 Termux 外面：先运行 termux-setup-storage 并允许，再备份一次，就会放进手机的「下载」文件夹。" \
                "To get backups out of Termux, run termux-setup-storage, allow it, and back up again."
        fi
    fi
}

# 解开备份用的 zip（Windows 版做的备份是 zip）
unzip_to() {
    if [ "$PLATFORM" = mac ]; then
        ditto -x -k "$1" "$2" 2>/dev/null
    elif command -v unzip >/dev/null 2>&1; then
        unzip -q "$1" -d "$2" 2>/dev/null
    elif command -v python3 >/dev/null 2>&1; then
        python3 -m zipfile -e "$1" "$2" 2>/dev/null
    else
        return 1
    fi
}

cmd_restore() {
    st_running_port >/dev/null && die "请先关掉酒馆再恢复。" "Close SillyTavern first."
    local list n i=1 choice f tmp d p ext cands=""
    # 自己的 backups 里全部都算；桌面和下载文件夹（隔空投送、微信存的文件常在这里）只认备份的文件名，
    # 用户文件夹是卸载时桌面放不了备份的退路。
    # Windows 版做的 .zip 也认，换电脑时拷过来就能恢复
    for ext in tar.gz zip; do
        cands="$cands
$BACKUP_DIR/*.$ext"
        for d in "$EST_DESKTOP" "$HOME/Downloads" "$HOME"; do
            for p in 酒馆数据备份 SillyTavern-backup manual auto final; do
                cands="$cands
$d/$p-*.$ext"
            done
        done
    done
    # shellcheck disable=SC2086
    list="$(IFS=$'\n'; ls -1t $cands 2>/dev/null | awk '!seen[$0]++')"
    [ -n "$list" ] || { info "还没有备份。" "No backups yet."; return 0; }
    n="$(printf '%s\n' "$list" | wc -l | tr -d ' ')"
    step "选一个备份恢复（越靠上越新）" "Pick a backup to restore (newest first)"
    printf '%s\n' "$list" | while IFS= read -r f; do
        printf '   %s) %s  %s(%s)%s\n' "$i" "$(basename "$f")" "$C_D" "$(du -h "$f" | awk '{print $1}')" "$C_0"
        i=$((i + 1))
    done
    has_input || return 0
    printf '  %s ' "$(t "输入编号，直接回车取消：" "Enter a number, or press Enter to cancel:")"
    read_reply
    choice="$REPLY_TEXT"
    case "$choice" in ''|*[!0-9]*) return 0 ;; esac
    [ "$choice" -ge 1 ] && [ "$choice" -le "$n" ] || return 0
    f="$(printf '%s\n' "$list" | sed -n "${choice}p")"
    tmp="$(mktemp -d)"
    case "$f" in
        *.zip) unzip_to "$f" "$tmp" ;;
        *)     tar -xzf "$f" -C "$tmp" data 2>/dev/null ;;
    esac
    [ -d "$tmp/data" ] || { rm -rf "$tmp"; die "这个备份文件打不开。" "Cannot read this backup."; }
    # 恢复前 import_data 会先把现在的数据再备份一份，恢复错了还能回来
    import_data "$tmp/data" "$(basename "$f")"
    rm -rf "$tmp"
}

# ------------------------------------------------------------- 更新 ---

# a 比 b 新就成功。只往新版本走：jsDelivr 发版后几个小时内还可能给旧文件
version_gt() {
    awk -v a="$1" -v b="$2" 'BEGIN {
        split(a, x, "."); split(b, y, ".")
        for (i = 1; i <= 3; i++) { if (x[i] + 0 > y[i] + 0) exit 0; if (x[i] + 0 < y[i] + 0) exit 1 }
        exit 1
    }'
}

self_update() {
    local tmp new_ver
    tmp="$(mktemp -d)"
    # shellcheck disable=SC2046
    if fetch_quiet "$tmp/easy-st.sh" $(gh_urls "$EST_REPO" "$EST_BRANCH" mac/easy-st.sh); then
        new_ver="$(sed -n 's/^EST_VERSION="\(.*\)"$/\1/p' "$tmp/easy-st.sh" | head -n 1)"
        # 先检查语法，下坏了或者被网页替换了都不会覆盖
        if [ -n "$new_ver" ] && version_gt "$new_ver" "$EST_VERSION" && "$BASH_BIN" -n "$tmp/easy-st.sh" 2>/dev/null; then
            # 用 mv 换成新文件，不能直接覆盖：bash 是边读边跑的，脚本被改写后会读到错位的内容
            chmod +x "$tmp/easy-st.sh" && mv "$tmp/easy-st.sh" "$SELF"
            ok "工具箱已更新到 $new_ver" "Toolbox updated to $new_ver"
        fi
    fi
    rm -rf "$tmp"
}

cmd_update() {
    is_installed || die "酒馆还没装好，请重新运行安装命令。" "SillyTavern is not installed yet."
    if st_running_port >/dev/null; then
        die "酒馆正在运行。请先关掉酒馆的黑色窗口，再来更新。" "SillyTavern is running. Close it first."
    fi
    detect_system
    choose_sources
    self_update
    step "更新前先自动备份" "Backing up before updating"
    local f
    if f="$(do_backup auto)"; then ok "$f"; else warn "备份失败，继续更新（聊天记录不会被更新动到）" "Backup failed; continuing"; fi
    install_node
    install_st
    write_config
    seed_tokenizers
    make_shortcuts
    state_set SETUP "done"
    ok "更新完成" "Update finished"
}

cmd_rollback() {
    [ -d "$APP_DIR.prev" ] || die "没有可以退回的旧版本。" "No previous version to roll back to."
    st_running_port >/dev/null && die "请先关掉酒馆再退回。" "Close SillyTavern first."
    local cur prev
    cur="$(st_version)"
    prev="$(sed -n 's/^ *"version": *"\([^"]*\)".*/\1/p' "$APP_DIR.prev/package.json" | head -n 1)"
    ask "从 $cur 退回到 ${prev}？" "Roll back from $cur to $prev?" y || return 0
    mv "$APP_DIR" "$APP_DIR.rollback"
    mv "$APP_DIR.prev" "$APP_DIR"
    mv "$APP_DIR.rollback" "$APP_DIR.prev"
    ok "已退回到 $prev" "Rolled back to $prev"
}

# ------------------------------------------------------------- 诊断 ---

# 打印第一个真的写得进去的文件夹。macOS 上点过「不允许」的桌面，看起来存在，写的时候才失败
writable_dir() {
    local d
    for d in "$@"; do
        [ -d "$d" ] || continue
        if { : > "$d/.est-write-test"; } 2>/dev/null; then
            rm -f "$d/.est-write-test"
            printf '%s' "$d"
            return 0
        fi
    done
    return 1
}

cmd_doctor() {
    detect_system
    local report dir
    dir="$(writable_dir "$EST_DESKTOP" "$EST_HOME" "$HOME")" || die "找不到能写报告的文件夹。" "No writable folder for the report."
    report="$dir/$(t "酒馆诊断报告" "SillyTavern-diagnostics")-$(date +%Y%m%d-%H%M%S).txt"
    step "正在检查……" "Checking..."
    {
        echo "Easy SillyTavern $EST_VERSION diagnostics  $(date '+%Y-%m-%d %H:%M:%S')"
        echo "$SYS_DESC  platform=$PLATFORM  arch=$ARCH  rosetta=$ROSETTA  clt=$HAS_CLT  free=${FREE_MB}MB  lang=$EST_LANG"
        echo "home=${EST_HOME/#$HOME/~}  installed=$(is_installed && echo yes || echo no)"
        echo "node=$([ -x "$NODE" ] && "$NODE" -v || echo none)  want_major=$NODE_MAJOR"
        echo "sillytavern=$(st_version)  prev=$([ -d "$APP_DIR.prev" ] && echo yes || echo no)"
        echo "state: $(tr '\n' ' ' < "$STATE" 2>/dev/null | sed "s#$HOME#~#g")"
        detect_proxy
        echo "proxy=$(safe_url "${PROXY_URL:-none}") src=${PROXY_SRC:-} dead=$(safe_url "${PROXY_DEAD:-}")"
        echo "running_port=$(st_running_port || echo none)"
        local p
        for p in 8000 8001 8002; do
            echo "port $p: $(lsof -nP -iTCP:$p -sTCP:LISTEN 2>/dev/null | awk 'NR==2 {print $1" pid="$2}')"
        done
        echo "--- network (http_code seconds)"
        apply_proxy
        local u
        for u in https://registry.npmjs.org/sillytavern/latest https://registry.npmmirror.com/sillytavern/latest \
                 https://nodejs.org/dist/index.json https://cdn.npmmirror.com/binaries/node/index.json \
                 https://raw.githubusercontent.com/SillyTavern/SillyTavern/release/package.json \
                 https://fastly.jsdelivr.net/gh/SillyTavern/SillyTavern@release/package.json \
                 https://api.openai.com https://api.anthropic.com https://generativelanguage.googleapis.com \
                 https://api.deepseek.com; do
            echo "$u $(curl -s -o /dev/null -r 0-0 --connect-timeout 5 --max-time 8 -w '%{http_code} %{time_total}' "$u" 2>/dev/null)"
        done
        echo "--- config (non-default keys)"
        if [ -f "$CONFIG" ] && [ -f "$APP_DIR/default/config.yaml" ]; then
            diff "$APP_DIR/default/config.yaml" "$CONFIG" | grep '^>' | grep -viE 'pass|token|secret|key' | head -n 30
        fi
        echo "--- last log"
        local last
        last="$(ls -1t "$LOG_DIR"/st-*.log 2>/dev/null | head -n 1)"
        [ -n "$last" ] && tail -n 80 "$last" | sed "s#$HOME#~#g"
    } > "$report" 2>&1
    ok "报告在：$report" "Report saved: $report"
    info "报告里没有你的 API 密钥和聊天内容，可以放心发给别人。" \
        "The report contains no API keys or chats."
    show_path -e "$report"
}

# ------------------------------------------------------------- 卸载 ---

cmd_uninstall() {
    [ -f "$MARKER" ] || die "$EST_HOME 不是 Easy SillyTavern 的安装目录，不敢删。" \
        "$EST_HOME does not look like an Easy SillyTavern install; refusing to delete it."
    st_running_port >/dev/null && die "请先关掉酒馆再卸载。" "Close SillyTavern first."
    step "卸载酒馆" "Uninstall"
    local keep=""
    if [ -d "$DATA_DIR/default-user" ] && ask "先把聊天记录和角色卡备份到桌面吗？（强烈建议）" \
            "Save your chats and characters to the Desktop first? (recommended)" y; then
        keep="$(do_backup final)" || die "备份失败，没有卸载。" "Backup failed; nothing was removed."
        # 备份绝不能留在马上要删的文件夹里。桌面放不了（比如点过「不允许」）就放用户文件夹
        local dir dest
        dir="$(writable_dir "$EST_DESKTOP" "$HOME")" || die "备份没地方放（还在 ${keep}），没有卸载。" \
            "Nowhere to put the backup (still at $keep); nothing was removed."
        dest="$dir/$(t "酒馆数据备份" "SillyTavern-backup")-$(date +%Y%m%d-%H%M%S).tar.gz"
        mv "$keep" "$dest" || die "备份挪不出来（还在 ${keep}），没有卸载。" \
            "Could not move the backup (still at $keep); nothing was removed."
        keep="$dest"
        ok "备份在：$keep" "Backup: $keep"
    fi
    ask "确定删除 $EST_HOME 吗？" "Delete $EST_HOME?" n || { info "已取消" "Cancelled"; return 0; }
    local f
    # SHORTCUTS 是用 | 隔开的一串路径
    state_get SHORTCUTS | tr '|' '\n' | while IFS= read -r f; do
        [ -n "$f" ] && rm -f "$f"
    done
    cd "$HOME" || true
    rm -rf "$EST_HOME"
    ok "已卸载。" "Uninstalled."
    exit 0
}

# ------------------------------------------------------------- 菜单 ---

cmd_menu() {
    printf '\033]0;%s\007' "$(t "酒馆工具箱" "SillyTavern Toolbox")"
    while true; do
        clear 2>/dev/null
        cat <<EOF

  ==============  $(t "酒馆工具箱" "SillyTavern Toolbox")  ==============
  $(t "酒馆版本" "Version"): $(st_version)    $(t "工具箱" "Toolbox"): $EST_VERSION

   1) $(t "启动酒馆" "Start SillyTavern")
   2) $(t "检查更新" "Check for updates")
   3) $(t "备份聊天记录和设置" "Back up data")
   4) $(t "打开数据文件夹（角色卡、聊天记录在这里）" "Open the data folder")
   5) $(t "从别的酒馆导入聊天记录" "Import data from another SillyTavern")
   6) $(t "从备份恢复" "Restore from a backup")
   7) $(t "诊断（出问题时用，生成报告）" "Diagnose (creates a report)")
   8) $(t "退回上一个版本" "Roll back to the previous version")
   9) $(t "卸载" "Uninstall")
   0) $(t "退出" "Quit")

EOF
        printf '  %s ' "$(t "输入数字后按回车：" "Choose:")"
        local c
        read -r c || exit 0
        case "$c" in
            1) cmd_start ;;
            2) cmd_update; pause ;;
            3) cmd_backup; pause ;;
            4) if [ "$PLATFORM" = termux ]; then
                   info "$DATA_DIR/default-user"
                   pause
               elif [ -d "$DATA_DIR/default-user" ]; then
                   show_path "$DATA_DIR/default-user"
               else
                   show_path "$DATA_DIR"
               fi ;;
            5) offer_import menu; pause ;;
            6) cmd_restore; pause ;;
            7) cmd_doctor; pause ;;
            8) cmd_rollback; pause ;;
            9) cmd_uninstall; pause ;;
            0|q|Q) exit 0 ;;
        esac
    done
}

# ------------------------------------------------------------- 安装 ---

cmd_install() {
    printf '\033]0;%s\007' "$(t "安装酒馆 SillyTavern" "Installing SillyTavern")"
    cat <<EOF

  ================================================
$(t "      酒馆 SillyTavern 一键安装" "      SillyTavern one-click installer")
$(t "      不需要管理员密码，全程大约 2～5 分钟" "      No admin password needed, about 2-5 minutes")
  ================================================
EOF
    detect_system
    step "检查$MACHINE" "Checking $MACHINE"
    info "$SYS_DESC"
    if [ -n "$UNSUPPORTED" ]; then
        # 再运行一次也没用，别走 die 的那套提示
        err "$UNSUPPORTED"
        pause
        exit 1
    fi
    [ "$NODE_MAJOR" = 20 ] && warn "系统比较旧，只能用 Node.js 20（已停止维护），建议升级 macOS。" \
        "Old macOS: falling back to Node.js 20, which is end-of-life."
    [ "$FREE_MB" -ge 1500 ] || die "硬盘空间不够，至少需要 1.5 GB，现在只剩 ${FREE_MB} MB。" \
        "Not enough disk space: need 1.5 GB, have ${FREE_MB} MB."
    if is_installed; then
        st_running_port >/dev/null && die "酒馆正在运行。请先关掉酒馆的窗口，再来安装。" "SillyTavern is running. Close it first."
        ok "之前已经装过（$(st_version)），这次会检查更新并修复" "Already installed ($(st_version)); updating and repairing"
    fi
    ok "可以安装" "Ready to install"

    choose_sources
    install_self
    install_node
    install_st
    write_config
    seed_tokenizers
    [ -d "$DATA_DIR/default-user" ] || offer_import
    make_shortcuts
    state_set SETUP "done"

    local done_msg
    case "$PLATFORM" in
        mac) done_msg="$(t "  安装完成！以后双击桌面上的「酒馆 SillyTavern」就能用。" \
                 "  Done! Double-click \"SillyTavern\" on your Desktop to start it.")" ;;
        linux) done_msg="$(t "  安装完成！以后在应用菜单里打开「酒馆 SillyTavern」就能用。" \
                   "  Done! Open \"SillyTavern\" from your applications menu to start it.")" ;;
        termux) done_msg="$(t "  安装完成！以后打开 Termux，输入 tavern 按回车就能用。" \
                    "  Done! Open Termux and run tavern to start it.")" ;;
    esac
    printf '\n  %s================================================%s\n' "$C_G" "$C_0"
    printf '  %s%s%s\n' "$C_G" "$done_msg" "$C_0"
    printf '  %s================================================%s\n' "$C_G" "$C_0"
    if [ "${EST_NO_START:-}" = 1 ]; then return 0; fi
    if ask "现在就启动酒馆吗？" "Start SillyTavern now?" y; then
        cmd_start
    fi
}

usage() {
    cat <<EOF
Easy SillyTavern $EST_VERSION ($PLATFORM)
usage: easy-st.sh [install|start|menu|update|backup|restore|import|doctor|rollback|uninstall]
EOF
}

main() {
    local cmd="${1:-}"
    if [ -z "$cmd" ]; then
        # 装到一半被打断的，再运行一次要接着装，不能直接进工具箱（桌面图标还没放呢）
        if setup_done && [ -f "$SELF" ]; then cmd=menu; else cmd=install; fi
    fi
    case "$cmd" in
        install)   cmd_install ;;
        start)     detect_system; cmd_start ;;
        menu)      detect_system; cmd_menu ;;
        update)    cmd_update; pause ;;
        backup)    cmd_backup ;;
        import)    detect_system; offer_import menu ;;
        restore)   cmd_restore ;;
        doctor)    cmd_doctor ;;
        rollback)  cmd_rollback ;;
        uninstall) cmd_uninstall ;;
        version|-v|--version) echo "$EST_VERSION" ;;
        *) usage; exit 2 ;;
    esac
}

main "$@"
exit $?
