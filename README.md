# yarp_device_xiaomi_munch

TWRP 设备树 — 小米 Redmi K40S（代号 **munch**，型号 **22021211RC**，SM8250/kona，Adreno 650）。

本仓库基于 [TeamWin/android_device_xiaomi_munch](https://github.com/TeamWin/android_device_xiaomi_munch)
导入，并移植到 **TWRP 16.0 / android-16.0.0_r1**（分支 `yarp-16`）。

## 设备信息

| 项目 | 值 |
| --- | --- |
| 设备代号 | munch |
| 市场名称 | Redmi K40S |
| 型号 | 22021211RC |
| SoC | Qualcomm SM8250 (kona) |
| GPU | Adreno 650 |
| 出厂 API | 31 (Android 12) |
| 当前固件基线 | HyperOS OS1.0.15.0.ULMCNXM (Android 13, RKQ1.211001.001) |
| 分区方案 | A/B + 动态分区 (qti_dynamic_partitions, super 9126805504 字节) |

## 构建

前置条件：完整的 TWRP 16.0 源码树（[platform_manifest_twrp_aosp](https://github.com/TWRP-Test/platform_manifest_twrp_aosp) 分支 `twrp-16.0`）。

```bash
repo init --depth=1 -u https://github.com/TWRP-Test/platform_manifest_twrp_aosp.git -b twrp-16.0
repo sync -j8 --force-sync --no-clone-bundle --no-tags

# 把本设备树放到 device/xiaomi/munch
git clone https://github.com/AviderMin/yarp_device_xiaomi_munch.git device/xiaomi/munch

export ALLOW_MISSING_DEPENDENCIES=true
. build/envsetup.sh
lunch twrp_munch
mka bootimage            # 本设备无 recovery 分区：TWRP 的 recovery 资源被并入 boot.img（recovery-as-boot）
```

产物位置：`out/target/product/munch/boot.img`。本设备**没有 recovery 分区**，`BOARD_USES_RECOVERY_AS_BOOT := true`
使 `INSTALLED_RECOVERYIMAGE_TARGET` 为空（`build/make/core/Makefile:283-296`），**不会**产出 `recovery.img`；
TWRP 的 recovery 资源直接打进 boot 镜像，刷机写的是 boot 分区：`fastboot flash boot boot.img`。

## 目录结构

```
BoardConfig.mk             板级配置（编译开关、分区、TWRP 变量）
device.mk                  产品配置（动态分区、A/B、HAL 包、加密）
twrp_munch.mk              lunch 目标 twrp_munch
AndroidProducts.mk         PRODUCT_MAKEFILES 注册
prebuilt/Image.gz-dtb      预编译内核（TARGET_PREBUILT_KERNEL 路线，不源码编译内核）
recovery/root/             recovery ramdisk 覆盖层（init rc、fstab、twrp.flags、stock QTI 二进制）
system.prop
```

## 注意事项

* **FDE 解密不再支持**：TWRP 16.0 上游 README 明确写明 `FDE decryption will not be supported in this branch`，
  本设备树只保留 FBE（`TW_INCLUDE_CRYPTO_FBE`）路线。旧的 `qcom_decrypt` / `qcom_decrypt_fbe` 包与
  `init.recovery.qcom_decrypt.rc` 引用已随移植移除。
* **预编译内核**：内核来自 `prebuilt/Image.gz-dtb`（`TARGET_PREBUILT_KERNEL`），TWRP 16.0 的
  `vendor/twrp/build/tasks/kernel.mk` 仍然支持该路线，不会去编译 `kernel/xiaomi/munch`。
* **VINTF 清单保留**：`recovery/root/{system,vendor}/etc/vintf/manifest*.xml` 来自官方固件转储。
  启动时 TWRP 会扫描 `/vendor/etc/vintf/manifest*.xml` 判定 Keymaster 版本并写入 `TW_KEYMASTER_VERSION_PROP`
  （`bootable/recovery/twrp_functions.cpp` 的 `GetServiceFromManifest` ← `partitionmanager.cpp` 的 `Process_Keymaster_Version`）。
  清单缺失时会回退到 `keymaster_ver` 属性/ramdisk 清单，但保留它仍是解密路径的首选版本判定来源，因此**不要清理**。
* **stock/ 不入库**：`.gitignore` 忽略的 `stock/` 是本地 HyperOS 官方固件转储（约 9.25 GB），
  仅作为 QTI 二进制/清单的来源素材，不属于交付内容。
* **QTI 安全服务**：stock 固件的 `vendor/etc/init/` 下 `android.hardware.keymaster@4.0-service-qti.rc`、
  `android.hardware.gatekeeper@1.0-service-qti.rc` 与 `qseecomd.rc` 都不会被 recovery 导入，因此
  `recovery/root/init.recovery.qcom.rc` 自行声明 `qseecomd`（`on fs` 起）、`keymaster-4-0` 与
  `gatekeeper-1-0`（`on boot` 起），并显式写出 `interface` 行，使 init 能解析
  `ctl.interface_start` 的 lazy-HAL 请求。缺失时表现为
  `android.hardware.keymaster@4.0::IKeymasterDevice/default is not registered`。
* **AIDL 振动后端**：预编译的 `vendor.xiaomi.hardware.vibratorfeature.service` 依赖
  `android.hardware.vibrator-V1-ndk_platform.so`，该后端默认不生成，需在 `BoardConfig.mk`
  打开 `NEED_AIDL_NDK_PLATFORM_BACKEND := true`，并由 `device.mk` 的
  `RECOVERY_LIBRARY_SOURCE_FILES` 收进 recovery 镜像的 `/system/lib64`。
* **recovery 在 boot 里**：本设备没有独立 recovery 分区（`device.mk` 的 `AB_OTA_PARTITIONS` 与 `twrp.flags`
  中都没有 recovery 条目），TWRP 走 recovery-as-boot 路线，recovery 资源并入 `boot.img`；
  boot header v3 通过 `BOARD_MKBOOTIMG_ARGS += --header_version 3` 传给 `mkbootimg`，刷入目标同样是 boot 分区。

## 许可

GPL-2.0（见 [LICENSE](LICENSE)）。
