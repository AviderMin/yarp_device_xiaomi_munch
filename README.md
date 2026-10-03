# yarp_device_xiaomi_munch

小米 Redmi K40S（代号 **munch**，型号 **22021211RC**，Qualcomm SM8250 / kona）的 **TWRP 16.0 设备树**，把 recovery 资源直接打进 boot 分区（recovery-as-boot）。

派生自 [TeamWin/android_device_xiaomi_munch](https://github.com/TeamWin/android_device_xiaomi_munch) 与 SebaUbuntu 的 TWRP 设备树生成器骨架，运行在 [TWRP-Test/platform_manifest_twrp_aosp](https://github.com/TWRP-Test/platform_manifest_twrp_aosp) 的 `twrp-16.0` 分支上，工作分支为 `yarp-16`。

本仓库同时是一份**「已经修好的参考实现 + 现场记录」**：FBE 元数据解密、persist 设置保存、`/firmware` 挂载、USB OTG 这几处关键问题的根因、证据和踩坑都写在本文档里，可以直接复用或对照排查。

> **给接手者的三条最短路径**
> 1. 只想构建刷机 → 看 [第 3 章](#3-构建与刷机) 与 [第 8 章](#8-验证与自检)。
> 2. 想知道「为什么这么改」→ 看 [第 5 章](#5-关键技术实现) 与 [第 6 章](#6-修复索引症状--根因--落点)。
> 3. 想动手改 → 先读 [第 9 章 红线](#9-维护红线不要踩的坑)，那里每一条都是构建失败或变砖级别的事故总结。

---

## 1. 一句话定位与维护原则

* **只改设备树**（构建时位于 `device/xiaomi/munch`），不改 AOSP 源码，不源码编译内核。
* stock 固件里缺的、recovery 又需要的件（预编译 `.so`、固件、VINTF 清单），一律放进 `recovery/root/`，随 recovery ramdisk 打包；不做整目录复制，只补「确实被引用且确实缺失」的文件。
* 所有手工放入的二进制都必须 `git add`：它们不是编译产物，漏提交会让新克隆出来的构建缺件（`vendor.awa.wavelib.so` 就是这么补进来的）。

---

## 2. 设备信息（已按仓库与 stock 转储核对）

| 项目 | 值 | 依据 |
| --- | --- | --- |
| 设备代号 / 型号 | `munch` / `22021211RC`（Redmi K40S） | `twrp_munch.mk` |
| SoC / GPU | Qualcomm SM8250 (kona) / Adreno 650 | `BoardConfig.mk` 的 `TARGET_BOARD_PLATFORM` / `_GPU` |
| 出厂 API | 31（`PRODUCT_SHIPPING_API_LEVEL`） | `device.mk:11` |
| stock 固件基线 | Android 13 / `RKQ1.211001.001`，增量版本 `V816.0.15.0.ULMCNXM`，fingerprint `Redmi/munch/munch:13/RKQ1.211001.001/V816.0.15.0.ULMCNXM:user/release-keys` | `stock/vendor/build.prop` |
| stock vendor 安全补丁 | `ro.vendor.build.security_patch=2025-03-01` | `stock/vendor/build.prop` |
| 分区方案 | A/B + 动态分区（`qti_dynamic_partitions`，super = 9126805504 B） | `BoardConfig.mk` |
| **recovery 位置** | **在 boot 分区里**（recovery-as-boot，本机没有独立 recovery 分区） | `device.mk:18` |
| boot 分区大小 | 201326592 B（192 MiB） | `BoardConfig.mk` |
| 内核 | `prebuilt/Image`（50628624 B），**预编译，不参与构建**；内核版本串 `Linux version 4.19.157-perf-ge7d64d2c1baa`，Xiaomi `pangu-build-component` 构建，clang 10.0.7 | `prebuilt/Image` 内嵌字符串 |
| 加密方式 | FBE，metadata encryption（fscrypt policy v2 + wrapped key） | `recovery.fstab:53`、`twrp.flags:31-32` |
| TWRP 版本串 | `TW_DEVICE_VERSION := AviderMin`；`TW_MAIN_VERSION_STR` 由上游 `vendor/twrp` 提供（本机不固定 3.7.1，以实际构建为准） | `BoardConfig.mk` |

> ⚠️ **口径修正**：老版本 README 写内核是 `4.19.325-NijikaX-v2.9（KernelSU）`。实测 `prebuilt/Image` 的版本串是 `4.19.157-perf-ge7d64d2c1baa`，且镜像里搜不到 `NijikaX` / `KernelSU` / `sukisu` 任何标记。请以实测为准；若要换内核，换的就是 `prebuilt/Image` 这一个文件。

---

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

* lunch 目标来自 `AndroidProducts.mk` 的 `COMMON_LUNCH_CHOICES := twrp_munch-eng`，产品名来自 `twrp_munch.mk` 的 `PRODUCT_NAME := twrp_munch`。
* `ALLOW_MISSING_DEPENDENCIES=true` 在 `BoardConfig.mk:11` 里也设了一份，避免用最小清单构建时缺件报错。

### 3.2 刷入

```bash
fastboot flash boot out/target/product/munch/boot.img
```

本机**没有 recovery 分区**：`device.mk:18` 打开 `BOARD_USES_RECOVERY_AS_BOOT := true`，AOSP 因此把 `INSTALLED_RECOVERYIMAGE_TARGET` 置空（`build/make/core/Makefile:283-296`），**不会**产出 `recovery.img`；TWRP 的 recovery 资源被打进 boot 镜像，所以刷的是 `boot` 分区。

> 从别的 recovery 切过来时注意 A/B 槽位：`fastboot --set-active=a|b` 要与刷入的槽位一致。本机实测 `ro.boot.slot_suffix` 为 `_a`。

---

## 4. 仓库结构

```
BoardConfig.mk              板级配置：架构、预编译内核、分区、mkbootimg、加密、TWRP 变量
device.mk                   产品配置：API 级别、A/B、动态分区、boot HAL、加密开关、PLATFORM_VERSION
twrp_munch.mk               lunch 目标 twrp_munch（继承 base / core_64_bit_only / virtual_ab_ota）
AndroidProducts.mk          注册 PRODUCT_MAKEFILES 与 COMMON_LUNCH_CHOICES
Android.mk                  子目录 makefile 入口
system.prop                 ro.adb.secure=0 / ro.boot.dynamic_partitions / gatekeeper.disable_spu
prebuilt/Image              预编译内核（TARGET_PREBUILT_KERNEL 指向这里）
recovery/root/              recovery ramdisk 覆盖层（被原样打包进 ramdisk），共 77 个文件
├── init.recovery.qcom.rc       核心 init rc：挂载链、QTI 安全服务、属性门
├── init.recovery.usb.rc        USB gadget / adb / fastbootd / MTP（98 行）
├── ueventd.rc                  516 行设备节点权限规则
├── system/etc/
│   ├── recovery.fstab          分区表（含 userdata 的 FBE metadata 参数、metadata、modem）
│   ├── twrp.flags              TWRP 自己的分区表（/firmware /persist /usb_otg /modem 等）
│   ├── vintf/manifest.xml      TWRP 判定 Keymaster 版本用，勿删
│   ├── event-log-tags          日志 tag 定义
│   └── task_profiles.json      cgroup / task profile 定义
└── vendor/
    ├── bin/qseecomd                        QSEECom 守护进程
    ├── bin/keymasterd                      vendor keymasterd（保持 TA 常驻）
    ├── bin/hw/                             keymaster@4.0 / gatekeeper@1.0 预编译 HAL
    ├── etc/ueventd.rc                      10 行，追加 firmware_directories /firmware/image/
    ├── etc/vintf/manifest.xml              vendor VINTF 清单，勿删
    ├── firmware/aw8697_haptic.bin          内核触感 ram firmware（3622 B，与 stock 逐字节相同）
    ├── firmware/focaltech_ts_fw.bin        触摸固件（113092 B，见 5.6）
    ├── firmware_mnt/image/                 keymaster / keymaster64 / sp_keymaster 共 27 个 MBN 分段
    └── lib64/                              QTI 安全库 + vendor.awa.wavelib.so + display.config
stock/                      本地官方固件转储（9.33 GB / 10534 个文件，.gitignore 忽略，非交付内容）
log/                        调试日志（dmesg.log / logcat.txt / recovery.log，.gitignore 忽略）
```

### 4.1 关键文件速查

| 文件 | 作用 | 关键行 |
| --- | --- | --- |
| `BoardConfig.mk` | `PLATFORM_SECURITY_PATCH := 2099-12-31`（解密关键）、`BOARD_MKBOOTIMG_ARGS += --header_version 3` | :91-92, :50 |
| `device.mk` | `BOARD_USES_RECOVERY_AS_BOOT := true`、`TW_INCLUDE_FBE_METADATA_DECRYPT := true` | :18, :68-70 |
| `recovery/root/init.recovery.qcom.rc` | `on fs` 挂载链（modem/persist/bind）、QTI 服务声明、属性门 | :42, :69-71, :81-85, :107-149 |
| `recovery/root/system/etc/twrp.flags` | `/firmware` :33、`/persist` :36、`/usb_otg` :47、`/data` :31 |
| `recovery/root/system/etc/recovery.fstab` | userdata 的 FBE metadata 参数 :53、metadata :50、modem :63 |
| `recovery/root/vendor/etc/ueventd.rc` | `firmware_directories /firmware/image/` :10 |

---

## 5. 关键技术实现

### 5.1 recovery-as-boot 与 boot 镜像头

* `device.mk` 打开 `BOARD_USES_RECOVERY_AS_BOOT := true`，并启用 `ENABLE_VIRTUAL_AB := true` / `AB_OTA_UPDATER := true`。
* boot 镜像头版本走 `BOARD_MKBOOTIMG_ARGS += --header_version 3`（`BoardConfig.mk:50`），由 AOSP 直接透传给 `mkbootimg`（`build/make/core/Makefile:1299/1398`）。
* ⚠️ **不要在 `BoardConfig.mk` 里定义 `BOARD_BOOT_HEADER_VERSION`**：任何 ≥3 的值都会让 AOSP 置 `BUILDING_VENDOR_BOOT_IMAGE := true`（`build/make/core/board_config.mk:521-531`），把内核 cmdline 从 boot.img 挪走，TWRP 的 `twrpfastboot=1`（`vendor/twrp/config/BoardConfigTWRP.mk:7`）就落不进任何镜像。这条警告在 `BoardConfig.mk:38-49` 有完整注释。
* 内核走预编译路线：`BOARD_KERNEL_IMAGE_NAME := Image` + `TARGET_PREBUILT_KERNEL := $(DEVICE_PATH)/prebuilt/Image`（`BoardConfig.mk:35-38`），不编译 `kernel/xiaomi/munch`。
* `BOARD_KERNEL_CMDLINE` 为空，设备特有的 cmdline 由 TWRP 自己追加。

### 5.2 FBE 元数据解密（本树最重要的一处修复）

**症状**：TWRP 看得见 `/metadata`，但报 `I:Unable to decrypt metadata encryption`，`/data` 探测失败。

**根因链**（历史日志 `log/logcat.txt`）：

```
rsp_header->status: -62 (KEY_REQUIRES_UPGRADE)
  -> keystore2 upgrade_keyblob_if_required_with
  -> Error::Km(INVALID_ARGUMENT) -38
  -> decryptWithKeystoreKey failed
  -> I:Unable to decrypt metadata encryption
```

**key blob 里的真实参数**（`/metadata/vold/metadata_encryption/key/keymaster_key_blob`，232 B，magic `pKMblob` + CBOR）：

| Keymaster tag | blob 中的值 | TWRP 原来提供的 |
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

生成出的属性是 `ro.build.version.security_patch=2099-12-31` 与 `ro.vendor.build.security_patch=2099-12-31`。比 blob 要求的日期更新，Keymaster 会在 TEE 里做一次性升级，且**不落盘**：

```
KeyMint upgraded <blob> for this operation only; the on-disk blob is left unchanged
```

因此刷回官方系统不受影响。实测结果：`Successfully decrypted metadata encrypted data partition with new block device: '/dev/block/mapper/userdata'` → `All found users are decrypted` → `/data` 以 f2fs rw 挂载。

**备选方案**：把 patch level 精确设成 blob 里的 `2026-08-01` 也能解密（已用 `resetprop` 在设备上验证过），只是维持一个会过期的日期不如远未来值省事。

**踩过的坑**：

* 不要把 `ro.build.version.security_patch` 写进设备树 `system.prop`：`build/make/tools/post_process_props.py:97-141` 的 `override_optional_props(allow_dup=False)` 会直接报 `error: found duplicate sysprop assignments` 让构建失败。
* `ro.vendor.build.security_patch` 原本没人赋值（`build/make/core/sysprop_config.mk:122` 从 `VENDOR_SECURITY_PATCH` 取），所以必须显式给 `VENDOR_SECURITY_PATCH` 赋值。
* 属性最终来源是 `prop.default`（`build/make/core/Makefile:2716-2730` 按 system→vendor→odm→product→system_ext→recovery-ui 顺序拼接），后加载的覆盖先加载的。
* `resetprop` 改这两个属性只对当前这次启动有效，**不能**作为永久修复；永久修复必须在设备树里。
* Android 16 把 patch level 收归 release flags：`RELEASE_PLATFORM_SECURITY_PATCH` / `RELEASE_PLATFORM_VERSION_LAST_STABLE` 是 `.KATI_READONLY`，直接设 `PLATFORM_SECURITY_PATCH` / `PLATFORM_VERSION_LAST_STABLE` 会踩 `build/make/core/version_util.mk:55 / :113` 的 `$(error)` 守卫。`device.mk` 末尾的注释记录了这件事；真正生效的赋值留在 `BoardConfig.mk:91-92`。`PLATFORM_VERSION := 99.87.36` 两侧都写了，只有它仍然可以从设备树覆盖。

### 5.3 QTI 安全服务（qseecomd / keymaster / gatekeeper）

recovery 不会导入 stock 的 `vendor/etc/init/*.rc`（stock 里这些文件都在，只是不生效），所以 `init.recovery.qcom.rc` 必须自己声明这些服务：

| 服务 | 定义位置 | 说明 |
| --- | --- | --- |
| `vendor.qseecomd` | `init.recovery.qcom.rc:107` | `class core`，在 `on fs` 里 `start`（:98）；启动前先 `wait /dev/qseecom` 与 `ssd` 节点（:96-97） |
| `vendor.keymasterd` | :116 | `class core`，`disabled`，由属性门拉起 |
| `keymaster-4-0` | :124 | `class hal`，必须写 `interface android.hardware.keymaster@4.0::IKeymasterDevice default`，否则 `ctl.interface_start` 的 lazy HAL 请求找不到服务 |
| `gatekeeper-1-0` | :133 | 同上，`interface android.hardware.gatekeeper@1.0::IGatekeeper default` |

启动门槛在 `:146`：

```
on property:hwservicemanager.ready=true && property:vendor.sys.listeners.registered=true
    start gatekeeper-1-0
    start keymaster-4-0
    start vendor.keymasterd
```

`vendor.sys.listeners.registered` 由 qseecomd 自己设置；没有这道门，HAL 会在 QSEE 就绪前调 `QSEECom_start_app` 并崩溃重启。

`on early-init` 会把 `/vendor/lib64` bind 到 `/vendor_lib64`（:32-33），后续即使真 vendor 分区被挂上也不会遮蔽这些安全库。所有 QTI 服务共用同一条 `setenv LD_LIBRARY_PATH`（:111 等）：`/vendor_lib64:/vendor_lib64/hw:/vendor/lib64:/vendor/lib64/hw:/system/lib64:/sbin`——`/vendor_lib64` 必须排在 `/vendor/lib64` 前面。

`on fs` 还会放开两个节点权限（:87-92）：`/dev/qseecom`（QSEECom 的客户端节点）和 `/dev/ion`（QSEECom 通过 ION 分配共享缓冲，默认 root-only，不放权则每次 listener 注册和 `start_app` 都失败）。

**keymaster TA 在哪**：munch 的 keymaster TA 不是 modem 分区里的，而是 `keymaster_a` 分区（sde11）的签名镜像；树里以拆分 MBN 形式放在 `recovery/root/vendor/firmware_mnt/image/`（`keymaster.*` / `keymaster64.*` / `sp_keymaster.*` 共 27 个文件）。`libkeymasterdeviceutils.so` 硬编码搜索 `/vendor/firmware_mnt/image`，QSEECom 打开 `<dir>/<app>.mdt` 与 `.b00..`。因为文件就在 ramdisk 里，这条路径**不需要挂载任何分区**即可解析。

`on fs` 里还写了一行 `write /proc/sys/kernel/firmware_config/force_sysfs_fallback 1`（:56），让内核固件加载器走 sysfs 回退路径；`recovery/root/vendor/etc/ueventd.rc:10` 追加 `firmware_directories /firmware/image/` 作为兜底别名。

### 5.4 persist 挂载与 TWRP 设置保存

**症状**：TWRP 里改的设置重启后丢失，`recovery.log` 里有 `Unable to find partition for path /mnt/vendor/persist/TWRP`。

**根因**：TWRP 16.0 把设置目录定义为 `TW_PERSIST_DIR = /mnt/vendor/persist/TWRP`（`bootable/recovery/variables.h:24-25`，`TW_PERSIST_ROOT = /mnt/vendor/persist`），而本树 `recovery.fstab:58` 的那行 persist 是注释掉的，TWRP 的分区表里没有挂载点是 `/mnt/vendor/persist` 的表项，于是解析不到分区、设置写不进去。

**修复**（`init.recovery.qcom.rc:81-85`）：

```
mkdir /mnt/vendor 0775 shell system
mkdir /mnt/vendor/persist 0775 shell system
wait /dev/block/bootdevice/by-name/persist 10
mount ext4 /dev/block/bootdevice/by-name/persist /persist noatime nosuid nodev barrier=1
mount none /persist /mnt/vendor/persist bind
```

为什么绕这一圈：TWRP 启动时会卸载自己管理的挂载点，并且只按路径首段解析分区，所以它「拿不住」`/mnt/vendor/persist` 本身。真分区挂到 `/persist`（这个挂载点 TWRP 认得，见 `twrp.flags:36`），再从 `/persist` bind 到 `/mnt/vendor/persist`；bind 不在 TWRP 自己的挂载列表里，`PartitionManager::Is_Mounted_By_Path()`（`infomanager.cpp:67-72`）会认为它已挂载，于是既不会被卸载，也不需要解析分区，设置就能稳稳写进真分区。

参考上游实现：[lingqiqi5211/twrp_device_xiaomi_sm8750@aaa74ed](https://github.com/lingqiqi5211/twrp_device_xiaomi_sm8750/commit/aaa74ed11b18d69a4ba17976803f184b66ab1517)。

> 本节原有的一处副作用是给振动 HAL 的校准数据（`/mnt/vendor/persist/haptics/*`）提供路径。振动 HAL 已在 `7071440` 移除（见 5.8），现在 persist 挂载只为 TWRP 设置服务。

### 5.5 `/firmware`(modem) 挂载

**症状**：`Failed to mount '/firmware' (No such file or directory)`，`Actual block device: ''`；`on fs` 里白等一整个 `wait` 超时（先是 10 s，后来 30 s）。

**根因**（用 `log/` 里的日志复核后推翻了更早版本的结论）：原来等的是 `/dev/block/bootdevice/by-name/modem`，但**这个节点在本机根本不存在**——`modem` 是 slotselect 分区，真名是 `modem_a` / `modem_b`（`recovery.fstab:63` 的 `/vendor/firmware_mnt` 和 `twrp.flags:20` 的 `/modem` 都带 `slotselect`，正是这个原因）。非后缀的 `by-name/modem` 是 **TWRP 自己**在解析 `/modem` 表项时创建的（`partition.cpp:2970-2973` 先 `unlink` 再 `symlink`），而 init 的 `on fs` 远早于 TWRP 启动。所以这个 `wait` 无论给多久都不会成功，只会烧掉整个超时时间。

而且 init 的 action 是串行执行的：这次 30 s 的 `wait` 把后面整条链都堵住了——`healthd`(pid 639)、`qseecomd`(634)、TWRP 自己(638) 全都等到 boot 32.33–32.35 s 才启动。也就是说 **「10 → 30」并没有修好 `/firmware`，只是把白等从 10 s 变成了 30 s。**

**修复**（`init.recovery.qcom.rc:69-71`）：等真正的节点。`ro.boot.slot_suffix` 在 init 第二阶段早期就有了（本机是 `_a`），超时放宽到 60 s 当纯余量（节点一出现 `wait` 就返回，不会真的等满）：

```
wait /dev/block/bootdevice/by-name/modem${ro.boot.slot_suffix} 60
mkdir /firmware 0755 root root
mount vfat /dev/block/bootdevice/by-name/modem${ro.boot.slot_suffix} /firmware ro shortname=lower
```

同时给 `twrp.flags:33` 的 `/firmware` 补上 `slotselect`，让 TWRP 自己就能解析，不必依赖它自建的链接（否则开机还会弹一次 `Failed to mount '/firmware'`）。

### 5.6 触摸固件（focaltech_ts_fw.bin）

**这一节与旧版 README 的结论相反，请注意。**

* 触摸控制器请求的固件文件名是 `focaltech_ts_fw.bin`。文件**不在** `stock/vendor/firmware/` 的 380 个文件里，**但确实存在于内核镜像内部**。
* 已实测：`recovery/root/vendor/firmware/focaltech_ts_fw.bin`（113092 B）与 `prebuilt/Image` 偏移 `0x2E8FB60` 处内嵌的固件**逐字节相同**，SHA-256 均为
  `8BAF73FD6221605EF815646B3C08C1C6E16566C71F41F0CF0C8CB371CB1FF0E1`。
* 因此这份文件的来源是「从内核映像里提取出来、放回 ramdisk 的 `/vendor/firmware/`」，属于**恢复内核内置固件**，不是伪造：该固件是分块/分段格式（首字节 `00 00 20 60`，随后是重复的 `00 00 AA 70` 段标记），必须按真实的分段布局整份写入才有效。

**为什么这很关键**：FTS 驱动在请求失败时会回退到**内核内置固件**；如果内置版本与面板里的不一致，驱动会**整片擦写重刷**面板。历史现场是 `fw version in tp:28, host:21`，boot 32.45→46.56 s 共 14.1 s 面板都停在 bootloader 里，完全没有触摸，正好是「刚进 recovery 不能触摸」，等约 15 s 会自己恢复。把与内核匹配的固件放到 `/vendor/firmware/` 可以避免这次不一致重刷。

**改动前必须验证**：换内核（替换 `prebuilt/Image`）后，内嵌固件可能变化。此时必须重新从新镜像里提取固件并替换 `recovery/root/vendor/firmware/focaltech_ts_fw.bin`，否则两者版本不一致，副作用与「不提供文件」一样甚至更糟。提取校验命令见第 8 章。

### 5.7 USB OTG

**症状**：`Unable to mount '/usb_otg'`，`/usb_otg Size: 0 B`，内核有 `request_module fs-auto succeeded, but still no fs?`。

**根因**：`twrp.flags` 里 `/usb_otg` 的 fstype 写的是 `auto`。TWRP 只在介质在位时才用 blkid 解析出真实文件系统（`partition.cpp` 的 `Check_FS_Type()`：`Is_Present == false` 就直接返回），没插盘时字符串 `auto` 被原样交给 `mount(2)`，内核去找一个不存在的 `fs-auto` 模块。

**修复**：`twrp.flags:47` 改成 `vfat`。设备节点路径本身没错：UFS 的 6 个 LUN 已经占满 `sda..sdf`，OTG 盘只会是 `sdg` / `sdg1`。插着盘时 blkid 仍会覆盖成真实文件系统，所以固定 `vfat` 不会伤到真实 U 盘。

### 5.8 振动 HAL：已移除（这里是当前分支的真实现状）

**代码状态**：`7071440 移除与小米振动器 HAL 相关的代码和配置文件`。此后 HEAD 上**不存在**下列任何东西：

| 已删除的路径 / 变量 | 原作用 |
| --- | --- |
| `recovery/root/vendor/bin/hw/vendor.xiaomi.hardware.vibratorfeature.service` | Xiaomi `vibratorfeature` HAL 预编译二进制 |
| `recovery/root/vendor/lib64/vendor.hardware.vibratorfeature.IVibratorExt-V1-ndk_platform.so` | HAL 的 Ext 接口库 |
| `recovery/root/vendor/etc/vintf/manifest/vendor.xiaomi.hardware.vibratorfeature.service.xml` | 该 HAL 的 VINTF 清单 |
| `vibrator/Android.bp`、`vibrator/ThreadCompat.cpp` | 为解决 Thread 所有权问题而写的 `libmunch_vibrator_compat.so` 兼容库 |
| `BoardConfig.mk` 的 `NEED_AIDL_NDK_PLATFORM_BACKEND := true` | 生成 AIDL platform-NDK 后端的开关 |
| `device.mk` 的 `RECOVERY_LIBRARY_SOURCE_FILES` 中两项 `android.hardware.vibrator-V1-ndk_platform.so` / `libmunch_vibrator_compat.so` | 把 AIDL 后端与兼容库 relink 进 recovery 的 `/system/lib64` |
| `device.mk` 的 `TW_SUPPORT_INPUT_AIDL_HAPTICS := true` 与 `..._FQNAME := "IVibrator/vibratorfeature"` | 告诉 TWRP 有 AIDL 振动 HAL |
| `init.recovery.qcom.rc` 的 `vibratorfeature-hal-service` 服务块 | 服务声明（含 `setenv LD_PRELOAD` 与 `class_start hal` 用的 `disabled`） |
| `init.recovery.qcom.rc` 的 aw8697/awinic sysfs `chown`/`chmod` 权限块 | 放开 `f0_save`/`osc_save`/`custom_wave`/`nv_flag`/`f0_value` 等节点 |
| `recovery/root/system/etc/vintf/manifest/vibratorfeature.xml` | 曾被加入、随后在 `285450c` 被 revert 的 AIDL 清单 |

**因此当前分支的振动能力是：**

* **基础振动（点击式）走内核 awinic/aw8697 驱动与 sysfs**，不依赖任何 HAL。`recovery/root/ueventd.rc` 里已放开 `/dev/i2c-*` 与 `/sys/class/qcom-haptics/*` 的权限；`recovery/root/vendor/firmware/aw8697_haptic.bin`（3622 B，与 `stock/vendor/firmware/aw8697_haptic.bin` 逐字节相同）是内核驱动的 ram firmware。
* **Xiaomi 命名振动效果（RTP 效果流）不支持**，也刻意不打包：`stock/vendor/firmware/` 里 380 个文件中绝大多数是 `*RTP.bin` 效果文件，体积可观；没有它们不影响基础振动。
* `recovery/root/vendor/lib64/vendor.awa.wavelib.so`（631200 B，与 `stock/vendor/lib64/vendor.awa.wavelib.so` 逐字节相同）**仍在仓库里**，但目前没有服务加载它（它的唯一消费者是被删除的 vibratorfeature HAL）。保留原因见 `c972f34` 的修复历史；如需减重可评估移除，但要确认没有别的引用。

**历史教训（保留，避免重走一遍）**：旧 HAL 在 Android 16 recovery 下崩溃的根因是
`F RefBase : incStrongRequireStrong() called on 0x... which isn't already owned` → `Fatal signal 6 (SIGABRT)`。
其机制是：HAL 在 `0xc038` 分配 `Thread` 子类、`0xc04c` 保存裸指针、`0xc06c` 直接调用虚表里的 `Thread::run`，中间没有建立强引用；而 Android 16 的 `system/core/libutils/Threads.cpp:685` 使用 `sp<Thread>::fromExisting(this)`，会调用 `incStrongRequireStrong()` 并 abort。当时的对策是 `LD_PRELOAD` 拦截 `_ZN7android6Thread3runEPKcim`、只在计数为 `1 << 28` 时建立一次 legacy owner。**该 HAL 与其兼容库现已整体移除**，若将来要重新引入振动 HAL，请从这里重新评估，不要去改全局 RefBase 检查。

### 5.9 其它已做的调整

* `TW_FRAMERATE := 120`（`d6bf374`）：recovery 界面 120 Hz。
* `TW_USE_FSCRYPT_POLICY := 2`：Android 13 固件用 fscrypt policy v2。TWRP 只在取值恰好为 `1` 时选 v1，其它值（含 2）都落在 v2，即 `2 == 默认 ==` 期望值。
* `TW_EXCLUDE_APEX := true`：跳过 recovery 里的 APEX loop 挂载，本机内核上 APEX 探测只会白白多一次失败挂载。
* `TW_BACKUP_EXCLUSIONS := /data/fonts`、`TW_INPUT_BLACKLIST := "hbtp_vm"`、`TW_DEFAULT_BRIGHTNESS := 500` / `TW_MAX_BRIGHTNESS := 2047`、状态栏定位三连（`center` / 50 / 340 / 800）。
* `TW_INCLUDE_CRYPTO` / `TW_INCLUDE_CRYPTO_FBE` / `TW_INCLUDE_FBE_METADATA_DECRYPT` 全开，`BOARD_USES_QCOM_FBE_DECRYPTION := true`，`BOARD_USES_METADATA_PARTITION := true`。
* 已移除旧的 `qcom_decrypt` / `qcom_decrypt_fbe` 包与 `init.recovery.qcom_decrypt.rc`（`3433b29`），本分支只走 FBE 路线。
* `.gitattributes` 强制所有文本文件 `eol=lf`（本仓库在 Windows 上编辑、在 Linux 上构建），并把 `*.bin` / `*.so` / `*.img` / `*.apk` 以及 `prebuilt/Image` 显式标为 binary，避免换行符转换破坏二进制。
* `system.prop` 只有三行：`ro.adb.secure=0`、`ro.boot.dynamic_partitions=true`、`vendor.gatekeeper.disable_spu=true`。第三个是 gatekeeper 在 recovery 下缺少 SPU 时的必要开关。

---

## 6. 修复索引（症状 → 根因 → 落点）

| 症状 | 根因 | 落点 | 状态 |
| --- | --- | --- | --- |
| `Unable to decrypt metadata encryption` | key blob 的 OS/VENDOR patchlevel 与属性不匹配，TA 升级失败（-62 / -38） | `BoardConfig.mk:91-92` | 已实机验证 |
| 设置重启后丢失 / `Unable to find partition for path /mnt/vendor/persist/TWRP` | persist 分区没挂，`TW_PERSIST_DIR` 解析不到分区 | `init.recovery.qcom.rc:81-85` | 已修，待刷机复验 |
| `/firmware` 挂不上；开机白等一整个超时；qseecomd/TWRP 启动被推迟到 boot 32 s | 等的 `by-name/modem` 不是真实节点（真名 `modem_a`），TWRP 自建的链接来得太晚，且 init action 串行 | `init.recovery.qcom.rc:69-71` + `twrp.flags:33` 补 `slotselect` | 已修，待刷机复验 |
| `/usb_otg` 挂载失败，`Size: 0 B`，`request_module fs-auto` | fstype `auto` 在无介质时直达 `mount(2)` | `twrp.flags:47`（auto → vfat） | 已修，需插盘验证 |
| `fail to load lib : /vendor/lib64/vendor.awa.wavelib.so`，HAL 每 5 s SIGABRT | ramdisk 缺该库 | 新增 `recovery/root/vendor/lib64/vendor.awa.wavelib.so` | 库仍在，消费者已删除（见 5.8） |
| HAL `RefBase: incStrongRequireStrong()` abort | 旧 HAL 的 Thread 裸指针所有权与 Android 16 libutils 不兼容 | 曾用 `vibrator/ThreadCompat.cpp` + 专用 `LD_PRELOAD` 缓解 | **随 HAL 一并移除**（5.8） |
| HAL 死在版本化符号错误上 | 没钉 `LD_LIBRARY_PATH`，stock vendor 覆盖 `/vendor` 后 libbinder.so 压过 recovery 副本 | 曾给 vibratorfeature 补 `setenv LD_LIBRARY_PATH` | 其它 QTI 服务仍保留该 setenv |
| 触摸在进入 recovery 后约 14 s 完全无响应 | FTS 驱动回退内核内置固件，且与面板版本不一致（tp:28 / host:21）导致整片重刷 | `recovery/root/vendor/firmware/focaltech_ts_fw.bin`（与内核内嵌固件同源同哈希） | 已提供文件，待实机复验 |
| keymaster/gatekeeper 反复崩溃或找不到服务 | 服务未在本文件声明；缺 `interface ...::IKeymasterDevice default`；缺属性门 | `init.recovery.qcom.rc:107-149` | 已修 |
| `QSEECom_start_app` / listener 注册失败 | `/dev/qseecom`、`/dev/ion` 权限不足 | `init.recovery.qcom.rc:87-92` | 已修 |

---

## 7. 已知问题与限制

* **FDE（全盘加密）不支持**：TWRP 16.0 上游明确该分支不提供 FDE 解密；本树只保留 FBE 路线，旧的 `qcom_decrypt` 相关包与 rc 均已移除。
* **无 AIDL 振动 HAL**：见 5.8。基础振动可用（走内核驱动），命名效果不支持。
* **`/sys/class/leds/vibrator/activate` 不存在**：历史日志里旧 HAL 会打印 `errno = 2` 后回退；awinic 驱动的真实节点在 `/sys/bus/i2c/drivers/awinic_haptic/` 与 `/sys/class/qcom-haptics/`。
* **触摸固件与内核绑定**：`focaltech_ts_fw.bin` 必须与 `prebuilt/Image` 内嵌的那份一致（当前 SHA-256 以 8BAF73FD… 开头）。换内核必须同步换这份固件（见 5.6、8.3）。
* **仍可能出现 `timed out and took ... ms`**：ueventd coldboot 会被触摸固件请求拖慢；只要不再等错节点，就不会再阻塞 init 串行链。
* **大量 permissive avc denial**：recovery 跑在 permissive 下，日志刷屏是正常的；`SELinux : Context u:object_r:... unmapped` 在 persist 挂载时的 restorecon 噪音可忽略。
* **`preserve` 相关**：`BOARD_ROOT_EXTRA_FOLDERS` 里的 `persist` 只影响 system-as-root 目录布局，与 5.4 的挂载无冲突。
* **未验证项**：5.4 / 5.5 的修复在最后一次提交后尚未刷机复验；USB OTG 需要真实 U 盘；触摸需要一个与当前内核匹配的面板现场。本文档不把「代码已改」写成「已实机验证」。

---

## 8. 验证与自检

### 8.1 刷机后自检

```bash
adb shell getprop ro.build.version.security_patch        # 期望 2099-12-31
adb shell getprop ro.vendor.build.security_patch         # 期望 2099-12-31
adb shell mount | grep -E 'persist|firmware|usb_otg'     # 期望看到 /persist 与 /mnt/vendor/persist
adb shell ls -l /persist/TWRP/.twrp_settings             # TWRP 设置文件应存在
adb shell ls -l /vendor/firmware/focaltech_ts_fw.bin     # 触摸固件应在 ramdisk 中
adb shell dmesg | grep -iE 'fts|focaltech|timed out'     # 观察是否仍有超时与重刷
adb shell service list | grep -E 'keymaster|gatekeeper'  # 期望两个 HIDL 服务已注册
```

### 8.2 构建产物自检

```bash
# boot.img 存在且头部版本为 3
ls -l out/target/product/munch/boot.img
unpack_bootimg --boot_img out/target/product/munch/boot.img --header_version 3 --out /tmp/boot
grep -a twrpfastboot /tmp/boot/kernel_cmdline.txt        # 期望能搜到 twrpfastboot=1
```

### 8.3 触摸固件一致性校验（换内核后必做）

```bash
# 1) 取树里的固件哈希
sha256sum recovery/root/vendor/firmware/focaltech_ts_fw.bin
# 期望 8baf73fd6221605ef815646b3c08c1c6e16566c71f41f0cf0c8cb371cb1ff0e1

# 2) 在新内核镜像里找到内嵌固件（16 字节特征头 00 00 20 60 00 00 AA 70 ...）
python3 - <<'PY'
import hashlib, pathlib
tree = pathlib.Path('recovery/root/vendor/firmware/focaltech_ts_fw.bin').read_bytes()
img  = pathlib.Path('prebuilt/Image').read_bytes()
probe = tree[:16]
start, hits = 0, []
while (i := img.find(probe, start)) != -1:
    hits.append(i); start = i + 1
print('candidates:', [hex(h) for h in hits])
target = hashlib.sha256(tree).hexdigest()
for h in hits:
    if hashlib.sha256(img[h:h+len(tree)]).hexdigest() == target:
        print('EXACT MATCH at', hex(h))
PY
```

当前状态：`prebuilt/Image` 中恰好 1 处候选，位于 `0x2E8FB60`，哈希一致。

---

## 9. 维护红线（不要踩的坑）

| 不要做 | 原因 |
| --- | --- |
| 不要把 `ro.build.version.security_patch` / `ro.vendor.build.security_patch` 写进 `system.prop` | 重复 sysprop 会让构建直接报 `error: found duplicate sysprop assignments`（见 5.2） |
| 不要定义 `BOARD_BOOT_HEADER_VERSION` | ≥3 会让 AOSP 走 vendor_boot 路径，`twrpfastboot=1` 无处安放（见 5.1） |
| 不要直接设 release flag 里的 patch level | Android 16 的 `.KATI_READONLY` 守卫会 `$(error)`（见 5.2） |
| 不要删 `recovery/root/{system,vendor}/etc/vintf/manifest*.xml` | TWRP 靠它判定 Keymaster 版本（`GetServiceFromManifest` ← `Process_Keymaster_Version`），删了会回退默认判定 |
| 不要 `git clean -fdx` | `stock/` 是本地素材且被 ignore；树里大量预编译二进制一旦被清掉无法从仓库恢复 |
| 不要整目录复制 stock 文件进 `recovery/root/` | 只补「确实缺且被引用」的文件。振动效果固件（大量 `*RTP.bin`）就是反例 |
| 不要伪造 / 随便替换 `focaltech_ts_fw.bin` | 它是真实的分段固件格式，会被真的写进面板；必须与内核内嵌固件一致（见 5.6、8.3） |
| 不要给 recovery 新增服务时忘了 `disabled` + 属性门 | `on boot` 的 `class_start hal` 只跳过显式 `disabled` 的服务（`system/core/init/builtins.cpp:166-181`），否则会在 QSEE 就绪前崩溃重启 |
| 不要在 `on fs` 里等非 slotselect 的裸节点名 | 见 5.5：`by-name/modem` 是 TWRP 事后创建的，等它只会白等并把整条 init 链堵死 |
| 新增 `.so` / 固件 / HAL 二进制后不要忘记 `git add` | 它们不是编译产物，漏提交会让新克隆的构建缺件 |

---

## 10. 变更历史（全部 36 个提交）

下面按时间顺序列出全部提交。这是理解「为什么现在是这个样子」的最快路径：每个修复都有对应的提交。

| # | 提交 | 日期 | 说明 | 影响 |
| --- | --- | --- | --- | --- |
| 1 | `1e81b51` | 2026-10-01 | Initial commit | 仓库初始化 |
| 2 | `987aeda` | 2026-10-01 | init from TeamWin/android_device_xiaomi_munch | 导入上游设备树：绝大部分文件、`prebuilt/Image.gz-dtb`、keymaster/gatekeeper HAL、vibratorfeature HAL |
| 3 | `3433b29` | 2026-10-01 | 更新设备树以支持小米 Redmi K40S，移除不必要的解密支持 | 改 `BoardConfig.mk` / `device.mk` / `init.recovery.qcom.rc` / `twrp_munch.mk`，移除 qcom_decrypt 路线 |
| 4 | `475b67b` | 2026-10-02 | 移除不必要的 64 位绑定器支持，调整 boot 镜像构建以支持 recovery-as-boot | 定下 recovery-as-boot |
| 5 | `f9ad63f` | 2026-10-02 | docs: align README build command with AndroidProducts lunch target | 文档 |
| 6 | `d602e12` | 2026-10-02 | 修复 vbmeta_system 的 A/B 分区配置；新增 .gitattributes | 换行符规范化 |
| 7 | `fc41a90` | 2026-10-02 | `TW_DEVICE_VERSION` 改为 `AviderMin` | TWRP 版本串 |
| 8 | `ea83deb` | 2026-10-02 | .gitignore 新增 `log/` | 忽略日志 |
| 9 | `62b952e` | 2026-10-02 | 修复 recovery 内的 QTI 安全服务与振动 HAL 依赖 | QTI 服务声明 + 振动 HAL 依赖 |
| 10 | `a709477` | 2026-10-02 | 删除 `prebuilt/Image.gz-dtb`，新增 `prebuilt/Image` | 内核镜像改名 |
| 11 | `3f4367c` | 2026-10-02 | `BoardConfig.mk` 改用 `Image` 并更新路径 | 内核命名 |
| 12 | `81baea0` | 2026-10-02 | 更新 .gitattributes / README / .gitignore | 文档与属性 |
| 13 | `c89bbbb` | 2026-10-02 | Refactor：rc/fstab/flags 调整 | HAL 二进制从 `system/bin` 移到 `vendor/bin`，补 `keymasterd`、`libkeymasterprovision.so`、`vendor.display.config@1.0.so`、`vendor.qti.hardware.qseecom@1.0.so` |
| 14 | `d6bf374` | 2026-10-02 | 新增 `TW_FRAMERATE := 120` | 帧率 |
| 15 | `a9ac5a9` | 2026-10-02 | Refactor：rc/fstab 调整 | 新增 `vendor.display.config@2.0.so` |
| 16 | `784098a` | 2026-10-02 | 优化初始化过程，提前挂载调制解调器分区以支持密钥管理服务 | modem 提前挂载（后被 5.5 推翻结论） |
| 17 | `c330069` | 2026-10-02 | 优化调制解调器分区挂载过程，调整等待条件以支持安全服务 | wait 条件调整 |
| 18 | `2c68df0` | 2026-10-02 | 新增 Qualcomm 安全堆栈的 ueventd 规则 | 新增 `recovery/root/vendor/etc/ueventd.rc` |
| 19 | `4e7936a` | 2026-10-02 | 优化 ueventd 规则，调整固件目录以支持更快的密钥管理服务 | 固件目录调整 |
| 20 | `de50261` | 2026-10-02 | Add new keymaster firmware images and metadata files | 新增 27 个 keymaster MBN 分段 |
| 21 | `a745930` | 2026-10-02 | 更新 Keymaster 补丁级别以支持 FBE 元数据解密 | patch level 第一次调整 |
| 22 | `145e1e1` | 2026-10-02 | 移除过时的 Keymaster 补丁级别注释，更新系统属性以支持 FBE 元数据解密 | 收敛到最终方案（5.2） |
| 23 | `c972f34` | 2026-10-03 | Implement structural updates and optimizations | 新增 `vendor.awa.wavelib.so`；修 `init.recovery.qcom.rc` 与 `twrp.flags` |
| 24 | `c3678b0` | 2026-10-03 | 更新 README，完善设备信息和功能状态，修复 persist 挂载、USB OTG 与触摸固件处理 | 5.4 / 5.7 落地 |
| 25 | `d2fe0c4` | 2026-10-03 | 禁用振动特性 HAL 服务并调整启动顺序以确保依赖条件满足 | 给 vibratorfeature 加 `disabled` + 属性门 |
| 26 | `478cb96` | 2026-10-03 | 更新振动 HAL 服务的环境变量设置，以避免版本化符号错误 | 给 vibratorfeature 加 `LD_LIBRARY_PATH` |
| 27 | `8f681a2` | 2026-10-03 | 新增振动 HAL 兼容库以修复线程所有权问题 | 新增 `vibrator/Android.bp` + `vibrator/ThreadCompat.cpp` |
| 28 | `6911337` | 2026-10-03 | 更新 README，修正振动 HAL 状态描述，新增 VINTF 清单以支持 AIDL 注册 | 新增 `recovery/root/system/etc/vintf/manifest/vibratorfeature.xml` |
| 29 | `285450c` | 2026-10-03 | Revert "更新 README…新增 VINTF 清单…" | 回滚 28 的清单 |
| 30 | `ed4b131` | 2026-10-03 | .gitignore 新增 `.agent-teams/` 与 `%SystemDrive%/` | 忽略 |
| 31 | `21b56e6` | 2026-10-03 | Refactor code structure | 尝试 QTI 振动器路线：新增 `vendor.qti.hardware.vibrator.service`、`vibrator.default.so`、`libqtivibratoreffect.so`、`vendor.qti.hardware.vibrator.impl.so` 与 `AUDIT_REPORT.md` |
| 32 | `6745bdf` | 2026-10-03 | Revert "Refactor code structure…" | 回滚 31 的 QTI 振动器路线 |
| 33 | `7071440` | 2026-10-03 | 移除与小米振动器 HAL 相关的代码和配置文件 | **整体移除振动 HAL 路线**（见 5.8） |
| 34 | `c95e7c5` | 2026-10-03 | 修复 `/firmware` 挂载失败：等待真实 modem 分区、超时 60 s、`slotselect` | 5.5 落地；同时清掉 `on fs` 里整块振动 sysfs 权限 |
| 35 | `0129b0d` | 2026-10-03 | Implement code changes to enhance functionality and improve performance（HEAD） | 新增 `recovery/root/vendor/firmware/focaltech_ts_fw.bin`（113092 B，与内核内嵌固件同哈希，见 5.6） |

**当前工作区状态**：`HEAD = 0129b0d`，分支 `yarp-16`，`git status` 干净，无未提交改动。

---

## 11. 排障

日志位置：

| 来源 | 位置 | 说明 |
| --- | --- | --- |
| TWRP 主日志 | `/tmp/recovery.log`（TWRP 界面里也可以直接复制到存储） | TWRP 自身行为、分区解析 |
| 内核 | `dmesg` | 分区探测、UFS、FTS 触摸、aw8697 |
| Android | `logcat` | HAL、keystore2、vold |

仓库里保留的历史现场日志（`.gitignore` 忽略，仅本地存在）：`log/dmesg.log`（约 245 KB）、`log/logcat.txt`（约 709 KB）、`log/recovery.log`（约 38 KB）。本文档中引用的 5.2 / 5.4 / 5.5 / 5.8 证据都来自它们。

关键字速查：

```
Unable to decrypt metadata encryption   -> 解密链（见 5.2）
KeyMint upgraded ... left unchanged     -> TA 运行时升级，正常
status: -62 / INVALID_ARGUMENT          -> patch level 不匹配（见 5.2）
Unable to find partition for path       -> TWRP 分区表缺项（见 5.4）
Failed to mount '/firmware'             -> 节点名/slotselect（见 5.5）
request_module fs-auto / no fs?         -> fstype auto（见 5.7）
fw version in tp: , host:               -> 面板固件与内核不一致，会重刷（见 5.6）
RefBase : incStrongRequireStrong()      -> 旧 HAL Thread 所有权问题（历史，见 5.8）
CANNOT LINK EXECUTABLE ... ndk_platform -> 缺 AIDL platform-NDK 后端（历史，见 5.8）
SELinux : Context u:object_r:... unmapped -> persist 挂载时 restorecon 噪音，忽略
Fatal signal 6                          -> 往上找崩溃点真正的那一行
request_firmware / firmware_directories -> 固件搜索路径（见 5.3、5.6）
```

---

## 12. 许可与致谢

* 本仓库：GPL-2.0，见 [LICENSE](LICENSE)。
* [TeamWin/android_device_xiaomi_munch](https://github.com/TeamWin/android_device_xiaomi_munch)（原始设备树）。
* [SebaUbuntu android_device_generator-twrp](https://github.com/SebaUbuntu/android_device_generator-twrp)（骨架）。
* [TWRP-Test/platform_manifest_twrp_aosp](https://github.com/TWRP-Test/platform_manifest_twrp_aosp)（TWRP 16.0 清单）。
* [lingqiqi5211/twrp_device_xiaomi_sm8750@aaa74ed](https://github.com/lingqiqi5211/twrp_device_xiaomi_sm8750/commit/aaa74ed11b18d69a4ba17976803f184b66ab1517)（persist 挂载思路）。

