import Foundation

/// DeviceSpoofManager - Manages device identity spoofing
/// Allows changing device model and system version reported to Telegram servers
public final class DeviceSpoofManager {
    public static let shared = DeviceSpoofManager()
    
    // MARK: - Device Profile
    
    public struct DeviceProfile: Equatable {
        public let id: Int
        public let name: String
        public let deviceModel: String
        public let systemVersion: String
        
        public init(id: Int, name: String, deviceModel: String, systemVersion: String) {
            self.id = id
            self.name = name
            self.deviceModel = deviceModel
            self.systemVersion = systemVersion
        }
    }
    
    // MARK: - Preset Profiles
    
    public static let profiles: [DeviceProfile] = [
        DeviceProfile(id: 0, name: "Реальное устройство", deviceModel: "", systemVersion: ""),
        DeviceProfile(id: 1, name: "iPhone 14 Pro", deviceModel: "iPhone 14 Pro", systemVersion: "iOS 17.2"),
        DeviceProfile(id: 2, name: "iPhone 15 Pro Max", deviceModel: "iPhone 15 Pro Max", systemVersion: "iOS 17.4"),
        DeviceProfile(id: 3, name: "Samsung Galaxy S23", deviceModel: "Samsung SM-S918B", systemVersion: "Android 14"),
        DeviceProfile(id: 4, name: "Google Pixel 8", deviceModel: "Google Pixel 8 Pro", systemVersion: "Android 14"),
        DeviceProfile(id: 5, name: "Desktop Windows", deviceModel: "PC 64bit", systemVersion: "Windows 11"),
        DeviceProfile(id: 6, name: "Desktop macOS", deviceModel: "MacBook Pro", systemVersion: "macOS 14.3"),
        DeviceProfile(id: 7, name: "Telegram Web", deviceModel: "Web", systemVersion: "Chrome 121"),
        DeviceProfile(id: 8, name: "Huawei P60 Pro", deviceModel: "HUAWEI MNA-LX9", systemVersion: "HarmonyOS 4.0"),
        DeviceProfile(id: 9, name: "Xiaomi 14", deviceModel: "Xiaomi 2311DRK48G", systemVersion: "Android 14"),
        DeviceProfile(id: 100, name: "Своё устройство", deviceModel: "", systemVersion: "")
    ]
    
    // MARK: - Keys
    
    private enum Keys {
        static let isEnabled = "DeviceSpoof.isEnabled"
        static let hasExplicitConfiguration = "DeviceSpoof.hasExplicitConfiguration"
        static let selectedProfileId = "DeviceSpoof.selectedProfileId"
        static let customDeviceModel = "DeviceSpoof.customDeviceModel"
        static let customSystemVersion = "DeviceSpoof.customSystemVersion"
    }

    private struct ResolvedConfiguration {
        let isEnabled: Bool
        let selectedProfileId: Int
        let customDeviceModel: String
        let customSystemVersion: String
    }

    private static let validProfileIds = Set(profiles.map { $0.id })
    
    private let defaults = UserDefaults.standard
    
    // MARK: - Properties
    
    /// Whether device spoofing is enabled
    public var isEnabled: Bool {
        get {
            let configuration = resolvedConfiguration()
            return configuration.isEnabled
        }
        set {
            defaults.set(newValue, forKey: Keys.isEnabled)
            notifyChanged()
        }
    }

    /// Whether the current spoofing configuration was explicitly set by the user
    public var hasExplicitConfiguration: Bool {
        get { defaults.bool(forKey: Keys.hasExplicitConfiguration) }
        set {
            defaults.set(newValue, forKey: Keys.hasExplicitConfiguration)
            notifyChanged()
        }
    }
    
    /// Selected profile ID (0 = real device, 100 = custom)
    public var selectedProfileId: Int {
        get {
            sanitizeStoredConfiguration()
            return defaults.integer(forKey: Keys.selectedProfileId)
        }
        set {
            defaults.set(newValue, forKey: Keys.selectedProfileId)
            sanitizeStoredConfiguration()
            notifyChanged()
        }
    }
    
