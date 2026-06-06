import AppKit

// MARK: - ShortcutAction

enum ShortcutAction: String, CaseIterable {
    case captureFullscreen = "captureFullscreen"
    case captureArea = "captureArea"
    case captureWindow = "captureWindow"
    case openScreenshotApp = "openScreenshotApp"
    
    var displayName: String {
        switch self {
        case .captureFullscreen: return "Capture Fullscreen"
        case .captureArea: return "Capture Selected Area"
        case .captureWindow: return "Capture Selected Window"
        case .openScreenshotApp: return "Open Screenshot App"
        }
    }
    
    var systemImage: String {
        switch self {
        case .captureFullscreen: return "rectangle.fill"
        case .captureArea: return "crop"
        case .captureWindow: return "macwindow"
        case .openScreenshotApp: return "slider.horizontal.3"
        }
    }
    
    var defaultKeyCode: UInt16 {
        switch self {
        case .captureFullscreen: return 0x14 // 3
        case .captureArea: return 0x15 // 4
        case .captureWindow: return 0x15 // 4 (with space)
        case .openScreenshotApp: return 0x17 // 5
        }
    }
    
    var defaultModifiers: NSEvent.ModifierFlags {
        switch self {
        case .captureFullscreen: return [.command, .shift]
        case .captureArea: return [.command, .shift]
        case .captureWindow: return [.command, .shift]
        case .openScreenshotApp: return [.command, .shift]
        }
    }
}

// MARK: - ShortcutConfig

struct ShortcutConfig: Codable {
    let action: String
    var keyCode: UInt16
    var modifierFlags: UInt
    var isEnabled: Bool
    
    var actionEnum: ShortcutAction? {
        ShortcutAction(rawValue: action)
    }
    
    var modifiers: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierFlags)
    }
    
    func matches(event: NSEvent) -> Bool {
        guard isEnabled else { return false }
        return event.keyCode == keyCode && event.modifierFlags.intersection(.deviceIndependentFlagsMask) == modifiers
    }
    
    var displayString: String {
        var parts: [String] = []
        let mods = modifiers
        if mods.contains(.command) { parts.append("⌘") }
        if mods.contains(.option) { parts.append("⌥") }
        if mods.contains(.control) { parts.append("⌃") }
        if mods.contains(.shift) { parts.append("⇧") }
        parts.append(keyCodeToString(keyCode))
        return parts.joined()
    }
}

// MARK: - ShortcutStore

final class ShortcutStore {

    static let shared = ShortcutStore()
    private let defaults = UserDefaults.standard
    private let key = "shortcutConfigs"

    /// Cached configs to avoid JSON decode on every keydown event
    private var cachedConfigs: [ShortcutConfig]?

    var configs: [ShortcutConfig] {
        get {
            if let cached = cachedConfigs { return cached }
            guard let data = defaults.data(forKey: key),
                  let decoded = try? JSONDecoder().decode([ShortcutConfig].self, from: data) else {
                let defaults = defaultConfigs()
                cachedConfigs = defaults
                return defaults
            }
            cachedConfigs = decoded
            return decoded
        }
        set {
            cachedConfigs = newValue
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: key)
                defaults.synchronize()
            }
        }
    }
    
    func config(for action: ShortcutAction) -> ShortcutConfig? {
        configs.first { $0.action == action.rawValue }
    }
    
    func update(action: ShortcutAction, keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        var current = configs
        if let index = current.firstIndex(where: { $0.action == action.rawValue }) {
            current[index].keyCode = keyCode
            current[index].modifierFlags = modifiers.rawValue
            configs = current
        }
    }
    
    func resetToDefaults() {
        configs = defaultConfigs()
    }
    
    private func defaultConfigs() -> [ShortcutConfig] {
        ShortcutAction.allCases.map { action in
            ShortcutConfig(
                action: action.rawValue,
                keyCode: action.defaultKeyCode,
                modifierFlags: action.defaultModifiers.rawValue,
                isEnabled: true
            )
        }
    }
}

// MARK: - Key Code to String

private func keyCodeToString(_ keyCode: UInt16) -> String {
    let map: [UInt16: String] = [
        0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H",
        0x05: "G", 0x06: "Z", 0x07: "X", 0x08: "C", 0x09: "V",
        0x0B: "B", 0x0C: "Q", 0x0D: "W", 0x0E: "E", 0x0F: "R",
        0x10: "Y", 0x11: "T", 0x12: "1", 0x13: "2", 0x14: "3",
        0x15: "4", 0x16: "6", 0x17: "5", 0x18: "=", 0x19: "9",
        0x1A: "7", 0x1B: "-", 0x1C: "8", 0x1D: "0", 0x1E: "]",
        0x1F: "O", 0x20: "U", 0x21: "[", 0x22: "I", 0x23: "P",
        0x25: "L", 0x26: "J", 0x27: "'", 0x28: "K", 0x29: ";",
        0x2A: "\\", 0x2B: ",", 0x2C: "/", 0x2D: "N", 0x2E: "M",
        0x2F: ".", 0x32: "`", 0x24: "Return", 0x30: "Tab",
        0x31: "Space", 0x33: "Delete", 0x35: "Escape",
        0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4",
        0x60: "F5", 0x61: "F6", 0x62: "F7", 0x64: "F8",
        0x65: "F9", 0x6D: "F10", 0x67: "F11", 0x6F: "F12"
    ]
    return map[keyCode] ?? "Key \(keyCode)"
}
