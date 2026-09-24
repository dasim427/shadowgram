import Foundation
import UIKit
import PhotosUI
import UniformTypeIdentifiers

// Shadowgram: picks a GIF or picture from the photo library for the chat background.
// The original file (not a re-encoded still) is copied, so GIFs keep their animation.
@available(iOS 14.0, *)
final class SGBackgroundPicker: NSObject, PHPickerViewControllerDelegate {
    private static var current: SGBackgroundPicker?

    private let completion: (Bool) -> Void

    private init(completion: @escaping (Bool) -> Void) {
        self.completion = completion
    }

    static func present(from controller: UIViewController, completion: @escaping (Bool) -> Void) {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        let handler = SGBackgroundPicker(completion: completion)
        SGBackgroundPicker.current = handler
        picker.delegate = handler
        controller.present(picker, animated: true, completion: nil)
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true, completion: nil)
        let completion = self.completion
        SGBackgroundPicker.current = nil

        guard let provider = results.first?.itemProvider else {
            completion(false)
            return
        }
        let typeIdentifier: String
        if provider.hasItemConformingToTypeIdentifier(UTType.gif.identifier) {
            typeIdentifier = UTType.gif.identifier
        } else {
            typeIdentifier = UTType.image.identifier
        }
        provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, _ in
            // The URL is only valid inside this callback, so copy right away.
            var success = false
            if let url {
                success = sgStoreChatBackground(from: url)
            }
            DispatchQueue.main.async {
                completion(success)
            }
        }
    }
}

private func sgChatBackgroundPath() -> String {
    return NSHomeDirectory() + "/Documents/SGBackgrounds/chat.gif"
}

private func sgStoreChatBackground(from url: URL) -> Bool {
    let directory = NSHomeDirectory() + "/Documents/SGBackgrounds"
    let _ = try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true, attributes: nil)
    let target = URL(fileURLWithPath: sgChatBackgroundPath())
    let _ = try? FileManager.default.removeItem(at: target)
    do {
        try FileManager.default.copyItem(at: url, to: target)
        return true
    } catch {
        return false
    }
}

func sgHasChatBackground() -> Bool {
    return FileManager.default.fileExists(atPath: sgChatBackgroundPath())
}

func sgRemoveChatBackground() {
    let _ = try? FileManager.default.removeItem(atPath: sgChatBackgroundPath())
}
