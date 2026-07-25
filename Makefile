PKG_VERSION := release-1.13
PKG_COMMIT := d8c80cc
TALOS_VERSION := v1.13.6
SBCOVERLAY_VERSION := v0.2.0

PUSH ?= true
REGISTRY ?= ghcr.io
REGISTRY_USERNAME ?= charliebravo636
TAG ?= $(shell git describe --tags --exact-match)

SED ?= sed
ASSET_TYPE ?= rpi_5
CONFIG_TXT ?= dtparam=i2c_arm=on

EXTENSIONS := "ghcr.io/siderolabs/gvisor:20260622.0@sha256:9ceeb9e8950dae906e9d1219e2745ac3866e5041ca0d0f72680cca0fb20d13fd"
EXTENSIONS += "ghcr.io/siderolabs/iscsi-tools:v0.2.0@sha256:6dcc959cb165826261a40b453277aea5b75dcc4ffe583058a2a42be7abb74e81"
EXTENSIONS += "ghcr.io/siderolabs/util-linux-tools:2.41.4@sha256:f60939819154f68fe7d8bfa3f8fd0c519d61babe2f547b39b64839c1ad9a3001"
EXTENSION_ARGS := $(foreach ext,$(EXTENSIONS),--system-extension-image $(ext))

EXTRA_KERNEL_ARGS ?=
EXTRA_KERNEL := $(foreach arg,$(EXTRA_KERNEL_ARGS),--extra-kernel-arg $(arg))

PKG_REPOSITORY := https://github.com/siderolabs/pkgs.git
TALOS_REPOSITORY := https://github.com/siderolabs/talos.git
SBCOVERLAY_REPOSITORY := https://github.com/siderolabs/sbc-raspberrypi

CHECKOUTS_DIRECTORY := $(PWD)/checkouts
PATCHES_DIRECTORY := $(PWD)/patches

PKGS_TAG ?= $(shell cd $(CHECKOUTS_DIRECTORY)/pkgs && git describe --tag --always --dirty --match v[0-9]\*)
TALOS_TAG ?= $(or ${TAG}, $(shell cd $(CHECKOUTS_DIRECTORY)/talos && git describe --tag --always --dirty --match v[0-9]\*))
SBCOVERLAY_TAG ?= $(shell cd $(CHECKOUTS_DIRECTORY)/sbc-raspberrypi && git describe --tag --always --dirty --match v[0-9]\*)

#
# Help
#
.PHONY: help
help:
	@echo "debug            : Show Debug Variables"
	@echo "checkouts        : Clone repositories required for the build"
	@echo "patches          : Apply all patches for Raspberry Pi 5"
	@echo "kernel           : Build kernel"
	@echo "overlay          : Build Raspberry Pi 5 overlay"
	@echo "imager           : Build imager docker image"
	@echo "installer-base   : Build installer-base docker image"
	@echo "initramfs-kernel : Build kernel and initramfs"
	@echo "installer        : Build installer"
	@echo "image            : Build disk image for Raspberry Pi 5"
	@echo "pi5              : Full build pipeline for Raspberry Pi 5"
	@echo "clean            : Clean up any remains"
#
# Debug
#
.PHONY: debug
debug:
	echo "The Extensions are: $(EXTENSION_ARGS)"

#
# Checkouts
#
.PHONY: checkouts checkouts-clean
checkouts:
	git clone -c advice.detachedHead=false --single-branch --branch "$(PKG_VERSION)" "$(PKG_REPOSITORY)" "$(CHECKOUTS_DIRECTORY)/pkgs"
	cd "$(CHECKOUTS_DIRECTORY)/pkgs" && git reset --hard "$(PKG_COMMIT)"
	git clone -c advice.detachedHead=false --single-branch --branch "$(TALOS_VERSION)" "$(TALOS_REPOSITORY)" "$(CHECKOUTS_DIRECTORY)/talos"
	git clone -c advice.detachedHead=false --single-branch --branch "$(SBCOVERLAY_VERSION)" "$(SBCOVERLAY_REPOSITORY)" "$(CHECKOUTS_DIRECTORY)/sbc-raspberrypi"

