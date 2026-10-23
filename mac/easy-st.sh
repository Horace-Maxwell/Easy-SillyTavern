#!/bin/bash
#
# Easy SillyTavern · macOS
# 酒馆 SillyTavern 一键安装 / 启动 / 更新 / 备份 / 诊断
#
#   安装：bash -c "$(curl -fsSL <本文件的地址>)"
#   之后：双击桌面上的「酒馆 SillyTavern」启动，「酒馆工具箱」做更新、备份、诊断。
#
# 不需要 Homebrew、Xcode、管理员密码。所有东西都装在 ~/SillyTavern-Easy 里：
#   runtime/node   私有的 Node.js（按 Mac 芯片和系统版本自动选）
#   app/           SillyTavern 程序本体（更新时整个替换）
#   data/          聊天记录、角色卡、设置（更新时不动）
#   config.yaml    酒馆配置
#
# 只用 macOS 自带的 bash 3.2、curl、tar、shasum，别加 bash 4 以后才有的写法。

set -u

EST_VERSION="0.1.0"
EST_REPO="${EST_REPO:-Horace-Maxwell/Easy-SillyTavern}"
EST_BRANCH="${EST_BRANCH:-main}"

EST_HOME="${EST_HOME:-$HOME/SillyTavern-Easy}"
EST_DESKTOP="${EST_DESKTOP:-$HOME/Desktop}"
NODE_DIR="$EST_HOME/runtime/node"
NOGIT_DIR="$EST_HOME/runtime/nogit"
APP_DIR="$EST_HOME/app"
DATA_DIR="$EST_HOME/data"
CONFIG="$EST_HOME/config.yaml"
LOG_DIR="$EST_HOME/logs"
BACKUP_DIR="$EST_HOME/backups"
STATE="$EST_HOME/state.env"
SELF="$EST_HOME/easy-st.sh"
MARKER="$EST_HOME/.easy-sillytavern"
NODE="$NODE_DIR/bin/node"
NPM="$NODE_DIR/bin/npm"

PORT_FIRST=8000
PORT_LAST=8019
# 酒馆运行时会按需下载的分词器，提前放进缓存，免得国内网络第一次用时卡住
TOKENIZERS="deepseek qwen2 nemo command-r command-a"

export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

# ---------------------------------------------------------------- 输出 ---

case "${EST_LANG:-$(defaults read -g AppleLocale 2>/dev/null || echo "${LANG:-}")}" in
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

die() {
    err "$@"
    printf '\n  %s\n' "$(t "可以双击桌面上的「酒馆工具箱」选「诊断」，把生成的报告发给帮你的人。" \
        "Run \"diagnose\" from the toolbox and send the report to whoever helps you.")"
    pause
    exit 1
}

