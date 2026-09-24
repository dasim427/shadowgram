#import <TgVoipWebrtc/SGCallAudioEffects.h>

#include <algorithm>
#include <atomic>
#include <cmath>
#include <mutex>
#include <vector>

// Shadowgram: real-time call audio effects. Everything here runs on the audio thread for
// every 10 ms chunk, so it is plain arithmetic on preallocated buffers.

namespace {

static NSString *const kSGVoicePresetKey = @"SG.callVoice.preset";
static NSString *const kSGSilentMicKey = @"SG.callVoice.silentMic";
static NSString *const kSGSoundVolumeKey = @"SG.callVoice.soundVolume";

std::atomic<int> sgPreset{-1};
std::atomic<int> sgSilent{-1};
std::atomic<float> sgSoundVolume{-1.0f};

std::mutex sgSoundMutex;
std::vector<int16_t> sgSound;
double sgSoundPosition = 0.0;
std::atomic<bool> sgSoundPlaying{false};
std::atomic<long> sgCapturedChunks{0};
std::atomic<long> sgProcessedChunks{0};

/// Pitch shifting with two read heads sweeping through a short delay line, crossfaded
/// with complementary sin² windows. About one window (~40 ms) of latency.
class PitchShifter {
public:
    PitchShifter() : _buffer(16384, 0.0f) {
    }

    void reset() {
        std::fill(_buffer.begin(), _buffer.end(), 0.0f);
        _writePosition = 0;
        _phase = 0.0;
    }

    float process(float input, double ratio, double window) {
        const size_t size = _buffer.size();
        _buffer[_writePosition] = input;

        double secondPhase = _phase + 0.5;
        if (secondPhase >= 1.0) {
            secondPhase -= 1.0;
        }
        const float first = read(_phase * window);
        const float second = read(secondPhase * window);
        float firstGain = (float)std::sin(M_PI * _phase);
        firstGain *= firstGain;
        float secondGain = (float)std::sin(M_PI * secondPhase);
        secondGain *= secondGain;

        _writePosition = (_writePosition + 1) % size;
        _phase += (1.0 - ratio) / window;
        while (_phase >= 1.0) {
            _phase -= 1.0;
        }
        while (_phase < 0.0) {
            _phase += 1.0;
        }
        return first * firstGain + second * secondGain;
    }

private:
    float read(double delay) {
        const size_t size = _buffer.size();
        double position = (double)_writePosition - delay;
        while (position < 0.0) {
            position += (double)size;
        }
        const size_t index = (size_t)position % size;
        const size_t next = (index + 1) % size;
        const float fraction = (float)(position - std::floor(position));
        return _buffer[index] * (1.0f - fraction) + _buffer[next] * fraction;
    }

    std::vector<float> _buffer;
    size_t _writePosition = 0;
    double _phase = 0.0;
};

/// RBJ biquad, used as the high- and low-pass of the telephone effect.
class Biquad {
public:
    void configure(bool highPass, double frequency, double sampleRate) {
        if (_configuredFrequency == frequency && _configuredRate == sampleRate && _configuredHighPass == highPass) {
            return;
        }
        _configuredFrequency = frequency;
        _configuredRate = sampleRate;
        _configuredHighPass = highPass;
        const double omega = 2.0 * M_PI * frequency / sampleRate;
        const double alpha = std::sin(omega) / (2.0 * 0.707);
        const double cosOmega = std::cos(omega);
        double b0, b1, b2;
        if (highPass) {
            b0 = (1.0 + cosOmega) / 2.0;
            b1 = -(1.0 + cosOmega);
            b2 = (1.0 + cosOmega) / 2.0;
        } else {
            b0 = (1.0 - cosOmega) / 2.0;
            b1 = 1.0 - cosOmega;
            b2 = (1.0 - cosOmega) / 2.0;
        }
        const double a0 = 1.0 + alpha;
        _b0 = b0 / a0;
        _b1 = b1 / a0;
        _b2 = b2 / a0;
        _a1 = (-2.0 * cosOmega) / a0;
        _a2 = (1.0 - alpha) / a0;
    }

    float process(float x) {
        const double y = _b0 * x + _b1 * _x1 + _b2 * _x2 - _a1 * _y1 - _a2 * _y2;
        _x2 = _x1;
        _x1 = x;
        _y2 = _y1;
        _y1 = y;
        return (float)y;
    }

private:
    double _configuredFrequency = -1.0;
    double _configuredRate = -1.0;
    bool _configuredHighPass = false;
    double _b0 = 1.0, _b1 = 0.0, _b2 = 0.0, _a1 = 0.0, _a2 = 0.0;
    double _x1 = 0.0, _x2 = 0.0, _y1 = 0.0, _y2 = 0.0;
};

PitchShifter sgPitchShifter;
Biquad sgHighPass;
Biquad sgLowPass;
double sgRingPhase = 0.0;
int sgLastPreset = -1;

std::atomic<double> sgLastSettingsRead{0.0};

void reloadSettingsIfNeeded() {
    const double now = CFAbsoluteTimeGetCurrent();
    if (sgPreset.load() >= 0 && now - sgLastSettingsRead.load() < 1.0) {
        return;
    }
    sgLastSettingsRead.store(now);
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    sgPreset.store((int)[defaults integerForKey:kSGVoicePresetKey]);
    sgSilent.store([defaults boolForKey:kSGSilentMicKey] ? 1 : 0);
    NSNumber *storedVolume = [defaults objectForKey:kSGSoundVolumeKey];
    sgSoundVolume.store(storedVolume != nil ? storedVolume.floatValue : 0.8f);
}

int currentPreset() {
    reloadSettingsIfNeeded();
    return sgPreset.load();
}

bool currentSilent() {
    reloadSettingsIfNeeded();
    return sgSilent.load() != 0;
}

float currentSoundVolume() {
    reloadSettingsIfNeeded();
    return sgSoundVolume.load();
}

/// Semitones to a frequency ratio.
double ratioForSemitones(double semitones) {
    return std::pow(2.0, semitones / 12.0);
}

}

