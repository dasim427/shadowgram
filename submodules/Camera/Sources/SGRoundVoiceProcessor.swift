import Foundation
import AVFoundation
import CoreMedia
import TelegramCore

// Shadowgram: applies the voice from "Voice double" (VoiceMorpherManager) to the sound
// of round videos while they are recorded. Same real-time approach as the call effects:
// a two-tap delay-line pitch shifter, a telephone band-pass and a ring-modulated robot.
final class SGRoundVoiceProcessor {
    static let shared = SGRoundVoiceProcessor()

    private var buffer = [Float](repeating: 0.0, count: 16384)
    private var writePosition = 0
    private var phase = 0.0
    private var ringPhase = 0.0
    private var lastPreset: VoiceMorpherManager.VoicePreset = .disabled
    private var lastSampleRate = 0.0
    private var highPass = SGBiquad()
    private var lowPass = SGBiquad()

    /// Returns a processed copy, or nil when the voice is off or the format is unsupported.
    func process(_ sampleBuffer: CMSampleBuffer) -> CMSampleBuffer? {
        let preset = VoiceMorpherManager.shared.effectivePreset
        if preset == .disabled {
            return nil
        }
        guard let format = CMSampleBufferGetFormatDescription(sampleBuffer), let description = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee, description.mFormatID == kAudioFormatLinearPCM else {
            return nil
        }
        let isFloat = description.mFormatFlags & kAudioFormatFlagIsFloat != 0
        let isNonInterleaved = description.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        let bitsPerChannel = Int(description.mBitsPerChannel)
        let channels = max(1, Int(description.mChannelsPerFrame))
        guard !isNonInterleaved, (isFloat && bitsPerChannel == 32) || (!isFloat && bitsPerChannel == 16) else {
            return nil
        }
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return nil
        }
        let length = CMBlockBufferGetDataLength(blockBuffer)
        if length == 0 {
            return nil
        }
        var bytes = [UInt8](repeating: 0, count: length)
        let copyStatus = bytes.withUnsafeMutableBytes { pointer -> OSStatus in
            return CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: pointer.baseAddress!)
        }
        if copyStatus != noErr {
            return nil
        }

        let sampleRate = description.mSampleRate
        if preset != self.lastPreset || sampleRate != self.lastSampleRate {
            self.reset()
            self.lastPreset = preset
            self.lastSampleRate = sampleRate
        }

        bytes.withUnsafeMutableBytes { raw in
            if isFloat {
                let samples = raw.bindMemory(to: Float.self)
                let frames = samples.count / channels
                for frame in 0 ..< frames {
                    let value = self.processSample(samples[frame * channels] * 32767.0, preset: preset, sampleRate: sampleRate) / 32767.0
                    for channel in 0 ..< channels {
                        samples[frame * channels + channel] = max(-1.0, min(1.0, value))
                    }
                }
            } else {
                let samples = raw.bindMemory(to: Int16.self)
                let frames = samples.count / channels
                for frame in 0 ..< frames {
                    let value = self.processSample(Float(samples[frame * channels]), preset: preset, sampleRate: sampleRate)
                    let clamped = Int16(max(-32768.0, min(32767.0, value)))
                    for channel in 0 ..< channels {
                        samples[frame * channels + channel] = clamped
                    }
                }
            }
        }

        var newBlockBuffer: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: length, blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0, dataLength: length, flags: 0, blockBufferOut: &newBlockBuffer) == noErr, let newBlockBuffer else {
            return nil
        }
        let replaceStatus = bytes.withUnsafeBytes { pointer -> OSStatus in
            return CMBlockBufferReplaceDataBytes(with: pointer.baseAddress!, blockBuffer: newBlockBuffer, offsetIntoDestination: 0, dataLength: length)
        }
        if replaceStatus != noErr {
            return nil
        }
        var result: CMSampleBuffer?
        let createStatus = CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: kCFAllocatorDefault, dataBuffer: newBlockBuffer, formatDescription: format, sampleCount: CMSampleBufferGetNumSamples(sampleBuffer), presentationTimeStamp: CMSampleBufferGetPresentationTimeStamp(sampleBuffer), packetDescriptions: nil, sampleBufferOut: &result)
        if createStatus != noErr {
            return nil
        }
        return result
    }

    private func reset() {
        for index in 0 ..< self.buffer.count {
            self.buffer[index] = 0.0
        }
        self.writePosition = 0
        self.phase = 0.0
        self.ringPhase = 0.0
        self.highPass = SGBiquad()
        self.lowPass = SGBiquad()
    }

    private func processSample(_ input: Float, preset: VoiceMorpherManager.VoicePreset, sampleRate: Double) -> Float {
        var value = input
        let semitones = Double(preset.pitchShift) / 100.0
        if semitones != 0.0 {
            value = self.pitchShift(value, ratio: pow(2.0, semitones / 12.0), window: sampleRate * 0.04)
        }
        switch preset {
        case .robot:
            value *= Float(sin(self.ringPhase)) * 1.4
            self.ringPhase += 2.0 * Double.pi * 60.0 / sampleRate
            if self.ringPhase > 2.0 * Double.pi {
                self.ringPhase -= 2.0 * Double.pi
            }
        case .anonymous:
            self.highPass.configure(highPass: true, frequency: 350.0, sampleRate: sampleRate)
            self.lowPass.configure(highPass: false, frequency: 3200.0, sampleRate: sampleRate)
            value = self.lowPass.process(self.highPass.process(value)) * 1.3
        default:
            break
        }
        return value
    }

    private func pitchShift(_ input: Float, ratio: Double, window: Double) -> Float {
        let size = self.buffer.count
        self.buffer[self.writePosition] = input
        var secondPhase = self.phase + 0.5
        if secondPhase >= 1.0 {
            secondPhase -= 1.0
        }
        let first = self.read(delay: self.phase * window)
        let second = self.read(delay: secondPhase * window)
        var firstGain = Float(sin(Double.pi * self.phase))
        firstGain *= firstGain
        var secondGain = Float(sin(Double.pi * secondPhase))
        secondGain *= secondGain
        self.writePosition = (self.writePosition + 1) % size
        self.phase += (1.0 - ratio) / window
        while self.phase >= 1.0 {
            self.phase -= 1.0
        }
        while self.phase < 0.0 {
            self.phase += 1.0
        }
        return first * firstGain + second * secondGain
    }

    private func read(delay: Double) -> Float {
        let size = self.buffer.count
        var position = Double(self.writePosition) - delay
        while position < 0.0 {
            position += Double(size)
        }
        let index = Int(position) % size
        let next = (index + 1) % size
        let fraction = Float(position - floor(position))
        return self.buffer[index] * (1.0 - fraction) + self.buffer[next] * fraction
    }
}

