import AppKit
import FinderSync

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

    static func resolvedValues() -> [String: Bool] {
        var values = defaultValues
        let store = store()

        defaultValues.keys.forEach { key in
            if store.object(forKey: key) != nil {
                values[key] = store.bool(forKey: key)
            }
        }

        for (key, value) in mirroredValues() {
            values[key] = value
        }

        return values
    }

    static func bool(_ key: String, in values: [String: Bool]) -> Bool {
        values[key] ?? defaultValues[key] ?? false
    }

    private static func mirroredValues() -> [String: Bool] {
        var values: [String: Bool] = [:]

        for url in preferenceFileURLs() {
            guard
                let data = try? Data(contentsOf: url),
                let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
                let dictionary = plist as? [String: Any]
            else {
                continue
            }

            defaultValues.keys.forEach { key in
                if let value = dictionary[key] as? Bool {
                    values[key] = value
                } else if let value = dictionary[key] as? NSNumber {
                    values[key] = value.boolValue
                }
            }
        }

        return values
    }

    private static func preferenceFileURLs() -> [URL] {
        let fileManager = FileManager.default
        let fileName = "\(suiteName).plist"
        var urls = [
            fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Preferences", isDirectory: true)
                .appendingPathComponent(fileName)
        ]

        if let userHome = realUserHomeDirectory() {
            urls.append(
                userHome
                    .appendingPathComponent("Library/Containers", isDirectory: true)
                    .appendingPathComponent(extensionContainerIdentifier, isDirectory: true)
                    .appendingPathComponent("Data/Library/Preferences", isDirectory: true)
                    .appendingPathComponent(fileName)
            )
            urls.append(
                userHome
                    .appendingPathComponent("Library/Preferences", isDirectory: true)
                    .appendingPathComponent(fileName)
            )
        }

        return urls
    }

    private static func realUserHomeDirectory() -> URL? {
        let userName = NSUserName()
        guard !userName.isEmpty else {
            return nil
        }

        return URL(fileURLWithPath: "/Users").appendingPathComponent(userName, isDirectory: true)
    }
}

@objc(FinderSync)
final class FinderSync: FIFinderSync {
    private let containingAppBundleIdentifier = "com.codex.RightMenuMini"

    override init() {
        super.init()
        FIFinderSyncController.default().directoryURLs = monitoredDirectories()
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems || menuKind == .contextualMenuForContainer else {
            return nil
        }

        let preferences = RightMenuMiniPreferences.resolvedValues()
        guard RightMenuMiniPreferences.bool(RightMenuMiniPreferences.isMenuEnabled, in: preferences) else {
            return nil
        }

        let actionItems = enabledActionItems(preferences: preferences)
        guard !actionItems.isEmpty else {
            return nil
        }

        let menu = NSMenu(title: "右键菜单助手")

        if RightMenuMiniPreferences.bool(RightMenuMiniPreferences.isGroupedMenuEnabled, in: preferences) {
            let groupItem = NSMenuItem(title: "右键菜单助手", action: nil, keyEquivalent: "")
            groupItem.image = symbol("contextualmenu.and.cursorarrow")
            let submenu = NSMenu(title: "右键菜单助手")
            actionItems.forEach { submenu.addItem($0) }
            groupItem.submenu = submenu
            menu.addItem(groupItem)
        } else {
            actionItems.forEach { menu.addItem($0) }
        }

        return menu
    }

    private func enabledActionItems(preferences: [String: Bool]) -> [NSMenuItem] {
        var items: [NSMenuItem] = []

        if RightMenuMiniPreferences.bool(RightMenuMiniPreferences.isNewTextEnabled, in: preferences) {
            items.append(menuItem(title: "新建 Text", symbolName: "doc.badge.plus", action: #selector(createTextFile(_:))))
        }

        if RightMenuMiniPreferences.bool(RightMenuMiniPreferences.isTerminalEnabled, in: preferences) {
            items.append(menuItem(title: "进入终端", symbolName: "terminal", action: #selector(openTerminal(_:))))
        }

        if RightMenuMiniPreferences.bool(RightMenuMiniPreferences.isCopyPathEnabled, in: preferences) {
            items.append(menuItem(title: "拷贝路径", symbolName: "doc.on.doc", action: #selector(copyPath(_:))))
        }

        return items
    }

    private func menuItem(title: String, symbolName: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.image = symbol(symbolName)
        return item
    }

    @objc private func createTextFile(_ sender: Any?) {
        guard let folderURL = bestFolderURL() else {
            return
        }

        performInContainingApp(action: "new-text", folderURL: folderURL)
    }

    @objc private func openTerminal(_ sender: Any?) {
        guard let folderURL = bestFolderURL() else {
            return
        }

        performInContainingApp(action: "terminal", folderURL: folderURL)
    }

    @objc private func copyPath(_ sender: Any?) {
        let paths = selectedURLsForAction().map(\.path)
        let fallbackPath = bestFolderURL()?.path
        let value = paths.isEmpty ? fallbackPath : paths.joined(separator: "\n")

        guard let value, !value.isEmpty else {
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }

    private func monitoredDirectories() -> Set<URL> {
        let fileManager = FileManager.default
        var urls: Set<URL> = [
            fileManager.homeDirectoryForCurrentUser,
            URL(fileURLWithPath: "/"),
            URL(fileURLWithPath: "/Volumes")
        ]

        let home = fileManager.homeDirectoryForCurrentUser
        ["Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures"].forEach { name in
            urls.insert(home.appendingPathComponent(name))
        }

        return urls
    }

    private func selectedURLsForAction() -> [URL] {
        FIFinderSyncController.default().selectedItemURLs() ?? []
    }

    private func bestFolderURL() -> URL? {
        if let firstSelectedURL = selectedURLsForAction().first {
            return folderURL(for: firstSelectedURL)
        }

        if let targetedURL = FIFinderSyncController.default().targetedURL() {
            return folderURL(for: targetedURL)
        }

        return nil
    }

    private func folderURL(for url: URL) -> URL {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return url
        }

        return url.deletingLastPathComponent()
    }

    private func symbol(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)
    }

    private func performInContainingApp(action: String, folderURL: URL) {
        guard
            let appURL = containingApplicationURL(),
            let actionURL = actionURL(action: action, folderURL: folderURL, quitAfterHandling: shouldQuitAppAfterHandlingAction())
        else {
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.promptsUserIfNeeded = false
        configuration.addsToRecentItems = false

        NSWorkspace.shared.open([actionURL], withApplicationAt: appURL, configuration: configuration) { _, error in
            if let error {
                NSLog("RightMenuMini action failed: \(action), \(error.localizedDescription)")
            }
        }
    }

    private func containingApplicationURL() -> URL? {
        let extensionURL = Bundle.main.bundleURL
        let contentsURL = extensionURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appURL = contentsURL.deletingLastPathComponent()

        return appURL.pathExtension == "app" ? appURL : nil
    }

    private func shouldQuitAppAfterHandlingAction() -> Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: containingAppBundleIdentifier).isEmpty
    }

    private func actionURL(action: String, folderURL: URL, quitAfterHandling: Bool) -> URL? {
        var components = URLComponents()
        components.scheme = "rightmenumini"
        components.host = action
        components.queryItems = [
            URLQueryItem(name: "path", value: folderURL.path),
            URLQueryItem(name: "quit", value: quitAfterHandling ? "1" : "0")
        ]

        return components.url
    }
}
