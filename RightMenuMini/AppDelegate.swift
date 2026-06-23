import AppKit
import Carbon

private enum RightMenuMiniPreferences {
    static let suiteName = "com.codex.RightMenuMini.shared"
    static let isMenuEnabled = "isMenuEnabled"
    static let isNewTextEnabled = "isNewTextEnabled"
    static let isTerminalEnabled = "isTerminalEnabled"
    static let isCopyPathEnabled = "isCopyPathEnabled"
    static let isGroupedMenuEnabled = "isGroupedMenuEnabled"
    static let languageMode = "languageMode"
    static let appearanceMode = "appearanceMode"

    static let systemValue = "system"
    static let chineseValue = "zh-Hans"
    static let englishValue = "en"
    static let lightValue = "light"
    static let darkValue = "dark"

    static let defaultValues: [String: Bool] = [
        isMenuEnabled: true,
        isNewTextEnabled: true,
        isTerminalEnabled: true,
        isCopyPathEnabled: true,
        isGroupedMenuEnabled: false
    ]
    static let stringDefaultValues: [String: String] = [
        languageMode: systemValue,
        appearanceMode: systemValue
    ]
    static var registeredDefaults: [String: Any] {
        var values: [String: Any] = defaultValues.mapValues { $0 as Any }
        stringDefaultValues.forEach { values[$0.key] = $0.value }
        return values
    }
    static let extensionContainerIdentifier = "com.codex.RightMenuMini.FinderExtension"

    static func store() -> UserDefaults {
        let store = UserDefaults(suiteName: suiteName) ?? .standard
        store.register(defaults: registeredDefaults)
        return store
    }

    static func bool(_ key: String, in store: UserDefaults) -> Bool {
        if store.object(forKey: key) == nil {
            return defaultValues[key] ?? false
        }
        return store.bool(forKey: key)
    }

    static func string(_ key: String, in store: UserDefaults) -> String {
        let fallback = stringDefaultValues[key] ?? systemValue
        guard let value = store.string(forKey: key), !value.isEmpty else {
            return fallback
        }
        return value
    }

    static func values(in store: UserDefaults) -> [String: Any] {
        var values: [String: Any] = defaultValues.mapValues { $0 as Any }
        defaultValues.keys.forEach { key in
            if store.object(forKey: key) != nil {
                values[key] = store.bool(forKey: key)
            }
        }
        stringDefaultValues.keys.forEach { key in
            values[key] = string(key, in: store)
        }
        return values
    }

    static func mirrorValues(from store: UserDefaults) {
        let values = values(in: store)
        guard let data = try? PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0) else {
            return
        }

        for url in preferenceFileURLs() {
            do {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: url, options: .atomic)
            } catch {
                NSLog("RightMenuMini preferences mirror failed: \(error.localizedDescription)")
            }
        }
    }

    private static func preferenceFileURLs() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let fileName = "\(suiteName).plist"
        return [
            home
                .appendingPathComponent("Library/Preferences", isDirectory: true)
                .appendingPathComponent(fileName),
            home
                .appendingPathComponent("Library/Containers", isDirectory: true)
                .appendingPathComponent(extensionContainerIdentifier, isDirectory: true)
                .appendingPathComponent("Data/Library/Preferences", isDirectory: true)
                .appendingPathComponent(fileName)
        ]
    }
}

private enum AppText {
    static var languageMode: String {
        RightMenuMiniPreferences.string(RightMenuMiniPreferences.languageMode, in: RightMenuMiniPreferences.store())
    }

    static var isEnglish: Bool {
        switch languageMode {
        case RightMenuMiniPreferences.englishValue:
            return true
        case RightMenuMiniPreferences.chineseValue:
            return false
        default:
            let preferredLanguage = Locale.preferredLanguages.first?.lowercased() ?? ""
            return !preferredLanguage.hasPrefix("zh")
        }
    }

    static func localized(_ chinese: String, _ english: String) -> String {
        isEnglish ? english : chinese
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum SidebarTab {
        case general
        case actions

        var identifier: String {
            switch self {
            case .general:
                return "general"
            case .actions:
                return "actions"
            }
        }

        static func from(identifier: String) -> SidebarTab? {
            switch identifier {
            case "general":
                return .general
            case "actions":
                return .actions
            default:
                return nil
            }
        }
    }

    private let extensionBundleIdentifier = "com.codex.RightMenuMini.FinderExtension"
    private let sidebarWidth: CGFloat = 220
    private let contentWidth: CGFloat = 540
    private let repositoryURL = URL(string: "https://github.com/Goonwb/RightMenuMini")!
    private let latestReleaseAPIURL = URL(string: "https://api.github.com/repos/Goonwb/RightMenuMini/releases/latest")!
    private var window: NSWindow?
    private var statusItem: NSStatusItem?
    private var statusMenuAuthorizationItem: NSMenuItem?
    private var receivedActionURL = false
    private let preferences = RightMenuMiniPreferences.store()
    private var currentTab: SidebarTab = .general
    private var contentContainer: NSView?
    private var sidebarButtons: [SidebarTab: NSButton] = [:]
    private var preferenceSwitches: [String: NSSwitch] = [:]
    private var preferenceRows: [String: NSView] = [:]
    private var statusDetailLabels: [String: NSTextField] = [:]
    private var preferenceIconViews: [String: NSImageView] = [:]
    private var preferenceIconTiles: [String: NSView] = [:]
    private var finderExtensionEnabled = false
    private var authorizationIconTile: NSView?
    private var authorizationIconView: NSImageView?
    private var authorizationTitleLabel: NSTextField?
    private var authorizationDetailLabel: NSTextField?
    private var authorizationButton: NSButton?
    private var updateStatusLabel: NSTextField?
    private var updateCheckButton: NSButton?
    private var latestReleasePageURL: URL?
    private var flatLayoutCard: LayoutOptionCard?
    private var groupedLayoutCard: LayoutOptionCard?
    private var sidebarBrandLabel: NSTextField?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        preferences.register(defaults: RightMenuMiniPreferences.registeredDefaults)
        RightMenuMiniPreferences.mirrorValues(from: preferences)
        applyAppearancePreference()
        configureStatusItem()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, !self.receivedActionURL else {
                return
            }
            self.showWindow()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        refreshAuthorizationStatus()
    }

