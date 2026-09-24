import Foundation
import AVFoundation
import UIKit
import UniformTypeIdentifiers
import TgVoipWebrtc

// Shadowgram: the call soundpad. Sounds are mixed into the outgoing call audio by
// SGCallAudioEffects, as 16-bit mono PCM at 48 kHz. A few simple sounds are synthesized
// here; the rest are the user's own audio files, kept in Documents/SGSoundpad.

struct SGSound: Equatable {
    enum Source: Equatable {
        case builtIn(String)
        case file(String)
    }

    var title: String
    var source: Source
}

private let sgSoundpadMaxSeconds = 30.0

private func sgSoundpadDirectory() -> String {
    return NSHomeDirectory() + "/Documents/SGSoundpad"
}

let sgBuiltInSounds: [SGSound] = [
    SGSound(title: "Сигнал", source: .builtIn("beep")),
    SGSound(title: "Двойной сигнал", source: .builtIn("doubleBeep")),
    SGSound(title: "Сирена", source: .builtIn("siren")),
    SGSound(title: "Гудок", source: .builtIn("horn")),
    SGSound(title: "Трель звонка", source: .builtIn("ring")),
    SGSound(title: "Помехи", source: .builtIn("static"))
]

func sgUserSounds() -> [SGSound] {
    let names = (try? FileManager.default.contentsOfDirectory(atPath: sgSoundpadDirectory())) ?? []
    return names.filter { !$0.hasPrefix(".") }.sorted().map { name in
        SGSound(title: (name as NSString).deletingPathExtension, source: .file(name))
    }
}

func sgDeleteSound(_ sound: SGSound) {
    if case let .file(name) = sound.source {
        let _ = try? FileManager.default.removeItem(atPath: sgSoundpadDirectory() + "/" + name)
    }
}

/// Copies an audio file into the soundpad. Returns false if it cannot be decoded.
func sgImportSound(from url: URL) -> Bool {
    let isAccessing = url.startAccessingSecurityScopedResource()
    defer {
        if isAccessing {
            url.stopAccessingSecurityScopedResource()
        }
    }
    guard sgDecodeSound(url: url) != nil else {
        return false
    }
    let _ = try? FileManager.default.createDirectory(atPath: sgSoundpadDirectory(), withIntermediateDirectories: true, attributes: nil)
    let target = sgSoundpadDirectory() + "/" + url.lastPathComponent
    let _ = try? FileManager.default.removeItem(atPath: target)
    do {
        try FileManager.default.copyItem(at: url, to: URL(fileURLWithPath: target))
        return true
    } catch {
        return false
    }
}

/// Plays a sound into the current call.
@discardableResult
func sgPlaySound(_ sound: SGSound) -> Bool {
    let data: Data?
    switch sound.source {
    case let .builtIn(name):
        data = sgSynthesizeSound(name)
    case let .file(name):
        data = sgDecodeSound(url: URL(fileURLWithPath: sgSoundpadDirectory() + "/" + name))
    }
    guard let data else {
        return false
    }
    SGCallAudioEffects.playPCM16Mono48k(data)
    return true
}

// MARK: - Decoding

/// Any audio file iOS can read, as 16-bit mono PCM at 48 kHz, cut to 30 seconds.
private func sgDecodeSound(url: URL) -> Data? {
    guard let file = try? AVAudioFile(forReading: url) else {
        return nil
    }
    guard let outputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 48000.0, channels: 1, interleaved: true), let converter = AVAudioConverter(from: file.processingFormat, to: outputFormat) else {
        return nil
    }
    let inputFrames = AVAudioFrameCount(min(Double(file.length), sgSoundpadMaxSeconds * file.processingFormat.sampleRate))
    guard inputFrames > 0, let inputBuffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: inputFrames) else {
        return nil
    }
    do {
        try file.read(into: inputBuffer, frameCount: inputFrames)
    } catch {
        return nil
    }
    let outputCapacity = AVAudioFrameCount(Double(inputBuffer.frameLength) * 48000.0 / file.processingFormat.sampleRate) + 1024
    guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputCapacity) else {
        return nil
    }
    var consumed = false
    var conversionError: NSError?
    let status = converter.convert(to: outputBuffer, error: &conversionError, withInputFrom: { _, inputStatus in
        if consumed {
            inputStatus.pointee = .endOfStream
            return nil
        }
        consumed = true
        inputStatus.pointee = .haveData
        return inputBuffer
    })
    guard status != .error, conversionError == nil, let channel = outputBuffer.int16ChannelData else {
        return nil
    }
    return Data(bytes: channel[0], count: Int(outputBuffer.frameLength) * MemoryLayout<Int16>.size)
}

