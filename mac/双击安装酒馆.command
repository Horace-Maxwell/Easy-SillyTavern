#!/bin/bash
# Easy SillyTavern：下载了整个压缩包的话，双击这个文件安装。
# 第一次双击被 Mac 拦下时：系统设置 → 隐私与安全性 → 往下拉 → 点「仍要打开」。
cd "$(dirname "$0")" || exit 1
exec /bin/bash ./easy-st.sh install
