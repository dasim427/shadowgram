import Foundation

// Shadowgram: what a video call sends instead of (or on top of) the plain camera.
public enum SGCallVideoMode: Int, CaseIterable {
    /// The normal camera.
    case off = 0
    /// A picture, GIF or video from the gallery instead of the camera.
    case media = 1
    /// The front camera with the active mask.
    case maskedCamera = 2

    public var title: String {
        switch self {
        case .off:
            return "Обычная камера"
        case .media:
            return "Картинка, GIF или видео"
        case .maskedCamera:
            return "Камера с маской"
        }
    }
}

public enum SGCallVideoStore {
    private static let modeKey = "SG.callVideo.mode"
    private static let fileKey = "SG.callVideo.file"

    public static var directory: String {
        return NSHomeDirectory() + "/Documents/SGCallVideo"
    }

    public static var mode: SGCallVideoMode {
        get {
            return SGCallVideoMode(rawValue: UserDefaults.standard.integer(forKey: self.modeKey)) ?? .off
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: self.modeKey)
        }
    }

    /// Full path of the picked media, if any.
    public static var mediaPath: String? {
        guard let name = UserDefaults.standard.string(forKey: self.fileKey) else {
            return nil
        }
        let path = self.directory + "/" + name
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    public static var mediaIsVideo: Bool {
        guard let path = self.mediaPath else {
            return false
        }
        let ext = (path as NSString).pathExtension.lowercased()
        return ext == "mp4" || ext == "mov" || ext == "m4v"
    }

    /// Copies a picked file in, keeping its extension so pictures and videos can be told apart.
    @discardableResult
    public static func storeMedia(from url: URL) -> Bool {
        let ext = url.pathExtension.isEmpty ? "dat" : url.pathExtension.lowercased()
        let name = "source." + ext
        let _ = try? FileManager.default.removeItem(atPath: self.directory)
        let _ = try? FileManager.default.createDirectory(atPath: self.directory, withIntermediateDirectories: true, attributes: nil)
        do {
            try FileManager.default.copyItem(at: url, to: URL(fileURLWithPath: self.directory + "/" + name))
        } catch {
            return false
        }
        UserDefaults.standard.set(name, forKey: self.fileKey)
        return true
    }

    public static func removeMedia() {
        let _ = try? FileManager.default.removeItem(atPath: self.directory)
        UserDefaults.standard.removeObject(forKey: self.fileKey)
        if self.mode == .media {
            self.mode = .off
        }
    }
}
