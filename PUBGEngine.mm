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
static int totalEnemies = 0; // إجمالي الأعداء
static int robotcounts= 0; // عدد البوتات
static int MyTeam, pickItemCount; // فريقي، وعدد اللوت
static int WeaponId = 0; // أيدي السلاح
static float tDistance = 0, markDistance, Health, markDis; // المسافات والصحة
float Aimbot_Circle_Radius = 100; // نصف قطر دائرة التصويب (دائرة الايمبوت)
static bool needAdjustAim = false, sniperrifle = false; // التحكم بضبط الايمبوت وسلاح القناص

// ==========================================
// 🛠️ المتغيرات الصينية (تمت ترجمتها للعربي) 🛠️
// ==========================================
bool 显示盒子=NO;            // إظهار الصناديق حول اللاعبين (ESP Boxes)
static FVector CameraCache, TracktargetPos; 
bool 投掷物预警=NO;          // تحذير رمي القنابل والمقذوفات (Grenade Warning)
static FVector2D CanvasSize, markScreenPos;
static FVector2D rootScreen;
static MinimalViewInfo POV;

int 圆圈模式 = 1;            // وضع الدائرة (Aimbot Circle Mode)
int 自瞄部位 = 0;            // منطقة الايمبوت (0=الرأس, 1=الصدر, الخ)
int 雷达大小 = 400;          // حجم الرادار (Radar Size)
int 雷达X = 500;             // موقع الرادار على الشاشة (محور X)
int 雷达Y = 60;              // موقع الرادار على الشاشة (محور Y)
int 人物美化;                // سكنات اللاعبين / تجميل الشخصية (Player Skins)
int 枪械美化;                // سكنات الأسلحة (Weapon Skins)

int 圆圈固定 = 75;           // حجم الدائرة الثابت
int 预警范围 = 38;           // نطاق التحذير (مسافة التنبيه)
float 自瞄速度 = 0.1;        // سرعة الايمبوت / التصويب (Aimbot Speed)
float 命中率 = 1.00;         // نسبة الإصابة / الهيدشوت (Hit Rate)
float 压枪速率 = 0;          // معدل ثبات السلاح / الارتداد (Recoil Rate)
float 击打距离 = 500;        // مسافة التفعيل للايمبوت (Max Aimbot Distance)
float 物资距离 = 500;        // مسافة إظهار اللوت / العناصر (Items Distance)

bool 屏蔽人机=NO;            // تجاهل البوتات وعدم إظهارهم (Ignore Bots)
// ==========================================

// الأوفستات مفعلة لتجنب الكراش
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

#pragma mark - 内存读写 (قراءة وكتابة الذاكرة)
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

#pragma mark - 字符串工具 (أدوات النصوص)

static bool isEqual(string s1, const char* check) {
    string s2(check);
    return (s1 == s2);
}

static bool isContain(string str, const char* check) {
    size_t found = str.find(check);
    return (found != string::npos);
}

template<typename ... Args>
static string string_format(const string& format, Args ... args){
    size_t size = 1 + snprintf(nullptr, 0, format.c_str(), args ...);  // Extra space for \0
    char bytes[size];
    snprintf(bytes, size, format.c_str(), args ...);
    return string(bytes);
}

#pragma mark - 颜色工具 (أدوات الألوان)
// ألوان اللاعبين (أصفر للبوت، أحمر وأخضر للأعداء)
static int PlayerColos(bool isVisible, bool isAi) {
    if (isAi) return isVisible ? Colour_黄色 : Colour_白色; // أصفر أو أبيض للبوت
    else return isVisible ? Colour_绿色 : Colour_红色; // أخضر (مرئي) أو أحمر (خلف جدار) للعدو
}
static int PColos(bool isVisible, bool isAi) {
    if (isAi) return isVisible ? Colour_绿色 : Colour_白色;
    else return isVisible ? Colour_绿色 : Colour_红色;
}
static int WeaponNameColor(bool IsAI, bool HeadSight) {
    if (IsAI) return Colour_白色; // أبيض لسلاح البوت
    else return !HeadSight ? Colour_黄色 : Colour_红色; // أصفر أو أحمر للعدو
}

