#import "AudioTapShim.h"

@implementation AVAudioNode (KochiTap)

- (void)kochi_installTapOnBus:(AVAudioNodeBus)bus
                   bufferSize:(AVAudioFrameCount)bufferSize
                       format:(nullable AVAudioFormat *)format
                        block:(AVAudioNodeTapBlock)block {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [self installTapOnBus:bus bufferSize:bufferSize format:format block:block];
#pragma clang diagnostic pop
}

@end
