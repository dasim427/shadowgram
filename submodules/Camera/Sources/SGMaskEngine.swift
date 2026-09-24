import Foundation
import UIKit
import CoreImage
import Vision
import TelegramCore

// Shadowgram: applies an `SGMask` to camera frames. Faces and landmarks come from
// Vision, the person/background split from Vision's person segmentation (iOS 15+), and
// every effect is a Core Image filter chain, so the whole thing stays on the GPU apart
// from detection. Detection runs every other frame and the last result is reused.
public final class SGMaskEngine {
    /// The engine the round video recorder uses; it follows the active mask.
    public static let shared = SGMaskEngine()

    private struct Face {
        var bounds: CGRect
        var leftEye: CGPoint
        var rightEye: CGPoint
        var nose: CGPoint
        var mouth: CGPoint
        var chin: CGPoint

        var center: CGPoint {
            return CGPoint(x: self.bounds.midX, y: self.bounds.midY)
        }
    }

    private var loadedRevision = -1
    private var activeMask: SGMask?
    private var frameIndex = 0
    private var lastFace: Face?
    private var lastFaceFrame = -100
    private var lastPersonMask: CIImage?
    private var lastPersonMaskFrame = -100
    private var emojiCache: [String: CIImage] = [:]
    private var imageCache: [String: CIImage] = [:]
    private var swapFaceCache: [String: CIImage] = [:]

    public init() {
    }

    // MARK: - Entry points

    /// Applies the active mask when masks are on for rounds; otherwise returns `image`.
    public func applyActiveMask(to image: CIImage) -> CIImage {
        guard SGExtrasManager.shared.roundMasksEnabled else {
            return image
        }
        let revision = SGMaskStore.revision
        if revision != self.loadedRevision {
            self.loadedRevision = revision
            self.activeMask = SGMaskStore.activeMask()
            self.imageCache.removeAll()
            self.swapFaceCache.removeAll()
        }
        guard let mask = self.activeMask else {
            return image
        }
        return self.apply(mask: mask, to: image)
    }

    /// Applies `mask` to one frame. Call from a single serial queue.
    public func apply(mask: SGMask, to image: CIImage) -> CIImage {
        let layers = mask.layers.filter { $0.isEnabled }
        if layers.isEmpty {
            return image
        }
        self.frameIndex += 1
        let extent = image.extent

        var face: Face?
        if layers.contains(where: { $0.kind.needsFace }) {
            if self.frameIndex - self.lastFaceFrame >= 2 {
                self.lastFace = self.detectFace(in: image)
                self.lastFaceFrame = self.frameIndex
            }
            face = self.lastFace
        }

        var personMask: CIImage?
        if layers.contains(where: { $0.kind.needsBackgroundSeparation }) {
            if self.frameIndex - self.lastPersonMaskFrame >= 2 {
                self.lastPersonMask = self.detectPerson(in: image)
                self.lastPersonMaskFrame = self.frameIndex
            }
            personMask = self.lastPersonMask
        }

        var result = image
        for layer in layers {
            result = self.applyLayer(layer, to: result, face: face, personMask: personMask, extent: extent)
        }
        return result.cropped(to: extent)
    }

    // MARK: - Detection

    private func detectFace(in image: CIImage) -> Face? {
        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let observation = (request.results ?? []).max(by: { $0.boundingBox.width < $1.boundingBox.width }) else {
            return nil
        }
        let extent = image.extent
        let box = observation.boundingBox
        let bounds = CGRect(x: extent.minX + box.minX * extent.width, y: extent.minY + box.minY * extent.height, width: box.width * extent.width, height: box.height * extent.height)

        func point(_ normalized: CGPoint) -> CGPoint {
            return CGPoint(x: bounds.minX + normalized.x * bounds.width, y: bounds.minY + normalized.y * bounds.height)
        }
        func centroid(_ region: VNFaceLandmarkRegion2D?, fallback: CGPoint) -> CGPoint {
            guard let region, region.pointCount > 0 else {
                return point(fallback)
            }
            var sum = CGPoint()
            for value in region.normalizedPoints {
                sum.x += value.x
                sum.y += value.y
            }
            let count = CGFloat(region.pointCount)
            return point(CGPoint(x: sum.x / count, y: sum.y / count))
        }

        let landmarks = observation.landmarks
        var chin = point(CGPoint(x: 0.5, y: 0.05))
        if let contour = landmarks?.faceContour, contour.pointCount > 0, let lowest = contour.normalizedPoints.min(by: { $0.y < $1.y }) {
            chin = point(lowest)
        }
        return Face(
            bounds: bounds,
            leftEye: centroid(landmarks?.leftEye, fallback: CGPoint(x: 0.3, y: 0.62)),
            rightEye: centroid(landmarks?.rightEye, fallback: CGPoint(x: 0.7, y: 0.62)),
            nose: centroid(landmarks?.nose, fallback: CGPoint(x: 0.5, y: 0.45)),
            mouth: centroid(landmarks?.outerLips, fallback: CGPoint(x: 0.5, y: 0.25)),
            chin: chin
        )
    }