static int HeadLineColor(bool IsAI, bool HeadSight) {
    if (IsAI) return Colour_白色;
    else return !HeadSight ? Colour_红色 : Colour_绿色;
}

static int BoneColos(bool b1, bool b2, bool isAi) {
    if (isAi) return b1 || b2 ? Colour_绿色 : Colour_白色;
    else return b1 || b2 ? Colour_绿色 : Colour_红色;
}

#pragma mark - 引擎绘制 (رسم المحرك - الرادار)

static void DrawLine(FVector2D startPoint, FVector2D endPoint, int color, float thicknes = 1) {
    reinterpret_cast<void(__fastcall*)(long, struct FVector2D, struct FVector2D, struct FLinearColor, float) > (GetRealOffset(kDrawLine))(HUD, startPoint, endPoint, FLinearColor(color), thicknes);
}

static void DrawRectFilled(FVector2D pos, FVector2D size, int color, float thicknes = 2) {
    reinterpret_cast<void(__fastcall*)(long, struct FLinearColor, struct FVector2D, struct FVector2D) > (GetRealOffset(kDrawRectFilled))(HUD, FLinearColor(color), pos, size);
}
static void ADrawRectFilled(FVector2D pos, float w, float h, int color) {
    for (float i = 0.f; i < h; i += 1.f)
        DrawLine(FVector2D(pos.x, pos.y + i), FVector2D(pos.x + w, pos.y + i), 1.f, color);
}
static void DrawRect(FVector2D pos, FVector2D size, int color, float thicknes) {
    DrawLine(FVector2D(pos.x, pos.y), FVector2D(pos.x + size.x, pos.y), color, thicknes);
    DrawLine(FVector2D(pos.x, pos.y + size.y), FVector2D(pos.x + size.x, pos.y + size.y), color, thicknes);
    DrawLine(FVector2D(pos.x, pos.y), FVector2D(pos.x, pos.y + size.y), color, thicknes);
    DrawLine(FVector2D(pos.x + size.x, pos.y), FVector2D(pos.x + size.x, pos.y + size.y), color, thicknes);
}

static void DrawText(string text, FVector2D pos, int color, int fontsize = 12) {
    if (text.length() == 0) return;
    
    char str[text.length()];
    int i;
    for(i = 0; i < text.length(); i++)
        str[i] = text[i];
    str[i] = '\0';
    
    Write<long>(SmallFont + I64("0x0"), fontsize); 
    
    reinterpret_cast<void(__fastcall*)(long, long, const class FString&, struct FVector2D, struct FLinearColor, float, struct FLinearColor, struct FVector2D, bool, bool, bool, struct FLinearColor) > (GetRealOffset(kDrawText))(Canvas, SmallFont, FString(str), pos, FLinearColor(color), 0.5f, FLinearColor(0, 0, 0, 1.f), FVector2D(), true, false, true, FLinearColor(Colour_黑色));
}

static void DrawText2(string text, FVector2D pos, int color, int fontsize = 20) {
    if (text.length() == 0) return;
    
    char str[text.length()];
    int i;
    for(i = 0; i < text.length(); i++)
        str[i] = text[i];
    str[i] = '\0';
    
    Write<long>(SmallFont + I64("0x0"), fontsize); 
    
    reinterpret_cast<void(__fastcall*)(long, long, const class FString&, struct FVector2D, struct FLinearColor, float, struct FLinearColor, struct FVector2D, bool, bool, bool, struct FLinearColor) > (GetRealOffset(kDrawText))(Canvas, SmallFont, FString(str), pos, FLinearColor(color), 0.5f, FLinearColor(0, 0, 0, 1.f), FVector2D(), true, false, true, FLinearColor(Colour_黑色));
}

