#
# Package metadata for doona, the web panel dae serves from its own listener.
#
# doona has its own repository (szwjp/doona) and its own release; this package
# only re-hosts the published archive so the panel ships from the same release
# as the engine and the LuCI page, with no cross-repository version to track.
# The build fetches doona-<ver>.tar.gz, verifies it against digests.txt and
# stages its contents under /usr/share/doona.
#
# This file is free software, licensed under the GNU General Public License v3
# or later.

PKG_NAME:=doona
PKG_VERSION:=0.1.0
# The upstream version is the prerelease 0.1.0-rc.9; this repository packages
# it as 0.1.0-r9, the same number luci-app-dae carries. It sorts after the
# separately published doona 0.1.0_rc8-r1, so an upgrade replaces that package.
PKG_RELEASE:=18

PKG_LICENSE:=GPL-3.0-only
PKG_MAINTAINER:=szwjp <szwjp@users.noreply.github.com>
PKG_URL:=https://github.com/szwjp/doona

PKG_DESCRIPTION:=Static web panel for the dae engine. dae serves it at /ui/ from /usr/share/doona; the API still requires the secret.

PKG_ARCH:=noarch

# The published archive is a built frontend: index.html, assets/, fonts/ and
# the licence texts. The whole tree lands where dae looks for a UI.
PKG_ASSETS:=assets/doona=usr/share/doona

PKG_CONFFILES:=
