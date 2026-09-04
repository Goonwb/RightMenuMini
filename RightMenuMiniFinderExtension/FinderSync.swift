import AppKit
import FinderSync

private enum RightMenuMiniPreferences {
    static let suiteName = "com.codex.RightMenuMini.shared"
    static let isMenuEnabled = "isMenuEnabled"
    static let isNewTextEnabled = "isNewTextEnabled"
    static let isTerminalEnabled = "isTerminalEnabled"
    static let isCopyPathEnabled = "isCopyPathEnabled"
    static let isGroupedMenuEnabled = "isGroupedMenuEnabled"
    static let languageMode = "languageMode"

    static let systemValue = "system"
    static let chineseValue = "zh-Hans"
    static let englishValue = "en"

    static let defaultValues: [String: Bool] = [
        isMenuEnabled: true,
        isNewTextEnabled: true,
        isTerminalEnabled: true,
        isCopyPathEnabled: true,
        isGroupedMenuEnabled: false
    ]
    static let stringDefaultValues: [String: String] = [
        languageMode: systemValue
    ]
    static var registeredDefaults: [String: Any] {
        var values: [String: Any] = defaultValues.mapValues { $0 as Any }
        stringDefaultValues.forEach { values[$0.key] = $0.value }
        return values
    }

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