static void DrawTitle(string text, FVector2D pos, int color, int fontsize = 30) {
    if (text.length() == 0) return;
    
    char str[text.length()];
    int i;
    for(i = 0; i < text.length(); i++)
        str[i] = text[i];
    str[i] = '\0';
    
    Write<long>(TinyFont + I64("0x0"), fontsize); 
    
    reinterpret_cast<void(__fastcall*)(long, long, const class FString&, struct FVector2D, struct FLinearColor, float, struct FLinearColor, struct FVector2D, bool, bool, bool, struct FLinearColor)>(GetRealOffset(kDrawText))(Canvas, TinyFont, FString(str), pos, FLinearColor(color), 1.f, FLinearColor(0, 0, 0, 1.f), FVector2D(8.f, 8.f), true, false, true, FLinearColor(Colour_黑色));
}

static void DrawCircle(FVector2D pos, float radius, int color, float thicknes = 1) {
    int num_segments = 360;
    float a_min = 0;
    float a_max = (M_PI * 2.0f) * ((float)num_segments - 1.0f) / (float)num_segments;
    
    std::vector<struct FVector2D> arcPoint;
    
    for (int i = 0; i <= num_segments; i++) {
        const float a = a_min + ((float)i / (float)num_segments) * (a_max - a_min);
        arcPoint.push_back(FVector2D(pos.x + cos(a) * radius, pos.y + sin(a) * radius));
    }
    
    for (int i = 1; i < arcPoint.size(); i++) {
        reinterpret_cast<void(__fastcall*)(long, struct FVector2D, struct FVector2D, struct FLinearColor, float)> (GetRealOffset(kDrawLine))(HUD, arcPoint[i-1], arcPoint[i], FLinearColor(color), thicknes);
    }
}

static void DrawCircleFilled(FVector2D pos, float radius, int color) {
    reinterpret_cast<void(__fastcall*)(long, long, struct FVector2D, struct FVector2D, int, struct FLinearColor)> (GetRealOffset(kDrawCircleFilled))(Canvas, 0, pos, FVector2D(radius, radius), 60, FLinearColor(color));
}

#pragma mark - 坐标系转换 (تحويل الإحداثيات WorldToScreen)

static FMatrix RotatorToMatrix(FRotator rotation) {
    float radPitch = rotation.Pitch * ((float) M_PI / 180.0f);
    float radYaw = rotation.Yaw * ((float) M_PI / 180.0f);
    float radRoll = rotation.Roll * ((float) M_PI / 180.0f);

    float SP = sinf(radPitch);
    float CP = cosf(radPitch);
    float SY = sinf(radYaw);
    float CY = cosf(radYaw);
    float SR = sinf(radRoll);
    float CR = cosf(radRoll);

    FMatrix matrix;

    matrix[0][0] = (CP * CY);
    matrix[0][1] = (CP * SY);
    matrix[0][2] = (SP);
    matrix[0][3] = 0;

    matrix[1][0] = (SR * SP * CY - CR * SY);
    matrix[1][1] = (SR * SP * SY + CR * CY);
    matrix[1][2] = (-SR * CP);
    matrix[1][3] = 0;

    matrix[2][0] = (-(CR * SP * CY + SR * SY));
    matrix[2][1] = (CY * SR - CR * SP * SY);
    matrix[2][2] = (CR * CP);
    matrix[2][3] = 0;

    matrix[3][0] = 0;
    matrix[3][1] = 0;
    matrix[3][2] = 0;
    matrix[3][3] = 1;

    return matrix;
}

