import AppKit
import Carbon

// MARK: - Callback Bridge

/// Static callback bridge that holds a weak reference to the interceptor.
/// Prevents crashes if the interceptor is deallocated while the event tap is still active.
private final class HotkeyInterceptorBridge {
    static let shared = HotkeyInterceptorBridge()
    weak var interceptor: HotkeyInterceptor?

    static let callback: CGEventTapCallBack = { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
        guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
        let bridge = Unmanaged<HotkeyInterceptorBridge>.fromOpaque(refcon).takeUnretainedValue()
        guard let interceptor = bridge.interceptor else { return Unmanaged.passUnretained(event) }
        return interceptor.handleEvent(proxy: proxy, type: type, event: event)
    }
}

// MARK: - Hotkey Interceptor

final class HotkeyInterceptor {

    // MARK: - Types

    enum ScreenshotMode {
        case fullscreen
        case areaSelection
        case windowSelection
        case screenshotApp
    }

    // MARK: - Properties

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isIntercepting = false

    var onScreenshotHotkey: ((ScreenshotMode) -> Void)?

    // MARK: - Lifecycle

    deinit {
        stopIntercepting()
    }

    // MARK: - Public

    func startIntercepting() {
        guard !isIntercepting else { return }

        guard AXIsProcessTrusted() else {
            requestAccessibilityPermission()
            return
        }

        if Thread.isMainThread {
            installEventTap()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.installEventTap()
            }
        }
    }

    func stopIntercepting() {
        guard isIntercepting else { return }

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
        }
        eventTap = nil
        runLoopSource = nil
        isIntercepting = false

        NSLog("[HotkeyInterceptor] Stopped intercepting")
    }

    // MARK: - Accessibility Permission

    static func checkAccessibilityPermission() -> Bool {
        return AXIsProcessTrusted()
    }

    private func requestAccessibilityPermission() {
        NSLog("[HotkeyInterceptor] Accessibility permission not granted")

        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Accessibility Permission Required"
            alert.informativeText = "ScreenShoot needs Accessibility access to intercept screenshot shortcuts.\n\nPlease:\n1. Open System Settings → Privacy & Security → Accessibility\n2. Enable ScreenShoot\n3. Restart the app"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Later")

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    // MARK: - Event Tap Installation

    private func installEventTap() {
        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)

        HotkeyInterceptorBridge.shared.interceptor = self

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: HotkeyInterceptorBridge.callback,
            userInfo: Unmanaged.passUnretained(HotkeyInterceptorBridge.shared).toOpaque()
        ) else {
            NSLog("[HotkeyInterceptor] Failed to create event tap. Accessibility permission may not be granted.")
            requestAccessibilityPermission()
            return
        }

        self.eventTap = tap

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        isIntercepting = true
        NSLog("[HotkeyInterceptor] Started intercepting screenshot shortcuts")
    }

    // MARK: - Event Handling

    fileprivate func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        let store = ShortcutStore.shared

        for config in store.configs where config.isEnabled {
            guard config.keyCode == keyCode else { continue }

            let eventModifiers = NSEvent.ModifierFlags(rawValue: UInt(flags.rawValue))
                .intersection(.deviceIndependentFlagsMask)
            let configModifiers = config.modifiers
                .intersection(.deviceIndependentFlagsMask)

            guard eventModifiers == configModifiers else { continue }

            guard let action = config.actionEnum else { continue }

            let mode: ScreenshotMode?
            switch action {
            case .captureFullscreen:
                mode = .fullscreen
            case .captureArea:
                mode = .areaSelection
            case .captureWindow:
                mode = .windowSelection
            case .openScreenshotApp:
                mode = .screenshotApp
            }

            if let mode = mode {
                NSLog("[HotkeyInterceptor] Intercepted: \(action.displayName) -> \(mode)")

                DispatchQueue.main.async { [weak self] in
                    self?.onScreenshotHotkey?(mode)
                }

                return nil
            }
        }

        return Unmanaged.passUnretained(event)
    }
}
