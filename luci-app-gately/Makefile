# SPDX-License-Identifier: GPL-3.0-only
#
# Copyright (C) 2026 OpenWrt.org

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-gately
PKG_VERSION:=0.6.8.8
PKG_RELEASE:=15

PKG_SOURCE:=gately-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://codeload.github.com/wangwanjie/gately/tar.gz/v$(PKG_VERSION)?
PKG_HASH:=skip

PKG_LICENSE:=Apache-2.0
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=wangwanjie <https://github.com/wangwanjie/gately>

PKG_CONFIG_DEPENDS:= \
	CONFIG_GATELY_LANG_ALL \
	CONFIG_GATELY_LANG_CJKEN \
	CONFIG_GATELY_LANG_ZH \
	CONFIG_GATELY_CUSTOM_MODULES \
	CONFIG_GATELY_MOD_PROTOROUTE \
	CONFIG_GATELY_MOD_DDNS \
	CONFIG_GATELY_MOD_STUN \
	CONFIG_GATELY_MOD_GUARD \
	CONFIG_GATELY_MOD_KNOCK \
	CONFIG_GATELY_MOD_WAF \
	CONFIG_GATELY_MOD_FRP \
	CONFIG_GATELY_MOD_CLOUDFLARED \
	CONFIG_GATELY_MOD_TAILSCALE \
	CONFIG_GATELY_MOD_NETBIRD \
	CONFIG_GATELY_MOD_EASYTIER \
	CONFIG_GATELY_MOD_WEBTERMINAL \
	CONFIG_GATELY_MOD_DOCKER \
	CONFIG_GATELY_MOD_WOL \
	CONFIG_GATELY_MOD_CRON \
	CONFIG_GATELY_MOD_NETTOOLS \
	CONFIG_GATELY_MOD_STORAGE \
	CONFIG_GATELY_MOD_BACKUP \
	CONFIG_GATELY_MOD_WEBDAV \
	CONFIG_GATELY_MOD_FTP \
	CONFIG_GATELY_MOD_SMB \
	CONFIG_GATELY_MOD_FILEBROWSER \
	CONFIG_GATELY_MOD_NOTIFY \
	CONFIG_GATELY_MOD_PERF

PKG_BUILD_DEPENDS:=golang/host node/host node-pnpm/host
PKG_BUILD_PARALLEL:=1
PKG_BUILD_FLAGS:=no-mips16