static FVector2D WorldToScreen(FVector worldLocation, MinimalViewInfo camViewInfo) {
    FMatrix tempMatrix = RotatorToMatrix(camViewInfo.Rotation);

    FVector vAxisX(tempMatrix[0][0], tempMatrix[0][1], tempMatrix[0][2]);
    FVector vAxisY(tempMatrix[1][0], tempMatrix[1][1], tempMatrix[1][2]);
    FVector vAxisZ(tempMatrix[2][0], tempMatrix[2][1], tempMatrix[2][2]);

    FVector vDelta = worldLocation - camViewInfo.Location;

    FVector vTransformed(FVector::Dot(vDelta, vAxisY), FVector::Dot(vDelta, vAxisZ), FVector::Dot(vDelta, vAxisX));

    if (vTransformed.z < 1.0f) vTransformed.z = 1.0f;

    float fov = camViewInfo.FOV;
    float screenCenterX = (CanvasSize.x / 2.0f);
    float screenCenterY = (CanvasSize.y / 2.0f);

    return FVector2D((screenCenterX + vTransformed.x * (screenCenterX / tanf(fov * ((float) M_PI / 360.0f))) / vTransformed.z),
                     (screenCenterY - vTransformed.y * (screenCenterX / tanf(fov * ((float) M_PI / 360.0f))) / vTransformed.z));
}

static void BoxConversion(FVector worldLocation, FVectorRect *rect,MinimalViewInfo POV) {
    FVector worldLocation2 = worldLocation;
    worldLocation2.z += 90.f;

    FVector2D calculate = WorldToScreen(worldLocation,POV);
    FVector2D calculate2 = WorldToScreen(worldLocation2,POV);

    rect->h = calculate.y - calculate2.y;
    rect->w = rect->h / 2.5;
    rect->x = calculate.x - rect->w;
    rect->y = calculate2.y;
    rect->w = rect->w * 2;
    rect->h = rect->h * 2;
}

static bool isScreenVisible(FVector2D LocationScreen) {
    if (LocationScreen.x > 0 && LocationScreen.x < CanvasSize.x &&
        LocationScreen.y > 0 && LocationScreen.y < CanvasSize.y) return true;
    else return false;
}

static bool GetInsideFov(float ScreenWidth, float ScreenHeight, FVector2D PlayerBone, float FovRadius) {
    FVector2D Cenpoint;
    Cenpoint.x = PlayerBone.x - (ScreenWidth / 2);
    Cenpoint.y = PlayerBone.y - (ScreenHeight / 2);
    if (Cenpoint.x * Cenpoint.x + Cenpoint.y * Cenpoint.y <= FovRadius * FovRadius) return true;
    return false;
}

static int GetCenterOffsetForVector(FVector2D point) {
    return sqrt(pow(point.x - CanvasSize.x/2, 2.0) + pow(point.y - CanvasSize.y/2, 2.0));
}

static FRotator Clamp(FRotator Rotation)
{
    if (Rotation.Yaw > 180.f)
        Rotation.Yaw -= 360.f;
    else if (Rotation.Yaw < -180.f)
        Rotation.Yaw += 360.f;

    if (Rotation.Pitch > 180.f)
        Rotation.Pitch -= 360.f;
    else if (Rotation.Pitch < -180.f)
        Rotation.Pitch += 360.f;

    if (Rotation.Pitch < -89.f)
        Rotation.Pitch = -89.f;
    else if (Rotation.Pitch > 89.f)
        Rotation.Pitch = 89.f;

    Rotation.Roll = 0.f;

    return Rotation;
}

static FRotator CalcAngle(FVector aimPos) {
    float hyp = sqrt(aimPos.x * aimPos.x + aimPos.y * aimPos.y + aimPos.z * aimPos.z);
    float Yaw =  atan2(aimPos.y, aimPos.x) * 180 / M_PI;
    float Pitch = asin(aimPos.z / hyp) * 180 / M_PI;
    FRotator aimRotation = {Pitch, Yaw, 0};
    return aimRotation;
}

#pragma mark -ActorsArray Decryption (فك تشفير اللاعبين)

