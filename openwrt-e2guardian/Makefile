include $(TOPDIR)/rules.mk

PKG_NAME:=e2guardian
PKG_VERSION:=5.5.9r
PKG_RELEASE:=2

PKG_LICENSE:=GPL-2.0
PKG_MAINTAINER:=Douglas Orend <doug.orend2@gmail.com>

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/e2guardian/e2guardian/
PKG_SOURCE_VERSION:=e9d50c8852891952c7750aa03fcf086267217a7f
PKG_MIRROR_HASH:=skip

include $(INCLUDE_DIR)/uclibc++.mk
include $(INCLUDE_DIR)/package.mk

define Package/e2guardian
	SECTION:=net
	DEPENDS:=+libpthread $(CXX_DEPENDS) +zlib +libpcre2 +libopenssl
	CATEGORY:=Network
	SUBMENU:=Web Servers/Proxies
	TITLE:=E2Guardian
	URL:=http://e2guardian.org/cms/
endef

define Package/e2guardian/conffiles
/etc/e2guardian/e2guardianf1.conf
/etc/config/e2guardian
endef

CONFIGURE_VARS += \
	INCLUDES="" \
	CXXFLAGS="$$$$CXXFLAGS -fno-rtti" \
	LIBS="-lpthread"

CONFIGURE_ARGS += \
	--with-sysconfsubdir=e2guardian \
	--with-proxyuser=nobody \
	--with-proxygroup=nogroup \
	--with-piddir=/tmp/e2guardian/ \
	--enable-sslmitm=yes \
	--enable-icap=yes \
	--enable-orig-ip \
	--enable-pcre=yes

define Package/e2guardian/description
  e2guardian is an Open Source web content filter, It filters the actual content of pages based on many methods 
  including phrase matching, request  header and URL filtering, etc. It does not purely filter based on a banned list of sites
endef

define Build/Configure
	( cd $(PKG_BUILD_DIR); ./autogen.sh )
	$(call Build/Configure/Default,$CONFIGURE_ARGS)
endef

define Package/e2guardian/install
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/src/e2guardian $(1)/usr/sbin/

	$(INSTALL_DIR) $(1)/usr/share/e2guardian/languages/ukenglish
	$(CP) $(PKG_BUILD_DIR)/data/languages/ukenglish $(1)/usr/share/e2guardian/languages/

	$(INSTALL_DIR) $(1)/usr/share/e2guardian
	$(CP) $(PKG_BUILD_DIR)/data/transparent1x1.gif $(1)/usr/share/e2guardian/
	$(CP) $(PKG_BUILD_DIR)/data/blockedflash.swf $(1)/usr/share/e2guardian/

	$(INSTALL_DIR) $(1)/etc/init.d/
	$(INSTALL_BIN) ./files/e2guardian.init $(1)/etc/init.d/e2guardian

	$(INSTALL_DIR) $(1)/etc/e2guardian/lists
	$(CP) $(PKG_BUILD_DIR)/configs/lists/oldphraselists $(1)/etc/e2guardian/lists/
	$(RM) $(1)/etc/e2guardian/lists/oldphraselists/Makefile*
	$(RM) $(1)/etc/e2guardian/lists/oldphraselists/*.in

	$(CP) $(PKG_BUILD_DIR)/configs/lists/phraselists $(1)/etc/e2guardian/lists/
	$(RM) $(1)/etc/e2guardian/lists/phraselists/Makefile*
	$(RM) $(1)/etc/e2guardian/lists/phraselists/*.in

	$(CP) $(PKG_BUILD_DIR)/configs/lists/common $(1)/etc/e2guardian/lists/
	$(RM) $(1)/etc/e2guardian/lists/common/Makefile*
	$(RM) $(1)/etc/e2guardian/lists/common/*.in

	$(CP) $(PKG_BUILD_DIR)/configs/lists/example.group $(1)/etc/e2guardian/lists/example.group/
	$(RM) $(1)/etc/e2guardian/lists/example.group/Makefile*
	$(RM) $(1)/etc/e2guardian/lists/example.group/*.in

	$(CP) $(PKG_BUILD_DIR)/configs/lists/contentscanners $(1)/etc/e2guardian/lists/
	$(RM) $(1)/etc/e2guardian/lists/contentscanners/Makefile*
	$(RM) $(1)/etc/e2guardian/lists/contentscanners/*.in

	$(INSTALL_DIR) $(1)/etc/e2guardian/downloadmanagers
	$(CP) $(PKG_BUILD_DIR)/configs/downloadmanagers/default.conf $(1)/etc/e2guardian/downloadmanagers/

	$(INSTALL_DIR) $(1)/etc/e2guardian/authplugins
	$(CP) $(PKG_BUILD_DIR)/configs/authplugins/*.conf $(1)/etc/e2guardian/authplugins/

	$(INSTALL_DIR) $(1)/etc/e2guardian/contentscanners
	$(CP) $(PKG_BUILD_DIR)/configs/contentscanners/icapscan.conf $(1)/etc/e2guardian/contentscanners/

	$(INSTALL_CONF) $(PKG_BUILD_DIR)/configs/e2guardian.conf $(1)/etc/e2guardian/e2guardian.conf
	$(INSTALL_CONF) $(PKG_BUILD_DIR)/configs/e2guardianf1.conf $(1)/etc/e2guardian/e2guardianf1.conf
	$(CP) $(PKG_BUILD_DIR)/configs/*.story $(1)/etc/e2guardian/

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/e2guardian.config $(1)/etc/config/e2guardian
endef

$(eval $(call BuildPackage,e2guardian))
