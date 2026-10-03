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
# Android 16 owns the security-patch / last-stable values through release flags:
# RELEASE_PLATFORM_SECURITY_PATCH and RELEASE_PLATFORM_VERSION_LAST_STABLE are
# .KATI_READONLY build flags (build/release/flag_values/<branch>/*.textproto), and
# setting PLATFORM_SECURITY_PATCH / PLATFORM_VERSION_LAST_STABLE directly trips
# the $(error) guards in build/make/core/version_util.mk:55 / :113. The
# VENDOR_SECURITY_PATCH / BOOT_SECURITY_PATCH pair is derived from
# PLATFORM_SECURITY_PATCH by the build system. Only PLATFORM_VERSION itself is
# still overridable from a device tree.
PLATFORM_VERSION := 99.87.36

