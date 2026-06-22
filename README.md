<p align="center">
  <img src="RightMenuMini/Resources/RightMenuMini-source.png" width="112" alt="RightMenuMini icon">
</p>

<h1 align="center">RightMenuMini</h1>

<p align="center">
  A minimal macOS Finder context-menu extension.
</p>

<p align="center">
  <a href="README.md">English</a>
  |
  <a href="README.zh-CN.md">中文</a>
</p>

<p align="center">
  <a href="LICENSE">MIT License</a>
  ·
  <a href="https://github.com/Goonwb">Author</a>
</p>

## Features

RightMenuMini keeps the Finder context menu focused on three everyday actions:

- **New Text**: create an empty `Untitled.txt` in the current Finder folder. Duplicate names are numbered automatically.
- **Open Terminal**: open Terminal at the current Finder location.
- **Copy Path**: copy selected item paths, or copy the current folder path when nothing is selected.

The app supports:

- A master switch for the Finder context menu.
- Individual switches for each action.
- Optional grouped submenu display.
- Manual update checking from GitHub Releases.
- Language selection: System, Simplified Chinese, or English.
- Appearance selection: System, Light, or Dark.

## Screenshots

<p align="center">
  <img src="docs/images/overview-en.png" alt="RightMenuMini overview" width="820">
</p>

<p align="center">
  <img src="docs/images/settings-en.png" alt="RightMenuMini settings" width="820">
</p>

## Requirements

- macOS 13.0 or later
- Xcode 15 or later for building from source

## Install From Source

```zsh
chmod +x Scripts/install-local.sh
./Scripts/install-local.sh
```

The script builds the Release app, copies it to `/Applications`, registers the Finder extension, and restarts Finder.

## Build Manually

```zsh
xcodebuild \
  -project RightMenuMini.xcodeproj \
  -scheme RightMenuMini \
  -configuration Release \
  -derivedDataPath build \
  build

open build/Build/Products/Release/RightMenuMini.app
```

## First-Time Permission

RightMenuMini uses Apple's Finder Sync extension mechanism. macOS requires users to enable Finder extensions manually:

1. Open RightMenuMini.
2. Click **Authorize**.
3. Enable **RightMenuMini** or **右键菜单助手** in the **File Provider** extension sheet.

Before permission is granted, all switches are shown as off and disabled. After permission is enabled, the app restores the default or saved settings.

## Updating

macOS cannot replace an app bundle while it is running. Before replacing an older copy in `/Applications`, quit RightMenuMini from the menu bar.

Release archives in `dist/` are intentionally ignored by Git. Use GitHub Releases for public distribution.

## Notes

- Current version: `0.1.1`.
- The distributed app is not notarized yet. Users may need to allow it manually in macOS security settings.

## License

RightMenuMini is released under the [MIT License](LICENSE).
