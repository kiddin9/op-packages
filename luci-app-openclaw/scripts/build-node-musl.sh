#!/bin/sh
# 在 Alpine ARM64 Docker 容器内运行
# 环境变量: NODE_VER (目标版本号), /output (输出目录)
#
# 打包策略:
#   使用 patchelf 修改 node 二进制的 ELF interpreter 和 rpath，
#   使其直接使用打包的 musl 链接器和共享库，无需 LD_LIBRARY_PATH。
#   这样 process.execPath 返回正确的 node 路径，子进程 fork 也能正常工作。
#   安装路径固定为 /opt/openclaw/node (与 openclaw-env 一致)。
set -e

INSTALL_PREFIX="/opt/openclaw/node"

apk add --no-cache nodejs npm xz icu-data-full patchelf

ACTUAL_VER=$(node --version | sed 's/^v//')
echo "Alpine Node.js version: v${ACTUAL_VER} (requested: v${NODE_VER})"

# 使用实际版本号作为文件名 (Alpine apk 的 nodejs 版本可能与请求版本不同)
if [ "$ACTUAL_VER" != "$NODE_VER" ]; then
	echo "WARNING: Actual version (${ACTUAL_VER}) differs from requested (${NODE_VER})"
	echo "         Using actual version for package name"
fi
PKG_NAME="node-v${ACTUAL_VER}-linux-arm64-musl"
PKG_DIR="/tmp/${PKG_NAME}"
mkdir -p "${PKG_DIR}/bin" "${PKG_DIR}/lib/node_modules" "${PKG_DIR}/include/node"

# 复制 node 二进制
cp "$(which node)" "${PKG_DIR}/bin/node"
chmod +x "${PKG_DIR}/bin/node"

# 收集 node 依赖的所有共享库 (Alpine node 是动态链接的)
echo "=== Collecting shared libraries ==="
LIB_DIR="${PKG_DIR}/lib"
ldd "$(which node)" 2>/dev/null | while read -r line; do
  # 解析 ldd 输出: libxxx.so => /usr/lib/libxxx.so (0x...)
  lib_path=$(echo "$line" | grep -oE '/[^ ]+\.so[^ ]*' | head -1)
  if [ -n "$lib_path" ] && [ -f "$lib_path" ]; then
    cp -L "$lib_path" "$LIB_DIR/" 2>/dev/null || true
    echo "  + $(basename "$lib_path")"
  fi
done
# 确保 musl 动态链接器也在
if [ -f /lib/ld-musl-aarch64.so.1 ]; then
  cp -L /lib/ld-musl-aarch64.so.1 "$LIB_DIR/" 2>/dev/null || true
  echo "  + ld-musl-aarch64.so.1"
fi
echo "Libraries collected: $(ls "$LIB_DIR"/*.so* 2>/dev/null | wc -l) files"

# 用 patchelf 修改 node 二进制:
#   - interpreter 指向打包的 musl 链接器 (绝对路径，对应安装后的位置)
#   - rpath 指向打包的 lib 目录
echo "=== Patching ELF binary ==="
patchelf --set-interpreter "${INSTALL_PREFIX}/lib/ld-musl-aarch64.so.1" "${PKG_DIR}/bin/node"
patchelf --set-rpath "${INSTALL_PREFIX}/lib" "${PKG_DIR}/bin/node"
echo "  interpreter: ${INSTALL_PREFIX}/lib/ld-musl-aarch64.so.1"
echo "  rpath: ${INSTALL_PREFIX}/lib"

# 复制 ICU 完整数据 (npm 的 Intl.Collator 需要)
echo "=== Copying ICU data ==="
ICU_DAT=$(find /usr/share/icu -name "icudt*.dat" 2>/dev/null | head -1)
if [ -n "$ICU_DAT" ] && [ -f "$ICU_DAT" ]; then
  mkdir -p "${PKG_DIR}/share/icu"
  cp "$ICU_DAT" "${PKG_DIR}/share/icu/"
  echo "  + $(basename "$ICU_DAT") ($(du -h "$ICU_DAT" | cut -f1))"
else
  echo "  WARNING: ICU data file not found"
fi

# 创建 node wrapper 脚本 (只设置 NODE_ICU_DATA，ELF 层面已解决链接器和库路径)
cat > "${PKG_DIR}/bin/node-wrapper" << 'NODEWRAPPER'
#!/bin/sh
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
export NODE_ICU_DATA="${SELF_DIR}/../share/icu"
exec "${SELF_DIR}/node" "$@"
NODEWRAPPER
chmod +x "${PKG_DIR}/bin/node-wrapper"

# 复制 npm
if [ -d /usr/lib/node_modules/npm ]; then
  cp -r /usr/lib/node_modules/npm "${PKG_DIR}/lib/node_modules/"
fi

# 创建 npm wrapper (直接调用 patchelf 后的 node，只需设置 ICU)
cat > "${PKG_DIR}/bin/npm" << 'NPMWRAPPER'
#!/bin/sh
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
export NODE_ICU_DATA="${SELF_DIR}/../share/icu"
exec "${SELF_DIR}/node" "${SELF_DIR}/../lib/node_modules/npm/bin/npm-cli.js" "$@"
NPMWRAPPER
# 创建 npx wrapper
cat > "${PKG_DIR}/bin/npx" << 'NPXWRAPPER'
#!/bin/sh
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
export NODE_ICU_DATA="${SELF_DIR}/../share/icu"
exec "${SELF_DIR}/node" "${SELF_DIR}/../lib/node_modules/npm/bin/npx-cli.js" "$@"
NPXWRAPPER
chmod +x "${PKG_DIR}/bin/npm" "${PKG_DIR}/bin/npx"

# 验证 (需要将打包内容放到目标路径来测试 patchelf 结果)
echo "=== Verification ==="
mkdir -p "${INSTALL_PREFIX}"
cp -a "${PKG_DIR}"/* "${INSTALL_PREFIX}/"
"${INSTALL_PREFIX}/bin/node" --version
"${INSTALL_PREFIX}/bin/node" -e "console.log('execPath:', process.execPath)"
"${INSTALL_PREFIX}/bin/node" -e "console.log(process.arch, process.platform, process.versions.modules)"
NODE_ICU_DATA="${INSTALL_PREFIX}/share/icu" "${INSTALL_PREFIX}/bin/npm" --version 2>/dev/null || echo "npm needs ICU data"
rm -rf "${INSTALL_PREFIX}"

# 打包
cd /tmp
tar cJf "/output/${PKG_NAME}.tar.xz" "${PKG_NAME}"
ls -lh "/output/${PKG_NAME}.tar.xz"
echo "=== Done: ${PKG_NAME}.tar.xz ==="
