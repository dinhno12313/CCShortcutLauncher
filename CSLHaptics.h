#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Plays the configured tap feedback for a Control Center module press.
///
/// Does nothing when the user has turned haptics off, so callers do not have to
/// check the preference themselves.
void CSLPlayModuleTapHaptic(void);

NS_ASSUME_NONNULL_END
