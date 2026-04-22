import AppKit

final class TextInjector {
    private static let injectedUserData: Int64 = 0x7E57

    func replace(abbreviation: String, with expansion: String, delimiterKeyCode: Int64, deleteDelimiter: Bool) {
        let deleteCount = abbreviation.count + (deleteDelimiter ? 1 : 0)
        DebugLogger.log("replace abbreviation=\(abbreviation) deleteCount=\(deleteCount) delimiterKeyCode=\(delimiterKeyCode)")
        deleteBackward(count: deleteCount)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self] in
            guard let self else { return }
            DebugLogger.log("replace paste expansionLength=\(expansion.count)")
            self.pastePreservingClipboard(text: expansion)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                DebugLogger.log("replace delimiter keyCode=\(delimiterKeyCode)")
                self.insertDelimiter(keyCode: delimiterKeyCode)
            }
        }
    }

    func deleteBackward(count: Int) {
        guard count > 0 else { return }
        for _ in 0..<count {
            postKey(keyCode: 51)
        }
    }

    func insert(text: String) {
        guard !text.isEmpty else { return }
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        keyDown?.keyboardSetUnicodeString(stringLength: text.utf16.count, unicodeString: Array(text.utf16))
        keyDown?.flags = []
        keyUp?.flags = []
        // Setting unicode text on keyUp can cause duplicate insertion in some apps.
        markInjected(keyDown)
        markInjected(keyUp)
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    func insertDelimiter(keyCode: Int64) {
        postKey(keyCode: keyCode)
    }

    func paste(text: String) {
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        markInjected(keyDown)
        markInjected(keyUp)
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    private func pastePreservingClipboard(text: String) {
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)
        paste(text: text)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            snapshot?.restore(to: pasteboard)
        }
    }

    private func postKey(keyCode: Int64) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: false)
        keyDown?.flags = []
        keyUp?.flags = []
        markInjected(keyDown)
        markInjected(keyUp)
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    private func markInjected(_ event: CGEvent?) {
        event?.setIntegerValueField(.eventSourceUserData, value: TextInjector.injectedUserData)
    }

    static func isInjectedEvent(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == TextInjector.injectedUserData
    }
}

private struct PasteboardSnapshot {
    let items: [[NSPasteboard.PasteboardType: Data]]

    static func capture(from pasteboard: NSPasteboard) -> PasteboardSnapshot? {
        guard let pasteboardItems = pasteboard.pasteboardItems else { return nil }
        let items = pasteboardItems.map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            })
        }
        return PasteboardSnapshot(items: items)
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }

        let restoredItems = items.map { itemData -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in itemData {
                item.setData(data, forType: type)
            }
            return item
        }

        pasteboard.writeObjects(restoredItems)
    }
}
