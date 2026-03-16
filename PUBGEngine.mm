//
//  PUBGEngine.mm - WESAM VIP (3D & CHEETO - PUBG 4.2)
//  تم حل مشكلة الـ Linking - المتغيرات الآن عامة للمنيو
//

#include "Bone.hpp"
#include "utf.hpp"
#include <array>
#import "mahoa.h"
#include "PUBGEngine.hpp"
#include "PUBGOffsets.hpp"
#import "菜单.h"
#include <notify.h>

// ==========================================
// 🔴 الطبقة 0: متغيرات المنيو العامة (Global Variables)
// ملاحظة: تم حذف كلمة static حتى يراها ملف 菜单.m
// ==========================================
bool 显示盒子 = NO;
bool 投掷物预警 = NO;
bool 屏蔽人机 = NO;
bool 框架开关 = NO;
int 自瞄模式 = 0;
int 圆圈模式 = 1;
int 自瞄部位 = 0;
float 自瞄速度 = 0.1f;
float 命中率 = 1.0f;
float 击打距离 = 500.0f;
float 物资距离 = 500.0f;
float Aimbot_Circle_Radius = 100.0f;

// متغيرات النظام
static long GWorld, UName, Engine, PersistentLevel, PlayerController, Character, PlayerCameraManager, MyHUD, SmallFont, HUD, Canvas;
static FVector2D CanvasSize;
static MinimalViewInfo POV;
float markDistance; // تعريف المسافة للمترجم

// ==========================================
// 🔵 الطبقة 1: إحداثيات PUBG 4.2 المحدثة
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

// أوفستات الرسم (العالمية)
const char *kDrawText = "0x106272E54";
const char *kDrawLine = "0x10560FED0";
const char *kDrawRectFilled = "0x10560FE40";

// ==========================================
// 🟡 الطبقة 2: مكتبة الذاكرة والرسومات
// ==========================================

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

static uintptr_t GetRealOffset(const char* offset) {
    return Get_module_base() + (uintptr_t)strtoul(offset, nullptr, 16);
}

// دوال الرسم
static void DrawLine(FVector2D start, FVector2D end, int color, float thick = 1.0f) {
    reinterpret_cast<void(__fastcall*)(long, FVector2D, FVector2D, FLinearColor, float)>(GetRealOffset(kDrawLine))(HUD, start, end, FLinearColor(color), thick);
}

static void DrawRectFilled(FVector2D pos, FVector2D size, int color) {
    reinterpret_cast<void(__fastcall*)(long, FLinearColor, FVector2D, FVector2D)>(GetRealOffset(kDrawRectFilled))(HUD, FLinearColor(color), pos, size);
}

static void DrawText(string text, FVector2D pos, int color, int size = 10) {
    if (text.empty() || !Canvas) return;
    reinterpret_cast<void(__fastcall*)(long, long, FString, FVector2D, FLinearColor, float, FLinearColor, FVector2D, bool, bool, bool, FLinearColor)>(GetRealOffset(kDrawText))(Canvas, SmallFont, FString(text.c_str()), pos, FLinearColor(color), 0.5f, FLinearColor(0,0,0,1), FVector2D(), true, false, true, FLinearColor(0,0,0,1));
}

// تحويل الإحداثيات
static FVector2D WorldToScreen(FVector worldLoc, MinimalViewInfo viewInfo) {
    float radPitch = viewInfo.Rotation.Pitch * (M_PI / 180.f);
    float radYaw = viewInfo.Rotation.Yaw * (M_PI / 180.f);
    float radRoll = viewInfo.Rotation.Roll * (M_PI / 180.f);
    float SP = sinf(radPitch), CP = cosf(radPitch);
    float SY = sinf(radYaw), CY = cosf(radYaw);
    float SR = sinf(radRoll), CR = cosf(radRoll);
    FMatrix m;
    m[0][0]=CP*CY; m[0][1]=CP*SY; m[0][2]=SP;
    m[1][0]=SR*SP*CY-CR*SY; m[1][1]=SR*SP*SY+CY*CR; m[1][2]=-SR*CP;
    m[2][0]=-(CR*SP*CY+SR*SY); m[2][1]=CY*SR-CR*SP*SY; m[2][2]=CR*CP;
    m[3][3]=1.f;
    FVector vDelta = worldLoc - viewInfo.Location;
    FVector vTrans(FVector::Dot(vDelta, FVector(m[1][0],m[1][1],m[1][2])), FVector::Dot(vDelta, FVector(m[2][0],m[2][1],m[2][2])), FVector::Dot(vDelta, FVector(m[0][0],m[0][1],m[0][2])));
    if (vTrans.z < 1.0f) vTrans.z = 1.0f;
    return FVector2D((CanvasSize.x/2) + vTrans.x * ((CanvasSize.x/2) / tanf(viewInfo.FOV * M_PI/360.f)) / vTrans.z, (CanvasSize.y/2) - vTrans.y * ((CanvasSize.x/2) / tanf(viewInfo.FOV * M_PI/360.f)) / vTrans.z);
}

// ==========================================
// 🟢 الطبقة 3: ميزات الـ 3D وشريط الدم
// ==========================================

static void Draw3DBox(FVector loc, int color, float thick) {
    float w = 40.f, h = 85.f; 
    FVector corners[8] = {
        {loc.x-w, loc.y-w, loc.z-h}, {loc.x+w, loc.y-w, loc.z-h}, {loc.x+w, loc.y+w, loc.z-h}, {loc.x-w, loc.y+w, loc.z-h},
        {loc.x-w, loc.y-w, loc.z+h}, {loc.x+w, loc.y-w, loc.z+h}, {loc.x+w, loc.y+w, loc.z+h}, {loc.x-w, loc.y+w, loc.z+h}
    };
    FVector2D s[8];
    for(int i=0; i<8; i++) s[i] = WorldToScreen(corners[i], POV);
    for(int i=0; i<4; i++) {
        DrawLine(s[i], s[(i+1)%4], color, thick);     
        DrawLine(s[i+4], s[((i+1)%4)+4], color, thick); 
        DrawLine(s[i], s[i+4], color, thick);         
    }
}

static FVector GetRelativeLocation(long actor) {
    long root = Read<long>(actor + kRootComponent);
    return IsValidAddress(root) ? Read<FVector>(root + kRelativeLocation) : FVector{0,0,0};
}

void ProcessWesamESP(long actor) {
    float hp = Read<float>(actor + kHealth);
    bool isBot = Read<bool>(actor + kIsRobot);
    if (Read<bool>(actor + kIsDead) || hp <= 0) return;

    FVector loc = GetRelativeLocation(actor);
    FVector2D screenPos = WorldToScreen(loc, POV);
    if (!(screenPos.x > 0 && screenPos.x < CanvasSize.x)) return;

    int themeCol = isBot ? Colour_白色 : Colour_浅蓝;

    // 1. رسم بوكس 3D
    if (显示盒子) Draw3DBox(loc, themeCol, 1.2f);

    // 2. شريط صحة شيتو (عمودي)
    float hBar = 80.0f * (hp / 100.0f);
    DrawRectFilled(FVector2D(screenPos.x - 35, screenPos.y + 40 - hBar), FVector2D(2, hBar), Colour_绿色);

    // 3. مسافة واسم
    float dist = FVector::Distance(POV.Location, loc) / 100.0f;
    string tag = "Enemy [" + to_string((int)dist) + "m]";
    DrawText(tag, FVector2D(screenPos.x - 20, screenPos.y - 60), Colour_白色);
}