# ask "问题" "question" 默认值(y/n)：返回 0 表示「是」。非交互时用默认值。
ask() {
    local def="${3:-y}" hint reply
    if [ "${EST_YES:-}" = 1 ]; then [ "$def" = y ]; return; fi
    if [ ! -t 0 ]; then [ "$def" = y ]; return; fi
    if [ "$def" = y ]; then hint="[Y/n]"; else hint="[y/N]"; fi
    printf '  %s %s ' "$(t "$1" "$2")" "$hint"
    read -r reply || reply=""
    case "$reply" in
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

is_installed() { [ -x "$NODE" ] && [ -f "$APP_DIR/server.js" ]; }
st_version() { sed -n 's/^ *"version": *"\([^"]*\)".*/\1/p' "$APP_DIR/package.json" 2>/dev/null | head -n 1; }

# -------------------------------------------------------- 系统检测 ---

detect_system() {
    MAC_VER="$(sw_vers -productVersion 2>/dev/null)"
    MAC_MAJOR="${MAC_VER%%.*}"
    MAC_MINOR="$(printf '%s' "$MAC_VER" | cut -d. -f2)"
    [ -n "$MAC_MINOR" ] || MAC_MINOR=0
    # 用 hw.optional.arm64 而不是 uname -m：终端开了 Rosetta 时 uname 会说 x86_64
    if [ "$(sysctl -n hw.optional.arm64 2>/dev/null)" = 1 ]; then ARCH=arm64; else ARCH=x64; fi
    ROSETTA="$(sysctl -n sysctl.proc_translated 2>/dev/null || echo 0)"
    if xcode-select -p >/dev/null 2>&1; then HAS_CLT=1; else HAS_CLT=0; fi
    FREE_MB=$(( $(df -k "$HOME" | awk 'NR==2 {print $4}') / 1024 ))

    # Node.js 各大版本支持的最低 macOS；酒馆要求 Node 20 以上
    if [ "$MAC_MAJOR" -ge 14 ] || { [ "$MAC_MAJOR" -eq 13 ] && [ "$MAC_MINOR" -ge 5 ]; }; then
        NODE_MAJOR=24
    elif [ "$MAC_MAJOR" -ge 11 ]; then
        NODE_MAJOR=22
    elif [ "$MAC_MAJOR" -eq 10 ] && [ "$MAC_MINOR" -ge 15 ]; then
        NODE_MAJOR=20
    else
        NODE_MAJOR=""
    fi
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
        ok "发现代理 ${PROXY_URL}，下载会走代理" "Using proxy $PROXY_URL"
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

install_node() {
    step "准备 Node.js（酒馆的运行环境）" "Setting up Node.js"
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

    file="node-$ver-darwin-$ARCH.tar.gz"
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
    have="$(shasum -a 256 "$tmp/$file" | awk '{print $1}')"
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

# 打印 "版本 下载地址 完整性校验值"
st_latest_meta() {
    local reg json
    for reg in "$NPM_REGISTRY" "$NPM_FALLBACK"; do
        json="$(curl -fsSL --connect-timeout 8 --max-time 30 "$reg/sillytavern/latest" 2>/dev/null)" || continue
        printf '%s' "$json" | "$NODE" -e '
            let s = ""; process.stdin.on("data", c => s += c).on("end", () => {
                const j = JSON.parse(s);
                console.log(j.version, j.dist.tarball, j.dist.integrity);
            });' 2>/dev/null && return 0
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

write_config() {
    mkdir -p "$DATA_DIR" "$LOG_DIR" "$BACKUP_DIR"
    if [ ! -f "$CONFIG" ]; then
        cp "$APP_DIR/default/config.yaml" "$CONFIG"
        # 没装苹果开发者工具的 Mac 上一调用系统 git 就弹窗，统一用酒馆内置的 git 功能装扩展
        sed -i '' 's/^  backend: auto$/  backend: builtin/' "$CONFIG"
        ok "已生成配置文件" "Config created"
    fi

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
        find "$HOME/Desktop" "$HOME/Downloads" "$HOME/Documents" -maxdepth 6 -type d \
            -path '*/SillyTavern/data/default-user' 2>/dev/null | sed 's#/default-user$##'
    } | grep -v "^$EST_HOME/" | awk '!seen[$0]++'
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
    # ditto 合并复制，保留原文件不动
    ditto "$src" "$DATA_DIR" || return 1
    ok "已导入：${2:-$src}" "Imported: ${2:-$src}"
}

offer_import() {
    local list n src i=1 choice
    list="$(find_old_data)"
    [ -n "$list" ] || { [ "${1:-}" = menu ] && info "没有找到别的酒馆数据。" "No other SillyTavern data found."; return 0; }
    n="$(printf '%s\n' "$list" | wc -l | tr -d ' ')"
    step "发现这台 Mac 上已经有酒馆的聊天记录" "Found existing SillyTavern data on this Mac"
    printf '%s\n' "$list" | while IFS= read -r src; do
        printf '   %s) %s  %s(%s)%s\n' "$i" "${src/#$HOME/~}" "$C_D" "$(describe_data "$src")" "$C_0"
        i=$((i + 1))
    done
    info "导入是「复制」，原来的文件不会被改动。" "Importing copies the files; the originals stay untouched."
    if [ "${EST_YES:-}" = 1 ] || [ ! -t 0 ]; then
        info "（非交互模式，跳过导入）" "(non-interactive, skipping import)"
        return 0
    fi
    printf '  %s ' "$(t "要导入哪一个？输入编号，直接回车跳过：" "Import which one? Enter a number, or press Enter to skip:")"
    read -r choice || choice=""
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
    if [ -f "$SELF.new" ] && grep -q '^EST_VERSION=' "$SELF.new" && /bin/bash -n "$SELF.new" 2>/dev/null; then
        mv "$SELF.new" "$SELF"
    else
        rm -f "$SELF.new"
    fi
    chmod +x "$SELF" 2>/dev/null
}

make_shortcuts() {
    [ "${EST_NO_SHORTCUTS:-}" = 1 ] && return 0
    [ -d "$EST_DESKTOP" ] || return 0
    local start="$EST_DESKTOP/$(t "酒馆 SillyTavern" "SillyTavern").command"
    local tools="$EST_DESKTOP/$(t "酒馆工具箱" "SillyTavern Toolbox").command"
    printf '#!/bin/bash\n# Easy SillyTavern：启动酒馆\nexec /bin/bash "%s" start\n' "$SELF" > "$start"
    printf '#!/bin/bash\n# Easy SillyTavern：更新、备份、诊断、卸载\nexec /bin/bash "%s" menu\n' "$SELF" > "$tools"
    chmod +x "$start" "$tools"
    state_set SHORTCUTS "$start|$tools"
    ok "桌面上放好了「$(basename "$start" .command)」和「$(basename "$tools" .command)」" \
        "Shortcuts created on the Desktop"
}

# ------------------------------------------------------------- 启动 ---

# 打印正在运行的「这一份」酒馆的端口。别的酒馆（比如用户自己另装的一份）占着端口不算：
# 看监听端口的进程是不是在我们的 app 文件夹里运行
st_running_port() {
    local p pid want
    want="$(cd "$APP_DIR" 2>/dev/null && pwd -P)" || return 1
    for p in $(seq "$PORT_FIRST" "$PORT_LAST"); do
        pid="$(lsof -nP -tiTCP:"$p" -sTCP:LISTEN 2>/dev/null | head -n 1)"
        [ -n "$pid" ] || continue
        if [ "$(lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p')" = "$want" ]; then
            printf '%s' "$p"
            return 0
        fi
    done
    return 1
}

port_busy() { lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1; }

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
        [ "${EST_NO_BROWSER:-}" = 1 ] || open "http://127.0.0.1:$port/"
        exit 0
    fi
    port="$(free_port)" || die "端口 ${PORT_FIRST}～$PORT_LAST 都被占用了，重启电脑后再试。" \
        "Ports $PORT_FIRST-$PORT_LAST are all busy. Restart your Mac and try again."
    [ "$port" != "$PORT_FIRST" ] && warn "$PORT_FIRST 端口被别的程序占了，这次用 $port" \
        "Port $PORT_FIRST is busy, using $port"

    local extra=""
    detect_proxy
    if [ -n "$PROXY_URL" ]; then
        # 让酒馆连 OpenAI、Claude、Gemini 这些接口时也走代理
        extra="--requestProxyEnabled=true --requestProxyUrl=$PROXY_URL"
    fi
    [ "${EST_NO_BROWSER:-}" = 1 ] && extra="$extra --browserLaunchEnabled=false"
    [ "$HAS_CLT" = 1 ] || export PATH="$NOGIT_DIR:$PATH"
    export PATH="$NODE_DIR/bin:$PATH"

    clear 2>/dev/null
    cat <<EOF

  ================================================
$(t "      酒馆 SillyTavern $(st_version) 正在启动……" "      Starting SillyTavern $(st_version)...")

$(t "   · 启动好后浏览器会自动打开" "   · Your browser will open by itself")
$(t "   · 用的时候【不要关掉】这个窗口" "   · Keep this window open while you use it")
$(t "   · 用完直接关掉这个窗口（问你时点「终止」）" "   · Close this window when you are done")
$(t "   · 浏览器没打开的话，手动访问 http://127.0.0.1:$port" "   · If the browser does not open: http://127.0.0.1:$port")
EOF
    [ -n "$PROXY_URL" ] && printf '%s\n' "$(t "   · 已自动使用代理 $PROXY_URL" "   · Using proxy $PROXY_URL")"
    cat <<EOF
  ================================================
$(t "   （下面滚动的英文是运行记录，不用管）" "   (The log below is for troubleshooting.)")

EOF

    mkdir -p "$LOG_DIR"
    ls -1t "$LOG_DIR"/st-*.log 2>/dev/null | tail -n +6 | while IFS= read -r f; do rm -f "$f"; done
    local log
    log="$LOG_DIR/st-$(date +%Y%m%d-%H%M%S).log"

    cd "$APP_DIR" || die "找不到酒馆程序文件夹。" "SillyTavern folder missing."
    # shellcheck disable=SC2086
    NODE_ENV=production "$NODE" server.js --configPath "$CONFIG" --dataRoot "$DATA_DIR" --port "$port" $extra 2>&1 | tee -a "$log"
    local code="${PIPESTATUS[0]}"

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
    open -R "$f" 2>/dev/null
}

cmd_restore() {
    st_running_port >/dev/null && die "请先关掉酒馆再恢复。" "Close SillyTavern first."
    local list n i=1 choice f tmp
    list="$(ls -1t "$BACKUP_DIR"/*.tar.gz "$EST_DESKTOP"/酒馆数据备份-*.tar.gz \
        "$EST_DESKTOP"/SillyTavern-backup-*.tar.gz 2>/dev/null)"
    [ -n "$list" ] || { info "还没有备份。" "No backups yet."; return 0; }
    n="$(printf '%s\n' "$list" | wc -l | tr -d ' ')"
    step "选一个备份恢复（越靠上越新）" "Pick a backup to restore (newest first)"
    printf '%s\n' "$list" | while IFS= read -r f; do
        printf '   %s) %s  %s(%s)%s\n' "$i" "$(basename "$f")" "$C_D" "$(du -h "$f" | awk '{print $1}')" "$C_0"
        i=$((i + 1))
    done
    [ -t 0 ] || return 0
    printf '  %s ' "$(t "输入编号，直接回车取消：" "Enter a number, or press Enter to cancel:")"
    read -r choice || choice=""
    case "$choice" in ''|*[!0-9]*) return 0 ;; esac
    [ "$choice" -ge 1 ] && [ "$choice" -le "$n" ] || return 0
    f="$(printf '%s\n' "$list" | sed -n "${choice}p")"
    tmp="$(mktemp -d)"
    tar -xzf "$f" -C "$tmp" data 2>/dev/null && [ -d "$tmp/data" ] || { rm -rf "$tmp"; die "这个备份文件打不开。" "Cannot read this backup."; }
    # 恢复前 import_data 会先把现在的数据再备份一份，恢复错了还能回来
    import_data "$tmp/data" "$(basename "$f")"
    rm -rf "$tmp"
}

# ------------------------------------------------------------- 更新 ---

self_update() {
    local tmp new_ver
    tmp="$(mktemp -d)"
    # shellcheck disable=SC2046
    if fetch_quiet "$tmp/easy-st.sh" $(gh_urls "$EST_REPO" "$EST_BRANCH" mac/easy-st.sh); then
        new_ver="$(sed -n 's/^EST_VERSION="\(.*\)"$/\1/p' "$tmp/easy-st.sh" | head -n 1)"
        # 先检查语法，下坏了或者被网页替换了都不会覆盖
        if [ -n "$new_ver" ] && [ "$new_ver" != "$EST_VERSION" ] && /bin/bash -n "$tmp/easy-st.sh" 2>/dev/null; then
            cp "$tmp/easy-st.sh" "$SELF" && chmod +x "$SELF"
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

cmd_doctor() {
    detect_system
    local report
    report="$EST_DESKTOP/$(t "酒馆诊断报告" "SillyTavern-diagnostics")-$(date +%Y%m%d-%H%M%S).txt"
    [ -d "$EST_DESKTOP" ] || report="$EST_HOME/diagnostics.txt"
    step "正在检查……" "Checking..."
    {
        echo "Easy SillyTavern $EST_VERSION diagnostics  $(date '+%Y-%m-%d %H:%M:%S')"
        echo "macOS $MAC_VER  arch=$ARCH  rosetta=$ROSETTA  clt=$HAS_CLT  free=${FREE_MB}MB  lang=$EST_LANG"
        echo "home=${EST_HOME/#$HOME/~}  installed=$(is_installed && echo yes || echo no)"
        echo "node=$([ -x "$NODE" ] && "$NODE" -v || echo none)  want_major=$NODE_MAJOR"
        echo "sillytavern=$(st_version)  prev=$([ -d "$APP_DIR.prev" ] && echo yes || echo no)"
        echo "state: $(tr '\n' ' ' < "$STATE" 2>/dev/null | sed "s#$HOME#~#g")"
        detect_proxy
        echo "proxy=${PROXY_URL:-none} src=${PROXY_SRC:-} dead=${PROXY_DEAD:-}"
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
    open -e "$report" 2>/dev/null
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
        local dest
        dest="$EST_DESKTOP/$(t "酒馆数据备份" "SillyTavern-backup")-$(date +%Y%m%d-%H%M%S).tar.gz"
        mv "$keep" "$dest" && keep="$dest"
        ok "备份在：$keep" "Backup: $keep"
    fi
    ask "确定删除 $EST_HOME 吗？" "Delete $EST_HOME?" n || { info "已取消" "Cancelled"; return 0; }
    local s
    s="$(state_get SHORTCUTS)"
    rm -f "${s%%|*}" "${s##*|}"
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
            4) open "$DATA_DIR/default-user" 2>/dev/null || open "$DATA_DIR"; ;;
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
    step "检查这台 Mac" "Checking this Mac"
    info "macOS $MAC_VER · $( [ "$ARCH" = arm64 ] && t "Apple 芯片" "Apple silicon" || t "Intel 芯片" "Intel" )"
    [ -n "$NODE_MAJOR" ] || die "这台 Mac 的系统太旧了（${MAC_VER}），酒馆最低需要 macOS 10.15。" \
        "macOS $MAC_VER is too old; SillyTavern needs macOS 10.15 or newer."
    [ "$NODE_MAJOR" = 20 ] && warn "系统比较旧，只能用 Node.js 20（已停止维护），建议升级 macOS。" \
        "Old macOS: falling back to Node.js 20, which is end-of-life."
    [ "$FREE_MB" -ge 1500 ] || die "硬盘空间不够，至少需要 1.5 GB，现在只剩 ${FREE_MB} MB。" \
        "Not enough disk space: need 1.5 GB, have ${FREE_MB} MB."
    if is_installed; then
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

    printf '\n  %s================================================%s\n' "$C_G" "$C_0"
    printf '  %s%s%s\n' "$C_G" "$(t "  安装完成！以后双击桌面上的「酒馆 SillyTavern」就能用。" \
        "  Done! Double-click \"SillyTavern\" on your Desktop to start it.")" "$C_0"
    printf '  %s================================================%s\n' "$C_G" "$C_0"
    if [ "${EST_NO_START:-}" = 1 ]; then return 0; fi
    if ask "现在就启动酒馆吗？" "Start SillyTavern now?" y; then
        cmd_start
    fi
}

usage() {
    cat <<EOF
Easy SillyTavern $EST_VERSION (macOS)
usage: easy-st.sh [install|start|menu|update|backup|restore|import|doctor|rollback|uninstall]
EOF
}

main() {
    local cmd="${1:-}"
    if [ -z "$cmd" ]; then
        if is_installed && [ -f "$SELF" ]; then cmd=menu; else cmd=install; fi
    fi
    case "$cmd" in
        install)   cmd_install ;;
        start)     detect_system; cmd_start ;;
        menu)      detect_system; cmd_menu ;;
        update)    cmd_update; pause ;;
        backup)    cmd_backup ;;
        import)    offer_import menu ;;
        restore)   cmd_restore ;;
        doctor)    cmd_doctor ;;
        rollback)  cmd_rollback ;;
        uninstall) cmd_uninstall ;;
        version|-v|--version) echo "$EST_VERSION" ;;
        *) usage; exit 2 ;;
    esac
}

main "$@"
