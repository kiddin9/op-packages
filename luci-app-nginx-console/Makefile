# SPDX-License-Identifier: Apache-2.0

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-nginx-console
PKG_VERSION:=0.7.0
PKG_RELEASE:=1

PKG_MAINTAINER:=szwjp <szwjp@users.noreply.github.com>
PKG_LICENSE:=Apache-2.0

LUCI_TITLE:=LuCI console for the nginx UCI configuration
LUCI_DESCRIPTION:=Browse the server sections of /etc/config/nginx in a \
	master-detail layout: the sections on the left, the selected one on the \
	right.  The read-only views (logs, certificates, backups, access control, \
	health check) and the write commands (server sections, conf.d fragments) \
	are separated, so a read grant cannot change the configuration.
LUCI_PKGARCH:=all
# nginx is a virtual package provided by nginx-ssl, nginx-full and friends.
# The console calls its backend through rpcd's file.exec, so rpcd-mod-file is
# what it needs - not cgi-io.  jsonfilter decodes the uci list values without
# invoking a shell, which is what keeps option values from being executed.
LUCI_DEPENDS:=+luci-base +rpcd +rpcd-mod-file +jsonfilter +nginx

include $(TOPDIR)/feeds/luci/luci.mk

# luci.mk copies root/ verbatim and does not set the execute bit, so the two
# entry points are marked here as well - a package built from a tree that lost
# the file modes would otherwise ship a non-executable helper.
define Package/$(PKG_NAME)/install
	$(INSTALL_DIR) $(1)/www
	$(CP) ./htdocs/* $(1)/www/
	$(CP) ./root/* $(1)/
	$(INSTALL_DIR) $(1)/usr/libexec
	$(CHMOD) 0755 $(1)/usr/libexec/nginx-console
	$(CHMOD) 0755 $(1)/usr/libexec/nginx-console-write
endef

# The rate limits live in a file inside the package, so a hand edited rate
# would be overwritten by the next upgrade.  Listing it as a conffile keeps
# the local version and stores the new one next to it.
define Package/$(PKG_NAME)/conffiles
/etc/nginx/conf.d/nginx-console-limits.conf
endef

# call BuildPackage - OpenWrt buildroot signature
