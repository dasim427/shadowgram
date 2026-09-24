import Foundation

// Shadowgram: masks for round videos (and later video calls). A mask is an ordered list
// of layers — face effects, face distortions, color filters, background replacement and
// pictures — computed on the device. Masks are JSON `.sgmask` files in Documents/SGMasks;
// the camera reads the active one through `SGMaskStore.activeMask()`.

public struct SGMaskLayer: Codable, Equatable {
    public enum Kind: String, Codable, CaseIterable {
        // Face
        case blurFace
        case pixelateFace
        case emojiFace
        case swapFace
        case spotlight
        case faceVignette
        // Face shape
        case bigEyes
        case smallEyes
        case bigNose
        case bigMouth
        case longChin
        case narrowFace
        case wideFace
        case bulgeFace
        case pinchFace
        // Whole frame
        case colorFilter
        case adjust
        case overlayImage
        // Background (needs iOS 15)
        case blurBackground
        case colorBackground
        case imageBackground

        public var title: String {
            switch self {
            case .blurFace: return "Размыть лицо"
            case .pixelateFace: return "Пикселизовать лицо"
            case .emojiFace: return "Эмодзи на лицо"
            case .swapFace: return "Подменить лицо фото"
            case .spotlight: return "Прожектор на лицо"
            case .faceVignette: return "Виньетка вокруг лица"
            case .bigEyes: return "Большие глаза"
            case .smallEyes: return "Маленькие глаза"
            case .bigNose: return "Большой нос"
            case .bigMouth: return "Большой рот"
            case .longChin: return "Длинный подбородок"
            case .narrowFace: return "Узкое лицо"
            case .wideFace: return "Широкое лицо"
            case .bulgeFace: return "Выпуклое лицо"
            case .pinchFace: return "Втянутое лицо"
            case .colorFilter: return "Цветовой фильтр"
            case .adjust: return "Яркость, контраст, насыщенность"
            case .overlayImage: return "Картинка поверх"
            case .blurBackground: return "Размыть фон"
            case .colorBackground: return "Цвет вместо фона"
            case .imageBackground: return "Картинка вместо фона"
            }
        }

        public var needsFace: Bool {
            switch self {
            case .colorFilter, .adjust, .overlayImage, .blurBackground, .colorBackground, .imageBackground:
                return false
            default:
                return true
            }
        }

        /// Eyes, nose, mouth and chin need face landmarks; the rest only need the face box.
        public var needsLandmarks: Bool {
            switch self {
            case .bigEyes, .smallEyes, .bigNose, .bigMouth, .longChin:
                return true
            default:
                return false
            }
        }

        public var needsBackgroundSeparation: Bool {
            switch self {
            case .blurBackground, .colorBackground, .imageBackground:
                return true
            default:
                return false
            }
        }
    }

    public var id: String
    public var kind: Kind
    public var isEnabled: Bool
    /// Strength of the effect, 0...1.
    public var intensity: Double
    /// Color filter name, see `SGMaskColorFilter`.
    public var filter: String?
    /// -1...1, 0 is unchanged.
    public var brightness: Double
    public var contrast: Double
    public var saturation: Double
    /// 0xRRGGBB.
    public var color: Int
    /// Emoji for `.emojiFace`.
    public var text: String?
    /// PNG/JPEG for `.swapFace`, `.imageBackground` and `.overlayImage`.
    public var imageData: Data?
    /// Placement of `.overlayImage`, 0...1 of the frame.
    public var centerX: Double
    public var centerY: Double
    public var scale: Double
    /// Radians.
    public var rotation: Double

    public init(kind: Kind) {
        self.id = UUID().uuidString
        self.kind = kind
        self.isEnabled = true
        self.intensity = 0.7
        self.filter = kind == .colorFilter ? SGMaskColorFilter.mono.rawValue : nil
        self.brightness = 0.0
        self.contrast = 0.0
        self.saturation = 0.0
        self.color = 0x1C1238
        self.text = kind == .emojiFace ? "😎" : nil
        self.imageData = nil
        self.centerX = 0.5
        self.centerY = 0.5
        self.scale = 1.0
        self.rotation = 0.0
    }
}

