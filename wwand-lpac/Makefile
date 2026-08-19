# Self-contained static build of lpac for wwand-esim.
#
# lpac's ES9+ HTTPS leg needs a TLS stack with the full GSMA curve/algorithm
# set. OpenWrt's mbedtls is feature-stripped (fails the SM-DP+ TLS) and its
# libcurl+OpenSSL drags in ~6.4 MB of libcrypto/libssl. Instead we bundle a
# minimal static wolfSSL + a minimal static libcurl straight into the lpac
# binary: one ~1 MB self-contained executable, no libcurl/libssl .so at all.
#
# Proven on the RG650E: full SGP.22 RSP download over the wwand stdio bridge.

include $(TOPDIR)/rules.mk

PKG_NAME:=wwand-lpac
PKG_VERSION:=2.3.0
PKG_RELEASE:=2

PKG_LICENSE:=AGPL-3.0-only GPL-3.0-or-later curl
PKG_MAINTAINER:=

# lpac (primary source)
PKG_SOURCE:=lpac-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://codeload.github.com/estkme-group/lpac/tar.gz/refs/tags/v$(PKG_VERSION)?
PKG_HASH:=skip
# unique build dir (the lpac tarball's top dir is lpac-2.3.0, same as the stock
# lpac package — extract it ourselves with --strip-components into our own dir)
PKG_BUILD_DIR:=$(BUILD_DIR)/wwand-lpac-$(PKG_VERSION)

# bundled, statically-linked dependencies
WOLFSSL_VERSION:=5.9.2-stable
CURL_VERSION:=8.21.0

PKG_BUILD_PARALLEL:=1

# wolfSSL's SP math (sp_int.c, WOLFSSL_SP_MIPS) carries inline assembly that
# MIPS16 cannot encode ("operand 3 must be an immediate expression `addu ...'")
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

define Package/wwand-lpac
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=WWAN
  TITLE:=lpac eSIM LPA — self-contained static build (wolfSSL)
  URL:=https://github.com/estkme-group/lpac
  # PROVIDES:=lpac so wwand-esim's `+lpac` dependency resolves to this
  # self-contained build. Do NOT also CONFLICTS:=lpac — when the real `lpac`
  # package is present in the feed set (CI), CONFLICTS emits a
  # `depends on PACKAGE_lpac` (scripts/package-metadata.pl mconf_conflicts)
  # which, together with the PROVIDES `select`, is a Kconfig recursive
  # dependency that breaks `make defconfig` for every feed consumer. The
  # vpackage provider model keeps the two `lpac` providers mutually exclusive.
  PROVIDES:=lpac
endef

