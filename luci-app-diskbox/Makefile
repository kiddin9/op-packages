include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-diskbox
LUCI_NAME:=luci-app-diskbox
PKG_VERSION:=1.26.9
PKG_RELEASE:=1
PKG_MAINTAINER:=permails <https://github.com/permails/luci-app-diskbox>
PKG_LICENSE:=AGPL-3.0

LUCI_TITLE:=DiskBox - Modern Disk Manager interface for LuCI
LUCI_DEPENDS:=+e2fsprogs +parted +smartmontools +blkid \
	+kmod-fs-vfat +dosfstools +kmod-fs-msdos +kmod-nls-base +kmod-nls-utf8 +kmod-nls-cp932 +kmod-nls-cp936 +kmod-nls-cp950 \
	+kmod-fs-exfat +exfat-mkfs +exfat-fsck \
	+kmod-fs-ntfs3 \
	+kmod-fs-btrfs \
	+PACKAGE_$(PKG_NAME)_INCLUDE_ntfs_3g_utils:ntfs-3g-utils \
	+PACKAGE_$(PKG_NAME)_INCLUDE_btrfs_progs:btrfs-progs \
	+PACKAGE_$(PKG_NAME)_INCLUDE_lsblk:lsblk \
	+PACKAGE_$(PKG_NAME)_INCLUDE_mdadm:mdadm \
	+PACKAGE_$(PKG_NAME)_INCLUDE_kmod_md_raid456:mdadm \
	+PACKAGE_$(PKG_NAME)_INCLUDE_kmod_md_raid456:kmod-md-raid456 \
	+PACKAGE_$(PKG_NAME)_INCLUDE_kmod_md_linears:mdadm \
	+PACKAGE_$(PKG_NAME)_INCLUDE_kmod_md_linears:kmod-md-linear \
	+luci-base

LUCI_DESCRIPTION:=Modern Disk and Partition Manager interface for OpenWrt LuCI (JavaScript client-rendered, no luci-compat required)

define Package/$(PKG_NAME)/config
config PACKAGE_$(PKG_NAME)_INCLUDE_ntfs_3g_utils
	depends on PACKAGE_$(PKG_NAME)
	bool "Include ntfs-3g-utils"
	default y
config PACKAGE_$(PKG_NAME)_INCLUDE_btrfs_progs
	depends on PACKAGE_$(PKG_NAME)
	bool "Include btrfs-progs"
	default y
config PACKAGE_$(PKG_NAME)_INCLUDE_lsblk
	depends on PACKAGE_$(PKG_NAME)
	bool "Include lsblk"
	default y
config PACKAGE_$(PKG_NAME)_INCLUDE_mdadm
	depends on PACKAGE_$(PKG_NAME)
	bool "Include mdadm"
	default n
config PACKAGE_$(PKG_NAME)_INCLUDE_kmod_md_raid456
	depends on PACKAGE_$(PKG_NAME)_INCLUDE_mdadm
	bool "Include kmod-md-raid456"
	default n
config PACKAGE_$(PKG_NAME)_INCLUDE_kmod_md_linears
	depends on PACKAGE_$(PKG_NAME)_INCLUDE_mdadm
	bool "Include kmod-md-linear"
	default n
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
