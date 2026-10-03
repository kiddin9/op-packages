# luci-app-hermes — OpenWrt LuCI plugin for Hermes Agent (Python AI Gateway)
# Dual-version: supports luci 18.06 (Lua CBI) + luci 24.10+ (JS view)
# Works as feeds source or standalone in package/ directory

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-hermes
PKG_VERSION:=2026.05.10
PKG_RELEASE:=3

PKG_MAINTAINER:=Hermes Agent
PKG_LICENSE:=GPL-3.0

LUCI_TITLE:=Hermes AI Agent Gateway
LUCI_DEPENDS:=+luci-compat +luci-base +python3 +python3-pip
LUCI_PKGARCH:=all

# Prefer feeds/luci/luci.mk (handles install + i18n automatically)
LUCI_MK:=$(firstword $(wildcard $(TOPDIR)/feeds/luci/luci.mk))

ifneq ($(LUCI_MK),)
  include $(LUCI_MK)
else
  # Standalone mode: no luci feed available
  include $(INCLUDE_DIR)/package.mk

  define Package/$(PKG_NAME)
    SECTION:=luci
    CATEGORY:=LuCI
    SUBMENU:=3. Applications
    TITLE:=$(LUCI_TITLE)
    DEPENDS:=$(LUCI_DEPENDS)
    PKGARCH:=all
  endef

  define Package/$(PKG_NAME)/description
    Hermes Agent AI Gateway LuCI management plugin.
    Python-based AI agent with web UI, gateway, and terminal.
  endef

  define Package/$(PKG_NAME)/install
	# JS view (luci 24.10+)
	$(INSTALL_DIR) $(1)/www/luci-static/resources/view
	$(INSTALL_DATA) ./htdocs/luci-static/resources/view/hermes.js \
		$(1)/www/luci-static/resources/view/hermes.js
	# Lua compat (luci 18.06)
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller
	$(INSTALL_DATA) ./luasrc/controller/hermes.lua \
		$(1)/usr/lib/lua/luci/controller/hermes.lua
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/model/cbi
	$(INSTALL_DATA) ./luasrc/model/cbi/hermes.lua \
		$(1)/usr/lib/lua/luci/model/cbi/hermes.lua
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/view/hermes
	$(INSTALL_DATA) ./luasrc/view/hermes/status.htm \
		$(1)/usr/lib/lua/luci/view/hermes/status.htm
	$(INSTALL_DATA) ./luasrc/view/hermes/console.htm \
		$(1)/usr/lib/lua/luci/view/hermes/console.htm
	$(INSTALL_DATA) ./luasrc/view/hermes/terminal.htm \
		$(1)/usr/lib/lua/luci/view/hermes/terminal.htm
	# root overlay
	$(CP) ./root/* $(1)/
	# fix permissions
	chmod 755 $(1)/etc/init.d/hermes 2>/dev/null || true
	chmod 755 $(1)/etc/uci-defaults/99-hermes 2>/dev/null || true
	chmod 755 $(1)/usr/bin/hermes-env 2>/dev/null || true
	chmod 755 $(1)/usr/share/hermes/luci-helper 2>/dev/null || true
	chmod 755 $(1)/usr/share/hermes/web-pty.py 2>/dev/null || true
  endef
endif

define Package/$(PKG_NAME)/conffiles
/etc/config/hermes
endef

define Package/$(PKG_NAME)/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	( . /etc/uci-defaults/99-hermes ) && rm -f /etc/uci-defaults/99-hermes
	rm -f /tmp/luci-indexcache /tmp/luci-modulecache/* 2>/dev/null
	exit 0
}
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
