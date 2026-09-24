import Foundation
import UIKit
import TelegramCore

// Shadowgram: profile badges. A badge is a small canvas of layers (pictures and text)
// over an optional colored background. Badges are kept as JSON `.sgbadge` files in
// Documents/SGBadges; the active one is also rendered to active.png, which the profile
// header draws after the user's name.

struct SGBadgeLayer: Codable, Equatable {
    enum Kind: String, Codable {
        case image
        case text
    }

    var id: String
    var kind: Kind
    var imageData: Data?
    var text: String?
    var textColor: Int
    var isBold: Bool
    /// Center of the layer on the canvas, 0...1 on both axes.
    var centerX: Double
    var centerY: Double
    var scale: Double
    /// Radians.
    var rotation: Double
    var opacity: Double

    static func image(_ data: Data) -> SGBadgeLayer {
        return SGBadgeLayer(id: UUID().uuidString, kind: .image, imageData: data, text: nil, textColor: 0xFFFFFF, isBold: false, centerX: 0.5, centerY: 0.5, scale: 1.0, rotation: 0.0, opacity: 1.0)
    }

    static func text(_ text: String) -> SGBadgeLayer {
        return SGBadgeLayer(id: UUID().uuidString, kind: .text, imageData: nil, text: text, textColor: 0xFFFFFF, isBold: true, centerX: 0.5, centerY: 0.5, scale: 1.0, rotation: 0.0, opacity: 1.0)
    }
}

struct SGBadge: Codable, Equatable {
    var id: String
    var name: String
    /// 0xRRGGBB, or -1 for a transparent background.
    var backgroundColor: Int
    /// Corner radius as a share of the badge height, 0...0.5.
    var cornerRadius: Double
    /// Width divided by height.
    var aspect: Double
    var layers: [SGBadgeLayer]

    static func empty(name: String) -> SGBadge {
        return SGBadge(id: UUID().uuidString, name: name, backgroundColor: 0x7B5CFF, cornerRadius: 0.3, aspect: 2.0, layers: [])
    }
}

let sgBadgeColorPalette: [Int] = [0xFFFFFF, 0x000000, 0x7B5CFF, 0xFF2D55, 0xFF9500, 0xFFCC00, 0x34C759, 0x5AC8FA, 0x007AFF]

func sgColor(_ rgb: Int) -> UIColor {
    return UIColor(red: CGFloat((rgb >> 16) & 0xff) / 255.0, green: CGFloat((rgb >> 8) & 0xff) / 255.0, blue: CGFloat(rgb & 0xff) / 255.0, alpha: 1.0)
}

// MARK: - Storage

private func sgBadgesDirectory() -> String {
    return NSHomeDirectory() + "/Documents/SGBadges"
}

private func sgBadgePath(_ id: String) -> String {
    return sgBadgesDirectory() + "/" + id + ".sgbadge"
}

private let sgActiveBadgeKey = "SG.badge.active"

func sgLoadBadges() -> [SGBadge] {
    let names = (try? FileManager.default.contentsOfDirectory(atPath: sgBadgesDirectory())) ?? []
    var result: [SGBadge] = []
    for name in names where name.hasSuffix(".sgbadge") {
        if let data = try? Data(contentsOf: URL(fileURLWithPath: sgBadgesDirectory() + "/" + name)), let badge = try? JSONDecoder().decode(SGBadge.self, from: data) {
            result.append(badge)
        }
    }
    return result.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
}

func sgActiveBadgeId() -> String? {
    return UserDefaults.standard.string(forKey: sgActiveBadgeKey)
}

@discardableResult
func sgSaveBadge(_ badge: SGBadge) -> Bool {
    let _ = try? FileManager.default.createDirectory(atPath: sgBadgesDirectory(), withIntermediateDirectories: true, attributes: nil)
    guard let data = try? JSONEncoder().encode(badge) else {
        return false
    }
    do {
        try data.write(to: URL(fileURLWithPath: sgBadgePath(badge.id)), options: .atomic)
    } catch {
        return false
    }
    if sgActiveBadgeId() == badge.id {
        sgRenderActiveBadge(badge)
    }
    return true
}

func sgSetActiveBadge(_ badge: SGBadge?) {
    if let badge {
        UserDefaults.standard.set(badge.id, forKey: sgActiveBadgeKey)
        sgRenderActiveBadge(badge)
        SGExtrasManager.shared.setOn(.profileBadge, true)
    } else {
        UserDefaults.standard.removeObject(forKey: sgActiveBadgeKey)
        let _ = try? FileManager.default.removeItem(atPath: sgBadgesDirectory() + "/active.png")
    }
}

