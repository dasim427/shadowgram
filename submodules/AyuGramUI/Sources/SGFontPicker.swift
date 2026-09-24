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

    UserDefaults.standard.removeObject(forKey: "SG.fontPreset")
    UserDefaults.standard.set(fileName, forKey: sgCustomFontFileKey)
    UserDefaults.standard.set(name, forKey: sgCustomFontNameKey)
    return name
}

func sgResetCustomFont() {
    UserDefaults.standard.removeObject(forKey: sgCustomFontFileKey)
    UserDefaults.standard.removeObject(forKey: sgCustomFontNameKey)
    let _ = try? FileManager.default.removeItem(atPath: NSHomeDirectory() + "/Documents/SGFonts")
}

// Shadowgram: font presets. The bundled families ship in the app (Google Fonts, OFL);
// the rest are fonts every iPhone already has. nil means the system font.
let sgFontPresets: [(title: String, family: String?)] = [
    ("Системный (SF Pro)", nil),
    ("Roboto", "Roboto"),
    ("Open Sans", "Open Sans"),
    ("Montserrat", "Montserrat"),
    ("Rubik", "Rubik"),
    ("Nunito", "Nunito"),
    ("Raleway", "Raleway"),
    ("PT Sans", "PT Sans"),
    ("Comfortaa", "Comfortaa"),
    ("Unbounded", "Unbounded"),
    ("Lora", "Lora"),
    ("PT Serif", "PT Serif"),
    ("Georgia", "Georgia"),
    ("Times New Roman", "Times New Roman"),
    ("JetBrains Mono", "JetBrains Mono"),
    ("Menlo", "Menlo"),
    ("Courier New", "Courier New"),
    ("Caveat (рукописный)", "Caveat"),
    ("Avenir Next", "Avenir Next"),
    ("Helvetica Neue", "Helvetica Neue"),
    ("American Typewriter", "American Typewriter"),
    ("Noteworthy", "Noteworthy")
]

private let sgFontPresetKey = "SG.fontPreset"

func sgActiveFontPreset() -> String? {
    return UserDefaults.standard.string(forKey: sgFontPresetKey)
}

/// Picking a preset replaces an imported font file, so the two never compete.
func sgSetFontPreset(_ family: String?) {
    if let family {
        UserDefaults.standard.set(family, forKey: sgFontPresetKey)
    } else {
        UserDefaults.standard.removeObject(forKey: sgFontPresetKey)
    }
    sgResetCustomFont()
}
