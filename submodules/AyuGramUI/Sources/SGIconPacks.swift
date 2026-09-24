import Foundation
import UIKit
import UniformTypeIdentifiers
import AppBundle
import ZipArchive

// Shadowgram: icon packs. A pack is a folder of PNGs named after Telegram's bundle image
// names ("Settings/Menu/Proxy.png", or "Settings_Menu_Proxy.png") plus a metadata.json
// with its name. Packs are shared as .zip files. Several packs can be enabled at once:
// the first enabled pack that has an icon wins, then the base pack, then the app's own
// icon. AppBundle reads this configuration on launch.

struct SGIconPackMetadata: Codable, Equatable {
    var name: String
    var author: String?
    var version: Int?
}

struct SGIconPack: Equatable {
    var id: String
    var metadata: SGIconPackMetadata
    var iconCount: Int
}

private let sgEnabledPacksKey = "SG.iconPacks.enabled"
private let sgBasePackKey = "SG.iconPacks.base"

private let sgMaxArchiveSize: Int64 = 100 * 1024 * 1024
private let sgMaxUnpackedSize: Int64 = 300 * 1024 * 1024
private let sgMaxCompressionRatio: Int64 = 200
private let sgMaxFileCount = 5000
private let sgMaxMetadataSize = 64 * 1024

func sgIconPacksDirectory() -> String {
    return NSHomeDirectory() + "/Documents/SGIconPacks"
}

private func sgPackDirectory(_ id: String) -> String {
    return sgIconPacksDirectory() + "/" + id
}

// MARK: - Listing and configuration

private func sgPngCount(in directory: String) -> Int {
    guard let enumerator = FileManager.default.enumerator(atPath: directory) else {
        return 0
    }
    var count = 0
    while let item = enumerator.nextObject() as? String {
        if item.lowercased().hasSuffix(".png") {
            count += 1
        }
    }
    return count
}

private func sgReadMetadata(directory: String) -> SGIconPackMetadata? {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: directory + "/metadata.json")), data.count <= sgMaxMetadataSize else {
        return nil
    }
    return try? JSONDecoder().decode(SGIconPackMetadata.self, from: data)
}

func sgInstalledIconPacks() -> [SGIconPack] {
    let ids = (try? FileManager.default.contentsOfDirectory(atPath: sgIconPacksDirectory())) ?? []
    var result: [SGIconPack] = []
    for id in ids where !id.hasPrefix(".") {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: sgPackDirectory(id), isDirectory: &isDirectory), isDirectory.boolValue else {
            continue
        }
        let metadata = sgReadMetadata(directory: sgPackDirectory(id)) ?? SGIconPackMetadata(name: id, author: nil, version: nil)
        result.append(SGIconPack(id: id, metadata: metadata, iconCount: sgPngCount(in: sgPackDirectory(id))))
    }
    return result.sorted(by: { $0.metadata.name.localizedCaseInsensitiveCompare($1.metadata.name) == .orderedAscending })
}

func sgEnabledIconPackIds() -> [String] {
    let installed = Set(sgInstalledIconPacks().map { $0.id })
    let stored = UserDefaults.standard.stringArray(forKey: sgEnabledPacksKey) ?? []
    return stored.filter { installed.contains($0) }
}

func sgSetEnabledIconPackIds(_ ids: [String]) {
    UserDefaults.standard.set(ids, forKey: sgEnabledPacksKey)
}

func sgBaseIconPackId() -> String? {
    return UserDefaults.standard.string(forKey: sgBasePackKey)
}

func sgSetBaseIconPackId(_ id: String?) {
    if let id {
        UserDefaults.standard.set(id, forKey: sgBasePackKey)
    } else {
        UserDefaults.standard.removeObject(forKey: sgBasePackKey)
    }
}

func sgToggleIconPack(_ id: String) {
    var ids = sgEnabledIconPackIds()
    if let index = ids.firstIndex(of: id) {
        ids.remove(at: index)
    } else {
        ids.insert(id, at: 0)
    }
    sgSetEnabledIconPackIds(ids)
}

func sgMoveIconPack(_ id: String, up: Bool) {
    var ids = sgEnabledIconPackIds()
    guard let index = ids.firstIndex(of: id) else {
        return
    }
    let target = up ? index - 1 : index + 1
    guard target >= 0 && target < ids.count else {
        return
    }
    ids.swapAt(index, target)
    sgSetEnabledIconPackIds(ids)
}

func sgDeleteIconPack(_ id: String) {
    sgSetEnabledIconPackIds(sgEnabledIconPackIds().filter { $0 != id })
    if sgBaseIconPackId() == id {
        sgSetBaseIconPackId(nil)
    }
    let _ = try? FileManager.default.removeItem(atPath: sgPackDirectory(id))
}

// MARK: - Creating and editing

private func sgNewPackId() -> String {
    return "pack-" + UUID().uuidString.prefix(8).lowercased()
}

private func sgWriteMetadata(_ metadata: SGIconPackMetadata, directory: String) {
    if let data = try? JSONEncoder().encode(metadata) {
        let _ = try? data.write(to: URL(fileURLWithPath: directory + "/metadata.json"), options: .atomic)
    }
}

/// Creates an empty pack and enables it. Returns its id.
func sgCreateIconPack(name: String) -> String {
    let id = sgNewPackId()
    let directory = sgPackDirectory(id)
    let _ = try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true, attributes: nil)
    sgWriteMetadata(SGIconPackMetadata(name: name, author: nil, version: 1), directory: directory)
    var ids = sgEnabledIconPackIds()
    ids.insert(id, at: 0)
    sgSetEnabledIconPackIds(ids)
    return id
}

func sgRenameIconPack(_ id: String, name: String) {
    var metadata = sgReadMetadata(directory: sgPackDirectory(id)) ?? SGIconPackMetadata(name: name, author: nil, version: 1)
    metadata.name = name
    sgWriteMetadata(metadata, directory: sgPackDirectory(id))
}

private func sgIconFilePath(packId: String, iconName: String) -> String {
    return sgPackDirectory(packId) + "/" + iconName.replacingOccurrences(of: "/", with: "_") + ".png"
}

/// The pack's own image for an icon, if it has one.
func sgIconPackImage(packId: String, iconName: String) -> UIImage? {
    let flat = sgIconFilePath(packId: packId, iconName: iconName)
    if let image = UIImage(contentsOfFile: flat) {
        return image
    }
    return UIImage(contentsOfFile: sgPackDirectory(packId) + "/" + iconName + ".png")
}

/// Stores `image` as the pack's icon for `iconName`, sized like the original icon.
func sgSetIconPackImage(packId: String, iconName: String, image: UIImage) -> Bool {
    let original = sgOriginalBundleImage(iconName)
    let targetSize = original?.size ?? CGSize(width: 30.0, height: 30.0)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 3.0
    format.opaque = false
    let rendered = UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
        let aspect = image.size.width / max(1.0, image.size.height)
        var drawSize = targetSize
        if aspect > targetSize.width / max(1.0, targetSize.height) {
            drawSize.height = targetSize.width / aspect
        } else {
            drawSize.width = targetSize.height * aspect
        }
        image.draw(in: CGRect(x: (targetSize.width - drawSize.width) / 2.0, y: (targetSize.height - drawSize.height) / 2.0, width: drawSize.width, height: drawSize.height))
    }
    guard let data = rendered.pngData() else {
        return false
    }
    let path = sgIconFilePath(packId: packId, iconName: iconName).replacingOccurrences(of: ".png", with: "@3x.png")
    let _ = try? FileManager.default.removeItem(atPath: sgIconFilePath(packId: packId, iconName: iconName))
    do {
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        return true
    } catch {
        return false
    }
}

func sgRemoveIconPackImage(packId: String, iconName: String) {
    let flat = sgIconFilePath(packId: packId, iconName: iconName)
    for path in [flat, flat.replacingOccurrences(of: ".png", with: "@2x.png"), flat.replacingOccurrences(of: ".png", with: "@3x.png"), sgPackDirectory(packId) + "/" + iconName + ".png", sgPackDirectory(packId) + "/" + iconName + "@3x.png"] {
        let _ = try? FileManager.default.removeItem(atPath: path)
    }
}