func sgDeleteBadge(_ badge: SGBadge) {
    if sgActiveBadgeId() == badge.id {
        sgSetActiveBadge(nil)
    }
    let _ = try? FileManager.default.removeItem(atPath: sgBadgePath(badge.id))
}

private func sgRenderActiveBadge(_ badge: SGBadge) {
    let image = sgRenderBadge(badge, height: 32.0, scale: 3.0)
    guard let data = image.pngData() else {
        return
    }
    let _ = try? FileManager.default.createDirectory(atPath: sgBadgesDirectory(), withIntermediateDirectories: true, attributes: nil)
    let _ = try? data.write(to: URL(fileURLWithPath: sgBadgesDirectory() + "/active.png"), options: .atomic)
}

// MARK: - Rendering

/// The side a layer at scale 1 fits into, as a share of the badge height.
private let sgLayerBaseFraction: CGFloat = 0.8

func sgBadgeCanvasSize(_ badge: SGBadge, height: CGFloat) -> CGSize {
    return CGSize(width: floor(height * CGFloat(max(0.5, min(4.0, badge.aspect)))), height: height)
}

/// The layer's box before rotation, in canvas points, centered on its center.
func sgBadgeLayerSize(_ layer: SGBadgeLayer, canvasHeight: CGFloat) -> CGSize {
    let base = canvasHeight * sgLayerBaseFraction * CGFloat(layer.scale)
    switch layer.kind {
    case .image:
        guard let data = layer.imageData, let image = UIImage(data: data), image.size.height > 0.0 else {
            return CGSize(width: base, height: base)
        }
        let aspect = image.size.width / image.size.height
        if aspect >= 1.0 {
            return CGSize(width: base, height: base / aspect)
        } else {
            return CGSize(width: base * aspect, height: base)
        }
    case .text:
        let size = (layer.text ?? "").size(withAttributes: sgBadgeTextAttributes(layer, canvasHeight: canvasHeight))
        return CGSize(width: ceil(size.width), height: ceil(size.height))
    }
}

private func sgBadgeTextAttributes(_ layer: SGBadgeLayer, canvasHeight: CGFloat) -> [NSAttributedString.Key: Any] {
    let fontSize = canvasHeight * 0.5 * CGFloat(layer.scale)
    let font = layer.isBold ? UIFont.systemFont(ofSize: fontSize, weight: .bold) : UIFont.systemFont(ofSize: fontSize, weight: .regular)
    return [.font: font, .foregroundColor: sgColor(layer.textColor)]
}

func sgRenderBadge(_ badge: SGBadge, height: CGFloat, scale: CGFloat) -> UIImage {
    let size = sgBadgeCanvasSize(badge, height: height)
    let format = UIGraphicsImageRendererFormat()
    format.scale = scale
    format.opaque = false
    return UIGraphicsImageRenderer(size: size, format: format).image { rendererContext in
        let context = rendererContext.cgContext
        let bounds = CGRect(origin: CGPoint(), size: size)
        let cornerRadius = height * CGFloat(max(0.0, min(0.5, badge.cornerRadius)))
        let path = UIBezierPath(roundedRect: bounds, cornerRadius: cornerRadius)
        path.addClip()
        if badge.backgroundColor >= 0 {
            sgColor(badge.backgroundColor).setFill()
            path.fill()
        }
        for layer in badge.layers {
            let layerSize = sgBadgeLayerSize(layer, canvasHeight: height)
            context.saveGState()
            context.setAlpha(CGFloat(max(0.0, min(1.0, layer.opacity))))
            context.translateBy(x: CGFloat(layer.centerX) * size.width, y: CGFloat(layer.centerY) * size.height)
            context.rotate(by: CGFloat(layer.rotation))
            let rect = CGRect(x: -layerSize.width / 2.0, y: -layerSize.height / 2.0, width: layerSize.width, height: layerSize.height)
            switch layer.kind {
            case .image:
                if let data = layer.imageData, let image = UIImage(data: data) {
                    image.draw(in: rect)
                }
            case .text:
                (layer.text ?? "").draw(in: rect, withAttributes: sgBadgeTextAttributes(layer, canvasHeight: height))
            }
            context.restoreGState()
        }
    }
}

