//
//  PUBGEngine.mm - WESAM VIP (3D EDITION)
//  كامل مكمل 100% - يحتوي على مكتبة الرسومات والتحويل الإحداثي
//

#include "Bone.hpp"
#include "utf.hpp"
#include <array>
#import "mahoa.h"
#include "PUBGEngine.hpp"
#include "PUBGOffsets.hpp"
#import "菜单.h"
#include <notify.h>

// متغيرات النظام
static long GWorld, UName, Engine, PersistentLevel, PlayerController, Character, PlayerCameraManager, MyHUD, SmallFont, HUD, Canvas;
static FVector2D CanvasSize;
static MinimalViewInfo POV;

// ==========================================
// 🔴 الطبقة 0: إحداثيات PUBG 4.2 (الأوفستات)
// ==========================================
#define kSelfOffset 0x28e0
#define kRootComponent 0x208
#define kRelativeLocation 0x1c8
#define kHealth 0xe28
#define kHealthMax 0xe2c
#define kIsRobot 0xa49
#define kPlayerName 0x960
#define kTeamID 0x998
#define kIsDead 0xdd4

// ==========================================
// 🔵 الطبقة 1: مكتبة الرسومات والذاكرة (Graphics & Memory Lib)
// (هذا القسم يحل الـ 16 خطأ اللي ظهروا عندك)
// ==========================================

template<typename T>
static T Read(uintptr_t address) {
    T data;
    vm_copy(mach_task_self(), (vm_address_t)address, sizeof(T), (vm_address_t)&data);
    return data;
}

static bool Read_data(long Adder, int Size, void* buff) {
    return vm_copy(mach_task_self(), (vm_address_t)Adder, (vm_size_t)Size, (vm_address_t)buff) == 0;
}

static uintptr_t GetRealOffset(string address) {
    static uintptr_t base = 0;
    if (!base) {
        uint32_t count = _dyld_image_count();
        for (int i = 0; i < count; i++) {
            if (string(_dyld_get_image_name(i)).find("ShadowTrackerExtra") != string::npos) {
                base = _dyld_get_image_vmaddr_slide(i); break;
            }
        }
    }
    return base + (uintptr_t)strtoul(address.c_str(), nullptr, 16);
}

// دوال الرسم الأساسية
static void DrawLine(FVector2D start, FVector2D end, int color, float thick = 1.0f) {
    reinterpret_cast<void(__fastcall*)(long, FVector2D, FVector2D, FLinearColor, float)>(GetRealOffset(kDrawLine))(HUD, start, end, FLinearColor(color), thick);
}

static void DrawRectFilled(FVector2D pos, FVector2D size, int color) {
    reinterpret_cast<void(__fastcall*)(long, FLinearColor, FVector2D, FVector2D)>(GetRealOffset(kDrawRectFilled))(HUD, FLinearColor(color), pos, size);
}

static void DrawText(string text, FVector2D pos, int color, int size = 10) {
    if (text.empty()) return;
    reinterpret_cast<void(__fastcall*)(long, long, FString, FVector2D, FLinearColor, float, FLinearColor, FVector2D, bool, bool, bool, FLinearColor)>(GetRealOffset(kDrawText))(Canvas, SmallFont, FString(text.c_str()), pos, FLinearColor(color), 0.5f, FLinearColor(0,0,0,1), FVector2D(), true, false, true, FLinearColor(0,0,0,1));
}