// MARK: - Import and export

enum SGIconPackImportResult {
    case success(String, Bool)
    case failure(String)
}

/// Installs a pack from a .zip or a folder. A pack whose name matches an installed one
/// replaces it (that is how packs are updated). The Bool in `.success` is true for an update.
func sgImportIconPack(from url: URL) -> SGIconPackImportResult {
    let isAccessing = url.startAccessingSecurityScopedResource()
    defer {
        if isAccessing {
            url.stopAccessingSecurityScopedResource()
        }
    }
    let fileManager = FileManager.default
    let staging = NSTemporaryDirectory() + "sg-iconpack-" + UUID().uuidString
    defer {
        let _ = try? fileManager.removeItem(atPath: staging)
    }

    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
        return .failure("Файл набора не найден.")
    }
    if isDirectory.boolValue {
        do {
            try fileManager.copyItem(atPath: url.path, toPath: staging)
        } catch {
            return .failure("Не удалось скопировать папку набора.")
        }
    } else {
        let archiveSize = ((try? fileManager.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value ?? 0
        if archiveSize <= 0 || archiveSize > sgMaxArchiveSize {
            return .failure("Набор иконок слишком большой.")
        }
        if SSZipArchive.isFilePasswordProtected(atPath: url.path) {
            return .failure("Архив набора защищён паролем.")
        }
        guard let payload = try? SSZipArchive.payloadSizeForArchive(atPath: url.path) else {
            return .failure("Архив набора повреждён или имеет неверный формат.")
        }
        let unpackedSize = payload.int64Value
        if unpackedSize > sgMaxUnpackedSize || unpackedSize > archiveSize * sgMaxCompressionRatio {
            return .failure("Архив набора сжат слишком сильно — похоже на битый или опасный файл.")
        }
        let _ = try? fileManager.createDirectory(atPath: staging, withIntermediateDirectories: true, attributes: nil)
        if !SSZipArchive.unzipFile(atPath: url.path, toDestination: staging) {
            return .failure("Архив набора повреждён или имеет неверный формат.")
        }
    }

    // Archives often wrap everything in one top-level folder; look inside it.
    var root = staging
    if sgReadMetadataIfPresent(root) == nil, let children = try? fileManager.contentsOfDirectory(atPath: root) {
        let folders = children.filter { name in
            var childIsDirectory: ObjCBool = false
            return !name.hasPrefix(".") && !name.hasPrefix("__MACOSX") && fileManager.fileExists(atPath: root + "/" + name, isDirectory: &childIsDirectory) && childIsDirectory.boolValue
        }
        if folders.count == 1, sgReadMetadataIfPresent(root + "/" + folders[0]) != nil {
            root = root + "/" + folders[0]
        }
    }

    let metadataPath = root + "/metadata.json"
    guard fileManager.fileExists(atPath: metadataPath) else {
        return .failure("В архиве набора нет metadata.json.")
    }
    if let size = (try? fileManager.attributesOfItem(atPath: metadataPath))?[.size] as? NSNumber, size.intValue > sgMaxMetadataSize {
        return .failure("Метаданные набора слишком большие.")
    }
    guard let metadata = sgReadMetadata(directory: root), !metadata.name.trimmingCharacters(in: .whitespaces).isEmpty else {
        return .failure("Метаданные набора некорректны: нужен JSON с полем \"name\".")
    }

    var fileCount = 0
    if let enumerator = fileManager.enumerator(atPath: root) {
        while enumerator.nextObject() != nil {
            fileCount += 1
            if fileCount > sgMaxFileCount {
                return .failure("В наборе слишком много файлов.")
            }
        }
    }

    let existing = sgInstalledIconPacks().first(where: { $0.metadata.name == metadata.name })
    let id = existing?.id ?? sgNewPackId()
    let target = sgPackDirectory(id)
    let _ = try? fileManager.createDirectory(atPath: sgIconPacksDirectory(), withIntermediateDirectories: true, attributes: nil)
    let _ = try? fileManager.removeItem(atPath: target)
    do {
        try fileManager.moveItem(atPath: root, toPath: target)
    } catch {
        return .failure("Не удалось сохранить набор иконок.")
    }
    if existing == nil {
        var ids = sgEnabledIconPackIds()
        ids.insert(id, at: 0)
        sgSetEnabledIconPackIds(ids)
    }
    return .success(metadata.name, existing != nil)
}

private func sgReadMetadataIfPresent(_ directory: String) -> SGIconPackMetadata? {
    return sgReadMetadata(directory: directory)
}

/// Zips a pack for sharing.
func sgExportIconPack(_ pack: SGIconPack) -> URL? {
    let safeName = pack.metadata.name.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined(separator: "_")
    let path = NSTemporaryDirectory() + (safeName.isEmpty ? "icons" : safeName) + ".zip"
    let _ = try? FileManager.default.removeItem(atPath: path)
    if SSZipArchive.createZipFile(atPath: path, withContentsOfDirectory: sgPackDirectory(pack.id)) {
        return URL(fileURLWithPath: path)
    }
    return nil
}

/// Every icon name the app has shown since launch, plus the ones a pack already covers.
func sgKnownIconNames() -> [String] {
    var names = Set(sgRequestedBundleImageNames())
    for pack in sgInstalledIconPacks() {
        guard let enumerator = FileManager.default.enumerator(atPath: sgPackDirectory(pack.id)) else {
            continue
        }
        while let item = enumerator.nextObject() as? String {
            guard item.lowercased().hasSuffix(".png") else {
                continue
            }
            var name = String(item.dropLast(4))
            for suffix in ["@2x", "@3x"] where name.hasSuffix(suffix) {
                name = String(name.dropLast(3))
            }
            if !name.contains("/") {
                name = name.replacingOccurrences(of: "_", with: "/")
            }
            if sgOriginalBundleImage(name) != nil {
                names.insert(name)
            }
        }
    }
    return names.sorted()
}

// MARK: - Pickers

@available(iOS 14.0, *)
final class SGIconPackPicker: NSObject, UIDocumentPickerDelegate {
    private static var current: SGIconPackPicker?

    private let completion: (URL?) -> Void

    private init(completion: @escaping (URL?) -> Void) {
        self.completion = completion
    }

    /// Lets the user pick a .zip pack or a pack folder. The URL is only valid inside
    /// `completion`, which runs synchronously on the main thread.
    static func present(from controller: UIViewController, completion: @escaping (URL?) -> Void) {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.zip, UTType.folder], asCopy: false)
        let handler = SGIconPackPicker(completion: completion)
        SGIconPackPicker.current = handler
        picker.delegate = handler
        controller.present(picker, animated: true, completion: nil)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        let completion = self.completion
        SGIconPackPicker.current = nil
        completion(urls.first)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        SGIconPackPicker.current = nil
    }
}

/// Shares a text file with every icon name the app has loaded since launch, as a
/// starting point for drawing a pack. Browse the app a little first to fill it.
func sgShareIconNameList(from controller: UIViewController) {
    let names = sgKnownIconNames()
    let text = "Имена иконок Shadowgram (\(names.count)).\nНабор — это папка с metadata.json ({\"name\": \"Мой набор\"}) и PNG с такими же путями, например Settings/Menu/Proxy.png, или с / заменённым на _. Упакуй папку в .zip, чтобы поделиться.\n\n" + names.joined(separator: "\n")
    let url = URL(fileURLWithPath: NSTemporaryDirectory() + "shadowgram-icons.txt")
    do {
        try text.write(to: url, atomically: true, encoding: .utf8)
    } catch {
        return
    }
    let activityController = UIActivityViewController(activityItems: [url], applicationActivities: nil)
    activityController.popoverPresentationController?.sourceView = controller.view
    controller.present(activityController, animated: true, completion: nil)
}
