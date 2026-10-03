# 🚫 Explicitly Excluded Features

The following features were considered but explicitly excluded:

## Prune Operations
- ❌ Container Prune - Already available via System Prune in Overview
- ❌ Image Prune - Already available via System Prune in Overview
- ❌ Network Prune - Already available via System Prune in Overview
- ❌ Volume Prune - Already available via System Prune in Overview
- ❌ Pod Prune - Already available via System Prune in Overview

**Reason:** Global system prune in overview.js handles all cleanup operations

## Image Management
- ❌ Image Tag - Not needed for typical use cases
- ❌ Image History - Not needed for typical use cases

**Reason:** Low value for typical OpenWrt/embedded use cases

## Advanced Features
- ❌ Container Exec - Too complex, SSH/CLI available
- ❌ Container Archive (Copy Files) - Too complex UI
- ❌ Container Checkpoint/Restore - May not work on OpenWrt (needs CRIU)
- ❌ Image Build - Too complex, build elsewhere and pull
- ❌ Generate Systemd Units - OpenWrt doesn't use systemd
- ❌ Manifest Management - Too niche
- ❌ System Events (Real-time Updates) - Events disabled on system (`events_logger = "none"`)
