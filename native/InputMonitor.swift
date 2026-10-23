import AppKit
import ApplicationServices

private let inputCallback: CGEventTapCallBack = { _, type, event, context in
    guard let context = context else { return Unmanaged.passUnretained(event) }
    return Unmanaged<InputMonitor>.fromOpaque(context).takeUnretainedValue().handle(type, event)
}

final class InputMonitor {
    unowned let model: AppModel
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private var observers: [NSObjectProtocol] = []
    private let eventSource = CGEventSource(stateID: .combinedSessionState)

    init(model: AppModel) {
        self.model = model
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.stop()
                self?.model.inputFailed("session ended or Mac went to sleep")
            })
        }
    }
    deinit {
        stop()
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }
    func start() throws {
        guard AXIsProcessTrusted(), CGPreflightListenEventAccess(), CGPreflightPostEventAccess() else {
            throw ConfigurationError.message("Permission is required. Choose Request Permissions, allow Accessibility/Input Monitoring as requested by macOS, then enable again.")
        }
        if let port = port, CGEvent.tapIsEnabled(tap: port) { return }
        stop()
        let types: [CGEventType] = [.otherMouseDown, .otherMouseUp, .mouseMoved, .otherMouseDragged, .leftMouseDragged, .rightMouseDragged, .keyDown, .keyUp]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: mask, callback: inputCallback,
                                        userInfo: Unmanaged.passUnretained(self).toOpaque()),
              let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            throw ConfigurationError.message("macOS did not create the input event tap. Check permissions and relaunch the app.")
        }
        port = tap
        source = runLoopSource
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }
    func stop() {
        if let port = port { CGEvent.tapEnable(tap: port, enable: false) }
        if let source = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let port = port { CFMachPortInvalidate(port) }
        source = nil
        port = nil
    }
    func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // Fail closed; never automatically resume a half-finished gesture.
            model.inputFailed("macOS disabled the input tap")
            return Unmanaged.passUnretained(event)
        }
        if gl_is_own(event.getIntegerValueField(.eventSourceUserData)) != 0 { return Unmanaged.passUnretained(event) }
        var kind: UInt32
        var code: UInt32 = 0
        switch type {
        case .otherMouseDown, .otherMouseUp:
            kind = type == .otherMouseDown ? 1 : 2
            code = UInt32(clamping: event.getIntegerValueField(.mouseEventButtonNumber))
        case .keyDown, .keyUp:
            kind = type == .keyDown ? 4 : 5
            code = UInt32(clamping: event.getIntegerValueField(.keyboardEventKeycode))
        case .mouseMoved, .otherMouseDragged, .leftMouseDragged, .rightMouseDragged:
            kind = 3
        default: return Unmanaged.passUnretained(event)
        }
        let point = event.location
        let result = gl_process(model.engine, kind, code, point.x, point.y)
        if result.kind != 0 && !send(result, point: point, releasedKey: kind == 5 ? code : nil) {
            // Never do filesystem work inside the event-tap callback.
            model.inputFailed("could not prepare or submit input; nothing will be retried")
            DispatchQueue.main.async { [weak self] in self?.model.logFailure("Input generation failed; gestures disabled") }
        }
        return result.suppress != 0 ? nil : Unmanaged.passUnretained(event)
    }
    private func send(_ result: GlOutcome, point: CGPoint, releasedKey: UInt32?) -> Bool {
        guard CGPreflightPostEventAccess() else { return false }
        let down: CGEvent
        let up: CGEvent
        if result.kind == 2 {
            // CGMouseButton exposes only left/right/center by name. Set the actual
            // extra-button number explicitly on a valid other-button event.
            guard let d = CGEvent(mouseEventSource: eventSource, mouseType: .otherMouseDown, mouseCursorPosition: point, mouseButton: .center),
                  let u = CGEvent(mouseEventSource: eventSource, mouseType: .otherMouseUp, mouseCursorPosition: point, mouseButton: .center) else { return false }
            d.setIntegerValueField(.mouseEventButtonNumber, value: Int64(result.code))
            u.setIntegerValueField(.mouseEventButtonNumber, value: Int64(result.code))
            down = d; up = u
        } else if result.kind == 1 || result.kind == 3 {
            guard result.code <= UInt32(UInt16.max) else { return false }
            let code = CGKeyCode(result.code)
            // Preserve real held keys: do not send a key-up for a physical target.
            // A trigger's own key-up can arrive before the async state catches up.
            // Replay of that released key is intentional, unlike another held target.
            if result.kind == 1 && releasedKey != result.code && CGEventSource.keyState(.combinedSessionState, key: code) { return true }
            guard let d = CGEvent(keyboardEventSource: eventSource, virtualKey: code, keyDown: true),
                  let u = CGEvent(keyboardEventSource: eventSource, virtualKey: code, keyDown: false) else { return false }
            down = d; up = u
        } else { return false }
        // Attach modifiers to the complete pair; never inject modifier key-downs.
        // This cannot leave a synthetic Command/Ctrl key held between actions.
        let modifiers = CGEventSource.flagsState(.combinedSessionState).union(CGEventFlags(rawValue: result.flags))
        down.flags = modifiers; up.flags = modifiers
        down.setIntegerValueField(.eventSourceUserData, value: gl_marker())
        up.setIntegerValueField(.eventSourceUserData, value: gl_marker())
        // Both events exist before either is posted. CGEvent.post has no delivery
        // result; certification/runtime checks must verify actual target behavior.
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}
