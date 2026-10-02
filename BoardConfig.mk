#
# Copyright (C) 2022 The Android Open Source Project
# Copyright (C) 2022 SebaUbuntu's TWRP device tree generator
#
# SPDX-License-Identifier: Apache-2.0
#

DEVICE_PATH := device/xiaomi/munch

# For building with minimal manifest
ALLOW_MISSING_DEPENDENCIES := true

# Architecture
TARGET_ARCH := arm64
TARGET_ARCH_VARIANT := armv8-a
TARGET_CPU_ABI := arm64-v8a
TARGET_CPU_ABI2 :=
TARGET_CPU_VARIANT := generic

TARGET_2ND_ARCH := arm
TARGET_2ND_ARCH_VARIANT := armv7-a-neon
TARGET_2ND_CPU_ABI := armeabi-v7a
TARGET_2ND_CPU_ABI2 := armeabi
TARGET_2ND_CPU_VARIANT := generic
TARGET_BOARD_SUFFIX := _64

# Assert
TARGET_OTA_ASSERT_DEVICE := munch

# Platform
TARGET_BOARD_PLATFORM := kona
TARGET_BOARD_PLATFORM_GPU := qcom-adreno650

# Kernel
TARGET_KERNEL_ARCH := arm64
TARGET_KERNEL_HEADER_ARCH := $(TARGET_KERNEL_ARCH)
BOARD_KERNEL_IMAGE_NAME := Image
TARGET_PREBUILT_KERNEL := $(DEVICE_PATH)/prebuilt/Image
# NOTE: do NOT define BOARD_BOOT_HEADER_VERSION here. Setting it (>= 3) makes AOSP
# set BUILDING_VENDOR_BOOT_IMAGE := true (build/make/core/board_config.mk:521-531),
# which moves the kernel cmdline out of boot.img (Makefile:1334-1348) and makes
# TWRP's twrpfastboot=1 (vendor/twrp/config/BoardConfigTWRP.mk:7) land in no image
# at all. The boot-image header version is only ever taken from here, because
# build/make/core/ never mentions header_version itself - it goes straight to
# mkbootimg via BOARD_MKBOOTIMG_ARGS (Makefile:1299/1398).
# No device-specific kernel arguments are required here; TWRP appends twrpfastboot=1.
BOARD_KERNEL_CMDLINE :=
# TARGET_KERNEL_SOURCE := kernel/xiaomi/munch
# TARGET_KERNEL_CONFIG := munch_defconfig
BOARD_MKBOOTIMG_ARGS += --header_version 3
# Boot header patch level.  The Qualcomm bootloader hands the boot image's
# patch level to the keymaster TA (BOOT_PATCHLEVEL), and the key blob in
# /metadata/vold/metadata_encryption/key was written by a ROM whose boot image
# declared 2025-03 (BOOT_PATCHLEVEL=20250301).  A tree build would otherwise
# stamp INTERNAL_MKBOOTIMG_VERSION_ARGS = PLATFORM_VERSION_LAST_STABLE (16) +
# PLATFORM_SECURITY_PATCH (2025-06-05) into the header (Makefile:1350-1352),
# i.e. a value the TA does not expect.  These arguments are appended after it
# (Makefile:1299/1398, and - through BOARD_RECOVERY_MKBOOTIMG_ARGS,
# Makefile:2779-2781 - the recovery-as-boot path at Makefile:2844), so they win.
BOARD_MKBOOTIMG_ARGS += --os_version 13.0.0 --os_patch_level 2025-03

# AIDL backends
# The stock Xiaomi vibrator HAL is a prebuilt binary shipped in the recovery
# ramdisk (recovery/root/vendor/bin/hw/vendor.xiaomi.hardware.vibratorfeature.service)
# and it links against the platform-NDK flavor of the AIDL vibrator interface.
# Soong only generates that flavor when this flag is set
# (build/make/core/soong_config.mk:320 -> GenerateAidlNdkPlatformBackend); without
# it the HAL dies at startup with
#   CANNOT LINK EXECUTABLE ...: library android.hardware.vibrator-V1-ndk_platform.so not found
# The guard in build/make/core/config.mk:806-810 only rejects this flag for
# PRODUCT_SHIPPING_API_LEVEL >= 36, and this device ships API 31.
NEED_AIDL_NDK_PLATFORM_BACKEND := true

# AVB
BOARD_AVB_ENABLE := true

