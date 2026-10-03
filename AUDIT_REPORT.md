# t5 最终汇总：munch TWRP 设备树只读审查结论
汇总对象：t1[boot]/t2[build]/t3[crypto] 三份已完成审查 + captain 校验要求。只读汇总，未写文件、未编译、未刷机（工作区仅 .agent-teams/ 未跟踪，HEAD=285450c）。所有行号可复核。

## 0. 本次汇总新做的交叉核验（只读，WSL 源码树）
- 确认 VintfObjectRecovery.cpp:48-69：注释明写 "All manifests are installed under /system/etc/vintf"，读取 kSystemManifest + kSystemManifestFragmentDir（=/system/etc/vintf/manifest/*.xml），fragment 失败直接 return ⇒ 不读 /vendor/etc/vintf，且"要么全好要么全废"成立。
- 确认 mkbootimg.py:114-135 的 write_header_v3_and_above 只写 magic/kernel_size/ramdisk_size/os_version/header_size/reserved/header_version/cmdline，**不含 base/pagesize/kernel_offset 字段**；:194-197 header_version∈{3,4} 直接转该函数 ⇒ v0-v2 参数被静默忽略。captain 校验点 1 成立。
- 确认 build/make/core/Makefile:1305/:1438/:2852 只透传 $(INTERNAL_AVB_BOOT_SIGNING_ARGS)，而 `grep -rn INTERNAL_AVB_BOOT_SIGNING_ARGS build/make/` 仅命中这三处消费点、**无任何定义** ⇒ 展开为空；本树 BoardConfig.mk:64-65 只有 BOARD_AVB_ENABLE := true，无任何 BOARD_AVB_BOOT_KEY_PATH/ALGORITHM。avbtool.py:4234-4236 --algorithm 默认 'NONE'，:3255 `if algorithm_name != 'NONE'` 才签名，:3580-3600 按 --partition_size 用 DONT_CARE 垫到末尾并写 footer ⇒ boot.img 为**无签名 hash footer**、恒为 192 MiB（= BOARD_BOOTIMAGE_PARTITION_SIZE 201326592）。captain 校验点 2 成立。
- 确认 BOARD_SYSTEMIMAGE_PARTITION_TYPE 在 build/make/core/{Makefile,board_config.mk} 零命中，全树只在 device/xiaomi/munch/BoardConfig.mk:70 出现 ⇒ 死变量成立；BOARD_QTI_DYNAMIC_PARTITIONS_SIZE 同（t2 已作用域 grep）。
- 未复核：stock vendor_boot 头部内容、启动链实际装载地址、avbtool 未签名产物在设备的校验行为（无镜像、无实机）。

## 1. 分级总表
| ID | 严重度 | 证据等级 | 结论 |
| --- | --- | --- | --- |
| C1 振动 HAL 无限 crash-loop | 高 | 已证实（logcat 行号） | 当前设备树唯一的实机功能缺陷 |
| C2 VINTF 片段装配"要么全好要么全废" | 高 | 源码路径推断，未实机复现 | 解释崩溃放大面，非本次事故根因证据 |
| C3 fastboot 回归 | 中 | 机制已证实 / 触发者未知 | 无失败版本日志，不得确定根因 |
| C4 /firmware 等待 30 s 超时与 README 结论相反 | 高（文档+体验） | 已证实（dmesg/logcat 行号） | 文档结论错误 + 每次开机固定白等 30 s |
| C5 vendor_boot/dtbo 未纳入构建 | 中（边界/维护） | 已证实（配置缺失+分区实测） | 外部依赖，不是当前缺陷；只建议文档化 |
| C6 镜像类型死变量与 erofs 不一致 | 中 | 已证实（零消费者） | 本目标不产出 system/vendor 镜像，只修命名/注释 |
| C7 boot header 配置 | 信息 | 已证实（源码） | 配置正确；t2 原 F4 的 base/pagesize 风险不适用 |
| C8 AVB 配置 | 低（可见性） | 已证实（源码） | 无签名 hash footer + 体积断言；不是 testkey 签名 |
| C9 README 行号/引用/机制表述类文档问题 | 低-中 | 已证实 | 纯文档修正，不动代码 |
| C10 rc 权限块重复与无关路径 | 低 | 已证实 | 无害（recovery permissive），仅文档标注 |
| C11 ueventd 固件目录不一致 | 信息 | 已证实（实测序列） | 当前不影响功能 |
| C12 gatekeeper AIDL 未找到 | 信息 | 已证实（logcat:3427） | 与 C1 同类；HIDL 1.0 已注册，解密不受影响 |
| C13 构建/证据可复现性 | 中 | 已证实 | out/ 为 10-03 中断残留、无 boot.img，不得据此断言当前镜像依赖已验证 |
| 保护项 | — | 已证实 | 解密/持久化/属性配置与日志一致，禁止无证据改动 |

## 2. 发现明细

### C1 [高｜已证实] 振动 HAL 无限 crash-loop、振动功能为 0
- 机制：libbinder NDK AServiceManager_addService → recovery servicemanager 只读 /system/etc/vintf/manifest.xml + /system/etc/vintf/manifest/*.xml（system/libvintf/VintfObjectRecovery.cpp:48-69；ServiceManager.cpp:76-96 `#ifdef __ANDROID_RECOVERY__`）→ 查不到实例返回非 OK → HAL 侧 CHECK 失败 abort → 服务无 oneshot 被 init 反复重生。
- 证据：recovery/root/system/etc/vintf/manifest.xml（149 行）无该 AIDL；唯一声明在 recovery/root/vendor/etc/vintf/manifest/vendor.xiaomi.hardware.vibratorfeature.service.xml:28-33（fqname :31，recovery 不读该路径）；log/logcat.txt:2314 "Could not find android.hardware.vibrator.IVibrator/vibratorfeature in the VINTF manifest. No alternative instances declared in VINTF."（Caller pid=659 uid=1000）；:2305 "F … Check failed: STATUS_OK == AServiceManager_addService(...)"；:2307 SIGABRT pid 659；:3372/:3377、:4259/:4264、:4354/:4359 多轮重生；:4370-4371 init "received signal 6" + "Sending signal 9"。
- 交叉引用：t3 R8 的 logcat:2314 与本文 C1 是同一行证据；t2 F6（构建期依赖闭合，BoardConfig.mk:52-62、device.mk:66-77、bootable/recovery/prebuilt/Android.mk:376-393）说明问题**不在打包层**，而在 VINTF 声明位置与运行时时序。
- 修复候选（需用户确认，未验证）：(a) 片段改放 recovery/root/system/etc/vintf/manifest/（被读取的 system/etc 路径）；(b) 改用上游 sm8750 的 hal-launch.sh / bind /odm 方案。
- 验证方法：新 boot 的 `logcat -b all -d` 无 CHECK/SIGABRT、服务不重生；`service list` 出现 IVibrator/vibratorfeature；日志出现 Found … in recovery VINTF manifest 而非 Could not find。
- 编译/实机：需要两者。

### C2 [高｜源码路径推断] 片段装配"要么全好要么全废"
- 机制/行号：addDirectoryManifests 任一条目失败即 `if (err != OK) return err;`（system/libvintf/VintfObject.cpp:234-262）；fetchOneHalManifest 解析失败返回非 OK 且不写 out（:435-443）；fetchRecoveryHalManifest 传播错误（VintfObjectRecovery.cpp:48-69，本次已直接复核）→ 整份 recovery 清单加载失败 → ServiceManager.cpp:100-110 打 "NULL VINTF MANIFEST!" → 所有 HAL addService 被拒。
- 重要更正（相对 t1 措辞）：该机制**不能**用来解释"加片段导致 fastboot 重启"，因为 recovery 根本不读 /vendor/etc/vintf，历史上的 system/etc 片段已被 285450c 回退；本次事故也没有清单加载失败日志。它说明的是"若把片段放错位置/写坏，代价是全 HAL"。
- 验证方法：本地以 libvintf 走等价路径断言合并后含目标 AIDL 实例；实机对照 Found/Could not find。
- 编译/实机：验证需要编译。

### C3 [中｜机制已证实、触发者未知] 首屏后重启至 fastboot
- 已证实机制：bootonce-bootloader 只由 `reboot,bootloader` 写入——system/core/init/reboot.cpp:918-925 → bootable/recovery/bootloader_message/bootloader_message.cpp:229-240（全树唯一写点；boot-recovery :200-226、boot-fastboot reboot.cpp:952-965）；bootloader 读到即进 fastboot。设备上确实残留过该命令：log/recovery.log:16 与 log/logcat.txt:2317 "Boot command: bootonce-bootloader"。TWRP 只对 boot-fastboot/boot-rescue 加参数（bootable/recovery/recovery_main.cpp:174-183），对 bootonce-bootloader 不置 fastboot，故该次 recovery 正常启动。
- 明确不得下结论：无失败版本日志（log/boot_crash_logcat.txt 0 字节，10/3 12:40:38）、无 pstore，**不能确定本次 fastboot 重启的根因**；VINTF 片段是纯 XML，无法自行启动 TWRP UI 或触发 reboot（推测触发者为用户/工具执行 reboot-to-bootloader 或 BCB 残留）。
- 需要补的证据：本次 boot 的 `logcat -b all -d` + dmesg + pstore（含 pmsg/console-ramoops），以及 bootloader 侧是否有 `bootonce` 标记。
- 编译/实机：无需编译，需一次可复现的实机抓取。

### C4 [高｜已证实，文档+开机体验] /firmware 等待 30 s 超时与 README 已修结论相反
- 证据：log/dmesg.log:1972-1973 init: wait for '/dev/block/bootdevice/by-name/modem' timed out and took 30008ms；失败动作指向 init.recovery.qcom.rc:62（该 rc 已是 wait 30 版本）；log/logcat.txt:2068-2069 同内容；/firmware 实际由 TWRP 按 recovery/root/system/etc/twrp.flags:33 挂上（log/recovery.log:866 /firmware 448 MB，Mount_To_Decrypt/IsPresent）；全 log/ 中 10005 命中 0（README.md:305/:330 的自检关键字永久失效）。
- 交叉引用：t3 R1；README.md:33/:253/:255/:257/:278/:285 与 init.recovery.qcom.rc:57-62 注释（仍写 10 s/实测 12.2 s）需改。
- 修复候选（未验证）：把 by-name 等待从 on fs 阻塞链摘掉，或声明 /firmware 交给 TWRP 自己挂；**先不要动** twrp.flags:33 与 rc:75-79。
- 编译/实机：改变 rc 需编译+实机验证；仅改文档不需要。

### C5 [中｜已证实] vendor_boot / dtbo 未纳入构建（外部依赖）
- 事实：BoardConfig.mk 全文无 BOARD_VENDOR_BOOTIMAGE_PARTITION_SIZE / BOARD_PREBUILT_VENDOR_BOOTIMAGE / BOARD_VENDOR_RAMDISK_*，也无 BOARD_PREBUILT_DTBOIMAGE；device.mk:21-31 AB_OTA_PARTITIONS 含 vendor_boot；recovery/root/system/etc/twrp.flags:8 暴露 /vendor_boot 可刷写；log/recovery.log:974 实测 /vendor_boot 96.0 MB。
- 判定：这是**边界/外部依赖**，不是当前启动缺陷（本次 boot 只写 boot.img 即自洽，日志证明能进 TWRP）；风险仅在"有人按常规补 BOARD_BOOT_HEADER_VERSION(≥3) 使 BUILDING_VENDOR_BOOT_IMAGE 变真"时出现（build/make/core/board_config.mk:1045-1063 才做一致性校验，现在静默跳过）。
- 修复候选：只在文档中写明"本树只产出 boot.img，vendor_boot/dtbo 由出厂分区提供，禁止单独刷写"；**不建议补齐构建**（无法验证）。
- 编译/实机：纯文档，无需编译。

### C6 [中｜已证实] 镜像类型声明与出厂格式不符，其中一条是死变量
- 事实：BoardConfig.mk:70 BOARD_SYSTEMIMAGE_PARTITION_TYPE（正确名为 BOARD_SYSTEMIMAGE_FILE_SYSTEM_TYPE）无任何消费者（build/make/core/{Makefile,board_config.mk} 零命中，全树只在 :70 出现）；:71 BOARD_VENDORIMAGE_FILE_SYSTEM_TYPE := ext4、:78 BOARD_QTI_DYNAMIC_PARTITIONS_SIZE 亦无消费者；stock/config/config.json pd_repack_state=erofs、recovery.fstab:38-47 以 erofs 为首选 fstype，实测逻辑分区挂载成功。
- 判定：本构建目标不产出 system/vendor 镜像，属占位/误导；**不建议为匹配 stock erofs 盲改**（无法验证产物）。
- 修复候选：删除/改名 :70，或在 :71/:78 加"仅占位、不参与打包"注释。
- 编译/实机：纯配置注释，不需实机。

### C7 [信息｜已证实] boot header 配置正确（t2 原 F4 风险不适用）
- 事实：BoardConfig.mk:39-50 通过 BOARD_MKBOOTIMG_ARGS += --header_version 3 指定版本，且未定义 BOARD_BOOT_HEADER_VERSION；mkbootimg.py:114-135 的 v3+ 头部不含 base/pagesize/kernel_offset，v0-v2 参数被静默忽略（:194-197）；BOARD_KERNEL_CMDLINE 为空配合 mkbootimg 默认 --cmdline '' 无副作用；twrpfastboot=1 经 vendor/twrp/config/BoardConfigTWRP.mk:4-10 落在 INTERNAL_KERNEL_CMDLINE（消费方 bootable/recovery/kernel_module_loader.cpp:26-30、system/core/init/first_stage_init.cpp:116），因 header_version∈{3,4} 时 Makefile:1325-1345 才写入 boot.img 头外的 cmdline 段，故配置自洽。
- 残留边界：实际装载地址/页大小由 stock vendor_boot 头部与启动链决定，未复核（见第 4 节未知项）。
- 修复候选：README.md:115 "twrpfastboot=1 land in no image at all" 措辞改为"会落到未被构建/刷写的 vendor_boot.img"。

### C8 [低｜已证实] AVB：无签名 hash footer + 体积断言
- 事实：BOARD_AVB_ENABLE := true（BoardConfig.mk:65）触发 Makefile:1367-1385 build_boot_from_kernel_avb_enabled → avbtool add_hash_footer --partition_size <boot 分区>；INTERNAL_AVB_BOOT_SIGNING_ARGS 全树无定义 ⇒ 无 --key/--algorithm ⇒ avbtool.py:4234-4236 默认 NONE、:3255 跳过签名；:3580-3600 按分区尺寸垫尾并写 footer ⇒ 产物恒 192 MiB。**不是"默认 test key 签名"**（t2 原 F5 更正）；vbmeta.img 不在 bootimage 目标内，testkey 与该产物无关。
- 影响：无签名 footer 对"刷入后能否引导"无正面作用，只影响 AVB 校验路径；正面作用是 assert-max-image-size 体积断言。
- 修复候选：仅加注释说明；如需关闭 AVB 需另行评估（不在本次建议内）。

### C9 [低-中｜已证实] README 证据与行号问题（同一类：只改文档）
- t3 R2 README.md:122 引用不存在的 log/live/logcat_all.txt:2524-2558（仓库无 log/live/，相关关键字全 log/ 0 命中）；t3 R3 README.md:107/:233 自相矛盾（metadata 实为 recovery.fstab:50，:58 是注释掉的 persist，:63 是 modem）；t3 R4 README.md:245 的 Is_Mounted_By_Path 机制解释与唯一相关日志相反（rc:79 bind 已执行，见 dmesg.log:1984；结果正常，不改代码）；t3 R5 日志无法溯源到 commit（RTC 1972、ro.vendor.build.date.utc 被 TWRP 置 0，README.md:188/:205 的 06-18/14:55 引用不可核验）；t3 R6 README.md:173-178/:207/:217/:274-275 行号大范围过期（真实：qseecomd rc:142、keymasterd rc:151、keymaster-4-0 rc:159、gatekeeper-1-0 rc:168、属性门 rc:181-187、disabled rc:134、LD_LIBRARY_PATH rc:131、device.mk:97-98）；t2 F3 README.md:115 措辞问题（见 C7）。
- 修复候选：只更新 README，不动任何配置。

### C10 [低｜已证实] rc 权限块重复与无关路径
- recovery/root/init.recovery.qcom.rc:94-117：:98-101 对 /sys/bus/i2c/drivers/aw8697_haptic/2-005a/custom_wave 重复 chown/chmod 两轮；同时授权 aw8697_haptic/*、awinic_haptic/*、/sys/class/qcom-haptics/{lra_calibration,lra_impedance}。实测生效驱动目录是 awinic_haptic（log/logcat.txt:1097、:2295 使用 /sys/bus/i2c/drivers/awinic_haptic/3-005a/custom_wave）；全 log/ 中 qcom-haptics 命中 0；SELinux 对 custom_wave 存在 write 拒绝但 permissive=1 放行（logcat:2298）。无害；仅文档标注实际生效项。

### C11 [信息｜已证实] ueventd 固件目录
- recovery/root/ueventd.rc:31 firmware_directories /vendor/firmware_mnt/image/，但实测搜索序列为 /etc/firmware、/odm/firmware、/vendor/firmware、/firmware/image、/firmware/image（重复），未出现 /vendor/firmware_mnt/image（log/dmesg.log:2036-2040）；TA 实际由 libkeymasterdeviceutils.so 硬编码 /vendor/firmware_mnt/image 加载（log/logcat.txt:2343 QSEE app 已加载 + 解密成功）。当前不影响功能，不建议改代码。

### C12 [信息｜已证实] gatekeeper AIDL 未找到 = 与 C1 同类
- log/logcat.txt:3427 Caller(pid=644,uid=0) "Could not find android.hardware.gatekeeper.IGatekeeper/default in the VINTF manifest"；HIDL 1.0 gatekeeper 已注册（:2278）并被解密使用，故解密成功不受影响。t3 的"servicemanager 在 recovery 下是否读取 /vendor/etc/vintf/manifest/ 子目录"疑问在此解决：recovery 只读 /system/etc/vintf（本次源码复核 C6 节），故放 /vendor 的声明一律无效——这也解释了 C1 的振动 AIDL 症状与 C2 的"片段放错位置无救"结论。

### C13 [中｜已证实] 可复现性与证据等级
- WSL out/ 为 2026-10-03 12:50 启动、13:09 中断的残留（out/error.log 0 字节、无 boot.img），对应更早树状态；仓库与 ~/.bash_history 无 pack/flash 脚本（只有 `mka bootimage`）。**不得用该残留断言当前镜像依赖已验证**。log/ 与 stock/ 均未被 git 跟踪（.gitignore:36-37），不能保证与失败版本一致。保留日志的构建指纹矛盾（ro.vendor.build.date=Fri Oct 2 23:47:09 CST 2026 vs logcat:2299 的 MunchVibratorCompat 需要 8f681a2@10-03 12:13）。

## 3. 已核实正常 / 保护边界（本次不建议改动）
- 解密与持久化：recovery/root/system/etc/recovery.fstab:50（metadata wrappedkey）、:53（userdata aes-256-xts:aes-256-cts:v2+inlinecrypt_optimized+wrappedkey_v0、keydirectory=/metadata/vold/metadata_encryption）、:58（保持注释的 persist）、:63（modem）；recovery/root/system/etc/twrp.flags:31/:32/:33/:36；init.recovery.qcom.rc:62、:75-79（persist bind）、:131/:134/:135/:142/:151/:159/:163/:168/:172/:181-187；BoardConfig.mk:91-92（安全补丁 2099-12-31，与 log/recovery.log:288/:566 一致）；system.prop（vendor.gatekeeper.disable_spu=true 确被 gatekeeper HAL 消费）。
- 实测与配置一致：FBE 参数（log/recovery.log:74-80）、keymaster 4.0 版本判定（log/recovery.log:134-135，vendor/etc/vintf/manifest.xml:80-89）、QTI 安全链拉起（logcat:2082/:2278/:2354、recovery.log:563）、TA 齐备（vendor/firmware_mnt/image 下 27 个文件）。
- 构建侧：BoardConfig.mk:52-62 NEED_AIDL_NDK_PLATFORM_BACKEND、device.mk:66-77 RECOVERY_LIBRARY_SOURCE_FILES 的 AIDL NDK platform 变体确实生成、HAL 全部 SONAME 已在 ramdisk；BoardConfig.mk:69/:77 分区尺寸与 stock config.json 完全一致（log/recovery.log:745/:1020）。
- 上述任一项若被后续改动触及，必须附新的实机日志证据。

## 4. 最终行动清单（全部为待用户确认候选，无"立即改代码"项）
优先级 1（高）：C1 振动 HAL 崩溃循环。候选：片段改放 /system/etc/vintf/manifest/ 或走 hal-launch.sh/bind /odm。需编译+实机验证；不触及保护项。
优先级 2（高）：C3 补一次可复现的实机抓取（logcat -b all -d + dmesg + pstore + bootloader 侧 bootonce 标记）。无需编译；在拿到证据前不得归因。
优先级 3（高，体验+文档）：C4。文档必须先更正（README.md:33/:253/:255/:257/:285/:305/:330 与 rc:57-62 注释）；rc 阻塞链调整属候选，需编译+实机，且不得动 twrp.flags:33。
优先级 4（中，文档）：C9 全部 README 行号/引用修正、C5 vendor_boot/dtbo 策略说明、C6 死变量命名/注释、C7 README:115 措辞、C8 AVB 注释、C10/C11 标注。全部无需编译、无需实机、不动代码。
优先级 5（信息，留待后续）：C2 的"全有或全无"若要验证需构建等价断言；C13 的构建指纹补齐（未来日志随附 ro.build.fingerprint / version.incremental）。

## 5. 遗留未知项（明确不可下结论）
1) fastboot 回归触发者未知：log/boot_crash_logcat.txt 为 0 字节，缺本次 boot 的 logcat -b all -d、dmesg、pstore；在补齐前不得判定根因。
2) coldboot 约 30 s 的真实阻塞点未知：LUN 已在 t≈1.08 s 枚举完、固件请求在 ~32.4 s 才被处理（log/dmesg.log:779-792、:2035-2041），仓库日志不足以定位 ueventd 侧阻塞点，需实机 strace/ueventd 日志。
3) 振动修复未编译、未实机验证（且 ThreadCompat 的 1<<28 启发式、dlsym(RTLD_NEXT) 失败静默返回 INVALID_OPERATION 均在 t1 F5，属未验证风险）。
4) 保留日志对应的确切 commit 未知（RTC 不可信、指纹被覆盖）；WSL out/ 残留不能证明当前镜像依赖。
5) key blob 内 tag 数值（README:134-139）无仓库副本，无法离线复核；/mnt/vendor/persist/haptics 校准文件是否真被 HAL 读取未验证。
6) stock vendor_boot 头部内容与启动链实际装载地址未复核（C7 边界）。