/// Scales a picked picture down so badge files stay small.
func sgBadgeImageData(_ image: UIImage) -> Data? {
    let maxSide: CGFloat = 512.0
    let largest = max(image.size.width, image.size.height)
    let factor = largest > maxSide ? maxSide / largest : 1.0
    let targetSize = CGSize(width: floor(image.size.width * factor), height: floor(image.size.height * factor))
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1.0
    format.opaque = false
    let scaled = UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
        image.draw(in: CGRect(origin: CGPoint(), size: targetSize))
    }
    return scaled.pngData()
}

// MARK: - Import and export

enum SGBadgeImportResult {
    case badge(SGBadge)
    case image(Data)
    case failure(String)
}

/// Accepts either a `.sgbadge` file or a picture; the extension does not matter.
func sgInterpretBadgeData(_ data: Data) -> SGBadgeImportResult {
    if data.count > 20 * 1024 * 1024 {
        return .failure("Файл слишком большой.")
    }
    if var badge = try? JSONDecoder().decode(SGBadge.self, from: data) {
        badge.id = UUID().uuidString
        return .badge(badge)
    }
    if let image = UIImage(data: data), let imageData = sgBadgeImageData(image) {
        return .image(imageData)
    }
    if let text = String(data: data.prefix(512), encoding: .utf8), text.lowercased().contains("<html") {
        return .failure("По ссылке веб-страница, а не файл. Нужна прямая ссылка на бейдж или картинку.")
    }
    return .failure("Это не бейдж и не картинка. Подойдёт файл .sgbadge, PNG или JPEG.")
}

func sgBadgeExportURL(_ badge: SGBadge) -> URL? {
    guard let data = try? JSONEncoder().encode(badge) else {
        return nil
    }
    let safeName = badge.name.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined(separator: "_")
    let url = URL(fileURLWithPath: NSTemporaryDirectory() + (safeName.isEmpty ? "badge" : safeName) + ".sgbadge")
    do {
        try data.write(to: url, options: .atomic)
    } catch {
        return nil
    }
    return url
}

// MARK: - Presets

/// Ready-made badges: an emoji and a word on a colored plate, or a lone emoji.
func sgBadgePresets() -> [SGBadge] {
    func plate(_ id: String, _ name: String, _ text: String, background: Int, textColor: Int) -> SGBadge {
        var layer = SGBadgeLayer.text(text)
        layer.id = "preset-layer-" + id
        layer.textColor = textColor
        layer.scale = 0.9
        return SGBadge(id: "preset-" + id, name: name, backgroundColor: background, cornerRadius: 0.5, aspect: 3.0, layers: [layer])
    }
    func emoji(_ id: String, _ name: String, _ text: String) -> SGBadge {
        var layer = SGBadgeLayer.text(text)
        layer.id = "preset-layer-" + id
        layer.scale = 1.5
        return SGBadge(id: "preset-" + id, name: name, backgroundColor: -1, cornerRadius: 0.0, aspect: 1.0, layers: [layer])
    }
    return [
        plate("vip", "VIP", "👑 VIP", background: 0xFFB800, textColor: 0x1A1A1A),
        plate("fire", "Огонь", "🔥 Огонь", background: 0xFF5A1F, textColor: 0xFFFFFF),
        plate("pro", "PRO", "⚡ PRO", background: 0x7B5CFF, textColor: 0xFFFFFF),
        plate("ghost", "Призрак", "👻 Призрак", background: 0x1C1238, textColor: 0xFFFFFF),
        plate("legend", "Легенда", "💎 Легенда", background: 0x2F80ED, textColor: 0xFFFFFF),
        plate("admin", "Админ", "🛡 Админ", background: 0x2EAD5B, textColor: 0xFFFFFF),
        plate("gamer", "Геймер", "🎮 Геймер", background: 0x9B51E0, textColor: 0xFFFFFF),
        plate("night", "Ночь", "🌙 Ночь", background: 0x0B1F3A, textColor: 0xFFFFFF),
        plate("star", "Звезда", "⭐ Звезда", background: 0xFFCC00, textColor: 0x1A1A1A),
        plate("dev", "Dev", "💻 Dev", background: 0x24292E, textColor: 0x7EE787),
        plate("love", "Love", "💗 Love", background: 0xFF2D78, textColor: 0xFFFFFF),
        plate("boss", "Босс", "😎 Босс", background: 0x000000, textColor: 0xFFD60A),
        emoji("heart", "Сердце", "❤️"),
        emoji("crown", "Корона", "👑"),
        emoji("skull", "Череп", "💀"),
        emoji("wolf", "Волк", "🐺"),
        emoji("lightning", "Молния", "⚡"),
        emoji("rocket", "Ракета", "🚀")
    ]
}