BUILD_DATE:=$(shell date -u -d "@$(SOURCE_DATE_EPOCH)" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")

GO_PKG:=github.com/wangwanjie/gately
GO_PKG_BUILD_PKG:=$(GO_PKG)/cmd/gately
GO_PKG_CGO_ENABLED:=0
GO_PKG_LDFLAGS:=-s -w
GO_PKG_LDFLAGS_X:= \
	$(GO_PKG)/internal/version.Version=v$(PKG_VERSION) \
	$(GO_PKG)/internal/version.Commit=v$(PKG_VERSION)-r$(PKG_RELEASE) \
	$(GO_PKG)/internal/version.BuildDate=$(BUILD_DATE)

empty:=
space:=$(empty) $(empty)
comma:=,

# Upstream strips unused Coraza @validateSchema operator (~2.3 MB smaller binary)
GATELY_GO_TAGS:=coraza.disabled_operators.validateSchema
GATELY_LOCALES:=

ifeq ($(CONFIG_GATELY_LANG_ZH),y)
  GATELY_GO_TAGS+=lang_zh
  GATELY_LOCALES:=zh-CN
else ifeq ($(CONFIG_GATELY_LANG_CJKEN),y)
  GATELY_GO_TAGS+=lang_cjken
  GATELY_LOCALES:=zh-CN,zh-TW,en
endif

ifeq ($(CONFIG_GATELY_CUSTOM_MODULES),y)
  GATELY_GO_TAGS+= \
	$(if $(CONFIG_GATELY_MOD_PROTOROUTE),,no_protoroute) \
	$(if $(CONFIG_GATELY_MOD_DDNS),,no_ddns) \
	$(if $(CONFIG_GATELY_MOD_STUN),,no_stun) \
	$(if $(CONFIG_GATELY_MOD_GUARD),,no_guard) \
	$(if $(CONFIG_GATELY_MOD_KNOCK),,no_knock) \
	$(if $(CONFIG_GATELY_MOD_WAF),,no_waf) \
	$(if $(CONFIG_GATELY_MOD_FRP),,no_frp) \
	$(if $(CONFIG_GATELY_MOD_CLOUDFLARED),,no_cloudflared) \
	$(if $(CONFIG_GATELY_MOD_TAILSCALE),,no_tailscale) \
	$(if $(CONFIG_GATELY_MOD_NETBIRD),,no_netbird) \
	$(if $(CONFIG_GATELY_MOD_EASYTIER),,no_easytier) \
	$(if $(CONFIG_GATELY_MOD_WEBTERMINAL),,no_webterminal) \
	$(if $(CONFIG_GATELY_MOD_DOCKER),,no_docker) \
	$(if $(CONFIG_GATELY_MOD_WOL),,no_wol) \
	$(if $(CONFIG_GATELY_MOD_CRON),,no_cron) \
	$(if $(CONFIG_GATELY_MOD_NETTOOLS),,no_nettools) \
	$(if $(CONFIG_GATELY_MOD_STORAGE),,no_storage) \
	$(if $(CONFIG_GATELY_MOD_BACKUP),,no_backup) \
	$(if $(CONFIG_GATELY_MOD_WEBDAV),,no_webdav) \
	$(if $(CONFIG_GATELY_MOD_FTP),,no_ftp) \
	$(if $(CONFIG_GATELY_MOD_SMB),,no_smb) \
	$(if $(CONFIG_GATELY_MOD_FILEBROWSER),,no_filebrowser) \
	$(if $(CONFIG_GATELY_MOD_NOTIFY),,no_notify) \
	$(if $(CONFIG_GATELY_MOD_PERF),,no_perf)
endif

GO_PKG_TAGS:=$(subst $(space),$(comma),$(strip $(GATELY_GO_TAGS)))

include $(INCLUDE_DIR)/package.mk
include $(TOPDIR)/feeds/packages/lang/golang/golang-package.mk

define Package/luci-app-gately
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=LuCI support for Gately (with Gately binary)
  URL:=https://github.com/wangwanjie/gately
  DEPENDS:=$(GO_ARCH_DEPENDS) +luci-base +ca-bundle
  PROVIDES:=gately
endef

define Package/luci-app-gately/description
  All-in-one Gately network gateway toolkit and LuCI management app.
  Integrates reverse proxy, protocol routing (SNI/ALPN/Host), ACME SSL
  certificates, DDNS, STUN NAT traversal, port forwarding, WAF (Coraza +
  OWASP CRS v4), fail2ban-style intrusion prevention, port knocking, tunnel
  managers (frp, Tailscale, NetBird, EasyTier, cloudflared), WebDAV/FTP/SMB,
  Web Terminal, and LuCI service control in a single package.
endef

define Package/luci-app-gately/config
  source "$(SOURCE)/Config.in"
endef

define Package/luci-app-gately/conffiles
/etc/config/gately
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(HOST_TAR) -xzf $(DL_DIR)/$(PKG_SOURCE) -C $(PKG_BUILD_DIR) --strip-components=1
	$(Build/Patch)
endef

define Build/Compile
	( \
		set -e; \
		export CI=true; \
		export HOME="$(PKG_BUILD_DIR)/.home"; \
		export PNPM_HOME="$(PKG_BUILD_DIR)/.pnpm"; \
		export npm_config_store_dir="$(PKG_BUILD_DIR)/.pnpm-store"; \
		cd "$(PKG_BUILD_DIR)/web"; \
		pnpm install --frozen-lockfile --prefer-offline; \
		GATELY_LOCALES="$(GATELY_LOCALES)" pnpm run build; \
	)
	$(call GoPackage/Build/Compile)
endef

define Package/luci-app-gately/install
	$(call GoPackage/Package/Install/Bin,$(1))

	$(CP) $(PKG_BUILD_DIR)/deploy/openwrt/luci/root/. $(1)/
	find $(1)/usr/lib $(1)/usr/share $(1)/www -type d -exec chmod 0755 {} + 2>/dev/null || true
	find $(1)/usr/lib $(1)/usr/share $(1)/www -type f -exec chmod 0644 {} + 2>/dev/null || true
	chmod 0755 $(1)/usr/libexec/rpcd/luci.gately

	if [ ! -f "$(1)/usr/lib/lua/luci/i18n/gately.zh-cn.lmo" ] && [ -x "$(STAGING_DIR_HOSTPKG)/bin/po2lmo" ]; then \
		$(INSTALL_DIR) $(1)/usr/lib/lua/luci/i18n; \
		for po in $(PKG_BUILD_DIR)/deploy/openwrt/luci/po/*/gately.po; do \
			[ -f "$$po" ] || continue; \
			lang=$$(basename "$$(dirname "$$po")"); \
			$(STAGING_DIR_HOSTPKG)/bin/po2lmo "$$po" "$(1)/usr/lib/lua/luci/i18n/gately.$$lang.lmo"; \
		done; \
	fi

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/deploy/openwrt/gately.init $(1)/etc/init.d/gately

	$(INSTALL_DIR) $(1)/etc/uci-defaults
	printf '%s\n' \
		'#!/bin/sh' \
		'if [ ! -f /etc/config/gately ]; then' \
		'	mkdir -p /etc/config' \
		'	printf "\nconfig gately '\''main'\''\n" > /etc/config/gately' \
		'fi' \
		'rm -f /tmp/luci-indexcache /tmp/luci-indexcache.* /tmp/luci-gately-version' \
		'rm -rf /tmp/luci-modulecache/' \
		'/etc/init.d/rpcd reload 2>/dev/null || true' \
		'if /etc/init.d/gately running 2>/dev/null; then' \
		'	/etc/init.d/gately restart >/dev/null 2>&1 || true' \
		'fi' \
		'exit 0' \
		> $(1)/etc/uci-defaults/99-luci-app-gately
	chmod 0755 $(1)/etc/uci-defaults/99-luci-app-gately
endef

define Package/luci-app-gately/postrm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
rm -f /tmp/luci-indexcache /tmp/luci-indexcache.* /tmp/luci-gately-version
rm -rf /tmp/luci-modulecache/
killall -HUP rpcd 2>/dev/null || /etc/init.d/rpcd reload 2>/dev/null || true
exit 0
endef

$(eval $(call GoBinPackage,luci-app-gately))
$(eval $(call BuildPackage,luci-app-gately))
