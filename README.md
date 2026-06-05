# 右键菜单助手

一个极简 macOS Finder 右键扩展，默认启用三项功能：

- 新建 Text：在当前文件夹创建 `Untitled.txt`，重名时自动追加编号。
- 进入终端：在当前文件夹打开 Terminal。
- 拷贝路径：复制所选文件路径；没有选中文件时复制当前文件夹路径。

App 内可以单独开关每一项，也可以关闭总开关；开启“折叠显示”后，Finder 右键菜单会显示为“右键菜单助手 > 三项功能”。

作者主页：[Goonwb](https://github.com/Goonwb)

## 本地安装

```zsh
chmod +x Scripts/install-local.sh
./Scripts/install-local.sh
```

如果右键菜单没有立刻出现：

1. 打开 App，点击“初次授予权限”。
2. 在“文件提供程序”弹窗里启用“右键菜单助手”。
3. 如菜单没有立刻刷新，可执行 `killall Finder`。

## 手动编译

```zsh
xcodebuild -project RightMenuMini.xcodeproj -scheme RightMenuMini -configuration Release -derivedDataPath build build
open build/Build/Products/Release/RightMenuMini.app
```

Finder Sync 扩展是 macOS 系统机制，首次使用需要手动启用一次。

## 更新提示

如果从 zip 更新旧版本，先从菜单栏里选择“退出右键菜单助手”，再把新版拖进“应用程序”。macOS 不能替换正在运行的 `.app` 包；如需给朋友分发更省心的版本，可以使用安装脚本先退出旧进程再复制新版。
