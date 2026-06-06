import Foundation

enum ThumbnailCorner: String, CaseIterable, Codable {
    case bottomLeft
    case bottomRight
    case topLeft
    case topRight

    var displayName: String {
        switch self {
        case .bottomLeft: return "Bottom Left"
        case .bottomRight: return "Bottom Right"
        case .topLeft: return "Top Left"
        case .topRight: return "Top Right"
        }
    }

    var systemImage: String {
        switch self {
        case .bottomLeft: return "arrow.down.left"
        case .bottomRight: return "arrow.down.right"
        case .topLeft: return "arrow.up.left"
        case .topRight: return "arrow.up.right"
        }
    }
}

enum SaveLocation: String, CaseIterable, Codable {
    case desktop
    case custom
    case clipboardOnly

    var displayName: String {
        switch self {
        case .desktop: return "Desktop"
        case .custom: return "Custom Folder"
        case .clipboardOnly: return "Clipboard Only"
        }
    }

    var systemImage: String {
        switch self {
        case .desktop: return "desktopcomputer"
        case .custom: return "folder"
        case .clipboardOnly: return "clipboard"
        }
    }
}

// MARK: - Settings Keys

enum SettingsKey: String {
    case thumbnailCorner = "thumbnailCorner"
    case saveLocation = "saveLocation"
    case customSaveDirectory = "customSaveDirectory"
    case isRainbowMode = "isRainbowMode"
}

// MARK: - SettingsStore

/// Centralized settings manager. All reads/writes go through UserDefaults directly.
/// Thread-safe for reads. Writes should happen on main thread.
final class SettingsStore {

    static let shared = SettingsStore()
    private let defaults = UserDefaults.standard

    var thumbnailCorner: ThumbnailCorner {
        let raw = defaults.string(forKey: SettingsKey.thumbnailCorner.rawValue) ?? ""
        return ThumbnailCorner(rawValue: raw) ?? .bottomLeft
    }

    var saveLocation: SaveLocation {
        let raw = defaults.string(forKey: SettingsKey.saveLocation.rawValue) ?? ""
        return SaveLocation(rawValue: raw) ?? .desktop
    }

    var customSaveDirectory: String {
        defaults.string(forKey: SettingsKey.customSaveDirectory.rawValue) ?? ""
    }

    var isRainbowMode: Bool {
        defaults.bool(forKey: SettingsKey.isRainbowMode.rawValue)
    }

    var outputDirectory: URL? {
        switch saveLocation {
        case .desktop:
            return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        case .custom:
            guard !customSaveDirectory.isEmpty else {
                return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
            }
            return URL(fileURLWithPath: customSaveDirectory)
        case .clipboardOnly:
            return nil
        }
    }

    // MARK: - Explicit Writes

    func setThumbnailCorner(_ value: ThumbnailCorner) {
        defaults.set(value.rawValue, forKey: SettingsKey.thumbnailCorner.rawValue)
        defaults.synchronize()
    }

    func setSaveLocation(_ value: SaveLocation) {
        defaults.set(value.rawValue, forKey: SettingsKey.saveLocation.rawValue)
        defaults.synchronize()
    }

    func setCustomSaveDirectory(_ value: String) {
        defaults.set(value, forKey: SettingsKey.customSaveDirectory.rawValue)
        defaults.synchronize()
    }

    func setRainbowMode(_ value: Bool) {
        defaults.set(value, forKey: SettingsKey.isRainbowMode.rawValue)
        defaults.synchronize()
    }
}
