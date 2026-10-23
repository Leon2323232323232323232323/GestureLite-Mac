import AppKit
import ApplicationServices
import SwiftUI

struct GestureBinding: Codable, Identifiable {
    var trigger: String
    var tapPassthrough: Bool
    var clickAction: String? = nil
    var left: String? = nil
    var right: String? = nil
    var up: String? = nil
    var down: String? = nil
    var id: String { trigger }
}
struct GestureConfiguration: Codable {
    var schema: Int = 1
    var enabled = false
    var distance: Double = 360
    var dominance: Double = 1.25
    var bindings: [GestureBinding] = [
        .init(trigger: "Mouse4", tapPassthrough: true, left: "CMD+[", right: "CMD+]"),
        .init(trigger: "Mouse5", tapPassthrough: true, left: "CTRL+LEFT", right: "CTRL+RIGHT", up: "CTRL+UP", down: "CTRL+DOWN")
    ]
    static func encode(_ config: Self) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(config)
    }
}
enum ConfigurationError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

// Settings and the event tap are confined to the main run loop.
final class AppModel: ObservableObject {
    @Published var draft = GestureConfiguration()
    @Published var status = "Gestures are disabled. Configure them, then enable explicitly."
    @Published var running = false
    let directory: URL
    let file: URL
    var engine: OpaquePointer
    var input: InputMonitor!
    var onRunningChanged: (() -> Void)?
    private var originalData: Data?
    private var active = GestureConfiguration()

    init() {
        directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GestureLite", isDirectory: true)
        file = directory.appendingPathComponent("config.json")
        engine = gl_new()!
        input = InputMonitor(model: self)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: file.path) {
                let data = try Data(contentsOf: file)
                guard data.count <= 65_536 else { throw ConfigurationError.message("Configuration exceeds 64 KiB.") }
                draft = try JSONDecoder().decode(GestureConfiguration.self, from: data)
                originalData = data
            } else {
                let data = try GestureConfiguration.encode(draft)
                try data.write(to: file, options: .atomic)
                originalData = data
            }
            // Never activate global input hooks just by launching or reading JSON.
            var safe = draft
            safe.enabled = false
            try configure(safe, on: engine)
            active = safe
            draft.enabled = false
        } catch {
            draft = GestureConfiguration()
            status = "Configuration was not loaded: \(error.localizedDescription). Original file preserved."
        }
    }
    deinit { input.stop(); gl_free(engine) }

    private func configure(_ config: GestureConfiguration, on handle: OpaquePointer) throws {
        let data = try GestureConfiguration.encode(config)
        guard let json = String(data: data, encoding: .utf8) else { throw ConfigurationError.message("Invalid UTF-8") }
        let ok = json.withCString { gl_configure(handle, $0) }
        if ok == 0 {
            let reason = gl_error(handle).map { String(cString: $0) } ?? "Invalid configuration"
            throw ConfigurationError.message(reason)
        }
    }
    func save() {
        do {
            // Validate against a disposable engine first, leaving live holds untouched.
            let temporary = gl_new()!
            defer { gl_free(temporary) }
            var candidate = draft
            candidate.enabled = running
            try configure(candidate, on: temporary)
            let current = try Data(contentsOf: file)
            guard current == originalData else {
                throw ConfigurationError.message("config.json changed outside Settings. Reopen the app before saving; external changes were preserved.")
            }
            let data = try GestureConfiguration.encode(candidate)
            let backup = directory.appendingPathComponent("config.backup-\(UUID().uuidString).json")
            try current.write(to: backup, options: .withoutOverwriting)
            try data.write(to: file, options: .atomic)
            originalData = data
            try configure(candidate, on: engine)
            active = candidate
            draft = candidate
            status = "Saved. Click actions run on release; gestures still run once per press."
        } catch { status = "Not saved: \(error.localizedDescription)" }
    }
    func setEnabled(_ enabled: Bool) {
        if !enabled {
            gl_disable(engine)
            running = false
            draft.enabled = false
            active.enabled = false
            status = "Gestures disabled. Pending holds were cancelled."
            onRunningChanged?()
            return
        }
        do {
            // Enabling uses the saved/applied mappings, not an unvalidated editor draft.
            var config = active
            config.enabled = true
            try input.start()
            try configure(config, on: engine)
            running = true
            draft.enabled = true
            active = config
            status = "Gestures enabled. Release all trigger buttons before starting a gesture."
        } catch {
            input.stop()
            gl_disable(engine)
            running = false
            draft.enabled = false
            status = error.localizedDescription
        }
        onRunningChanged?()
    }
    func inputFailed(_ reason: String) {
        gl_disable(engine)
        running = false
        draft.enabled = false
        active.enabled = false
        status = "Gestures stopped: \(reason). Release trigger buttons, then enable again."
        onRunningChanged?()
    }
    func requestPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        _ = CGRequestListenEventAccess()
        _ = CGRequestPostEventAccess()
        status = "Review macOS Privacy & Security permissions for GestureLite, then return and enable gestures."
    }
    func openConfiguration() { NSWorkspace.shared.open(file) }
    func logFailure(_ text: String) {
        // Only operational failures; no key streams, pointer history or telemetry.
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(text)\n"
        let log = directory.appendingPathComponent("gesturelite.log")
        if let size = try? log.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 262_144 {
            try? FileManager.default.removeItem(at: log.appendingPathExtension("previous"))
            try? FileManager.default.moveItem(at: log, to: log.appendingPathExtension("previous"))
        }
        if !FileManager.default.fileExists(atPath: log.path) { FileManager.default.createFile(atPath: log.path, contents: nil) }
        if let handle = try? FileHandle(forWritingTo: log) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
        }
    }
}
