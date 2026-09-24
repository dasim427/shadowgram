#import <Foundation/Foundation.h>
#import <stdint.h>

NS_ASSUME_NONNULL_BEGIN

// Shadowgram: effects applied to the microphone signal of calls, right where the
// device's recorded audio is handed to the call. Voice presets change the voice in
// real time, the soundpad mixes sounds in so the other side hears them, and the silent
// microphone sends silence without the "microphone off" mark.

typedef NS_ENUM(NSInteger, SGCallVoicePreset) {
    SGCallVoicePresetOff = 0,
    SGCallVoicePresetMale = 1,
    SGCallVoicePresetFemale = 2,
    SGCallVoicePresetChild = 3,
    SGCallVoicePresetDeep = 4,
    SGCallVoicePresetAnonymous = 5,
    SGCallVoicePresetRobot = 6,
    SGCallVoicePresetTelephone = 7
};

@interface SGCallAudioEffects : NSObject

/// Stored in the standard user defaults, so it survives restarts.
+ (SGCallVoicePreset)voicePreset;
+ (void)setVoicePreset:(SGCallVoicePreset)preset;

/// Sends silence instead of the microphone. Stored like the voice preset.
+ (BOOL)silentMicrophone;
+ (void)setSilentMicrophone:(BOOL)value;

/// 0...1, how loud soundpad sounds are mixed in.
+ (float)soundVolume;
+ (void)setSoundVolume:(float)value;

/// Mixes a sound into the call: 16-bit signed mono PCM at 48 kHz. Replaces a sound that
/// is still playing.
+ (void)playPCM16Mono48k:(NSData *)data;
+ (void)stopSound;
+ (BOOL)isPlayingSound;

@end

#ifdef __cplusplus
extern "C" {
#endif

/// Whether the call audio needs to go through SGCallAudioEffectsProcess at all.
bool SGCallAudioEffectsIsActive(void);

/// Processes interleaved 16-bit samples in place.
void SGCallAudioEffectsProcess(int16_t *samples, size_t frames, size_t channels, uint32_t sampleRate);

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
