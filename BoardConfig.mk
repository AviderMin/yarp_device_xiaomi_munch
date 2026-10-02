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
BOARD_KERNEL_IMAGE_NAME := Image.gz-dtb
TARGET_PREBUILT_KERNEL := $(DEVICE_PATH)/prebuilt/Image.gz-dtb
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

# AVB
BOARD_AVB_ENABLE := true

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
TW_BACKUP_EXCLUSIONS := /data/fonts

TW_STATUS_ICONS_ALIGN := center
TW_CUSTOM_CPU_POS := "50"
TW_CUSTOM_CLOCK_POS := "340"
TW_CUSTOM_BATTERY_POS := "800"

# TWRP Debug Flags
# TWRP_EVENT_LOGGING := true
TWRP_INCLUDE_LOGCAT := true
TARGET_USES_LOGD := true