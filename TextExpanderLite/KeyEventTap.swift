import AppKit

final class KeyEventTap {
    private let callback: (CGEvent) -> Unmanaged<CGEvent>?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init(callback: @escaping (CGEvent) -> Unmanaged<CGEvent>?) {
        self.callback = callback
    }

    @discardableResult
    func start() -> Bool {
        if eventTap != nil {
            return ensureEnabled()
        }

        let mask = (1 << CGEventType.keyDown.rawValue)
        let tapCallback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passRetained(event) }
            let tap = Unmanaged<KeyEventTap>.fromOpaque(refcon).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                tap.reenableIfNeeded()
                return Unmanaged.passRetained(event)
            }
            return tap.callback(event) ?? Unmanaged.passRetained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: tapCallback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            return false
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return ensureEnabled()
    }

    private func reenableIfNeeded() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    @discardableResult
    func ensureEnabled() -> Bool {
        guard let tap = eventTap else { return false }
        if !CGEvent.tapIsEnabled(tap: tap) {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return CGEvent.tapIsEnabled(tap: tap)
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        runLoopSource = nil
        eventTap = nil
    }
}