# Keymaster patch levels for FBE metadata decryption
#
# Keymaster 4.0 requires the four patch-level parameters sent by the HAL
# (OS_VERSION, OS_PATCHLEVEL, VENDOR_PATCHLEVEL, BOOT_PATCHLEVEL) to be
# identical to the ones stored inside the key blob, otherwise begin() returns
# KEY_REQUIRES_UPGRADE (-62) and the TA rejects the upgrade of an already
# older blob with INVALID_ARGUMENT (-38) - which is exactly why TWRP could
# not decrypt /metadata.
#
# The installed ROM's blob records: OS_VERSION 160000 (ro.build.version.release
# = 16, already correct), OS_PATCHLEVEL 202608, VENDOR_PATCHLEVEL 20260801 and
# BOOT_PATCHLEVEL 20250301.
#
# ro.build.version.security_patch is generated from PLATFORM_SECURITY_PATCH,
# which is a read-only release flag in Android 16, so OS_PATCHLEVEL is fixed up
# in system.prop instead.
#
# ro.vendor.build.security_patch comes from VENDOR_SECURITY_PATCH
# (build/make/core/sysprop_config.mk:122).  Nothing in this source tree ever
# assigns VENDOR_SECURITY_PATCH, so the property was empty, the QTI HAL logged
# 'Vendor patchlevel string does not match expected format.  Using patchlevel
# 0' and reported VENDOR_PATCHLEVEL=0.
#
# BOOT_SECURITY_PATCH adds com.android.build.boot.security_patch to the boot
# image's AVB footer (build/make/core/Makefile:4740-4743); for recovery-as-boot
# images that is the footer written with BOARD_AVB_BOOT_ADD_HASH_FOOTER_ARGS
# (Makefile:2852).  Belt and braces for a build that carries an AVB footer;
# it matches the boot header value set above.
#
# Verified on this device: overriding only ro.build.version.security_patch and
# ro.vendor.build.security_patch to 2026-08-01 and restarting
# keymaster-4-0/keystore2 made TWRP log 'Successfully decrypted metadata
# encrypted data partition with new block device' and mount /data, i.e.
# OS_PATCHLEVEL and VENDOR_PATCHLEVEL were the only mismatched parameters.
#
# Keep these two in sync with the ROM that owns the metadata encryption key
# whenever its security patch level changes.
VENDOR_SECURITY_PATCH := 2026-08-01
BOOT_SECURITY_PATCH := 2025-03-01

# File systems
BOARD_HAS_LARGE_FILESYSTEM := true
BOARD_BOOTIMAGE_PARTITION_SIZE := 201326592
BOARD_SYSTEMIMAGE_PARTITION_TYPE := ext4
BOARD_VENDORIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_USERDATAIMAGE_FILE_SYSTEM_TYPE := f2fs
TARGET_USERIMAGES_USE_F2FS := true
TARGET_COPY_OUT_VENDOR := vendor

# Dynamic Partiton
BOARD_SUPER_PARTITION_SIZE := 9126805504
BOARD_QTI_DYNAMIC_PARTITIONS_SIZE := 9126805504
BOARD_SUPER_PARTITION_GROUPS := qti_dynamic_partitions
BOARD_QTI_DYNAMIC_PARTITIONS_PARTITION_LIST := system system_ext product vendor odm

# Recovery
TARGET_RECOVERY_PIXEL_FORMAT := RGBX_8888
TARGET_USES_MKE2FS := true

# System as root
BOARD_ROOT_EXTRA_FOLDERS := bluetooth dsp firmware persist
BOARD_SUPPRESS_SECURE_ERASE := true

# TWRP Configuration
TW_THEME := portrait_hdpi
RECOVERY_SDCARD_ON_DATA := true
TARGET_RECOVERY_QCOM_RTC_FIX := true
TW_DEFAULT_BRIGHTNESS := 500
TW_MAX_BRIGHTNESS := 2047
TW_FRAMERATE := 120
TW_DEVICE_VERSION := AviderMin
TW_EXTRA_LANGUAGES := true
TW_SCREEN_BLANK_ON_BOOT := true
TW_INPUT_BLACKLIST := "hbtp_vm"
TW_USE_TOOLBOX := true
TW_INCLUDE_NTFS_3G := true
TW_INCLUDE_REPACKTOOLS := true
TW_INCLUDE_RESETPROP := true
TW_INCLUDE_FASTBOOTD := true
TW_HAS_EDL_MODE := true
# fscrypt policy: Android 13 firmware uses fscrypt policy v2. TWRP 16.0's
# bootable/recovery/libtar/libtar_defaults.go picks v1 only when this is exactly
# "1"; any other value (incl. 2) selects v2, i.e. 2 == default == what we want.
TW_USE_FSCRYPT_POLICY := 2
# Skip APEX loop mounting in recovery. Runtime APEX probes fail on this kernel
# and only add a failed mount attempt before metadata decryption (taro pattern).
TW_EXCLUDE_APEX := true
TW_BACKUP_EXCLUSIONS := /data/fonts

TW_STATUS_ICONS_ALIGN := center
TW_CUSTOM_CPU_POS := "50"
TW_CUSTOM_CLOCK_POS := "340"
TW_CUSTOM_BATTERY_POS := "800"

# TWRP Debug Flags
# TWRP_EVENT_LOGGING := true
TWRP_INCLUDE_LOGCAT := true
TARGET_USES_LOGD := true