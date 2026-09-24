import Foundation
import UIKit
import AVFoundation
import CoreImage
import TelegramCore

// Shadowgram: shows the active mask on the round video camera while it is open, so the
// user sees the mask before and during recording. The camera preview itself is Apple's
// raw preview layer, so the masked frames are drawn by an image view on top of it.
public final class SGMaskPreview {
    public static let shared = SGMaskPreview()

    private let engine = SGMaskEngine()
    /// The preview is rendered off the camera queue so it never holds up recording.
    private let renderQueue = DispatchQueue(label: "shadowgram.mask.preview", qos: .userInitiated)
    private let ciContext = CIContext()
    private let lock = NSLock()
    private var handler: ((UIImage?) -> Void)?
    private var isRendering = false
    private var lastFrameTime: Double = 0.0
    private var wasShowing = false

    /// The preview only works while someone listens; `nil` stops it.
    public func setHandler(_ handler: ((UIImage?) -> Void)?) {
        self.lock.lock()
        self.handler = handler
        self.wasShowing = false
        self.lock.unlock()
    }

    var isActive: Bool {
        self.lock.lock()
        defer {
            self.lock.unlock()
        }
        return self.handler != nil
    }

    /// Called on the camera queue for every video frame.
    func process(_ sampleBuffer: CMSampleBuffer, isFront: Bool) {
        // With both cameras running, back camera frames arrive interleaved with the front
        // ones. They must be skipped, not treated as "hide the mask" — that made it blink.
        if !isFront {
            return
        }
        let showsMask = SGExtrasManager.shared.roundMasksEnabled && SGMaskStore.activeId != nil

        self.lock.lock()
        guard let handler = self.handler else {
            self.lock.unlock()
            return
        }
        if !showsMask {
            let wasShowing = self.wasShowing
            self.wasShowing = false
            self.lock.unlock()
            if wasShowing {
                DispatchQueue.main.async {
                    handler(nil)
                }
            }
            return
        }
        let now = CACurrentMediaTime()
        if self.isRendering || now - self.lastFrameTime < 1.0 / 24.0 {
            self.lock.unlock()
            return
        }
        self.isRendering = true
        self.lastFrameTime = now
        self.wasShowing = true
        self.lock.unlock()

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            self.finishRendering()
            return
        }
        self.renderQueue.async {
            // Portrait, mirrored like the selfie preview, scaled down for speed.
            var image = CIImage(cvPixelBuffer: pixelBuffer).oriented(.leftMirrored)
            let factor = min(1.0, 360.0 / max(1.0, min(image.extent.width, image.extent.height)))
            image = image.transformed(by: CGAffineTransform(scaleX: factor, y: factor))
            image = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
            let processed = self.engine.applyActiveMask(to: image)
            let cgImage = self.ciContext.createCGImage(processed, from: processed.extent)

            DispatchQueue.main.async {
                if let cgImage {
                    handler(UIImage(cgImage: cgImage))
                }
                self.finishRendering()
            }
        }
    }

    private func finishRendering() {
        self.lock.lock()
        self.isRendering = false
        self.lock.unlock()
    }
}
