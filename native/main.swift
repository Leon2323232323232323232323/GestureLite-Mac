import AppKit
import SwiftUI
import Darwin

// CI exercises the real Swift/C/Rust bridge without creating a window, requesting
// permissions, installing input hooks, posting events or touching user settings.
if CommandLine.arguments.contains("--self-test") {
    let handle = gl_new()!
    defer { gl_free(handle) }
    do {
        guard MemoryLayout<GlOutcome>.size == 24 else { throw ConfigurationError.message("C ABI layout mismatch") }
        var config = GestureConfiguration()
        config.enabled = true
        let data = try GestureConfiguration.encode(config)
        let json = String(data: data, encoding: .utf8)!
        guard json.withCString({ gl_configure(handle, $0) }) == 1 else { throw ConfigurationError.message("Swift defaults did not validate in Rust") }
        _ = gl_process(handle, 1, 4, 0, 0)
        let action = gl_process(handle, 3, 0, 360, 0)
        guard action.kind == 1, action.code == 124, action.flags == (1 << 18),
              gl_process(handle, 3, 0, 720, 0).kind == 0,
              gl_process(handle, 2, 4, 720, 0).kind == 0,
              gl_is_own(gl_marker()) == 1, gl_is_own(0x455f3031) == 1 else {
            throw ConfigurationError.message("Bridge gesture/replay regression")
        }
        print("Native Swift/C/Rust bridge self-test passed; no input events sent.")
    } catch { fputs("Native self-test failed: \(error.localizedDescription)\n", stderr); exit(1) }
    exit(0)
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel!
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var enableItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        model = AppModel()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "cursorarrow.motionlines", accessibilityDescription: "GestureLite")
            if button.image == nil { button.title = "GL" }
            button.toolTip = "GestureLite for Mac"
        }
        let menu = NSMenu()
        enableItem = NSMenuItem(title: "Enable Gestures", action: #selector(toggleEnabled), keyEquivalent: "")
        enableItem.target = self
        menu.addItem(enableItem)
        let settings = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self; menu.addItem(settings)
        let open = NSMenuItem(title: "Open Configuration", action: #selector(openConfiguration), keyEquivalent: "")
        open.target = self; menu.addItem(open)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit GestureLite", action: #selector(quit), keyEquivalent: "q")
        quit.target = self; menu.addItem(quit)
        statusItem.menu = menu
        model.onRunningChanged = { [weak self] in self?.updateMenu() }
        updateMenu()
        showSettings()
    }
    private func updateMenu() {
        enableItem.state = model.running ? .on : .off
        enableItem.title = model.running ? "Disable Gestures" : "Enable Gestures"
    }
    @objc private func toggleEnabled() { model.setEnabled(!model.running) }
    @objc private func openConfiguration() { model.openConfiguration() }
    @objc func showSettings() {
        if settingsWindow == nil {
            let view = NSHostingView(rootView: SettingsView(model: model))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 710, height: 640),
                                  styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "GestureLite Settings — Mac Preview"
            window.isReleasedWhenClosed = false
            window.contentView = view
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showSettings(); return true }
    func applicationWillTerminate(_ notification: Notification) { model.setEnabled(false); model.input.stop() }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
