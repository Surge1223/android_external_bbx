LOCAL_PATH := $(call my-dir)
BB_PATH := $(LOCAL_PATH)

common_cflags := \
  -Wall -W -Wundef \
  -Wshadow -Wmissing-noreturn \
  -Wmissing-format-attribute \
  -std=gnu99 -O2 -fpic -fPIC \
  -pipe -fno-strict-aliasing \
  -D_GNU_SOURCE  \
  -D__BIONIC__ -DANDROID \
	-D__linux__ \
  -D__ANDROID__

# Make a static library for RPC library (coming from uClibc).
include $(CLEAR_VARS)
LOCAL_SRC_FILES := $(shell cat $(BB_PATH)/android/librpc.sources)
LOCAL_C_INCLUDES := $(BB_PATH)/android/librpc
LOCAL_MODULE := libuclibcrpc
LOCAL_CFLAGS += -fno-strict-aliasing
LOCAL_CFLAGS += -DBIONIC_ICS -DBIONIC_L
include $(BUILD_STATIC_LIBRARY)


# Make a static library for regex.
include $(CLEAR_VARS)
LOCAL_SRC_FILES := android/regex/bb_regex.c
LOCAL_C_INCLUDES := $(BB_PATH)/android/regex
LOCAL_CFLAGS := -Wno-sign-compare
LOCAL_MODULE := libregx
include $(BUILD_STATIC_LIBRARY)

#####################################################################

# Execute make prepare for normal config & static lib (recovery)

LOCAL_PATH := $(BB_PATH)
include $(CLEAR_VARS)

BBX_CROSS_COMPILER_PREFIX := $(abspath $(TARGET_TOOLS_PREFIX))

BB_PREPARE_FLAGS:=
ifeq ($(HOST_OS),darwin)
    BB_HOSTCC := $(AOSP_ROOT)/prebuilts/gcc/darwin-x86/host/i686-apple-darwin-4.2.1/bin/i686-apple-darwin11-gcc
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

#####################################################################

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
       $( $(AOSP_ROOT)/bionic/libc/arch-$(TARGET_ARCH)/syscalls/,$(BBX_ASM_FILES))
endif


BBX_C_INCLUDES = \
	$(BB_PATH)/include $(BB_PATH)/libbb \
	bionic/libc/private \
	bionic/libm/include \
	bionic/libc \
	bionic/libm \
	libc/kernel/common \
	external/selinux/include \
        external/selinux/libselinux/src \
        external/selinux/libselinux/include \
	external/selinux/libselinux/include/selinux \
        external/selinux/libsepol/include \
	$(BB_PATH)/android/regex \
	$(BB_PATH)/android/librpc

BBX_CFLAGS = \
	-Werror=implicit -Wno-clobbered -Wno-format-security \
	-DHAVE_SCHED_H \
	-D_GNU_SOURCE \
	-Wno-deprecated-declarations \
        -Wno-sign-compare \
        -Wno-non-virtual-dtor \
        -Wno-implicit-function-declaration \
	-DNDEBUG \
	-DANDROID \
        -D__ANDROID__ \
        -DHAVE_DPRINTF \
	-fno-strict-aliasing \
	-fno-builtin-stpcpy \
	-include $(bb_gen)/$(BBX_CONFIG)/include/autoconf.h \
	'-DCONFIG_DEFAULT_MODULES_DIR="$(KERNEL_MODULES_DIR)"' \
	-DBB_BT=AUTOCONF_TIMESTAMP


# Static Busybox

LOCAL_PATH := $(BB_PATH)
include $(CLEAR_VARS)

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
LOCAL_STATIC_LIBRARIES := libc libcutils libm libregx libuclibcrpc libsepol libselinux
LOCAL_MODULE_CLASS := EXECUTABLES
LOCAL_MODULE_PATH := $(TARGET_ROOT_OUT_SBIN)
LOCAL_ADDITIONAL_DEPENDENCIES := $(bbx_prepare_full)
LOCAL_PACK_MODULE_RELOCATIONS := false
include $(BUILD_EXECUTABLE)