    static func resolvedString(_ key: String) -> String {
        var value = string(key, in: store())

        for url in preferenceFileURLs() {
            guard
                let data = try? Data(contentsOf: url),
                let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
                let dictionary = plist as? [String: Any],
                let mirroredValue = dictionary[key] as? String,
                !mirroredValue.isEmpty
            else {
                continue
            }
            value = mirroredValue
        }

        return value
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

private enum MenuText {
    static var languageMode: String {
        RightMenuMiniPreferences.resolvedString(RightMenuMiniPreferences.languageMode)
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

private enum MenuWishAssets {
    // MenuWish 专属标志：原版三颗四角星（纯矢量，支持 Hover 纯白反色与深浅色模式）
    static let originalSparklesSVG = """
    <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 18 18" fill="black">
      <path d="M 8.70 4.75 L 9.82 7.88 L 12.95 9.00 L 9.82 10.12 L 8.70 13.25 L 7.58 10.12 L 4.45 9.00 L 7.58 7.88 Z" />
      <path d="M 4.15 2.65 L 4.77 4.13 L 6.25 4.75 L 4.77 5.37 L 4.15 6.85 L 3.53 5.37 L 2.05 4.75 L 3.53 4.13 Z" />
      <path d="M 13.65 11.55 L 14.19 12.81 L 15.45 13.35 L 14.19 13.89 L 13.65 15.15 L 13.11 13.89 L 11.85 13.35 L 13.11 12.81 Z" />
    </svg>
    """

    // Phosphor Icons Medium: 适度加粗（+30% 粗度，完美契合 macOS 菜单字重与可读性）
    static let phosphorFileTextSVG = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="black">
      <path stroke="black" stroke-width="5" stroke-linecap="round" stroke-linejoin="round" d="M213.66,82.34l-56-56A8,8,0,0,0,152,24H56A16,16,0,0,0,40,40V216a16,16,0,0,0,16,16H200a16,16,0,0,0,16-16V88A8,8,0,0,0,213.66,82.34ZM160,51.31,188.69,80H160ZM200,216H56V40h88V88a8,8,0,0,0,8,8h48V216Zm-32-80a8,8,0,0,1-8,8H96a8,8,0,0,1,0-16h64A8,8,0,0,1,168,136Zm0,32a8,8,0,0,1-8,8H96a8,8,0,0,1,0-16h64A8,8,0,0,1,168,168Z"/>
    </svg>
    """

    static let phosphorTerminalSVG = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="black">
      <path stroke="black" stroke-width="5" stroke-linecap="round" stroke-linejoin="round" d="M128,128a8,8,0,0,1-3,6.25l-40,32a8,8,0,1,1-10-12.5L107.19,128,75,102.25a8,8,0,1,1,10-12.5l40,32A8,8,0,0,1,128,128Zm48,24H136a8,8,0,0,0,0,16h40a8,8,0,0,0,0-16Zm56-96V200a16,16,0,0,1-16,16H40a16,16,0,0,1-16-16V56A16,16,0,0,1,40,40H216A16,16,0,0,1,232,56ZM216,200V56H40V200H216Z"/>
    </svg>
    """

    static let phosphorLinkSVG = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="black">
      <path stroke="black" stroke-width="5" stroke-linecap="round" stroke-linejoin="round" d="M240,88.23a54.43,54.43,0,0,1-16,37L189.25,160a54.27,54.27,0,0,1-38.63,16h-.05A54.63,54.63,0,0,1,96,119.84a8,8,0,0,1,16,.45A38.62,38.62,0,0,0,150.58,160h0a38.39,38.39,0,0,0,27.31-11.31l34.75-34.75a38.63,38.63,0,0,0-54.63-54.63l-11,11A8,8,0,0,1,135.7,59l11-11A54.65,54.65,0,0,1,224,48,54.86,54.86,0,0,1,240,88.23ZM109,185.66l-11,11A38.41,38.41,0,0,1,70.6,208h0a38.63,38.63,0,0,1-27.29-65.94L78,107.31A38.63,38.63,0,0,1,144,135.71a8,8,0,0,0,16,.45A54.86,54.86,0,0,0,144,96a54.65,54.65,0,0,0-77.27,0L32,130.75A54.62,54.62,0,0,0,70.56,224h0a54.28,54.28,0,0,0,38.64-16l11-11A8,8,0,0,0,109,185.66Z"/>
    </svg>
    """

    nonisolated(unsafe) private static var cache: [String: NSImage] = [:]
    private static let lock = NSLock()

    static func image(named name: String, size: NSSize = NSSize(width: 16, height: 16)) -> NSImage? {
        let key = "\(name)_\(Int(size.width))x\(Int(size.height))"
        lock.lock()
        if let cached = cache[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let svgString: String?
        switch name {
        case "sparkles", "menuwish-stars":
            svgString = originalSparklesSVG
        case "file-text":
            svgString = phosphorFileTextSVG
        case "square-terminal", "terminal":
            svgString = phosphorTerminalSVG
        case "link":
            svgString = phosphorLinkSVG
        default:
            svgString = nil
        }

        guard let svg = svgString,
              let data = svg.data(using: .utf8),
              let svgImage = NSImage(data: data) else {
            return nil
        }

        let rendered = NSImage(size: size)
        for scale in [1.0, 2.0] {
            let pxW = Int(size.width * scale)
            let pxH = Int(size.height * scale)
            let colorSpace = CGColorSpaceCreateDeviceGray()
            guard let ctx = CGContext(
                data: nil,
                width: pxW,
                height: pxH,
                bitsPerComponent: 8,
                bytesPerRow: pxW * 2,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                continue
            }
            ctx.interpolationQuality = .high
            ctx.setShouldAntialias(true)
            ctx.scaleBy(x: scale, y: scale)

            let g = NSGraphicsContext(cgContext: ctx, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = g
            svgImage.draw(in: NSRect(origin: .zero, size: size))
            NSGraphicsContext.restoreGraphicsState()

            if let cgImage = ctx.makeImage() {
                let rep = NSBitmapImageRep(cgImage: cgImage)
                rep.size = size
                rendered.addRepresentation(rep)
            }
        }

        rendered.isTemplate = true

        lock.lock()
        cache[key] = rendered
        lock.unlock()

        return rendered
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

        let menuTitle = "MenuWish"
        let menu = NSMenu(title: menuTitle)

        if RightMenuMiniPreferences.bool(RightMenuMiniPreferences.isGroupedMenuEnabled, in: preferences) {
            let groupItem = NSMenuItem(title: menuTitle, action: nil, keyEquivalent: "")
            groupItem.image = MenuWishAssets.image(named: "sparkles", size: NSSize(width: 18, height: 18))
            let submenu = NSMenu(title: menuTitle)
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
            items.append(menuItem(title: MenuText.localized("新建 Text", "New Text"), symbolName: "file-text", action: #selector(createTextFile(_:))))
        }

        if RightMenuMiniPreferences.bool(RightMenuMiniPreferences.isTerminalEnabled, in: preferences) {
            items.append(menuItem(title: MenuText.localized("进入终端", "Open Terminal"), symbolName: "square-terminal", action: #selector(openTerminal(_:))))
        }

        if RightMenuMiniPreferences.bool(RightMenuMiniPreferences.isCopyPathEnabled, in: preferences) {
            items.append(menuItem(title: MenuText.localized("拷贝路径", "Copy Path"), symbolName: "link", action: #selector(copyPath(_:))))
        }

        return items
    }

    private func menuItem(title: String, symbolName: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        if let icon = MenuWishAssets.image(named: symbolName, size: NSSize(width: 16, height: 16)) {
            item.image = icon
        } else {
            item.image = symbol(symbolName)
        }
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
