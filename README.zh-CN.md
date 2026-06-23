<p align="center">
  <img src="RightMenuMini/Resources/RightMenuMini-source.png" width="112" alt="右键菜单助手图标">
</p>

<h1 align="center">右键菜单助手</h1>

<p align="center">
  一个简洁的 macOS Finder 右键菜单扩展。
</p>

<p align="center">
  <a href="README.md">English</a>
  |
  <a href="README.zh-CN.md">中文</a>
</p>

<p align="center">
  <a href="LICENSE">MIT License</a>
  ·
  <a href="https://github.com/Goonwb">作者</a>
</p>

## 功能

右键菜单助手专注给 Finder 右键菜单补上三项高频小动作：

- **新建 Text**：在当前 Finder 文件夹创建空白 `Untitled.txt`，重名时自动追加编号。
- **进入终端**：在当前 Finder 位置打开 Terminal。
- **拷贝路径**：复制所选项目路径；未选择文件时复制当前文件夹路径。

App 内支持：

- 总开关：启用或停用整个 Finder 右键菜单。
- 子功能开关：单独启用或停用三项功能。
- 折叠显示：将三项功能收进一个子菜单。
- 版本检查：从 GitHub Releases 手动检查最新版本。
- 语言：简体中文或 English。
- 外观：跟随系统、浅色或深色模式。

## 界面预览

<p align="center">
  <img src="docs/images/general-zh-CN.png" alt="右键菜单助手通用界面" width="820">
</p>

<p align="center">
  <img src="docs/images/actions-zh-CN.png" alt="右键菜单助手快捷功能界面" width="820">
</p>

## 系统要求

- macOS 13.0 或更高版本
- 如需从源码编译，需要 Xcode 15 或更高版本

## 从源码安装

```zsh
chmod +x Scripts/install-local.sh
./Scripts/install-local.sh
```

脚本会编译 Release 版本，将 App 复制到 `/Applications`，注册 Finder 扩展并重启 Finder。

## 手动编译

```zsh
xcodebuild \
  -project RightMenuMini.xcodeproj \
  -scheme RightMenuMini \
  -configuration Release \
  -derivedDataPath build \
  build

open build/Build/Products/Release/RightMenuMini.app
```

## 首次授权

右键菜单助手使用 Apple 的 Finder Sync 扩展机制。首次使用前需要手动启用扩展：

1. 打开右键菜单助手。
2. 点击 **初次授权**。
3. 在 **文件提供程序** 扩展弹窗中启用 **右键菜单助手**。

未授权时，App 内所有功能开关会显示为关闭并禁用；授权后会恢复默认或已保存的设置。

## 说明

- 当前版本：`0.1.2`。
- 当前分发版本尚未公证。其他用户安装时，可能需要在 macOS 安全设置中手动允许打开。

## 许可证

右键菜单助手基于 [MIT License](LICENSE) 开源。
