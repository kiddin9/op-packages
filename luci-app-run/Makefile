include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-run
PKG_VERSION:=1.0.0
PKG_RELEASE:=9

LUCI_TITLE:=LuCI support for running installers and packages
LUCI_DESCRIPTION:=Upload and execute .run, .sh, .ipk and .apk files from LuCI.
LUCI_DEPENDS:=+luci-base +rpcd +libubox
LUCI_PKGARCH:=all

PKG_MAINTAINER:=wukongdaily <wukongdaily@gmail.com>

define Build/Prepare
	find $(CURDIR) -type f -name "*.o" -delete
	$(call Build/Prepare/Default)
endef

define Package/luci-app-run/postinst
#!/bin/sh
echo "$(PKG_VERSION)-$(PKG_RELEASE)" > /tmp/luci-app-run.version
/etc/init.d/rpcd restart >/dev/null 2>&1 || true
exit 0
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature