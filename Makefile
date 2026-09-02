TARGET := iphone:clang:latest:10.0
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TOOL_NAME = flashlightd

flashlightd_FILES = main.m
flashlightd_FRAMEWORKS = Foundation AVFoundation
flashlightd_CFLAGS = -fobjc-arc -Wno-unused-variable
flashlightd_CODESIGN_FLAGS = -Sentitlements.plist
flashlightd_INSTALL_PATH = /usr/local/bin

include $(THEOS_MAKE_PATH)/tool.mk

after-install::
	install.exec "launchctl unload /Library/LaunchDaemons/com.flashlight.daemon.plist 2>/dev/null || true; launchctl load /Library/LaunchDaemons/com.flashlight.daemon.plist"