checkouts-clean:
	rm -rf "$(CHECKOUTS_DIRECTORY)/pkgs"
	rm -rf "$(CHECKOUTS_DIRECTORY)/talos"
	rm -rf "$(CHECKOUTS_DIRECTORY)/sbc-raspberrypi"

#
# Patches
#
.PHONY: patches-pkgs patches-talos patches-sbc-raspberrypi patches patches
patches-pkgs:
	cd "$(CHECKOUTS_DIRECTORY)/pkgs" && \
		git am "$(PATCHES_DIRECTORY)/siderolabs/pkgs/0001-Patched-for-Raspberry-Pi5.patch"
		  # Using other SED Interpreter for Building, if your own sed is diffierent, like gsed
		git am "$(PATCHES_DIRECTORY)/siderolabs/pkgs/0002-Support-alternative-sed-interpreter.patch"

patches-talos:
	cd "$(CHECKOUTS_DIRECTORY)/talos" && \
		git am "$(PATCHES_DIRECTORY)/siderolabs/talos/0001-Patched-for-Raspberry-Pi-5.patch" && \
		git am "$(PATCHES_DIRECTORY)/siderolabs/talos/0002-Makefile.patch"

patches-sbc-raspberrypi:
	cd "$(CHECKOUTS_DIRECTORY)/sbc-raspberrypi" && \
		git am "$(PATCHES_DIRECTORY)/siderolabs/sbc-raspberrypi/0001-Patched-for-Raspberry-Pi-5.patch"

