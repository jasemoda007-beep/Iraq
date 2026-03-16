ARCHS = arm64
DEBUG = 0
FINALPACKAGE = 1
FOR_RELEASE = 1
THEOS_PACKAGE_SCHEME = rootless

TWEAK_NAME = UE4

include $(THEOS)/makefiles/common.mk

UE4_FRAMEWORKS = UIKit Foundation Security QuartzCore CoreGraphics CoreText AVFoundation Accelerate GLKit SystemConfiguration GameController

# توجيه المترجم للبحث عن ملفات الهيدر بداخل فولدر Menu والواجهة
UE4_CCFLAGS = -std=c++14 -fno-rtti -fno-exceptions -DNDEBUG -w -s -I. -IMenu
UE4_CFLAGS = -w -fobjc-arc -Wno-deprecated-declarations -Wno-unused-variable -I. -IMenu

# سحب PUBGEngine.mm من الواجهة وكل الملفات من فولدر Menu
UE4_FILES = PUBGEngine.mm $(wildcard Menu/*.m) $(wildcard Menu/*.mm) $(wildcard Menu/*.cpp) $(wildcard Menu/*.xm)

include $(THEOS_MAKE_PATH)/tweak.mk
after-install::
	install.exec "killall -9 ShadowTrackerExtra || :"
