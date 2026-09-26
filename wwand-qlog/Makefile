#
# On-demand Qualcomm diag (QMDL) capture through Quectel QLog, for wwand:
# `wwandctl qlog`. A wwand PLUGIN, kept out of the wwand sources on purpose:
# it is not meant for upstream. wwand itself only resolves and publishes the
# modem's diag node (status.diag_port) and never opens it.
#
# Sources live in https://github.com/ddimension/wwand-qlog, tagged vX.Y.Z. Pin
# a new commit with `scripts/bump-source.sh wwand-qlog <tag|commit>`.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=wwand-qlog
PKG_VERSION:=0.1.0
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/ddimension/wwand-qlog.git
PKG_SOURCE_VERSION:=e4ef3350ac11439259f8bdfd7f11baf002ec9659
PKG_MIRROR_HASH:=skip

PKG_LICENSE:=GPL-2.0-only
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=

include $(INCLUDE_DIR)/package.mk

UCDIR:=/usr/share/ucode/wwand

define Package/wwand-qlog
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=WWAN
  TITLE:=Quectel QLog diag capture for wwand (wwandctl qlog)
  # qlog: /usr/sbin/QLog and its filter profiles. QLog's device scan covers
  # Quectel modules only (its VID/PID allow-list, see the README).
  DEPENDS:=+wwand +qlog
  PKGARCH:=all
endef

define Package/wwand-qlog/description
 `wwandctl qlog`: start, inspect and stop a Qualcomm diag capture with Quectel
 QLog on the modem's DM/DIAG port, which wwand resolves. On demand only; the
 storage sink (TCP, TFTP, FTP, a directory) is QLog's own and passed through
 verbatim, and a capture without one is refused so a QMDL cannot fill the
 router's flash.
endef

define Build/Compile
endef

define Package/wwand-qlog/install
	$(INSTALL_DIR) $(1)$(UCDIR)/ctl
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/qlog.uc $(1)$(UCDIR)/
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/ctl/qlog.uc $(1)$(UCDIR)/ctl/
endef

$(eval $(call BuildPackage,wwand-qlog))