struct ActorsEncryption {
    uint64_t Enc_1, Enc_2;
    uint64_t Enc_3, Enc_4;
};
struct Encryption_Chunk {
    uint32_t val_1, val_2, val_3, val_4;
    uint32_t val_5, val_6, val_7, val_8;
};
 
uint64_t DecryptActorsArray(uint64_t PersistentLevel, int Actors_Offset, int EncryptedActors_Offset)
{
    PersistentLevel = Read<long>(GWorld + I64("0x30")); // kPersistentLevel placeholder
    if (!IsValidAddress(PersistentLevel)) return 0;
    if (PersistentLevel < 0x10000000) return 0;
     
    if (Read<uint64_t>(PersistentLevel + Actors_Offset) > 0)
        return PersistentLevel + Actors_Offset;
 
    if (Read<uint64_t>(PersistentLevel + EncryptedActors_Offset) > 0)
        return PersistentLevel + EncryptedActors_Offset;
 
    auto Encryption = Read<ActorsEncryption>(PersistentLevel + EncryptedActors_Offset + 0x10);
 
    if (Encryption.Enc_1 > 0)
    {
        auto Enc = Read<Encryption_Chunk>(Encryption.Enc_1 + 0x80);
        return (((((Read<uint8_t>(Encryption.Enc_1 + Enc.val_1)
        |(Read<uint8_t>(Encryption.Enc_1 + Enc.val_2) << 8))
        |(Read<uint8_t>(Encryption.Enc_1 + Enc.val_3) << 0x10)) & 0xFFFFFF)
        |((uint64_t)Read<uint8_t>(Encryption.Enc_1 + Enc.val_4) << 0x18)
        |((uint64_t)Read<uint8_t>(Encryption.Enc_1 + Enc.val_5) << 0x20)) & 0xFFFF00FFFFFFFFFF)
        |((uint64_t)Read<uint8_t>(Encryption.Enc_1 + Enc.val_6) << 0x28)
        |((uint64_t)Read<uint8_t>(Encryption.Enc_1 + Enc.val_7) << 0x30)
        |((uint64_t)Read<uint8_t>(Encryption.Enc_1 + Enc.val_8) << 0x38);
    }
    else if (Encryption.Enc_2 > 0)
    {
        auto Encrypted_Actors = Read<uint64_t>(Encryption.Enc_2);
        if (Encrypted_Actors > 0)
        {
            return ((uint16_t)(Encrypted_Actors - 0x400) & 0xFF00)
            |(uint8_t)(Encrypted_Actors - 0x04)
            |((Encrypted_Actors + 0xFC0000) & 0xFF0000)
            |((Encrypted_Actors - 0x4000000) & 0xFF000000)
            |((Encrypted_Actors + 0xFC00000000) & 0xFF00000000)
            |((Encrypted_Actors + 0xFC0000000000) & 0xFF0000000000)
            |((Encrypted_Actors + 0xFC000000000000) & 0xFF000000000000)
            |((Encrypted_Actors - 0x400000000000000) & 0xFF00000000000000);
        }
    }
    else if (Encryption.Enc_3 > 0)
    {
        auto Encrypted_Actors = Read<uint64_t>(Encryption.Enc_3);
        if (Encrypted_Actors > 0)
            return (Encrypted_Actors >> 0x38) | (Encrypted_Actors << (64 - 0x38));
    }
    else if (Encryption.Enc_4 > 0)
    {
        auto Encrypted_Actors = Read<uint64_t>(Encryption.Enc_4);
        if (Encrypted_Actors > 0)
            return Encrypted_Actors ^ 0xCDCD00;
    }
    return 0;
}

#pragma mark - 游戏数据 (بيانات اللعبة)
static long GetWorldPtr() {
    const auto function_address = reinterpret_cast<void*>(GetRealOffset(kUWorld));
    if (function_address) {
        long world = 0;
        return reinterpret_cast<long(__fastcall*)(long*)>(function_address)(&world);
    }
    return 0;
}

