import Foundation
import UIKit
import PhotosUI
import UniformTypeIdentifiers
import TelegramCore

// Shadowgram: picks what a video call shows instead of the camera — a picture, a GIF or a
// video. The original file is copied so GIFs keep their frames and videos their sound-free
// motion.
@available(iOS 14.0, *)
final class SGCallMediaPicker: NSObject, PHPickerViewControllerDelegate {
    private static var current: SGCallMediaPicker?

    private let completion: (Bool) -> Void

    private init(completion: @escaping (Bool) -> Void) {
        self.completion = completion
    }

    static func present(from controller: UIViewController, completion: @escaping (Bool) -> Void) {
        var configuration = PHPickerConfiguration()
        configuration.filter = .any(of: [.images, .videos])
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        let handler = SGCallMediaPicker(completion: completion)
        SGCallMediaPicker.current = handler
        picker.delegate = handler
        controller.present(picker, animated: true, completion: nil)
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true, completion: nil)
        let completion = self.completion
        SGCallMediaPicker.current = nil

        guard let provider = results.first?.itemProvider else {
            completion(false)
            return
        }
        let typeIdentifier: String
        if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
            typeIdentifier = UTType.movie.identifier
        } else if provider.hasItemConformingToTypeIdentifier(UTType.gif.identifier) {
            typeIdentifier = UTType.gif.identifier
        } else {
            typeIdentifier = UTType.image.identifier
        }
        provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, _ in
            // The URL is only valid inside this callback, so copy right away.
            var success = false
            if let url {
                success = SGCallVideoStore.storeMedia(from: url)
            }
            DispatchQueue.main.async {
                completion(success)
            }
        }
    }
}