define Package/wwand-lpac/description
 A single self-contained lpac binary for wwand-esim: minimal static wolfSSL
 (TLS 1.2/1.3, ECDHE, ECDSA+RSA, NIST + Brainpool curves, x25519, AES-GCM,
 SHA-2; built with WOLFSSL_NO_ASN_STRICT so the GSMA id-rspRole critical
 extension is accepted) and a minimal static libcurl (HTTPS only) are linked
 straight into lpac. No libcurl/libssl/libcrypto .so — ~1 MB total instead of
 the ~6.4 MB that libcurl+OpenSSL pulls in. Only the stdio + curl drivers are
 built (the wwand stdio bridge relays the eUICC APDUs through wwand's own
 modem_apdu channel). Drop-in replacement for the stock lpac package.

 Includes patch 110 (backport of upstream #399, the v2.3.0 stdio-driver fix).
endef

PREFIX:=$(PKG_BUILD_DIR)/.bundle
WOLFSSL_DIR:=$(PKG_BUILD_DIR)/wolfssl-$(WOLFSSL_VERSION)
CURL_DIR:=$(PKG_BUILD_DIR)/curl-$(CURL_VERSION)
LPAC_BUILD:=$(PKG_BUILD_DIR)/.lpac-build

# LTO across the whole bundle (wolfSSL + libcurl + lpac). Fat LTO objects keep
# real machine code alongside the IR, so the sub-libs' configure link-tests
# (plain, no -flto) still resolve symbols while the final lpac link (-flto) still
# optimises across all three. gcc-ar/gcc-ranlib are the LTO-aware archivers.
LTO_CFLAGS:=-flto=auto -ffat-lto-objects
BUNDLE_AR:=AR="$(TARGET_CROSS)gcc-ar" RANLIB="$(TARGET_CROSS)gcc-ranlib"

# extract lpac (strip its top dir into our unique build dir), patch it, then
# unpack the bundled wolfSSL + curl sources alongside it
define Build/Prepare
	$(INSTALL_DIR) $(PKG_BUILD_DIR)
	$(TAR) -C $(PKG_BUILD_DIR) --strip-components=1 -xzf $(DL_DIR)/$(PKG_SOURCE)
	$(Build/Patch)
	$(TAR) -C $(PKG_BUILD_DIR) -xzf $(DL_DIR)/wolfssl-$(WOLFSSL_VERSION).tar.gz
	$(TAR) -C $(PKG_BUILD_DIR) -xJf $(DL_DIR)/curl-$(CURL_VERSION).tar.xz
endef

# nothing to autoconf for the top-level (lpac is CMake); the sub-libs are
# configured inside Build/Compile
Build/Configure:=

define Build/Compile
	# 1) minimal static wolfSSL (GSMA-capable)
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

	# 2) minimal static libcurl (HTTPS only) against the bundled wolfSSL
	# -DSIZEOF_LONG_LONG=8: on 32-bit targets curl_config.h defines
	# SIZEOF_LONG=4 and nothing else; wolfSSL's CTC_SETTINGS enum (types.h)
	# then hits "#error bad math long / long long settings". 64-bit targets
	# take the SIZEOF_LONG==8 branch and never look at it.
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

	# 3) lpac, statically linked against the two bundled .a
	rm -rf $(LPAC_BUILD)
	mkdir -p $(LPAC_BUILD)
	( cd $(LPAC_BUILD) && PKG_CONFIG_PATH="$(PREFIX)/lib/pkgconfig" cmake $(PKG_BUILD_DIR) \
		-DCMAKE_SYSTEM_NAME=Linux -DCMAKE_SYSTEM_PROCESSOR=$(ARCH) \
		-DCMAKE_C_COMPILER="$(TARGET_CROSS)gcc" \
		-DCMAKE_AR="$(TARGET_CROSS)gcc-ar" -DCMAKE_RANLIB="$(TARGET_CROSS)gcc-ranlib" \
		-DCMAKE_FIND_ROOT_PATH="$(PREFIX)" -DCMAKE_PREFIX_PATH="$(PREFIX)" \
		-DCMAKE_C_FLAGS="$(TARGET_CFLAGS) $(LTO_CFLAGS) -ffunction-sections -fdata-sections -I$(PREFIX)/include" \
		-DCMAKE_EXE_LINKER_FLAGS="$(TARGET_LDFLAGS) $(LTO_CFLAGS) -Wl,--gc-sections -L$(PREFIX)/lib" \
		-DCMAKE_C_STANDARD_LIBRARIES="-L$(PREFIX)/lib -lwolfssl -lm" \
		-DLPAC_DYNAMIC_LIBEUICC=OFF \
		-DLPAC_WITH_APDU_PCSC=OFF -DLPAC_WITH_APDU_AT=OFF \
		-DLPAC_WITH_APDU_QMI=OFF -DLPAC_WITH_APDU_MBIM=OFF \
		-DLPAC_WITH_HTTP_CURL=ON \
		-DCURL_INCLUDE_DIR="$(PREFIX)/include" -DCURL_LIBRARY="$(PREFIX)/lib/libcurl.a" )
	+$(MAKE) -C $(LPAC_BUILD)
endef

define Package/wwand-lpac/install
	$(INSTALL_DIR) $(1)/usr/lib
	$(INSTALL_BIN) $(LPAC_BUILD)/output/lpac $(1)/usr/lib/lpac
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) ./files/lpac.sh $(1)/usr/bin/lpac
endef

$(eval $(call BuildPackage,wwand-lpac))
