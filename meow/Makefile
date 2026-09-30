include $(TOPDIR)/rules.mk

PKG_NAME:=meow
PKG_VERSION?=0.21.2
PKG_RELEASE?=1

include $(INCLUDE_DIR)/package.mk

PKG_MAINTAINER:=Independent meow OpenWrt package <noreply@example.invalid>

define Package/meow
  SECTION:=net
  CATEGORY:=Network
  TITLE:=meow high-performance rule-based proxy core
  URL:=https://github.com/meow-rs/meow-rs
  LICENSE:=MIT
endef

define Package/meow/description
  meow Rust proxy core built from the upstream commit recorded in UPSTREAM.json.
endef

define Build/Prepare
endef

define Build/Compile
endef

define Package/meow/install
	@test -s ./prebuilt-meow || { echo "ERROR: meow/prebuilt-meow is not populated yet; run build-core.yml first."; exit 1; }
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_DIR) $(1)/etc/meow
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_DIR) $(1)/usr/share/meow
	$(INSTALL_BIN) ./prebuilt-meow $(1)/usr/bin/meow
	$(INSTALL_BIN) ./files/meow.init $(1)/etc/init.d/meow
	$(INSTALL_DATA) ./files/meow.config $(1)/etc/config/meow
	$(INSTALL_DATA) ./files/config.yaml $(1)/etc/meow/config.yaml
	$(INSTALL_BIN) ./files/gateway.sh $(1)/usr/share/meow/gateway.sh
	$(INSTALL_BIN) ./files/arp-hijack.sh $(1)/usr/share/meow/arp-hijack.sh
	$(INSTALL_BIN) ./files/meow-arp.init $(1)/etc/init.d/meow-arp
	$(INSTALL_BIN) ./files/meow.uci-defaults $(1)/etc/uci-defaults/80_meow
endef

define Package/meow/conffiles
/etc/config/meow
/etc/meow/config.yaml
endef

$(eval $(call BuildPackage,meow))
