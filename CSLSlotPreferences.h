#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// One Control Center module is one slot. Every slot owns its own ordered list
/// of Shortcuts, so a user can keep work Shortcuts in one module and home
/// Shortcuts in another.
FOUNDATION_EXPORT NSUInteger const CSLMinimumModuleSlotCount;
FOUNDATION_EXPORT NSUInteger const CSLMaximumModuleSlotCount;
FOUNDATION_EXPORT NSUInteger const CSLDefaultModuleSlotCount;

/// Language selected inside the tweak. Vietnamese is used until the user
/// explicitly selects English.
NSString *CSLInterfaceLanguageCode(void);
BOOL CSLUsesVietnamese(void);
NSString *CSLLocalizedText(NSString *vietnamese, NSString *english);

/// Number of modules the provider vends, clamped to the range above.
NSUInteger CSLModuleSlotCount(void);
void CSLSetModuleSlotCount(NSUInteger count);

/// Tap feedback for a module press. Global, not per slot: it describes how the
/// tweak feels, not what a particular module does.
FOUNDATION_EXPORT NSString *const CSLHapticStyleLight;
FOUNDATION_EXPORT NSString *const CSLHapticStyleMedium;
FOUNDATION_EXPORT NSString *const CSLHapticStyleHeavy;

/// Whether a module press vibrates. On by default.
///
/// Read only: both values are written by the Settings page straight into the
/// domain through its `defaults` key. A setter here would be a second way to
/// write the same key, and the two would drift.
BOOL CSLHapticFeedbackEnabled(void);

/// Strength of that vibration. Always one of the three constants above; an
/// unknown stored value reads as medium rather than as silence.
NSString *CSLHapticStyle(void);

/// Control Center module identifier for a slot. Slot 0 keeps the pre-1.4
/// identifier so an existing Control Center layout survives the update.
NSString *CSLModuleIdentifierForSlot(NSUInteger slot);

/// Slot index for a module identifier, or NSNotFound when the identifier does
/// not belong to this tweak.
NSUInteger CSLSlotForModuleIdentifier(NSString *_Nullable identifier);

/// User supplied module name, or nil when the slot uses its default name.
NSString *_Nullable CSLSlotName(NSUInteger slot);
void CSLSetSlotName(NSString *_Nullable name, NSUInteger slot);

/// Optional icon-pack identifier for a multi-Shortcut slot. Empty slots and
/// single-Shortcut slots deliberately ignore this value without deleting it.
NSString *_Nullable CSLSlotIconName(NSUInteger slot);
void CSLSetSlotIconName(NSString *_Nullable iconName, NSUInteger slot);

/// Name shown in Settings and in the Control Center popup.
NSString *CSLDisplayNameForSlot(NSUInteger slot);

/// Validated catalog written by the resolver daemon, sorted by name.
NSArray<NSDictionary<NSString *, id> *> *CSLShortcutCatalog(void);

/// Workflow identifiers assigned to a slot, in user order. Empty by default:
/// loading the catalog never assigns Shortcuts to a module on its own.
NSArray<NSString *> *CSLShortcutIDsForSlot(NSUInteger slot);
void CSLSetShortcutIDs(NSArray<NSString *> *identifiers, NSUInteger slot);

/// Catalog entries assigned to a slot, in user order, skipping identifiers that
/// are no longer in the catalog.
NSArray<NSDictionary<NSString *, id> *> *CSLEntriesForSlot(NSUInteger slot);

/// Moves a pre-1.4 single-module selection into slot 0. Safe to call more than
/// once; call it from Settings only, never from SpringBoard.
void CSLMigrateLegacySelectionIfNeeded(void);

/// Clears the keys an earlier version wrote for its diagnostics page, so
/// removing that page does not leave values behind in the preferences file.
void CSLRemoveDiagnosticPreferences(void);

/// SpringBoard caches the provided module list once per process, so a module
/// added in Settings stays unusable until a respring. This asks CCSupport to
/// re-read providers and refresh module metadata instead.
void CSLRequestControlCenterModuleReload(void);

NS_ASSUME_NONNULL_END
