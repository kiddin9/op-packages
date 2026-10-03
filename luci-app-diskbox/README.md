# LuCI DiskBox (`luci-app-diskbox`)

**A Modern Disk, Partition, RAID & Btrfs Manager for OpenWrt LuCI**

`luci-app-diskbox` is a standalone, lightweight, and modern disk management application designed for OpenWrt 21.02 / 23.05 / 24.10 / Master. Built with pure JavaScript client-side rendering and a dedicated RPCD backend, it operates smoothly without requiring `luci-compat`.

---

## Features

### 1. Storage Device Overview & S.M.A.R.T. Health
- **Multi-Device Support**: Full recognition of SCSI/SATA (`/dev/sd*`), NVMe (`/dev/nvme*`), MMC/eMMC (`/dev/mmcblk*`), and VirtIO (`/dev/vd*`) block storage devices.
- **Health & Temperature Monitoring**: Real-time S.M.A.R.T attribute scanning with critical bad-sector (05/C5) warnings and eMMC life-cycle/wear-level detection.
- **Visual Partition Usage**: Color-coded proportional capacity bars representing partition layouts.
- **Safe Ejection**: One-click software detachment (`sync` & SCSI device deletion) before physical unplugging to prevent kernel panics.

### 2. Partition Management
- **Partition Table Operations**: Initialize and switch between GPT and MBR partition tables.
- **Partition Creation**: Support for optimal 2048-sector alignment and human-readable capacity input in End Sector (`+500M`, `+10G`, `+1T`).
- **Safety Protection**: Accurate detection of MBR extended partitions and prevention of accidental deletion or formatting while logical partitions or mount points are active.
- **Multi-Filesystem Formatting**: Format partitions to `ext2`, `ext3`, `ext4`, `fat32`, `exfat`, `ntfs`, `btrfs`, or `swap`.

### 3. Software RAID (mdadm)
- **Array Creation**: Support for Linear, RAID 0, RAID 1, RAID 5, RAID 6, and RAID 10.
- **Dynamic Selection**: Standard LuCI dropdown menus to select member devices and partitions.
- **Auto Configuration**: Automatically generates UCI configurations and loads arrays upon system boot.

### 4. Btrfs Multi-Device & Snapshot Management
- **Filesystem Creation**: Support for multi-device Btrfs pools (`single`, `raid0`, `raid1`, `raid10`, `dup`).
- **Subvolumes**: Create, delete, and set default subvolumes.
- **Snapshots**: Fast creation of read-only or read-write snapshots with custom source and destination paths.

### 5. Mount Points
- **Active Mount Inspection**: Displays real-time mount paths and active mount options.
- **Quick Mount & Umount**: Easily mount unused partitions or unmount active mount points.

### 6. Internationalization (i18n)
- Seamless dynamic language switching following OpenWrt system language (English, Simplified Chinese, Traditional Chinese, Polish).

---

## Directory Structure

```text
luci-app-diskbox/
├── Makefile                         # OpenWrt package Makefile
├── htdocs/                          # Pure JavaScript frontend views
│   └── luci-static/resources/view/diskbox/
│       ├── disks.js                 # Overview, RAID, Btrfs & Mount points
│       ├── partition.js             # Partition management & formatting
│       └── btrfs.js                 # Btrfs detail & snapshot view
├── root/                            # RPCD backend and LuCI menu declarations
│   ├── etc/uci-defaults/99-luci-app-diskbox
│   ├── usr/libexec/rpcd/luci.diskbox
│   └── usr/share/
│       ├── luci/menu.d/luci-app-diskbox.json
│       └── rpcd/acl.d/luci-app-diskbox.json
├── po/                              # i18n translation catalogs
│   ├── templates/diskbox.pot
│   ├── zh-cn/diskbox.po
│   ├── zh-tw/diskbox.po
│   └── pl/diskbox.po
├── LICENSE
└── README.md
```

---

## Build from Source

Clone the repository directly into your OpenWrt buildroot's `package` directory:

```bash
# Navigate to your OpenWrt source root
cd openwrt

# Clone luci-app-diskbox
git clone https://github.com/permails/luci-app-diskbox.git package/luci-app-diskbox

# Update feeds and select in menuconfig
./scripts/feeds update -a
./scripts/feeds install -a
make menuconfig
```

Select the package in `menuconfig`:
```text
LuCI --->
  3. Applications --->
    <*> luci-app-diskbox................... Modern Disk Manager interface for LuCI
```

Compile the package:
```bash
make package/luci-app-diskbox/compile V=s
```

---

## Author

- **permails** ([https://github.com/permails/luci-app-diskbox](https://github.com/permails/luci-app-diskbox))

---

## License

Licensed under the [AGPL-3.0 License](LICENSE).
