import Foundation
import UIKit
import AVFoundation
import CoreImage
import ImageIO
import TelegramCore
import TelegramVoip
import Display
import Camera

// Shadowgram: the camera a video call gets. Normally Telegram's own capturer; with a
// replacement picked in Shadowgram settings it is a custom capturer fed by
// `SGCallVideoSource` — a looping picture/GIF/video, or the front camera with the active
// mask. The source stays alive exactly as long as the capturer does.
func sgMakeCallVideoCapturer() -> OngoingCallVideoCapturer {
    switch SGCallVideoStore.mode {
    case .off:
        return OngoingCallVideoCapturer()
    case .media:
        guard SGCallVideoStore.mediaPath != nil else {
            return OngoingCallVideoCapturer()
        }
        let capturer = OngoingCallVideoCapturer(isCustom: true)
        SGCallVideoSource.attach(to: capturer, mode: .media)
        return capturer
    case .maskedCamera:
        let capturer = OngoingCallVideoCapturer(isCustom: true)
        SGCallVideoSource.attach(to: capturer, mode: .maskedCamera)
        return capturer
    }
}

private let sgCallVideoSourceKey = NSObject()

final class SGCallVideoSource: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private weak var capturer: OngoingCallVideoCapturer?
    private let queue = DispatchQueue(label: "shadowgram.call.video")
    private var timer: DispatchSourceTimer?

    // Pictures and GIFs
    private var frames: [(image: UIImage, duration: Double)] = []
    private var totalDuration: Double = 0.0
    private var startTime: Double = 0.0
    private var staticSampleBuffer: CMSampleBuffer?

    // Videos
    private var videoAsset: AVAsset?
    private var videoReader: AVAssetReader?
    private var videoOutput: AVAssetReaderTrackOutput?
    private var videoTransform: CGAffineTransform = .identity
    private var videoStartTime: Double = 0.0

    // Masked camera
    private var session: AVCaptureSession?
    private let engine = SGMaskEngine()
    private var mask: SGMask?
    private var maskRevision = -1
    private let ciContext = CIContext()
    private var pixelBufferPool: CVPixelBufferPool?
    private var poolSize: CGSize = .zero

    static func attach(to capturer: OngoingCallVideoCapturer, mode: SGCallVideoMode) {
        let source = SGCallVideoSource(capturer: capturer)
        objc_setAssociatedObject(capturer, Unmanaged.passUnretained(sgCallVideoSourceKey).toOpaque(), source, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        switch mode {
        case .media:
            source.startMedia()
        case .maskedCamera:
            source.startMaskedCamera()
        case .off:
            break
        }
    }

    private init(capturer: OngoingCallVideoCapturer) {
        self.capturer = capturer
        super.init()
    }

    deinit {
        self.timer?.cancel()
        if let session = self.session {
            DispatchQueue.global(qos: .userInitiated).async {
                session.stopRunning()
            }
        }
    }

    private func inject(_ sampleBuffer: CMSampleBuffer) {
        guard let capturer = self.capturer else {
            self.timer?.cancel()
            return
        }
        capturer.injectSampleBuffer(sampleBuffer, rotation: .up, completion: {})
    }

    // MARK: - Pictures, GIFs and videos

    private func startMedia() {
        guard let path = SGCallVideoStore.mediaPath else {
            return
        }
        self.queue.async {
            if SGCallVideoStore.mediaIsVideo {
                self.videoAsset = AVURLAsset(url: URL(fileURLWithPath: path))
                if !self.restartVideoReader() {
                    return
                }
                self.videoStartTime = CACurrentMediaTime()
            } else {
                self.loadFrames(path: path)
                if self.frames.isEmpty {
                    return
                }
                self.startTime = CACurrentMediaTime()
                if self.frames.count == 1 {
                    self.staticSampleBuffer = self.frames[0].image.cmSampleBuffer
                }
            }
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now(), repeating: 1.0 / 30.0)
            timer.setEventHandler { [weak self] in
                self?.mediaTick()
            }
            self.timer = timer
            timer.resume()
        }
    }

    private func loadFrames(path: String) {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else {
            return
        }
        let count = min(CGImageSourceGetCount(source), 90)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 640,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        var result: [(image: UIImage, duration: Double)] = []
        var total = 0.0
        for index in 0 ..< count {
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary) else {
                continue
            }
            var duration = 0.1
            if let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any], let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] {
                if let value = gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double, value > 0.01 {
                    duration = value
                } else if let value = gif[kCGImagePropertyGIFDelayTime] as? Double, value > 0.01 {
                    duration = value
                }
            }
            result.append((UIImage(cgImage: cgImage), duration))
            total += duration
        }
        self.frames = result
        self.totalDuration = max(0.1, total)
    }

    private func restartVideoReader() -> Bool {
        self.videoReader?.cancelReading()
        guard let asset = self.videoAsset, let track = asset.tracks(withMediaType: .video).first, let reader = try? AVAssetReader(asset: asset) else {
            return false
        }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            return false
        }
        reader.add(output)
        guard reader.startReading() else {
            return false
        }
        self.videoReader = reader
        self.videoOutput = output
        self.videoTransform = track.preferredTransform
        return true
    }

    private func mediaTick() {
        if self.capturer == nil {
            self.timer?.cancel()
            return
        }
        if self.videoAsset != nil {
            self.videoTick()
            return
        }
        if let staticSampleBuffer = self.staticSampleBuffer {
            self.inject(staticSampleBuffer)
            return
        }
        var elapsed = (CACurrentMediaTime() - self.startTime).truncatingRemainder(dividingBy: self.totalDuration)
        for frame in self.frames {
            if elapsed < frame.duration {
                if let sampleBuffer = frame.image.cmSampleBuffer {
                    self.inject(sampleBuffer)
                }
                return
            }
            elapsed -= frame.duration
        }
    }

    private func videoTick() {
        guard let output = self.videoOutput else {
            return
        }
        let elapsed = CACurrentMediaTime() - self.videoStartTime
        var latest: CMSampleBuffer?
        while true {
            guard let next = output.copyNextSampleBuffer() else {
                // End of the video: start over.
                if self.restartVideoReader() {
                    self.videoStartTime = CACurrentMediaTime()
                }
                break
            }
            latest = next
            if CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(next)) >= elapsed {
                break
            }
        }
        guard let latest, let pixelBuffer = CMSampleBufferGetImageBuffer(latest) else {
            return
        }
        let upright = CIImage(cvPixelBuffer: pixelBuffer).transformed(by: self.videoTransform)
        let normalized = upright.transformed(by: CGAffineTransform(translationX: -upright.extent.minX, y: -upright.extent.minY))
        if let sampleBuffer = self.render(normalized) {
            self.inject(sampleBuffer)
        }
    }

    // MARK: - Masked camera

    private func startMaskedCamera() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front), let input = try? AVCaptureDeviceInput(device: device) else {
            return
        }
        let session = AVCaptureSession()
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: self.queue)
        session.beginConfiguration()
        if session.canSetSessionPreset(.hd1280x720) {
            session.sessionPreset = .hd1280x720
        }
        if session.canAddInput(input) {
            session.addInput(input)
        }
        if session.canAddOutput(output) {
            session.addOutput(output)
        }
        session.commitConfiguration()
        self.session = session
        self.queue.async {
            session.startRunning()
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if self.capturer == nil {
            self.session?.stopRunning()
            return
        }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        // Front camera frames arrive sideways; turn them upright as the other side sees them.
        var image = CIImage(cvPixelBuffer: pixelBuffer).oriented(.right)
        image = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
        let revision = SGMaskStore.revision
        if revision != self.maskRevision {
            self.maskRevision = revision
            self.mask = SGMaskStore.activeMask()
        }
        if let mask = self.mask {
            image = self.engine.apply(mask: mask, to: image)
        }
        if let result = self.render(image) {
            self.inject(result)
        }
    }

    // MARK: - Rendering

    private func render(_ image: CIImage) -> CMSampleBuffer? {
        let size = CGSize(width: floor(image.extent.width), height: floor(image.extent.height))
        if size.width < 2.0 || size.height < 2.0 {
            return nil
        }
        if self.pixelBufferPool == nil || self.poolSize != size {
            let attributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height),
                kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()
            ]
            var pool: CVPixelBufferPool?
            CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attributes as CFDictionary, &pool)
            self.pixelBufferPool = pool
            self.poolSize = size
        }
        guard let pool = self.pixelBufferPool else {
            return nil
        }
        var pixelBufferOut: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBufferOut)
        guard let pixelBuffer = pixelBufferOut else {
            return nil
        }
        self.ciContext.render(image, to: pixelBuffer)

        var formatDescription: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescriptionOut: &formatDescription)
        guard let formatDescription else {
            return nil
        }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 30), presentationTimeStamp: CMTime(seconds: CACurrentMediaTime(), preferredTimescale: 1000), decodeTimeStamp: .invalid)
        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, dataReady: true, makeDataReadyCallback: nil, refcon: nil, formatDescription: formatDescription, sampleTiming: &timing, sampleBufferOut: &sampleBuffer)
        return sampleBuffer
    }
}
