#
# Package metadata for luci-app-dae, the LuCI side of the dae engine.
#
# The page shows the state of the service, opens the doona panel dae serves at
# /ui/, hands out the API secret and drives the manual geo data update. The
# panel itself is the doona package this repository builds from szwjp/doona's
# release archive (installed under /usr/share/doona); this package ships only
# the LuCI page, its rpcd backend and the translations.
#
# This file is free software, licensed under the GNU General Public License v3
# or later.

PKG_NAME:=luci-app-dae
# The page is versioned by release date; the panel it opens keeps its own
# upstream version (0.1.0-rN, see ../doona/Makefile).
PKG_VERSION:=2026.11.14
PKG_RELEASE:=10

PKG_LICENSE:=GPL-3.0-only
PKG_MAINTAINER:=szwjp <szwjp@users.noreply.github.com>
PKG_URL:=https://github.com/szwjp/luci-app-dae

LUCI_DEPENDS:=+luci-base +dae +doona

PKG_DESCRIPTION:=LuCI page for the dae engine. The doona panel itself is the doona package; dae serves it from its own listener.

# The page is static, so the package is the same on every architecture.
PKG_ARCH:=noarch

# The LuCI page reads the state of the service over rpcd, so the package
# ships a small backend next to the view.
PKG_CONFFILES:=
