// SPDX-License-Identifier: Apache-2.0
// Recovery-only compatibility for the stock munch vibrator HAL.
#define LOG_TAG "MunchVibratorCompat"
#include <dlfcn.h>
#include <log/log.h>
#include <utils/Thread.h>

#include <mutex>

namespace {
using Run = android::status_t (*)(android::Thread*, const char*, int32_t, size_t);
constexpr char kRunSymbol[] = "_ZN7android6Thread3runEPKcim";
// RefBase's initial value means no sp<> has ever owned this live object.
// Zero is NOT equivalent: it may mean the last owner has already released it.
constexpr int32_t kInitialStrongValue = 1 << 28;
std::mutex ownerMutex;
char legacyOwner;
}

// Export the arm64 C++ symbol without replacing any system library or using
// a virtual call (which would recurse back into this interposer).
extern "C" __attribute__((visibility("default")))
android::status_t munch_thread_run(android::Thread* thread,
                                              const char* name,
                                              int32_t priority, size_t stack)
        __asm__("_ZN7android6Thread3runEPKcim");

extern "C" __attribute__((visibility("default")))
android::status_t munch_thread_run(android::Thread* thread,
                                              const char* name,
                                              int32_t priority, size_t stack) {
    static const Run original = reinterpret_cast<Run>(dlsym(RTLD_NEXT, kRunSymbol));
    if (original == nullptr) {
        ALOGE("Cannot resolve original Thread::run: %s", dlerror());
        return android::INVALID_OPERATION;
    }
    if (thread == nullptr) return android::BAD_VALUE;
    {
        std::lock_guard<std::mutex> lock(ownerMutex);
        if (thread->getStrongCount() == kInitialStrongValue) {
            // The stock HAL keeps DynamicEffectDevice as a raw pointer and
            // calls run() without establishing an sp<> owner. Android 16
            // Thread::run uses sp<Thread>::fromExisting(this) and aborts.
            // Keep one legacy-owner reference for the HAL process lifetime:
            // dropping it after run() could delete an object the HAL still
            // accesses (or delete it immediately when thread creation fails).
            thread->incStrong(&legacyOwner);
            ALOGI("Established legacy Thread owner for %s", name ? name : "(null)");
        }
    }
    return original(thread, name, priority, stack);
}
