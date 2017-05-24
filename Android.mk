LOCAL_PATH := $(call my-dir)
BB_PATH := $(LOCAL_PATH)

# Bionic Branches Switches (GB/ICS/L)
BIONIC_ICS := false
BIONIC_L := true

# Make a static library for regex.
include $(CLEAR_VARS)
LOCAL_SRC_FILES := android/regex/bb_regex.c
LOCAL_C_INCLUDES := $(BB_PATH)/android/regex
LOCAL_CFLAGS := -Wno-sign-compare
LOCAL_MODULE := libregx
include $(BUILD_STATIC_LIBRARY)

# Make a static library for RPC library (coming from uClibc).
include $(CLEAR_VARS)
LOCAL_SRC_FILES := $(shell cat $(BB_PATH)/android/librpc.sources)
LOCAL_C_INCLUDES := $(BB_PATH)/android/librpc
LOCAL_MODULE := libuclibcrpc2
LOCAL_CFLAGS += -fno-strict-aliasing
ifeq ($(BIONIC_L),true)
LOCAL_CFLAGS += -DBIONIC_ICS -DBIONIC_L
endif
include $(BUILD_STATIC_LIBRARY)

#####################################################################

# Execute make prepare for normal config & static lib (recovery)

LOCAL_PATH := $(BB_PATH)
include $(CLEAR_VARS)

BBX_CROSS_COMPILER_PREFIX := $(abspath $(TARGET_TOOLS_PREFIX))

BB_PREPARE_FLAGS:=
ifeq ($(HOST_OS),darwin)
    BB_HOSTCC := $(ANDROID_BUILD_TOP)/prebuilts/gcc/darwin-x86/host/i686-apple-darwin-4.2.1/bin/i686-apple-darwin11-gcc
    BB_PREPARE_FLAGS := HOSTCC=$(BB_HOSTCC)
endif

# On aosp (master), path is relative, not on cm (kitkat)
bb_gen := $(abspath $(TARGET_OUT_INTERMEDIATES)/bbx)

bbx_prepare_full := $(bb_gen)/full/.config
$(bbx_prepare_full): $(BB_PATH)/bbx-full.config
	@echo -e ${CL_YLW}"Prepare config for bbx binary"${CL_RST}
	@rm -rf $(bb_gen)/full
	@rm -f $(shell find $(abspath $(call intermediates-dir-for,EXECUTABLES,bbx)) -name "*.o")
	@mkdir -p $(@D)
	@cat $^ > $@ && echo "CONFIG_CROSS_COMPILER_PREFIX=\"$(BBX_CROSS_COMPILER_PREFIX)\"" >> $@
	make -C $(BB_PATH) prepare O=$(@D) $(BB_PREPARE_FLAGS)

bbx_prepare_minimal := $(bb_gen)/minimal/.config
$(bbx_prepare_minimal): $(BB_PATH)/bbx-minimal.config
	@echo -e ${CL_YLW}"Prepare config for libbbx"${CL_RST}
	@rm -rf $(bb_gen)/minimal
	@rm -f $(shell find $(abspath $(call intermediates-dir-for,STATIC_LIBRARIES,libbbx)) -name "*.o")
	@mkdir -p $(@D)
	@cat $^ > $@ && echo "CONFIG_CROSS_COMPILER_PREFIX=\"$(BBX_CROSS_COMPILER_PREFIX)\"" >> $@
	make -C $(BB_PATH) prepare O=$(@D) $(BB_PREPARE_FLAGS)


#####################################################################

LOCAL_PATH := $(BB_PATH)
include $(CLEAR_VARS)

KERNEL_MODULES_DIR ?= /system/lib/modules

SUBMAKE := make -s -C $(BB_PATH) CC=$(CC)

BBX_SRC_FILES = \
	$(shell cat $(BB_PATH)/bbx-$(BBX_CONFIG).sources) \
	android/libc/mktemp.c \
	android/libc/pty.c \
	android/android.c

BBX_ASM_FILES =
ifneq ($(BIONIC_L),true)
    BBX_ASM_FILES += swapon.S swapoff.S sysinfo.S
endif

ifneq ($(filter arm arm64 x86 mips,$(TARGET_ARCH)),)
    BBX_SRC_FILES += \
        $(addprefix android/libc/arch-$(TARGET_ARCH)/syscalls/,$(BBX_ASM_FILES))
