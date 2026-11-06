#!/bin/bash
# 把一份真实安装从头走到尾：安装、启动、隐私、备份恢复、接着装、更新、卸载。
# Mac、Linux、Termux 都跑这一个。全部装在临时文件夹里，不碰这台电脑上已有的安装。
#
#   bash tests/smoke.sh
#
# 文件夹名字故意带中文和空格，能测出路径没加引号的问题。

set -u

script="$(cd "$(dirname "$0")/.." && pwd)/mac/easy-st.sh"
work="$(mktemp -d)"
export HOME="$work/home"
export EST_HOME="$HOME/酒馆 测试" EST_DESKTOP="$HOME/Desktop" EST_LANG=zh
export EST_YES=1 EST_NO_START=1 EST_NO_BROWSER=1
mkdir -p "$EST_DESKTOP"

fails=0
pass() { printf 'ok    %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; fails=$((fails + 1)); }
# check 说明 命令…：命令成功就算过
check() {
    local what="$1"
    shift
    if "$@" >/dev/null 2>&1; then pass "$what"; else fail "$what"; fi
}
# refuse 说明 命令…：命令失败才算过
refuse() {
    local what="$1"
    shift
    if "$@" >/dev/null 2>&1; then fail "$what"; else pass "$what"; fi
}
run() { bash "$script" "$@" < /dev/null; }
cleanup() {
    [ -f "$EST_HOME/run.info" ] && kill "$(cut -d' ' -f1 "$EST_HOME/run.info")" 2>/dev/null
    [ -n "${mock:-}" ] && kill "$mock" 2>/dev/null
    rm -rf "$work"
}
trap cleanup EXIT

# ---------------------------------------------------------------- 安装 ---

if ! run install > "$work/install.log" 2>&1; then
    tail -n 40 "$work/install.log"
    fail "安装"
    exit 1
fi
pass "安装"
check "酒馆程序在" test -f "$EST_HOME/app/server.js"
check "酒馆日志级别不是 DEBUG" grep -q '^  minLogLevel: 1' "$EST_HOME/config.yaml"

case "$(uname -s)" in
    Darwin) check "桌面图标" test -x "$EST_DESKTOP/酒馆 SillyTavern.command" ;;
    *)
        if [ "$(uname -o)" = Android ]; then
            check "tavern 命令" test -x "$PREFIX/bin/tavern"
        else
            check "应用菜单" test -x "$HOME/.local/share/applications/easy-sillytavern.desktop"
            check "tavern 命令" test -x "$HOME/.local/bin/tavern"
        fi ;;
esac

printf '0\n' | bash "$script" > "$work/menu.log" 2>&1
check "装好后再运行进工具箱" grep -q '酒馆工具箱' "$work/menu.log"

node_bin="$EST_HOME/runtime/node/bin/node"
[ -x "$node_bin" ] || node_bin="$(command -v node)"

# ---------------------------------------------------------------- 启动 ---

# 模拟 v0.1.0 留下的状态：DEBUG 级别，旧记录里有聊天内容
sed 's/^  minLogLevel: 1/  minLogLevel: 0/' "$EST_HOME/config.yaml" > "$work/config" && cp "$work/config" "$EST_HOME/config.yaml"
mkdir -p "$EST_HOME/logs"
echo "OLD_PRIVATE_CHAT" > "$EST_HOME/logs/st-20200101-000000.log"

bash "$script" start > "$work/start.log" 2>&1 < /dev/null &
port=""
for _ in $(seq 1 120); do
    if [ -f "$EST_HOME/run.info" ]; then
        port="$(cut -d' ' -f2 "$EST_HOME/run.info")"
        [ "$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$port/" 2>/dev/null)" = 200 ] && break
    fi
    sleep 1
done
if [ "$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$port/" 2>/dev/null)" = 200 ]; then
    pass "启动后网页打得开（端口 ${port}）"
else
    tail -n 30 "$work/start.log"
    fail "启动后网页打得开"
    exit 1
fi
run start > "$work/again.log" 2>&1
check "重复启动不会开第二份" grep -q '已经在运行' "$work/again.log"
check "旧版 DEBUG 配置被改掉" grep -q '^  minLogLevel: 1' "$EST_HOME/config.yaml"
refuse "旧记录里的聊天内容被清掉" grep -rq OLD_PRIVATE_CHAT "$EST_HOME/logs"

# ---------------------------------------------------------------- 隐私 ---

# 发一句真的聊天给一个假的 AI 接口，确认它进不了运行记录和诊断报告
"$node_bin" -e '
    require("http").createServer((q, r) => {
        q.resume();
        q.on("end", () => {
            r.setHeader("content-type", "application/json");
            r.end(JSON.stringify({ id: "x", object: "chat.completion", model: "m",
                choices: [{ index: 0, finish_reason: "stop", message: { role: "assistant", content: "MOCK_REPLY" } }] }));
        });
    }).listen(9911, "127.0.0.1");' &
