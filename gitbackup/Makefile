#
# Copyright (C) 2026 VizzleTF
#
# This is free software, licensed under the GNU General Public License v2.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=gitbackup
PKG_VERSION:=0.1.1
PKG_RELEASE:=1

PKG_LICENSE:=GPL-2.0-only
PKG_MAINTAINER:=VizzleTF <vizzlef@gmail.com>

include $(INCLUDE_DIR)/package.mk

define Package/gitbackup
  SECTION:=net
  CATEGORY:=Network
  TITLE:=Automatic configuration backup to a Git repository
  # Every entry earns its place with a measured 25.12.4 failure, not habit
  # (spec, "Проверенные факты"): stat is entirely absent from the base image
  # and the manifest depends on it (coreutils-stat); dbclient cannot read
  # OpenSSH-format keys or honor UserKnownHostsFile, so ssh needs the real
  # openssh client and keygen; git-http is required for `git fetch https://`
  # (fails with "remote-https is not a git command" otherwise). flock is a
  # busybox applet and needs nothing here.
  DEPENDS:=+git +git-http +ca-bundle +jsonfilter +coreutils-stat +openssh-client +openssh-keygen
  PKGARCH:=all
endef

define Package/gitbackup/description
 gitbackup commits the router's configuration to a private git repository on
 a schedule, without keeping a working copy of that repository on flash, and
 restores it back onto a freshly flashed router.
endef

define Package/gitbackup/conffiles
/etc/config/gitbackup
endef

define Build/Compile
endef

define Package/gitbackup/install
	$(INSTALL_DIR) $(1)
	$(CP) ./files/* $(1)/
endef

$(eval $(call BuildPackage,gitbackup))
