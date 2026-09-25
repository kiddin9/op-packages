#
# Copyright (C) 2026
#
# This is free software, licensed under the Apache License, Version 2.0 .
#

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-footstrap-files
# luci.mk keys hook names on LUCI_NAME, which defaults to the checkout's directory name — a
# differently-named checkout symlinked into the feed would silently skip the Build/Prepare hook.
LUCI_NAME:=luci-app-footstrap-files

# Version is git-derived; never hardcode PKG_VERSION. CI injects FOOTSTRAP_VERSION from the tag (an
# SDK build has no .git, so it cannot derive one). This package has its own repo and its own tags:
# the number here is this package's alone and does not track the theme's.
FOOTSTRAP_VERSION?=
ifneq ($(FOOTSTRAP_VERSION),)
PKG_VERSION:=$(FOOTSTRAP_VERSION)
PKG_RELEASE:=1
endif

LUCI_TITLE:=A file manager for the Footstrap theme

# +luci-base only, and NOT the theme. This is an ordinary LuCI view, not a chrome plugin: it renders
# under any theme, and its stylesheet is scoped to this package's own `.fsf-*` classes, unlayered
# and without one `!important` — an app's sheet already outranks every cascade layer a theme has
# inside the app's own subtree. Depending on the theme would install a theme on a router that asked
# for a file manager.
#
# cgi-io is what serves the actual bytes for an upload and a download (`/cgi-bin/cgi-upload`,
# `/cgi-bin/cgi-download`); luci-base pulls it in already, and it is named here because this package
# breaks without it rather than degrades.
LUCI_DEPENDS:=+luci-base +cgi-io
LUCI_PKGARCH:=all
LUCI_MAINTAINER:=VizzleTF <vizzletf47@gmail.com>
LUCI_URL:=https://github.com/VizzleTF/luci-app-footstrap-files
LUCI_DESCRIPTION:=Browse, upload, download, rename, edit and delete files on the router. Written for \
the Footstrap theme and usable under any other: the page is plain LuCI markup, the styling is scoped \
to the package's own classes, and everything it does goes through luci-base's own `fs` API and cgi-io.

PKG_LICENSE:=Apache-2.0
PKG_LICENSE_FILES:=LICENSE

# CSS: ship verbatim. luci.mk defaults LUCI_MINIFY_CSS to 1, which runs csstidy over every *.css
# under htdocs/ — and csstidy is fifteen years older than the syntax a sheet written today uses:
# measured on the theme's own sheet it drops the `@layer` wrapper and every rule inside it, and this
# one is full of color-mix(). The owfeed path minifies it with tools/minify-css.sh instead, which is
# string-aware and checks its own rule count before and after.
LUCI_MINIFY_CSS:=0

# RELOAD, NOT RESTART: rpcd holds sessions in memory, so `restart` logs out every LuCI user while
# `reload` re-reads the ACLs and keeps them. This package DOES ship an acl.d file — unlike the
# theme's other apps — so rpcd has something new to read on install, and a router where it is not
# reloaded answers `access denied` until the next reboot.
define Package/luci-app-footstrap-files/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	/etc/init.d/rpcd reload >/dev/null 2>&1 || true
	rm -f /tmp/luci-indexcache* /tmp/luci-modulecache/* >/dev/null 2>&1 || true
}
exit 0
endef

define Package/luci-app-footstrap-files/postrm
#!/bin/sh
# An UPGRADE runs postrm for the old version after the new one is unpacked, so dropping the caches
# is right in both cases, and reloading rpcd on the way out costs a session nothing.
[ -n "$${IPKG_INSTROOT}" ] || {
	/etc/init.d/rpcd reload >/dev/null 2>&1 || true
	rm -f /tmp/luci-indexcache* /tmp/luci-modulecache/* >/dev/null 2>&1 || true
}
exit 0
endef

# Absolute, not a relative path: CI rsyncs this package into package/, not into the feed.
include $(TOPDIR)/feeds/luci/luci.mk

# luci.mk's Build/Prepare copies only src/ luasrc/ htdocs/ root/ ucode/ into $(PKG_BUILD_DIR), and
# PKG_LICENSE_FILES resolves against THAT — so the Apache text has to be put there by hand or the
# declaration above points at nothing. The hook name is keyed on LUCI_NAME, which is pinned at the
# top for exactly this reason.
define Build/Prepare/luci-app-footstrap-files
	$(CP) $(CURDIR)/LICENSE $(PKG_BUILD_DIR)/
endef

# THE LINE BELOW IS LOAD-BEARING AND IT IS NOT A SIGNATURE — do not delete it as boilerplate.
# include/scan.mk builds the package list by GREPPING Makefiles for `call BuildPackage`; luci.mk calls
# it at the include above, but the grep cannot see that, so this literal is what puts the package into
# the SDK's list.
# call BuildPackage - OpenWrt buildroot signature
