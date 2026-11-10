#!/usr/bin/env bash
#
# deploy.sh - Deploy luci-app-device-manager directly to an OpenWrt router for development/testing.
# SSH authentication is performed once; all deployment commands reuse that connection.
#
# Usage:
#   ./tools/deploy.sh [options] <target>
#
# Examples:
#   ./tools/deploy.sh 192.168.1.1
#   ./tools/deploy.sh root@192.168.1.1
#   ./tools/deploy.sh -p 2222 root@192.168.1.1
#

set -euo pipefail

# Color formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

print_info() {
    printf "${BLUE}[INFO]${NC} %s\n" "$1"
}

print_success() {
    printf "${GREEN}[SUCCESS]${NC} %s\n" "$1"
}

print_error() {
    printf "${RED}[ERROR]${NC} %s\n" "$1" >&2
}

show_usage() {
    cat <<EOF
Usage: $0 [options] <target>

Arguments:
    <target>               Router IP address or SSH user@host (e.g., 192.168.1.1 or root@192.168.1.1)

Options:
    -p, --port <port>      SSH port number (default: 22)
    -h, --help             Show this help message

Examples:
    $0 192.168.1.1
    $0 root@192.168.1.1
    $0 -p 2222 root@192.168.31.1
EOF
}

# Parse options
SSH_PORT="22"
TARGET=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--port)
            if [[ $# -lt 2 || ! "$2" =~ ^[0-9]+$ || ${#2} -gt 5 ]] || (( 10#$2 < 1 || 10#$2 > 65535 )); then
                print_error "SSH port must be an integer between 1 and 65535."
                exit 1
            fi
            SSH_PORT="$2"
            shift 2
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        -*)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
        *)
            if [[ -z "$TARGET" ]]; then
                TARGET="$1"
            else
                print_error "Unexpected argument: $1"
                show_usage
                exit 1
            fi
            shift
            ;;
    esac
done

if [[ -z "$TARGET" ]]; then
    print_error "Target router address is required."
    show_usage
    exit 1
fi

# Normalize SSH target
if [[ "$TARGET" != *"@"* ]]; then
    SSH_TARGET="root@${TARGET}"
    ROUTER_IP="${TARGET}"
else
    SSH_TARGET="${TARGET}"
    ROUTER_IP="${TARGET#*@}"
fi

# Check prerequisites
for cmd in ssh scp mktemp; do
    if ! command -v "$cmd" &>/dev/null; then
        print_error "Required local command '$cmd' is not found in PATH."
        exit 1
    fi
done

# Resolve workspace directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Verify essential project files exist
if [[ ! -f "${PROJECT_ROOT}/htdocs/luci-static/resources/view/device-manager/devices.js" ]]; then
    print_error "Missing frontend view file: htdocs/.../devices.js"
    exit 1
fi

if [[ ! -f "${PROJECT_ROOT}/root/usr/share/luci/menu.d/luci-app-device-manager.json" ]]; then
    print_error "Missing menu definition file: root/.../menu.d/luci-app-device-manager.json"
    exit 1
fi

if [[ ! -f "${PROJECT_ROOT}/root/usr/share/rpcd/acl.d/luci-app-device-manager.json" ]]; then
    print_error "Missing ACL definition file: root/.../acl.d/luci-app-device-manager.json"
    exit 1
fi

for resource in model.js service.js snapshot-cache.js feedback.js online-check.js preferences.js table.js device-dialog.js group-dialog.js styles.css; do
    if [[ ! -f "${PROJECT_ROOT}/htdocs/luci-static/resources/device-manager/${resource}" ]]; then
        print_error "Missing frontend resource: device-manager/${resource}"
        exit 1
    fi
done

if [[ ! -f "${PROJECT_ROOT}/root/usr/libexec/rpcd/luci.device-manager" || ! -f "${PROJECT_ROOT}/tools/initialize-config.sh" ]]; then
    print_error "Missing rpcd helper or configuration initializer."
    exit 1
fi

# Keep the control socket private and its path short enough for Unix socket limits.
SSH_CONTROL_DIR="$(mktemp -d /tmp/luci-deploy.XXXXXX)"
SSH_CONTROL_PATH="${SSH_CONTROL_DIR}/ssh"
SSH_COMMON_OPTS=(-o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -o "ControlPath=${SSH_CONTROL_PATH}")
SSH_OPTS=(-p "${SSH_PORT}" "${SSH_COMMON_OPTS[@]}" -o ControlMaster=no -o BatchMode=yes)
SCP_OPTS=(-P "${SSH_PORT}" "${SSH_COMMON_OPTS[@]}" -o ControlMaster=no -o BatchMode=yes)

cleanup() {
    ssh "${SSH_OPTS[@]}" -O exit "${SSH_TARGET}" >/dev/null 2>&1 || true
    rm -rf -- "${SSH_CONTROL_DIR}"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

print_info "Connecting to OpenWrt router at ${SSH_TARGET} (port: ${SSH_PORT})..."

# Authenticate once and keep the master connection open until cleanup.
if ! ssh -p "${SSH_PORT}" "${SSH_COMMON_OPTS[@]}" -o BatchMode=no -o ControlPersist=no -M -N -f "${SSH_TARGET}"; then
    print_error "Failed to connect to ${SSH_TARGET} via SSH. Please check network, IP, port, and SSH key/password."
    exit 1
fi

if ! ssh "${SSH_OPTS[@]}" "${SSH_TARGET}" "command -v ip >/dev/null && command -v flock >/dev/null && test -r /usr/share/libubox/jshn.sh"; then
    print_error "Router is missing ip, flock or jshn. Standard OpenWrt BusyBox provides ip and flock; custom builds may need ip-tiny and flock. Install jshn if missing."
    exit 1
fi

print_info "Connection verified. Preparing remote directories..."

ssh "${SSH_OPTS[@]}" "${SSH_TARGET}" "
    mkdir -p /www/luci-static/resources/view/device-manager \
             /usr/share/luci/menu.d \
             /usr/share/rpcd/acl.d \
             /usr/lib/lua/luci/i18n \
             /usr/libexec/rpcd \
             /etc/uci-defaults \
             /etc/config
"

print_info "Deploying shared frontend modules and stylesheet..."
scp "${SCP_OPTS[@]}" -r \
    "${PROJECT_ROOT}/htdocs/luci-static/resources/device-manager" \
    "${SSH_TARGET}:/www/luci-static/resources/"

print_info "Deploying frontend view (devices.js)..."
scp "${SCP_OPTS[@]}" \
    "${PROJECT_ROOT}/htdocs/luci-static/resources/view/device-manager/devices.js" \
    "${SSH_TARGET}:/www/luci-static/resources/view/device-manager/devices.js"

print_info "Deploying LuCI menu and rpcd ACL definitions..."
scp "${SCP_OPTS[@]}" \
    "${PROJECT_ROOT}/root/usr/share/luci/menu.d/luci-app-device-manager.json" \
    "${SSH_TARGET}:/usr/share/luci/menu.d/luci-app-device-manager.json"

scp "${SCP_OPTS[@]}" \
    "${PROJECT_ROOT}/root/usr/share/rpcd/acl.d/luci-app-device-manager.json" \
    "${SSH_TARGET}:/usr/share/rpcd/acl.d/luci-app-device-manager.json"

# Native translations are installed as the matching luci-i18n package.
# Remove files left by older development deployments without changing LuCI language.
ssh "${SSH_OPTS[@]}" "${SSH_TARGET}" "
    rm -f /www/luci-static/resources/device-manager/i18n.js /www/luci-static/resources/device-manager/translations.js
    rm -f /usr/lib/lua/luci/i18n/device-manager-builtin.zh-cn.lmo /etc/uci-defaults/81_device_manager_i18n
"

if [[ -f "${PROJECT_ROOT}/root/usr/libexec/rpcd/luci.device-manager" ]]; then
    print_info "Deploying rpcd helper backend script..."
    scp "${SCP_OPTS[@]}" \
        "${PROJECT_ROOT}/root/usr/libexec/rpcd/luci.device-manager" \
        "${SSH_TARGET}:/usr/libexec/rpcd/luci.device-manager"
    ssh "${SSH_OPTS[@]}" "${SSH_TARGET}" "chmod +x /usr/libexec/rpcd/luci.device-manager"
fi

if [[ -f "${PROJECT_ROOT}/tools/initialize-config.sh" ]]; then
    print_info "Deploying development configuration initializer..."
    scp "${SCP_OPTS[@]}" \
        "${PROJECT_ROOT}/tools/initialize-config.sh" \
        "${SSH_TARGET}:/etc/uci-defaults/80_device_manager"
fi

print_info "Ensuring configuration persistence (protecting existing user remarks)..."
ssh "${SSH_OPTS[@]}" "${SSH_TARGET}" "
    set -e
    if [ ! -f /etc/config/device_manager ]; then
        echo 'Initializing default /etc/config/device_manager'
    else
        echo 'Existing /etc/config/device_manager preserved.'
    fi
    if [ -f /etc/uci-defaults/80_device_manager ]; then
        chmod +x /etc/uci-defaults/80_device_manager
        /etc/uci-defaults/80_device_manager
        rm -f /etc/uci-defaults/80_device_manager
    fi
"

print_info "Clearing LuCI cache and restarting rpcd..."
ssh "${SSH_OPTS[@]}" "${SSH_TARGET}" "
    rm -f /tmp/luci-indexcache* /tmp/luci-modulecache*
    /etc/init.d/rpcd restart
"

print_success "Deployment completed successfully!"
printf "\n"
printf "${CYAN}================================================================${NC}\n"
printf "  ${GREEN}luci-app-device-manager${NC} is now active on your router.\n"
printf "\n"
printf "  Access URL:  ${YELLOW}http://%s/cgi-bin/luci/admin/network/device-manager${NC}\n" "${ROUTER_IP}"
printf "  Menu path:   ${YELLOW}网络 -> 设备管理${NC}\n"
printf "\n"
printf "  ${YELLOW}Note:${NC} If you are already logged in, please refresh the page\n"
printf "  with ${CYAN}Ctrl + Shift + R${NC} to clear browser JavaScript cache.\n"
printf "${CYAN}================================================================${NC}\n"
