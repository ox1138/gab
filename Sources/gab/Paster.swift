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
        let ourChangeCount = pb.changeCount

        sendCmdV()

        // Restore the old clipboard only AFTER the paste has certainly landed.
        // The frontmost app reads the pasteboard asynchronously; if we restore too
        // early (the old blind 250ms timer), a sluggish or heavy app — especially
        // right after wake — reads *after* the restore and pastes the previous
        // clipboard instead of the transcription. Give it a generous margin.
        //
        // Also skip the restore if anything else touched the clipboard since our
        // write (changeCount moved) — that means a clipboard manager or the user
        // put something new there, and we must not stomp it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            guard pb.changeCount == ourChangeCount else { return }
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