patches-linux:
	# Remove patches targeting mainline kernel which are N/A in this vendor kernel
	rm -f "$(CHECKOUTS_DIRECTORY)/pkgs/kernel/build/patches/0001-net-macb-flush-PCIe-posted-write-after-TSTART-doorbe.patch"
	rm -f "$(CHECKOUTS_DIRECTORY)/pkgs/kernel/build/patches/0002-net-macb-insert-PCIe-read-barrier-before-TX-completi.patch"
	rm -f "$(CHECKOUTS_DIRECTORY)/pkgs/kernel/build/patches/0003-net-macb-add-TX-stall-watchdog-to-recover-from-lost-.patch"
	
	@if [ -d "$(PATCHES_DIRECTORY)/linux" ] && ls "$(PATCHES_DIRECTORY)/linux"/*.patch >/dev/null 2>&1; then \
		mkdir -p "$(CHECKOUTS_DIRECTORY)/pkgs/kernel/build/patches" && \
		cp -v "$(PATCHES_DIRECTORY)/linux"/*.patch "$(CHECKOUTS_DIRECTORY)/pkgs/kernel/build/patches/"; \
	else \
		echo "No local kernel patches in $(PATCHES_DIRECTORY)/linux, skipping"; \
	fi

patches: patches-pkgs patches-talos patches-sbc-raspberrypi patches-linux

# Backwards-compatible alias
patches: patches

.PHONY: kernel
kernel:
	cd "$(CHECKOUTS_DIRECTORY)/pkgs" && \
		$(MAKE) \
			REGISTRY=$(REGISTRY) USERNAME=$(REGISTRY_USERNAME) PUSH=$(PUSH) \
			PLATFORM=linux/arm64 \
			kernel

.PHONY: overlay
overlay:
	@echo SBCOVERLAY_TAG = $(SBCOVERLAY_TAG)
	cd "$(CHECKOUTS_DIRECTORY)/sbc-raspberrypi" && \
		$(MAKE) \
			REGISTRY=$(REGISTRY) USERNAME=$(REGISTRY_USERNAME) IMAGE_TAG=$(SBCOVERLAY_TAG) PUSH=$(PUSH) \
			PKGS_PREFIX=$(REGISTRY)/$(REGISTRY_USERNAME) PKGS=$(PKGS_TAG) \
			INSTALLER_ARCH=arm64 PLATFORM=linux/arm64 \
			sbc-raspberrypi

.PHONY: imager
imager:
	cd "$(CHECKOUTS_DIRECTORY)/talos" && \
		$(MAKE) \
			TAG=${TALOS_TAG} REGISTRY=$(REGISTRY) USERNAME=$(REGISTRY_USERNAME) PUSH=$(PUSH) \
			PKG_KERNEL=$(REGISTRY)/$(REGISTRY_USERNAME)/kernel:$(PKGS_TAG) \
			INSTALLER_ARCH=arm64 PLATFORM=linux/arm64 SED=$(SED) \
			imager

.PHONY: installer-base
installer-base:
	cd "$(CHECKOUTS_DIRECTORY)/talos" && \
		$(MAKE) \
			TAG=${TALOS_TAG} REGISTRY=$(REGISTRY) USERNAME=$(REGISTRY_USERNAME) PUSH=$(PUSH) \
			PKG_KERNEL=$(REGISTRY)/$(REGISTRY_USERNAME)/kernel:$(PKGS_TAG) \
			INSTALLER_ARCH=arm64 PLATFORM=linux/arm64 SED=$(SED) \
			installer-base

.PHONY: initramfs-kernel
initramfs-kernel:
	cd "$(CHECKOUTS_DIRECTORY)/talos" && \
		$(MAKE) \
			TAG=${TALOS_TAG} REGISTRY=$(REGISTRY) USERNAME=$(REGISTRY_USERNAME) \
			PKG_KERNEL=$(REGISTRY)/$(REGISTRY_USERNAME)/kernel:$(PKGS_TAG) \
			INSTALLER_ARCH=arm64 PLATFORM=linux/arm64 SED=$(SED) \
			initramfs kernel

.PHONY: installer
installer:
	cd "$(CHECKOUTS_DIRECTORY)/talos" && \
		docker \
			run --rm -t -v ./_out:/out -v /dev:/dev --privileged $(REGISTRY)/$(REGISTRY_USERNAME)/imager:$(TALOS_TAG) \
			installer \
			--arch arm64 \
			--base-installer-image="$(REGISTRY)/$(REGISTRY_USERNAME)/installer-base:$(TALOS_TAG)" \
			--overlay-name="rpi_5" \
			--overlay-image="$(REGISTRY)/$(REGISTRY_USERNAME)/sbc-raspberrypi:$(SBCOVERLAY_TAG)" \
			--overlay-option="configTxtAppend=$$CONFIG_TXT" \
			$(EXTENSION_ARGS) \
			$(EXTRA_KERNEL)
		crane push \
			./checkouts/talos/_out/installer-arm64.tar \
			${REGISTRY}/${REGISTRY_USERNAME}/installer:${TALOS_TAG}-arm64-extensions

.PHONY: image
image:
	cd "$(CHECKOUTS_DIRECTORY)/talos" && \
		docker \
			run --rm -t -v ./_out:/out -v /dev:/dev --privileged $(REGISTRY)/$(REGISTRY_USERNAME)/imager:$(TALOS_TAG) \
			$(ASSET_TYPE) \
			--arch arm64 \
			--base-installer-image="$(REGISTRY)/$(REGISTRY_USERNAME)/installer-base:$(TALOS_TAG)" \
			--overlay-name="rpi_5" \
			--overlay-image="$(REGISTRY)/$(REGISTRY_USERNAME)/sbc-raspberrypi:$(SBCOVERLAY_TAG)" \
			--overlay-option="configTxtAppend=$$CONFIG_TXT" \
			$(EXTENSION_ARGS) \
			$(EXTRA_KERNEL)

.PHONY: pi5
pi5: checkouts-clean checkouts patches kernel initramfs-kernel installer-base imager overlay installer image

.PHONY: clean
clean: checkouts-clean
