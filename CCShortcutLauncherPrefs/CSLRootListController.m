#import "CSLRootListController.h"
#import "CSLShortcutOrderController.h"
#import "../CSLModuleIcon.h"
#import "../CSLSlotPreferences.h"

#import <CoreFoundation/CoreFoundation.h>
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>

static CFStringRef const CSLPreferencesDomain =
    CFSTR("com.dinhnguyenx.ccshortcutlauncher");
static CFStringRef const CSLCatalogRequestedNotification =
    CFSTR("com.dinhnguyenx.ccshortcutlauncher/catalogRequested");
static NSString *const CSLRepositoryURLString = @"https://dinhno12313.github.io";
static NSString *const CSLRepositorySpecifierIdentifier = @"RepositoryLink";
static NSString *const CSLModuleCountSpecifierIdentifier = @"ModuleCount";
static NSString *const CSLSettingsVersionText =
    @"CCShortcutLauncher 1.6.0";

/// The polling path synchronizes the domain once, then reads all related keys
/// from the same snapshot instead of forcing a disk synchronization per key.
static id CSLPreferenceValueWithoutSynchronizing(CFStringRef key) {
    CFPropertyListRef value =
        CFPreferencesCopyAppValue(key, CSLPreferencesDomain);
    return value != NULL ? CFBridgingRelease(value) : nil;
}

