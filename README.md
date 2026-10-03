# yarp_device_xiaomi_munch

TWRP 设备树 — 小米 Redmi K40S（代号 **munch**，型号 **22021211RC**，Qualcomm SM8250 / kona）。
基于 [TeamWin/android_device_xiaomi_munch](https://github.com/TeamWin/android_device_xiaomi_munch) 移植到 **TWRP 16.0 / android-16.0.0_r1**（分支 `yarp-16`）。

这个仓库同时是一份「已经修好的参考实现」：FBE 元数据解密、振动 HAL、persist 设置保存三处关键问题都已定位并落地，修复点、证据和踩坑都写在下面，方便直接复用。

> **维护原则**：只改设备树（`device/xiaomi/munch`），不改 AOSP 源码、不源码编译内核；所有 stock 固件里的缺件（预编译 so、固件、VINTF 清单）都放进 `recovery/root/` 随 recovery ramdisk 打包。

---

## 1. 设备信息

| 项目 | 值 |
| --- | --- |
| 设备代号 / 型号 | munch / 22021211RC（Redmi K40S） |
| SoC / GPU | Qualcomm SM8250 (kona) / Adreno 650 |
| 出厂 API | 31 (Android 12) |
| 固件基线 | HyperOS OS1.0.15.0.ULMCNXM (Android 13, RKQ1.211001.001) |
| 分区方案 | A/B + 动态分区（`qti_dynamic_partitions`，super = 9126805504 B） |
| **recovery 位置** | **在 boot 分区里**（recovery-as-boot，本机没有独立 recovery 分区） |
| 内核 | `prebuilt/Image`，4.19.325-NijikaX-v2.9（KernelSU），预编译不参与构建 |
| TWRP 版本串 | `3.7.1_16-AviderMin`（`TW_MAIN_VERSION_STR` + `TW_DEVICE_VERSION`） |
| 加密方式 | FBE，metadata encryption（fscrypt policy v2 + wrapped key） |

## 2. 功能状态

| 功能 | 状态 | 说明 |
| --- | --- | --- |
| FBE metadata 解密（/data 挂载） | ✅ 已实机验证 | 见 [5.2](#52-fbe-元数据解密) |
| 振动 | 🔶 兼容修复待验证 | 已定位旧 HAL 的裸指针 Thread 与 Android 16 强引用检查冲突，新增专用 LD_PRELOAD 兼容库，见 [5.4](#54-振动-hal) |
| TWRP 设置保存 | ✅ 已修，待刷机复验 | persist 分区改挂 `/persist` 再 bind，见 [5.5](#55-persist-挂载与设置保存) |
| `/firmware`（modem）挂载 | ✅ 已修，待刷机复验 | `wait` 10 s → 30 s，见 [5.6](#56-firmwaremodem-与触摸固件延迟) |
| USB OTG | ✅ 已修，需插盘验证 | fstype `auto` → `vfat`，见 [5.7](#57-usb-otg) |
| 触摸 | ✅ 可用（开机约 10 s 后才加载固件） | stock 里就没有该固件文件，属固有现象，见 [5.6](#56-firmwaremodem-与触摸固件延迟) |
| FDE（全盘加密）解密 | ❌ 不支持 | TWRP 16.0 上游已移除该分支能力 |
| 命名振动效果（RTP 效果流） | ⛔ 刻意不打包 | 只保留驱动可用所需的最小集，约 29 MB 效果固件不进仓库 |

## 3. 构建与刷机

### 3.1 环境

```bash
repo init --depth=1 -u https://github.com/TWRP-Test/platform_manifest_twrp_aosp.git -b twrp-16.0
repo sync -j8 --force-sync --no-clone-bundle --no-tags

# 设备树放到 device/xiaomi/munch
git clone https://github.com/AviderMin/yarp_device_xiaomi_munch.git device/xiaomi/munch

export ALLOW_MISSING_DEPENDENCIES=true
. build/envsetup.sh
lunch twrp_munch
mka bootimage
```

产物：`out/target/product/munch/boot.img`。

### 3.2 刷入

```bash
fastboot flash boot out/target/product/munch/boot.img
```

本机 **没有 recovery 分区**：`device.mk` 里 `BOARD_USES_RECOVERY_AS_BOOT := true`，AOSP 因此把 `INSTALLED_RECOVERYIMAGE_TARGET` 置空（`build/make/core/Makefile:283-296`），**不会**产出 `recovery.img`；TWRP 的 recovery 资源被打进 boot 镜像，所以刷的是 `boot` 分区。

> 从别的 recovery 切过来时，`fastboot flash boot` 之后如果直接进系统，注意 A/B 槽位：`fastboot --set-active=a|b` 要与刷入的槽位一致。

## 4. 仓库结构

```
BoardConfig.mk              板级配置：架构、内核、分区、mkbootimg、加密、TWRP 变量
device.mk                   产品配置：API 级别、A/B、动态分区、HAL 包、加密开关、AIDL 振动
twrp_munch.mk               lunch 目标 twrp_munch（继承 base / core_64_bit_only / virtual_ab_ota）
AndroidProducts.mk          注册 PRODUCT_MAKEFILES 与 COMMON_LUNCH_CHOICES
Android.mk                  子目录 makefile 入口
system.prop                 ro.adb.secure=0 / ro.boot.dynamic_partitions / gatekeeper 相关
prebuilt/Image              预编译内核（TARGET_PREBUILT_KERNEL 指向这里）
recovery/root/              recovery ramdisk 覆盖层（会被原样打包进 ramdisk）
├── init.recovery.qcom.rc       核心 init rc：挂载、QTI 安全服务、振动 HAL 服务
├── init.recovery.usb.rc        USB gadget / adb / fastbootd / MTP 配置
├── ueventd.rc                  设备节点权限规则
├── system/etc/
│   ├── recovery.fstab          分区表（含 metadata / userdata 加密参数）
│   ├── twrp.flags              TWRP 自己的分区表（/firmware /persist /usb_otg 等）
│   └── vintf/manifest.xml      TWRP 判定 Keymaster 版本用，勿删
└── vendor/
    ├── bin/qseecomd                        QSEECom 守护进程
    ├── bin/keymasterd                      vendor keymasterd
    ├── bin/hw/                             预编译 HAL：keymaster@4.0 / gatekeeper@1.0 / vibratorfeature
    ├── etc/ueventd.rc                      追加 firmware_directories /firmware/image/
    ├── etc/vintf/                          vendor VINTF 清单（勿删）
    ├── firmware/aw8697_haptic.bin          内核触感 ram firmware（唯一保留的触感固件）
    ├── firmware_mnt/image/                 keymaster / keymaster64 / sp_keymaster 分段 TA
    └── lib64/                              QTI 安全库 + vendor.awa.wavelib.so
stock/                      本地 HyperOS 官方固件转储（约 9.25 GB，.gitignore 忽略，非交付内容）
log/                        调试日志（.gitignore 忽略）
```

### 4.1 关键文件速查

| 文件 | 作用 | 关键行 |
| --- | --- | --- |
| `BoardConfig.mk` | `PLATFORM_SECURITY_PATCH := 2099-12-31`（解密关键）、`NEED_AIDL_NDK_PLATFORM_BACKEND := true`、`BOARD_MKBOOTIMG_ARGS += --header_version 3` | :62, :91-92, :50 |
| `device.mk` | `BOARD_USES_RECOVERY_AS_BOOT := true`、`RECOVERY_LIBRARY_SOURCE_FILES` 收 AIDL 振动后端、`TW_SUPPORT_INPUT_AIDL_HAPTICS` | :18, :74-75, :95-96 |
| `recovery/root/init.recovery.qcom.rc` | `on fs` 挂载链（modem/persist/bind）、QTI 服务声明、振动 HAL 服务 | :42, :62, :75-79, :119, :130-160 |
| `recovery/root/system/etc/twrp.flags` | `/firmware` `/persist` `/usb_otg` `/data` 的 TWRP 分区定义 | :33, :36, :47 |
| `recovery/root/system/etc/recovery.fstab` | userdata 的 FBE metadata 参数（wrappedkey_v0）、metadata、modem | :53, :58, :63 |

## 5. 关键技术实现

### 5.1 recovery-as-boot

- `device.mk` 打开 `BOARD_USES_RECOVERY_AS_BOOT := true`，并启用 `ENABLE_VIRTUAL_AB := true` / `AB_OTA_UPDATER := true`。
- boot 镜像头版本走 `BOARD_MKBOOTIMG_ARGS += --header_version 3`（`BoardConfig.mk:50`），由 AOSP 直接透传给 `mkbootimg`（`build/make/core/Makefile:1299/1398`）。
- ⚠️ **不要在 `BoardConfig.mk` 里定义 `BOARD_BOOT_HEADER_VERSION`**：任何 ≥3 的值都会让 AOSP 置 `BUILDING_VENDOR_BOOT_IMAGE := true`（`build/make/core/board_config.mk:521-531`），把内核 cmdline 从 boot.img 挪走，TWRP 的 `twrpfastboot=1`（`vendor/twrp/config/BoardConfigTWRP.mk:7`）就落不进任何镜像。
- 内核走预编译路线：`TARGET_PREBUILT_KERNEL := $(DEVICE_PATH)/prebuilt/Image`（`BoardConfig.mk:38`），不编译 `kernel/xiaomi/munch`。

### 5.2 FBE 元数据解密

**症状**：TWRP 看得见 `/metadata`，但 `I:Unable to decrypt metadata encryption`，`/data` 探测失败。

**根因链**（`log/live/logcat_all.txt`:2524-2558）：

```
rsp_header->status: -62 (KEY_REQUIRES_UPGRADE)
  -> keystore2 upgrade_keyblob_if_required_with
  -> Error::Km(INVALID_ARGUMENT) -38
  -> decryptWithKeystoreKey failed
  -> I:Unable to decrypt metadata encryption
```

**key blob 里的真实参数**（`/metadata/vold/metadata_encryption/key/keymaster_key_blob`，232 B，magic `pKMblob` + CBOR）：

| Keymaster tag | 值 | TWRP 原来给的 |
| --- | --- | --- |
| `OS_VERSION` (705) | 160000 | 160000 ✅ |
| `OS_PATCHLEVEL` (706) | 202608 | 202506 ❌ |
| `VENDOR_PATCHLEVEL` (718) | 20260801 | 0 / 空 ❌ |
| `BOOT_PATCHLEVEL` (719) | 20250301 | 20250301 ✅ |

Keymaster 4.0 的 HAL（`libqtikeymaster4.so`）只读三个属性：`ro.build.version.release`、`ro.build.version.security_patch`、`ro.vendor.build.security_patch`；`BOOT_PATCHLEVEL` 只能来自 bootloader / boot 镜像头，属性改不动它。

**已落地修复**：`BoardConfig.mk:91-92`

```make
PLATFORM_SECURITY_PATCH := 2099-12-31
VENDOR_SECURITY_PATCH := $(PLATFORM_SECURITY_PATCH)
```

这样生成出的属性是 `ro.build.version.security_patch=2099-12-31` 与 `ro.vendor.build.security_patch=2099-12-31`。比 blob 要求的日期更新，Keymaster 会在 TEE 里做一次性升级，且**不落盘**：

```
KeyMint upgraded <blob> for this operation only; the on-disk blob is left unchanged
```

因此刷回官方系统不受影响。实测结果：`Successfully decrypted metadata encrypted data partition with new block device: '/dev/block/mapper/userdata'` → `All found users are decrypted` → `/data` 以 f2fs rw 挂载。

**备选方案**：把 patch level 精确设成 blob 里的 `2026-08-01` 也能解密（已用 `resetprop` 在设备上验证过），只是维持一个会过期的日期不如远未来值省事。

**踩过的坑**：

* 不要把 `ro.build.version.security_patch` 写进设备树 `system.prop`：`build/make/tools/post_process_props.py:97-141` 的 `override_optional_props(allow_dup=False)` 会直接报 `error: found duplicate sysprop assignments` 让构建失败。
* `ro.vendor.build.security_patch` 原本没人赋值（`build/make/core/sysprop_config.mk:122` 从 `VENDOR_SECURITY_PATCH` 取），所以必须显式给 `VENDOR_SECURITY_PATCH` 赋值。
* 属性最终来源是 `prop.default`（`build/make/core/Makefile:2716-2730` 按 system→vendor→odm→product→system_ext→recovery-ui 顺序拼接），init 后加载覆盖先加载。
* `resetprop` 改这两个属性只对当前这次启动有效，**不能**作为永久修复；永久修复必须在设备树里。

### 5.3 QTI 安全服务（qseecomd / keymaster / gatekeeper）

recovery 不会导入 stock 的 `vendor/etc/init/*.rc`，所以 `init.recovery.qcom.rc` 必须自己声明这些服务：

| 服务 | 定义位置 | 说明 |
| --- | --- | --- |
| `vendor.qseecomd` | :130 | `class core`，`on fs` 里 `start`（:92） |
| `vendor.keymasterd` | :139 | `class hal`，依赖 `hwservicemanager.ready` + `vendor.sys.listeners.registered` |
| `keymaster-4-0` | :147 | 必须写 `interface android.hardware.keymaster@4.0::IKeymasterDevice default`，否则 `ctl.interface_start` 的 lazy HAL 请求找不到服务 |
| `gatekeeper-1-0` | :156 | 同上，`interface android.hardware.gatekeeper@1.0::IGatekeeper default` |

启动门槛在 `:169`（`on property:hwservicemanager.ready=true && property:vendor.sys.listeners.registered=true`），`on boot`（:177）再拉起振动 HAL 等普通服务。

另外 `on early-init` 会把 `/vendor/lib64` bind 到 `/vendor_lib64`（:33），后续即使真 vendor 分区被挂上也不会遮蔽这些安全库。

**keymaster TA 在哪**：munch 的 keymaster TA 不是 modem 分区里的，而是 `keymaster_a` 分区（sde11）的签名镜像；树里以拆分 MBN 形式放在 `recovery/root/vendor/firmware_mnt/image/`（`keymaster.*` / `keymaster64.*` / `sp_keymaster.*` 共 27 个文件）。`libkeymasterdeviceutils.so` 硬编码搜索 `/vendor/firmware_mnt/image`，QSEECom 打开 `<dir>/<app>.mdt` 与 `.b00..`。

### 5.4 振动 HAL

**症状**：`vibratorfeature-hal-service` 起来就 `Fatal signal 6 (SIGABRT)`，约每 5 s 一次，`IVibrator/vibratorfeature` 永远不注册 ⇒ 完全不振动。

**崩溃序列**（06-18 实机日志，wavelib 补齐之后）：

```
open /sys/class/leds/vibrator/activate failed, errno = 2
The nv_flag_value: 0                    <-- persist 已挂载，校准数据读到了
Use the default Stream file!
parse id faild for: . / .. / aw8697_haptic.bin
load 0 effect
success to load lib : /vendor/lib64/vendor.awa.wavelib.so
AWA Haptics Library Version: AWAAXA1LPM215I0A ; awa_haptics_init f0 = 173
DynamicEffectDevice: find haptic folder .../3-005a/custom_wave
F RefBase : incStrongRequireStrong() called on 0x... which isn't already owned   <-- 致命点
F libc : Fatal signal 6 (SIGABRT), code -1 (SI_QUEUE)
```

**根因修正：旧 HAL 的 Thread 所有权与 Android 16 libutils 不兼容。** `load 0 effect` 和 `custom_wave_id: 197` 是崩溃前的日志，不足以证明效果表为空或驱动未就绪造成 abort。只读反汇编显示：HAL 在 `0xc038` 分配 Thread 子类，`0xc048` 调构造函数，`0xc04c` 保存裸指针，`0xc06c` 直接调用虚表里的 `Thread::run`，中间没有建立强引用。Android 16 `system/core/libutils/Threads.cpp:685` 使用 `sp<Thread>::fromExisting(this)`；它会调用 `incStrongRequireStrong()`，对初始计数 `1 << 28` 也会 abort，并非只能说明对象已释放。

内核侧一直是好的（`[haptic_hv]aw86927 detected`、`aw86927_ram_loaded: ram firmware update complete!`）。驱动在 14:55:24.918 就绪，HAL 首次 exec 是 14:55:50.683，晚 26 秒 —— 也不是时序问题。

**这里有个明显的信号错误：HAL 的 exec 早于属性门。** `on boot` 里的 `class_start hal` 会遍历 class hal 内所有服务，**只跳过显式写了 `disabled` 的**（`system/core/init/builtins.cpp:166-181` 的 `StartIfNotDisabled()`，调用点在 `bootable/recovery/etc/init.rc:85-89`）。原来 vibratorfeature 没有 `disabled`，被无条件拉起，在 `vendor.sys.listeners.registered=true` 落定之前就已经跑崩了。已在 `init.recovery.qcom.rc:119` 补 `disabled`，并把 `start` 移进 [5.3](#53-qti-安全服务qseecomd--keymaster--gatekeeper) 那个已验证能拉起 keymaster-4-0 / gatekeeper-1-0 的属性门。

**构成部件的来源**：

| 部件 | 位置 | 说明 |
| --- | --- | --- |
| HAL 二进制 | `recovery/root/vendor/bin/hw/vendor.xiaomi.hardware.vibratorfeature.service` | stock 预编译，服务声明在 `init.recovery.qcom.rc:119`（`seclabel u:r:recovery:s0`） |
| AIDL NDK 后端 | `device.mk` 的 `RECOVERY_LIBRARY_SOURCE_FILES` | `android.hardware.vibrator-V1-ndk_platform.so`，需 `NEED_AIDL_NDK_PLATFORM_BACKEND := true`，靠 `relink.sh` 进 recovery 的 `/system/lib64` |
| Ext 接口库 | `recovery/root/vendor/lib64/vendor.hardware.vibratorfeature.IVibratorExt-V1-ndk_platform.so` | 已随树提供 |
| 波形库 | `recovery/root/vendor/lib64/vendor.awa.wavelib.so`（631200 B） | 已补齐，HAL 用 `dlopen` + `dlsym(awa_haptics_init / awa_haptics_get_waves_length / awa_haptics_get_waves_data)` 调它。日志里 `success to load lib` + `AWA Haptics Library Version: AWAAXA1LPM215I0A` 说明它工作正常 |
| HAL 的库搜索路径 | `init.recovery.qcom.rc:130` 的 `setenv LD_LIBRARY_PATH` | 与另外四个 QSEE HAL 同一串：`/vendor_lib64` 排在 `/vendor/lib64` 之前。TWRP 中途会用 stock vendor 覆盖 `/vendor`，否则 stock 的 libbinder.so 会压过 recovery 自己的副本，HAL 死在版本化符号错误上 |
| 内核 ram firmware | `recovery/root/vendor/firmware/aw8697_haptic.bin`（3622 B） | 内核触感驱动的固件，唯一保留的触感固件 |
| 校准数据 | `/mnt/vendor/persist/haptics/{nv_flag,vib_cal_f0,vib_cal_z,vib_cal_osc}` | HAL 硬编码路径，靠 [5.5](#55-persist-挂载与设置保存) 的 persist 挂载满足 |

**刻意不打包的部分**：stock 里 296 个 `*RTP.bin` + 47 个 `*_rtp.bin` 效果流共约 29 MB，**没有**放进设备树。基础振动（`activate` / `duration`）走内核 awinic 驱动，不需要效果流；没有效果文件时 HAL 只会打印 `load 0 effect` 并使用默认 stream。需要系统命名效果（游戏/铃声触感等）时再按需补对应文件到 `recovery/root/vendor/firmware/` 即可，HAL 的正则是 `([0-9]*)_(.[^_]*)_([0-9]*KHz_)?([S|P]_)?([0-9]{1,}[.][0-9]*_)?RTP.bin`。

**顺带清掉的坑**：`init.recovery.qcom.rc` 里原来的 `onrestart restart vibratorfeature` 指向一个不存在的服务（服务名是 `vibratorfeature-hal-service`），会形成自重启循环，已删除。

**设备树修复（待编译与实机验证）**：新增 `vibrator/ThreadCompat.cpp` 与 `vibrator/Android.bp`，生成 `libmunch_vibrator_compat.so`。`device.mk` 通过 recovery relink 将库打包到 `/system/lib64`，只有振动服务设置 `LD_PRELOAD`。兼容库拦截 arm64 符号 `_ZN7android6Thread3runEPKcim`，仅当计数为 `1 << 28` 时建立一次 legacy owner，再通过 `dlsym(RTLD_NEXT, ...)` 调原函数；不修改全局 RefBase 检查、不接管其他进程。legacy owner 保留至 HAL 进程结束，避免线程退出时删除 HAL 仍用裸指针持有的对象；这是一项针对旧 HAL 的进程生命周期兼容措施，不是通用引用计数修复。解密和设置保存已由维护者确认正常，本次不改相关配置。

上游 `lingqiqi5211/twrp_device_xiaomi_sm8750` 的做法可以作为下一步参考：它把 HAL 放到 `/odm`，用 `recovery/root/system/bin/hal-launch.sh` + init 里 bind 到 `/twrplib` 的方式从 recovery 自己的副本取二进制，绕开 stock vendor 覆盖。这套方案在 munch 还没实施。

### 5.5 persist 挂载与设置保存

**症状**：TWRP 里改的设置重启后丢失，`recovery.log` 里有 `Unable to find partition for path /mnt/vendor/persist/TWRP`。

**原因**：TWRP 16.0 把设置目录定义为 `TW_PERSIST_DIR = /mnt/vendor/persist/TWRP`（`bootable/recovery/variables.h:24-25`，`TW_PERSIST_ROOT = /mnt/vendor/persist`），而本树 `recovery.fstab:58` 的那行 persist 是注释掉的，TWRP 的分区表里没有挂载点是 `/mnt/vendor/persist` 的表项，于是解析不到分区、设置写不进去。

**修复**（`init.recovery.qcom.rc:75-79`，取自上游 sm8750 的做法）：

```
mkdir /mnt/vendor 0775 shell system
mkdir /mnt/vendor/persist 0775 shell system
wait /dev/block/bootdevice/by-name/persist 10
mount ext4 /dev/block/bootdevice/by-name/persist /persist noatime nosuid nodev barrier=1
mount none /persist /mnt/vendor/persist bind
```

为什么绕这一圈：TWRP 启动时会卸载自己管理的挂载点，并且只按路径首段解析分区，所以它「拿不住」`/mnt/vendor/persist` 本身。真分区挂到 `/persist`（这个挂载点 TWRP 认得，见 `twrp.flags:36`），再从 `/persist` bind 到 `/mnt/vendor/persist`；bind 不在 TWRP 自己的挂载列表里，`PartitionManager::Is_Mounted_By_Path()`（`infomanager.cpp:67-72`）会认为它已挂载，于是既不会被卸载，也不需要解析分区，设置就能稳稳写进真分区。

参考上游实现：[lingqiqi5211/twrp_device_xiaomi_sm8750@aaa74ed](https://github.com/lingqiqi5211/twrp_device_xiaomi_sm8750/commit/aaa74ed11b18d69a4ba17976803f184b66ab1517)。

### 5.6 /firmware(modem) 与触摸固件延迟

**症状**：`Failed to mount '/firmware' (No such file or directory)`，`Actual block device: ''`；`on fs` 里白等一整个 `wait` 超时（先是 10 s，后来 30 s）。

**原因**（用 `log/` 那三份日志复核后推翻了本节原来的结论）：`init.recovery.qcom.rc` 等的是 `/dev/block/bootdevice/by-name/modem`，但**这个节点在本机根本不存在**——`modem` 是 slotselect 分区，真名是 `modem_a` / `modem_b`（`recovery.fstab:63` 的 `/vendor/firmware_mnt` 和 `twrp.flags:20` 的 `/modem` 都带 `slotselect`，正是这个原因）。非后缀的 `by-name/modem` 是 **TWRP 自己**在解析 `/modem` 表项时创建的（`partition.cpp:2970-2973` 先 `unlink` 再 `symlink`；对应 `logcat:2401` 在 10:47:04.519 对 `by-name` 目录的 write 拒绝），而 init 的 `on fs` 远早于 TWRP 启动。所以这个 `wait` 无论给多久都不会成功，只会烧掉整个超时时间。

而且 init 的 action 是串行执行的：这次 30 s 的 `wait` 把后面整条链都堵住了——`healthd`(639)、`qseecomd`(634)、TWRP 自己(638) 全都等到 boot 32.33–32.35 s 才启动（`dmesg.log:1967` 的超时在 `[32.301783]`，TWRP 第一条日志在 `10:47:04.351`）。也就是说 **"10 → 30" 并没有修好 `/firmware`，只是把白等从 10 s 变成了 30 s。**

触摸控制器的固件请求（`focaltech_ts_fw.bin`，这个文件**在 9.25 GB 的 stock 转储里根本不存在**，官方系统上同样会失败）确实会拖住 ueventd 的 coldboot（这次 `dmesg.log:1991` 记的是 `took 30047ms`），但那是另一回事，不是 `/firmware` 挂不上的原因。

**修复**：等真正的节点。`ro.boot.slot_suffix` 在 init 第二阶段早期就有了（本机日志里是 `_a`），超时放宽到 60 s 当纯余量（节点一出现 `wait` 就返回，不会真的等满）：

```
wait /dev/block/bootdevice/by-name/modem${ro.boot.slot_suffix} 60
mkdir /firmware 0755 root root
mount vfat /dev/block/bootdevice/by-name/modem${ro.boot.slot_suffix} /firmware ro shortname=lower
```

同时给 `twrp.flags:33` 的 `/firmware` 补上 `slotselect`，让 TWRP 自己就能解析，不必依赖它自建的链接（否则开机还会弹一次 `Failed to mount '/firmware'`，见 `recovery.log:177`）。

**一个必须知道的连带坑**：`focaltech_ts_fw.bin` 请求失败后，FTS 驱动会回退到**内核内置固件**；如果内置版本与面板里的不一致，驱动会**整片擦写重刷**面板——这次是 `fw version in tp:28, host:21`，boot 32.45→46.56 s 共 14.1 s 面板都停在 bootloader 里，完全没有触摸，正好是"刚进 recovery 不能触摸"，等约 15 s 会自己恢复（恢复后的点按带 80 ms 触感，见 `logcat:3918` 起的 50 条 `duration = 80`）。要根治就把 `prebuilt/Image` 换成与所装 ROM 匹配的内核（当前是 `4.19.325-NijikaX-v2.9` KernelSU）。**不要**去伪造 `focaltech_ts_fw.bin` 放进设备树：它会被真的写进面板。

### 5.7 USB OTG

**症状**：`Unable to mount '/usb_otg'`，`/usb_otg Size: 0 B`，内核有 `request_module fs-auto succeeded, but still no fs?`。

**原因**：`twrp.flags` 里 `/usb_otg` 的 fstype 写的是 `auto`。TWRP 只在介质在位时才用 blkid 解析出真实文件系统（`partition.cpp` 的 `Check_FS_Type()`：`Is_Present == false` 就直接返回），没插盘时字符串 `auto` 被原样交给 `mount(2)`，内核去找一个不存在的 `fs-auto` 模块。

**修复**：`twrp.flags:47` 改成 `vfat`。设备节点路径本身没错：UFS 的 6 个 LUN 已经占满 `sda..sdf`，OTG 盘只会是 `sdg` / `sdg1`。插着盘时 blkid 仍会覆盖成真实文件系统，所以固定 `vfat` 不会伤到真实 U 盘。

## 6. 修复索引（症状 → 根因 → 落点）

| 症状 | 根因 | 落点 |
| --- | --- | --- |
| `Unable to decrypt metadata encryption` | key blob 的 OS/VENDOR patchlevel 与属性不匹配，TA 升级失败（-62 / -38） | `BoardConfig.mk:91-92` |
| HAL 每 5 s SIGABRT，致命点为 `fail to load lib` | `/vendor/lib64/vendor.awa.wavelib.so` 缺件 | 新增 `recovery/root/vendor/lib64/vendor.awa.wavelib.so` |
| HAL `RefBase: incStrongRequireStrong()` abort | Thread 子类裸指针直接调用 run，Android 16 要求已有强引用 | `vibrator/ThreadCompat.cpp` + 振动服务专用 `LD_PRELOAD`，待实机验证 |
| 同上，且 HAL 的 exec 早于 `vendor.sys.listeners.registered=true` | `class hal` 服务没有 `disabled`，被 `on boot` 的 `class_start hal` 无条件拉起（`builtins.cpp:166-181`） | `init.recovery.qcom.rc:123` 补 `disabled` + `start` 移入属性门 |
| HAL 可能死在版本化符号错误上 | 没钉 `LD_LIBRARY_PATH`，stock vendor 覆盖 `/vendor` 后它的 libbinder.so 压过 recovery 副本 | `init.recovery.qcom.rc:130` 补 `setenv LD_LIBRARY_PATH` |
| 设置重启后丢失 | persist 分区没挂，`TW_PERSIST_DIR` 解析不到分区 | `init.recovery.qcom.rc:75-79` |
| 振动校准读不到（`nv_flag = -1`） | HAL 读 `/mnt/vendor/persist/haptics`，同一分区未挂 | 同上 |
| 开机白等一整个超时、`/firmware` 挂不上 | 等的 `by-name/modem` 不是真实节点（真名 `modem_a`），TWRP 自建的链接来得太晚 | `init.recovery.qcom.rc:62-64`（改 `modem${ro.boot.slot_suffix}`、超时 60）、`twrp.flags:33`（补 `slotselect`） |
| `/usb_otg` 挂载失败 | fstype `auto` 在无介质时直达 `mount(2)` | `twrp.flags:47`（auto → vfat） |
| HAL 自重启循环 | `onrestart restart vibratorfeature` 指向不存在的服务 | `init.recovery.qcom.rc`（已删） |

## 7. 已知问题与限制

* **FDE 不支持**：TWRP 16.0 上游明确 `FDE decryption will not be supported in this branch`，本树只保留 FBE 路线；旧的 `qcom_decrypt` / `qcom_decrypt_fbe` 包与 `init.recovery.qcom_decrypt.rc` 均已移除。
* **触摸固件请求必然失败**：`focaltech_ts_fw.bin` 在 stock 中不存在（见 [5.6](#56-firmwaremodem-与触摸固件延迟)），只能等它超时，表现为 ueventd coldboot 被拖约 30 s（`dmesg.log:1991` `took 30047ms`）。更要紧的是驱动回退到内核内置固件后可能整片重刷面板：内置版本与面板不一致时，进 recovery 后会有约 14 s 完全无触摸（这次 tp:28 / host:21，`dmesg.log:1999`）；换用与所装 ROM 匹配的内核可消除。
* **`/sys/class/leds/vibrator/activate` 不存在**：HAL 会打印 `errno = 2` 后回退，不影响基础振动（awinic 驱动节点在 `/sys/bus/i2c/drivers/awinic_haptic/`，已在 rc 里放开权限）。
* **不带命名振动效果**：见 [5.4](#54-振动-hal)，需要时按需补 `*RTP.bin`。
* **无 AIDL health HAL**：TWRP 回退到 HIDL，日志里有对应提示，属正常噪音。
* **大量 permissive avc denial**：recovery 跑在 permissive 下，日志刷屏是正常的。
* **KernelSU 内核**：`prebuilt/Image` 带 KernelSU hook，启动日志里会出现相关行。
* **`preserve` 相关**：`BOARD_ROOT_EXTRA_FOLDERS` 里的 `persist` 只影响 system-as-root 目录布局，与 [5.5](#55-persist-挂载与设置保存) 的挂载无冲突。

## 8. 刷机后自检

```bash
adb shell getprop ro.build.version.security_patch        # 期望 2099-12-31
adb shell getprop ro.vendor.build.security_patch         # 期望 2099-12-31
adb shell mount | grep -E 'persist|firmware|usb_otg'     # 期望看到 /persist 与 /mnt/vendor/persist
adb shell ls -l /persist/TWRP/.twrp_settings             # 设置文件应存在
adb shell ls /vendor/firmware /vendor/lib64/vendor.awa.wavelib.so
adb shell getprop init.svc.vibratorfeature-hal-service   # 期望持续 running，不能只采样一次
adb shell ls -l /system/lib64/libmunch_vibrator_compat.so
adb logcat -d -s MunchVibratorCompat                     # 期望 Established legacy Thread owner
adb shell service list | grep android.hardware.vibrator # 期望 IVibrator/vibratorfeature
adb shell dmesg | grep -iE 'timed out|aw86927'           # 不应再有 10005ms 超时
```

## 9. 排障

日志位置：

| 来源 | 位置 |
| --- | --- |
| TWRP 主日志 | `/tmp/recovery.log`（TWRP 界面里也可以直接复制到存储） |
| 内核 | `dmesg` |
| Android | `logcat` |

关键字速查：

```
Unable to decrypt metadata encryption   -> 解密链（见 5.2）
KeyMint upgraded ... left unchanged     -> TA 运行时升级，正常
status: -62 / INVALID_ARGUMENT          -> patch level 不匹配
fail to load lib : /vendor/lib64/vendor.awa.wavelib.so  -> HAL 缺件（见 5.4）
RefBase : incStrongRequireStrong()            -> 检查 Thread 强引用兼容库是否生效，见 5.4
load 0 effect                                -> 未打包 RTP 效果，不能单独判定崩溃根因
SELinux : Context u:object_r:... unmapped    -> persist 挂载时的 restorecon 噪音，忽略
Fatal signal 6                               -> 往上找崩溃点真正的那一行
Unable to find partition for path       -> TWRP 分区表缺项（见 5.5）
timed out and took 10005ms              -> by-name 等待过短（见 5.6）
request_module fs-auto / no fs?         -> fstype auto（见 5.7）
```

## 10. 维护约定

* **不要删** `recovery/root/{system,vendor}/etc/vintf/manifest*.xml`：TWRP 靠它判定 Keymaster 版本（`bootable/recovery/twrp_functions.cpp` 的 `GetServiceFromManifest` ← `partitionmanager.cpp` 的 `Process_Keymaster_Version`），删了会回退到默认判定。
* **不要**把 security patch 写进 `system.prop`（重复 sysprop，构建直接失败，见 [5.2](#52-fbe-元数据解密)）。
* **不要**定义 `BOARD_BOOT_HEADER_VERSION`（见 [5.1](#51-recovery-as-boot)）。
* **不要** `git clean -fdx`：`stock/` 是本地素材且被 ignore，树里大量预编译二进制一旦被清掉无法从仓库恢复。
* 新增的 `.so` / 固件 / HAL 二进制都要 `git add`：它们不是从源码编译出来的，漏提交会让新克隆的构建缺件（`vendor.awa.wavelib.so` 就是典型）。
* 改完设备树记得核对 stock 与 ramdisk 的差异，只补「确实缺且被引用」的文件，不要整目录复制（振动效果固件就是反例）。

## 11. 许可与致谢

* 本仓库：GPL-2.0，见 [LICENSE](LICENSE)。
* [TeamWin/android_device_xiaomi_munch](https://github.com/TeamWin/android_device_xiaomi_munch)（原始设备树）、[SebaUbuntu TWRP device tree generator](https://github.com/SebaUbuntu/android_device_generator-twrp)（骨架）。
* [TWRP-Test/platform_manifest_twrp_aosp](https://github.com/TWRP-Test/platform_manifest_twrp_aosp)（TWRP 16.0 清单）。
* [lingqiqi5211/twrp_device_xiaomi_sm8750@aaa74ed](https://github.com/lingqiqi5211/twrp_device_xiaomi_sm8750/commit/aaa74ed11b18d69a4ba17976803f184b66ab1517)（persist 挂载思路）。