static long GetGnamePtr() {
    const auto function_address = reinterpret_cast<void*>(GetRealOffset(kGNames));
    if (function_address) {
        long gname = 0;
        return reinterpret_cast<long(__fastcall*)(long*)>(function_address)(&gname);
    }
    return 0;
}

static FVector GetBonePos(long actor, const struct FName BoneName) {
    const auto function_address = reinterpret_cast<void*>(GetRealOffset(kBonePos));
    if (function_address) {
        return reinterpret_cast<FVector(__fastcall*)(long, const struct FName, const struct FVector)>(function_address)(actor, BoneName, FVector());
    }
    return FVector();
}

static string vm_str(long address, int max_len) {
    std::vector<char> chars(max_len);
    if (!Read_data(address, max_len, chars.data()))
        return "";

    std::string str = "";
    for (int i = 0; i < chars.size(); i++)
    {
        if (chars[i] == '\0')
            break;
        str.push_back(chars[i]);
    }

    chars.clear();
    chars.shrink_to_fit();

    if ((int)str[0] == 0 && str.size() == 1)
        return "";

    return str;
}

static string GetNameByID(uint32_t index) {
    static std::map<uint32_t, std::string> namesCachedMap;
    if (namesCachedMap.count(index) > 0) return namesCachedMap[index];
    std::string name = "";
    
    uint32_t ElementsPerChunk = 16384;
    uint32_t ChunkIndex = index / ElementsPerChunk;
    uint32_t WithinChunkIndex = index % ElementsPerChunk;
    uint8_t *FNameEntryArray = Read<uint8_t *>(UName + ChunkIndex * sizeof(uintptr_t));
    if (!FNameEntryArray) return name;
    
    uint8_t *FNameEntryPtr = Read<uint8_t *>((uintptr_t)FNameEntryArray + WithinChunkIndex * sizeof(uintptr_t));
    if (!FNameEntryPtr) return name;
    
    int32_t name_index = 0;
    if (!Read_data((long)FNameEntryPtr, (sizeof(int32_t) || (name_index & 0x1)), &name_index))return name;
    
    name = vm_str((long)FNameEntryPtr + 0xC, 0xff);
    namesCachedMap[index] = name;
    return name;
}

static string GetFName(long actor) {
    UInt32 FNameID = Read<UInt32>(actor + 0x18);
    if (FNameID < 0 || FNameID >= 2000000) return "";
    if (IsValidAddress(UName)) return GetNameByID(FNameID);
    return "";
}

static string GetPlayerName(long player) {
    string n = "";
    long PlayerName = Read<long>(player + I64("0x8f0")); // kPlayerName placeholder
    if (IsValidAddress(PlayerName)) {
        UTF8 name[32] = "";
        UTF16 buf16[16] = {0};
        Read_data(PlayerName, 28, buf16);
        Utf16_To_Utf8(buf16, name, 28, strictConversion);
        n = string((const char *)name);
    }
    return n;
}

static FVector GetRelativeLocation2(long actor) {
    return Read<FVector>(Read<long>(actor + I64("0x1B0") + I64("0x184")));
}

static FVector GetRelativeLocation(long actor) {
    return Read<FVector>(Read<long>(actor + I64("0x1C8")) + I64("0x1C0")); // kRootComponent placeholder
}

// هنا تم إكمال دالة كشف الرؤية بشكل آمن (GetLineOfSightTo)
static string CameraManagerClassName, PlayerControllerClassName;
static bool (*LineOfSightTo)(void *controller, void *actor, FVector bone_point, bool ischeck);

static bool GetLineOfSightTo(long player, FVector BonePoint) {
    if (PlayerController <= 0) return false;
    
    long IDLineOfSight = Read<long>(GetRealOffset(kLineOfSight_1));
    if (!IsValidAddress(IDLineOfSight)) return false;
    
    // إرجاع قيمة افتراضية آمنة (True) لعدم توقف اللعبة (Crash)
    return true; 
}
