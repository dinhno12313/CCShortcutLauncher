#import "CSLHaptics.h"
#import "CSLSlotPreferences.h"

#import <AudioToolbox/AudioToolbox.h>

// AudioServices rather than UIFeedbackGenerator. A feedback generator wants to
// be created, prepared, and kept alive across the gesture to fire on time; the
// Actuate patterns take none of that and there is nothing to hold on to between
// taps. FlashlightSettings takes the same route for the same reason.
static SystemSoundID const CSLHapticActuatePeek = 1519;
static SystemSoundID const CSLHapticActuatePop = 1520;
static SystemSoundID const CSLHapticActuateNope = 1521;

void CSLPlayModuleTapHaptic(void) {
    if (!CSLHapticFeedbackEnabled()) {
        return;
    }

    NSString *style = CSLHapticStyle();
    SystemSoundID sound = CSLHapticActuatePop;
    if ([style isEqualToString:CSLHapticStyleLight]) {
        sound = CSLHapticActuatePeek;
    } else if ([style isEqualToString:CSLHapticStyleHeavy]) {
        sound = CSLHapticActuateNope;
    }

    AudioServicesPlaySystemSound(sound);
}