    private func showWindow() {
        if window == nil {
            buildWindow()
        }

        window?.center()
        refreshPreferenceControls()
        refreshAuthorizationStatus()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildWindow() {
        applyAppearancePreference()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 821, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = AppText.localized("右键菜单助手", "RightMenuMini")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.center()

        let visualView = NSVisualEffectView()
        visualView.material = .windowBackground
        visualView.blendingMode = .behindWindow
        visualView.state = .active
        visualView.translatesAutoresizingMaskIntoConstraints = false

        window.contentView = visualView

        preferenceSwitches.removeAll()
        preferenceRows.removeAll()
        statusDetailLabels.removeAll()
        preferenceIconViews.removeAll()
        preferenceIconTiles.removeAll()
        sidebarButtons.removeAll()
        updateStatusLabel = nil
        updateCheckButton = nil

        let sidebar = sidebarView()
        let separator = NSView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.wantsLayer = true
        separator.layer?.backgroundColor = separatorLayerColor.cgColor

        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        visualView.addSubview(sidebar)
        visualView.addSubview(separator)
        visualView.addSubview(content)

        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: visualView.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: visualView.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: visualView.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: sidebarWidth),

            separator.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            separator.topAnchor.constraint(equalTo: visualView.topAnchor),
            separator.bottomAnchor.constraint(equalTo: visualView.bottomAnchor),
            separator.widthAnchor.constraint(equalToConstant: 1),

            content.leadingAnchor.constraint(equalTo: separator.trailingAnchor, constant: 30),
            content.trailingAnchor.constraint(equalTo: visualView.trailingAnchor, constant: -30),
            content.topAnchor.constraint(equalTo: visualView.topAnchor, constant: 30),
            content.bottomAnchor.constraint(equalTo: visualView.bottomAnchor, constant: -26)
        ])

        self.window = window
        self.contentContainer = content
        selectSidebarTab(.general)
        refreshAuthorizationStatus()
    }

    private func configureStatusItem() {
        let statusItem = self.statusItem ?? NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "contextualmenu.and.cursorarrow",
            accessibilityDescription: AppText.localized("右键菜单助手", "RightMenuMini")
        )
        statusItem.button?.image?.isTemplate = true

        let menu = NSMenu()
        menu.addItem(NSMenuItem(
            title: AppText.localized("打开右键菜单助手", "Open RightMenuMini"),
            action: #selector(showMainWindow),
            keyEquivalent: ""
        ))
        let authorizationItem = NSMenuItem(
            title: AppText.localized("初次授权", "First-Time Permission"),
            action: #selector(openExtensionSettings),
            keyEquivalent: ""
        )
        menu.addItem(authorizationItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(
            title: AppText.localized("退出右键菜单助手", "Quit RightMenuMini"),
            action: #selector(quitApp),
            keyEquivalent: "q"
        ))
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu

        self.statusMenuAuthorizationItem = authorizationItem
        self.statusItem = statusItem
        refreshAuthorizationStatus()
    }

    @objc private func showMainWindow() {
        showWindow()
    }

    @objc private func sidebarTabSelected(_ sender: NSButton) {
        guard
            let identifier = sender.identifier?.rawValue,
            let tab = SidebarTab.from(identifier: identifier)
        else {
            return
        }

        selectSidebarTab(tab)
    }

    private func selectSidebarTab(_ tab: SidebarTab) {
        currentTab = tab

        for (buttonTab, button) in sidebarButtons {
            let isSelected = buttonTab == tab
            button.layer?.backgroundColor = isSelected
                ? sidebarSelectionColor.cgColor
                : NSColor.clear.cgColor

            for subview in button.subviews {
                if let imageView = subview as? NSImageView {
                    imageView.contentTintColor = isSelected ? .controlAccentColor : .secondaryLabelColor
                } else if let label = subview as? NSTextField {
                    label.textColor = isSelected ? .controlAccentColor : .secondaryLabelColor
                    label.font = .systemFont(ofSize: 13, weight: isSelected ? .semibold : .medium)
                }
            }
        }

        guard let contentContainer else {
            return
        }

        contentContainer.subviews.forEach { $0.removeFromSuperview() }
        preferenceSwitches.removeAll()
        preferenceRows.removeAll()
        statusDetailLabels.removeAll()
        preferenceIconViews.removeAll()
        preferenceIconTiles.removeAll()
        authorizationIconTile = nil
        authorizationIconView = nil
        authorizationTitleLabel = nil
        authorizationDetailLabel = nil
        authorizationButton = nil
        updateStatusLabel = nil
        updateCheckButton = nil
        flatLayoutCard = nil
        groupedLayoutCard = nil

        let content: NSView
        switch tab {
        case .general:
            content = generalContentView()
        case .actions:
            content = actionsContentView()
        }

        content.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            content.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            content.bottomAnchor.constraint(lessThanOrEqualTo: contentContainer.bottomAnchor)
        ])

        refreshAuthorizationStatus()
    }

    private func sidebarView() -> NSView {
        let sidebar = NSVisualEffectView()
        sidebar.material = .sidebar
        sidebar.blendingMode = .behindWindow
        sidebar.state = .active
        sidebar.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView()
        icon.image = applicationIconImage()
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.wantsLayer = true
        icon.layer?.shadowColor = NSColor.black.cgColor
        icon.layer?.shadowOffset = CGSize(width: 0, height: -2.5)
        icon.layer?.shadowRadius = 6.0
        icon.layer?.shadowOpacity = 0.12

        let titleLabel = NSTextField(labelWithString: AppText.localized("右键菜单助手", "RightMenuMini"))
        titleLabel.font = .systemFont(ofSize: 17, weight: .bold)
        titleLabel.textColor = .labelColor
        titleLabel.alignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        self.sidebarBrandLabel = titleLabel

        let versionLabel = NSTextField(labelWithString: "v\(currentVersionString)")
        versionLabel.font = .systemFont(ofSize: 11.5)
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.alignment = .center
        versionLabel.translatesAutoresizingMaskIntoConstraints = false

        let brandStack = NSStackView(views: [titleLabel, versionLabel])
        brandStack.orientation = .vertical
        brandStack.alignment = .centerX
        brandStack.spacing = 4
        brandStack.translatesAutoresizingMaskIntoConstraints = false

        let generalButton = sidebarNavigationButton(symbol: "gearshape", title: sidebarTitle(for: .general), tab: .general)
        let actionsButton = sidebarNavigationButton(symbol: "contextualmenu.and.cursorarrow", title: sidebarTitle(for: .actions), tab: .actions)

        let navStack = NSStackView(views: [generalButton, actionsButton])
        navStack.orientation = .vertical
        navStack.alignment = .width
        navStack.spacing = 8
        navStack.translatesAutoresizingMaskIntoConstraints = false

        sidebar.addSubview(icon)
        sidebar.addSubview(brandStack)
        sidebar.addSubview(navStack)

        NSLayoutConstraint.activate([
            icon.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 60),
            icon.centerXAnchor.constraint(equalTo: sidebar.centerXAnchor),
            icon.widthAnchor.constraint(equalToConstant: 72),
            icon.heightAnchor.constraint(equalToConstant: 72),

            brandStack.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 14),
            brandStack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 18),
            brandStack.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -18),

            navStack.topAnchor.constraint(equalTo: brandStack.bottomAnchor, constant: 28),
            navStack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 18),
            navStack.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -18),
            generalButton.widthAnchor.constraint(equalTo: navStack.widthAnchor),
            actionsButton.widthAnchor.constraint(equalTo: navStack.widthAnchor)
        ])

        return sidebar
    }

    private func sidebarTitle(for tab: SidebarTab) -> String {
        switch tab {
        case .general:
            return AppText.localized("通用", "General")
        case .actions:
            return AppText.localized("快捷功能", "Actions")
        }
    }

    private func sidebarNavigationButton(symbol: String, title: String, tab: SidebarTab) -> NSButton {
        let button = NSButton(title: "", target: self, action: #selector(sidebarTabSelected(_:)))
        button.identifier = NSUserInterfaceItemIdentifier(tab.identifier)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 8
        button.layer?.cornerCurve = .continuous

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        icon.symbolConfiguration = .init(pointSize: 15, weight: .semibold)
        icon.contentTintColor = .secondaryLabelColor
        icon.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false

        button.addSubview(icon)
        button.addSubview(label)

        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(equalToConstant: 36),

            icon.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 14),
            icon.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 20),
            icon.heightAnchor.constraint(equalToConstant: 20),

            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            label.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: button.trailingAnchor, constant: -12)
        ])

        sidebarButtons[tab] = button
        return button
    }

    private func applicationIconImage() -> NSImage {
        if
            let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
            let image = NSImage(contentsOf: iconURL)
        {
            return image
        }

        return NSApp.applicationIconImage
    }

    private func generalContentView() -> NSView {
        let statusSection = sectionTitle(AppText.localized("服务与状态", "Service & Status"))

        let authRow = authorizationRow()
        let menuRow = statusToggleRow()
        let statusPanel = settingsPanel(rows: [authRow, menuRow])

        let preferencesSection = sectionTitle(AppText.localized("偏好", "Preferences"))
        let preferencesPanel = settingsPanel(rows: [
            settingsPopUpRow(
                symbol: "character.bubble",
                title: AppText.localized("语言", "Language"),
                detail: AppText.localized("选择 App 和 Finder 菜单显示语言", "Choose the app and Finder menu language"),
                key: RightMenuMiniPreferences.languageMode,
                items: [
                    (RightMenuMiniPreferences.systemValue, AppText.localized("跟随系统", "System")),
                    (RightMenuMiniPreferences.chineseValue, "简体中文"),
                    (RightMenuMiniPreferences.englishValue, "English")
                ],
                action: #selector(languageSelectionChanged(_:))
            ),
            settingsPopUpRow(
                symbol: "circle.lefthalf.filled",
                title: AppText.localized("外观", "Appearance"),
                detail: AppText.localized("选择浅色、深色或跟随系统", "Choose light, dark, or system appearance"),
                key: RightMenuMiniPreferences.appearanceMode,
                items: [
                    (RightMenuMiniPreferences.systemValue, AppText.localized("跟随系统", "System")),
                    (RightMenuMiniPreferences.lightValue, AppText.localized("浅色", "Light")),
                    (RightMenuMiniPreferences.darkValue, AppText.localized("深色", "Dark"))
                ],
                action: #selector(appearanceSelectionChanged(_:))
            )
        ])

        let versionRow = settingsVersionRow(
            symbol: "info.circle",
            title: AppText.localized("当前版本", "Current Version"),
            version: currentVersionString,
            detail: AppText.localized("可检查最新版本与发布日志", "Check latest version and release notes"),
            buttonTitle: AppText.localized("检查", "Check"),
            action: #selector(checkForUpdates)
        )
        updateStatusLabel = versionRow.detailLabel
        updateCheckButton = versionRow.button

        let githubRow = settingsButtonRow(
            symbol: "github",
            title: "GitHub",
            detail: "github.com/Goonwb/RightMenuMini",
            buttonTitle: AppText.localized("前往", "Visit"),
            action: #selector(openGitHubProfile)
        )

        let projectSection = sectionTitle(AppText.localized("关于", "About"))
        let projectPanel = settingsPanel(rows: [
            versionRow.row,
            githubRow.row
        ])

        let stack = NSStackView(views: [
            statusSection,
            statusPanel,
            preferencesSection,
            preferencesPanel,
            projectSection,
            projectPanel
        ])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 0
        stack.setCustomSpacing(10, after: statusSection)
        stack.setCustomSpacing(24, after: statusPanel)
        stack.setCustomSpacing(10, after: preferencesSection)
        stack.setCustomSpacing(24, after: preferencesPanel)
        stack.setCustomSpacing(10, after: projectSection)
        stack.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            stack.widthAnchor.constraint(equalToConstant: contentWidth)
        ])

        return stack
    }

    private func actionsContentView() -> NSView {
        let layoutSection = sectionTitle(AppText.localized("菜单布局", "Menu Layout"))

        let flatCard = LayoutOptionCard(
            symbol: "list.bullet",
            title: AppText.localized("平铺显示", "Flat Layout"),
            detail: AppText.localized("直接显示三项功能", "Show actions directly")
        )
        flatCard.target = self
        flatCard.action = #selector(flatLayoutSelected(_:))
        self.flatLayoutCard = flatCard

        let groupedCard = LayoutOptionCard(
            symbol: "rectangle.stack",
            title: AppText.localized("折叠显示", "Grouped Layout"),
            detail: AppText.localized("三项功能集合显示", "Show actions in a submenu")
        )
        groupedCard.target = self
        groupedCard.action = #selector(groupedLayoutSelected(_:))
        self.groupedLayoutCard = groupedCard

        let layoutStack = NSStackView(views: [flatCard, groupedCard])
        layoutStack.orientation = .horizontal
        layoutStack.distribution = .fillEqually
        layoutStack.spacing = 12
        layoutStack.translatesAutoresizingMaskIntoConstraints = false

        let featuresSection = sectionTitle(AppText.localized("快捷功能", "Quick Actions"))

        let rows = [
            preferenceRow(
                symbol: "doc.badge.plus",
                title: AppText.localized("新建 Text", "New Text"),
                detail: AppText.localized("在当前位置创建 Untitled.txt", "Create Untitled.txt here"),
                key: RightMenuMiniPreferences.isNewTextEnabled
            ),
            preferenceRow(
                symbol: "terminal",
                title: AppText.localized("进入终端", "Open Terminal"),
                detail: AppText.localized("从当前位置打开 Terminal", "Open Terminal at this location"),
                key: RightMenuMiniPreferences.isTerminalEnabled
            ),
            preferenceRow(
                symbol: "doc.on.doc",
                title: AppText.localized("拷贝路径", "Copy Path"),
                detail: AppText.localized("复制所选项目或当前文件夹路径", "Copy selected paths or current folder"),
                key: RightMenuMiniPreferences.isCopyPathEnabled
            )
        ]

        let featuresPanel = settingsPanel(rows: rows)

        let stack = NSStackView(views: [
            layoutSection,
            layoutStack,
            featuresSection,
            featuresPanel
        ])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 0
        stack.setCustomSpacing(10, after: layoutSection)
        stack.setCustomSpacing(24, after: layoutStack)
        stack.setCustomSpacing(10, after: featuresSection)
        stack.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            stack.widthAnchor.constraint(equalToConstant: contentWidth),
            layoutStack.widthAnchor.constraint(equalToConstant: contentWidth),
            layoutStack.heightAnchor.constraint(equalToConstant: 72)
        ])

        return stack
    }

    private func sectionTitle(_ title: String) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 14.5, weight: .bold)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(label)

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: contentWidth),
            container.heightAnchor.constraint(equalToConstant: 26),

            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 6),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        return container
    }

    private func settingsButtonRow(
        symbol: String,
        title: String,
        detail: String,
        buttonTitle: String,
        action: Selector
    ) -> (row: NSView, detailLabel: NSTextField, button: NSButton) {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let color = iconColor(forSymbol: symbol)
        let iconTile = NSView()
        iconTile.translatesAutoresizingMaskIntoConstraints = false
        iconTile.wantsLayer = true
        iconTile.layer?.cornerRadius = 11
        iconTile.layer?.cornerCurve = .continuous
        iconTile.layer?.backgroundColor = tintBackgroundColor(for: color).cgColor

        let icon = NSImageView()
        if symbol == "github" {
            if let image = NSImage(named: "github") {
                image.isTemplate = true
                icon.image = image
            } else {
                icon.image = NSImage(systemSymbolName: "globe", accessibilityDescription: title)
            }
        } else {
            icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        }
        icon.symbolConfiguration = .init(pointSize: 18, weight: .semibold)
        icon.contentTintColor = color
        icon.translatesAutoresizingMaskIntoConstraints = false
        iconTile.addSubview(icon)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13.5, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let detailLabel = NSTextField(labelWithString: detail)
        detailLabel.font = .systemFont(ofSize: 11.5)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingMiddle
        detailLabel.maximumNumberOfLines = 1
        detailLabel.translatesAutoresizingMaskIntoConstraints = false

        let button = NSButton(title: buttonTitle, target: self, action: action)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .rounded
        button.controlSize = .regular

        row.addSubview(iconTile)
        row.addSubview(titleLabel)
        row.addSubview(detailLabel)
        row.addSubview(button)

        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 64),
            iconTile.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 18),
            iconTile.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            iconTile.widthAnchor.constraint(equalToConstant: 38),
            iconTile.heightAnchor.constraint(equalToConstant: 38),
            icon.centerXAnchor.constraint(equalTo: iconTile.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconTile.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 22),
            icon.heightAnchor.constraint(equalToConstant: 22),
            titleLabel.leadingAnchor.constraint(equalTo: iconTile.trailingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: button.leadingAnchor, constant: -12),
            titleLabel.topAnchor.constraint(equalTo: row.topAnchor, constant: 13),
            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(lessThanOrEqualTo: button.leadingAnchor, constant: -12),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 5),
            button.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -18),
            button.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            button.heightAnchor.constraint(equalToConstant: 30),
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 72)
        ])

        return (row, detailLabel, button)
    }

    private func settingsVersionRow(
        symbol: String,
        title: String,
        version: String,
        detail: String,
        buttonTitle: String,
        action: Selector
    ) -> (row: NSView, detailLabel: NSTextField, button: NSButton) {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let color = iconColor(forSymbol: symbol)
        let iconTile = NSView()
        iconTile.translatesAutoresizingMaskIntoConstraints = false
        iconTile.wantsLayer = true
        iconTile.layer?.cornerRadius = 11
        iconTile.layer?.cornerCurve = .continuous
        iconTile.layer?.backgroundColor = tintBackgroundColor(for: color).cgColor

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        icon.symbolConfiguration = .init(pointSize: 18, weight: .semibold)
        icon.contentTintColor = color
        icon.translatesAutoresizingMaskIntoConstraints = false
        iconTile.addSubview(icon)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13.5, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        // Version badge
        let badge = NSView()
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 5
        badge.layer?.cornerCurve = .continuous
        badge.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(usesDarkAppearance ? 0.16 : 0.08).cgColor
        badge.layer?.borderWidth = 0.5
        badge.layer?.borderColor = NSColor.systemGreen.withAlphaComponent(usesDarkAppearance ? 0.3 : 0.15).cgColor

        let badgeLabel = NSTextField(labelWithString: version)
        badgeLabel.font = .systemFont(ofSize: 10.5, weight: .bold)
        badgeLabel.textColor = .systemGreen
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        badge.addSubview(badgeLabel)

        NSLayoutConstraint.activate([
            badgeLabel.leadingAnchor.constraint(equalTo: badge.leadingAnchor, constant: 6),
            badgeLabel.trailingAnchor.constraint(equalTo: badge.trailingAnchor, constant: -6),
            badgeLabel.topAnchor.constraint(equalTo: badge.topAnchor, constant: 1.5),
            badgeLabel.bottomAnchor.constraint(equalTo: badge.bottomAnchor, constant: -1.5)
        ])

        let detailLabel = NSTextField(labelWithString: detail)
        detailLabel.font = .systemFont(ofSize: 11.5)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingMiddle
        detailLabel.maximumNumberOfLines = 1
        detailLabel.translatesAutoresizingMaskIntoConstraints = false

        let button = NSButton(title: buttonTitle, target: self, action: action)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .rounded
        button.controlSize = .regular

        row.addSubview(iconTile)
        row.addSubview(titleLabel)
        row.addSubview(badge)
        row.addSubview(detailLabel)
        row.addSubview(button)

        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 64),

            iconTile.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 18),
            iconTile.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            iconTile.widthAnchor.constraint(equalToConstant: 38),
            iconTile.heightAnchor.constraint(equalToConstant: 38),

            icon.centerXAnchor.constraint(equalTo: iconTile.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconTile.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 22),
            icon.heightAnchor.constraint(equalToConstant: 22),

            titleLabel.leadingAnchor.constraint(equalTo: iconTile.trailingAnchor, constant: 16),
            titleLabel.topAnchor.constraint(equalTo: row.topAnchor, constant: 13),

            badge.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 8),
            badge.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            badge.trailingAnchor.constraint(lessThanOrEqualTo: button.leadingAnchor, constant: -12),

            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(lessThanOrEqualTo: button.leadingAnchor, constant: -12),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 5),

            button.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -18),
            button.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            button.heightAnchor.constraint(equalToConstant: 30),
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 72)
        ])

        return (row, detailLabel, button)
    }

    private func settingsLinkRow(
        symbol: String,
        title: String,
        detail: String,
        action: Selector
    ) -> NSView {
        let row = ClickableRowView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.target = self
        row.action = action

        let color = iconColor(forSymbol: symbol)
        let iconTile = NSView()
        iconTile.translatesAutoresizingMaskIntoConstraints = false
        iconTile.wantsLayer = true
        iconTile.layer?.cornerRadius = 11
        iconTile.layer?.cornerCurve = .continuous
        iconTile.layer?.backgroundColor = tintBackgroundColor(for: color).cgColor

        let icon = NSImageView()
        if symbol == "github" {
            if let image = NSImage(named: "github") {
                image.isTemplate = true
                icon.image = image
            } else {
                icon.image = NSImage(systemSymbolName: "globe", accessibilityDescription: title)
            }
        } else {
            icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        }
        icon.symbolConfiguration = .init(pointSize: 18, weight: .semibold)
        icon.contentTintColor = color
        icon.translatesAutoresizingMaskIntoConstraints = false
        iconTile.addSubview(icon)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13.5, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let detailLabel = NSTextField(labelWithString: detail)
        detailLabel.font = .systemFont(ofSize: 11.5)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingMiddle
        detailLabel.maximumNumberOfLines = 1
        detailLabel.translatesAutoresizingMaskIntoConstraints = false

        let chevron = NSImageView()
        chevron.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "")
        chevron.symbolConfiguration = .init(pointSize: 12, weight: .bold)
        chevron.contentTintColor = .tertiaryLabelColor
        chevron.translatesAutoresizingMaskIntoConstraints = false

        row.addSubview(iconTile)
        row.addSubview(titleLabel)
        row.addSubview(detailLabel)
        row.addSubview(chevron)

        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 64),

            iconTile.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 18),
            iconTile.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            iconTile.widthAnchor.constraint(equalToConstant: 38),
            iconTile.heightAnchor.constraint(equalToConstant: 38),

            icon.centerXAnchor.constraint(equalTo: iconTile.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconTile.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 22),
            icon.heightAnchor.constraint(equalToConstant: 22),

            titleLabel.leadingAnchor.constraint(equalTo: iconTile.trailingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: chevron.leadingAnchor, constant: -12),
            titleLabel.topAnchor.constraint(equalTo: row.topAnchor, constant: 13),

            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(lessThanOrEqualTo: chevron.leadingAnchor, constant: -12),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 5),

            chevron.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -22),
            chevron.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 12),
            chevron.heightAnchor.constraint(equalToConstant: 12)
        ])

        return row
    }

    private func settingsPopUpRow(
        symbol: String,
        title: String,
        detail: String,
        key: String,
        items: [(value: String, title: String)],
        action: Selector
    ) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let color = iconColor(forSymbol: symbol)
        let iconTile = NSView()
        iconTile.translatesAutoresizingMaskIntoConstraints = false
        iconTile.wantsLayer = true
        iconTile.layer?.cornerRadius = 11
        iconTile.layer?.cornerCurve = .continuous
        iconTile.layer?.backgroundColor = tintBackgroundColor(for: color).cgColor

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        icon.symbolConfiguration = .init(pointSize: 18, weight: .semibold)
        icon.contentTintColor = color
        icon.translatesAutoresizingMaskIntoConstraints = false
        iconTile.addSubview(icon)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13.5, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let detailLabel = NSTextField(labelWithString: detail)
        detailLabel.font = .systemFont(ofSize: 11.5)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.maximumNumberOfLines = 1
        detailLabel.translatesAutoresizingMaskIntoConstraints = false

        let popup = NSPopUpButton()
        popup.identifier = NSUserInterfaceItemIdentifier(key)
        popup.translatesAutoresizingMaskIntoConstraints = false
        popup.controlSize = .regular
        popup.target = self
        popup.action = action

        items.forEach { item in
            popup.addItem(withTitle: item.title)
            popup.lastItem?.representedObject = item.value
        }

        let selectedValue = RightMenuMiniPreferences.string(key, in: preferences)
        if let selectedItem = popup.itemArray.first(where: { $0.representedObject as? String == selectedValue }) {
            popup.select(selectedItem)
        }

        row.addSubview(iconTile)
        row.addSubview(titleLabel)
        row.addSubview(detailLabel)
        row.addSubview(popup)

        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 64),
            iconTile.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 18),
            iconTile.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            iconTile.widthAnchor.constraint(equalToConstant: 38),
            iconTile.heightAnchor.constraint(equalToConstant: 38),
            icon.centerXAnchor.constraint(equalTo: iconTile.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconTile.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 22),
            icon.heightAnchor.constraint(equalToConstant: 22),
            titleLabel.leadingAnchor.constraint(equalTo: iconTile.trailingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: popup.leadingAnchor, constant: -12),
            titleLabel.topAnchor.constraint(equalTo: row.topAnchor, constant: 13),
            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(lessThanOrEqualTo: popup.leadingAnchor, constant: -12),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 5),
            popup.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -18),
            popup.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            popup.widthAnchor.constraint(equalToConstant: 118)
        ])

        return row
    }

    private func authorizationRow() -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let iconTile = NSView()
        iconTile.translatesAutoresizingMaskIntoConstraints = false
        iconTile.wantsLayer = true
        iconTile.layer?.cornerRadius = 11
        iconTile.layer?.cornerCurve = .continuous

        let icon = NSImageView()
        icon.symbolConfiguration = .init(pointSize: 18, weight: .semibold)
        icon.translatesAutoresizingMaskIntoConstraints = false
        iconTile.addSubview(icon)

        let titleLabel = NSTextField(labelWithString: "")
        titleLabel.font = .systemFont(ofSize: 13.5, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let detailLabel = NSTextField(labelWithString: "")
        detailLabel.font = .systemFont(ofSize: 11.5)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.maximumNumberOfLines = 1
        detailLabel.translatesAutoresizingMaskIntoConstraints = false

        let textStack = NSStackView(views: [titleLabel, detailLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 4
        textStack.translatesAutoresizingMaskIntoConstraints = false

        let button = primaryButton(
            title: AppText.localized("授权", "Authorize"),
            symbol: "checkmark.shield",
            action: #selector(openExtensionSettings)
        )

        row.addSubview(iconTile)
        row.addSubview(textStack)
        row.addSubview(button)

        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 64),
            iconTile.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 18),
            iconTile.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            iconTile.widthAnchor.constraint(equalToConstant: 38),
            iconTile.heightAnchor.constraint(equalToConstant: 38),

            icon.centerXAnchor.constraint(equalTo: iconTile.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconTile.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 22),
            icon.heightAnchor.constraint(equalToConstant: 22),

            textStack.leadingAnchor.constraint(equalTo: iconTile.trailingAnchor, constant: 16),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: button.leadingAnchor, constant: -12),
            textStack.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            button.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -18),
            button.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            button.heightAnchor.constraint(equalToConstant: 30),
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 72)
        ])

        authorizationIconView = icon
        authorizationIconTile = iconTile
        authorizationTitleLabel = titleLabel
        authorizationDetailLabel = detailLabel
        authorizationButton = button

        return row
    }

    private func statusToggleRow() -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let key = RightMenuMiniPreferences.isMenuEnabled
        let color = NSColor.systemBlue

        let iconTile = NSView()
        iconTile.translatesAutoresizingMaskIntoConstraints = false
        iconTile.wantsLayer = true
        iconTile.layer?.cornerRadius = 11
        iconTile.layer?.cornerCurve = .continuous
        iconTile.layer?.backgroundColor = tintBackgroundColor(for: color).cgColor

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "power", accessibilityDescription: AppText.localized("右键菜单", "Context Menu"))
        icon.symbolConfiguration = .init(pointSize: 18, weight: .semibold)
        icon.contentTintColor = color
        icon.translatesAutoresizingMaskIntoConstraints = false
        iconTile.addSubview(icon)

        let titleLabel = NSTextField(labelWithString: AppText.localized("右键菜单服务", "Context Menu Service"))
        titleLabel.font = .systemFont(ofSize: 13.5, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let detailLabel = NSTextField(labelWithString: "")
        detailLabel.font = .systemFont(ofSize: 11.5)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.maximumNumberOfLines = 1
        detailLabel.translatesAutoresizingMaskIntoConstraints = false

        let textStack = NSStackView(views: [titleLabel, detailLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 4
        textStack.translatesAutoresizingMaskIntoConstraints = false

        let toggle = NSSwitch()
        toggle.identifier = NSUserInterfaceItemIdentifier(key)
        toggle.target = self
        toggle.action = #selector(preferenceSwitchChanged(_:))
        toggle.controlSize = .regular
        toggle.translatesAutoresizingMaskIntoConstraints = false

        row.addSubview(iconTile)
        row.addSubview(textStack)
        row.addSubview(toggle)

        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 64),
            iconTile.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 18),
            iconTile.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            iconTile.widthAnchor.constraint(equalToConstant: 38),
            iconTile.heightAnchor.constraint(equalToConstant: 38),

            icon.centerXAnchor.constraint(equalTo: iconTile.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconTile.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 22),
            icon.heightAnchor.constraint(equalToConstant: 22),

            textStack.leadingAnchor.constraint(equalTo: iconTile.trailingAnchor, constant: 16),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: toggle.leadingAnchor, constant: -12),
            textStack.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            toggle.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -18),
            toggle.centerYAnchor.constraint(equalTo: row.centerYAnchor)
        ])

        preferenceSwitches[key] = toggle
        preferenceRows[key] = row
        statusDetailLabels[key] = detailLabel
        preferenceIconViews[key] = icon
        preferenceIconTiles[key] = iconTile

        return row
    }

    private func featureSettingsPanel() -> NSView {
        settingsPanel(rows: [
            preferenceRow(
                symbol: "doc.badge.plus",
                title: AppText.localized("新建 Text", "New Text"),
                detail: AppText.localized("在当前位置创建 Untitled.txt", "Create Untitled.txt here"),
                key: RightMenuMiniPreferences.isNewTextEnabled
            ),
            preferenceRow(
                symbol: "terminal",
                title: AppText.localized("进入终端", "Open Terminal"),
                detail: AppText.localized("从当前位置打开 Terminal", "Open Terminal at this location"),
                key: RightMenuMiniPreferences.isTerminalEnabled
            ),
            preferenceRow(
                symbol: "doc.on.doc",
                title: AppText.localized("拷贝路径", "Copy Path"),
                detail: AppText.localized("复制所选项目或当前文件夹路径", "Copy selected paths or current folder"),
                key: RightMenuMiniPreferences.isCopyPathEnabled
            )
        ])
    }

    private func settingsPanel(rows: [NSView]) -> NSView {
        let list = NSStackView()
        list.orientation = .vertical
        list.alignment = .width
        list.distribution = .fill
        list.spacing = 0
        list.translatesAutoresizingMaskIntoConstraints = false

        rows.enumerated().forEach { index, row in
            if index > 0 {
                list.addArrangedSubview(divider())
            }
            list.addArrangedSubview(row)
        }

        let panel = plainCard(height: CGFloat(rows.count * 64 + max(rows.count - 1, 0)), cornerRadius: 16, fixedWidth: contentWidth)
        panel.addSubview(list)

        NSLayoutConstraint.activate([
            list.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            list.topAnchor.constraint(equalTo: panel.topAnchor),
            list.bottomAnchor.constraint(equalTo: panel.bottomAnchor)
        ])

        return panel
    }

    private var usesDarkAppearance: Bool {
        let appearance = window?.effectiveAppearance ?? NSApp.effectiveAppearance
        return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private var cardBackgroundColor: NSColor {
        usesDarkAppearance ? NSColor(white: 0.13, alpha: 1.0) : .white
    }

    private var cardBorderColor: NSColor {
        usesDarkAppearance ? NSColor(white: 1.0, alpha: 0.08) : NSColor(white: 0.0, alpha: 0.06)
    }

    private var cardShadowColor: NSColor {
        .black
    }

    private var iconTileBackgroundColor: NSColor {
        NSColor.controlAccentColor.withAlphaComponent(usesDarkAppearance ? 0.16 : 0.08)
    }

    private var sidebarSelectionColor: NSColor {
        NSColor.controlAccentColor.withAlphaComponent(usesDarkAppearance ? 0.24 : 0.18)
    }

    private var separatorLayerColor: NSColor {
        usesDarkAppearance
            ? NSColor.white.withAlphaComponent(0.08)
            : NSColor.separatorColor.withAlphaComponent(0.12)
    }

    private func tintBackgroundColor(for color: NSColor) -> NSColor {
        color.withAlphaComponent(usesDarkAppearance ? 0.18 : 0.08)
    }

    private func iconColor(forSymbol symbol: String) -> NSColor {
        switch symbol {
        case "power":
            return .systemBlue
        case "rectangle.stack":
            return .systemPurple
        case "doc.badge.plus":
            return .systemOrange
        case "terminal":
            return .systemTeal
        case "doc.on.doc":
            return .systemGreen
        case "character.bubble":
            return .systemBlue
        case "circle.lefthalf.filled":
            return .systemOrange
        case "info.circle":
            return .systemGreen
        case "github":
            return .labelColor
        default:
            return .controlAccentColor
        }
    }

    private func plainCard(height: CGFloat, cornerRadius: CGFloat, fixedWidth: CGFloat?) -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.backgroundColor = cardBackgroundColor.cgColor
        view.layer?.borderWidth = 0.5
        view.layer?.borderColor = cardBorderColor.cgColor

        view.layer?.shadowColor = cardShadowColor.cgColor
        view.layer?.shadowOffset = CGSize(width: 0, height: -2.5)
        view.layer?.shadowRadius = 8.0
        view.layer?.shadowOpacity = usesDarkAppearance ? 0.12 : 0.04
        view.layer?.masksToBounds = false

        var constraints = [
            view.heightAnchor.constraint(equalToConstant: height)
        ]
        if let fixedWidth {
            constraints.append(view.widthAnchor.constraint(equalToConstant: fixedWidth))
        }
        NSLayoutConstraint.activate(constraints)

        return view
    }

    private func preferenceRow(symbol: String, title: String, detail: String, key: String) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let color = iconColor(forSymbol: symbol)
        let iconTile = NSView()
        iconTile.translatesAutoresizingMaskIntoConstraints = false
        iconTile.wantsLayer = true
        iconTile.layer?.cornerRadius = 12
        iconTile.layer?.backgroundColor = tintBackgroundColor(for: color).cgColor

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        icon.symbolConfiguration = .init(pointSize: 20, weight: .semibold)
        icon.contentTintColor = color
        icon.translatesAutoresizingMaskIntoConstraints = false
        iconTile.addSubview(icon)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13.5, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1

        let detailLabel = NSTextField(labelWithString: detail)
        detailLabel.font = .systemFont(ofSize: 11.5)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.maximumNumberOfLines = 1

        let textStack = NSStackView(views: [titleLabel, detailLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 4
        textStack.translatesAutoresizingMaskIntoConstraints = false

        let toggle = NSSwitch()
        toggle.identifier = NSUserInterfaceItemIdentifier(key)
        toggle.target = self
        toggle.action = #selector(preferenceSwitchChanged(_:))
        toggle.controlSize = .regular
        toggle.translatesAutoresizingMaskIntoConstraints = false
        toggle.toolTip = title
        preferenceSwitches[key] = toggle
        preferenceRows[key] = row
        statusDetailLabels[key] = detailLabel
        preferenceIconViews[key] = icon
        preferenceIconTiles[key] = iconTile

        row.addSubview(iconTile)
        row.addSubview(textStack)
        row.addSubview(toggle)

        let constraints = [
            row.heightAnchor.constraint(equalToConstant: 64),
            iconTile.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            iconTile.widthAnchor.constraint(equalToConstant: 40),
            iconTile.heightAnchor.constraint(equalToConstant: 40),
            icon.centerXAnchor.constraint(equalTo: iconTile.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconTile.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 22),
            icon.heightAnchor.constraint(equalToConstant: 22),
            textStack.leadingAnchor.constraint(equalTo: iconTile.trailingAnchor, constant: 16),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: toggle.leadingAnchor, constant: -12),
            textStack.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            toggle.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -22),
            toggle.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            iconTile.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 18)
        ]

        NSLayoutConstraint.activate(constraints)
        return row
    }

    private var versionDescription: String {
        "v\(currentVersionString)"
    }

    private func divider() -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false

        let line = NSView()
        line.translatesAutoresizingMaskIntoConstraints = false
        line.wantsLayer = true
        line.layer?.backgroundColor = separatorLayerColor.cgColor
        view.addSubview(line)

        view.wantsLayer = true
        NSLayoutConstraint.activate([
            view.heightAnchor.constraint(equalToConstant: 1),
            line.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 74),
            line.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -22),
            line.topAnchor.constraint(equalTo: view.topAnchor),
            line.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        return view
    }

    private func primaryButton(title: String, symbol: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        button.imagePosition = .imageLeading
        return button
    }

    private func secondaryButton(title: String, symbol: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        button.imagePosition = .imageLeading
        return button
    }

    @objc private func languageSelectionChanged(_ sender: NSPopUpButton) {
        updateStringPreference(from: sender)
        configureStatusItem()
        refreshLocalizedInterface()
    }

    @objc private func appearanceSelectionChanged(_ sender: NSPopUpButton) {
        updateStringPreference(from: sender)
        applyAppearancePreference()
        reloadCurrentTab()
    }

    private func updateStringPreference(from sender: NSPopUpButton) {
        guard
            let key = sender.identifier?.rawValue,
            let value = sender.selectedItem?.representedObject as? String
        else {
            return
        }

        preferences.set(value, forKey: key)
        preferences.synchronize()
        RightMenuMiniPreferences.mirrorValues(from: preferences)
    }

    private func applyAppearancePreference() {
        let appearance: NSAppearance?
        switch RightMenuMiniPreferences.string(RightMenuMiniPreferences.appearanceMode, in: preferences) {
        case RightMenuMiniPreferences.lightValue:
            appearance = NSAppearance(named: .aqua)
        case RightMenuMiniPreferences.darkValue:
            appearance = NSAppearance(named: .darkAqua)
        default:
            appearance = nil
        }

        NSApp.appearance = appearance
        window?.appearance = appearance
    }

    private func refreshLocalizedInterface() {
        window?.title = AppText.localized("右键菜单助手", "RightMenuMini")
        sidebarBrandLabel?.stringValue = AppText.localized("右键菜单助手", "RightMenuMini")

        for (tab, button) in sidebarButtons {
            for subview in button.subviews {
                if let label = subview as? NSTextField {
                    label.stringValue = sidebarTitle(for: tab)
                }
            }
        }

        reloadCurrentTab()
    }

    private func reloadCurrentTab() {
        selectSidebarTab(currentTab)
    }

    @objc private func preferenceSwitchChanged(_ sender: NSSwitch) {
        guard finderExtensionEnabled else {
            sender.state = .off
            return
        }

        guard let key = sender.identifier?.rawValue else {
            return
        }

        preferences.set(sender.state == .on, forKey: key)
        preferences.synchronize()
        RightMenuMiniPreferences.mirrorValues(from: preferences)
        refreshPreferenceControls()
    }

    @objc private func flatLayoutSelected(_ sender: LayoutOptionCard) {
        guard finderExtensionEnabled && preferenceValue(for: RightMenuMiniPreferences.isMenuEnabled) else {
            return
        }
        preferences.set(false, forKey: RightMenuMiniPreferences.isGroupedMenuEnabled)
        preferences.synchronize()
        RightMenuMiniPreferences.mirrorValues(from: preferences)
        refreshPreferenceControls()
    }

    @objc private func groupedLayoutSelected(_ sender: LayoutOptionCard) {
        guard finderExtensionEnabled && preferenceValue(for: RightMenuMiniPreferences.isMenuEnabled) else {
            return
        }
        preferences.set(true, forKey: RightMenuMiniPreferences.isGroupedMenuEnabled)
        preferences.synchronize()
        RightMenuMiniPreferences.mirrorValues(from: preferences)
        refreshPreferenceControls()
    }

    private func refreshPreferenceControls() {
        let menuEnabled = preferenceValue(for: RightMenuMiniPreferences.isMenuEnabled)
        let isGrouped = preferenceValue(for: RightMenuMiniPreferences.isGroupedMenuEnabled)

        flatLayoutCard?.isSelected = !isGrouped
        groupedLayoutCard?.isSelected = isGrouped

        if finderExtensionEnabled && menuEnabled {
            flatLayoutCard?.alphaValue = 1.0
            groupedLayoutCard?.alphaValue = 1.0
        } else {
            flatLayoutCard?.alphaValue = finderExtensionEnabled ? 0.48 : 0.46
            groupedLayoutCard?.alphaValue = finderExtensionEnabled ? 0.48 : 0.46
        }

        guard !preferenceSwitches.isEmpty else {
            return
        }

        guard finderExtensionEnabled else {
            preferenceSwitches.values.forEach { toggle in
                toggle.state = .off
                toggle.isEnabled = false
            }
            preferenceRows.values.forEach { row in
                row.alphaValue = 0.46
            }
            statusDetailLabels[RightMenuMiniPreferences.isMenuEnabled]?.stringValue = AppText.localized("请先启用上方的 Finder 扩展授权", "Please enable Finder Extension permission above first")
            statusDetailLabels[RightMenuMiniPreferences.isGroupedMenuEnabled]?.stringValue = AppText.localized("授权后可设置", "Available after permission")
            updateMenuPowerAppearance(isEnabled: false)
            return
        }

        for (key, toggle) in preferenceSwitches {
            toggle.state = preferenceValue(for: key) ? .on : .off
            toggle.isEnabled = true
        }

        statusDetailLabels[RightMenuMiniPreferences.isMenuEnabled]?.stringValue = menuEnabled
            ? AppText.localized("已激活并显示在右键菜单中", "Activated and shown in context menu")
            : AppText.localized("已暂停（菜单项目已隐藏）", "Paused (menu items hidden)")
        updateMenuPowerAppearance(isEnabled: menuEnabled)

        statusDetailLabels[RightMenuMiniPreferences.isGroupedMenuEnabled]?.stringValue = isGrouped
            ? AppText.localized("折叠为子菜单", "Grouped in submenu")
            : AppText.localized("直接显示三项功能", "Show actions directly")

        dependentPreferenceKeys.forEach { key in
            preferenceSwitches[key]?.isEnabled = menuEnabled
            preferenceRows[key]?.alphaValue = menuEnabled ? 1 : 0.48
        }

        preferenceRows[RightMenuMiniPreferences.isMenuEnabled]?.alphaValue = 1
    }

    private func updateMenuPowerAppearance(isEnabled: Bool) {
        let color: NSColor = isEnabled ? .systemGreen : .systemRed
        preferenceIconViews[RightMenuMiniPreferences.isMenuEnabled]?.contentTintColor = color

        let tile = preferenceIconTiles[RightMenuMiniPreferences.isMenuEnabled]
        tile?.layer?.backgroundColor = tintBackgroundColor(for: color).cgColor
        tile?.layer?.shadowColor = color.cgColor
        tile?.layer?.shadowOffset = .zero
        tile?.layer?.shadowRadius = 5.0
        tile?.layer?.shadowOpacity = usesDarkAppearance ? 0.35 : 0.16
        tile?.layer?.masksToBounds = false
    }

    private var dependentPreferenceKeys: [String] {
        [
            RightMenuMiniPreferences.isNewTextEnabled,
            RightMenuMiniPreferences.isTerminalEnabled,
            RightMenuMiniPreferences.isCopyPathEnabled,
            RightMenuMiniPreferences.isGroupedMenuEnabled
        ]
    }

    private func preferenceValue(for key: String) -> Bool {
        RightMenuMiniPreferences.bool(key, in: preferences)
    }

    @objc private func openExtensionSettings() {
        registerFinderExtension()
        if refreshAuthorizationStatus() {
            return
        }
        revealExtensionItemsSettings()
        scheduleAuthorizationRefresh()
    }

    private func registerFinderExtension() {
        guard let extensionURL = Bundle.main.builtInPlugInsURL?.appendingPathComponent("RightMenuMiniFinderExtension.appex") else {
            return
        }

        runPluginKit(arguments: ["-a", extensionURL.path])
    }

    private func runPluginKit(arguments: [String]) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        task.arguments = arguments
        try? task.run()
        task.waitUntilExit()
    }

    @discardableResult
    private func refreshAuthorizationStatus() -> Bool {
        let isEnabled = finderExtensionIsEnabled()
        finderExtensionEnabled = isEnabled
        statusMenuAuthorizationItem?.isHidden = isEnabled
        authorizationButton?.isHidden = isEnabled

        if isEnabled {
            authorizationIconView?.image = NSImage(
                systemSymbolName: "checkmark.circle.fill",
                accessibilityDescription: AppText.localized("已授权", "Authorized")
            )
            authorizationIconView?.contentTintColor = .systemGreen
            authorizationIconTile?.layer?.backgroundColor = tintBackgroundColor(for: .systemGreen).cgColor
            authorizationIconTile?.layer?.shadowColor = NSColor.systemGreen.cgColor
            authorizationIconTile?.layer?.shadowOffset = .zero
            authorizationIconTile?.layer?.shadowRadius = 6.0
            authorizationIconTile?.layer?.shadowOpacity = usesDarkAppearance ? 0.35 : 0.18
            authorizationIconTile?.layer?.masksToBounds = false

            authorizationTitleLabel?.stringValue = AppText.localized("Finder 扩展授权", "Finder Extension Permission")
            authorizationDetailLabel?.stringValue = AppText.localized("已授权 · 服务准备就绪", "Authorized · Service ready")
        } else {
            authorizationIconView?.image = NSImage(
                systemSymbolName: "exclamationmark.circle.fill",
                accessibilityDescription: AppText.localized("需要授权", "Permission Required")
            )
            authorizationIconView?.contentTintColor = .systemOrange
            authorizationIconTile?.layer?.backgroundColor = tintBackgroundColor(for: .systemOrange).cgColor
            authorizationIconTile?.layer?.shadowColor = NSColor.systemOrange.cgColor
            authorizationIconTile?.layer?.shadowOffset = .zero
            authorizationIconTile?.layer?.shadowRadius = 6.0
            authorizationIconTile?.layer?.shadowOpacity = usesDarkAppearance ? 0.35 : 0.18
            authorizationIconTile?.layer?.masksToBounds = false

            authorizationTitleLabel?.stringValue = AppText.localized("Finder 扩展授权", "Finder Extension Permission")
            authorizationDetailLabel?.stringValue = AppText.localized("未授权 · 请在系统设置中开启", "Unauthorized · Please enable in System Settings")
        }

        refreshPreferenceControls()
        return isEnabled
    }

    private func finderExtensionIsEnabled() -> Bool {
        let output = runPluginKitAndCapture(arguments: ["-m", "-i", extensionBundleIdentifier])
        for line in output.components(separatedBy: .newlines) where line.contains(extensionBundleIdentifier) {
            return line.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("+")
        }

        return false
    }

    private func runPluginKitAndCapture(arguments: [String]) -> String {
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        task.arguments = arguments
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            NSLog("RightMenuMini pluginkit query failed: \(error.localizedDescription)")
            return ""
        }
    }

    private func scheduleAuthorizationRefresh() {
        [1.0, 2.5, 5.0].forEach { delay in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.refreshAuthorizationStatus()
            }
        }
    }

    private struct GitHubRelease: Decodable {
        let tagName: String
        let htmlURL: String

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }

    private struct GitHubAPIError: Decodable {
        let message: String?
    }

    @objc private func checkForUpdates() {
        latestReleasePageURL = nil
        updateCheckButton?.title = AppText.localized("检查", "Check")
        updateCheckButton?.action = #selector(checkForUpdates)
        updateCheckButton?.isEnabled = false
        updateStatusLabel?.stringValue = AppText.localized("正在检查 GitHub Releases...", "Checking GitHub Releases...")

        let webURL = URL(string: "https://github.com/Goonwb/RightMenuMini/releases/latest")!
        var request = URLRequest(url: webURL)
        request.httpMethod = "GET"
        request.setValue("RightMenuMini/\(currentVersionString)", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else {
                    return
                }

                self.updateCheckButton?.isEnabled = true

                if let error {
                    self.updateStatusLabel?.stringValue = AppText.localized(
                        "检查失败：\(error.localizedDescription)",
                        "Check failed: \(error.localizedDescription)"
                    )
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse else {
                    self.updateStatusLabel?.stringValue = AppText.localized(
                        "无法连接 GitHub。",
                        "Unable to connect to GitHub."
                    )
                    return
                }

                guard (200..<300).contains(httpResponse.statusCode) else {
                    if httpResponse.statusCode == 404 {
                        self.updateStatusLabel?.stringValue = AppText.localized(
                            "还没有发布 Release。",
                            "No GitHub release has been published yet."
                        )
                        return
                    }

                    self.updateStatusLabel?.stringValue = AppText.localized(
                        "GitHub 返回 \(httpResponse.statusCode)，请稍后再试。",
                        "GitHub returned \(httpResponse.statusCode). Please try again later."
                    )
                    return
                }

                guard let finalURL = httpResponse.url,
                      finalURL.pathComponents.contains("tag")
                else {
                    self.updateStatusLabel?.stringValue = AppText.localized(
                        "未找到最新版本信息。",
                        "No release version information was found."
                    )
                    return
                }

                let tagName = finalURL.lastPathComponent
                let latestVersion = self.normalizedVersion(tagName)
                self.latestReleasePageURL = finalURL

                if self.isVersion(latestVersion, newerThan: self.currentVersionString) {
                    self.updateStatusLabel?.stringValue = AppText.localized(
                        "发现新版本 \(tagName)，可前往 GitHub 下载。",
                        "New version \(tagName) is available on GitHub."
                    )
                    self.updateCheckButton?.title = AppText.localized("前往下载最新版本", "Download Latest")
                    self.updateCheckButton?.action = #selector(self.openLatestReleaseOrRepository)
                } else {
                    self.updateStatusLabel?.stringValue = AppText.localized(
                        "已是最新版本：\(self.versionDescription)",
                        "You are up to date: \(self.versionDescription)"
                    )
                }
            }
        }.resume()
    }

    @objc private func openGitHubProfile() {
        NSWorkspace.shared.open(repositoryURL)
    }

    @objc private func openLatestReleaseOrRepository() {
        NSWorkspace.shared.open(latestReleasePageURL ?? repositoryURL)
    }

    private var currentVersionString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    private func normalizedVersion(_ value: String) -> String {
        var version = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if version.lowercased().hasPrefix("v") {
            version.removeFirst()
        }
        return version
    }

    private func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let candidateParts = versionParts(candidate)
        let currentParts = versionParts(current)
        let count = max(candidateParts.count, currentParts.count)

        for index in 0..<count {
            let candidatePart = index < candidateParts.count ? candidateParts[index] : 0
            let currentPart = index < currentParts.count ? currentParts[index] : 0

            if candidatePart > currentPart {
                return true
            }
            if candidatePart < currentPart {
                return false
            }
        }

        return false
    }

    private func versionParts(_ value: String) -> [Int] {
        normalizedVersion(value)
            .split(separator: ".")
            .map { part in
                let numericPrefix = part.prefix { $0.isNumber }
                return Int(numericPrefix) ?? 0
            }
    }

    private func revealExtensionItemsSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.ExtensionsPreferences?extensionPointIdentifier=com.apple.fileprovider-nonui",
            "x-apple.systempreferences:com.apple.ExtensionsPreferences?extensionPointIdentifier=com.apple.FinderSync",
            "x-apple.systempreferences:com.apple.LoginItems-Settings.extension?ExtensionItems",
            "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
        ]

        for value in candidates {
            guard let url = URL(string: value), NSWorkspace.shared.open(url) else {
                continue
            }
            return
        }

        let script = """
        tell application "System Settings"
            activate
            reveal anchor "ExtensionItems" of pane id "com.apple.LoginItems-Settings.extension"
        end tell
        """

        var error: NSDictionary?
        _ = NSAppleScript(source: script)?.executeAndReturnError(&error)
    }

    @objc private func handleGetURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        receivedActionURL = true

        guard
            let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
            let url = URL(string: urlString),
            url.scheme == "rightmenumini",
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let action = components.host,
            let folderPath = components.queryItems?.first(where: { $0.name == "path" })?.value,
            !folderPath.isEmpty
        else {
            return
        }

        let shouldQuitAfterHandling = components.queryItems?.first(where: { $0.name == "quit" })?.value == "1"
        let folderURL = URL(fileURLWithPath: folderPath)

        switch action {
        case "new-text":
            createTextFile(in: folderURL)
        case "terminal":
            openTerminal(in: folderURL)
        default:
            break
        }

        if shouldQuitAfterHandling {
            terminateIfOnlyHandlingAction()
        }
    }

    private func terminateIfOnlyHandlingAction() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, self.window?.isVisible != true else {
                return
            }

            NSApp.terminate(nil)
        }
    }

    private func createTextFile(in folderURL: URL) {
        let fileURL = nextAvailableTextFileURL(in: folderURL)

        do {
            try Data().write(to: fileURL, options: .withoutOverwriting)
        } catch {
            NSLog("RightMenuMini fallback new text failed: \(error.localizedDescription)")
        }
    }

    private func openTerminal(in folderURL: URL) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-a", "Terminal", folderURL.path]

        do {
            try task.run()
        } catch {
            NSLog("RightMenuMini fallback terminal failed: \(error.localizedDescription)")
        }
    }

    private func nextAvailableTextFileURL(in folderURL: URL) -> URL {
        let fileManager = FileManager.default
        var index = 0

        while true {
            let suffix = index == 0 ? "" : " \(index + 1)"
            let candidate = folderURL.appendingPathComponent("Untitled\(suffix).txt")
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            index += 1
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

}

@main
@MainActor
struct RightMenuMiniApplication {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

@MainActor
final class ClickableRowView: NSView {
    var action: Selector?
    weak var target: AnyObject?
    private var isHovered = false
    private var isPressed = false
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeInActiveApp, .assumeInside]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        self.trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        isPressed = false
        needsDisplay = true

        let localPoint = convert(event.locationInWindow, from: nil)
        if bounds.contains(localPoint) {
            if let target, let action {
                _ = target.perform(action, with: self)
            }
        }
    }

    override func draw(_ rect: NSRect) {
        super.draw(rect)
        let isDark: Bool
        if let appearance = window?.effectiveAppearance {
            isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        } else {
            isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }

        if isPressed {
            let highlightRect = bounds.insetBy(dx: 4, dy: 4)
            let path = NSBezierPath(roundedRect: highlightRect, xRadius: 8, yRadius: 8)
            NSColor(white: isDark ? 1.0 : 0.0, alpha: isDark ? 0.12 : 0.06).set()
            path.fill()
        } else if isHovered {
            let highlightRect = bounds.insetBy(dx: 4, dy: 4)
            let path = NSBezierPath(roundedRect: highlightRect, xRadius: 8, yRadius: 8)
            NSColor(white: isDark ? 1.0 : 0.0, alpha: isDark ? 0.06 : 0.03).set()
            path.fill()
        }
    }
}