mock=$!
sleep 1
token="$(curl -s -c "$work/jar" "http://127.0.0.1:$port/csrf-token" | sed 's/.*"token":"\([^"]*\)".*/\1/')"
curl -s -b "$work/jar" -H "X-CSRF-Token: $token" -H 'content-type: application/json' \
    -d '{"chat_completion_source":"custom","custom_url":"http://127.0.0.1:9911/v1","model":"m","stream":false,"messages":[{"role":"user","content":"PRIVATE_CHAT_MARKER"}]}' \
    "http://127.0.0.1:$port/api/backends/chat-completions/generate" > "$work/reply.json"
check "聊天请求真的发出去了" grep -q MOCK_REPLY "$work/reply.json"
sleep 1
refuse "聊天内容不进运行记录" grep -rq PRIVATE_CHAT_MARKER "$EST_HOME/logs"

kill "$(cut -d' ' -f1 "$EST_HOME/run.info")"
for _ in $(seq 1 20); do [ -f "$EST_HOME/run.info" ] || break; sleep 1; done
kill "$mock" 2>/dev/null
mock=""
check "关掉后记录被清掉" test ! -f "$EST_HOME/run.info"

run doctor > "$work/doctor.log" 2>&1
report="$(ls "$EST_DESKTOP"/酒馆诊断报告-*.txt 2>/dev/null | head -n 1)"
check "诊断报告生成了" test -s "$report"
refuse "诊断报告里没有聊天内容" grep -q PRIVATE_CHAT_MARKER "$report"

# ------------------------------------------------------------ 备份恢复 ---

chat="$EST_HOME/data/default-user/chats/alice/a.jsonl"
mkdir -p "$(dirname "$chat")"
echo '{"mes":"keep me"}' > "$chat"
run backup > "$work/backup.log" 2>&1
check "备份提醒里面有密钥" grep -q 'API 密钥' "$work/backup.log"
rm -f "$chat"
EST_ANSWERS=1 run restore > "$work/restore.log" 2>&1
check "从备份恢复" test -f "$chat"

# Windows 版做的备份是 zip，换电脑时要能恢复
if command -v python3 >/dev/null 2>&1; then
    mkdir -p "$work/zip/data/default-user/chats/bob"
    echo '{"mes":"from windows"}' > "$work/zip/data/default-user/chats/bob/b.jsonl"
    (cd "$work/zip" && python3 -m zipfile -c "$EST_DESKTOP/SillyTavern-backup-20300101-000000.zip" data)
    sleep 1
    touch "$EST_DESKTOP/SillyTavern-backup-20300101-000000.zip"
    EST_ANSWERS=1 run restore > "$work/restore-zip.log" 2>&1
    check "恢复 Windows 版的 zip 备份" test -f "$EST_HOME/data/default-user/chats/bob/b.jsonl"
fi

# ----------------------------------------------------- 接着装、更新 ---

# 模拟装到一半被打断：程序都在，但最后一步没走完。这时再运行要接着装，不能进工具箱
grep -v -e '^SETUP=' -e '^SHORTCUTS=' "$EST_HOME/state.env" > "$work/state" && cp "$work/state" "$EST_HOME/state.env"
bash "$script" > "$work/resume.log" 2>&1 < /dev/null
check "被打断后再运行会接着装" grep -q '安装完成' "$work/resume.log"
check "走完后记下了" grep -q '^SETUP=done' "$EST_HOME/state.env"

run update > "$work/update.log" 2>&1
check "检查更新" grep -q '更新完成' "$work/update.log"

# ---------------------------------------------------------------- 卸载 ---

# 桌面放不了备份时，备份绝不能跟着安装文件夹一起被删
EST_DESKTOP="$work/没有这个文件夹" EST_ANSWERS="y y" run uninstall > "$work/uninstall.log" 2>&1
refuse "安装文件夹删掉了" test -d "$EST_HOME"
kept="$(ls "$HOME"/酒馆数据备份-*.tar.gz 2>/dev/null | head -n 1)"
check "桌面不能用时备份留在用户文件夹" test -s "$kept"
if [ -n "$kept" ]; then
    tar -tzf "$kept" > "$work/kept.txt" 2>/dev/null
    check "备份里有聊天记录" grep -q 'alice/a.jsonl' "$work/kept.txt"
fi
case "$(uname -s)" in
    Darwin) ;;
    *)
        if [ "$(uname -o)" = Android ]; then
            refuse "tavern 命令删掉了" test -e "$PREFIX/bin/tavern"
        else
            refuse "应用菜单项删掉了" test -e "$HOME/.local/share/applications/easy-sillytavern.desktop"
        fi ;;
esac

echo ""
if [ "$fails" -eq 0 ]; then
    echo "全部通过"
else
    echo "$fails 项没通过"
    exit 1
fi
