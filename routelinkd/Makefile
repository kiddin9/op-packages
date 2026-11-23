include $(TOPDIR)/rules.mk

PKG_NAME:=routelinkd
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKG_LICENSE:=MIT
PKG_MAINTAINER:=tsix2019 <tsix2019@users.noreply.github.com>

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/cmake.mk

define Package/routelinkd
  SECTION:=net
  CATEGORY:=Network
  TITLE:=RouteLink per-device traffic, wireless, latency and limits
  URL:=https://github.com/tsix2019/RouteLink
  DEPENDS:=+libubox +libubus +libuci +libblobmsg-json +libjson-c +libmnl +kmod-nf-conntrack-netlink +uclient-fetch +tc-tiny +kmod-sched-core +kmod-sched-flower +kmod-ifb +ca-bundle
endef

define Package/routelinkd/description
  Records upload and download traffic of every LAN device from conntrack
  accounting, and on access points the signal, rates and channel busy time
  of wireless stations (nl80211), the latency to probe targets with an
  outage log, and runs router-side speed tests (uclient-fetch). Sets
  per-device speed limits (tc) and data quotas (nftables), logs DNS answers
  and where devices go, and sends push messages. Serves everything over
  ubus (object "routelink") for LuCI and the RouteLink app.
endef

define Package/routelinkd/conffiles
/etc/config/routelink
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) ./src/* $(PKG_BUILD_DIR)/
endef

CMAKE_OPTIONS += -DRL_VERSION=$(PKG_VERSION) -DRL_BUILD_EPOCH=$(SOURCE_DATE_EPOCH)

define Package/routelinkd/install
	$(INSTALL_DIR) $(1)/usr/sbin $(1)/etc/init.d $(1)/etc/config $(1)/lib/upgrade/keep.d \
		$(1)/etc/hotplug.d/ntp $(1)/usr/share/rpcd/acl.d
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/routelinkd $(1)/usr/sbin/
	$(INSTALL_BIN) ./files/routelink.init $(1)/etc/init.d/routelink
	$(INSTALL_CONF) ./files/routelink.config $(1)/etc/config/routelink
	$(INSTALL_DATA) ./files/routelink.keep $(1)/lib/upgrade/keep.d/routelink
	$(INSTALL_DATA) ./files/routelink.upgrade.sh $(1)/lib/upgrade/routelink.sh
	$(INSTALL_DATA) ./files/routelink.ntp $(1)/etc/hotplug.d/ntp/90-routelink
	$(INSTALL_DATA) ./files/routelink.acl.json $(1)/usr/share/rpcd/acl.d/routelink.json
endef

# rpcd only reads ACL files at start: without a reload even root cannot call the new object
define Package/routelinkd/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || /etc/init.d/rpcd reload
exit 0
endef

$(eval $(call BuildPackage,routelinkd))
