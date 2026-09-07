#import "CSLSlotPreferences.h"
#import "CSLModuleIcon.h"

#import <CoreFoundation/CoreFoundation.h>

NSUInteger const CSLMinimumModuleSlotCount = 1;
NSUInteger const CSLMaximumModuleSlotCount = 8;
NSUInteger const CSLDefaultModuleSlotCount = 2;

static CFStringRef const CSLPreferencesDomain =
    CFSTR("com.dinhnguyenx.ccshortcutlauncher");
static NSString *const CSLBaseModuleIdentifier =
    @"com.dinhnguyenx.ccshortcutlauncher";
static NSString *const CSLSlotIdentifierSuffix = @".slot";

static CFStringRef const CSLModuleSlotCountKey = CFSTR("ModuleSlotCount");
static CFStringRef const CSLInterfaceLanguageKey = CFSTR("InterfaceLanguage");
static CFStringRef const CSLSlotShortcutIDsKey = CFSTR("SlotShortcutIDs");
static CFStringRef const CSLSlotNamesKey = CFSTR("SlotNames");
static CFStringRef const CSLSlotIconNamesKey = CFSTR("SlotIconNames");
static CFStringRef const CSLLegacyShortcutIDsKey = CFSTR("PopupShortcutIDs");
static CFStringRef const CSLShortcutsCatalogKey = CFSTR("ShortcutsCatalog");
static CFStringRef const CSLModuleGlyphPathsKey = CFSTR("ModuleGlyphPaths");
static CFStringRef const CSLHapticFeedbackKey = CFSTR("HapticFeedback");
static CFStringRef const CSLHapticStyleKey = CFSTR("HapticStyle");

/// Handled by CCSupport in SpringBoard: reloads providers and refreshes the
/// metadata of every module.
static CFStringRef const CSLControlCenterReloadProvidersNotification =
    CFSTR("com.opa334.ccsupport/ReloadProviders");

static id CSLPreferenceValue(CFStringRef key) {
    CFPreferencesAppSynchronize(CSLPreferencesDomain);
    CFPropertyListRef value = CFPreferencesCopyAppValue(key, CSLPreferencesDomain);
    return value != NULL ? CFBridgingRelease(value) : nil;
}

NSString *CSLInterfaceLanguageCode(void) {
    id value = CSLPreferenceValue(CSLInterfaceLanguageKey);
    return [value isKindOfClass:[NSString class]] &&
        [(NSString *)value isEqualToString:@"en"]
        ? @"en"
        : @"vi";
}

BOOL CSLUsesVietnamese(void) {
    return [CSLInterfaceLanguageCode() isEqualToString:@"vi"];
}

NSString *CSLLocalizedText(NSString *vietnamese, NSString *english) {
    return CSLUsesVietnamese() ? vietnamese : english;
}

static void CSLSetPreferenceValue(CFStringRef key, id _Nullable value) {
    CFPreferencesSetAppValue(key, (__bridge CFPropertyListRef)value, CSLPreferencesDomain);
    if (!CFPreferencesAppSynchronize(CSLPreferencesDomain)) {
        NSLog(@"[CCShortcutLauncher][Prefs] WRITE_FAILED key=%@", (__bridge NSString *)key);
    }
}

static NSString *CSLSlotStorageKey(NSUInteger slot) {
    return [NSString stringWithFormat:@"%lu", (unsigned long)slot];
}

static NSDictionary *CSLDictionaryPreference(CFStringRef key) {
    id value = CSLPreferenceValue(key);
    return [value isKindOfClass:[NSDictionary class]] ? (NSDictionary *)value : nil;
}

/// Keeps only well formed UUID strings and drops duplicates.
static NSArray<NSString *> *CSLNormalizedIdentifiers(id _Nullable value) {
    if (![value isKindOfClass:[NSArray class]]) {
        return @[];
    }

    NSMutableArray<NSString *> *identifiers = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (id item in (NSArray *)value) {
        if (![item isKindOfClass:[NSString class]]) {
            continue;
        }
        NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:(NSString *)item];
        NSString *identifier = uuid.UUIDString;
        if (identifier == nil || [seen containsObject:identifier]) {
            continue;
        }
        [seen addObject:identifier];
        [identifiers addObject:identifier];
    }
    return identifiers;
}

