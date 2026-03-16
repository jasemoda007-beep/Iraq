//
//  PUBGEngine.mm
//  PUBGEngine
//
//  Created by ABC on 2021/10/11.
//
#include "Bone.hpp"
#include "utf.hpp"
#include <array>
#import "mahoa.h"
#include "PUBGEngine.hpp"
#include "PUBGOffsets.hpp"
#import "菜单.h"
#include <notify.h>

// متغيرات المحرك الأساسية
static long GWorld, UName, Engine, PersistentLevel, PlayerController, Character, PlayerCameraManager, ControlRotation, MyHUD, TinyFont, SmallFont, HUD, Canvas;
static int totalEnemies = 0; 
static int robotcounts= 0; 
static int MyTeam, pickItemCount;
static int WeaponId = 0;
static float tDistance = 0, markDistance, Health, markDis;
float Aimbot_Circle_Radius = 100;
static bool needAdjustAim = false, sniperrifle = false;

// ==========================================
// 🛠️ المتغيرات الصينية (مترجمة للعربي) 🛠️
// ==========================================
bool 显示盒子=NO;            // إظهار الصناديق
static FVector CameraCache, TracktargetPos; 
bool 投掷物预警=NO;          // تحذير القنابل
static FVector2D CanvasSize, markScreenPos;
static FVector2D rootScreen;
static MinimalViewInfo POV;

int 圆圈模式 = 1;            // وضع الدائرة
int 自瞄部位 = 0;            // منطقة الايمبوت
int 雷达大小 = 400;          // حجم الرادار
int 雷达X = 500;             // موقع الرادار X
int 雷达Y = 60;              // موقع الرادار Y
int 人物美化;                // سكنات اللاعبين
int 枪械美化;                // سكنات الأسلحة

int 圆圈固定 = 75;           
int 预警范围 = 38;           
float 自瞄速度 = 0.1;        // سرعة الايمبوت
float 命中率 = 1.00;         // نسبة الإصابة
float 压枪速率 = 0;          // ثبات السلاح
float 击打距离 = 500;        // مسافة الايمبوت
float 物资距离 = 500;        // مسافة اللوت

bool 屏蔽人机=NO;            // تجاهل البوتات
bool 框架开关 = NO;          // مفتاح الرادار
int 自瞄模式 = 0;            // وضع الايمبوت
// ==========================================

// الأوفستات الأساسية
const char *kDrawText = "0x106272E54";
const char *kDrawLine = "0x10560FED0";
const char *kDrawRectFilled = "0x10560FE40";
const char *kDrawCircleFilled = "0x1059B7238";

const char *kEngine = "0x1093514D8";
const char *kUWorld = "0x105D13894";
const char *kGNames = "0x1044748F4";

const char *hookHUD = "0x107814DF0";
const char *kGetHUD = "0x10332B270";

const char *kLineOfSight_1 = "0x1090410B8";
const char *kLineOfSight_2 = "0x10933A6D0";
const char *kLineOfSight_3 = "0x10546AE34";
const char *kLineOfSight_4 = "0x10546AF20";
const char *kLineOfSight_5 = "0x10547A940";

const char *kBonePos = "0x10302FE30";
const char *kProjectWorldLocationToScreen = "0x10621D764";

#pragma mark - 内存读写
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

static uintptr_t GetHexAddr(string address) {
    return (uintptr_t)strtoul(address.c_str(), nullptr, 16);
}

static uintptr_t GetRealOffset(string address) {
    return (Get_module_base() + GetHexAddr(address));
}

template<typename T>
static T Read(uintptr_t address) {
    T data;
    vm_copy(mach_task_self(), (vm_address_t)address, sizeof(T), (vm_address_t)&data);
    return data;
}

template<typename T>
static void Write(uintptr_t address, T data) {
    vm_copy(mach_task_self(), (vm_address_t)&data, sizeof(T), (vm_address_t)address);
}

static bool Read_data(long Adder, int Size, void* buff) {
    kern_return_t kret = vm_copy(mach_task_self(), (vm_address_t)Adder, (vm_size_t)Size, (vm_address_t)buff);
    return kret == 0;
}

static uint64_t I64(string address) {
    return (uint64_t)strtoul(address.c_str(), nullptr, 16);
}

#pragma mark - 字符串工具
static bool isEqual(string s1, const char* check) {
    string s2(check);
    return (s1 == s2);
}

static bool isContain(string str, const char* check) {
    size_t found = str.find(check);
    return (found != string::npos);
}

#pragma mark - دوال الرسم
static void DrawLine(FVector2D startPoint, FVector2D endPoint, int color, float thicknes = 1) {
    reinterpret_cast<void(__fastcall*)(long, struct FVector2D, struct FVector2D, struct FLinearColor, float) > (GetRealOffset(kDrawLine))(HUD, startPoint, endPoint, FLinearColor(color), thicknes);
}

