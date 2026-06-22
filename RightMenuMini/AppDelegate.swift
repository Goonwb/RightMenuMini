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
            return Locale.preferredLanguages.first?.lowercased().hasPrefix("en") == true
        }
    }

    static func localized(_ chinese: String, _ english: String) -> String {
        isEnglish ? english : chinese
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum SidebarTab {
        case overview
        case settings

        var identifier: String {
            switch self {
            case .overview:
                return "overview"
            case .settings:
                return "settings"
            }
        }

        static func from(identifier: String) -> SidebarTab? {
            switch identifier {
            case "overview":
                return .overview
            case "settings":
                return .settings
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
    private var currentTab: SidebarTab = .overview
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
    private var sidebarTitleLabel: NSTextField?
    private var sidebarVersionLabel: NSTextField?
    private var updateStatusLabel: NSTextField?
    private var updateCheckButton: NSButton?
    private var latestReleasePageURL: URL?

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
            contentRect: NSRect(x: 0, y: 0, width: 824, height: 570),
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
        selectSidebarTab(.overview)
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

        let content: NSView
        switch tab {
        case .overview:
            content = overviewContentView()
        case .settings:
            content = settingsContentView()
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

        let titleLabel = NSTextField(labelWithString: AppText.localized("右键菜单助手", "RightMenuMini"))
        titleLabel.font = .systemFont(ofSize: 21, weight: .bold)
        titleLabel.textColor = .labelColor
        titleLabel.alignment = .center

        let versionLabel = NSTextField(labelWithString: versionDescription)
        versionLabel.font = .systemFont(ofSize: 13)
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.alignment = .center

        let titleStack = NSStackView(views: [titleLabel, versionLabel])
        titleStack.orientation = .vertical
        titleStack.alignment = .centerX
        titleStack.spacing = 5
        titleStack.translatesAutoresizingMaskIntoConstraints = false

        let overviewButton = sidebarNavigationButton(symbol: "house", title: sidebarTitle(for: .overview), tab: .overview)
        let settingsButton = sidebarNavigationButton(symbol: "gearshape", title: sidebarTitle(for: .settings), tab: .settings)
        let navStack = NSStackView(views: [overviewButton, settingsButton])
        navStack.orientation = .vertical
        navStack.alignment = .width
        navStack.spacing = 8
        navStack.translatesAutoresizingMaskIntoConstraints = false

        sidebar.addSubview(icon)
        sidebar.addSubview(titleStack)
        sidebar.addSubview(navStack)

        NSLayoutConstraint.activate([
            icon.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 86),
            icon.centerXAnchor.constraint(equalTo: sidebar.centerXAnchor),
            icon.widthAnchor.constraint(equalToConstant: 88),
            icon.heightAnchor.constraint(equalToConstant: 88),

            titleStack.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 20),
            titleStack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 24),
            titleStack.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -24),

            navStack.topAnchor.constraint(equalTo: titleStack.bottomAnchor, constant: 34),
            navStack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 18),
            navStack.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -18),
            overviewButton.widthAnchor.constraint(equalTo: navStack.widthAnchor),
            settingsButton.widthAnchor.constraint(equalTo: navStack.widthAnchor)
        ])

        sidebarTitleLabel = titleLabel
        sidebarVersionLabel = versionLabel
        return sidebar
    }

    private func sidebarTitle(for tab: SidebarTab) -> String {
        switch tab {
        case .overview:
            return AppText.localized("概览", "Overview")
        case .settings:
            return AppText.localized("设置", "Settings")
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

    private func overviewContentView() -> NSView {
        let authorization = authorizationCard()
        let statusSection = sectionTitle(AppText.localized("快速状态", "Quick Status"))
        let statusCards = statusCardsPanel()
        let featuresSection = sectionTitle(AppText.localized("快捷功能", "Quick Actions"))
        let featuresPanel = featureSettingsPanel()

        let stack = NSStackView(views: [
            authorization,
            statusSection,
            statusCards,
            featuresSection,
            featuresPanel
        ])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 0
        stack.setCustomSpacing(24, after: authorization)
        stack.setCustomSpacing(10, after: statusSection)
        stack.setCustomSpacing(24, after: statusCards)
        stack.setCustomSpacing(10, after: featuresSection)
        stack.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            stack.widthAnchor.constraint(equalToConstant: contentWidth)
        ])

        return stack
    }

    private func sectionTitle(_ title: String) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            label.widthAnchor.constraint(equalToConstant: contentWidth),
            label.heightAnchor.constraint(equalToConstant: 20)
        ])

        return label
    }

    private func settingsContentView() -> NSView {
        let versionRow = settingsButtonRow(
            symbol: "info.circle",
            title: AppText.localized("当前版本", "Current Version"),
            detail: AppText.localized("\(versionDescription) · 可检查 GitHub Releases", "\(versionDescription) · Check GitHub Releases"),
            buttonTitle: AppText.localized("检查", "Check"),
            action: #selector(checkForUpdates)
        )
        updateStatusLabel = versionRow.detailLabel
        updateCheckButton = versionRow.button

        let githubRow = settingsButtonRow(
            symbol: "globe",
            title: "GitHub",
            detail: "github.com/Goonwb/RightMenuMini",
            buttonTitle: AppText.localized("前往", "Visit"),
            action: #selector(openGitHubProfile)
        )

        let projectSection = sectionTitle(AppText.localized("项目", "Project"))
        let projectPanel = settingsPanel(rows: [
            versionRow.row,
            githubRow.row
        ])

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

        let stack = NSStackView(views: [
            preferencesSection,
            preferencesPanel,
            projectSection,
            projectPanel
        ])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 0
        stack.setCustomSpacing(10, after: preferencesSection)
        stack.setCustomSpacing(24, after: preferencesPanel)
        stack.setCustomSpacing(10, after: projectSection)
        stack.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            stack.widthAnchor.constraint(equalToConstant: contentWidth)
        ])

        return stack
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

        let iconTile = NSView()
        iconTile.translatesAutoresizingMaskIntoConstraints = false
        iconTile.wantsLayer = true
        iconTile.layer?.cornerRadius = 11
        iconTile.layer?.cornerCurve = .continuous
        iconTile.layer?.backgroundColor = iconTileBackgroundColor.cgColor

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        icon.symbolConfiguration = .init(pointSize: 18, weight: .semibold)
        icon.contentTintColor = .secondaryLabelColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        iconTile.addSubview(icon)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let detailLabel = NSTextField(labelWithString: detail)
        detailLabel.font = .systemFont(ofSize: 13)
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

        let iconTile = NSView()
        iconTile.translatesAutoresizingMaskIntoConstraints = false
        iconTile.wantsLayer = true
        iconTile.layer?.cornerRadius = 11
        iconTile.layer?.cornerCurve = .continuous
        iconTile.layer?.backgroundColor = iconTileBackgroundColor.cgColor

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        icon.symbolConfiguration = .init(pointSize: 18, weight: .semibold)
        icon.contentTintColor = .secondaryLabelColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        iconTile.addSubview(icon)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let detailLabel = NSTextField(labelWithString: detail)
        detailLabel.font = .systemFont(ofSize: 13)
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

    private func authorizationCard() -> NSView {
        let card = plainCard(height: 96, cornerRadius: 12, fixedWidth: contentWidth)

        let iconTile = NSView()
        iconTile.translatesAutoresizingMaskIntoConstraints = false
        iconTile.wantsLayer = true
        iconTile.layer?.cornerRadius = 11
        iconTile.layer?.backgroundColor = iconTileBackgroundColor.cgColor

        let icon = NSImageView()
        icon.symbolConfiguration = .init(pointSize: 24, weight: .semibold)
        icon.translatesAutoresizingMaskIntoConstraints = false
        iconTile.addSubview(icon)

        let titleLabel = NSTextField(labelWithString: "")
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail

        let detailLabel = NSTextField(labelWithString: "")
        detailLabel.font = .systemFont(ofSize: 13)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail

        let textStack = NSStackView(views: [titleLabel, detailLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 4
        textStack.translatesAutoresizingMaskIntoConstraints = false

        let button = primaryButton(
            title: AppText.localized("初次授权", "Authorize"),
            symbol: "checkmark.shield",
            action: #selector(openExtensionSettings)
        )
        button.controlSize = .large

        card.addSubview(iconTile)
        card.addSubview(textStack)
        card.addSubview(button)

        NSLayoutConstraint.activate([
            iconTile.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 22),
            iconTile.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            iconTile.widthAnchor.constraint(equalToConstant: 44),
            iconTile.heightAnchor.constraint(equalToConstant: 44),
            icon.centerXAnchor.constraint(equalTo: iconTile.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconTile.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 26),
            icon.heightAnchor.constraint(equalToConstant: 26),
            textStack.leadingAnchor.constraint(equalTo: iconTile.trailingAnchor, constant: 16),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: button.leadingAnchor, constant: -12),
            textStack.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            button.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            button.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            button.heightAnchor.constraint(equalToConstant: 34),
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 112)
        ])

        authorizationIconView = icon
        authorizationIconTile = iconTile
        authorizationTitleLabel = titleLabel
        authorizationDetailLabel = detailLabel
        authorizationButton = button

        return card
    }

    private func statusCardsPanel() -> NSView {
        let menuCard = statusToggleCard(
            symbol: "power",
            title: AppText.localized("右键菜单", "Context Menu"),
            detail: AppText.localized("控制 Finder 菜单入口", "Control the Finder menu entry"),
            key: RightMenuMiniPreferences.isMenuEnabled
        )
        let groupCard = statusToggleCard(
            symbol: "rectangle.stack",
            title: AppText.localized("折叠显示", "Grouped Menu"),
            detail: AppText.localized("三项功能集合显示", "Show actions in a submenu"),
            key: RightMenuMiniPreferences.isGroupedMenuEnabled
        )

        let stack = NSStackView(views: [menuCard, groupCard])
        stack.orientation = .horizontal
        stack.alignment = .height
        stack.distribution = .fillEqually
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            stack.widthAnchor.constraint(equalToConstant: contentWidth),
            stack.heightAnchor.constraint(equalToConstant: 78)
        ])

        return stack
    }

    private func statusToggleCard(symbol: String, title: String, detail: String, key: String) -> NSView {
        let card = plainCard(height: 78, cornerRadius: 14, fixedWidth: nil)

        let iconTile = NSView()
        iconTile.translatesAutoresizingMaskIntoConstraints = false
        iconTile.wantsLayer = true
        iconTile.layer?.cornerRadius = 12
        iconTile.layer?.backgroundColor = iconTileBackgroundColor.cgColor

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        icon.symbolConfiguration = .init(pointSize: 22, weight: .semibold)
        icon.contentTintColor = .secondaryLabelColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        iconTile.addSubview(icon)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 15, weight: .bold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail

        let detailLabel = NSTextField(labelWithString: detail)
        detailLabel.font = .systemFont(ofSize: 12)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail

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
        preferenceSwitches[key] = toggle
        preferenceRows[key] = card
        statusDetailLabels[key] = detailLabel
        preferenceIconViews[key] = icon
        preferenceIconTiles[key] = iconTile

        card.addSubview(iconTile)
        card.addSubview(textStack)
        card.addSubview(toggle)

        NSLayoutConstraint.activate([
            iconTile.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            iconTile.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            iconTile.widthAnchor.constraint(equalToConstant: 38),
            iconTile.heightAnchor.constraint(equalToConstant: 38),
            icon.centerXAnchor.constraint(equalTo: iconTile.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconTile.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 24),
            icon.heightAnchor.constraint(equalToConstant: 24),

            textStack.leadingAnchor.constraint(equalTo: iconTile.trailingAnchor, constant: 14),
            textStack.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: toggle.leadingAnchor, constant: -12),

            toggle.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            toggle.centerYAnchor.constraint(equalTo: card.centerYAnchor)
        ])

        return card
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
        usesDarkAppearance ? NSColor(calibratedWhite: 0.18, alpha: 1) : .white
    }

    private var iconTileBackgroundColor: NSColor {
        NSColor.controlAccentColor.withAlphaComponent(usesDarkAppearance ? 0.16 : 0.08)
    }

    private var sidebarSelectionColor: NSColor {
        NSColor.controlAccentColor.withAlphaComponent(usesDarkAppearance ? 0.18 : 0.12)
    }

    private var separatorLayerColor: NSColor {
        usesDarkAppearance
            ? NSColor.white.withAlphaComponent(0.14)
            : NSColor.separatorColor.withAlphaComponent(0.22)
    }

    private func tintBackgroundColor(for color: NSColor) -> NSColor {
        color.withAlphaComponent(usesDarkAppearance ? 0.22 : 0.10)
    }

    private func plainCard(height: CGFloat, cornerRadius: CGFloat, fixedWidth: CGFloat?) -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.backgroundColor = cardBackgroundColor.cgColor
        view.layer?.borderWidth = 0
        view.layer?.shadowOpacity = 0

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

        let iconTile = NSView()
        iconTile.translatesAutoresizingMaskIntoConstraints = false
        iconTile.wantsLayer = true
        iconTile.layer?.cornerRadius = 12
        iconTile.layer?.backgroundColor = iconTileBackgroundColor.cgColor

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        icon.symbolConfiguration = .init(pointSize: 20, weight: .semibold)
        icon.contentTintColor = .controlAccentColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        iconTile.addSubview(icon)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 15, weight: .bold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1

        let detailLabel = NSTextField(labelWithString: detail)
        detailLabel.font = .systemFont(ofSize: 13)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.maximumNumberOfLines = 1

        let textStack = NSStackView(views: [titleLabel, detailLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 5
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
        preferenceIconViews[key] = icon
        preferenceIconTiles[key] = iconTile

        row.addSubview(iconTile)
        row.addSubview(textStack)
        row.addSubview(toggle)

        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 64),
            iconTile.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 18),
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
            toggle.centerYAnchor.constraint(equalTo: row.centerYAnchor)
        ])

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
        sidebarTitleLabel?.stringValue = AppText.localized("右键菜单助手", "RightMenuMini")
        sidebarVersionLabel?.stringValue = versionDescription

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

    private func refreshPreferenceControls() {
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
            statusDetailLabels[RightMenuMiniPreferences.isMenuEnabled]?.stringValue = AppText.localized("等待授权", "Waiting for permission")
            statusDetailLabels[RightMenuMiniPreferences.isGroupedMenuEnabled]?.stringValue = AppText.localized("授权后可设置", "Available after permission")
            updateMenuPowerAppearance(isEnabled: false)
            return
        }

        for (key, toggle) in preferenceSwitches {
            toggle.state = preferenceValue(for: key) ? .on : .off
            toggle.isEnabled = true
        }

        let menuEnabled = preferenceValue(for: RightMenuMiniPreferences.isMenuEnabled)
        statusDetailLabels[RightMenuMiniPreferences.isMenuEnabled]?.stringValue = menuEnabled
            ? AppText.localized("已启用", "Enabled")
            : AppText.localized("已关闭", "Disabled")
        updateMenuPowerAppearance(isEnabled: menuEnabled)

        let grouped = preferenceValue(for: RightMenuMiniPreferences.isGroupedMenuEnabled)
        statusDetailLabels[RightMenuMiniPreferences.isGroupedMenuEnabled]?.stringValue = grouped
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
        preferenceIconTiles[RightMenuMiniPreferences.isMenuEnabled]?.layer?.backgroundColor = tintBackgroundColor(for: color).cgColor
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
            authorizationTitleLabel?.stringValue = AppText.localized("Finder 扩展已启用", "Finder Extension Enabled")
            authorizationDetailLabel?.stringValue = AppText.localized("右键菜单可以直接使用。", "The context menu is ready to use.")
        } else {
            authorizationIconView?.image = NSImage(
                systemSymbolName: "exclamationmark.circle.fill",
                accessibilityDescription: AppText.localized("需要授权", "Permission Required")
            )
            authorizationIconView?.contentTintColor = .systemOrange
            authorizationIconTile?.layer?.backgroundColor = tintBackgroundColor(for: .systemOrange).cgColor
            authorizationTitleLabel?.stringValue = AppText.localized("需要 Finder 扩展权限", "Finder Extension Permission Required")
            authorizationDetailLabel?.stringValue = AppText.localized("首次使用前，请在系统设置中启用。", "Enable it in System Settings before first use.")
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

    @objc private func checkForUpdates() {
        latestReleasePageURL = nil
        updateCheckButton?.title = AppText.localized("检查", "Check")
        updateCheckButton?.action = #selector(checkForUpdates)
        updateCheckButton?.isEnabled = false
        updateStatusLabel?.stringValue = AppText.localized("正在检查 GitHub Releases...", "Checking GitHub Releases...")

        var request = URLRequest(url: latestReleaseAPIURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
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

                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 404 {
                    self.updateStatusLabel?.stringValue = AppText.localized(
                        "还没有发布 Release。",
                        "No GitHub release has been published yet."
                    )
                    return
                }

                guard
                    let data,
                    let release = try? JSONDecoder().decode(GitHubRelease.self, from: data)
                else {
                    self.updateStatusLabel?.stringValue = AppText.localized(
                        "无法读取版本信息。",
                        "Unable to read release information."
                    )
                    return
                }

                let latestVersion = self.normalizedVersion(release.tagName)
                self.latestReleasePageURL = URL(string: release.htmlURL)

                if self.isVersion(latestVersion, newerThan: self.currentVersionString) {
                    self.updateStatusLabel?.stringValue = AppText.localized(
                        "发现新版本 \(release.tagName)，可前往 GitHub 下载。",
                        "New version \(release.tagName) is available on GitHub."
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
