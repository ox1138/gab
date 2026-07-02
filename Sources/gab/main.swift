import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Accessory: no Dock icon, never steals focus from the target text field.
app.setActivationPolicy(.accessory)
app.run()