static void DrawRectFilled(FVector2D pos, FVector2D size, int color, float thicknes = 2) {
    reinterpret_cast<void(__fastcall*)(long, struct FLinearColor, struct FVector2D, struct FVector2D) > (GetRealOffset(kDrawRectFilled))(HUD, FLinearColor(color), pos, size);
}

static void DrawText(string text, FVector2D pos, int color, int fontsize = 12) {
    if (text.length() == 0) return;
    char str[256];
    strncpy(str, text.c_str(), sizeof(str));
    reinterpret_cast<void(__fastcall*)(long, long, const class FString&, struct FVector2D, struct FLinearColor, float, struct FLinearColor, struct FVector2D, bool, bool, bool, struct FLinearColor) > (GetRealOffset(kDrawText))(Canvas, SmallFont, FString(str), pos, FLinearColor(color), 0.5f, FLinearColor(0, 0, 0, 1.f), FVector2D(), true, false, true, FLinearColor(Colour_黑色));
}

static void DrawCircle(FVector2D pos, float radius, int color, float thicknes = 1) {
    int num_segments = 100;
    float step = M_PI * 2.0f / num_segments;
    for (int i = 0; i < num_segments; i++) {
        float a1 = i * step;
        float a2 = (i + 1) * step;
        FVector2D p1 = FVector2D(pos.x + cos(a1) * radius, pos.y + sin(a1) * radius);
        FVector2D p2 = FVector2D(pos.x + cos(a2) * radius, pos.y + sin(a2) * radius);
        DrawLine(p1, p2, color, thicknes);
    }
}

#pragma mark - تحويل الإحداثيات
static FMatrix RotatorToMatrix(FRotator rotation) {
    float radPitch = rotation.Pitch * (M_PI / 180.0f);
    float radYaw = rotation.Yaw * (M_PI / 180.0f);
    float radRoll = rotation.Roll * (M_PI / 180.0f);
    float SP = sinf(radPitch); float CP = cosf(radPitch);
    float SY = sinf(radYaw);   float CY = cosf(radYaw);
    float SR = sinf(radRoll);  float CR = cosf(radRoll);
    FMatrix m;
    m[0][0] = (CP * CY); m[0][1] = (CP * SY); m[0][2] = (SP);
    m[1][0] = (SR * SP * CY - CR * SY); m[1][1] = (SR * SP * SY + CR * CY); m[1][2] = (-SR * CP);
    m[2][0] = (-(CR * SP * CY + SR * SY)); m[2][1] = (CY * SR - CR * SP * SY); m[2][2] = (CR * CP);
    m[3][3] = 1;
    return m;
}

static FVector2D WorldToScreen(FVector worldLocation, MinimalViewInfo camViewInfo) {
    FMatrix m = RotatorToMatrix(camViewInfo.Rotation);
    FVector vDelta = worldLocation - camViewInfo.Location;
    FVector vTransformed(FVector::Dot(vDelta, FVector(m[1][0], m[1][1], m[1][2])), 
                         FVector::Dot(vDelta, FVector(m[2][0], m[2][1], m[2][2])), 
                         FVector::Dot(vDelta, FVector(m[0][0], m[0][1], m[0][2])));
    if (vTransformed.z < 1.0f) vTransformed.z = 1.0f;
    float screenCenterX = (CanvasSize.x / 2.0f);
    float screenCenterY = (CanvasSize.y / 2.0f);
    return FVector2D((screenCenterX + vTransformed.x * (screenCenterX / tanf(camViewInfo.FOV * (M_PI / 360.0f))) / vTransformed.z),
                     (screenCenterY - vTransformed.y * (screenCenterX / tanf(camViewInfo.FOV * (M_PI / 360.0f))) / vTransformed.z));
}

#pragma mark - جلب بيانات اللعبة
static long GetWorldPtr() {
    const auto fn = reinterpret_cast<long(__fastcall*)(long*)>(GetRealOffset(kUWorld));
    long world = 0;
    if (fn) fn(&world);
    return world;
}

static string GetPlayerName(long player) {
    string n = "";
    long PlayerNamePtr = Read<long>(player + I64("0x8f0")); 
    if (IsValidAddress(PlayerNamePtr)) {
        UTF8 name[32] = "";
        UTF16 buf16[16] = {0};
        Read_data(PlayerNamePtr, 28, buf16);
        Utf16_To_Utf8(buf16, name, 28, strictConversion);
        n = string((const char *)name);
    }
    return n;
}

static FVector GetRelativeLocation(long actor) {
    long root = Read<long>(actor + I64("0x1C8"));
    return Read<FVector>(root + I64("0x1C0"));
}

static bool GetLineOfSightTo(long player, FVector BonePoint) {
    if (PlayerController <= 0) return false;
    return true; 
}

// نهاية الملف - تأكد من وجود هذا القوس
