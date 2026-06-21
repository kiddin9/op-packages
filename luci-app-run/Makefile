include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-run
PKG_VERSION:=1.0.0
PKG_RELEASE:=4

LUCI_TITLE:=LuCI support for running makeself .run installers
LUCI_DESCRIPTION:=Upload and execute makeself-generated .run installers from LuCI.
LUCI_DEPENDS:=+luci-base +rpcd +libubox
LUCI_PKGARCH:=all

PKG_MAINTAINER:=wukongdaily <2666180@gmail.com>

# 定义版本号用于缓存刷新
define Package/luci-app-run/postinst
#!/bin/sh
# 设置版本号到临时文件，用于前端资源缓存刷新
echo "$(PKG_VERSION)-$(PKG_RELEASE)" > /tmp/luci-app-run.version
exit 0
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature