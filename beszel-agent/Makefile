include $(TOPDIR)/rules.mk

PKG_NAME:=beszel
PKG_VERSION:=0.21.2
PKG_RELEASE:=15

PKG_SOURCE:=beszel-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://codeload.github.com/henrygd/beszel/tar.gz/v$(PKG_VERSION)?
PKG_HASH:=skip

PKG_MAINTAINER:=Jackie264 <OneNAS-space>
PKG_LICENSE:=MIT
PKG_LICENSE_FILES:=LICENSE

PKG_BUILD_DIR:=$(BUILD_DIR)/beszel-$(PKG_VERSION)
PKG_BUILD_DEPENDS:=golang/host
PKG_BUILD_PARALLEL:=1
PKG_USE_MIPS16:=0

GO_PKG:=github.com/henrygd/beszel
GO_PKG_BUILD_PKG:=$(GO_PKG)/internal/cmd/agent
GO_PKG_TAGS:=openwrt
GO_PKG_ENABLE_CGO:=0

include $(INCLUDE_DIR)/package.mk
include $(TOPDIR)/feeds/packages/lang/golang/golang-package.mk

define Package/beszel-agent
  SECTION:=net
  CATEGORY:=Network
  TITLE:=Beszel monitoring agent
  URL:=https://beszel.dev
  DEPENDS:=$(GO_ARCH_DEPENDS)
endef

define Package/beszel-agent/description
  Beszel is a lightweight server monitoring hub. 
  This package contains the agent that runs on the monitored system.
endef

define Build/Prepare
	$(call Build/Prepare/Default)
	$(CP) ./files/openwrt_services.go $(PKG_BUILD_DIR)/agent/
	$(CP) ./files/openwrt_intel_gpu.go $(PKG_BUILD_DIR)/agent/
	$(SED) 's|//go:build linux|//go:build linux \&\& !openwrt|' $(PKG_BUILD_DIR)/agent/systemd.go
	rm -f $(PKG_BUILD_DIR)/agent/gpu_intel.go
endef

define Package/beszel-agent/conffiles
/etc/config/beszel-agent
endef

define Package/beszel-agent/preinst
#!/bin/sh
if [ -z "$${IPKG_INSTROOT}" ]; then
	if [ -f "/etc/init.d/beszel-agent" ]; then
		echo "Stopping old Beszel Agent instance before upgrade..."
		/etc/init.d/beszel-agent stop
	fi
fi
exit 0
endef

define Package/beszel-agent/postinst
#!/bin/sh
if [ -z "$${IPKG_INSTROOT}" ]; then
	echo "Beszel Agent updated successfully. Starting service..."
	/etc/init.d/beszel-agent enable
	/etc/init.d/beszel-agent start
fi
exit 0
endef

define Package/beszel-agent/install
	$(call GoPackage/Package/Install/Bin,$(PKG_INSTALL_DIR))
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/agent $(1)/usr/bin/beszel-agent

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/beszel-agent.init $(1)/etc/init.d/beszel-agent

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/beszel-agent.config $(1)/etc/config/beszel-agent
endef

$(eval $(call GoPackage,beszel-agent))
$(eval $(call BuildPackage,beszel-agent))