NSString *const CSLHapticStyleLight = @"light";
NSString *const CSLHapticStyleMedium = @"medium";
NSString *const CSLHapticStyleHeavy = @"heavy";

BOOL CSLHapticFeedbackEnabled(void) {
    id value = CSLPreferenceValue(CSLHapticFeedbackKey);
    // On by default: a tap that does nothing visible until the Shortcut runs is
    // exactly the case that wants confirmation, and one switch turns it off.
    return [value isKindOfClass:[NSNumber class]] ? [(NSNumber *)value boolValue] : YES;
}

NSString *CSLHapticStyle(void) {
    id value = CSLPreferenceValue(CSLHapticStyleKey);
    if (![value isKindOfClass:[NSString class]]) {
        return CSLHapticStyleMedium;
    }

    NSString *style = (NSString *)value;
    if ([style isEqualToString:CSLHapticStyleLight] ||
        [style isEqualToString:CSLHapticStyleHeavy]) {
        return style;
    }
    // Anything else, including a value left behind by a future version, reads as
    // the default rather than as no feedback at all.
    return CSLHapticStyleMedium;
}

NSUInteger CSLModuleSlotCount(void) {
    id value = CSLPreferenceValue(CSLModuleSlotCountKey);
    if (![value isKindOfClass:[NSNumber class]]) {
        return CSLDefaultModuleSlotCount;
    }

    NSInteger count = [(NSNumber *)value integerValue];
    if (count < (NSInteger)CSLMinimumModuleSlotCount) {
        return CSLMinimumModuleSlotCount;
    }
    if (count > (NSInteger)CSLMaximumModuleSlotCount) {
        return CSLMaximumModuleSlotCount;
    }
    return (NSUInteger)count;
}

void CSLSetModuleSlotCount(NSUInteger count) {
    NSUInteger clamped = MIN(MAX(count, CSLMinimumModuleSlotCount), CSLMaximumModuleSlotCount);
    if (clamped == CSLModuleSlotCount()) {
        return;
    }
    CSLSetPreferenceValue(CSLModuleSlotCountKey, @(clamped));
    CSLRequestControlCenterModuleReload();
}

NSString *CSLModuleIdentifierForSlot(NSUInteger slot) {
    if (slot == 0) {
        return CSLBaseModuleIdentifier;
    }
    return [NSString stringWithFormat:@"%@%@%lu",
        CSLBaseModuleIdentifier,
        CSLSlotIdentifierSuffix,
        (unsigned long)slot];
}

NSUInteger CSLSlotForModuleIdentifier(NSString *identifier) {
    if (identifier.length == 0) {
        return NSNotFound;
    }
    if ([identifier isEqualToString:CSLBaseModuleIdentifier]) {
        return 0;
    }

    NSString *prefix = [CSLBaseModuleIdentifier stringByAppendingString:CSLSlotIdentifierSuffix];
    if (![identifier hasPrefix:prefix]) {
        return NSNotFound;
    }

    NSString *suffix = [identifier substringFromIndex:prefix.length];
    if (suffix.length == 0) {
        return NSNotFound;
    }
    NSScanner *scanner = [NSScanner scannerWithString:suffix];
    long long slot = 0;
    if (![scanner scanLongLong:&slot] || !scanner.isAtEnd || slot <= 0 ||
        slot >= (long long)CSLMaximumModuleSlotCount) {
        return NSNotFound;
    }
    return (NSUInteger)slot;
}

