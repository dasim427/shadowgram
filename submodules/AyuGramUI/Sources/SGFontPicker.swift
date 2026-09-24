import Foundation
import UIKit
import UniformTypeIdentifiers

// Shadowgram: lets the user pick a .ttf/.otf file to use as the interface font.
// The file is copied into Documents/SGFonts and its PostScript name remembered in the
// standard defaults, where Display's `Font` looks for it on the next launch.
final class SGFontPicker: NSObject, UIDocumentPickerDelegate {
    private static var current: SGFontPicker?

    private let completion: (String?) -> Void

    private init(completion: @escaping (String?) -> Void) {
        self.completion = completion
    }

    static func present(from controller: UIViewController, completion: @escaping (String?) -> Void) {
        let picker: UIDocumentPickerViewController
        if #available(iOS 14.0, *) {
            picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.font], asCopy: true)
        } else {
            picker = UIDocumentPickerViewController(documentTypes: ["public.font"], in: .import)
        }
        let handler = SGFontPicker(completion: completion)
        SGFontPicker.current = handler
        picker.delegate = handler
        controller.present(picker, animated: true, completion: nil)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        let completion = self.completion
        SGFontPicker.current = nil
        guard let url = urls.first else {
            completion(nil)
            return
        }
        completion(sgInstallCustomFont(from: url))
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        SGFontPicker.current = nil
    }
}

private let sgCustomFontFileKey = "SG.customFontFile"
private let sgCustomFontNameKey = "SG.customFontName"

/// The PostScript name of the imported font, if one is set.
func sgCustomFontName() -> String? {
    return UserDefaults.standard.string(forKey: sgCustomFontNameKey)
}

/// Returns the font's PostScript name, or nil if the file is not a readable font.
func sgInstallCustomFont(from url: URL) -> String? {
    let isAccessing = url.startAccessingSecurityScopedResource()
    defer {
        if isAccessing {
            url.stopAccessingSecurityScopedResource()
        }
    }
    guard let data = try? Data(contentsOf: url), let provider = CGDataProvider(data: data as CFData), let cgFont = CGFont(provider), let postScriptName = cgFont.postScriptName else {
        return nil
    }
    let name = postScriptName as String

    let fileExtension = url.pathExtension.isEmpty ? "ttf" : url.pathExtension.lowercased()
    let directory = NSHomeDirectory() + "/Documents/SGFonts"
    let _ = try? FileManager.default.removeItem(atPath: directory)
    let _ = try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true, attributes: nil)
    let fileName = "SGFonts/custom." + fileExtension
    do {
        try data.write(to: URL(fileURLWithPath: NSHomeDirectory() + "/Documents/" + fileName))
    } catch {
        return nil
    }

    UserDefaults.standard.set(fileName, forKey: sgCustomFontFileKey)
    UserDefaults.standard.set(name, forKey: sgCustomFontNameKey)
    return name
}

func sgResetCustomFont() {
    UserDefaults.standard.removeObject(forKey: sgCustomFontFileKey)
    UserDefaults.standard.removeObject(forKey: sgCustomFontNameKey)
    let _ = try? FileManager.default.removeItem(atPath: NSHomeDirectory() + "/Documents/SGFonts")
}