    /// Custom device model (when profile ID = 100)
    public var customDeviceModel: String {
        get { defaults.string(forKey: Keys.customDeviceModel) ?? "" }
        set {
            defaults.set(newValue, forKey: Keys.customDeviceModel)
            notifyChanged()
        }
    }
    
    /// Custom system version (when profile ID = 100)
    public var customSystemVersion: String {
        get { defaults.string(forKey: Keys.customSystemVersion) ?? "" }
        set {
            defaults.set(newValue, forKey: Keys.customSystemVersion)
            notifyChanged()
        }
    }
    
    // MARK: - Computed
    
    /// Get the currently effective device model
    public var effectiveDeviceModel: String? {
        let configuration = resolvedConfiguration()
        guard configuration.isEnabled else {
            return nil
        }

        if configuration.selectedProfileId == 100 {
            guard !configuration.customDeviceModel.isEmpty, !configuration.customSystemVersion.isEmpty else {
                return nil
            }
            return configuration.customDeviceModel
        }

        if let profile = Self.profiles.first(where: { $0.id == configuration.selectedProfileId }), profile.id != 0 {
            return profile.deviceModel.isEmpty ? nil : profile.deviceModel
        }
        
        return nil
    }
    
    /// Get the currently effective system version
    public var effectiveSystemVersion: String? {
        let configuration = resolvedConfiguration()
        guard configuration.isEnabled else {
            return nil
        }

        if configuration.selectedProfileId == 100 {
            guard !configuration.customDeviceModel.isEmpty, !configuration.customSystemVersion.isEmpty else {
                return nil
            }
            return configuration.customSystemVersion
        }

        if let profile = Self.profiles.first(where: { $0.id == configuration.selectedProfileId }), profile.id != 0 {
            return profile.systemVersion.isEmpty ? nil : profile.systemVersion
        }
        
        return nil
    }
    
    /// Get selected profile
    public var selectedProfile: DeviceProfile? {
        return Self.profiles.first(where: { $0.id == selectedProfileId })
    }
    
    // MARK: - Notification
    
    public static let settingsChangedNotification = Notification.Name("DeviceSpoofSettingsChanged")
    
    private func notifyChanged() {
        NotificationCenter.default.post(name: Self.settingsChangedNotification, object: nil)
    }

    private func sanitizeStoredConfiguration() {
        let rawSelectedProfileId = defaults.integer(forKey: Keys.selectedProfileId)
        if !Self.validProfileIds.contains(rawSelectedProfileId) {
            defaults.set(0, forKey: Keys.selectedProfileId)
        }

        let rawCustomDeviceModel = defaults.string(forKey: Keys.customDeviceModel) ?? ""
        let trimmedCustomDeviceModel = rawCustomDeviceModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if rawCustomDeviceModel != trimmedCustomDeviceModel {
            defaults.set(trimmedCustomDeviceModel, forKey: Keys.customDeviceModel)
        }

        let rawCustomSystemVersion = defaults.string(forKey: Keys.customSystemVersion) ?? ""
        let trimmedCustomSystemVersion = rawCustomSystemVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        if rawCustomSystemVersion != trimmedCustomSystemVersion {
            defaults.set(trimmedCustomSystemVersion, forKey: Keys.customSystemVersion)
        }
    }

    private func resolvedConfiguration() -> ResolvedConfiguration {
        sanitizeStoredConfiguration()

        return ResolvedConfiguration(
            isEnabled: defaults.bool(forKey: Keys.hasExplicitConfiguration) && defaults.bool(forKey: Keys.isEnabled),
            selectedProfileId: defaults.integer(forKey: Keys.selectedProfileId),
            customDeviceModel: defaults.string(forKey: Keys.customDeviceModel) ?? "",
            customSystemVersion: defaults.string(forKey: Keys.customSystemVersion) ?? ""
        )
    }
    
    // MARK: - Init
    
    private init() {
        sanitizeStoredConfiguration()
    }
}
