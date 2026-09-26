# onomondo-ipa, the GSMA SGP.32 IoT Profile Assistant, built for wwand-ipa.
#
# The assistant polls an eIM (the fleet server) for eUICC packages and runs
# them on the card. Upstream reaches the card through PC/SC; patch 100 adds a
# card backend that speaks lpac's stdio APDU protocol instead, so wwand's
# esim_bridge relays its APDUs over the modem's own channel (QMI UIM / MBIM
# UICC / AT) exactly as it does for lpac, and adds -H: a profile change is
# handed to the host, which resets the SIM and waits for the new session. The
# patch carries a test for the card backend (tests/scard_stdio). The package
# build does not run it (BUILD_TESTING=OFF, target ipa only); on a host:
#   cmake -S . -B build -DIPA_SCARD_STDIO=ON && cmake --build build && ctest --test-dir build
# The -H wiring in main.c has no test of its own: exercising it takes an eIM
# that sends a profile change.
#
# TLS: the same minimal static wolfSSL + libcurl bundle as wwand-lpac, for the
# same reason (OpenWrt's mbedtls lacks curves the GSMA PKI uses, and
# libcurl+OpenSSL is ~6.4 MB). The eIM is reached over HTTPS with the system
# CA bundle unless the eIM configuration says otherwise.
#
# Upstream implements SGP.32 v1.0; wwand always runs it in IoT eUICC emulation
# (-E), i.e. against an SGP.22 consumer eUICC. See wwand's src-ucode/ipa.uc.

include $(TOPDIR)/rules.mk

PKG_NAME:=wwand-ipad
PKG_VERSION:=0.0.1_git20260901
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/onomondo/onomondo-ipa.git
PKG_SOURCE_VERSION:=6aaeb38a569e648c8305aa5bd4d300cc1ea6822a
PKG_MIRROR_HASH:=skip

PKG_LICENSE:=AGPL-3.0-only curl GPL-3.0-or-later
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=

# bundled, statically-linked dependencies (keep in step with wwand-lpac)
WOLFSSL_VERSION:=5.9.2-stable
CURL_VERSION:=8.21.0

PKG_BUILD_PARALLEL:=1

# wolfSSL's SP math carries inline assembly that MIPS16 cannot encode
PKG_BUILD_FLAGS:=no-mips16

include $(INCLUDE_DIR)/package.mk

define Download/wolfssl
  FILE:=wolfssl-$(WOLFSSL_VERSION).tar.gz
  URL:=https://github.com/wolfSSL/wolfssl/archive/v$(WOLFSSL_VERSION)
  HASH:=skip
endef
$(eval $(call Download,wolfssl))

define Download/curl
  FILE:=curl-$(CURL_VERSION).tar.xz
  URL:=https://github.com/curl/curl/releases/download/curl-8_21_0
  HASH:=skip
endef
$(eval $(call Download,curl))

define Package/wwand-ipad
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=WWAN
  TITLE:=SGP.32 IoT Profile Assistant (onomondo-ipa) for wwand-ipa
  URL:=https://github.com/onomondo/onomondo-ipa
  # the eIM is an HTTPS server with an ordinary certificate chain
  DEPENDS:=+ca-bundle
endef

