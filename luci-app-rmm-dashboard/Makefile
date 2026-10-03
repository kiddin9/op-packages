# SPDX-License-Identifier: MIT
include $(TOPDIR)/rules.mk

LUCI_TITLE:=OpenWrt RMM router dashboard
LUCI_DEPENDS:=+luci-base +luci-mod-status +rpcd-mod-iwinfo +rpcd-mod-luci +ucode-mod-rtnl
LUCI_PKGARCH:=all
LUCI_DESCRIPTION:=Read-only router and RMM agent overview for LuCI.

PKG_NAME:=luci-app-rmm-dashboard
PKG_VERSION:=0.9.0
PKG_RELEASE:=1
PKG_PO_VERSION:=$(PKG_VERSION)-r$(PKG_RELEASE)
PKG_LICENSE:=MIT
PKG_LICENSE_FILES:=LICENSE

include $(TOPDIR)/feeds/luci/luci.mk

# scan.mk greps for a literal `call BuildPackage`, keep as anchor
# $(call BuildPackage) is handled by luci.mk.
