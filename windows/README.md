# Windows 版

用户怎么装见[总 README](../README.md#windows-安装3-步)。这里是给改脚本的人看的。

| 文件 | 干什么用 |
| --- | --- |
| `easy-st.ps1` | 安装器 + 工具箱本体，安装时复制到 `%LOCALAPPDATA%\SillyTavern-Easy\easy-st.ps1` |
| `双击安装酒馆.bat` | 下载 ZIP 的人双击它；只是 `powershell -ExecutionPolicy Bypass -File easy-st.ps1 install` |

行为和 Mac 版 [`mac/easy-st.sh`](../mac/easy-st.sh) 一致，约定都在 [docs/DESIGN.md](../docs/DESIGN.md)，最后一节是 Windows 专门要注意的地方。

## 改脚本前必看

- `easy-st.ps1` 必须存成**带 BOM 的 UTF-8**。没有 BOM 的话，Windows PowerShell 5.1 会按系统 ANSI 编码读，中文全乱，脚本直接报错。CI 会检查
- `双击安装酒馆.bat` 是 **CRLF、不带 BOM**；`chcp 65001` 之前只能有英文
- 要兼容 Windows PowerShell 5.1：别用 `??`、`?:`、`&&`、`||` 这些 PowerShell 7 才有的写法
- 字符串里变量后面紧跟中文时写成 `${var}`，不然中文会被当成变量名的一部分
- 给 node 等外部程序传参数时别带双引号（5.1 不会转义），JS 代码里用单引号

## 本地测试

不想动自己电脑上的安装，就装到别处：

```powershell
$env:EST_HOME = "$env:TEMP\est 测试"; $env:EST_YES = '1'; $env:EST_NO_START = '1'; $env:EST_NO_SHORTCUTS = '1'
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\easy-st.ps1 install
```

路径里故意带空格和中文，能测出中文用户名的问题。
