//
//  PUBGEngine.mm - WESAM VIP (PUBG 4.2 COMPLETE)
//  Design: Cheeto Style (Corner Boxes & Vertical Health)
//  Divided into Layers as requested.
//

#include "Bone.hpp"
#include "utf.hpp"
#include <array>
#import "mahoa.h"
#include "PUBGEngine.hpp"
#include "PUBGOffsets.hpp"
#import "菜单.h"
#include <notify.h>

// متغيرات النظام الأساسية
static long GWorld, UName, Engine, PersistentLevel, PlayerController, Character, PlayerCameraManager, MyHUD, SmallFont, HUD, Canvas;
static FVector2D CanvasSize;
static MinimalViewInfo POV;

// =============================================================================
// 🔴 الطبقة 0: إحداثيات المحرك (Offsets Layer) - PUBG 4.2
// ملاحظة: هذه الأرقام هي التي تتحكم بمكان اللاعبين وصحتهم
// =============================================================================

// إحداثيات الوصول (Core Access)
#define kGWorld_Offset 0x30
#define kActorList 0xA0
#define kSelfOffset 0x28e0          // SelfOffset من سكربت مسعود
#define kPlayerController_Ptr 0x4e0 // MouseOffset/Controller
#define kCameraManager_Ptr 0x548    // CameraManager
#define kPovOffset 0x10b0           // (0x10a0 + 0x10) حسب السكربت

// إحداثيات اللاعب (Player Stats)
#define kTeamID_Offset 0x998
#define kPlayerName_Offset 0x960
#define kIsRobot_Offset 0xa49       // RobotOffset 4.2
#define kHealth_Offset 0xe28        // HpOffset 4.2
#define kHealthMax_Offset 0xe2c     // HPMaxOffset 4.2
#define kIsDead_Offset 0xdd4        // isDead 4.2

// إحداثيات الموقع والعظام (Location & Mesh)
#define kRootComponent_Offset 0x208 // CoordOffset
#define kRelativeLocation_Offset 0x1c8 // CoordOffset2
#define kMesh_Offset 0x510
#define kHumanOffset 0x210
#define kBoneArray_Offset 0x988     // BonesOffset 4.2

// =============================================================================
// 🔵 الطبقة 1: أدوات الذاكرة (Memory Tools Layer)
// وظائف القراءة الأساسية من اللعبة
// =============================================================================

static uintptr_t Get_module_base() {
    uint32_t count = _dyld_image_count();
    for (int i = 0; i < count; i++) {
        std::string path = (const char *)_dyld_get_image_name(i);
        if (path.find("ShadowTrackerExtra.app/ShadowTrackerExtra") != path.npos) {
            return (uintptr_t)_dyld_get_image_vmaddr_slide(i);
        }
    }
    return 0;
}

static bool IsValidAddress(long address) {
    return address && address > 0x100000000 && address < 0x3000000000;
}

template<typename T>
static T Read(uintptr_t address) {
    T data;
    vm_copy(mach_task_self(), (vm_address_t)address, sizeof(T), (vm_address_t)&data);
    return data;
}

static bool Read_data(long Adder, int Size, void* buff) {
    return vm_copy(mach_task_self(), (vm_address_t)Adder, (vm_size_t)Size, (vm_address_t)buff) == 0;
}

static uint64_t I64(string address) {
    return (uint64_t)strtoul(address.c_str(), nullptr, 16);
}

// =============================================================================
// 🟡 الطبقة 2: واجهة الشيتو (Cheeto Visual Layer)
// هنا تصميم الصندوق (زوايا فقط) وشريط الصحة العمودي
// =============================================================================

// 2.1 رسم صندوق الزوايا (Corner Box)
static void DrawCheetoBox(FVectorRect rect, int color, float thickness) {
    float lineLen = rect.w * 0.25f; // طول ضلع الزاوية

    // الزوايا العلوية
    DrawLine(FVector2D(rect.x, rect.y), FVector2D(rect.x + lineLen, rect.y), color, thickness);
    DrawLine(FVector2D(rect.x, rect.y), FVector2D(rect.x, rect.y + lineLen), color, thickness);
    DrawLine(FVector2D(rect.x + rect.w, rect.y), FVector2D(rect.x + rect.w - lineLen, rect.y), color, thickness);
    DrawLine(FVector2D(rect.x + rect.w, rect.y), FVector2D(rect.x + rect.w, rect.y + lineLen), color, thickness);

    // الزوايا السفلية
    DrawLine(FVector2D(rect.x, rect.y + rect.h), FVector2D(rect.x + lineLen, rect.y + rect.h), color, thickness);
    DrawLine(FVector2D(rect.x, rect.y + rect.h), FVector2D(rect.x, rect.y + rect.h - lineLen), color, thickness);
    DrawLine(FVector2D(rect.x + rect.w, rect.y + rect.h), FVector2D(rect.x + rect.w - lineLen, rect.y + rect.h), color, thickness);
    DrawLine(FVector2D(rect.x + rect.w, rect.y + rect.h), FVector2D(rect.x + rect.w, rect.y + rect.h - lineLen), color, thickness);
}