// MARK: - Synthesis

private func sgSynthesizeSound(_ name: String) -> Data? {
    let rate = 48000.0
    var samples: [Int16] = []

    func append(duration: Double, _ generator: (Double) -> Double) {
        let count = Int(duration * rate)
        samples.reserveCapacity(samples.count + count)
        for index in 0 ..< count {
            let t = Double(index) / rate
            // Short fades at both ends so the sound does not click.
            let fade = min(1.0, min(t, duration - t) / 0.01)
            let value = max(-1.0, min(1.0, generator(t))) * fade * 0.8
            samples.append(Int16(value * 32767.0))
        }
    }
    func silence(_ duration: Double) {
        samples.append(contentsOf: [Int16](repeating: 0, count: Int(duration * rate)))
    }

    switch name {
    case "beep":
        append(duration: 0.35) { sin(2.0 * .pi * 1000.0 * $0) }
    case "doubleBeep":
        append(duration: 0.15) { sin(2.0 * .pi * 1200.0 * $0) }
        silence(0.1)
        append(duration: 0.15) { sin(2.0 * .pi * 1200.0 * $0) }
    case "siren":
        var phase = 0.0
        append(duration: 2.4) { t in
            let frequency = 700.0 + 400.0 * sin(2.0 * .pi * 1.2 * t)
            phase += 2.0 * .pi * frequency / rate
            return sin(phase)
        }
    case "horn":
        append(duration: 0.8) { t in
            let a = sin(2.0 * .pi * 220.0 * t)
            let b = sin(2.0 * .pi * 277.0 * t)
            return (a + b) * 0.6
        }
    case "ring":
        for _ in 0 ..< 2 {
            append(duration: 0.4) { t in
                (sin(2.0 * .pi * 440.0 * t) + sin(2.0 * .pi * 480.0 * t)) * 0.5 * (sin(2.0 * .pi * 20.0 * t) > 0 ? 1.0 : 0.3)
            }
            silence(0.2)
        }
    case "static":
        var generator = SystemRandomNumberGenerator()
        append(duration: 1.2) { _ in
            Double(Int.random(in: -1000 ... 1000, using: &generator)) / 1000.0 * 0.5
        }
    default:
        return nil
    }
    return samples.withUnsafeBufferPointer { Data(buffer: $0) }
}

/// Picks an audio file for the soundpad.
@available(iOS 14.0, *)
final class SGSoundFilePicker: NSObject, UIDocumentPickerDelegate {
    private static var current: SGSoundFilePicker?

    private let completion: (Bool) -> Void

    private init(completion: @escaping (Bool) -> Void) {
        self.completion = completion
    }

    static func present(from controller: UIViewController, completion: @escaping (Bool) -> Void) {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.audio], asCopy: true)
        let handler = SGSoundFilePicker(completion: completion)
        SGSoundFilePicker.current = handler
        picker.delegate = handler
        controller.present(picker, animated: true, completion: nil)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        let completion = self.completion
        SGSoundFilePicker.current = nil
        guard let url = urls.first else {
            completion(false)
            return
        }
        completion(sgImportSound(from: url))
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        SGSoundFilePicker.current = nil
    }
}
