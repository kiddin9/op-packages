# luci-app-secbox

LuCI support for SecBox (Network Security & NFTables IP Set Management).

`luci-app-secbox` provides a clean, responsive, and native LuCI web interface for managing banIP and NFTables-based security rules on OpenWrt / ImmortalWrt systems.

---

## Features

- **Real-Time Overview**: High-efficiency dashboard displaying active service status, total element counts, execution time, uplink bindings, and NFT set parameters.
- **Rule Management**: Dedicated UI views for managing system and user-defined allowlists, blocklists, and custom threat feed sources.
- **Set Reporting**: Detailed NFT set hit/worst metrics and statistics covering SYN/UDP/ICMP flood mitigations and invalid connection drops.
- **Dual Log Viewers**: Streamlined log viewers for real-time monitoring of firewall blocks and backend execution tasks.
- **Native OpenWrt Design**: 100% compliant with standard LuCI CBI/JavaScript components, zebra-striped data tables, and dark mode themes.

---

## Dependencies

Runtime and build dependencies:

- `banip` (Core backend daemon)
- `luci-base`
- `nftables`
- `kmod-nft-core`

---

## Build Instructions

### 1. Add to OpenWrt Buildroot

Clone the repository into your OpenWrt source tree under the `package/` directory:

```bash
cd /path/to/openwrt

# Option A: Clone directly into package directory
git clone https://github.com/permails/luci-app-secbox.git package/luci-app-secbox

# Option B: Add to custom feeds (custom.feeds.conf)
# src-git secbox https://github.com/permails/luci-app-secbox.git
```

Update and install feeds if using external feed sources:

```bash
./scripts/feeds update -a
./scripts/feeds install -a
```

### 2. Configure Package Selection

Run the menu configuration utility:

```bash
make menuconfig
```

Navigate to:
```text
LuCI --->
    3. Applications --->
        <*> luci-app-secbox
```

### 3. Compile Package

To compile the single package and verify build output:

```bash
make package/luci-app-secbox/compile V=s
```

The resulting `.ipk` / `.apk` package will be located in:
```text
bin/packages/<architecture>/base/luci-app-secbox_1.26.8-1_all.ipk
```

---

## Manual Installation on Router

Transfer the compiled package to your router and install via `opkg`:

```bash
scp bin/packages/<arch>/base/luci-app-secbox_1.26.8-1_all.ipk root@192.168.1.1:/tmp/
ssh root@192.168.1.1

# Install package
opkg update
opkg install /tmp/luci-app-secbox_1.26.8-1_all.ipk

# Clear LuCI index cache
rm -rf /var/luci-indexcache* /tmp/luci-indexcache* /tmp/luci-modulecache
/etc/init.d/rpcd reload
/etc/init.d/uhttpd restart
```

Access the web interface at:
`http://192.168.1.1/cgi-bin/luci/admin/services/secbox`

---

## Project Structure

```text
luci-app-secbox/
├── Makefile                                # OpenWrt package build definition
├── root/
│   ├── etc/uci-defaults/                  # Post-install housekeeping scripts
│   └── usr/share/
│       ├── luci/menu.d/                   # LuCI routing and navigation entries
│       └── rpcd/acl.d/                    # RPCD ACL permission declarations
├── htdocs/
│   └── luci-static/resources/view/secbox/ # Frontend JavaScript controllers
│       ├── overview.js                    # Status overview view
│       ├── settings.js                    # Configuration settings view
│       ├── allowlist.js                   # Allowlist rule management
│       ├── blocklist.js                   # Blocklist rule management
│       ├── feeds.js                       # Custom threat feed editor
│       ├── setreport.js                   # NFT set metrics and reporting
│       ├── firewall_log.js                # Firewall log viewer
│       ├── processing_log.js              # Processing log viewer
│       └── logtemplate.js                 # Shared log viewer class
└── po/                                    # Internationalization sources (i18n)
    └── zh_Hans/secbox.po                  # Simplified Chinese localization
```

---

## Configuration

UCI configuration file: `/etc/config/banip`

Supported CLI actions:

```bash
/etc/init.d/banip start      # Start security daemon and load NFT sets
/etc/init.d/banip stop       # Stop daemon and flush active sets
/etc/init.d/banip restart    # Full restart
/etc/init.d/banip reload     # Refresh feeds and reload sets
/etc/init.d/banip report gen # Generate latest set statistics report
/etc/init.d/banip actual     # Query active uplink and device bindings
```

---

## Maintainer

- **Maintainer**: permails <logo@permails.com>
- **License**: Apache-2.0
