import AppKit
import CoreGraphics

/// Watches a single modifier key (right-Option by default) via a CGEventTap and
/// fires press/release callbacks for hold-to-talk.
///
/// Modifier keys do NOT emit keyDown/keyUp — they arrive as `.flagsChanged`.
/// We identify the key by its keycode and decide press vs release by whether the
/// modifier's flag bit is currently set.
final class HotkeyListener {
    /// Virtual keycodes for the modifiers we might use.
    enum Key: Int64 {
        case rightOption = 61
        case leftOption  = 58
        case rightCommand = 54
    }

    var onPress: () -> Void = {}
    var onRelease: () -> Void = {}

    private let keycode: Int64
    private let flagMask: CGEventFlags
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isDown = false

    init(key: Key = .rightOption) {
        self.keycode = key.rawValue
        switch key {
        case .rightOption, .leftOption: flagMask = .maskAlternate
        case .rightCommand:             flagMask = .maskCommand
        }
    }

    var isActive: Bool { tap != nil }

    func start() -> Bool {
        if tap != nil { return true } // already running
        let mask = (1 << CGEventType.flagsChanged.rawValue)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                let listener = Unmanaged<HotkeyListener>.fromOpaque(refcon!).takeUnretainedValue()
                listener.handle(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: selfPtr
        ) else {
            return false
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) {
        // The OS disables taps under load/timeout — re-enable or dictation dies.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        guard type == .flagsChanged else { return }
        guard event.getIntegerValueField(.keyboardEventKeycode) == keycode else { return }

        let pressed = event.flags.contains(flagMask)
        if pressed && !isDown {
            isDown = true
            DispatchQueue.main.async { [weak self] in self?.onPress() }
        } else if !pressed && isDown {
            isDown = false
            DispatchQueue.main.async { [weak self] in self?.onRelease() }
        }
    }
}