public enum SGMaskColorFilter: String, CaseIterable {
    case mono
    case noir
    case sepia
    case chrome
    case fade
    case instant
    case process
    case transfer
    case tonal
    case invert
    case thermal
    case posterize
    case comic
    case crystal
    case halftone
    case pointillize
    case sketch
    case bloom
    case kaleidoscope

    public var title: String {
        switch self {
        case .mono: return "Чёрно-белый"
        case .noir: return "Нуар"
        case .sepia: return "Сепия"
        case .chrome: return "Хром"
        case .fade: return "Выцветший"
        case .instant: return "Полароид"
        case .process: return "Кросс-процесс"
        case .transfer: return "Летний"
        case .tonal: return "Тонированный"
        case .invert: return "Негатив"
        case .thermal: return "Тепловизор"
        case .posterize: return "Постеризация"
        case .comic: return "Комикс"
        case .crystal: return "Кристаллы"
        case .halftone: return "Полутона"
        case .pointillize: return "Пуантилизм"
        case .sketch: return "Набросок"
        case .bloom: return "Свечение"
        case .kaleidoscope: return "Калейдоскоп"
        }
    }
}

public struct SGMask: Codable, Equatable {
    public var id: String
    public var name: String
    public var layers: [SGMaskLayer]

    public init(id: String = UUID().uuidString, name: String, layers: [SGMaskLayer]) {
        self.id = id
        self.name = name
        self.layers = layers
    }

    /// At most this many layers, so the camera keeps up.
    public static let maxLayers = 8
}

public enum SGMaskStore {
    private static let activeKey = "SG.mask.active"
    private static let revisionKey = "SG.mask.revision"

    private static var directory: String {
        return NSHomeDirectory() + "/Documents/SGMasks"
    }

    private static func path(_ id: String) -> String {
        return self.directory + "/" + id + ".sgmask"
    }

    /// Bumped on every change so the camera knows to reload.
    public static var revision: Int {
        return UserDefaults.standard.integer(forKey: self.revisionKey)
    }

    private static func bumpRevision() {
        UserDefaults.standard.set(self.revision + 1, forKey: self.revisionKey)
    }

