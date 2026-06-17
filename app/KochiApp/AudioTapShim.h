#import <AVFAudio/AVFAudio.h>

NS_ASSUME_NONNULL_BEGIN

/// Thin wrapper around the block-based `installTapOnBus:bufferSize:format:block:`,
/// which Apple deprecated on macOS 27 in favor of an `…error:block:` variant whose
/// Swift overlay isn't usable yet (it's `NS_REFINED_FOR_SWIFT` and imports with a
/// broken `error:` parameter on the current SDK). The block API still works fine;
/// this shim just keeps the deprecation out of the Swift build. Migrate to the
/// refined API once its Swift overlay ships.
@interface AVAudioNode (KochiTap)
- (void)kochi_installTapOnBus:(AVAudioNodeBus)bus
                   bufferSize:(AVAudioFrameCount)bufferSize
                       format:(nullable AVAudioFormat *)format
                        block:(AVAudioNodeTapBlock)block;
@end

NS_ASSUME_NONNULL_END