@implementation SGCallAudioEffects

+ (SGCallVoicePreset)voicePreset {
    return (SGCallVoicePreset)currentPreset();
}

+ (void)setVoicePreset:(SGCallVoicePreset)preset {
    sgPreset.store((int)preset);
    [[NSUserDefaults standardUserDefaults] setInteger:preset forKey:kSGVoicePresetKey];
}

+ (BOOL)silentMicrophone {
    return currentSilent();
}

+ (void)setSilentMicrophone:(BOOL)value {
    sgSilent.store(value ? 1 : 0);
    [[NSUserDefaults standardUserDefaults] setBool:value forKey:kSGSilentMicKey];
}

+ (float)soundVolume {
    return currentSoundVolume();
}

+ (void)setSoundVolume:(float)value {
    float clamped = std::max(0.0f, std::min(1.0f, value));
    sgSoundVolume.store(clamped);
    [[NSUserDefaults standardUserDefaults] setFloat:clamped forKey:kSGSoundVolumeKey];
}

+ (void)playPCM16Mono48k:(NSData *)data {
    std::lock_guard<std::mutex> lock(sgSoundMutex);
    const int16_t *samples = (const int16_t *)data.bytes;
    sgSound.assign(samples, samples + data.length / 2);
    sgSoundPosition = 0.0;
    sgSoundPlaying.store(!sgSound.empty());
}

+ (void)stopSound {
    std::lock_guard<std::mutex> lock(sgSoundMutex);
    sgSound.clear();
    sgSoundPosition = 0.0;
    sgSoundPlaying.store(false);
}

+ (BOOL)isPlayingSound {
    return sgSoundPlaying.load();
}

+ (NSInteger)capturedChunkCount {
    return (NSInteger)sgCapturedChunks.load();
}

+ (NSInteger)processedChunkCount {
    return (NSInteger)sgProcessedChunks.load();
}

@end

void SGCallAudioEffectsNoteCapture(void) {
    sgCapturedChunks.fetch_add(1);
}

bool SGCallAudioEffectsIsActive(void) {
    return currentPreset() != SGCallVoicePresetOff || currentSilent() || sgSoundPlaying.load();
}

void SGCallAudioEffectsProcess(int16_t *samples, size_t frames, size_t channels, uint32_t sampleRate) {
    if (samples == nullptr || frames == 0 || channels == 0 || sampleRate == 0) {
        return;
    }
    sgProcessedChunks.fetch_add(1);
    const int preset = currentPreset();
    const bool silent = currentSilent();
    const double rate = (double)sampleRate;

    if (preset != sgLastPreset) {
        sgPitchShifter.reset();
        sgLastPreset = preset;
    }

    double semitones = 0.0;
    bool telephone = false;
    bool robot = false;
    switch (preset) {
        case SGCallVoicePresetMale:
            semitones = -4.0;
            break;
        case SGCallVoicePresetFemale:
            semitones = 4.0;
            break;
        case SGCallVoicePresetChild:
            semitones = 7.0;
            break;
        case SGCallVoicePresetDeep:
            semitones = -7.0;
            break;
        case SGCallVoicePresetAnonymous:
            semitones = -5.0;
            telephone = true;
            break;
        case SGCallVoicePresetRobot:
            robot = true;
            break;
        case SGCallVoicePresetTelephone:
            telephone = true;
            break;
        default:
            break;
    }
    const double ratio = ratioForSemitones(semitones);
    const double window = rate * 0.04;
    if (telephone) {
        sgHighPass.configure(true, 350.0, rate);
        sgLowPass.configure(false, 3200.0, rate);
    }

    std::unique_lock<std::mutex> soundLock(sgSoundMutex, std::defer_lock);
    const bool mixSound = sgSoundPlaying.load();
    if (mixSound) {
        soundLock.lock();
    }
    const float soundVolume = currentSoundVolume();
    const double soundStep = 48000.0 / rate;

    for (size_t frame = 0; frame < frames; frame++) {
        float value = silent ? 0.0f : (float)samples[frame * channels];

        if (!silent) {
            if (semitones != 0.0) {
                value = sgPitchShifter.process(value, ratio, window);
            }
            if (robot) {
                value *= (float)std::sin(sgRingPhase) * 1.4f;
                sgRingPhase += 2.0 * M_PI * 60.0 / rate;
                if (sgRingPhase > 2.0 * M_PI) {
                    sgRingPhase -= 2.0 * M_PI;
                }
            }
            if (telephone) {
                value = sgLowPass.process(sgHighPass.process(value)) * 1.3f;
            }
        }

        if (mixSound && !sgSound.empty()) {
            const size_t index = (size_t)sgSoundPosition;
            if (index < sgSound.size()) {
                value += (float)sgSound[index] * soundVolume;
                sgSoundPosition += soundStep;
            } else {
                sgSound.clear();
                sgSoundPlaying.store(false);
            }
        }

        const float clamped = std::max(-32768.0f, std::min(32767.0f, value));
        for (size_t channel = 0; channel < channels; channel++) {
            samples[frame * channels + channel] = (int16_t)clamped;
        }
    }
}