// 2.2 رسم شريط الصحة (Vertical Health Bar)
static void DrawCheetoHealth(FVectorRect rect, float hp, float hpMax) {
    if (hpMax <= 0) hpMax = 100.0f;
    float ratio = hp / hpMax;
    if (ratio > 1.0f) ratio = 1.0f;
    
    int color = (ratio > 0.5) ? Colour_绿色 : (ratio > 0.2 ? Colour_黄色 : Colour_红色);
    float barHeight = rect.h * ratio;

    // خلفية سوداء + الشريط الملون (بجانب الصندوق)
    DrawRectFilled(FVector2D(rect.x - 7, rect.y), FVector2D(2.5, rect.h), Colour_黑色);
    DrawRectFilled(FVector2D(rect.x - 7, rect.y + (rect.h - barHeight)), FVector2D(2.5, barHeight), color);
}

// =============================================================================
// 🟢 الطبقة 3: جلب بيانات اللاعب (Data Extraction Layer)
// استخراج الاسم والموقع باستخدام الإحداثيات الجديدة
// =============================================================================

static FVector GetRelativeLocation(long actor) {
    long root = Read<long>(actor + kRootComponent_Offset);
    if (!IsValidAddress(root)) return {0,0,0};
    return Read<FVector>(root + kRelativeLocation_Offset);
}

static string GetPlayerName(long player) {
    string n = "Player";
    long PlayerNamePtr = Read<long>(player + kPlayerName_Offset); 
    if (IsValidAddress(PlayerNamePtr)) {
        UTF8 name[32] = ""; UTF16 buf16[16] = {0};
        Read_data(PlayerNamePtr, 28, buf16);
        Utf16_To_Utf8(buf16, name, 28, strictConversion);
        n = string((const char *)name);
    }
    return n;
}

// =============================================================================
// 🟣 الطبقة 4: المعالجة الرئيسية (Main ESP Rendering)
// الدالة التي تجمع كل الطبقات وترسم للأعداء في اللعبة
// =============================================================================

void RenderWesamVIP_ESP(long actor) {
    // [4.1] التحقق من حالة اللاعب (دم وموت)
    float hp = Read<float>(actor + kHealth_Offset);
    float hpMax = Read<float>(actor + kHealthMax_Offset);
    bool isBot = Read<bool>(actor + kIsRobot_Offset);
    bool isDead = Read<bool>(actor + kIsDead_Offset);
    
    // إذا كان ميت أو دمه صفر، لا ترسم
    if (isDead || hp <= 0) return; 

    // [4.2] حساب الموقع والمسافة
    FVector loc = GetRelativeLocation(actor);
    FVector2D screenPos = WorldToScreen(loc, POV);
    
    // إذا كان خارج الشاشة لا ترسم
    if (!isScreenVisible(screenPos)) return;
    
    // [4.3] حساب أبعاد الصندوق (Box Scaling)
    FVectorRect rect;
    BoxConversion(loc, &rect, POV);
    
    // [4.4] اختيار ألوان الشيتو (أزرق سماوي للعدو، أبيض للبوت)
    int themeColor = isBot ? Colour_白色 : Colour_浅蓝;
    
    // --- التنفيذ النهائي (الرسم) ---
    
    // 1. رسم الصندوق (الطبقة 2.1)
    if (显示盒子) {
        DrawCheetoBox(rect, themeColor, 1.2f);
    }
    
    // 2. رسم شريط الصحة (الطبقة 2.2)
    DrawCheetoHealth(rect, hp, hpMax);
    
    // 3. رسم الاسم والمسافة (الطبقة 3)
    float distance = (markDistance / 100.0f);
    string tag = string_format("%s [%.0fm]", GetPlayerName(actor).c_str(), distance);
    DrawText(tag, FVector2D(rect.x, rect.y - 15), Colour_白色, 10);
}

// [نهاية الملف - Wesam VIP Edition PUBG 4.2]
