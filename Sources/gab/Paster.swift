import AppKit
import CoreGraphics

/// Pastes text at the current cursor by writing the clipboard and posting a
/// synthetic Cmd+V, then restoring the previous clipboard. Works in every app
/// (native, Electron, terminal, browser) — unlike AXUIElement insertion.
enum Paster {
    private static let vKeyCode: CGKeyCode = 9 // 'v'

    static func paste(_ text: String) {
        guard !text.isEmpty else { return }
        let pb = NSPasteboard.general
        let previous = pb.string(forType: .string)

        pb.clearContents()
        pb.setString(text, forType: .string)

        sendCmdV()

        // Restore after the paste has had time to land. A blind short timer races
        // slow apps and clipboard managers; 250ms is a comfortable personal-app margin.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            pb.clearContents()
            if let previous {
                pb.setString(previous, forType: .string)
            }
        }
    }

    private static func sendCmdV() {
        let src = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: vKeyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: vKeyCode, keyDown: false) else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