/// RBJ biquad for the telephone band-pass.
private struct SGBiquad {
    private var configured: (Bool, Double, Double)?
    private var b0 = 1.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0
    private var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0

    mutating func configure(highPass: Bool, frequency: Double, sampleRate: Double) {
        if let configured = self.configured, configured.0 == highPass, configured.1 == frequency, configured.2 == sampleRate {
            return
        }
        self.configured = (highPass, frequency, sampleRate)
        let omega = 2.0 * Double.pi * frequency / sampleRate
        let alpha = sin(omega) / (2.0 * 0.707)
        let cosOmega = cos(omega)
        let a0 = 1.0 + alpha
        if highPass {
            self.b0 = (1.0 + cosOmega) / 2.0 / a0
            self.b1 = -(1.0 + cosOmega) / a0
            self.b2 = (1.0 + cosOmega) / 2.0 / a0
        } else {
            self.b0 = (1.0 - cosOmega) / 2.0 / a0
            self.b1 = (1.0 - cosOmega) / a0
            self.b2 = (1.0 - cosOmega) / 2.0 / a0
        }
        self.a1 = (-2.0 * cosOmega) / a0
        self.a2 = (1.0 - alpha) / a0
    }

    mutating func process(_ input: Float) -> Float {
        let x = Double(input)
        let y = self.b0 * x + self.b1 * self.x1 + self.b2 * self.x2 - self.a1 * self.y1 - self.a2 * self.y2
        self.x2 = self.x1
        self.x1 = x
        self.y2 = self.y1
        self.y1 = y
        return Float(y)
    }
}