endif


BBX_C_INCLUDES = \
	$(BB_PATH)/include $(BB_PATH)/libbb \
	bionic/libc/private \
	bionic/libm/include \
	bionic/libc \
	bionic/libm \
	libc/kernel/common \
	external/libselinux/include \
	external/selinux/libsepol/include \
	$(BB_PATH)/android/regex \
	$(BB_PATH)/android/librpc

BBX_CFLAGS = \
	-Werror=implicit -Wno-clobbered -Wno-format-security \
	-DNDEBUG \
	-DANDROID \
	-fno-strict-aliasing \
	-fno-builtin-stpcpy \
	-include $(bb_gen)/$(BBX_CONFIG)/include/autoconf.h \
	'-DCONFIG_DEFAULT_MODULES_DIR="$(KERNEL_MODULES_DIR)"' \
	-DBB_BT=AUTOCONF_TIMESTAMP


ifeq ($(BIONIC_L),true)
    BBX_CFLAGS += -DBIONIC_L
    BBX_AFLAGS += -DBIONIC_L
    # include changes for ICS/JB/KK
    BIONIC_ICS := true
endif

ifeq ($(BIONIC_ICS),true)
    BBX_CFLAGS += -DBIONIC_ICS
endif


# Build the static lib for the recovery tool

BBX_CONFIG:=minimal
BBX_SUFFIX:=static
LOCAL_SRC_FILES := $(BBX_SRC_FILES)
LOCAL_C_INCLUDES := $(bb_gen)/minimal/include $(BBX_C_INCLUDES)
LOCAL_CFLAGS := -Dmain=bbx_driver $(BBX_CFLAGS)
LOCAL_CFLAGS += \
  -DRECOVERY_VERSION \
  -Dgetusershell=bbx_getusershell \
  -Dsetusershell=bbx_setusershell \
  -Dendusershell=bbx_endusershell \
  -Dgetmntent=bbx_getmntent \
  -Dgetmntent_r=bbx_getmntent_r \
  -Dgenerate_uuid=bbx_generate_uuid \
  '-DBB_VER="$(shell cat $(PRODUCT_OUT)/obj/bbx/minimal/.kernelrelease)"'
LOCAL_ASFLAGS := $(BBX_AFLAGS)
LOCAL_MODULE := libbbx
LOCAL_MODULE_TAGS := eng debug
LOCAL_STATIC_LIBRARIES := libcutils libc libm libselinux
LOCAL_ADDITIONAL_DEPENDENCIES := $(bbx_prepare_minimal)
include $(BUILD_STATIC_LIBRARY)


# Static Busybox

LOCAL_PATH := $(BB_PATH)
include $(CLEAR_VARS)
LOCAL_CLANG := false
BBX_CONFIG:=full
BBX_SUFFIX:=static
LOCAL_SRC_FILES := $(BBX_SRC_FILES)
LOCAL_C_INCLUDES := $(bb_gen)/full/include $(BBX_C_INCLUDES)
LOCAL_CFLAGS := $(BBX_CFLAGS)
LOCAL_CFLAGS += \
  -Dgetusershell=bbx_getusershell \
  -Dsetusershell=bbx_setusershell \
  -Dendusershell=bbx_endusershell \
  -Dgetmntent=bbx_getmntent \
  -Dgetmntent_r=bbx_getmntent_r \
  -Dgenerate_uuid=bbx_generate_uuid \
  '-DBB_VER="$(shell cat $(PRODUCT_OUT)/obj/bbx/full/.kernelrelease)"'
LOCAL_ASFLAGS := $(BBX_AFLAGS)
LOCAL_FORCE_STATIC_EXECUTABLE := true
LOCAL_MODULE := bbx
LOCAL_MODULE_TAGS := optional
LOCAL_STATIC_LIBRARIES := libc libcutils libm libregx libuclibcrpc2 libselinux
LOCAL_MODULE_CLASS := EXECUTABLES
LOCAL_MODULE_PATH := $(TARGET_ROOT_OUT_SBIN)
LOCAL_UNSTRIPPED_PATH := $(PRODUCT_OUT)/symbols/utilities
LOCAL_ADDITIONAL_DEPENDENCIES := $(bbx_prepare_full)
LOCAL_PACK_MODULE_RELOCATIONS := false
include $(BUILD_EXECUTABLE)