NSString *CSLSlotName(NSUInteger slot) {
    id value = CSLDictionaryPreference(CSLSlotNamesKey)[CSLSlotStorageKey(slot)];
    if (![value isKindOfClass:[NSString class]]) {
        return nil;
    }
    NSString *name = [(NSString *)value stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return name.length > 0 ? name : nil;
}

void CSLSetSlotName(NSString *name, NSUInteger slot) {
    NSString *trimmed = [name stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSDictionary *stored = CSLDictionaryPreference(CSLSlotNamesKey) ?: @{};
    NSString *storageKey = CSLSlotStorageKey(slot);
    id existingValue = stored[storageKey];
    NSString *existing = [existingValue isKindOfClass:[NSString class]]
        ? [(NSString *)existingValue stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]]
        : nil;
    if ((trimmed.length == 0 && existing.length == 0) ||
        [trimmed isEqualToString:existing]) {
        return;
    }

    NSMutableDictionary *updated = [stored mutableCopy];
    if (trimmed.length > 0) {
        updated[storageKey] = trimmed;
    } else {
        [updated removeObjectForKey:storageKey];
    }
    CSLSetPreferenceValue(CSLSlotNamesKey, [updated copy]);
    CSLRequestControlCenterModuleReload();
}

NSString *CSLSlotIconName(NSUInteger slot) {
    id value = CSLDictionaryPreference(CSLSlotIconNamesKey)[CSLSlotStorageKey(slot)];
    if (![value isKindOfClass:[NSString class]] ||
        !CSLModuleIconIdentifierIsValid((NSString *)value)) {
        return nil;
    }
    return value;
}

void CSLSetSlotIconName(NSString *iconName, NSUInteger slot) {
    NSString *normalized = CSLModuleIconIdentifierIsValid(iconName) ? iconName : nil;
    NSDictionary *stored = CSLDictionaryPreference(CSLSlotIconNamesKey) ?: @{};
    NSString *storageKey = CSLSlotStorageKey(slot);
    id existingValue = stored[storageKey];
    NSString *existing = [existingValue isKindOfClass:[NSString class]] &&
        CSLModuleIconIdentifierIsValid((NSString *)existingValue)
        ? existingValue
        : nil;
    if ((normalized == nil && existing == nil) || [normalized isEqualToString:existing]) {
        return;
    }

    NSMutableDictionary *updated = [stored mutableCopy];
    if (normalized != nil) {
        updated[storageKey] = normalized;
    } else {
        [updated removeObjectForKey:storageKey];
    }
    CSLSetPreferenceValue(CSLSlotIconNamesKey, [updated copy]);
    CSLRequestControlCenterModuleReload();
}

NSString *CSLDisplayNameForSlot(NSUInteger slot) {
    NSString *name = CSLSlotName(slot);
    if (name != nil) {
        return name;
    }
    if (slot == 0 && CSLModuleSlotCount() == 1) {
        return @"CCShortcutLauncher";
    }
    return [NSString stringWithFormat:@"CCShortcutLauncher %lu", (unsigned long)(slot + 1)];
}

NSArray<NSDictionary<NSString *, id> *> *CSLShortcutCatalog(void) {
    id value = CSLPreferenceValue(CSLShortcutsCatalogKey);
    if (![value isKindOfClass:[NSArray class]]) {
        return @[];
    }

    NSMutableArray<NSDictionary<NSString *, id> *> *catalog = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (id item in (NSArray *)value) {
        if (![item isKindOfClass:[NSDictionary class]]) {
            continue;
        }

        id nameValue = ((NSDictionary *)item)[@"name"];
        id identifierValue = ((NSDictionary *)item)[@"workflowID"];
        if (![nameValue isKindOfClass:[NSString class]] ||
            ![identifierValue isKindOfClass:[NSString class]]) {
            continue;
        }

        NSString *name = [(NSString *)nameValue stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:(NSString *)identifierValue];
        if (name.length == 0 || uuid == nil || [seen containsObject:uuid.UUIDString]) {
            continue;
        }
        [seen addObject:uuid.UUIDString];

        NSMutableDictionary<NSString *, id> *entry = [@{
            @"name": name,
            @"workflowID": uuid.UUIDString,
        } mutableCopy];
        id glyphValue = ((NSDictionary *)item)[@"iconGlyph"];
        id colorValue = ((NSDictionary *)item)[@"iconColor"];
        if ([glyphValue isKindOfClass:[NSNumber class]]) {
            entry[@"iconGlyph"] = glyphValue;
        }
        if ([colorValue isKindOfClass:[NSNumber class]]) {
            entry[@"iconColor"] = colorValue;
        }
        id appValue = ((NSDictionary *)item)[@"appBundleID"];
        if ([appValue isKindOfClass:[NSString class]] &&
            [(NSString *)appValue length] > 0) {
            entry[@"appBundleID"] = appValue;
        }
        [catalog addObject:entry];
    }

    [catalog sortUsingComparator:^NSComparisonResult(
        NSDictionary<NSString *, id> *left,
        NSDictionary<NSString *, id> *right
    ) {
        NSComparisonResult nameResult =
            [left[@"name"] localizedCaseInsensitiveCompare:right[@"name"]];
        return nameResult != NSOrderedSame
            ? nameResult
            : [left[@"workflowID"] compare:right[@"workflowID"]];
    }];
    return catalog;
}

NSArray<NSString *> *CSLShortcutIDsForSlot(NSUInteger slot) {
    NSDictionary *slots = CSLDictionaryPreference(CSLSlotShortcutIDsKey);
    if (slots != nil) {
        return CSLNormalizedIdentifiers(slots[CSLSlotStorageKey(slot)]);
    }

    // Pre-1.4 preferences kept a single list. Settings migrates it on next
    // launch; until then slot 0 reads it directly so Control Center keeps
    // working without a write from SpringBoard.
    if (slot == 0) {
        return CSLNormalizedIdentifiers(CSLPreferenceValue(CSLLegacyShortcutIDsKey));
    }
    return @[];
}

void CSLSetShortcutIDs(NSArray<NSString *> *identifiers, NSUInteger slot) {
    NSDictionary *stored = CSLDictionaryPreference(CSLSlotShortcutIDsKey) ?: @{};
    NSArray<NSString *> *normalized = CSLNormalizedIdentifiers(identifiers);
    NSArray<NSString *> *existing =
        CSLNormalizedIdentifiers(stored[CSLSlotStorageKey(slot)]);
    if ([normalized isEqualToArray:existing]) {
        return;
    }

    NSMutableDictionary *updated = [stored mutableCopy];
    updated[CSLSlotStorageKey(slot)] = normalized;
    CSLSetPreferenceValue(CSLSlotShortcutIDsKey, [updated copy]);
}

NSArray<NSDictionary<NSString *, id> *> *CSLEntriesForSlot(NSUInteger slot) {
    NSArray<NSDictionary<NSString *, id> *> *catalog = CSLShortcutCatalog();
    NSMutableDictionary<NSString *, NSDictionary<NSString *, id> *> *byIdentifier =
        [NSMutableDictionary dictionary];
    for (NSDictionary<NSString *, id> *entry in catalog) {
        byIdentifier[entry[@"workflowID"]] = entry;
    }

    NSMutableArray<NSDictionary<NSString *, id> *> *entries = [NSMutableArray array];
    for (NSString *identifier in CSLShortcutIDsForSlot(slot)) {
        NSDictionary<NSString *, id> *entry = byIdentifier[identifier];
        if (entry != nil) {
            [entries addObject:entry];
        }
    }
    return entries;
}

void CSLMigrateLegacySelectionIfNeeded(void) {
    if (CSLDictionaryPreference(CSLSlotShortcutIDsKey) != nil) {
        return;
    }

    NSArray<NSString *> *legacy =
        CSLNormalizedIdentifiers(CSLPreferenceValue(CSLLegacyShortcutIDsKey));
    NSDictionary *migrated = legacy.count > 0 ? @{@"0": legacy} : @{};
    CSLSetPreferenceValue(CSLSlotShortcutIDsKey, migrated);
    CSLSetPreferenceValue(CSLLegacyShortcutIDsKey, nil);
    NSLog(@"[CCShortcutLauncher][Prefs] LEGACY_SELECTION_MIGRATED count=%lu",
          (unsigned long)legacy.count);
}

void CSLRemoveDiagnosticPreferences(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        CFStringRef obsoleteKeys[] = {
            CFSTR("ResolverAppColumn"),
            CFSTR("ResolverAppIconCount"),
            CFSTR("ResolverGlyphIconCount"),
            CFSTR("ResolverLastLoadDate"),
            CSLModuleGlyphPathsKey,
        };

        CFPreferencesAppSynchronize(CSLPreferencesDomain);
        BOOL removedValue = NO;
        for (size_t i = 0; i < sizeof(obsoleteKeys) / sizeof(obsoleteKeys[0]); i++) {
            CFPropertyListRef value =
                CFPreferencesCopyAppValue(obsoleteKeys[i], CSLPreferencesDomain);
            if (value == NULL) {
                continue;
            }
            CFRelease(value);
            CFPreferencesSetAppValue(obsoleteKeys[i], NULL, CSLPreferencesDomain);
            removedValue = YES;
        }
        if (removedValue) {
            CFPreferencesAppSynchronize(CSLPreferencesDomain);
        }
    });
}

void CSLRequestControlCenterModuleReload(void) {
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CSLControlCenterReloadProvidersNotification,
        NULL,
        NULL,
        true
    );
}
