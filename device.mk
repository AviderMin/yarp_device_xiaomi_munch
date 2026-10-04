#
# Copyright (C) 2022 The Android Open Source Project
# Copyright (C) 2022 SebaUbuntu's TWRP device tree generator
#
# SPDX-License-Identifier: Apache-2.0
#

LOCAL_PATH := device/xiaomi/munch

# API
PRODUCT_SHIPPING_API_LEVEL := 31

# Dynamic partitions
PRODUCT_USE_DYNAMIC_PARTITIONS := true

# A/B
ENABLE_VIRTUAL_AB := true
BOARD_USES_RECOVERY_AS_BOOT := true
# BOARD_BUILD_SYSTEM_ROOT_IMAGE := false
AB_OTA_UPDATER := true
AB_OTA_PARTITIONS += \
    boot \
    dtbo \
    system \
    system_ext \
    product \
    vendor \
    vendor_boot \
    odm \
    vbmeta \
    vbmeta_system

# A/B
AB_OTA_POSTINSTALL_CONFIG += \
    RUN_POSTINSTALL_system=true \
    POSTINSTALL_PATH_system=system/bin/otapreopt_script \
    FILESYSTEM_TYPE_system=ext4 \
    POSTINSTALL_OPTIONAL_system=true

# Boot control HAL (AIDL/HIDL boot control services come from
# bootable/recovery in TWRP 16.0, which also builds the *.recovery variants)
PRODUCT_PACKAGES += \
    android.hardware.boot@1.1-impl \
    android.hardware.boot@1.1-service

PRODUCT_PACKAGES += \
    otapreopt_script \
    cppreopts.sh \
    update_engine \
    update_verifier \
    update_engine_sideload

# fastbootd
PRODUCT_PACKAGES += \
    fastbootd \
    android.hardware.fastboot@1.0-impl-mock


# Recovery libs
TARGET_RECOVERY_DEVICE_MODULES += \
    libion

RECOVERY_LIBRARY_SOURCE_FILES += \
    $(TARGET_OUT_SHARED_LIBRARIES)/libion.so

# Crypto
TW_INCLUDE_CRYPTO := true
TW_INCLUDE_CRYPTO_FBE := true
TW_INCLUDE_FBE_METADATA_DECRYPT := true
BOARD_USES_METADATA_PARTITION := true

# Platform
# Version/patch-level override strategy (see README 5.2 for the full story):
# - The effective assignments live in BoardConfig.mk's Encryption section:
#   PLATFORM_SECURITY_PATCH / VENDOR_SECURITY_PATCH there are what end up in
#   ro.build.version.security_patch / ro.vendor.build.security_patch
#   (observed in the boot logs of a build made from this tree).
# - Upstream AOSP (android-16.0.0_r1, the tag this TWRP manifest pins) does
#   guard PLATFORM_SECURITY_PATCH / PLATFORM_VERSION_LAST_STABLE with
#   ifdef+$(error) and .KATI_READONLY in build/make/core/version_util.mk, but
#   in the TWRP twrp-16.0 build the direct device-tree assignments above are
#   what take effect; do not assume the upstream guard behaviour transfers
#   when the manifest or branch changes - re-verify with getprop after a
#   full build.
# - VENDOR_SECURITY_PATCH is written out as ro.vendor.build.security_patch by
#   build/make/core/sysprop_config.mk; BoardConfig.mk pins it to the same
#   far-future date so the derived value cannot drift.
# - PLATFORM_VERSION := 99.87.36 below only feeds build props (e.g.
#   ro.build.version.release) for the Keymaster patch-level comparison; it is
#   a build-time value, not a statement about the device.
PLATFORM_VERSION := 99.87.36