@MainActor
final class LayoutOptionCard: NSView {
    var action: Selector?
    weak var target: AnyObject?
    var isSelected = false {
        didSet {
            updateAppearance()
        }
    }

    private var isHovered = false
    private var isPressed = false
    private var trackingArea: NSTrackingArea?

    private let iconTile = NSView()
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")

    init(symbol: String, title: String, detail: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1.0

        iconTile.translatesAutoresizingMaskIntoConstraints = false
        iconTile.wantsLayer = true
        iconTile.layer?.cornerRadius = 8
        iconTile.layer?.cornerCurve = .continuous

        iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        iconView.symbolConfiguration = .init(pointSize: 16, weight: .semibold)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconTile.addSubview(iconView)

        titleLabel.font = .systemFont(ofSize: 12.5, weight: .bold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        detailLabel.font = .systemFont(ofSize: 10.5)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.maximumNumberOfLines = 1
        detailLabel.translatesAutoresizingMaskIntoConstraints = false

        let textStack = NSStackView(views: [titleLabel, detailLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconTile)
        addSubview(textStack)

        titleLabel.stringValue = title
        detailLabel.stringValue = detail

        NSLayoutConstraint.activate([
            iconTile.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            iconTile.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconTile.widthAnchor.constraint(equalToConstant: 32),
            iconTile.heightAnchor.constraint(equalToConstant: 32),

            iconView.centerXAnchor.constraint(equalTo: iconTile.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconTile.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),

            textStack.leadingAnchor.constraint(equalTo: iconTile.trailingAnchor, constant: 10),
            textStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeInActiveApp, .assumeInside]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        self.trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        updateAppearance()
    }

    override func mouseUp(with event: NSEvent) {
        isPressed = false
        updateAppearance()

        let localPoint = convert(event.locationInWindow, from: nil)
        if bounds.contains(localPoint) {
            if let target, let action {
                _ = target.perform(action, with: self)
            }
        }
    }

    func updateAppearance() {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        // Colors base
        let accent = NSColor.controlAccentColor
        let cardBgColor = isDark
            ? NSColor(white: 0.14, alpha: 1.0)
            : NSColor(white: 0.98, alpha: 1.0)
        let unselectedBorderColor = isDark
            ? NSColor(white: 1.0, alpha: 0.08)
            : NSColor(white: 0.0, alpha: 0.06)

        if isSelected {
            layer?.backgroundColor = accent.withAlphaComponent(isDark ? 0.12 : 0.06).cgColor
            layer?.borderColor = accent.cgColor
            layer?.borderWidth = 1.5

            iconTile.layer?.backgroundColor = accent.withAlphaComponent(isDark ? 0.20 : 0.10).cgColor
            iconView.contentTintColor = accent
        } else {
            layer?.borderWidth = 1.0
            layer?.borderColor = unselectedBorderColor.cgColor

            if isPressed {
                layer?.backgroundColor = isDark
                    ? NSColor(white: 0.11, alpha: 1.0).cgColor
                    : NSColor(white: 0.93, alpha: 1.0).cgColor
            } else if isHovered {
                layer?.backgroundColor = isDark
                    ? NSColor(white: 0.17, alpha: 1.0).cgColor
                    : NSColor(white: 0.96, alpha: 1.0).cgColor
            } else {
                layer?.backgroundColor = cardBgColor.cgColor
            }

            let iconColor = isDark ? NSColor.white.withAlphaComponent(0.7) : NSColor.black.withAlphaComponent(0.6)
            iconTile.layer?.backgroundColor = isDark ? NSColor.white.withAlphaComponent(0.08).cgColor : NSColor.black.withAlphaComponent(0.04).cgColor
            iconView.contentTintColor = iconColor
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateAppearance()
    }
}
