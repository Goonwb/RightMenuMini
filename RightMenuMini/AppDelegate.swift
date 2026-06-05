import AppKit
import Carbon

private enum RightMenuMiniPreferences {
    static let suiteName = "com.codex.RightMenuMini.shared"
    static let isMenuEnabled = "isMenuEnabled"
    static let isNewTextEnabled = "isNewTextEnabled"
    static let isTerminalEnabled = "isTerminalEnabled"
    static let isCopyPathEnabled = "isCopyPathEnabled"
    static let isGroupedMenuEnabled = "isGroupedMenuEnabled"

    static let defaultValues: [String: Bool] = [
        isMenuEnabled: true,
        isNewTextEnabled: true,
        isTerminalEnabled: true,
        isCopyPathEnabled: true,
        isGroupedMenuEnabled: false
    ]
    static let extensionContainerIdentifier = "com.codex.RightMenuMini.FinderExtension"

    static func store() -> UserDefaults {
        let store = UserDefaults(suiteName: suiteName) ?? .standard
        store.register(defaults: defaultValues)
        return store
    }

    static func bool(_ key: String, in store: UserDefaults) -> Bool {
        if store.object(forKey: key) == nil {
            return defaultValues[key] ?? false
        }
        return store.bool(forKey: key)
    }

    static func values(in store: UserDefaults) -> [String: Bool] {
        var values = defaultValues
        defaultValues.keys.forEach { key in
            if store.object(forKey: key) != nil {
                values[key] = store.bool(forKey: key)
            }
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

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let extensionBundleIdentifier = "com.codex.RightMenuMini.FinderExtension"
    private let contentWidth: CGFloat = 536
    private var window: NSWindow?
    private var statusItem: NSStatusItem?
    private var statusMenuAuthorizationItem: NSMenuItem?
    private var receivedActionURL = false
    private let preferences = RightMenuMiniPreferences.store()
    private var preferenceSwitches: [String: NSSwitch] = [:]
    private var preferenceRows: [String: NSView] = [:]
    private var authorizationIconView: NSImageView?
    private var authorizationTitleLabel: NSTextField?
    private var authorizationDetailLabel: NSTextField?
    private var authorizationButton: NSButton?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        preferences.register(defaults: RightMenuMiniPreferences.defaultValues)
        RightMenuMiniPreferences.mirrorValues(from: preferences)
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
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 610),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "右键菜单助手"
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

        let header = headerView()
        let authorization = authorizationCard()
        let displaySection = sectionTitle("菜单显示")
        let displayPanel = displaySettingsPanel()
        let featuresSection = sectionTitle("功能项")
        let featuresPanel = featureSettingsPanel()
        let about = aboutCard()
        let contentStack = NSStackView(views: [
            header,
            authorization,
            displaySection,
            displayPanel,
            featuresSection,
            featuresPanel,
            about
        ])
        contentStack.orientation = .vertical
        contentStack.alignment = .width
        contentStack.spacing = 0
        contentStack.setCustomSpacing(18, after: header)
        contentStack.setCustomSpacing(18, after: authorization)
        contentStack.setCustomSpacing(8, after: displaySection)
        contentStack.setCustomSpacing(16, after: displayPanel)
        contentStack.setCustomSpacing(8, after: featuresSection)
        contentStack.setCustomSpacing(16, after: featuresPanel)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        visualView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: visualView.leadingAnchor, constant: 32),
            contentStack.trailingAnchor.constraint(equalTo: visualView.trailingAnchor, constant: -32),
            contentStack.topAnchor.constraint(equalTo: visualView.topAnchor, constant: 32),
            contentStack.bottomAnchor.constraint(equalTo: visualView.bottomAnchor, constant: -24)
        ])

        self.window = window
        refreshAuthorizationStatus()
    }

    private func configureStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "contextualmenu.and.cursorarrow", accessibilityDescription: "右键菜单助手")
        statusItem.button?.image?.isTemplate = true

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "打开右键菜单助手", action: #selector(showMainWindow), keyEquivalent: ""))
        let authorizationItem = NSMenuItem(title: "初次授权", action: #selector(openExtensionSettings), keyEquivalent: "")
        menu.addItem(authorizationItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出右键菜单助手", action: #selector(quitApp), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu

        self.statusMenuAuthorizationItem = authorizationItem
        self.statusItem = statusItem
        refreshAuthorizationStatus()
    }

    @objc private func showMainWindow() {
        showWindow()
    }

    private func headerView() -> NSView {
        let icon = NSImageView()
        icon.image = applicationIconImage()
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: "右键菜单助手")
        titleLabel.font = .systemFont(ofSize: 21, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.alignment = .left

        let subtitleLabel = NSTextField(labelWithString: "在 Finder 中快速执行常用操作。")
        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.alignment = .left

        let titleStack = NSStackView(views: [titleLabel, subtitleLabel])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 3

        let stack = NSStackView(views: [icon, titleStack])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            stack.widthAnchor.constraint(equalToConstant: contentWidth),
            stack.heightAnchor.constraint(equalToConstant: 44),
            icon.widthAnchor.constraint(equalToConstant: 44),
            icon.heightAnchor.constraint(equalToConstant: 44)
        ])

        return stack
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

    private func sectionTitle(_ title: String) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            label.widthAnchor.constraint(equalToConstant: contentWidth),
            label.heightAnchor.constraint(equalToConstant: 16)
        ])

        return label
    }

    private func authorizationCard() -> NSView {
        let card = plainCard(height: 72)

        let iconTile = NSView()
        iconTile.translatesAutoresizingMaskIntoConstraints = false
        iconTile.wantsLayer = true
        iconTile.layer?.cornerRadius = 9
        iconTile.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.08).cgColor

        let icon = NSImageView()
        icon.symbolConfiguration = .init(pointSize: 18, weight: .semibold)
        icon.translatesAutoresizingMaskIntoConstraints = false
        iconTile.addSubview(icon)

        let titleLabel = NSTextField(labelWithString: "")
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail

        let detailLabel = NSTextField(labelWithString: "")
        detailLabel.font = .systemFont(ofSize: 12)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail

        let textStack = NSStackView(views: [titleLabel, detailLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false

        let button = primaryButton(title: "初次授权", symbol: "checkmark.shield", action: #selector(openExtensionSettings))

        card.addSubview(iconTile)
        card.addSubview(textStack)
        card.addSubview(button)

        NSLayoutConstraint.activate([
            iconTile.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            iconTile.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            iconTile.widthAnchor.constraint(equalToConstant: 34),
            iconTile.heightAnchor.constraint(equalToConstant: 34),
            icon.centerXAnchor.constraint(equalTo: iconTile.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconTile.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 20),
            icon.heightAnchor.constraint(equalToConstant: 20),
            textStack.leadingAnchor.constraint(equalTo: iconTile.trailingAnchor, constant: 12),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: button.leadingAnchor, constant: -12),
            textStack.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            button.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            button.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            button.heightAnchor.constraint(equalToConstant: 30),
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 108)
        ])

        authorizationIconView = icon
        authorizationTitleLabel = titleLabel
        authorizationDetailLabel = detailLabel
        authorizationButton = button

        return card
    }

    private func displaySettingsPanel() -> NSView {
        settingsPanel(rows: [
            preferenceRow(
                symbol: "power",
                title: "启用右键菜单",
                detail: "关闭后 Finder 中不显示任何菜单项",
                key: RightMenuMiniPreferences.isMenuEnabled
            ),
            preferenceRow(
                symbol: "rectangle.stack",
                title: "折叠显示",
                detail: "显示为“右键菜单助手 > 三项功能”",
                key: RightMenuMiniPreferences.isGroupedMenuEnabled
            )
        ])
    }

    private func featureSettingsPanel() -> NSView {
        settingsPanel(rows: [
            preferenceRow(
                symbol: "doc.badge.plus",
                title: "新建 Text",
                detail: "在当前位置创建 Untitled.txt",
                key: RightMenuMiniPreferences.isNewTextEnabled
            ),
            preferenceRow(
                symbol: "terminal",
                title: "进入终端",
                detail: "从当前位置打开 Terminal",
                key: RightMenuMiniPreferences.isTerminalEnabled
            ),
            preferenceRow(
                symbol: "doc.on.doc",
                title: "拷贝路径",
                detail: "复制所选项目或当前文件夹路径",
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

        let panel = plainCard(height: CGFloat(rows.count * 54 + max(rows.count - 1, 0)))
        panel.addSubview(list)

        NSLayoutConstraint.activate([
            list.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            list.topAnchor.constraint(equalTo: panel.topAnchor),
            list.bottomAnchor.constraint(equalTo: panel.bottomAnchor)
        ])

        return panel
    }

    private func plainCard(height: CGFloat) -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.wantsLayer = true
        view.layer?.cornerRadius = 10
        view.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.68).cgColor

        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: contentWidth),
            view.heightAnchor.constraint(equalToConstant: height)
        ])

        return view
    }

    private func preferenceRow(symbol: String, title: String, detail: String, key: String) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let iconTile = NSView()
        iconTile.translatesAutoresizingMaskIntoConstraints = false
        iconTile.wantsLayer = true
        iconTile.layer?.cornerRadius = 7
        iconTile.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.08).cgColor

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        icon.symbolConfiguration = .init(pointSize: 16, weight: .medium)
        icon.contentTintColor = .controlAccentColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        iconTile.addSubview(icon)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 14, weight: .medium)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1

        let detailLabel = NSTextField(labelWithString: detail)
        detailLabel.font = .systemFont(ofSize: 12)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.maximumNumberOfLines = 1

        let textStack = NSStackView(views: [titleLabel, detailLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
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

        row.addSubview(iconTile)
        row.addSubview(textStack)
        row.addSubview(toggle)

        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 54),
            iconTile.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 12),
            iconTile.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            iconTile.widthAnchor.constraint(equalToConstant: 30),
            iconTile.heightAnchor.constraint(equalToConstant: 30),
            icon.centerXAnchor.constraint(equalTo: iconTile.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconTile.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),
            textStack.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 56),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: toggle.leadingAnchor, constant: -12),
            textStack.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            toggle.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -14),
            toggle.centerYAnchor.constraint(equalTo: row.centerYAnchor)
        ])

        return row
    }

    private func aboutCard() -> NSView {
        let card = plainCard(height: 62)

        let titleLabel = NSTextField(labelWithString: "关于说明")
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let detailLabel = NSTextField(labelWithString: "RightMenuMini \(versionDescription) · by Goonwb")
        detailLabel.font = .systemFont(ofSize: 12)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.translatesAutoresizingMaskIntoConstraints = false

        let linkButton = NSButton(title: "GitHub", target: self, action: #selector(openGitHubProfile))
        linkButton.translatesAutoresizingMaskIntoConstraints = false
        linkButton.bezelStyle = .rounded
        linkButton.controlSize = .regular
        linkButton.image = NSImage(systemSymbolName: "arrow.up.right", accessibilityDescription: "GitHub")
        linkButton.imagePosition = .imageTrailing

        card.addSubview(titleLabel)
        card.addSubview(detailLabel)
        card.addSubview(linkButton)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: linkButton.leadingAnchor, constant: -12),
            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),
            detailLabel.trailingAnchor.constraint(lessThanOrEqualTo: linkButton.leadingAnchor, constant: -12),
            linkButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            linkButton.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            linkButton.heightAnchor.constraint(equalToConstant: 30),
            linkButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 92)
        ])

        return card
    }

    private var versionDescription: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.x"
        return "v\(version)"
    }

    private func divider() -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false

        let line = NSView()
        line.translatesAutoresizingMaskIntoConstraints = false
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.20).cgColor
        view.addSubview(line)

        view.wantsLayer = true
        NSLayoutConstraint.activate([
            view.heightAnchor.constraint(equalToConstant: 1),
            line.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 56),
            line.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
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

    @objc private func preferenceSwitchChanged(_ sender: NSSwitch) {
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

        for (key, toggle) in preferenceSwitches {
            toggle.state = preferenceValue(for: key) ? .on : .off
        }

        let menuEnabled = preferenceValue(for: RightMenuMiniPreferences.isMenuEnabled)
        dependentPreferenceKeys.forEach { key in
            preferenceSwitches[key]?.isEnabled = menuEnabled
            preferenceRows[key]?.alphaValue = menuEnabled ? 1 : 0.48
        }
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
        statusMenuAuthorizationItem?.isHidden = isEnabled
        authorizationButton?.isHidden = isEnabled

        if isEnabled {
            authorizationIconView?.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "已授权")
            authorizationIconView?.contentTintColor = .systemGreen
            authorizationTitleLabel?.stringValue = "Finder 扩展已启用"
            authorizationDetailLabel?.stringValue = "右键菜单可以直接使用。"
        } else {
            authorizationIconView?.image = NSImage(systemSymbolName: "exclamationmark.circle.fill", accessibilityDescription: "需要授权")
            authorizationIconView?.contentTintColor = .systemOrange
            authorizationTitleLabel?.stringValue = "需要 Finder 扩展权限"
            authorizationDetailLabel?.stringValue = "首次使用前，请在系统设置中启用。"
        }

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

    @objc private func openGitHubProfile() {
        guard let url = URL(string: "https://github.com/Goonwb") else {
            return
        }

        NSWorkspace.shared.open(url)
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
