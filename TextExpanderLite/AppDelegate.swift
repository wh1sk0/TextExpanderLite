import AppKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let snippetStore = SnippetStore.shared
    private let textInjector = TextInjector()
    private let buffer = TypedBuffer()
    private let prompter = FillInPrompter()
    private var keyEventTap: KeyEventTap?
    private var statusItem: NSStatusItem?
    private var snippetsWindow: SnippetsWindowController?
    private var searchWindow: SearchWindowController?
    private var hotKeyManager: HotKeyManager?
    private var tapHealthTimer: Timer?
    private var pendingExpansion: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        DebugLogger.clear()
        DebugLogger.log("launch bundle=\(Bundle.main.bundleIdentifier ?? "unknown")")
        enforceSingleInstance()
        setupStatusBar()
        startKeyEventTap()
        setupWindows()
        registerHotKey()
    }

    private func enforceSingleInstance() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let all = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        let currentPID = ProcessInfo.processInfo.processIdentifier
        for app in all where app.processIdentifier != currentPID {
            _ = app.terminate()
        }
    }

    private func setupStatusBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.title = "Tx"
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Text Expander Lite", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        let snippetsItem = NSMenuItem(title: "Snippets…", action: #selector(openSnippets), keyEquivalent: "s")
        snippetsItem.target = self
        menu.addItem(snippetsItem)

        let searchItem = NSMenuItem(title: "Search Snippets", action: #selector(openSearch), keyEquivalent: " ")
        searchItem.keyEquivalentModifierMask = [.command, .shift]
        searchItem.target = self
        menu.addItem(searchItem)

        let openFolderItem = NSMenuItem(title: "Open Snippets Folder", action: #selector(openSnippetsFolder), keyEquivalent: "o")
        openFolderItem.target = self
        menu.addItem(openFolderItem)

        let reloadItem = NSMenuItem(title: "Reload Snippets", action: #selector(reloadSnippets), keyEquivalent: "r")
        reloadItem.target = self
        menu.addItem(reloadItem)
        let restartListenerItem = NSMenuItem(title: "Restart Listener", action: #selector(restartListener), keyEquivalent: "l")
        restartListenerItem.target = self
        menu.addItem(restartListenerItem)
        let openLogItem = NSMenuItem(title: "Open Debug Log", action: #selector(openDebugLog), keyEquivalent: "d")
        openLogItem.target = self
        menu.addItem(openLogItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        item.menu = menu

        statusItem = item
    }

    private func startKeyEventTap() {
        let tap = KeyEventTap { [weak self] event in
            return self?.handle(event: event)
        }
        let started = tap.start()
        DebugLogger.log("startKeyEventTap started=\(started)")
        keyEventTap = tap
        startTapHealthChecks()
    }

    private func startTapHealthChecks() {
        tapHealthTimer?.invalidate()
        tapHealthTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.ensureListenerActive()
        }
        tapHealthTimer?.tolerance = 0.5
        ensureListenerActive()
    }

    private func ensureListenerActive() {
        guard let tap = keyEventTap else { return }
        let active = tap.ensureEnabled() || tap.start()
        DebugLogger.log("ensureListenerActive active=\(active)")
        updateStatusIcon(listenerActive: active)
    }

    private func updateStatusIcon(listenerActive: Bool) {
        statusItem?.button?.title = listenerActive ? "Tx" : "Tx!"
    }

    private func containsFillInToken(_ text: String) -> Bool {
        text.contains("[[") && text.contains("]]")
    }

    private func setupWindows() {
        snippetsWindow = SnippetsWindowController(store: snippetStore)
        searchWindow = SearchWindowController(store: snippetStore, textInjector: textInjector, prompter: prompter)
    }

    private func registerHotKey() {
        hotKeyManager = HotKeyManager { [weak self] in
            self?.openSearch()
        }
        hotKeyManager?.register()
    }

    private func handle(event: CGEvent) -> Unmanaged<CGEvent>? {
        if TextInjector.isInjectedEvent(event) {
            return Unmanaged.passRetained(event)
        }

        guard event.type == .keyDown else {
            return Unmanaged.passRetained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        if KeyClassifier.isBackspace(keyCode) {
            DebugLogger.log("key backspace bufferBefore=\(buffer.debugValue)")
            buffer.deleteLast()
            return Unmanaged.passRetained(event)
        }

        if KeyClassifier.isDelimiter(keyCode) {
            DebugLogger.log("delimiter keyCode=\(keyCode) buffer=\(buffer.debugValue)")
            if let abbreviation = buffer.current(),
               let expansion = snippetStore.expansion(for: abbreviation) {
                let delimiter = keyCode
                buffer.reset()
                let deleteDelimiter = KeyClassifier.delimiterInsertsCharacter(delimiter)
                DebugLogger.log("match abbreviation=\(abbreviation) deleteDelimiter=\(deleteDelimiter) expansionLength=\(expansion.count)")
                scheduleExpansion(
                    abbreviation: abbreviation,
                    expansion: expansion,
                    delimiterKeyCode: delimiter,
                    deleteDelimiter: deleteDelimiter
                )
                // Let the delimiter reach the target app so it fully commits the typed shortcut.
                return Unmanaged.passRetained(event)
            }

            DebugLogger.log("delimiter no-match bufferReset")
            buffer.reset()
            return Unmanaged.passRetained(event)
        }

        if let typed = KeyClassifier.readTypedString(from: event) {
            buffer.append(
                typed,
                maxLength: snippetStore.maxAbbreviationLength,
                validPrefixes: snippetStore.abbreviationPrefixes
            )
            DebugLogger.log("typed keyCode=\(keyCode) chars=\(typed.debugDescription) bufferNow=\(buffer.debugValue)")
        } else if let fallback = KeyClassifier.fallbackString(for: keyCode, flags: event.flags) {
            buffer.append(
                fallback,
                maxLength: snippetStore.maxAbbreviationLength,
                validPrefixes: snippetStore.abbreviationPrefixes
            )
            DebugLogger.log("typed fallback keyCode=\(keyCode) chars=\(fallback.debugDescription) bufferNow=\(buffer.debugValue)")
        } else {
            DebugLogger.log("typed missing keyCode=\(keyCode)")
        }

        return Unmanaged.passRetained(event)
    }

    @objc private func openSnippets() {
        snippetsWindow?.show()
    }

    @objc private func openSearch() {
        let previousApp = NSWorkspace.shared.frontmostApplication
        searchWindow?.show(previousApp: previousApp)
    }

    @objc private func openSnippetsFolder() {
        let folder = SnippetStore.shared
        let url = folder.loadFolderURL()
        NSWorkspace.shared.open(url)
    }

    @objc private func reloadSnippets() {
        snippetStore.reload()
        searchWindow?.reloadSnippets()
    }

    @objc private func restartListener() {
        DebugLogger.log("restartListener")
        keyEventTap?.stop()
        keyEventTap = nil
        startKeyEventTap()
    }

    @objc private func openDebugLog() {
        NSWorkspace.shared.open(URL(fileURLWithPath: DebugLogger.path()))
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        pendingExpansion?.cancel()
        pendingExpansion = nil
        tapHealthTimer?.invalidate()
        tapHealthTimer = nil
    }

    private func scheduleExpansion(abbreviation: String, expansion: String, delimiterKeyCode: Int64, deleteDelimiter: Bool) {
        pendingExpansion?.cancel()
        DebugLogger.log("scheduleExpansion abbreviation=\(abbreviation) delay=0.08")

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            DebugLogger.log("executeExpansion abbreviation=\(abbreviation)")

            if !self.containsFillInToken(expansion) {
                self.textInjector.replace(
                    abbreviation: abbreviation,
                    with: expansion,
                    delimiterKeyCode: delimiterKeyCode,
                    deleteDelimiter: deleteDelimiter
                )
                return
            }

            if let resolved = self.prompter.resolve(expansion) {
                self.textInjector.replace(
                    abbreviation: abbreviation,
                    with: resolved,
                    delimiterKeyCode: delimiterKeyCode,
                    deleteDelimiter: deleteDelimiter
                )
            } else {
                self.textInjector.insertDelimiter(keyCode: delimiterKeyCode)
            }
        }

        pendingExpansion = workItem

        // Let the target app commit the typed abbreviation and delimiter before we replace it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: workItem)
    }
}

final class TypedBuffer {
    private var storage = ""
    var debugValue: String { storage }

    func append(_ text: String, maxLength: Int, validPrefixes: Set<String>) {
        for character in text {
            storage.append(character)
            if storage.count > maxLength {
                storage = String(storage.suffix(maxLength))
            }
            storage = longestValidSuffix(in: storage, validPrefixes: validPrefixes)
        }
    }

    func deleteLast() {
        guard !storage.isEmpty else { return }
        storage.removeLast()
    }

    func reset() {
        storage.removeAll()
    }

    func current() -> String? {
        storage.isEmpty ? nil : storage
    }

    private func longestValidSuffix(in text: String, validPrefixes: Set<String>) -> String {
        guard !text.isEmpty else { return text }

        for start in text.indices {
            let suffix = String(text[start...])
            if validPrefixes.contains(suffix) {
                return suffix
            }
        }

        return ""
    }
}

enum KeyClassifier {
    static func isDelimiter(_ keyCode: Int64) -> Bool {
        switch keyCode {
        case 36, 48, 49, 51, 53: // return, tab, space, delete, escape
            return true
        default:
            return false
        }
    }

    static func delimiterInsertsCharacter(_ keyCode: Int64) -> Bool {
        switch keyCode {
        case 36, 48, 49: // return, tab, space
            return true
        default:
            return false
        }
    }

    static func isBackspace(_ keyCode: Int64) -> Bool {
        keyCode == 51
    }

    static func readTypedString(from event: CGEvent) -> String? {
        if let nsEvent = NSEvent(cgEvent: event) {
            if let chars = nsEvent.characters, !chars.isEmpty {
                return chars
            }
            if let charsIgnoringModifiers = nsEvent.charactersIgnoringModifiers, !charsIgnoringModifiers.isEmpty {
                return charsIgnoringModifiers
            }
        }

        let maxLength = 32
        var buffer = [UniChar](repeating: 0, count: maxLength)
        var actualLength = 0
        event.keyboardGetUnicodeString(
            maxStringLength: maxLength,
            actualStringLength: &actualLength,
            unicodeString: &buffer
        )
        guard actualLength > 0 else { return nil }
        return String(utf16CodeUnits: buffer, count: actualLength)
    }

    static func fallbackString(for keyCode: Int64, flags: CGEventFlags) -> String? {
        switch keyCode {
        case 41: // semicolon key
            return flags.contains(.maskShift) ? ":" : ";"
        default:
            return nil
        }
    }
}
