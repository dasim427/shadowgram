import Foundation
import UIKit
import UniformTypeIdentifiers
import AppBundle

// Shadowgram: icon packs. A pack is a folder of PNGs named after Telegram's bundle image
// names ("Settings/Menu/Proxy.png", or "Settings_Menu_Proxy.png"). Packs are copied into
// Documents/SGIconPacks; AppBundle reads the active one on launch.

private let sgIconPackKey = "SG.iconPack"

private func sgIconPacksDirectory() -> String {
    return NSHomeDirectory() + "/Documents/SGIconPacks"
}

func sgInstalledIconPacks() -> [String] {
    let names = (try? FileManager.default.contentsOfDirectory(atPath: sgIconPacksDirectory())) ?? []
    return names.filter { name in
        var isDirectory: ObjCBool = false
        return !name.hasPrefix(".") && FileManager.default.fileExists(atPath: sgIconPacksDirectory() + "/" + name, isDirectory: &isDirectory) && isDirectory.boolValue
    }.sorted()
}

func sgActiveIconPack() -> String? {
    return UserDefaults.standard.string(forKey: sgIconPackKey)
}

func sgSetActiveIconPack(_ name: String?) {
    if let name {
        UserDefaults.standard.set(name, forKey: sgIconPackKey)
    } else {
        UserDefaults.standard.removeObject(forKey: sgIconPackKey)
    }
}

func sgDeleteIconPack(_ name: String) {
    if sgActiveIconPack() == name {
        sgSetActiveIconPack(nil)
    }
    let _ = try? FileManager.default.removeItem(atPath: sgIconPacksDirectory() + "/" + name)
}

/// Copies a picked folder in as a pack named after it. Returns the pack name.
private func sgInstallIconPack(from url: URL) -> String? {
    let isAccessing = url.startAccessingSecurityScopedResource()
    defer {
        if isAccessing {
            url.stopAccessingSecurityScopedResource()
        }
    }
    let name = url.lastPathComponent.isEmpty ? "Набор" : url.lastPathComponent
    let target = URL(fileURLWithPath: sgIconPacksDirectory() + "/" + name)
    let _ = try? FileManager.default.createDirectory(atPath: sgIconPacksDirectory(), withIntermediateDirectories: true, attributes: nil)
    let _ = try? FileManager.default.removeItem(at: target)
    do {
        try FileManager.default.copyItem(at: url, to: target)
        return name
    } catch {
        return nil
    }
}

@available(iOS 14.0, *)
final class SGIconPackPicker: NSObject, UIDocumentPickerDelegate {
    private static var current: SGIconPackPicker?

    private let completion: (String?) -> Void

    private init(completion: @escaping (String?) -> Void) {
        self.completion = completion
    }

    static func present(from controller: UIViewController, completion: @escaping (String?) -> Void) {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.folder], asCopy: false)
        let handler = SGIconPackPicker(completion: completion)
        SGIconPackPicker.current = handler
        picker.delegate = handler
        controller.present(picker, animated: true, completion: nil)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        let completion = self.completion
        SGIconPackPicker.current = nil
        guard let url = urls.first else {
            completion(nil)
            return
        }
        completion(sgInstallIconPack(from: url))
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        SGIconPackPicker.current = nil
    }
}

/// Shares a text file with every icon name the app has loaded since launch, as a
/// starting point for drawing a pack. Browse the app a little first to fill it.
func sgShareIconNameList(from controller: UIViewController) {
    let names = sgRequestedBundleImageNames()
    let text = "Имена иконок Shadowgram (\(names.count)). Положите в папку набора PNG с таким же путём, например Settings/Menu/Proxy.png, или замените / на _.\n\n" + names.joined(separator: "\n")
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