define Package/wwand-ipad/description
 onomondo-ipa, the GSMA SGP.32 IoT Profile Assistant, built with a card
 backend that reaches the eUICC through wwand (lpac's stdio APDU protocol)
 instead of PC/SC, and with a minimal static wolfSSL + libcurl linked in.
 Installed as /usr/lib/wwand/ipad; wwand-ipa runs it. Implements SGP.32 v1.0
 and is run in IoT eUICC emulation against an SGP.22 consumer eUICC.
endef

PREFIX:=$(PKG_BUILD_DIR)/.bundle
WOLFSSL_DIR:=$(PKG_BUILD_DIR)/wolfssl-$(WOLFSSL_VERSION)
CURL_DIR:=$(PKG_BUILD_DIR)/curl-$(CURL_VERSION)
IPA_BUILD:=$(PKG_BUILD_DIR)/.ipa-build

LTO_CFLAGS:=-flto=auto -ffat-lto-objects
BUNDLE_AR:=AR="$(TARGET_CROSS)gcc-ar" RANLIB="$(TARGET_CROSS)gcc-ranlib"

# unpack + patch the assistant, then the bundled wolfSSL + curl beside it
define Build/Prepare
	$(call Build/Prepare/Default)
	$(TAR) -C $(PKG_BUILD_DIR) -xzf $(DL_DIR)/wolfssl-$(WOLFSSL_VERSION).tar.gz
	$(TAR) -C $(PKG_BUILD_DIR) -xJf $(DL_DIR)/curl-$(CURL_VERSION).tar.xz
endef

Build/Configure:=

define Build/Compile
	# 1) minimal static wolfSSL (the wwand-lpac recipe)
	( cd $(WOLFSSL_DIR) && ./autogen.sh )
	( cd $(WOLFSSL_DIR) && ./configure --host=$(GNU_TARGET_NAME) --prefix=$(PREFIX) \
		--enable-static --disable-shared \
		--enable-curl --enable-tls13 --enable-brainpool --enable-ecccustcurves \
		--enable-curve25519 --disable-dtls --disable-oldtls \
		--disable-examples --disable-crypttests \
		CC="$(TARGET_CC)" $(BUNDLE_AR) \
		CFLAGS="$(TARGET_CFLAGS) $(LTO_CFLAGS) -ffunction-sections -fdata-sections -DWOLFSSL_NO_ASN_STRICT" )
	+$(MAKE) -C $(WOLFSSL_DIR)
	$(MAKE) -C $(WOLFSSL_DIR) install

	# 2) minimal static libcurl (HTTP/HTTPS only) against it. HTTP stays: an
	# eIM configuration may name a plain-HTTP lab eIM (the assistant's -S).
	( cd $(CURL_DIR) && \
		PKG_CONFIG_PATH="$(PREFIX)/lib/pkgconfig" PKG_CONFIG_LIBDIR="$(PREFIX)/lib/pkgconfig" \
		./configure --host=$(GNU_TARGET_NAME) --prefix=$(PREFIX) --with-wolfssl=$(PREFIX) \
		--enable-static --disable-shared \
		--disable-ftp --disable-file --disable-ldap --disable-ldaps --disable-rtsp \
		--disable-dict --disable-telnet --disable-tftp --disable-pop3 --disable-imap \
		--disable-smtp --disable-gopher --disable-mqtt --disable-smb --disable-ntlm \
		--disable-manual --disable-unix-sockets --disable-progress-meter \
		--without-libpsl --without-zlib --without-nghttp2 --without-brotli \
		--without-zstd --without-libidn2 --without-librtmp --without-ca-path \
		--with-ca-bundle=/etc/ssl/certs/ca-certificates.crt \
		CC="$(TARGET_CC)" $(BUNDLE_AR) \
		CFLAGS="$(TARGET_CFLAGS) $(LTO_CFLAGS) -ffunction-sections -fdata-sections -DSIZEOF_LONG_LONG=8" \
		CPPFLAGS="-I$(PREFIX)/include" LDFLAGS="-L$(PREFIX)/lib" LIBS="-lm" )
	+$(MAKE) -C $(CURL_DIR)
	$(MAKE) -C $(CURL_DIR) install

	# 3) the assistant with the stdio card backend, statically against both.
	# AR/RANLIB go in as full paths: CMake took the bare name as a path relative
	# to its build directory and wrote `.ipa-build/aarch64-openwrt-linux-musl-gcc-ar`
	# into libasn's link.txt, which failed with "Error running link command: no
	# such file or directory" (SDK snapshot, aarch64, 2026-09-26).
	rm -rf $(IPA_BUILD)
	mkdir -p $(IPA_BUILD)
	( cd $(IPA_BUILD) && cmake $(PKG_BUILD_DIR) \
		-DCMAKE_SYSTEM_NAME=Linux -DCMAKE_SYSTEM_PROCESSOR=$(ARCH) \
		-DCMAKE_C_COMPILER="$(TARGET_CROSS)gcc" \
		-DCMAKE_AR="$(TOOLCHAIN_DIR)/bin/$(TARGET_CROSS)gcc-ar" \
		-DCMAKE_RANLIB="$(TOOLCHAIN_DIR)/bin/$(TARGET_CROSS)gcc-ranlib" \
		-DCMAKE_C_FLAGS="$(TARGET_CFLAGS) $(LTO_CFLAGS) -ffunction-sections -fdata-sections -I$(PREFIX)/include" \
		-DCMAKE_EXE_LINKER_FLAGS="$(TARGET_LDFLAGS) $(LTO_CFLAGS) -Wl,--gc-sections -L$(PREFIX)/lib" \
		-DCMAKE_C_STANDARD_LIBRARIES="-L$(PREFIX)/lib -lwolfssl -lm" \
		-DIPA_SCARD_STDIO=ON -DBUILD_TESTING=OFF )
	+$(MAKE) -C $(IPA_BUILD) ipa
endef

define Package/wwand-ipad/install
	$(INSTALL_DIR) $(1)/usr/lib/wwand
	$(INSTALL_BIN) $(IPA_BUILD)/src/ipa/ipa $(1)/usr/lib/wwand/ipad
endef

$(eval $(call BuildPackage,wwand-ipad))
