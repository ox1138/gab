import AppKit
import AVFoundation
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let audio = AudioCapture()
    private var transcriber: Transcriber?
    private let hotkey = HotkeyListener(key: .rightOption)

    private let minDurationSeconds = 0.3
    private let sampleRate = 16_000.0
    private var busy = false
    private var trustTimer: Timer?
    private var statusMenuItem: NSMenuItem?
    private var loginItem: NSMenuItem?
    private var modelSubmenu: NSMenu?
    private var currentModelPath: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        requestMicAccess()
        loadModel()
        startHotkey()
        enableLaunchAtLogin()
    }

    // MARK: - Menu bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setIcon(listening: false)
        let menu = NSMenu()
        let status = NSMenuItem(title: "gab — starting…", action: nil, keyEquivalent: "")
        statusMenuItem = status
        menu.addItem(status)
        menu.addItem(.separator())

        let modelParent = NSMenuItem(title: "Model", action: nil, keyEquivalent: "")
        let modelMenu = NSMenu()
        modelParent.submenu = modelMenu
        modelSubmenu = modelMenu
        menu.addItem(modelParent)
        rebuildModelMenu()

        menu.addItem(.separator())
        let login = NSMenuItem(title: "Start at Login", action: #selector(toggleLoginItem), keyEquivalent: "")
        login.target = self
        loginItem = login
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit gab", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    // MARK: - Model menu

    private func rebuildModelMenu() {
        guard let modelSubmenu else { return }
        modelSubmenu.removeAllItems()
        let models = ModelLocator.available()
        let current = ModelLocator.modelPath()
        if models.isEmpty {
            let none = NSMenuItem(title: "No models found — run fetch-model.sh", action: nil, keyEquivalent: "")
            none.isEnabled = false
            modelSubmenu.addItem(none)
            return
        }
        for model in models {
            let item = NSMenuItem(title: model.label, action: #selector(selectModel(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = model.fileName
            item.state = (model.path == current) ? .on : .off
            modelSubmenu.addItem(item)
        }
    }

    @objc private func selectModel(_ sender: NSMenuItem) {
        guard let fileName = sender.representedObject as? String else { return }
        let newPath = (ModelLocator.supportDir() as NSString).appendingPathComponent(fileName)
        guard newPath != currentModelPath else { return }
        ModelLocator.selectedFileName = fileName
        rebuildModelMenu()
        loadModel()
    }

    private func setIcon(listening: Bool) {
        guard let button = statusItem.button else { return }
        let name = listening ? "mic.fill" : "mic"
        let desc = listening ? "gab listening" : "gab idle"
        button.image = NSImage(systemSymbolName: name, accessibilityDescription: desc)
        button.contentTintColor = listening ? .systemRed : nil
    }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: - Launch at login

    private func enableLaunchAtLogin() {
        if SMAppService.mainApp.status != .enabled {
            try? SMAppService.mainApp.register()
        }
        refreshLoginItemState()
    }

    private func refreshLoginItemState() {
        loginItem?.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
    }

    @objc private func toggleLoginItem() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("gab: login item toggle failed: \(error)")
        }
        refreshLoginItemState()
    }

    // MARK: - Permissions

    private func requestMicAccess() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            if !granted { NSLog("gab: microphone access denied") }
        }
    }

    /// Prompt once for Accessibility (shows the system dialog if not yet granted).
    @discardableResult
    private func isTrusted(prompt: Bool) -> Bool {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    // MARK: - Model

    private func loadModel() {
        let path = ModelLocator.modelPath()
        guard FileManager.default.fileExists(atPath: path) else {
            NSLog("gab: model not found at \(path) — run scripts/fetch-model.sh")
            presentAlert(title: "Whisper model missing",
                         text: "Expected a ggml model at:\n\(path)\n\nRun scripts/fetch-model.sh, then relaunch gab.")
            return
        }
        currentModelPath = path
        // Drop the old model first so its GPU memory is freed before the new one
        // loads (otherwise both are briefly resident). Blocks dictation until ready.
        transcriber = nil
        let loadingFrom = hotkey.isActive ? "hold right-Option to dictate" : nil
        statusMenuItem?.title = "gab — loading \((path as NSString).lastPathComponent)…"

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let t = Transcriber(modelPath: path)
            DispatchQueue.main.async {
                guard let self else { return }
                // Ignore if the user switched again while this was loading.
                guard self.currentModelPath == path else { return }
                self.transcriber = t
                if t == nil {
                    self.statusMenuItem?.title = "gab — model failed to load"
                } else if let loadingFrom {
                    self.statusMenuItem?.title = "gab — \(loadingFrom)"
                } else {
                    self.statusMenuItem?.title = "gab — ready"
                }
            }
        }
    }

    // MARK: - Hotkey wiring

    private func startHotkey() {
        hotkey.onPress = { [weak self] in self?.beginDictation() }
        hotkey.onRelease = { [weak self] in self?.endDictation() }
        attemptEnableHotkey(promptIfNeeded: true)
    }

    /// Create the event tap once Accessibility is granted. While it isn't, poll
    /// (the grant can land without an app restart) and enable the tap the moment
    /// it does — so the user never has to manually relaunch after toggling it on.
    private func attemptEnableHotkey(promptIfNeeded: Bool = false) {
        guard !hotkey.isActive else { return }

        if isTrusted(prompt: promptIfNeeded) {
            if hotkey.start() {
                trustTimer?.invalidate(); trustTimer = nil
                statusMenuItem?.title = "gab — hold right-Option to dictate"
                NSLog("gab: hotkey active")
            } else {
                statusMenuItem?.title = "gab — event tap failed (see Console)"
                NSLog("gab: event tap creation failed despite Accessibility trust")
            }
            return
        }

        statusMenuItem?.title = "gab — needs Accessibility permission"
        NSLog("gab: waiting for Accessibility permission…")
        if trustTimer == nil {
            trustTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
                self?.attemptEnableHotkey()
            }
        }
    }

    private func beginDictation() {
        guard !busy, transcriber != nil else { return }
        do {
            try audio.start()
            setIcon(listening: true)
        } catch {
            NSLog("gab: audio start failed: \(error)")
        }
    }

    private func endDictation() {
        let samples = audio.stop()
        setIcon(listening: false)

        let duration = Double(samples.count) / sampleRate
        guard duration >= minDurationSeconds else { return } // drop quick taps / silence
        guard let transcriber else { return }

        busy = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let text = transcriber.transcribe(samples)
            DispatchQueue.main.async {
                self?.busy = false
                Paster.paste(text)
            }
        }
    }

    // MARK: - Helpers

    private func presentAlert(title: String, text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.alertStyle = .warning
        alert.runModal()
    }
}