    public static func load() -> [SGMask] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: self.directory)) ?? []
        var result: [SGMask] = []
        for name in names where name.hasSuffix(".sgmask") {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: self.directory + "/" + name)), let mask = try? JSONDecoder().decode(SGMask.self, from: data) {
                result.append(mask)
            }
        }
        return result.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
    }

    @discardableResult
    public static func save(_ mask: SGMask) -> Bool {
        let _ = try? FileManager.default.createDirectory(atPath: self.directory, withIntermediateDirectories: true, attributes: nil)
        guard let data = try? JSONEncoder().encode(mask) else {
            return false
        }
        do {
            try data.write(to: URL(fileURLWithPath: self.path(mask.id)), options: .atomic)
        } catch {
            return false
        }
        self.bumpRevision()
        return true
    }

    public static func delete(_ mask: SGMask) {
        if self.activeId == mask.id {
            self.activeId = nil
        }
        let _ = try? FileManager.default.removeItem(atPath: self.path(mask.id))
        self.bumpRevision()
    }

    public static var activeId: String? {
        get {
            return UserDefaults.standard.string(forKey: self.activeKey)
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: self.activeKey)
            } else {
                UserDefaults.standard.removeObject(forKey: self.activeKey)
            }
            self.bumpRevision()
        }
    }

    public static func activeMask() -> SGMask? {
        guard let id = self.activeId, let data = try? Data(contentsOf: URL(fileURLWithPath: self.path(id))) else {
            return nil
        }
        return try? JSONDecoder().decode(SGMask.self, from: data)
    }

    /// A `.sgmask` file for sharing.
    public static func exportURL(_ mask: SGMask) -> URL? {
        guard let data = try? JSONEncoder().encode(mask) else {
            return nil
        }
        let safeName = mask.name.components(separatedBy: CharacterSet(charactersIn: "/:?%*|<>\"")).joined(separator: "_")
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + (safeName.isEmpty ? "mask" : safeName) + ".sgmask")
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            return nil
        }
        return url
    }

    /// Reads a shared `.sgmask`; the copy gets a new id so it never overwrites a mask.
    public static func importMask(data: Data) -> SGMask? {
        guard data.count < 30 * 1024 * 1024, var mask = try? JSONDecoder().decode(SGMask.self, from: data) else {
            return nil
        }
        mask.id = UUID().uuidString
        if mask.layers.count > SGMask.maxLayers {
            mask.layers = Array(mask.layers.prefix(SGMask.maxLayers))
        }
        return mask
    }

    /// Ready-made masks to start from.
    public static func presets() -> [SGMask] {
        func layer(_ kind: SGMaskLayer.Kind, intensity: Double = 0.7, _ configure: (inout SGMaskLayer) -> Void = { _ in }) -> SGMaskLayer {
            var value = SGMaskLayer(kind: kind)
            value.id = "preset-" + kind.rawValue
            value.intensity = intensity
            configure(&value)
            return value
        }
        func filter(_ name: SGMaskColorFilter) -> (inout SGMaskLayer) -> Void {
            return { layer in
                layer.filter = name.rawValue
            }
        }
        return [
            SGMask(id: "preset-blur", name: "Размытое лицо", layers: [layer(.blurFace, intensity: 0.8)]),
            SGMask(id: "preset-pixels", name: "Пиксели", layers: [layer(.pixelateFace, intensity: 0.6)]),
            SGMask(id: "preset-emoji", name: "Эмодзи вместо лица", layers: [layer(.emojiFace, intensity: 1.0)]),
            SGMask(id: "preset-eyes", name: "Большие глаза", layers: [layer(.bigEyes, intensity: 0.8)]),
            SGMask(id: "preset-alien", name: "Инопланетянин", layers: [layer(.bigEyes, intensity: 1.0), layer(.pinchFace, intensity: 0.5), layer(.colorFilter, intensity: 0.6, filter(.tonal))]),
            SGMask(id: "preset-bulge", name: "Выпуклое лицо", layers: [layer(.bulgeFace, intensity: 0.7)]),
            SGMask(id: "preset-narrow", name: "Узкое лицо", layers: [layer(.narrowFace, intensity: 0.7)]),
            SGMask(id: "preset-noir", name: "Нуар", layers: [layer(.colorFilter, intensity: 1.0, filter(.noir)), layer(.faceVignette, intensity: 0.8)]),
            SGMask(id: "preset-spot", name: "Прожектор", layers: [layer(.spotlight, intensity: 0.8)]),
            SGMask(id: "preset-bgblur", name: "Размытый фон", layers: [layer(.blurBackground, intensity: 0.8)]),
            SGMask(id: "preset-comic", name: "Комикс", layers: [layer(.colorFilter, intensity: 1.0, filter(.comic))]),
            SGMask(id: "preset-thermal", name: "Тепловизор", layers: [layer(.colorFilter, intensity: 1.0, filter(.thermal))]),
            SGMask(id: "preset-sketch", name: "Набросок", layers: [layer(.colorFilter, intensity: 1.0, filter(.sketch))]),
            SGMask(id: "preset-anon", name: "Аноним", layers: [layer(.blurFace, intensity: 1.0), layer(.blurBackground, intensity: 1.0), layer(.colorFilter, intensity: 1.0, filter(.mono))])
        ]
    }
}

public extension SGExtrasManager {
    /// Apply the active mask to the front camera when recording rounds.
    var roundMasksEnabled: Bool {
        get {
            return AYGSharedDefaults.store.bool(forKey: "SG.mask.rounds")
        }
        set {
            AYGSharedDefaults.store.set(newValue, forKey: "SG.mask.rounds")
        }
    }
}
