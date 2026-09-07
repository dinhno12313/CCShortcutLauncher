#import "CCShortcutLauncher.h"
#import "CCShortcutLauncherBackgroundRunner.h"
#import "CSLDiagnostics.h"
#import "CSLHaptics.h"
#import "CSLModuleIcon.h"
#import "CSLShortcutIcon.h"
#import "CSLSlotPreferences.h"

#import <CoreFoundation/CoreFoundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

static id CSLObjectIvarValue(id object, const char *name) {
    if (object == nil || name == NULL) {
        return nil;
    }
    Ivar ivar = class_getInstanceVariable([object class], name);
    if (ivar == NULL) {
        return nil;
    }
    const char *type = ivar_getTypeEncoding(ivar);
    if (type == NULL || type[0] != '@') {
        return nil;
    }
    return object_getIvar(object, ivar);
}

static void CSLCollectViewControllers(
    id object,
    NSMutableArray<UIViewController *> *controllers,
    NSMutableSet<NSValue *> *visited,
    NSUInteger depth
) {
    if (object == nil || depth > 4) {
        return;
    }
    NSValue *identity = [NSValue valueWithPointer:(__bridge const void *)object];
    if ([visited containsObject:identity]) {
        return;
    }
    [visited addObject:identity];

    if ([object isKindOfClass:[UIViewController class]]) {
        [controllers addObject:(UIViewController *)object];
        return;
    }

    NSArray *children = nil;
    if ([object isKindOfClass:[NSArray class]]) {
        children = object;
    } else if ([object isKindOfClass:[NSDictionary class]]) {
        children = [(NSDictionary *)object allValues];
    } else if ([object isKindOfClass:[NSSet class]]) {
        children = [(NSSet *)object allObjects];
    } else if ([object isKindOfClass:[NSMapTable class]]) {
        children = [[(NSMapTable *)object objectEnumerator] allObjects];
    } else if ([object isKindOfClass:[NSHashTable class]]) {
        children = [(NSHashTable *)object allObjects];
    }

    for (id child in children) {
        CSLCollectViewControllers(child, controllers, visited, depth + 1);
    }
}

@interface CCShortcutLauncher ()
- (UIViewController *)popupPresenter;
- (void)presentShortcutPopup;
@end

@implementation CCShortcutLauncher

- (instancetype)initWithSlot:(NSUInteger)slot {
    self = [super init];
    if (self != nil) {
        _slot = slot;
    }
    return self;
}

- (instancetype)init {
    return [self initWithSlot:0];
}

- (NSArray<NSDictionary<NSString *, id> *> *)slotEntries {
    return CSLEntriesForSlot(self.slot);
}

/// Matches the size of the system glyphs sitting next to the module.
static const CGFloat CSLModuleGlyphSide = 36.0;

- (UIImage *)iconGlyph {
    NSArray<NSDictionary<NSString *, id> *> *entries = [self slotEntries];
    CSLIconDiagnosticLog(
        @"[CCShortcutLauncher][Icon] MODULE_REQUEST slot=%lu entries=%lu",
        (unsigned long)self.slot,
        (unsigned long)entries.count
    );
    return CSLModuleTemplateGlyphForSlot(
        self.slot,
        entries,
        CGSizeMake(CSLModuleGlyphSide, CSLModuleGlyphSide)
    );
}

- (UIImage *)selectedIconGlyph {
    return [self iconGlyph];
}

- (UIColor *)selectedColor {
    return [UIColor systemIndigoColor];
}

// This module is a momentary menu button, not an on/off toggle.
- (BOOL)isSelected {
    return NO;
}

- (void)setSelected:(BOOL)selected {
    if (!selected) {
        return;
    }

    // Fired here rather than inside the block below so the tap is answered on
    // the press itself. What follows is either a Shortcut running in the
    // background or a popup opening, and neither is instant; the feedback is
    // the only thing that says the module registered the touch.
    //
    // It also fires for a slot holding nothing, because a tap that turns out to
    // have nothing behind it is still a tap the user made.
    CSLPlayModuleTapHaptic();

    dispatch_async(dispatch_get_main_queue(), ^{
        NSArray<NSDictionary<NSString *, id> *> *entries = [self slotEntries];
        if (entries.count == 1) {
            // Nothing to choose from, so skip the popup entirely.
            NSDictionary<NSString *, id> *entry = entries.firstObject;
            [self runShortcutNamed:entry[@"name"] workflowID:entry[@"workflowID"]];
        } else {
            [self presentShortcutPopup];
        }
        [self refreshState];
    });
}

- (void)runShortcutNamed:(NSString *)shortcutName
             workflowID:(NSString *)workflowIdentifier {
    CSLBackgroundStartResult result =
        CSLStartBackgroundShortcutNamed(shortcutName, workflowIdentifier);
    if (result != CSLBackgroundStartResultSubmitted) {
        NSLog(@"[CCShortcutLauncher][Popup] RUN_REJECTED name=\"%@\" result=%ld",
              shortcutName,
              (long)result);
    }
}

- (NSString *)displayTitleForEntry:(NSDictionary<NSString *, id> *)entry
                         nameCounts:(NSDictionary<NSString *, NSNumber *> *)nameCounts
                    nameOccurrences:(NSMutableDictionary<NSString *, NSNumber *> *)nameOccurrences {
    NSString *shortcutName = entry[@"name"];
    NSString *countKey = shortcutName.lowercaseString;
    if (nameCounts[countKey].unsignedIntegerValue < 2) {
        return shortcutName;
    }

    NSUInteger occurrence = nameOccurrences[countKey].unsignedIntegerValue + 1;
    nameOccurrences[countKey] = @(occurrence);
    return [NSString stringWithFormat:@"%@ (%lu)",
        shortcutName,
        (unsigned long)occurrence];
}

