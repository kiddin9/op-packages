--- a/beszel-agent/Makefile
+++ b/beszel-agent/Makefile
@@ -4,7 +4,19 @@ PKG_NAME:=beszel-agent
 PKG_VERSION:=$(or $(BESZEL_VERSION),0.0.0)
 PKG_RELEASE:=1
 
-PKG_SOURCE:=$(PKG_NAME)_linux_$(or $(BESZEL_GOARCH),arm64).tar.gz
+ifeq ($(ARCH),aarch64)
+  PKG_ARCH:=arm64
+else ifeq ($(ARCH),x86_64)
+  PKG_ARCH:=amd64
+else ifeq ($(ARCH),mipsel)
+  PKG_ARCH:=mipsle
+else ifeq ($(ARCH),powerpc64le)
+  PKG_ARCH:=ppc64le
+else
+  PKG_ARCH:=$(ARCH)
+endif
+
+PKG_SOURCE:=$(PKG_NAME)_linux_$(PKG_ARCH).tar.gz
 PKG_SOURCE_URL:=https://github.com/henrygd/beszel/releases/download/v$(PKG_VERSION)/
 PKG_HASH:=skip
 
