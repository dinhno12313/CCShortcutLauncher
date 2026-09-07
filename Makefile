THEOS_PACKAGE_SCHEME = rootless

ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:16.0
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = CCShortcutLauncherProvider

CCShortcutLauncherProvider_BUNDLE_EXTENSION = bundle
CCShortcutLauncherProvider_FILES = CCShortcutLauncherProvider.m CCShortcutLauncher.m CCShortcutLauncherBackgroundRunner.m CSLHaptics.m CSLModuleIcon.m CSLShortcutIcon.m CSLSlotPreferences.m
CCShortcutLauncherProvider_RESOURCE_DIRS = Resources ModuleIcons
CCShortcutLauncherProvider_CFLAGS = -fobjc-arc -fmodules-cache-path=$(CURDIR)/.theos/module-cache
CCShortcutLauncherProvider_FRAMEWORKS = Foundation UIKit CoreText AudioToolbox
CCShortcutLauncherProvider_PRIVATE_FRAMEWORKS = ControlCenterUIKit
CCShortcutLauncherProvider_INSTALL_PATH = /Library/ControlCenter/CCSupport_Providers

include $(THEOS_MAKE_PATH)/bundle.mk

SUBPROJECTS += CCShortcutLauncherPrefs CSLResolverDaemon
include $(THEOS_MAKE_PATH)/aggregate.mk