- (UIViewController *)popupPresenter {
    NSMutableArray<UIViewController *> *controllers = [NSMutableArray array];
    NSMutableSet<NSValue *> *visited = [NSMutableSet set];

    @try {
        SEL contentSelector = NSSelectorFromString(@"contentViewController");
        if ([self respondsToSelector:contentSelector]) {
            id controller = ((id (*)(id, SEL))objc_msgSend)(self, contentSelector);
            CSLCollectViewControllers(controller, controllers, visited, 0);
        }

        const char *ivarNames[] = {
            "_contentViewControllers",
            "_contentViewController",
        };
        for (NSUInteger index = 0; index < sizeof(ivarNames) / sizeof(ivarNames[0]); index++) {
            id container = CSLObjectIvarValue(self, ivarNames[index]);
            if (container == nil) {
                continue;
            }
            CSLCollectViewControllers(container, controllers, visited, 0);
        }
    } @catch (NSException *exception) {
        NSLog(@"[CCShortcutLauncher][Popup] PRESENTER_DISCOVERY_EXCEPTION exception=%@ reason=%@",
              exception.name,
              exception.reason);
        return nil;
    }

    for (UIViewController *controller in controllers) {
        if (controller.isViewLoaded && controller.view.window != nil) {
            return controller;
        }
    }
    NSLog(@"[CCShortcutLauncher][Popup] PRESENTER_NOT_FOUND candidates=%lu",
          (unsigned long)controllers.count);
    return nil;
}

- (void)presentShortcutPopup {
    @try {
        UIViewController *presenter = [self popupPresenter];
        if (presenter == nil) {
            return;
        }
        if (presenter.presentedViewController != nil) {
            return;
        }

        NSArray<NSDictionary<NSString *, id> *> *loadedCatalog = CSLShortcutCatalog();
        NSArray<NSDictionary<NSString *, id> *> *catalog = [self slotEntries];
        NSString *message = nil;
        if (catalog.count > 0) {
            message = CSLLocalizedText(
                @"Chọn một phím tắt để chạy.",
                @"Choose a Shortcut to run."
            );
        } else if (loadedCatalog.count > 0) {
            message = CSLLocalizedText(
                @"Để thêm phím tắt, mở Cài đặt → Trung tâm điều khiển và chạm mô-đun này.",
                @"To add a Shortcut, open Settings → Control Center and tap this module."
            );
        } else {
            message = CSLLocalizedText(
                @"Để bắt đầu, mở Cài đặt → CCShortcutLauncher và chạm Tải phím tắt của tôi.",
                @"To get started, open Settings → CCShortcutLauncher and tap Load My Shortcuts."
            );
        }
        UIAlertController *popup = [UIAlertController
            alertControllerWithTitle:CSLDisplayNameForSlot(self.slot)
                             message:message
                      preferredStyle:UIAlertControllerStyleActionSheet];

        NSMutableDictionary<NSString *, NSNumber *> *nameCounts =
            [NSMutableDictionary dictionary];
        for (NSDictionary<NSString *, id> *entry in catalog) {
            NSString *countKey = [entry[@"name"] lowercaseString];
            nameCounts[countKey] = @(nameCounts[countKey].unsignedIntegerValue + 1);
        }

        __weak typeof(self) weakSelf = self;
        NSMutableDictionary<NSString *, NSNumber *> *nameOccurrences =
            [NSMutableDictionary dictionary];
        for (NSDictionary<NSString *, id> *entry in catalog) {
            NSString *title = [self displayTitleForEntry:entry
                                               nameCounts:nameCounts
                                          nameOccurrences:nameOccurrences];
            NSString *shortcutName = entry[@"name"];
            NSString *workflowIdentifier = entry[@"workflowID"];
            UIAlertAction *shortcutAction =
                [UIAlertAction actionWithTitle:title
                                         style:UIAlertActionStyleDefault
                                       handler:^(__unused UIAlertAction *action) {
                [weakSelf runShortcutNamed:shortcutName workflowID:workflowIdentifier];
            }];
            UIImage *shortcutIcon =
                CSLShortcutIconImageForEntry(entry, CGSizeMake(28.0, 28.0));
            CSLSetImageForAlertActionIfSupported(shortcutAction, shortcutIcon);
            [popup addAction:shortcutAction];
        }

        [popup addAction:[UIAlertAction actionWithTitle:CSLLocalizedText(@"Hủy", @"Cancel")
                                                 style:UIAlertActionStyleCancel
                                               handler:nil]];

        UIPopoverPresentationController *popover = popup.popoverPresentationController;
        if (popover != nil) {
            popover.sourceView = presenter.view;
            popover.sourceRect = CGRectMake(
                CGRectGetMidX(presenter.view.bounds),
                CGRectGetMidY(presenter.view.bounds),
                1.0,
                1.0
            );
            popover.permittedArrowDirections = 0;
        }

        [presenter presentViewController:popup animated:YES completion:nil];
    } @catch (NSException *exception) {
        NSLog(@"[CCShortcutLauncher][Popup] PRESENTATION_EXCEPTION exception=%@ reason=%@",
              exception.name,
              exception.reason);
    }
}

@end