// تحويل الإحداثيات (WorldToScreen)
static FVector2D WorldToScreen(FVector worldLoc, MinimalViewInfo viewInfo) {
    float radPitch = viewInfo.Rotation.Pitch * (M_PI / 180.f);
    float radYaw = viewInfo.Rotation.Yaw * (M_PI / 180.f);
    float radRoll = viewInfo.Rotation.Roll * (M_PI / 180.f);
    float SP = sinf(radPitch), CP = cosf(radPitch);
    float SY = sinf(radYaw), CY = cosf(radYaw);
    float SR = sinf(radRoll), CR = cosf(radRoll);
    FMatrix m;
    m[0][0]=CP*CY; m[0][1]=CP*SY; m[0][2]=SP;
    m[1][0]=SR*SP*CY-CR*SY; m[1][1]=SR*SP*SY+CR*CY; m[1][2]=-SR*CP;
    m[2][0]=-(CR*SP*CY+SR*SY); m[2][1]=CY*SR-CR*SP*SY; m[2][2]=CR*CP;
    m[3][3]=1.f;
    FVector vDelta = worldLoc - viewInfo.Location;
    FVector vTrans(FVector::Dot(vDelta, FVector(m[1][0],m[1][1],m[1][2])), FVector::Dot(vDelta, FVector(m[2][0],m[2][1],m[2][2])), FVector::Dot(vDelta, FVector(m[0][0],m[0][1],m[0][2])));
    if (vTrans.z < 1.0f) vTrans.z = 1.0f;
    float centerX = CanvasSize.x/2, centerY = CanvasSize.y/2;
    return FVector2D(centerX + vTrans.x * (centerX / tanf(viewInfo.FOV * M_PI/360.f)) / vTrans.z, centerY - vTrans.y * (centerX / tanf(viewInfo.FOV * M_PI/360.f)) / vTrans.z);
}

// دالة فحص الظهور على الشاشة
static bool isScreenVisible(FVector2D pos) {
    return (pos.x > 0 && pos.x < CanvasSize.x && pos.y > 0 && pos.y < CanvasSize.y);
}

// ==========================================
// 🟡 الطبقة 2: ميزة الـ 3D Box (التصميم الحديث)
// ==========================================

static void Draw3DBox(FVector loc, int color, float thick) {
    float w = 45.f, h = 90.f; // أبعاد الصندوق الافتراضية
    FVector corners[8] = {
        {loc.x-w, loc.y-w, loc.z-h}, {loc.x+w, loc.y-w, loc.z-h}, {loc.x+w, loc.y+w, loc.z-h}, {loc.x-w, loc.y+w, loc.z-h},
        {loc.x-w, loc.y-w, loc.z+h}, {loc.x+w, loc.y-w, loc.z+h}, {loc.x+w, loc.y+w, loc.z+h}, {loc.x-w, loc.y+w, loc.z+h}
    };
    FVector2D s[8];
    for(int i=0; i<8; i++) s[i] = WorldToScreen(corners[i], POV);
    
    // رسم الأضلاع الـ 12 للبوكس الـ 3D
    for(int i=0; i<4; i++) {
        DrawLine(s[i], s[(i+1)%4], color, thick);     // قاعدة
        DrawLine(s[i+4], s[((i+1)%4)+4], color, thick); // سقف
        DrawLine(s[i], s[i+4], color, thick);         // أعمدة جانبية
    }
}

// ==========================================
// 🟢 الطبقة 3: المعالجة الرئيسية (ESP Processor)
// ==========================================

static FVector GetRelativeLocation(long actor) {
    long root = Read<long>(actor + kRootComponent);
    return IsValidAddress(root) ? Read<FVector>(root + kRelativeLocation) : FVector{0,0,0};
}

void RenderPlayerESP(long actor) {
    float hp = Read<float>(actor + kHealth);
    bool isBot = Read<bool>(actor + kIsRobot);
    if (Read<bool>(actor + kIsDead) || hp <= 0) return;

    FVector loc = GetRelativeLocation(actor);
    FVector2D screenPos = WorldToScreen(loc, POV);
    if (!isScreenVisible(screenPos)) return;

    int themeCol = isBot ? Colour_白色 : Colour_浅蓝;

    // تفعيل الـ 3D Box
    if (显示盒子) Draw3DBox(loc, themeCol, 1.2f);

    // شريط الصحة العمودي (شيتو ستايل)
    DrawRectFilled(FVector2D(screenPos.x-40, screenPos.y-50), FVector2D(2, 100 * (hp/100.f)), Colour_绿色);

    // الاسم والمسافة
    string info = "Enemy [" + to_string((int)(markDistance/100)) + "m]";
    DrawText(info, FVector2D(screenPos.x-20, screenPos.y-70), Colour_白色);
}
