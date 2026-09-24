import Foundation
import UIKit
import ImageIO
import TelegramCore

// Shadowgram: a GIF (or still picture) the user picked, drawn over the chat wallpaper.
// The file lives at Documents/SGBackgrounds/chat.gif; frames are decoded once in the
// background, downscaled to phone size, and shared by every chat.

public func sgGifBackgroundPath() -> String {
    return NSHomeDirectory() + "/Documents/SGBackgrounds/chat.gif"
}

private final class SGGifBackgroundView: UIImageView {
}

private final class SGGifBackgroundCache {
    static let shared = SGGifBackgroundCache()

    private var image: UIImage?
    private var imageDate: Date?
    private var isLoading = false
    private var waiters: [(UIImage?) -> Void] = []

    /// Main thread only. Returns the decoded image when it is ready; otherwise starts
    /// decoding and calls `completion` once it is.
    func image(completion: @escaping (UIImage?) -> Void) -> UIImage? {
        let path = sgGifBackgroundPath()
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        guard let date = attributes?[.modificationDate] as? Date else {
            self.image = nil
            self.imageDate = nil
            return nil
        }
        if let image = self.image, self.imageDate == date {
            return image
        }
        self.waiters.append(completion)
        if !self.isLoading {
            self.isLoading = true
            DispatchQueue.global(qos: .userInitiated).async {
                let decoded = sgDecodeAnimatedImage(path: path, maxPixelSize: 720)
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.image = decoded
                    self.imageDate = date
                    let waiters = self.waiters
                    self.waiters = []
                    for waiter in waiters {
                        waiter(decoded)
                    }
                }
            }
        }
        return nil
    }
}

private func sgDecodeAnimatedImage(path: String, maxPixelSize: Int) -> UIImage? {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else {
        return nil
    }
    let count = min(CGImageSourceGetCount(source), 200)
    if count == 0 {
        return nil
    }
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        kCGImageSourceCreateThumbnailWithTransform: true
    ]
    var frames: [UIImage] = []
    var duration: Double = 0.0
    for index in 0 ..< count {
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary) else {
            continue
        }
        frames.append(UIImage(cgImage: cgImage))
        var frameDuration = 0.1
        if let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any], let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] {
            if let value = gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double, value > 0.01 {
                frameDuration = value
            } else if let value = gif[kCGImagePropertyGIFDelayTime] as? Double, value > 0.01 {
                frameDuration = value
            }
        }
        duration += frameDuration
    }
    if frames.isEmpty {
        return nil
    }
    if frames.count == 1 {
        return frames[0]
    }
    return UIImage.animatedImage(with: frames, duration: duration)
}

extension WallpaperBackgroundNodeImpl {
    func sgUpdateGifBackground(size: CGSize) {
        let existing = self.view.subviews.first(where: { $0 is SGGifBackgroundView }) as? SGGifBackgroundView
        guard SGExtrasManager.shared.isOn(.gifChatBackground) else {
            existing?.removeFromSuperview()
            return
        }
        let imageView = existing ?? SGGifBackgroundView()
        if imageView.superview == nil {
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            imageView.isUserInteractionEnabled = false
            self.view.addSubview(imageView)
        } else {
            self.view.bringSubviewToFront(imageView)
        }
        imageView.frame = CGRect(origin: CGPoint(), size: size)
        imageView.alpha = CGFloat(SGExtrasManager.shared.gifBackgroundOpacityPercent) / 100.0
        let image = SGGifBackgroundCache.shared.image(completion: { [weak imageView] image in
            imageView?.image = image
        })
        if let image, imageView.image !== image {
            imageView.image = image
        }
    }
}