static NSString *CSLPreferenceStringWithoutSynchronizing(CFStringRef key) {
    id value = CSLPreferenceValueWithoutSynchronizing(key);
    if (![value isKindOfClass:[NSString class]]) {
        return nil;
    }
    return [(NSString *)value stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

/// Declared here because the Preferences headers do not always ship it.
@interface PSListController (CSLSpecifierLookup)
- (PSSpecifier *)specifierAtIndexPath:(NSIndexPath *)indexPath;
@end

@interface CSLRootListController ()
@property (nonatomic, copy) NSDictionary<NSNumber *, NSArray<NSDictionary<NSString *, id> *> *> *slotEntriesSnapshot;
@end

static NSString *const CSLSlotSpecifierKey = @"CSLSlot";
/// Preferences reads this property to draw the icon on the left of a row.
static NSString *const CSLSpecifierIconKey = @"iconImage";
static const CGFloat CSLSpecifierIconSide = 29.0;

/// Loads the user's repository logo without applying Preferences tinting.
static UIImage *CSLRepositoryIcon(void) {
    NSBundle *bundle = [NSBundle bundleForClass:CSLRootListController.class];
    UIImage *source = [UIImage imageNamed:@"dinhnguyenxRepoLogo"
                                 inBundle:bundle
            compatibleWithTraitCollection:nil];
    if (source == nil) {
        return nil;
    }

    CGSize size = source.size;
    UIGraphicsBeginImageContextWithOptions(size, NO, source.scale);
    CGRect bounds = CGRectMake(0.0, 0.0, size.width, size.height);
    CGFloat cornerRadius = MIN(size.width, size.height) * 0.22;
    [[UIBezierPath bezierPathWithRoundedRect:bounds cornerRadius:cornerRadius] addClip];
    [source drawInRect:bounds];
    UIImage *rounded = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return [rounded imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
}

@implementation CSLRootListController

- (NSDictionary<NSNumber *, NSArray<NSDictionary<NSString *, id> *> *> *)
    buildSlotEntriesSnapshotWithCount:(NSUInteger)slotCount {
    NSArray<NSDictionary<NSString *, id> *> *catalog = CSLShortcutCatalog();
    NSMutableDictionary<NSString *, NSDictionary<NSString *, id> *> *byIdentifier =
        [NSMutableDictionary dictionaryWithCapacity:catalog.count];
    for (NSDictionary<NSString *, id> *entry in catalog) {
        byIdentifier[entry[@"workflowID"]] = entry;
    }

    NSMutableDictionary<NSNumber *, NSArray<NSDictionary<NSString *, id> *> *> *snapshot =
        [NSMutableDictionary dictionaryWithCapacity:slotCount];
    for (NSUInteger slot = 0; slot < slotCount; slot++) {
        NSMutableArray<NSDictionary<NSString *, id> *> *entries =
            [NSMutableArray array];
        for (NSString *identifier in CSLShortcutIDsForSlot(slot)) {
            NSDictionary<NSString *, id> *entry = byIdentifier[identifier];
            if (entry != nil) {
                [entries addObject:entry];
            }
        }
        snapshot[@(slot)] = [entries copy];
    }
    return [snapshot copy];
}

- (void)localizeBaseSpecifiers:(NSArray<PSSpecifier *> *)specifiers {
    for (PSSpecifier *specifier in specifiers) {
        NSString *identifier = specifier.identifier ?: [specifier propertyForKey:@"id"];
        if ([identifier isEqualToString:@"LanguageGroup"]) {
            specifier.name = CSLLocalizedText(@"NGÔN NGỮ", @"LANGUAGE");
            [specifier setProperty:CSLLocalizedText(
                @"Chọn ngôn ngữ dùng trong phần cài đặt và menu phím tắt.",
                @"Choose the language used in Settings and the Shortcut menu."
            ) forKey:@"footerText"];
        } else if ([identifier isEqualToString:@"Language"]) {
            specifier.name = CSLLocalizedText(@"Ngôn ngữ", @"Language");
        } else if ([identifier isEqualToString:@"MyShortcutsGroup"]) {
            specifier.name = CSLLocalizedText(@"PHÍM TẮT CỦA TÔI", @"MY SHORTCUTS");
            [specifier setProperty:CSLLocalizedText(
                @"Danh sách phím tắt được tự động cập nhật. Nếu thiếu một phím tắt, hãy chạm Tải phím tắt của tôi để làm mới, sau đó mở một mô-đun bên dưới để thêm hoặc sắp xếp.",
                @"Your Shortcut list updates automatically. If a Shortcut is missing, tap Load My Shortcuts to refresh the list, then choose a module below to add or arrange Shortcuts."
            ) forKey:@"footerText"];
        } else if ([identifier isEqualToString:@"LoadMyShortcuts"]) {
            specifier.name = CSLLocalizedText(@"Tải phím tắt của tôi", @"Load My Shortcuts");
        } else if ([identifier isEqualToString:@"ModulesGroup"]) {
            specifier.name = CSLLocalizedText(
                @"MÔ-ĐUN TRUNG TÂM ĐIỀU KHIỂN",
                @"CONTROL CENTER MODULES"
            );
            [specifier setProperty:CSLLocalizedText(
                @"Dùng − và + để chọn số mô-đun. Mở một mô-đun bên dưới để thêm phím tắt, đổi thứ tự hoặc đổi tên. Sau đó thêm mô-đun trong Cài đặt → Trung tâm điều khiển.",
                @"Use − and + to choose how many controls you want. Open a module below to add Shortcuts, change their order, or rename it. Then add the module in Settings → Control Center."
            ) forKey:@"footerText"];
        } else if ([identifier isEqualToString:CSLModuleCountSpecifierIdentifier]) {
            specifier.name = CSLLocalizedText(@"Số mô-đun", @"Number of Modules");
        } else if ([identifier isEqualToString:@"HapticsGroup"]) {
            specifier.name = CSLLocalizedText(@"RUNG PHẢN HỒI", @"HAPTICS");
            [specifier setProperty:CSLLocalizedText(
                @"Rung ngay khi chạm mô-đun. Phím tắt chạy nền và không để lại dấu hiệu nào trên màn hình, nên rung thường là phản hồi duy nhất cho cú chạm.",
                @"Vibrate the moment a module is tapped. A Shortcut runs in the background and leaves nothing on screen, so this is often the only answer the tap gets."
            ) forKey:@"footerText"];
        } else if ([identifier isEqualToString:@"HapticFeedback"]) {
            specifier.name = CSLLocalizedText(@"Rung khi chạm", @"Vibrate on Tap");
        } else if ([identifier isEqualToString:@"HapticStyle"]) {
            specifier.name = CSLLocalizedText(@"Độ mạnh", @"Strength");
            // The stored values stay English; only what the row shows changes.
            [specifier setProperty:@[
                CSLLocalizedText(@"Nhẹ", @"Light"),
                CSLLocalizedText(@"Vừa", @"Medium"),
                CSLLocalizedText(@"Mạnh", @"Heavy"),
            ] forKey:@"validTitles"];
        }
    }
}

- (NSArray *)specifiers {
    if (_specifiers == nil) {
        CSLMigrateLegacySelectionIfNeeded();
        CSLRemoveDiagnosticPreferences();

        NSMutableArray *specifiers =
            [[self loadSpecifiersFromPlistName:@"Root" target:self] mutableCopy];
        [self localizeBaseSpecifiers:specifiers];

        // Slot rows belong to the CONTROL CENTER MODULES group, so they go right
        // after the row that decides how many of them there are — not at the end
        // of the list. Appending worked only while that row happened to be last
        // in the plist; a group added below it swallows them instead.
        //
        // Matched on the row's id rather than its key: the count row is a custom
        // cell and carries no preference key at all.
        NSUInteger insertionIndex = specifiers.count;
        for (NSUInteger index = 0; index < specifiers.count; index++) {
            PSSpecifier *candidate = specifiers[index];
            NSString *identifier =
                candidate.identifier ?: [candidate propertyForKey:@"id"];
            if ([identifier isEqualToString:CSLModuleCountSpecifierIdentifier]) {
                insertionIndex = index + 1;
                break;
            }
        }

        NSUInteger slotCount = CSLModuleSlotCount();
        self.slotEntriesSnapshot =
            [self buildSlotEntriesSnapshotWithCount:slotCount];
        for (NSUInteger slot = 0; slot < slotCount; slot++) {
            PSSpecifier *specifier =
                [PSSpecifier preferenceSpecifierNamed:CSLDisplayNameForSlot(slot)
                                               target:self
                                                  set:NULL
                                                  get:@selector(shortcutSummaryForSpecifier:)
                                               detail:Nil
                                                 cell:PSLinkCell
                                                 edit:Nil];
            specifier->action = @selector(openModuleSlot:);
            [specifier setProperty:@(slot) forKey:CSLSlotSpecifierKey];
            [specifier setProperty:[self iconForSlot:slot] forKey:CSLSpecifierIconKey];
            [specifiers insertObject:specifier atIndex:insertionIndex + slot];
        }

        PSSpecifier *respringGroup = [PSSpecifier emptyGroupSpecifier];
        [respringGroup setProperty:CSLLocalizedText(
            @"Hầu hết thay đổi được áp dụng tự động. Nếu mô-đun bị thiếu hoặc vẫn hiển thị thông tin cũ, hãy chạm Khởi động lại giao diện rồi kiểm tra lại Trung tâm điều khiển.",
            @"Most changes appear automatically. If a module is missing or still shows old information, tap Respring and check Control Center again."
        )
                            forKey:@"footerText"];
        [specifiers addObject:respringGroup];

        PSSpecifier *respring = [PSSpecifier
            preferenceSpecifierNamed:CSLLocalizedText(
                @"Khởi động lại giao diện",
                @"Respring"
            )
            target:self
            set:NULL
            get:NULL
            detail:Nil
            cell:PSButtonCell
            edit:Nil];
        respring->action = @selector(confirmRespring);
        [specifiers addObject:respring];

        PSSpecifier *repositoryGroup = [PSSpecifier emptyGroupSpecifier];
        [specifiers addObject:repositoryGroup];

        PSSpecifier *repository =
            [PSSpecifier preferenceSpecifierNamed:@"dinhnguyenx Repo"
                                           target:self
                                              set:NULL
                                              get:NULL
                                           detail:Nil
                                             cell:PSButtonCell
                                             edit:Nil];
        repository.identifier = CSLRepositorySpecifierIdentifier;
        [repository setProperty:CSLRepositoryIcon() forKey:CSLSpecifierIconKey];
        repository->action = @selector(openRepository);
        [specifiers addObject:repository];

        PSSpecifier *footer = [PSSpecifier emptyGroupSpecifier];
        [footer setProperty:CSLSettingsVersionText forKey:@"footerText"];
        [specifiers addObject:footer];

        _specifiers = [specifiers copy];
    }

    return _specifiers;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // The module count and the module names can both change on the pages this
    // controller pushes, so the slot rows are rebuilt on every appearance.
    [self reloadSpecifiers];
}

- (void)moduleCountCellDidChange:(__unused CSLModuleCountCell *)cell {
    // Rebuild the module rows immediately while preserving all slot data. A
    // later increase restores the previous names and Shortcut assignments.
    [self reloadSpecifiers];
}

/// Returns NSNotFound for the rows that are not a module.
- (NSUInteger)slotForSpecifier:(PSSpecifier *)specifier {
    id slotValue = [specifier propertyForKey:CSLSlotSpecifierKey];
    if (![slotValue isKindOfClass:[NSNumber class]]) {
        return NSNotFound;
    }
    return [(NSNumber *)slotValue unsignedIntegerValue];
}

/// Uses the same routing as Settings → Control Center so both module lists
/// always show the same image.
- (UIImage *)iconForSlot:(NSUInteger)slot {
    NSArray<NSDictionary<NSString *, id> *> *entries =
        self.slotEntriesSnapshot[@(slot)] ?: @[];
    return CSLModuleSettingsIconForSlot(
        slot,
        entries,
        CGSizeMake(CSLSpecifierIconSide, CSLSpecifierIconSide)
    );
}

- (id)shortcutSummaryForSpecifier:(PSSpecifier *)specifier {
    NSUInteger slot = [self slotForSpecifier:specifier];
    if (slot == NSNotFound) {
        return nil;
    }

    NSUInteger count = self.slotEntriesSnapshot[@(slot)].count;
    if (count == 0) {
        return CSLLocalizedText(@"Không có phím tắt", @"No Shortcuts");
    }
    if (CSLUsesVietnamese()) {
        return [NSString stringWithFormat:@"%lu phím tắt", (unsigned long)count];
    }
    return [NSString stringWithFormat:@"%lu Shortcut%@",
        (unsigned long)count,
        count == 1 ? @"" : @"s"];
}

- (void)tableView:(UITableView *)tableView
    willDisplayCell:(UITableViewCell *)cell
  forRowAtIndexPath:(NSIndexPath *)indexPath {
    // Preferences themes its own cells here, but do not assume the superclass
    // implements an optional delegate method.
    if ([PSListController instancesRespondToSelector:_cmd]) {
        [super tableView:tableView willDisplayCell:cell forRowAtIndexPath:indexPath];
    }

    PSSpecifier *specifier = [self specifierAtIndexPath:indexPath];
    NSString *identifier = specifier.identifier ?: [specifier propertyForKey:@"id"];
    if ([identifier isEqualToString:CSLRepositorySpecifierIdentifier]) {
        if (cell.imageView.image == nil) {
            cell.imageView.image = CSLRepositoryIcon();
        }
        return;
    }

    NSUInteger slot = [self slotForSpecifier:specifier];
    if (slot == NSNotFound) {
        return;
    }

    // Indent the modules so they read as entries under the count above them.
    cell.indentationLevel = 1;
    cell.indentationWidth = 16.0;

    // The specifier already carries the icon and the summary, but a plain link
    // cell does not always draw them, so fill in whatever is still empty.
    if (cell.imageView.image == nil) {
        cell.imageView.image = [self iconForSlot:slot];
    }
    if (cell.detailTextLabel.text.length == 0) {
        cell.detailTextLabel.text = [self shortcutSummaryForSpecifier:specifier];
    }
}

- (void)confirmRespring {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:CSLLocalizedText(
                                     @"Khởi động lại giao diện",
                                     @"Respring"
                                 )
                         message:CSLLocalizedText(
                             @"Thao tác này sẽ khởi động lại nhanh Màn hình chính và Trung tâm điều khiển. Ứng dụng và dữ liệu của bạn không bị ảnh hưởng.",
                             @"This briefly restarts the Home Screen and Control Center. Your apps and data are not affected."
                         )
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:CSLLocalizedText(@"Hủy", @"Cancel")
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:CSLLocalizedText(
                                                         @"Khởi động lại",
                                                         @"Respring"
                                                     )
                                              style:UIAlertActionStyleDestructive
                                            handler:^(__unused UIAlertAction *action) {
        [self respring];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

/// Settings cannot spawn sbreload, so ask the render server to restart the way
/// SpringBoard itself does.
- (void)respring {
    Class relaunchActionClass = NSClassFromString(@"SBSRelaunchAction");
    Class systemServiceClass = NSClassFromString(@"FBSSystemService");
    if (relaunchActionClass == Nil || systemServiceClass == Nil) {
        [self showRespringUnavailable];
        return;
    }

    @try {
        id action = ((id (*)(id, SEL, id, NSUInteger, id))objc_msgSend)(
            relaunchActionClass,
            NSSelectorFromString(@"actionWithReason:options:targetURL:"),
            @"RestartRenderServer",
            4,
            nil
        );
        id service = ((id (*)(id, SEL))objc_msgSend)(
            systemServiceClass,
            NSSelectorFromString(@"sharedService")
        );
        if (action == nil || service == nil) {
            [self showRespringUnavailable];
            return;
        }
        ((void (*)(id, SEL, id, id))objc_msgSend)(
            service,
            NSSelectorFromString(@"sendActions:withResult:"),
            [NSSet setWithObject:action],
            nil
        );
    } @catch (NSException *exception) {
        NSLog(@"[CCShortcutLauncher][Settings] RESPRING_EXCEPTION exception=%@ reason=%@",
              exception.name,
              exception.reason);
        [self showRespringUnavailable];
    }
}

- (void)showRespringUnavailable {
    [self showMessageWithTitle:CSLLocalizedText(
                               @"Không thể khởi động lại giao diện",
                               @"Respring Unavailable"
                           )
                       message:CSLLocalizedText(
                           @"Hãy dùng tùy chọn Respring trong trình quản lý gói, sau đó quay lại Trung tâm điều khiển.",
                           @"Use the Respring option in your package manager, then return to Control Center."
                       )];
}

- (void)openModuleSlot:(PSSpecifier *)specifier {
    NSUInteger slot = [self slotForSpecifier:specifier];
    if (slot == NSNotFound) {
        return;
    }
    CSLShortcutOrderController *controller =
        [[CSLShortcutOrderController alloc] initWithSlot:slot];
    [self.navigationController pushViewController:controller animated:YES];
}

- (void)openRepository {
    NSURL *url = [NSURL URLWithString:CSLRepositoryURLString];
    if (url == nil) {
        return;
    }
    [[UIApplication sharedApplication] openURL:url
                                       options:@{}
                             completionHandler:nil];
}

- (void)showMessageWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)finishLoadingWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *loadingAlert = _loadingAlert;
    _loadingAlert = nil;
    if (loadingAlert.presentingViewController != nil) {
        [loadingAlert dismissViewControllerAnimated:YES completion:^{
            [self showMessageWithTitle:title message:message];
        }];
    } else {
        [self showMessageWithTitle:title message:message];
    }
}

- (void)pollCatalogWithGeneration:(NSUInteger)generation
                          attempt:(NSUInteger)attempt {
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)),
        dispatch_get_main_queue(),
        ^{
            if (generation != self->_resolveGeneration) {
                return;
            }

            CFPreferencesAppSynchronize(CSLPreferencesDomain);
            NSString *state =
                CSLPreferenceStringWithoutSynchronizing(CFSTR("ResolverState"));
            id catalogValue =
                CSLPreferenceValueWithoutSynchronizing(CFSTR("ShortcutsCatalog"));
            NSUInteger count = [catalogValue isKindOfClass:[NSArray class]]
                ? [(NSArray *)catalogValue count]
                : 0;

            if ([state isEqualToString:@"catalog_ready"]) {
                // Zero is a valid result: every Shortcut may have been deleted.
                NSString *message = nil;
                if (count > 0 && CSLUsesVietnamese()) {
                    message = [NSString stringWithFormat:
                        @"Đã tải %lu phím tắt. Mở một mô-đun bên dưới để chọn phím tắt sẽ chạy.",
                        (unsigned long)count];
                } else if (count > 0) {
                    NSString *shortcutLabel = count == 1
                        ? @"Shortcut is"
                        : @"Shortcuts are";
                    message = [NSString stringWithFormat:
                        @"%lu %@ ready. Open a module below to choose which ones it runs.",
                        (unsigned long)count,
                        shortcutLabel];
                } else {
                    message = CSLLocalizedText(
                        @"Không tìm thấy phím tắt. Hãy tạo một phím tắt trong ứng dụng Phím tắt rồi thử lại.",
                        @"No Shortcuts were found. Create one in the Shortcuts app, then try again."
                    );
                }
                [self finishLoadingWithTitle:CSLLocalizedText(
                                                   @"Đã tải phím tắt của tôi",
                                                   @"My Shortcuts Loaded"
                                               )
                                         message:message];
                return;
            }

            if ([state isEqualToString:@"error"]) {
                NSString *errorMessage = CSLPreferenceStringWithoutSynchronizing(
                    CFSTR("ResolverMessage")
                );
                NSString *message = CSLUsesVietnamese()
                    ? @"Không thể tải phím tắt. Hãy mở khóa thiết bị rồi thử lại."
                    : (errorMessage.length > 0
                        ? errorMessage
                        : @"Unlock the device and try again.");
                [self finishLoadingWithTitle:CSLLocalizedText(
                                                   @"Không thể tải phím tắt của tôi",
                                                   @"Unable to Load My Shortcuts"
                                               )
                                         message:message];
                return;
            }

            if (attempt >= 39) {
                [self finishLoadingWithTitle:CSLLocalizedText(
                                                   @"Tải quá lâu",
                                                   @"Loading Is Taking Too Long"
                                               )
                                         message:CSLLocalizedText(
                                             @"Hãy đảm bảo thiết bị đã được mở khóa, sau đó chạm Tải phím tắt của tôi lần nữa.",
                                             @"Make sure the device is unlocked, then tap Load My Shortcuts again."
                                         )];
                return;
            }

            [self pollCatalogWithGeneration:generation attempt:attempt + 1];
        }
    );
}

- (void)loadMyShortcuts {
    _resolveGeneration++;
    NSUInteger generation = _resolveGeneration;

    CFPreferencesSetAppValue(
        CFSTR("ResolverState"),
        CFSTR("catalog_requested"),
        CSLPreferencesDomain
    );
    CFPreferencesSetAppValue(CFSTR("ResolverMessage"), NULL, CSLPreferencesDomain);
    CFPreferencesAppSynchronize(CSLPreferencesDomain);

    _loadingAlert = [UIAlertController
        alertControllerWithTitle:CSLLocalizedText(
            @"Đang tải phím tắt của tôi",
            @"Loading My Shortcuts"
        )
        message:CSLLocalizedText(
            @"Đang lấy tên và biểu tượng phím tắt…",
            @"Getting your Shortcut names and icons…"
        )
        preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:_loadingAlert animated:YES completion:nil];

    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CSLCatalogRequestedNotification,
        NULL,
        NULL,
        true
    );
    [self pollCatalogWithGeneration:generation attempt:0];
}

@end
