# ipad, the GSMA SGP.32 v1.3 IoT Profile Assistant, built for wwand-ipa.
#
# It polls an eIM (the fleet server) for eUICC packages and runs them on the
# card, which it reaches through lpac's stdio APDU protocol: wwand's
# esim_bridge relays those APDUs over the modem's own channel (QMI UIM / MBIM
# UICC / AT), exactly as for lpac. An IoT eUICC is driven as it is; an SGP.22
# consumer eUICC through ipad's emulation of the SGP.32 functions, with its
# results signed by a device key the eIM imports (`wwandctl ipa export`).
#
# mbedTLS 3.6 LTS is built in statically: RSP needs brainpoolP256r1, which
# OpenWrt's shared mbedtls does not enable by default. The project's tests
# (unit, a scripted eIM, the real binary over the stdio protocol) are not run
# by the package build; see the ipad README.

include $(TOPDIR)/rules.mk

PKG_NAME:=wwand-ipad
PKG_VERSION:=0.1.0
PKG_RELEASE:=2

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/ddimension/ipad.git
PKG_SOURCE_VERSION:=fbb175f4d272f0db45b3bc006392f172cd248aa5
PKG_MIRROR_HASH:=skip

PKG_LICENSE:=GPL-2.0-only Apache-2.0
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=

MBEDTLS_VERSION:=3.6.7

PKG_BUILD_PARALLEL:=1
CMAKE_BINARY_SUBDIR:=openwrt-build

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/cmake.mk

# the release tarball; its SHA-256 is the one mbedtls-3.6.7-sha256sum.txt on
# the release page publishes
define Download/mbedtls
  FILE:=mbedtls-$(MBEDTLS_VERSION).tar.bz2
  URL:=https://github.com/Mbed-TLS/mbedtls/releases/download/mbedtls-$(MBEDTLS_VERSION)
  HASH:=skip
endef
$(eval $(call Download,mbedtls))

define Build/Prepare
	$(call Build/Prepare/Default)
	$(TAR) -C $(PKG_BUILD_DIR) -xjf $(DL_DIR)/mbedtls-$(MBEDTLS_VERSION).tar.bz2
endef

CMAKE_OPTIONS += \
	-DIPAD_MBEDTLS_DIR=$(PKG_BUILD_DIR)/mbedtls-$(MBEDTLS_VERSION) \
	-DIPAD_WERROR=OFF \
	-DBUILD_TESTING=OFF

TARGET_CFLAGS += -ffunction-sections -fdata-sections
TARGET_LDFLAGS += -Wl,--gc-sections

define Package/wwand-ipad
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=WWAN
  TITLE:=SGP.32 v1.3 IoT Profile Assistant (ipad) for wwand-ipa
  URL:=https://github.com/ddimension/ipad
  # the eIM is an HTTPS server; without a pin in its configuration the
  # system CAs decide
  DEPENDS:=+ca-bundle
endef

define Package/wwand-ipad/description
 ipad, a GSMA SGP.32 v1.3 IoT Profile Assistant: eIM packages (every PSMO
 and eCO), profile rollback, IPA/eUICC data, direct and indirect profile
 download, notifications and the connectivity parameters of the enabled
 profile. Drives an IoT eUICC, or an SGP.22 consumer eUICC through an
 emulation that signs its results with a device key the eIM imports.
 Reaches the card through wwand (lpac's stdio APDU protocol); mbedTLS
 linked in statically. Installed as /usr/lib/wwand/ipad; wwand-ipa runs it.
endef

define Package/wwand-ipad/install
	$(INSTALL_DIR) $(1)/usr/lib/wwand
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/$(CMAKE_BINARY_SUBDIR)/ipad $(1)/usr/lib/wwand/ipad
endef

$(eval $(call BuildPackage,wwand-ipad))