    private func detectPerson(in image: CIImage) -> CIImage? {
        guard #available(iOS 15.0, *) else {
            return nil
        }
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .balanced
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let buffer = request.results?.first?.pixelBuffer else {
            return nil
        }
        let maskImage = CIImage(cvPixelBuffer: buffer)
        let extent = image.extent
        let scaleX = extent.width / max(1.0, maskImage.extent.width)
        let scaleY = extent.height / max(1.0, maskImage.extent.height)
        return maskImage
            .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
    }

    // MARK: - Layers

    private func applyLayer(_ layer: SGMaskLayer, to image: CIImage, face: Face?, personMask: CIImage?, extent: CGRect) -> CIImage {
        let intensity = CGFloat(max(0.0, min(1.0, layer.intensity)))
        switch layer.kind {
        case .blurFace:
            guard let face else {
                return image
            }
            let blurred = image.clampedToExtent().applyingGaussianBlur(sigma: Double(face.bounds.width * (0.03 + 0.09 * intensity))).cropped(to: extent)
            return self.blend(blurred, over: image, mask: self.faceMask(face, extent: extent, expand: 1.15))
        case .pixelateFace:
            guard let face else {
                return image
            }
            let blockSize = max(4.0, face.bounds.width / (22.0 - 16.0 * intensity))
            let pixelated = image.clampedToExtent().applyingFilter("CIPixellate", parameters: [
                kCIInputCenterKey: CIVector(cgPoint: face.center),
                kCIInputScaleKey: blockSize
            ]).cropped(to: extent)
            return self.blend(pixelated, over: image, mask: self.faceMask(face, extent: extent, expand: 1.15, hard: true))
        case .emojiFace:
            guard let face, let emoji = self.emojiImage(layer.text ?? "😎") else {
                return image
            }
            let side = max(face.bounds.width, face.bounds.height) * (1.1 + 0.5 * intensity)
            let placed = emoji
                .transformed(by: CGAffineTransform(scaleX: side / max(1.0, emoji.extent.width), y: side / max(1.0, emoji.extent.height)))
            let positioned = placed.transformed(by: CGAffineTransform(translationX: face.center.x - placed.extent.midX, y: face.center.y - placed.extent.midY))
            return positioned.composited(over: image)
        case .swapFace:
            guard let face, let data = layer.imageData, let photoFace = self.swapFaceImage(layer.id, data: data) else {
                return image
            }
            let target = face.bounds.insetBy(dx: -face.bounds.width * 0.08, dy: -face.bounds.height * 0.08)
            let scaled = photoFace.transformed(by: CGAffineTransform(scaleX: target.width / max(1.0, photoFace.extent.width), y: target.height / max(1.0, photoFace.extent.height)))
            let positioned = scaled.transformed(by: CGAffineTransform(translationX: target.minX - scaled.extent.minX, y: target.minY - scaled.extent.minY))
            let faded = positioned.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0.4 + 0.6 * intensity)])
            return self.blend(faded.composited(over: image), over: image, mask: self.faceMask(face, extent: extent, expand: 1.1))
        case .spotlight:
            guard let face else {
                return image
            }
            let dark = image.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: -0.5 - 2.5 * intensity])
            return self.blend(image, over: dark, mask: self.faceMask(face, extent: extent, expand: 1.6))
        case .faceVignette:
            guard let face else {
                return image
            }
            return image.applyingFilter("CIVignetteEffect", parameters: [
                kCIInputCenterKey: CIVector(cgPoint: face.center),
                kCIInputRadiusKey: max(face.bounds.width, face.bounds.height) * 0.9,
                kCIInputIntensityKey: 0.3 + 0.9 * intensity,
                "inputFalloff": 0.4
            ]).cropped(to: extent)
        case .bigEyes, .smallEyes:
            guard let face else {
                return image
            }
            let sign: CGFloat = layer.kind == .bigEyes ? 1.0 : -1.0
            let radius = face.bounds.width * 0.2
            var result = image
            for eye in [face.leftEye, face.rightEye] {
                result = self.bump(result, center: eye, radius: radius, scale: sign * 0.6 * intensity, extent: extent)
            }
            return result
        case .bigNose:
            guard let face else {
                return image
            }
            return self.bump(image, center: face.nose, radius: face.bounds.width * 0.22, scale: 0.7 * intensity, extent: extent)
        case .bigMouth:
            guard let face else {
                return image
            }
            return self.bump(image, center: face.mouth, radius: face.bounds.width * 0.28, scale: 0.6 * intensity, extent: extent)
        case .longChin:
            guard let face else {
                return image
            }
            return self.linearBump(image, center: face.chin, radius: face.bounds.width * 0.4, angle: 0.0, scale: 0.6 * intensity, extent: extent)
        case .narrowFace, .wideFace:
            guard let face else {
                return image
            }
            let sign: CGFloat = layer.kind == .wideFace ? 1.0 : -1.0
            return self.linearBump(image, center: face.center, radius: face.bounds.width * 0.75, angle: .pi / 2.0, scale: sign * 0.5 * intensity, extent: extent)
        case .bulgeFace:
            guard let face else {
                return image
            }
            return self.bump(image, center: face.center, radius: face.bounds.width * 0.7, scale: 0.5 * intensity, extent: extent)
        case .pinchFace:
            guard let face else {
                return image
            }
            return image.clampedToExtent().applyingFilter("CIPinchDistortion", parameters: [
                kCIInputCenterKey: CIVector(cgPoint: face.center),
                kCIInputRadiusKey: face.bounds.width * 0.7,
                kCIInputScaleKey: 0.5 * intensity
            ]).cropped(to: extent)
        case .colorFilter:
            let filtered = self.colorFiltered(image, filter: SGMaskColorFilter(rawValue: layer.filter ?? "") ?? .mono, extent: extent)
            if intensity >= 0.999 {
                return filtered
            }
            return image.applyingFilter("CIDissolveTransition", parameters: [
                kCIInputTargetImageKey: filtered,
                kCIInputTimeKey: intensity
            ]).cropped(to: extent)
        case .adjust:
            return image.applyingFilter("CIColorControls", parameters: [
                kCIInputBrightnessKey: CGFloat(layer.brightness) * 0.4,
                kCIInputContrastKey: 1.0 + CGFloat(layer.contrast) * 0.5,
                kCIInputSaturationKey: 1.0 + CGFloat(layer.saturation)
            ])
        case .overlayImage:
            guard let data = layer.imageData, let overlay = self.cachedImage(layer.id, data: data) else {
                return image
            }
            let side = extent.width * 0.4 * CGFloat(layer.scale)
            let factor = side / max(1.0, max(overlay.extent.width, overlay.extent.height))
            var placed = overlay.transformed(by: CGAffineTransform(scaleX: factor, y: factor))
            placed = placed.transformed(by: CGAffineTransform(translationX: -placed.extent.midX, y: -placed.extent.midY))
            placed = placed.transformed(by: CGAffineTransform(rotationAngle: -CGFloat(layer.rotation)))
            placed = placed.transformed(by: CGAffineTransform(translationX: extent.minX + CGFloat(layer.centerX) * extent.width, y: extent.maxY - CGFloat(layer.centerY) * extent.height))
            placed = placed.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0.2 + 0.8 * intensity)])
            return placed.composited(over: image)
        case .blurBackground:
            guard let personMask else {
                return image
            }
            let background = image.clampedToExtent().applyingGaussianBlur(sigma: Double(4.0 + 16.0 * intensity)).cropped(to: extent)
            return self.blend(image, over: background, mask: personMask)
        case .colorBackground:
            guard let personMask else {
                return image
            }
            let color = CIColor(red: CGFloat((layer.color >> 16) & 0xff) / 255.0, green: CGFloat((layer.color >> 8) & 0xff) / 255.0, blue: CGFloat(layer.color & 0xff) / 255.0)
            let background = CIImage(color: color).cropped(to: extent)
            let mixed = image.applyingFilter("CIDissolveTransition", parameters: [kCIInputTargetImageKey: background, kCIInputTimeKey: 0.3 + 0.7 * intensity]).cropped(to: extent)
            return self.blend(image, over: mixed, mask: personMask)
        case .imageBackground:
            guard let personMask, let data = layer.imageData, let picture = self.cachedImage(layer.id, data: data) else {
                return image
            }
            let factor = max(extent.width / max(1.0, picture.extent.width), extent.height / max(1.0, picture.extent.height))
            var background = picture.transformed(by: CGAffineTransform(scaleX: factor, y: factor))
            background = background.transformed(by: CGAffineTransform(translationX: extent.midX - background.extent.midX, y: extent.midY - background.extent.midY)).cropped(to: extent)
            return self.blend(image, over: background, mask: personMask)
        }
    }

    // MARK: - Helpers

    /// `foreground` where `mask` is white, `background` elsewhere.
    private func blend(_ foreground: CIImage, over background: CIImage, mask: CIImage) -> CIImage {
        return foreground.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: background,
            kCIInputMaskImageKey: mask
        ])
    }

    /// A soft (or hard-edged) ellipse over the face, white inside.
    private func faceMask(_ face: Face, extent: CGRect, expand: CGFloat, hard: Bool = false) -> CIImage {
        let radius: CGFloat = 100.0
        let gradient = CIFilter(name: "CIRadialGradient", parameters: [
            "inputCenter": CIVector(x: 0.0, y: 0.0),
            "inputRadius0": hard ? radius * 0.97 : radius * 0.75,
            "inputRadius1": radius,
            "inputColor0": CIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0),
            "inputColor1": CIColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0)
        ])?.outputImage ?? CIImage(color: CIColor(red: 1.0, green: 1.0, blue: 1.0)).cropped(to: CGRect(x: -radius, y: -radius, width: radius * 2.0, height: radius * 2.0))
        let scaleX = face.bounds.width * expand / 2.0 / radius
        let scaleY = face.bounds.height * expand * 0.62 / radius
        return gradient
            .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            .transformed(by: CGAffineTransform(translationX: face.center.x, y: face.center.y + face.bounds.height * 0.05))
            .cropped(to: extent)
    }

    private func bump(_ image: CIImage, center: CGPoint, radius: CGFloat, scale: CGFloat, extent: CGRect) -> CIImage {
        return image.clampedToExtent().applyingFilter("CIBumpDistortion", parameters: [
            kCIInputCenterKey: CIVector(cgPoint: center),
            kCIInputRadiusKey: radius,
            kCIInputScaleKey: scale
        ]).cropped(to: extent)
    }

    private func linearBump(_ image: CIImage, center: CGPoint, radius: CGFloat, angle: CGFloat, scale: CGFloat, extent: CGRect) -> CIImage {
        return image.clampedToExtent().applyingFilter("CIBumpDistortionLinear", parameters: [
            kCIInputCenterKey: CIVector(cgPoint: center),
            kCIInputRadiusKey: radius,
            kCIInputAngleKey: angle,
            kCIInputScaleKey: scale
        ]).cropped(to: extent)
    }

    private func colorFiltered(_ image: CIImage, filter: SGMaskColorFilter, extent: CGRect) -> CIImage {
        let center = CIVector(x: extent.midX, y: extent.midY)
        let output: CIImage
        switch filter {
        case .mono:
            output = image.applyingFilter("CIPhotoEffectMono")
        case .noir:
            output = image.applyingFilter("CIPhotoEffectNoir")
        case .sepia:
            output = image.applyingFilter("CISepiaTone", parameters: [kCIInputIntensityKey: 0.9])
        case .chrome:
            output = image.applyingFilter("CIPhotoEffectChrome")
        case .fade:
            output = image.applyingFilter("CIPhotoEffectFade")
        case .instant:
            output = image.applyingFilter("CIPhotoEffectInstant")
        case .process:
            output = image.applyingFilter("CIPhotoEffectProcess")
        case .transfer:
            output = image.applyingFilter("CIPhotoEffectTransfer")
        case .tonal:
            output = image.applyingFilter("CIPhotoEffectTonal").applyingFilter("CIColorMonochrome", parameters: [
                kCIInputColorKey: CIColor(red: 0.45, green: 0.9, blue: 0.55),
                kCIInputIntensityKey: 0.6
            ])
        case .invert:
            output = image.applyingFilter("CIColorInvert")
        case .thermal:
            output = image.applyingFilter("CIFalseColor", parameters: [
                "inputColor0": CIColor(red: 0.05, green: 0.0, blue: 0.35),
                "inputColor1": CIColor(red: 1.0, green: 0.85, blue: 0.1)
            ])
        case .posterize:
            output = image.applyingFilter("CIColorPosterize", parameters: ["inputLevels": 5.0])
        case .comic:
            output = image.applyingFilter("CIComicEffect")
        case .crystal:
            output = image.clampedToExtent().applyingFilter("CICrystallize", parameters: [kCIInputRadiusKey: max(6.0, extent.width / 40.0), kCIInputCenterKey: center])
        case .halftone:
            output = image.applyingFilter("CIDotScreen", parameters: [kCIInputCenterKey: center, kCIInputWidthKey: max(4.0, extent.width / 80.0), kCIInputSharpnessKey: 0.7])
        case .pointillize:
            output = image.clampedToExtent().applyingFilter("CIPointillize", parameters: [kCIInputRadiusKey: max(4.0, extent.width / 60.0), kCIInputCenterKey: center])
        case .sketch:
            output = image.applyingFilter("CILineOverlay")
                .composited(over: CIImage(color: CIColor(red: 1.0, green: 1.0, blue: 1.0)).cropped(to: extent))
        case .bloom:
            output = image.applyingFilter("CIBloom", parameters: [kCIInputRadiusKey: extent.width / 30.0, kCIInputIntensityKey: 1.0])
        case .kaleidoscope:
            output = image.clampedToExtent().applyingFilter("CIKaleidoscope", parameters: [kCIInputCenterKey: center, "inputCount": 6, kCIInputAngleKey: 0.0])
        }
        return output.cropped(to: extent)
    }

    private func emojiImage(_ emoji: String) -> CIImage? {
        if let cached = self.emojiCache[emoji] {
            return cached
        }
        let size = CGSize(width: 256.0, height: 256.0)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = false
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 200.0)]
            let textSize = emoji.size(withAttributes: attributes)
            emoji.draw(at: CGPoint(x: (size.width - textSize.width) / 2.0, y: (size.height - textSize.height) / 2.0), withAttributes: attributes)
        }
        guard let cgImage = rendered.cgImage else {
            return nil
        }
        let image = CIImage(cgImage: cgImage)
        self.emojiCache[emoji] = image
        return image
    }

    private func cachedImage(_ key: String, data: Data) -> CIImage? {
        if let cached = self.imageCache[key] {
            return cached
        }
        guard let uiImage = UIImage(data: data), let cgImage = uiImage.cgImage else {
            return nil
        }
        let image = CIImage(cgImage: cgImage).oriented(sgOrientation(uiImage.imageOrientation))
        let normalized = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
        self.imageCache[key] = normalized
        return normalized
    }

    /// The face cut out of the user's photo, for face swap.
    private func swapFaceImage(_ key: String, data: Data) -> CIImage? {
        if let cached = self.swapFaceCache[key] {
            return cached
        }
        guard let photo = self.cachedImage(key, data: data) else {
            return nil
        }
        guard let face = self.detectFace(in: photo) else {
            return nil
        }
        let crop = face.bounds.insetBy(dx: -face.bounds.width * 0.08, dy: -face.bounds.height * 0.08).intersection(photo.extent)
        let cut = photo.cropped(to: crop)
        let normalized = cut.transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
        self.swapFaceCache[key] = normalized
        return normalized
    }
}

private func sgOrientation(_ orientation: UIImage.Orientation) -> CGImagePropertyOrientation {
    switch orientation {
    case .up:
        return .up
    case .down:
        return .down
    case .left:
        return .left
    case .right:
        return .right
    case .upMirrored:
        return .upMirrored
    case .downMirrored:
        return .downMirrored
    case .leftMirrored:
        return .leftMirrored
    case .rightMirrored:
        return .rightMirrored
    @unknown default:
        return .up
    }
}

/// Whether a picked photo has a face the swap layer can use.
public func sgMaskPhotoHasFace(_ data: Data) -> Bool {
    guard let uiImage = UIImage(data: data), let cgImage = uiImage.cgImage else {
        return false
    }
    let request = VNDetectFaceRectanglesRequest()
    let handler = VNImageRequestHandler(cgImage: cgImage, orientation: sgOrientation(uiImage.imageOrientation), options: [:])
    do {
        try handler.perform([request])
    } catch {
        return false
    }
    return !(request.results ?? []).isEmpty
}
