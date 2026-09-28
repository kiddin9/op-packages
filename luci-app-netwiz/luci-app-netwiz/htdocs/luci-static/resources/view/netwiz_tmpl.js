'use strict';
'require view'; // 引入 LuCI 的 view 官方核心

return view.extend({ // 继承view
   // 1. 多语言字典
   T: {
      'Network_Wizard': _('Network Wizard'),
      'TITLE': _('Netwiz NETWORK SETUP'),
      'SUBTITLE': _('Pure · Secure · Non-destructive Minimalist Config'),
      'APP_VERSION': 'v0.1.0',
      'MODE_ROUTER_TITLE': _('DHCP / Static IP (WAN)'),
      'MODE_ROUTER_DESC': _('Automatically obtain IP from the upstream network, or manually set a static IP.'),
      'MODE_PPPOE_TITLE': _('PPPoE Dial-up'),
      'MODE_PPPOE_DESC': _('Dial up directly using account and password on this device.'),
      'MODE_LAN_TITLE': _('LAN Settings'),
      'MODE_LAN_DESC': _('Change device LAN IP, switch to AP Wired Relay mode, or one-click IPv6 distribution.'),
      'MODE_WIFI_TITLE': _('Wi-Fi Settings'),
      'MODE_WIFI_DESC': _('Set Wi-Fi name, password, enable Wireless Relay (WISP) and Seamless Roaming.'),
      'TITLE_WIFI': _('Configure Wi-Fi'),
      'LBL_SMART_CONN': _('Smart Connect (All Bands)'),
      'LBL_WIFI_SWITCH': _('Enable Wi-Fi'),
      'LBL_WIFI_2G_EN': _('Enable 2.4G Wi-Fi'),
      'LBL_WIFI_5G_EN': _('Enable 5G Wi-Fi'),
      'PH_WIFI_SSID': _('e.g., My_WiFi'),
      'LBL_SSID': _('Network Name (SSID)'),
      'LBL_WIFI_PASS': _('Wi-Fi Password'),
      'LBL_WIFI_ENC': _('Encryption'),
      'LBL_5G2_SSID': _('Network Name (5G_Game)'),
      'LBL_5G2_PWD': _('Wi-Fi Password (5G_Game)'),
      'LBL_ADVANCED': _('Advanced Settings'),
      'LBL_ADVANCED_CLOSE': _('Hide Advanced'),
      'LBL_HIDE_SSID': _('Hide Wi-Fi Name (SSID)'),
      'LBL_CHANNEL': _('Channel'),
      'LBL_BANDWIDTH': _('Channel Width'),
      'LBL_MODE': _('Wireless Mode'),
      'OPT_AUTO': _('Auto'),
      'LBL_LEGACY_B': _('Enable 802.11b (Legacy Mode)'),
      'DESC_LEGACY_B': _('Only enable if very old IoT devices cannot connect.'),
      'OPT_NONE': _('No Password (Open)'),
      'OPT_PSK2': _('WPA2-PSK (Stable)'),
      'OPT_SAE': _('WPA3-SAE (Secure)'),
      'OPT_PSK2SAE': _('WPA2/WPA3 Mixed (Recommended)'),
      'TAB_2G': _('2.4G Wi-Fi'),
      'TAB_5G': _('5G Wi-Fi'),
      'M_INC_WIFI': _('SSID cannot be empty.'),
      'M_PWD_SHORT': _('Wi-Fi password must be at least 8 characters.'),
      'ACT_WIFI': _('Applying Wi-Fi Settings'),
      'M_MODE_WARN_TIT': '⚠️ ' + _('Severe Warning'),
      'M_MODE_WARN_MSG': _('Forcibly modifying the wireless physical mode may cause the hardware driver to crash or the Wi-Fi to disappear permanently if the chip does not support it! It is highly recommended to keep it on [Auto].<br><br>Are you absolutely sure you want to change this?'),
      'LOADING_CONFIG': _('Reading underlying config...'),
      'BTN_HOME': _('Back to Home'),
      'TITLE_WAN': _('Configure WAN'),
      'LBL_CONN_TYPE': _('Connection Type'),
      'OPT_DHCP': _('DHCP (Auto)'),
      'OPT_STATIC': _('Static IP'),
      'LBL_IP': _('Static IP'),
      'LBL_GW': _('Gateway'),
      'PH_IP': _('e.g., 192.168.1.2'),
      'PH_GW': _('e.g., 192.168.1.1'),
      'TITLE_PPPOE': _('PPPoE Credentials'),
      'LBL_USER': _('PPPoE Username'),
      'PH_USER': _('Enter PPPoE username'),
      'LBL_PASS': _('PPPoE Password'),
      'PH_PASS': _('Enter PPPoE password'),
      'TITLE_LAN': _('Configure LAN'),
      'LBL_IPV6': _('Enable IPv6 (DHCPv6)'),
      'TIP_IPV6_DESC': _('When enabled, [Terminal Device & IP Binding] can assign short IPv6 addresses to PCs.'), 
      'LBL_FORCE_APPLY': _('Safe Mode (Recommended ON)'),
      'DESC_FORCE_APPLY': _('If enabled, the system will auto-revert if you lose connection within 120s.'),
      'MSG_SAFE_OFF': _('Safe mode disabled. Applying immediately without rollback protection...'),
      'LBL_BYPASS': _('Enable AP Wired Relay'),
      'WARN_BYPASS': _('<b style="font-size: 16px;">AP Wired Relay Enabled:</b><br>1. DHCP will be disabled. <b style="color: #059669;">Devices must use static IPs or get IPs from upstream.</b><br>2. If LAN IP changes, ensure your client is in the same subnet to avoid <b style="color: #059669;">losing access</b>.'),
      'WARN_MAIN': _('<b style="font-size: 16px;">Main Router Mode Enabled:</b><br>1. DHCP will be enabled. This device assigns IPs.<br>2. If LAN IP changes, ensure your client is in the same subnet to avoid <b style="color: #ef4444;">losing access</b>.'),
      'LBL_LAN_IP': _('Device LAN IP'),
      'LBL_LAN_GW': _('LAN Gateway'),
      // ===== 一键探测与拦截防呆新增 =====
      'BTN_AUTO_DETECT': _('Auto Detect'),
      'MSG_DETECT_SUCC': _('Upstream subnet detected, recommended IP assigned'),
      'MSG_DETECT_FAIL': _('Detection failed, cannot get upstream gateway'),
      'M_DETECT_OP_INV_TIT': _('Invalid Operation'),
      'M_DETECT_OP_INV_MSG': _('In Main Router mode, LAN Gateway MUST be empty.<br><br>"Auto Detect" is only for AP/Relay mode!'),
      'M_DETECT_PPPOE_TIT': _('Critical Intercept'),
      'M_DETECT_PPPOE_MSG': _('System detected WAN is <b style="color:#3b82f6;">PPPoE Dial-up</b>.<br><br>The acquired <b>{gw}</b> is the ISP BRAS gateway!<br><b style="color:#ef4444;">NEVER set this as LAN gateway</b>, or your network will crash!'),

      'PH_LAN_GW': _('Blank for Main, required for AP Wired Relay'),
      'BTN_BACK': _('Back'),
      'BTN_NEXT': _('Next Step'),
      'BTN_EDIT': _('Back to Edit'),
      'TITLE_CONFIRM': _('Confirm Configuration'),
      'DESC_CONFIRM': _('The following settings will be applied, please verify:'),
      'NOTE_TITLE': _('Application Notes:'),
      'NOTE_1': _('After confirmation, the network will restart and apply new settings.'),
      'NOTE_2': _('The system will auto-refresh or redirect in 15 seconds.'),
      'BTN_APPLY': _('Apply Settings'),
      'STAT_BYPASS': _('AP Wired Relay'),
      'CURRENT_MODE': _('Current:'),
      'STAT_MAIN_PPPOE': _('PPPoE Dial-up'),
      'STAT_SEC_DHCP': _('DHCP Client (Auto IP)'),
      'STAT_SEC_STATIC': _('Static IP'),
      'STAT_LAN': _('LAN Mode'),
      'TXT_DEV_IP': _('Device IP:'),
      'TXT_UP_GW': _('Upstream GW:'),
      'TXT_PUB_IP': _('Public IP:'),
      'TXT_REM_GW': _('Remote GW:'),
      'TXT_LAN_IP': _('LAN IP:'),
      'TXT_STATUS': _('Status:'),
      'TXT_WAIT_REM': _('Waiting for remote response'),
      'TXT_WAN_IP': _('WAN IP:'),
      'TXT_GET_IP': _('Getting IP...'),
      'TXT_DHCP_SRV': _('DHCP Service:'),
      'TXT_ON': _('Enabled'),
      'TXT_OFF': _('Disabled'),
      'BDG_SUCC': _('Dial Success'),
      'BDG_DIAL': _('Dialing / Disconnected'),
      'BDG_GOT': _('IP Acquired'),
      'BDG_WAIT': _('Waiting for IP...'),
      'BDG_CONN': _('Interface Connected'),
      'BDG_UNPLUG': _('Cable Unplugged'),
      'TXT_GETTING': _('Getting...'),
      'TXT_NOT_GOT': _('Not acquired'),
      'TXT_NOT_SET': _('Not set'),
      'M_INC_TIT': _('Incomplete info'),
      'M_INC_IP': _('Device IP cannot be empty.'),
      'M_INC_WAN': _('Static IP and Gateway cannot be empty.'),
      'M_INC_PPPOE': _('PPPoE username and password cannot be empty.'),
      'M_FMT_TIT': _('Format Error'),
      'M_FMT_IP': _('The device IP is invalid, please check!'),
      'M_FMT_WAN': _('WAN IP is invalid, please check!'),
      'M_FMT_GW': _('Gateway IP is invalid, please check!'),
      'M_LOGIC_TIT': _('Logic Error'),
      'M_LOGIC_BYP': _('AP Wired Relay requires an upstream gateway IP.'),
      'M_SAME_GW': _('WAN Static IP MUST NOT be the same as the gateway!'),
      'M_SAME_BYP': _('In AP/Relay mode, the device IP MUST NOT be the exact same as the Gateway! (') + '💡 ' + _('Tip: The Gateway should be the LAN IP of your upstream main router, and this device needs its own unique IP)'),
      'M_NO_MOD_TIT': _('No Changes Needed'),
      'M_NO_MOD_MSG': _('Your settings match the current router config exactly.'),
      'M_EXIT': _('Exit to Home'),
      'M_CFLT_TIT': _('Conflict Blocked'),
      'M_CFLT_IP': _('The WAN IP cannot be the same as the current LAN IP ({ip})!'),
      'M_CFLT_SUB1': _('The WAN port cannot be in the same subnet as the LAN ({ip})!'),
      'M_CFLT_SUB2': _('This causes a routing loop.'),
      'M_CFLT_SUGGEST': _('Suggestion: Your upstream network uses the same IP subnet. Please go to [LAN Settings] first and change your Device LAN IP (e.g. to 192.168.10.1) to prevent network crash.'),
      'M_SUB_ERR_TIT': _('Subnet Error'),
      'M_SUB_ERR_WAN1': _('The WAN Static IP must be in the same subnet as the Gateway!'),
      'M_SUB_ERR_WAN2': _('e.g., if gateway is {gw}, the IP must be {ip}.x'),
      'M_SUB_ERR_BYP': _('In AP/Relay mode, the device IP must be in the same subnet as the Gateway! (') + '💡 ' + _('Tip: The Gateway should be the LAN IP of your upstream main router)'),
      'M_WARN_TIT': _('Config Warning'),
      'M_WARN_MSG': _('You selected [Main Router Mode] but filled in the [Gateway].<br><br><b>For a standard main router, the gateway must be blank.</b> Entering a gateway may cause the device to fail at distributing network, leading to a total outage!<br><br>Are you sure you want to do this?'),
      'M_WARN_BTN': _('Force Apply'),
      'M_SYS_ERR': _('System Exception'),
      'M_SYS_MSG': _('Cannot read underlying config for validation, please refresh.'),
      'M_APP_MSG': _('Writing request, please wait...'),
      'M_RST_TIT': _('Applying Configuration'),
      'M_CLOSE': _('Close'),
      'M_ACCT': _('Account'),
      'M_PWD': _('Password'),
      'M_IP_GW': _('IP & Gateway'),
      'M_AUTO_UP': _('Auto-assigned by upstream router'),
      'LBL_TARGET': _('Target:'),
      'ACT_LAN': _('Modifying LAN IP'),
      'ACT_BYPASS': _('Switching to AP Wired Relay'),
      'ACT_WAN_DHCP': _('Switching WAN to DHCP'),
      'ACT_WAN_STATIC': _('Switching WAN to Static IP'),
      'ACT_PPPOE': _('Applying PPPoE Dial-up'),
      'MSG_WRITING': _('Writing configuration to system, please do not close the page...'),
      'MSG_KNOCKING': _('Connecting to new IP... Config will auto-rollback upon timeout.'),
      'MSG_WAIT_NET': _('Waiting for network service to restart... Elapsed: {sec}s'),
      'MSG_WAIT_OLD': _('Waiting for router to safely restore... Elapsed: {sec}s'),
      'MSG_TIMER': _('Rollback countdown: <b style="color:#f59e0b;">{sec}</b> / {total} s'),
      'MSG_MANUAL_VISIT': _('If IP changed, please update PC IP. Auto-redirecting when connected...'),
      'MSG_ABANDONING': _('Waiting for router to abort changes and restore network...'),
      'TXT_WIFI_STATUS': _('Wi-Fi Status'),
      'TXT_5G_ACCT': _('5G Wi-Fi Account'),
      'TXT_2G_ACCT': _('2.4G Wi-Fi Account'),
      'TXT_NO_PASS': _('No Password'),
      // 中继功能词条
      'LBL_WISP_EN': _('Enable Wireless Relay (WISP)'),
      'DESC_WISP': _('Receive upstream Wi-Fi and broadcast your own network.'),
      'BTN_SCAN': '🔄 ' + _('Scan Nearby Wi-Fi'),
      'MODAL_WISP_TITLE': _('Select Upstream Network'),
      'WISP_PWD_PROMPT': _('Password for upstream:'),
      'TXT_WISP_ON': _('WISP Enabled'),
      // 扫描与错误提示词条
      'TXT_SCANNING': '⏳ ' + _('Scanning...'),
      'TXT_NO_NETWORKS': _('No networks found.'),
      'TXT_SCAN_FAILED': _('Scan failed. Driver might be busy.'),
      'LBL_ROAMING': _('802.11k/v/r Fast Roaming'),
      'DESC_ROAMING': _('Enable seamless roaming between routers with one click (Prerequisite: Same SSID, password, and LAN). Note: May cause connection issues with older smart home (IoT) devices.'),
      'TXT_TARGET_SSID': _('Target Wi-Fi'),
      'PH_WISP_PWD': _('Upstream Wi-Fi Password'),
      'TXT_ROAM_DIRTY': '⚠️ ' + _('Manual Configuration Warning'),
      'DESC_ROAM_DIRTY': _('Underlying parameter mismatch detected, which may cause roaming failures. Please toggle this switch off and on again, then save to apply the standard seamless roaming profile.'),
      'TXT_ROAMING': _('Roaming'),
      'TXT_ROAMING_ON': _('Roaming Enabled'),
      'TXT_CLICK_FIX': _('Click to Fix'),
      'TXT_CLICK_GOTO': _('Click to Settings'),
      'MSG_WAN_AUTODETECT': _('WAN Blind-Switch: Unplug the WAN cable for 10 seconds and reconnect to auto-detect and switch the connection type (takes about 2 mins).'),
      'TXT_NEW_MOD': _('New Config'),
      'TXT_MODIFIED': _('Modified'),
      'M_OPEN_WARN_TIT': _('Security Warning'),
      'M_OPEN_WARN_MSG': _('You are setting up an Open Wi-Fi network without a password. Anyone nearby will be able to connect and access your network.<br><br>Are you sure you want to continue?'),
      // ===== 向导词条 =====
      'WIZ_TITLE': _('Quick Setup Wizard'),
      'WIZ_PWD': _('Step 1: Admin Password'),
      'WIZ_WAN': _('Step 2: Internet Setup'),
      'WIZ_WIFI': _('Step 3: Wi-Fi Setup'),
      'WIZ_CONFIRM': _('Step 4: Confirm & Apply'),
      'LBL_CONFIRM_PWD': _('Confirm Password'),
      'PH_CONFIRM_PWD': _('Enter password again'),
      'M_PWD_MISMATCH': _('Passwords do not match, please try again!'),
      'WIZ_SKIP': _('Skip this time'),
      'TXT_NOT_CONFIGURED': _('Not configured (Keep current)'),
      'WIZ_WIFI_DESC': _('Set your wireless network name and password.'),
      'WIZ_HIDE': _("Don't show this again"),
      'WIZ_REOPEN': '✨ ' + _('Reopen Wizard'),
      'WIZ_SKIP_WIFI': _('Skip Wi-Fi Setup (Keep current)'),
      'TXT_UNSET': _('Not set'),
      'TXT_NO_PWD_OPEN': _('No Password (Open)'),
      'BTN_DEV_BIND': _('Terminal Device & IP Binding'),
      'TXT_DNS1': _('Primary DNS:'),
      'TXT_DNS2': _('Secondary DNS:'),
      'TIP_IPV6_WARN':_('Non-standard parameters (Default configuration recommended)'),
      'PH_PWD_TIP': '💡 ' + _('This password will be used for logging into the router web interface and SSH. Setting it now is highly recommended.'),
      // ===== 新增防呆与冲突拦截词条 =====
      'M_WAN_DOWN_TIT': _('Cable Unplugged or Wrong Port'),
      'M_WAN_DOWN_MSG': _('System detected NO SIGNAL on the <b>WAN port</b>!<br><br><b style="color:#ef4444;">') + '💡 ' + _('Troubleshooting:</b><br>1. Did you plug the upstream cable into the <b>LAN port</b>?<br>2. Are both ends plugged in tightly? Is the modem powered on?<br>'),
      'M_WAN_DOWN_WAIT': _('Detecting in background... This will close automatically once connected.'),
      'BTN_IGNORE_WAN': _('I am an AP / Ignore for now'),
      'M_CFLT_GLOBAL_TIT': _('Severe Warning: Routing Loop'),
      'M_CFLT_GLOBAL_MSG': _('System detected that the upstream network (<b style="color:#ef4444;">{wan_ip}</b>) and the LAN (<b style="color:#ef4444;">{lan_ip}</b>) are in the same subnet!<br><br>This will crash the router. <b style="color:#059669;">Please confirm or modify the new LAN IP below and click auto-evade:</b><br><br>'),
      'BTN_FIX_CONFLICT': _('Modify and Restart Network'),
      'M_INVALID_IP_FMT': '❌ ' + _('Invalid IP format! System restored safe default, please confirm.'),
      'M_STILL_CONFLICT': '❌ ' + _('Still conflicting! The modified IP is still in the same subnet as upstream.') + '\n' + _('System restored safe default, please change the 3rd number!'),
      'M_WARN_UNSAVED': _('IMPORTANT:') + '\n\n' + 
               _('To resolve the fatal network loop, the system must change LAN IP and restart immediately.') + '\n\n' + 
               _('Changes you made on this page will NOT be saved.') + '\n' + 
               _('Please reconfigure after the network restarts and redirects to the new IP.') + '\n\n' + 
               _('Continue to fix conflict?'),
      'M_CFLT_INTERCEPT_TIT': _('Network Conflict Blocked'),
      'M_CFLT_WIZ_MSG': _('Upstream network ({wan_ip}) conflicts with local LAN ({lan_ip})!<br><br>Please click below to safely evade to: <b>{safe_ip}</b> to finish setup.'),
      'BTN_AUTO_EVADE': _('Auto Evade'),
      'M_CFLT_CROSS_TIT': _('Cross-Subnet Loop Blocked'),
      'M_CFLT_CROSS_MSG': _('The LAN IP ({ip}) you set is in the same subnet as your upstream network ({wan_ip}), which will crash the router!<br><br>Suggested evasion to: <b>{safe_ip}</b>'),
      'BTN_FIX_APPLY': _('Fix and Apply'),
      'BTN_EDIT_MYSELF': _('Edit Manually'),
      'M_CFLT_ROUTER_MSG': _('Upstream network ({wan_ip}) conflicts with local LAN ({lan_ip})!<br><br>You MUST change device LAN IP. Suggested evasion to: <b>{safe_ip}</b>'),
      'M_CFLT_PHYSICAL_TIT': _('Severe Physical Conflict'),
      'M_CFLT_PHYSICAL_WAN_MSG': _('The WAN Static IP ({ip}) you set is exactly the same as the upstream Gateway!<br><br>This causes a severe physical loop. Please change your Static IP (e.g., {suggest_ip}).'),
      'M_CFLT_PHYSICAL_BYP_MSG': _('The AP IP ({ip}) you set is exactly the same as the upstream Gateway!<br><br>This will paralyze the network. Please change to another free IP (e.g., {suggest_ip}).'),
      'LBL_NEW_PWD': _('Router Admin Password (Optional)'),
      'PH_NEW_PWD': _('Keep empty to retain current password'),
      'WIZ_SKIP_TITLE': _('Skip Wizard'),
      'WIZ_SKIP_MSG': _('Releasing wizard lock, entering official dashboard...'),
      'M_PWD_REQ': _('Please enter a new password or check "Skip Password Setup"!'),
      'TAG_SMART': _('Smart Connect'),
      'TAG_SPLIT': _('Independent Bands'),
      'TAG_WISP': _('WISP Repeater'),
      'TAG_DISABLED': _('Disabled'),
      'MSG_SYS_NOT_READY': _('The underlying network status is not fully loaded. Please wait before submitting to prevent configuration loss.'),
      'MSG_SETUP_DONE': _('Configuration complete! Automatically logging you in...'),
      'MSG_PWD_FAIL': _('Password setup failed: '),
      'MSG_NO_WIFI_TIP': _('No Wi-Fi hardware detected, this step will be skipped automatically.<br>Please click [Next Step] directly.'),

      // 高级与实验室功能词条
      'LBL_LAB_TITLE': _('Advanced & Lab Features'),
      'LBL_LAB_BETA': _('Beta'),
      'TXT_FULL_BACKUP_TIT': _('Full Software Backup & Restore'),
      'TXT_FULL_BACKUP_DESC': _('Resolves traditional backup soft-brick risks. Smart backup is cross-version compatible. After flashing new firmware, upload backup to <span style=\"color:#ef4444; font-weight:bold;\">rapidly reinstall all software and losslessly restore configs (Requires Internet)</span>. Does not delete current software during restore. For absolute purity, factory reset the router first.<br><span style=\"color:#ef4444; font-weight:bold;\">Tip: If the backup shows Missing packages, manually place the installation packages in the /etc/netwiz/custom_pkgs/ directory.</span><br>If Netwiz is missing after a reset or needs an upgrade, connect to the internet and run this in SSH:'),
      'BTN_SMART_BACKUP': '📦 ' + _('Generate Backup'),
      'BTN_SMART_RESTORE': '⚡ ' + _('Restore System'),
      'TXT_COPY_TIP': '📋 ' + _('Click to Copy'),
      'TXT_COPIED': '✅ ' + _('Copied'),
      'TXT_COPY_FAIL': '❌ ' + _('Copy Failed'),

      // 备份提示
      'M_BAK_SEL_TIT': '📦 ' + _('Select Backup Mode'),
      'M_BAK_LIGHT_TIT': _('Lightweight Backup'),
      'M_BAK_LIGHT_SUB': _('Recommended'),
      'M_BAK_FULL_TIT': _('Full Backup'),
      'M_BAK_FULL_SUB': _('Includes Dependencies'),
      'M_BAK_LIGHT_DESC': _('<b style="color: #F00;">Lightweight Backup:</b> Only packs core configs (Passwords/Wi-Fi/IP) and main plugin packages. Fast and requires no extra RAM. Requires internet or built-in dependencies when restoring.'),
      'M_BAK_FULL_DESC': _('<b style="color: #F00;">Full Backup:</b> Packs core configs and recursively downloads ALL underlying dependencies for third-party plugins. Large size, slower generation. <b style="color: #F00;">NO internet required</b> during restore. Recommended for devices with >256MB RAM.'),
      'BTN_START_BAK': _('Start Backup'),
      'M_BAK_GEN_TIT': '📦 ' + _('Generating Backup'),
      'M_BAK_GEN_MSG': _('Extracting configs and packing files in background...'),
      'M_BAK_HINT_FULL': _('Note: Full mode selected, downloading all dependencies. Takes 1-3 mins, please wait.'),
      'M_BAK_HINT_LIGHT': _('Note: Lightweight mode selected, packing is very fast (~30s).'),
      'M_BAK_SUCC_TIT': '✅ ' + _('Backup Successful'),
      'M_BAK_SUCC_MSG': _('Backup capsule downloaded. Upload this file after flashing new firmware to restore.'),
      'M_BAK_FAIL_TIT': '❌ ' + _('Backup Failed'),
      'M_BAK_FAIL_MSG': _('Unable to start background backup task.'),

      // 恢复提示
      'M_RST_CONFIRM_TIT': '⚡ ' + _('Confirm System Restore'),
      'M_RST_CONFIRM_MSG': _('<span style="color:#ef4444; font-weight:bold;">WARNING: This will overwrite current configs and reinstall plugins!</span><br><br>Router will auto-reboot upon completion. Ensure file is correct.<br><br><span style="color:#059669; font-size: 14px;">') + '🛡️ ' + _('Safe Mode: Auto-rollback if connection is lost for 300s.</span><br><br>'),
      'M_RST_REGRET_PILL': _('Auto-download current state backup before restore (Regret Pill)'),
      'BTN_CONFIRM_SEL': _('Confirm & Select File'),
      'M_RST_NATIVE_TIT': '⚡ ' + _('Native Fast Restore Mode'),
      'MSG_RESTORE_UPLOADING': _('Transferring capsule via high-speed system channel...<br><br><b style="color:#ef4444;">DO NOT power off. Router will auto-reboot upon completion.</b><br><br><span style="color:#059669; font-size: 14px;">') + '🛡️ ' + _('Safe Mode: Auto-rollback if connection is lost for 300s.</span>'),
      'M_ERR_WIZ_FAILED': _('Wizard execution failed'),
      'M_ERR_DATA_PROC': _('Configuration data processing failed'),
      'M_ERR_VALIDATE': _('Input validation failed'),
      'M_RST_DELIVERED': '✅ ' + _('Capsule delivered, preparing offline task...'),
      'M_RST_BLOCKED_TIT': '❌ ' + _('Restore Blocked by Security'),
      'M_RST_BLOCKED_MSG': _('Self-healing mechanism triggered. Garbage cleared, router is safe and unharmed.'),
      'M_RST_TRANS_FAIL': '❌ ' + _('Transfer Failed'),
      'M_RST_TRANS_REJECT': _('Interface rejected reception, status code: '),
      'M_RST_NET_ERR': '❌ ' + _('Network Error'),
      'M_RST_NET_INTR': _('File transfer interrupted unexpectedly, check network!'),
      'M_RST_PILL_TIT': '💊 ' + _('Preparing Regret Pill'),
      'M_RST_PILL_MSG': _('Backing up current state to prevent regrets...<br><br><span style="font-size:12px; color:#10b981;">Tip: Restore will begin automatically after download</span>'),
      'M_RST_PROBE_TIT': '🔍 ' + _('Probing Environment'),
      'M_RST_PROBE_MSG': _('Calculating system available RAM and storage...'),
      'M_BAK_OOM_TIT': '⚠️ ' + _('Critical RAM Shortage'),
      'M_RST_OOM_MSG': _('Your full capsule size is <b style="color:#ef4444;">{size} MB</b>.<br><br>But /tmp (RAM) only has <b style="color:#ef4444;">{avail} MB</b> free!<br><br>Force uploading will <b style="color:#f00;">cause OOM, crash, and network drop</b>.<br><br><b>Solution:</b> Please <b style="color:#10b981;">reboot the router</b> once to clear RAM fragments, then retry.'),
      'BTN_CANCEL_RST': _('Cancel Restore'),

      // 后端执行状态映射代码
      'MSG_RST_WAIT': _('Waiting for background task to start...'),
      'MSG_RST_INIT': _('Capsule delivered, initializing restore environment...'),
      'MSG_RST_SCAN': _('Scanning capsule structure to estimate uncompressed size (5-10s)...'),
      'MSG_RST_OOM_INTERCEPT': _('Uncompressed size reaches {u}MB, but RAM only has {a}MB left! Intercepted to prevent router crash.'),
      'MSG_RST_SAFE': _('Size safe! Extracting backup capsule...'),
      'MSG_RST_FAIL': _('Extraction failed! Capsule may be corrupted, initiating self-healing...'),
      'MSG_RST_CONF': _('Extraction successful, applying core configs...'),
      'MSG_RST_PKGS': _('Force offline installing plugins (this takes a while, please wait)...'),
      'MSG_RST_DONE': _('Restore thoroughly complete! Router will auto-reboot!'),
      'MSG_RST_INVALID': _('Invalid capsule file! NetWiz signature missing, intercepted for security.'),
      'V6_NAT_ERR_TIT1': '🚨 ' + _('Severe Network Topology Conflict!'),
      'V6_NAT_ERR_MSG1': _('System detected that IPv6 and LAN "Masquerading (NAT)" are <b>BOTH enabled</b>!This will paralyze IPv6 allocation and cause routing loops.<br>%s<b>Fix:</b> Please go to <code>Network -> Firewall</code> to disable LAN Masquerading, or <b style="color:#ef4444;">Disable IPv6</b> in the LAN settings on the Netwiz homepage.').replace('%s', '👉 '),
      'V6_NAT_ERR_TIT2': '⚠️ ' + _('IPv6 Configuration Blocked'),
      'V6_NAT_ERR_MSG2': _('Detected that LAN "IP Masquerading (NAT)" is enabled. Forcing IPv6 on under a double-NAT topology will cause network disconnection.<br>%s<b>Fix:</b> Please go to <code>Network -> Firewall -> Zones</code> to disable LAN Masquerading first.').replace('%s', '👉 '),
      'MSG_REBOOTING': _('System is rebooting, please wait...'),
      'MSG_WAIT_OFFLINE': _('Waiting for device to disconnect...'),
      'TIT_IP_CONFLICT': _('IP Conflict Warning'),
      'MSG_IP_IN_USE': _('is already used by another device!'),
      'MSG_SUGGEST_FIX': _('We strongly recommend changing it to avoid network crashes.'),
      'BTN_FIX_IP': _('Fix to'),
      'MSG_SCAN_PKGS': _('Scanning installed plugins...'),
      'TIT_PKG_CHECK': _('Plugin Backup Status'),
      'MSG_CUSTOM_PKG_DESC': _('Please verify backup packages:'),
      'MSG_CUSTOM_PKG_ACT': _('If you proceed, missing plugins WILL NOT be restored automatically!'),
      'MSG_CUSTOM_PKG_TIP': _('Tip: Manually place missing packages .ipk/.apk into the /etc/netwiz/custom_pkgs/ directory via SSH to ensure they are automatically reinstalled during future restorations.'),
      'BTN_IGNORE_BAK': _('Ignore & Backup'),
      'TIT_ARCH_CONFLICT': _('Architecture Conflict Warning'),
      'MSG_RESTORE_ARCH_TIP': _('Architecture Safety Lock: Cross-package manager restoration (e.g., IPK to APK) is strictly prohibited. The underlying network and firewall configurations differ significantly across these system versions. Forcing a restore will cause severe network failure and brick your router!'),
      'BTN_FORCE_RESTORE': _('Force Restore Config'),
      'TXT_MISSING_PKGS': _('Missing packages:'),
      'TXT_PROVIDED_PKGS': _('Manually placed in custom_pkgs:'),
      'TIT_CUSTOM_PKG_READY': _('Custom Plugins Ready'),
      'MSG_CUSTOM_PKG_READY_DESC': _('Great! Your custom plugins are safely stored in the local directory and will be included in the backup capsule.'),
      'BTN_CONFIRM_BACKUP': _('Confirm Backup'),
      'TXT_OFFICIAL_PKGS': _('Auto-backup plugins:'),
      'TIT_OFFICIAL_PKG_READY': _('Plugin Scan Complete'),
      'MSG_OFFICIAL_PKG_READY_DESC': _('System scan complete! All your installed plugins are from the official repository and will be safely recorded for automatic restoration.'),
      'M_OOM_TITLE': '⚠️ ' + _('Backup Interrupted Warning'),
      'M_OOM_HEAD': _('Out of Memory (OOM Protection)!'),
      'M_OOM_DESC': _('The files you are trying to pack are too large and exceed the available memory.<br><br>To prevent device crash, the backup task has been safely canceled. Please clear unnecessary core files and try again.'),
      'M_I_KNOW': _('I Got It'),
      'M_SCAN_TIMEOUT_TITLE': '⚠️ ' + _('Scan Timeout Warning'),
      'M_SCAN_TIMEOUT_HEAD': _('Communication Timeout or Network Error'),
      'M_SCAN_TIMEOUT_DESC': _('Communication with the router timed out (possibly due to slow network source retrieval or network fluctuations).<br><br>To ensure backup integrity, the task has been safely canceled. Please try again later, or manually run opkg update via SSH.'),
      'TXT_WISP_WAITING': _('Connecting...'),
      'MSG_WISP_STUCK': '⚠️ ' + _('Connecting to upstream... (Check password or signal strength if stuck)'),
      'M_FIRST_SYNC_TITLE': '🔄 ' + _('First Time Syncing'),
      'M_FIRST_SYNC_SUB': _('Syncing lists in the background...'),
      'M_FIRST_SYNC_DESC': _('Verifying the list of plugins for automatic backup...<br><br>Depending on the network, this usually takes <b>15 to 20 seconds</b>.<br>The system is verifying, please wait...'),
      'M_SYNC_OK': _('OK, I will try again later'),
      'MSG_RST_PKG_ERR': '🚨 ' + _('RESTORE FAILED: Package manager mismatch (apk vs ipk). Please use firmware with the same underlying system.'),
      'MSG_RST_ARCH_ERR': '🚨 ' + _('RESTORE FAILED: CPU Architecture mismatch. Forcing this restore will brick your router! Process aborted.'),
      'TIT_PKG_CONFLICT': _('Package Manager Conflict'),
      'TIT_ARCH_CONFLICT': _('CPU Architecture Conflict'),
      'MSG_PKG_ERR_APK':  '🚨 ' + _('Your current system uses the apk architecture, but you are trying to flash an ipk backup!'),
      'MSG_PKG_ERR_OPKG':  '🚨 ' + _('Your current system uses the opkg architecture, but you are trying to flash an apk backup!'),
      'MSG_ARCH_ERR_UI': _('Architecture mismatch! (Current router: {arch})'),
      'MSG_ARCH_ERR_DESC': _('The backup package you selected belongs to a different hardware architecture. Forcing this restore will brick your router!'),
      'MSG_FAST_BLOCK': _('The frontend security system has instantly blocked this dangerous operation.'),
      'TIT_ARCH_WARN': _('Architecture Warning'),
      'MSG_ARCH_WARN_1': _('No architecture identifier ({arch}) detected in the selected backup filename.'),
      'MSG_ARCH_WARN_2': _('If you have <b>manually renamed</b> this file, please ignore this warning.<br><br><span style="color:#ef4444;">If it is the wrong package, the system\'s underlying security mechanism will forcibly intercept the restoration later!</span>'),
      'BTN_WARN_CONTINUE': _('I understand, continue'),
      'TXT_SCAN_TO_CONN': _('Scan to Connect'),
      'WARN_PPPOE_INVALID': '⚠️ ' + _('Current WAN is in DHCP/Static mode. PPPoE settings will not take effect until applied.'),
      'WARN_ROUTER_INVALID': '⚠️ ' + _('Current WAN is in PPPoE mode. DHCP/Static settings will not take effect until applied.'),
      // ===== 高级设置 =====
      'LBL_ADV_UTILS_TITLE': '⚙️ ' + _('Advanced Utilities'),
      'LBL_MAC_CLONE_LINK': '🔗 ' + _('MAC Address Clone'),
      'LBL_CRON_REBOOT_LINK': '⏱️ ' + _('Scheduled Reboot'),
      'LBL_WEB_ACCESS_TOGGLE': '🌐 ' + _('IPv6 Web Access, Port:'),

      'MSG_MAC_CLONE_TIP': '💡 ' + _('<b>Tip:</b> Some ISPs or campus networks bind to a specific device MAC. If dial-up fails, enter the cloned MAC here.'),
      'BTN_GET_MAC': '⚡ ' + _('Auto-fill MAC'),
      'MSG_MAC_NOT_FOUND': _('No active device connection detected, please enter MAC address manually.'),

      'LBL_CRON_ENABLE': _('Enable Scheduled Reboot'),
      'LBL_CRON_TIME': _('Reboot Time:'),
      'LBL_CRON_DAYS': _('Repeat Days (Multi-select):'),
      'MSG_CRON_NO_DAY': _('Please select at least one day!'),

      'LBL_DAY_1': _('Mon'),
      'LBL_DAY_2': _('Tue'),
      'LBL_DAY_3': _('Wed'),
      'LBL_DAY_4': _('Thu'),
      'LBL_DAY_5': _('Fri'),
      'LBL_DAY_6': _('Sat'),
      'LBL_DAY_0': _('Sun'),

      'BTN_ADV_HIDE': _('Advanced Settings') + ' ▲',
      'BTN_ADV_SHOW': _('Advanced Settings') + ' ▼',

      'LBL_CRON_REBOOT': _('Scheduled Reboot'),
      'LBL_MAC_CLONE': _('MAC Clone'),
      'BTN_CLEAR': '🗑️ ' + _('Clear (Restore Default)'),
      'TXT_NET_OK': _('Internet Connected'),
      'TXT_NET_FAIL': _('Internet Disconnected'),
      'BTN_CANCEL': _('Cancel'),
      'BTN_OK': _('OK'),
      'M_CANCEL': _('Ignore'),
      'M_FMT_MAC':_('Invalid MAC address format!'),
      'PH_MAC': _('e.g., AA:BB:CC:DD:EE:FF'),
      'MSG_MULTI_WAN':'💡 ' + _('Multi-WAN detected. You can modify the account and password for each line separately (other settings remain unchanged).'),
      'MSG_WIZ_MULTI_WAN':'💡 ' + _('Multi-WAN detected. Only the primary WAN will be configured here, other lines remain unchanged.'),
      'LBL_IFACE':_('Interface:'),
      'LBL_HOSTS_LINK': '✏️ ' + _('Custom Hosts'),
      'LBL_HOSTS_TITLE': _('Custom <a href="javascript:void(0)" id="nw-hosts-raw-toggle" style="color:red; text-decoration:underline dashed; transition:color 0.2s;" title="Click to toggle pure text advanced mode">Hosts</a>') + '👈 ' + _('(Domain Hijack)'),
      'LBL_HOSTS_VISUAL': '💡 ' + _('Quick Add:'),
      'BTN_HOSTS_ADD': '➕ ' + _('Add'),
      'TXT_HOSTS_EMPTY': _('No custom Hosts, please add below.'),
      'PH_HOSTS_IP': _('IP (e.g., 127.0.0.1 or ::1)'),
      'PH_HOSTS_DOMAIN': _('Domain (e.g., abc.com)'),
      'PH_HOSTS_CMT': _('Comment (Optional)'),
      'LBL_HOSTS_RAW_TIP': '💡 ' + _('<b>Pure Text Mode</b>: <b>Paste</b> to import, <b>Copy</b> to export. Format: <code>IP Domain #Comment</code>'),
      'MSG_HOSTS_REQ': _('IP and Domain cannot be empty!'),
      'M_FMT_IP': _('Invalid IP address format!'),
      'M_FMT_DOMAIN': _('Invalid domain! Spaces, wildcards (*), and special characters are not allowed.'),
      'MSG_NO_CHANGE': _('No changes have been made.'),
      'M_INC_TIT': _('Notice'),
      'MSG_WAIT': _('Please wait...'),
      'MSG_HOSTS_DUP': _('This IP and Domain combination already exists!'),
      'MSG_HOSTS_DUP_RAW': _('Duplicate records found in Hosts! Please remove them before continuing.'),
      'LBL_SMART_ADD': _('Smart Auto-fill'),
      'TIP_SMART_ADD': _('Auto-fill IPv4/v6 & www domain combinations'),
      'LBL_HOSTS_DESC': '💡 ' + _('This feature forces specific domains to resolve to designated IPs. Commonly used for blocking domain access or local device redirection.'),
      'MSG_RAW_ERR_1': _('Found invalid or duplicate records:'),
      'MSG_RAW_ERR_2': _('Click [OK] to automatically discard them and continue, or [Cancel] to manually fix them.'),
      // --- 插件修复急救箱 ---
      'LBL_REPAIR_BTN': '🚑 ' + _('Plugin Repair'),
      'M_REP_SCAN_TIT': _('Please wait'),
      'M_REP_SCAN_MSG': _('Scanning for repairable plugins...'),
      'M_REP_DESC': _('Standard uninstallation does not remove plugin configuration files. If a plugin malfunctions after reinstallation, select it below to reset it to its initial state.'),
      'M_REP_OPT': _('Factory Default'),
      'M_REP_TIT': '🚑 ' + _('Plugin Repair Toolkit'),
      'M_REP_OK': _('Repair Now'),
      'M_REP_PROC_TIT': _('Processing'),
      'M_REP_PROC_MSG1': _('Repairing and restarting'),
      'M_REP_SUCC_TIT': _('Repair Successful'),
      'M_REP_SUCC_MSG': _('has been successfully restored'),
      'M_REP_FAIL_TIT': _('Repair Failed'),
      'M_REP_FAIL_MSG': _('Unable to repair this plugin'),
      'M_REP_ERR_TIT': _('System Error'),
      'M_REP_ERR_MSG': _('Request timeout or error'),
      'M_HW_WAIT': _('Hardware execution takes longer, running in background...'),
      'M_REP_NOTICE_TIT': _('Notice'),
      'M_REP_EMPTY_MSG': _('No repairable plugins found'),
      'M_REP_GET_ERR': _('Failed to get plugin list'),
      // --- 孤件拔除警告词条 ---
      'M_REP_GHOST_TIT': '💀 ' + _('Ghost Plugin Deletion Warning'),
      'M_REP_GHOST_MSG': _('Executing this will uninstall the software and delete its config files. However, no installation package was found, so you will need to manually reinstall it later.'),
      'BTN_ERADICATE': '🗑️ ' + _('Eradicate Completely'),
      'M_ERADICATE_PROC': _('Eradicating completely...'),
      'M_ERADICATE_SUCC': _('has been completely uninstalled and cleaned.'),
      // --- 重裝指南 ---
      'M_GUIDE_TITLE': '💡 ' + _('Offline Reinstall Guide'),
      'M_GUIDE_DESC': _('To reinstall the plugin, it is highly recommended to use the <b>[%s]</b> feature in the Advanced Utilities panel for quick drag-and-drop setup.<br><br><b>If conflicts occur or the menu is missing</b>, you can upload the package via SSH to <b>/etc/netwiz/custom_pkgs/</b> and use the Force Install command:').replace('%s', '📦 ' + _('Plugin Installation')),
      'M_GUIDE_CMD_APK': 'apk add --allow-untrusted --force-reinstall --force-overwrite /etc/netwiz/custom_pkgs/XXXXXXX_your_name.apk',
      'M_GUIDE_CMD_OPKG': 'opkg install --force-reinstall --force-overwrite /etc/netwiz/custom_pkgs/XXXXXXX_your_name.ipk',
      // ---------------------------
      'M_PORT_RANGE': '⚠️ ' + _('Port number must be between 1 and 65535'),
      'M_PORT_ERR1': '⚠️ ' + _('For system security, do not use'),
      'M_PORT_ERR2': _('as the external port. It is a reserved high-risk port.'),
      'M_PORT_SUGG': _('It is recommended to use 8080 or a port above 10000.'),
      'LBL_WEB_PORT_TITLE': _('Enter custom external port number'),
      'M_PORT_CONFLICT_P1': _('Port'),
      'M_PORT_CONFLICT_P2': _('is already in use by another application!'),
      // ---------------------------
      'LBL_MOD_LAYOUT':  '⚙️ ' + _('Advanced Panel Management'),
      'ADV_LAYOUT_TIP': _('Drag ☰ to reorder, check to show/hide:'),
      'ADV_LAYOUT_SAVE': _('Save and Apply'),
      'ADV_SAFE_BTN': '📦 ' + _('Plugin Installation'),
      'ADV_SAFE_TITLE': _('Offline Plugin Installation'),
      'ADV_SAFE_DESC': _('Drop or click to select multiple .apk / .ipk files'),
      'ADV_ONLY_PKG': _('Security Block: Only .apk and .ipk allowed!'),
      'ADV_BTN_START': '🚀 ' + _('Start Upload & Secure'),
      'ADV_BTN_CONFIRM': '🚀 ' + _('Confirm Upload ({num} files)'),
      'ADV_BTN_PROC': _('Processing, do not close the window...'),
      'ADV_ERR_FORMAT': _('Format blocked!'),
      'ADV_MSG_ALL_DONE': '✅ ' + _('All files secured! Refreshing...'),
      'ADV_MSG_BATCH_INST': '⚙️ ' + _('All files secured, executing batch install...'),
      'ADV_MSG_INST_OK': '✅ ' + _('Installation successful! Refreshing...'),
      'ADV_MSG_HW_WAIT': '⚙️ ' + _('Hardware configuring, please wait <b id="nw-batch-cnt">{sec}</b>s...'),
      'ADV_ERR_BATCH': '❌ ' + _('Batch install error: '),
      'ADV_MSG_PROC_FILE': '🚀 ' + _('Processing ({idx}/{total}): {name} - {pct}%'),
      'ADV_MSG_BG_SECURE': '⚙️ ' + _('Securing in background: {name}'),
      'ADV_ERR_MV': '❌ ' + _('Backend transfer failed: {name}'),
      'ADV_ERR_UP': '❌ ' + _('Upload failed ({code}): {name}'),
      'ADV_ERR_NET': '❌ ' + _('Network disconnected: {name}'),
      'ADV_BTN_RETRY': _('Continue to retry remaining files'),
      'ADV_SAFE_BACKUP': _('Keep a permanent backup in /etc/netwiz/custom_pkgs'),
      'ADV_BTN_REMOVE': _('Remove'),
      'ADV_ERR_SAVE_LAYOUT': _('Save layout failed'),
      'ADV_WARN_NO_WIFI': _('Warning: No Wi-Fi hardware detected, Wi-Fi configuration card is hidden.'),
      'LBL_WATCHDOG_LINK': '📡 ' + _('IPv6 Watchdog'),
      'WOG_TITLE': _('IPv6 Heartbeat Probe'),
      'WOG_ENABLE': _('Enable Advanced IPv6 Link Monitoring & Auto Recovery'),
      'WOG_URL_LBL': _('Probe Target URL'),
      'WOG_URL_PH': _('e.g., XXXXX-XXXXX.workers.dev'),
      'WOG_HELP': '<div style="font-size:13px; color:#475569; line-height:1.6; text-align:left;">' +
                  '💡 <b>' + _('Note:') + '</b><br>' +
                  _('The server must parse this address and perform a live test:') + ' <b style="color:#ef4444; padding:0 2px;">' + _('Your_URL/[IPv6_Address]:Port') + '</b>. ' +
                  _('If the network is accessible, it must return the plain text') + ' <code style="background:#e2e8f0; padding:2px 4px; color:#ef4444; border-radius:3px;">OK</code>.<br><br>' +
                  '✍️ <b>' + _('Examples:') + '</b><br>' +
                  '<code style="background:#e2e8f0; padding:2px 6px; border-radius:4px; color:#0f172a; margin-top:2px; margin-bottom:4px; display:inline-block; word-break:break-all;">netwiz-probe.xxxx.workers.dev</code> ' + '<br>' +
                  '<code style="background:#e2e8f0; padding:2px 6px; border-radius:4px; color:#0f172a; margin-bottom:8px; display:inline-block; word-break:break-all;">http://your-vps-ip:18080</code> ' + _('<a href="https://raw.githubusercontent.com/huchd0/luci-app-netwiz/refs/heads/master/probe.py" target="_blank" style="color:#0284c7; text-decoration:underline; font-weight: bold;">' + _('(VPS_IPv6)')  + '</a>') + '<br>' +
                  '🔗 <a href="https://raw.githubusercontent.com/huchd0/luci-app-netwiz/refs/heads/master/worker.js" target="_blank" style="color:#0284c7; text-decoration:underline; font-weight: bold;">' + _('Click to view Cloudflare tutorial & source code') + '</a>' +
                  '</div>',
      'MSG_WOG_LINKAGE': _('To ensure the works correctly, the following dependent features have been automatically enabled:'),
      'MSG_WOG_LINK_V6': _('IPv6 Master Switch'),
      'MSG_WOG_LINK_WAN': _('WAN Access Web UI Channel'),
      'MSG_SEC_NOTICE': _('Security Notice'),
      'MSG_WOG_OFF_WAN': _('WAN access is about to be closed. To ensure complete firewall protection, the system will simultaneously disable the IPv6 Watchdog mechanism.'),
      'MSG_DEP_NOTICE': _('Dependency Notice'),
      'MSG_WOG_OFF_V6_ALL': _('You have disabled IPv6. To ensure security, the dependent IPv6 Watchdog and WAN Access will be automatically disabled.'),
      'ERR_EMPTY_URL': _('Probe URL cannot be empty, please fill it in before saving!'),
      'U_NEW_TITLE': '✨ ' + _('New Version Found'),
      'U_READY_MSG': _('Ready to install the update?'),
      'U_BTN_NOW': _('Update Now'),
      'U_BTN_LATER': _('Later'),
      'U_UPGRADING_TITLE': '🔄 ' + _('System Upgrading'),
      'U_UPGRADING_MSG': _('Downloading and replacing core files, please do not power off...'),
      'U_UPGRADING_WAIT': '⏳ ' + _('Forcing system file overwrite... (Est. {sec}s remaining)'),
      'U_INST_SUCC_TIT': '🎉 ' + _('Upgrade Successful!'),
      'U_INST_SUCC_MSG': _('The new version core has been deployed in the background!'),
      'U_INST_SUCC_DESC': '⚠️ ' + _('<b>Notice: Aggressive browser caching detected.</b><br>To ensure new menus and features display correctly, please press <kbd style="background:#fff; padding:2px 6px; border:1px solid #ccc; border-radius:4px; box-shadow:0 1px 1px rgba(0,0,0,0.2); color:#000;">Ctrl + F5</kbd> or <kbd style="background:#fff; padding:2px 6px; border:1px solid #ccc; border-radius:4px; box-shadow:0 1px 1px rgba(0,0,0,0.2); color:#000;">Shift + F5</kbd> to force refresh this page!<br><span style="font-size:13px; color:#64748b; font-weight:normal;">(Mobile users: please manually clear browser cache and refresh)</span>'),
      'MSG_ABOUT_TO_ENABLE': _('You are about to enable the <b>[%s]</b>.'),
      'MSG_ABOUT_TO_DISABLE': _('You are about to disable the <b>[%s]</b>.'),
      'MSG_SUGGESTION': _('Suggestion:'),
      'MSG_WOG_SUGGEST_MSG': _('No target URL is configured for the Watchdog. For long-term stability, it is recommended to manually configure and enable it in %s later.'),

      'BTN_GENERATE_BACKUP': _('Backup Config'),
      'BTN_RESTORE_SYSTEM': _('Restore Config'),
      // ==========================================
      // 备份相关
      // ==========================================
      'M_BAK_ING_TIT': _('Backing up'),
      'M_BAK_ING_MSG': _('Precisely packing %s config and generating download, please wait...'),
      'M_BAK_SUCC_MSG': _('The file contains core assets and is downloading in the background. Please check your browser!'),
      'M_BAK_FAIL_TIT': _('Backup Failed'),
      'M_BAK_FAIL_MSG': _('Config not found or packaging error. Please check if the plugin is installed.'),

      // ==========================================
      // 恢复相关
      // ==========================================
      'M_RST_CONF_TIT': _('Restore Configuration Confirm'),
      'M_RST_CONF_WARN': _('Warning: Restoring the configuration will overwrite all current settings and automatically restart the router upon completion!'),
      'M_SEL_FILE': _('Selected file: %s'),
      'BTN_RST_START': _('Confirm Restore'),
      'M_RST_CONF_TIT_ING': _('Restoring Configuration'),
      'MSG_RESTORE_UPLOADING': _('Uploading backup file, please do not disconnect power...'),
      'M_RST_DELIVERED': _('File delivered, starting restore...'),
      'MSG_REBOOTING': _('System is restarting...'),
      'M_RST_CMD_SENT': _('Restore command issued, device may be restarting...'),
      'M_RST_ING_TIT': _('Restoring'),
      'M_RST_ING_MSG': _('Uploading and restoring %s config...'),
      'M_RST_SUCC_TIT': _('Restore Successful'),
      'M_RST_SUCC_MSG': _('%s config file has been restored and reloaded!'),
      'M_RST_FAIL_TIT': _('Restore Failed'),
      'M_RST_FAIL_MSG': _('Failed to extract or restart service.'),
      'M_RELOAD': _('Reload Page'),

      // ==========================================
      // 网络与报错相关
      // ==========================================
      'M_REQ_FAIL_TIT': _('Request Failed'),
      'M_REQ_FAIL_MSG': _('API request failed: %s'),
      'M_UPL_FAIL_TIT': _('Upload Failed'),
      'M_UPL_FAIL_MSG': _('File upload rejected, status code: %s'),
      'M_UPL_FAIL_STAT': _('Upload failed: %s'),
      'M_SYS_ERR': _('Error'),
      'M_RST_NET_ERR': _('Network Error'),
      'M_RST_NET_INTR': _('Network connection unexpectedly interrupted!'),

      'M_FMT_ERR_TIT': _('Format Error'),
      'M_FMT_ERR_MSG': _('Please upload a valid .tar.gz backup file!'),
      'M_WARN_TIT': _('Warning'),
      'M_WARN_MSG': _('The selected file does not seem to belong to %s.<br>File name: %f<br>Are you sure you want to continue?'),
      'BTN_FORCE_RST': _('Force Restore'),
      'M_ERR_FILE_CORRUPT': _('The uploaded file is corrupted or not a valid archive!'),
      'M_ERR_FILE_MISMATCH': _('The archive content does not match %s!'),
      'M_RST_SUCC_MSG': _('%s config restored! Service is restarting in the background...'),
      'M_AUTO_RELOAD': _('Auto reloading in %s seconds...'),
      'M_ERR_EXTRACT': _('Failed to extract files to the system! (Storage full or permission denied)'),
   },

   // 2. HTML 结构
   html: `
   <link rel="stylesheet" type="text/css" href="{{CSS_URL}}">
   <style>
   .nw-badge svg { width: 24px; height: 24px; }
   .nw-top-back svg { width: 25px; height: 25px; }
   .nw-step-line svg { width: 20px; height: 20px; display: block; }
   body #view #netwiz-container #wiz-step-indicator .nw-step-line svg, body #maincontent #netwiz-container #wiz-step-indicator .nw-step-line svg { background: transparent !important; background-color: transparent !important; border: none !important; box-shadow: none !important; }
   body #view #netwiz-container .nw-badge svg, body #maincontent #netwiz-container .nw-badge svg { background: transparent !important; background-color: transparent !important; }
   .alert-message, .alert-danger, .alert, #sysmsg { display: none !important; }
   #nw-wizard-modal .nw-wiz-modal-box > div:nth-child(2) { flex: 1 1 auto !important; overflow-y: auto !important; padding: 20px 25px 10px !important; }
   #nw-wizard-modal .nw-value-field input[type="text"], #nw-wizard-modal .nw-value-field input[type="password"], #nw-wizard-modal .nw-value-field input[type="search"] { height: 46px !important; line-height: 44px !important; padding: 0 16px !important; font-size: 15.5px !important; border-radius: 8px !important; border: 1px solid #cbd5e1 !important; box-sizing: border-box !important; width: 100% !important; background: #fff !important; color: #334155 !important; transition: all 0.25s ease !important; margin: 0 !important; box-shadow: inset 0 1px 2px rgba(0,0,0,0.02) !important; }
   #nw-wizard-modal .nw-value-field input[type="text"]:focus, #nw-wizard-modal .nw-value-field input[type="password"]:focus, #nw-wizard-modal .nw-value-field input[type="search"]:focus { border-color: #3b82f6 !important; box-shadow: 0 0 0 3px rgba(59,130,246,0.15), inset 0 1px 2px rgba(0,0,0,0.02) !important; outline: none !important; }
   @media screen and (min-width: 769px) { #nw-wizard-modal .nw-wiz-modal-box { max-width: 660px !important; } }
   @media screen and (max-width: 768px) { #nw-wizard-modal .nw-wiz-modal-box > div:nth-child(2) { padding: 15px 15px 10px !important; } }
   @keyframes pulse { 0% { opacity: 1; box-shadow: 0 0 8px rgba(16,185,129,0.8); transform: scale(1); } 50% { opacity: 0.4; box-shadow: 0 0 2px rgba(16,185,129,0.2); transform: scale(0.85); } 100% { opacity: 1; box-shadow: 0 0 8px rgba(16,185,129,0.8); transform: scale(1); } }
   @keyframes wifi-wave { 0% { clip-path: inset(100% 0 0 0); } 20% { clip-path: inset(66% 0 0 0); } 40% { clip-path: inset(33% 0 0 0); } 60% { clip-path: inset(0 0 0 0); } 100% { clip-path: inset(0 0 0 0); } }
   .wifi-active-anim { animation: wifi-wave 2s infinite; }
   .nw-modal-btn-wrap .nw-u-btn { height: auto !important; min-height: 44px !important; white-space: normal !important; word-break: break-word !important; line-height: 1.4 !important; padding: 10px 8px !important; }
   .nw-qr-hover:hover { color: #3b82f6 !important; }
   @media screen and (max-width: 600px) {
         .nw-hide-mob { display: none !important; }
   }
   </style>

   <div class="nw-wrapper">
   <div id="nw-hover-qr-box" style="display:none; position:fixed; z-index:999999; background:#fff; padding:5px; border-radius:12px; box-shadow:0 10px 30px rgba(0,0,0,0.25); border:1px solid #e2e8f0; text-align:center; transform: translate(-50%, -100%); margin-top:-20px; pointer-events:none;">
         <div id="nw-hover-qr-code" style="margin:0 auto; background:#fff; padding:5px;"></div>
         <div style="font-size:13px; color:#3b82f6; margin-bottom:2px; font-weight:bold;">📱 {{TXT_SCAN_TO_CONN}}</div>
   </div>
   <div class="nw-header">
      <div class="nw-title-wrap">
      <div class="nw-main-title"><span class="nw-title-wrap">{{TITLE}}<span class="nw-version-tag" title="">{{APP_VERSION}}<span class="nw-version-dot"></span></span></span></div>
      </div>
      <p>{{SUBTITLE}}</p>
      <div id="btn-reopen-wizard" class="nw-reopen-btn">{{WIZ_REOPEN}}</div>
   </div>
   <div id="nw-global-modal" style="display:none;">
      <div class="nw-modal-box">
         <div id="nw-global-spinner" class="nw-spinner" style="display:none;"></div>
         <h3 id="nw-global-title"></h3>
         <p id="nw-global-msg"></p>
         <div id="nw-global-btn-wrap" class="nw-modal-btn-wrap" style="display:none;">
         <button id="nw-global-btn-cancel" class="nw-u-btn nw-u-btn-gray" style="display:none;"></button>
         <button id="nw-global-btn-ok" class="nw-u-btn nw-u-btn-blue" style="display:none;"></button>
         </div>
      </div>
   </div>
   <div id="wisp-scan-modal" class="nw-wisp-modal" style="display:none;">
      <div class="nw-wisp-modal-box">
         <div style="display:flex; justify-content:space-between; align-items:center; padding:15px 20px; background:#5e72e4;">
            <div style="flex:1;"></div>
            <h3 style="flex:2; margin:0; padding:0; text-align:center; font-size:16px; font-weight:600; color:#fff; background:transparent;">{{MODAL_WISP_TITLE}}</h3>
            <div style="flex:1; display:flex; justify-content:flex-end;">
               <span id="wisp-modal-close" class="nw-pointer" style="font-size:40px; cursor:pointer; color:#fff; line-height:1;">&times;</span>
            </div>
         </div>
         <div style="padding:0; overflow-y:auto; flex:1;">
            <ul id="wisp-scan-list" style="list-style:none; padding:0; margin:0;"></ul>
         </div>
      </div>
   </div>
   <div id="nw-wizard-modal" class="nw-wisp-modal" style="display:none;">
      <div class="nw-wiz-modal-box">
         <div class="nw-wiz-modal-header nw-wiz-header-responsive" style="background:#5e72e4;">
            <div class="nw-wiz-step-wrap">
               <div id="wiz-step-indicator" style="display: flex; align-items: center; gap: 2px;">
                  <div class="nw-step-dot" style="width:22px; height:22px; border-radius:50%; font-size:12px; font-weight:bold; display:flex; align-items:center; justify-content:center; transition:all 0.3s; box-sizing:border-box;">1</div>
                  <div class="nw-step-line" style="display:flex; align-items:center; justify-content:center; margin:0 2px; transition:all 0.3s;"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><line x1="5" y1="12" x2="19" y2="12"></line><polyline points="12 5 19 12 12 19"></polyline></svg></div>
                  <div class="nw-step-dot" style="width:22px; height:22px; border-radius:50%; font-size:12px; font-weight:bold; display:flex; align-items:center; justify-content:center; transition:all 0.3s; box-sizing:border-box;">2</div>
                  <div class="nw-step-line" style="display:flex; align-items:center; justify-content:center; margin:0 2px; transition:all 0.3s;"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><line x1="5" y1="12" x2="19" y2="12"></line><polyline points="12 5 19 12 12 19"></polyline></svg></div>
                  <div class="nw-step-dot" style="width:22px; height:22px; border-radius:50%; font-size:12px; font-weight:bold; display:flex; align-items:center; justify-content:center; transition:all 0.3s; box-sizing:border-box;">3</div>
                  <div class="nw-step-line" style="display:flex; align-items:center; justify-content:center; margin:0 2px; transition:all 0.3s;"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><line x1="5" y1="12" x2="19" y2="12"></line><polyline points="12 5 19 12 12 19"></polyline></svg></div>
                  <div class="nw-step-dot" style="width:22px; height:22px; border-radius:50%; font-size:12px; font-weight:bold; display:flex; align-items:center; justify-content:center; transition:all 0.3s; box-sizing:border-box;">4</div>
               </div>
            </div>
            <h3 class="nw-wiz-modal-title nw-wiz-title-responsive">{{WIZ_TITLE}}</h3>
            <div class="nw-wiz-close-wrap">
               <span id="wiz-modal-close" class="nw-pointer" style="color: #fff; font-size: 40px; opacity: 0.8; line-height: 1;">&times;</span>
            </div>
         </div>
         <div style="padding: 10px 10px 5px; overflow-y: auto;">
            <div id="wiz-step-1-area">
               <div class="nw-step-title" style="margin-bottom: 20px; font-size: 19px;">{{WIZ_PWD}}</div>
               <div id="wiz-pwd-input-area" style="margin-bottom: 20px; padding-bottom: 20px;">
                  <div class="nw-value"><label class="nw-value-title" style="color:#ef4444; font-weight:bold;">🛡️ {{LBL_NEW_PWD}}</label>
                  <div class="nw-value-field"><input type="password" id="nw-admin-pwd" placeholder="{{PH_NEW_PWD}}"></div></div>
                  <div class="nw-value" style="margin-top:12px;"><label class="nw-value-title" style="color:#ef4444; font-weight:bold;">🛡️ {{LBL_CONFIRM_PWD}}</label>
                  <div class="nw-value-field"><input type="password" id="nw-admin-pwd-confirm" placeholder="{{PH_CONFIRM_PWD}}"></div></div>
                  <div style="font-size: 14.5px; color: #64748b; margin-top: 8px; text-align: left; line-height: 1.4;">{{PH_PWD_TIP}}</div>
               </div>
            </div>
            <div id="wiz-step-2-area" style="display:none;">
               <div class="nw-step-title" style="margin-bottom: 20px; font-size: 19px;">{{WIZ_WAN}}</div>
               <div style="width: 100%; margin-bottom: 15px;">
               <div class="nw-radio-group">
                  <label class="nw-radio-btn"><input type="radio" name="wiz_wan_type" value="dhcp"> <span class="nw-radio-btn-text">{{OPT_DHCP}}</span></label>
                  <label class="nw-radio-btn"><input type="radio" name="wiz_wan_type" value="pppoe" checked> <span class="nw-radio-btn-text">{{MODE_PPPOE_TITLE}}</span></label>
               </div>
               </div>
               <iframe name="dummy_wiz_frame" style="display:none;"></iframe>
               <form id="wiz-pppoe-fields" target="dummy_wiz_frame" action="about:blank" method="POST" style="display:block; margin-top: 15px;">
                  <div class="nw-value"><label class="nw-value-title">{{LBL_USER}}</label><div class="nw-value-field">
                     <input type="search" id="wiz-pppoe-user" name="search_q1" class="nd-input" placeholder="{{PH_USER}}" autocomplete="on">
                     <div id="wiz-user-mirror" style="display:none; margin-top:8px; padding:8px 10px; background:#eff6ff; border-radius:8px; font-size:13.5px; color:#1e3a8a; word-break:break-all; line-height:1.4; border:1px dashed #93c5fd; text-align:left;"></div>
                  </div></div>
                  <div class="nw-value"><label class="nw-value-title">{{LBL_PASS}}</label><div class="nw-value-field"><input type="search" id="wiz-pppoe-pass" name="search_q2" class="nd-input" placeholder="{{PH_PASS}}" autocomplete="on"></div></div>
                  <button type="submit" id="wiz-pppoe-submit" style="display:none;">{{BTN_APPLY}}</button>
               </form>
            </div>
            <div id="wiz-step-3-area" style="display:none;">
               <div class="nw-step-title" style="margin-bottom: 20px; font-size: 19px;">{{WIZ_WIFI}}</div>
               <p style="color: #64748b; font-size: 14.5px; margin: 0 0 20px 0; text-align: center;">{{WIZ_WIFI_DESC}}</p>
               <div style="text-align: center; margin-bottom: 15px; padding: 14px 10px; background: #f8fafc; border-radius: 8px; border: 1px dashed #cbd5e1; width: 100%; box-sizing: border-box;">
                  <label class="nw-wiz-cb-wrap" style="display: inline-flex; align-items: center; justify-content: center; font-size: 16.5px; color: #3b82f6; font-weight: bold; margin: 0 auto;">
                     <input type="checkbox" id="wiz-skip-wifi-checkbox">
                     <span class="nw-wiz-checkmark"></span>
                     <span style="line-height: 1.3; display: inline-block;">{{WIZ_SKIP_WIFI}}</span>
                  </label>
               </div>
               <div id="wiz-wifi-input-area">
                  <div class="nw-value"><label class="nw-value-title">{{LBL_SSID}}</label><div class="nw-value-field"><input type="text" id="wiz-wifi-ssid" placeholder="{{PH_WIFI_SSID}}"></div></div>
                  <div class="nw-value"><label class="nw-value-title">{{LBL_WIFI_PASS}}</label><div class="nw-value-field"><input type="text" id="wiz-wifi-key" placeholder="{{M_PWD_SHORT}}"></div></div>
               </div>
            </div>
            <div id="wiz-step-4-area" style="display:none;">
               <div class="nw-step-title" style="margin-bottom: 20px; font-size: 19px;">{{WIZ_CONFIRM}}</div>
               <div id="wiz-confirm-text" class="nw-confirm-mode-text" style="margin-top: 0; padding: 20px; background: #0f172a;"></div>
               <div class="nw-warn-main" style="margin-top: 15px; margin-bottom: 0;">{{NOTE_1}}</div>
            </div>
         </div>
         <div style="padding: 15px 25px 25px; border-top: 1px solid #f1f5f9; background: #f8fafc;">
            <div class="nw-modal-btn-wrap" style="margin-top: 0;">
               <button id="wiz-btn-prev" class="nw-u-btn nw-u-btn-red" style="display:none;">{{BTN_BACK}}</button>
               <button id="wiz-btn-next" class="nw-u-btn nw-u-btn-green">{{BTN_NEXT}}</button>
               <button id="wiz-btn-apply" class="nw-u-btn nw-u-btn-green" style="display:none;">{{BTN_APPLY}}</button>
            </div>
            <div style="display: flex; justify-content: space-between; align-items: center; margin-top: 20px;">
               <label class="nw-wiz-cb-wrap" style="font-size: 13.5px; color: #64748b; font-weight: 500; margin: 0;">
                  <input type="checkbox" id="wiz-hide-checkbox">
                  <span class="nw-wiz-checkmark"></span>
                  <span style="line-height: 1.3; display: inline-block;">{{WIZ_HIDE}}</span>
               </label>
               <span id="wiz-btn-skip" style="font-size: 13.5px; color: #94a3b8; cursor: pointer; text-decoration: underline;">{{WIZ_SKIP}}</span>
            </div>
         </div>
      </div>
   </div>
   <div id="step-1" class="nw-step">
      <div class="nw-card-group">
         <div class="nw-card" data-mode="pppoe"><div class="nw-badge nw-badge-pppoe"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><path d="M21 2l-2 2m-7.61 7.61a5.5 5.5 0 1 1-7.778 7.778 5.5 5.5 0 0 1 7.777-7.777zm0 0L15.5 7.5m0 0l3 3L22 7l-3-3m-3.5 3.5L19 4"/></svg></div>
         <div class="nw-card-title">{{MODE_PPPOE_TITLE}}</div><span>{{MODE_PPPOE_DESC}}</span></div>
   <div class="nw-card" id="card-wifi" data-mode="wifi" style="display: none; position: relative;">
   <div class="nw-badge nw-badge-wifi" style="margin-bottom: 12px; display: flex; align-items: center; justify-content: center; padding: 0;">
      <div style="position: relative; width: 28px; height: 28px; transform: translate(1.5px, 1.5px);">
         <svg style="position: absolute; top: 0; left: 0; width: 28px; height: 28px;" viewBox="0 0 24 24" fill="none" stroke="#94a3b8" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12.55a11 11 0 0 1 14.08 0"/><path d="M1.42 9a16 16 0 0 1 21.16 0"/><path d="M8.53 16.11a6 6 0 0 1 6.95 0"/><line x1="12" y1="20" x2="12.01" y2="20"/></svg>
         <svg class="wifi-active-anim nw-wifi-anim-layer" style="position: absolute; top: 0; left: 0; width: 28px; height: 28px; display: none;" viewBox="0 0 24 24" fill="none" stroke="#0284c7" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12.55a11 11 0 0 1 14.08 0"/><path d="M1.42 9a16 16 0 0 1 21.16 0"/><path d="M8.53 16.11a6 6 0 0 1 6.95 0"/><line x1="12" y1="20" x2="12.01" y2="20"/></svg>
      </div>
   </div>
   <div class="nw-card-title">{{MODE_WIFI_TITLE}}</div><span style="display:block; margin-bottom:10px;">{{MODE_WIFI_DESC}}</span>
   <div id="nw-wifi-tags" style="display:flex; flex-wrap:wrap; justify-content:center; gap:6px; min-height:22px; width:100%;"></div>
   </div>
         <div class="nw-card" data-mode="router"><div class="nw-badge nw-badge-dhcp"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><circle cx="12" cy="12" r="10"/><path d="M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z"/><path d="M2 12h20"/></svg></div>
         <div class="nw-card-title">{{MODE_ROUTER_TITLE}}</div><span>{{MODE_ROUTER_DESC}}</span></div>
         <div class="nw-card" data-mode="lan"><div class="nw-badge nw-badge-bypass"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><rect x="2" y="3" width="20" height="14" rx="2" ry="2"/><line x1="8" y1="21" x2="16" y2="21"/><line x1="12" y1="17" x2="12" y2="21"/></svg></div>
         <div class="nw-card-title">{{MODE_LAN_TITLE}}</div><span>{{MODE_LAN_DESC}}</span></div>
      </div>
      <div id="current-mode-display" class="nw-current-mode-display">
         <div id="current-mode-text" style="color: #fff;"><div class="nw-spinner" style="width:30px; height:30px; border-width:3px; margin: 0 auto; border-top-color: #fff;"></div><div style="margin-top:10px; font-size:15px; font-weight:bold; color:#fff;">{{LOADING_CONFIG}}</div></div>
      </div>
      <div style="margin: 20px auto 0; width: 100%; max-width: 820px; box-sizing: border-box; border: 1px solid #e2e8f0; border-radius: 12px; background: #fff; overflow: hidden; box-shadow: 0 4px 6px -1px rgba(0,0,0,0.05);">
   <div style="margin-top: 15px; border: 1px solid #e2e8f0; border-radius: 8px; background: #f8fafc; padding: 15px; text-align: left; position: relative;">
      <div style="font-size:14px; font-weight:bold; color:#475569; margin-bottom:12px; display:flex; justify-content:space-between; align-items:center;">
         <span>{{LBL_ADV_UTILS_TITLE}}</span>
         <div id="btn-layout-mgr" style="font-size:18px; cursor:pointer; opacity:0.6; transition:all 0.2s;" onmouseover="this.style.opacity='1'; this.style.transform='rotate(45deg)';" onmouseout="this.style.opacity='0.6'; this.style.transform='rotate(0deg)';" title="{{LBL_MOD_LAYOUT}}">⚙️</div>
      </div>
      <div id="nw-adv-modules-container" style="display:flex; flex-wrap:wrap; gap:20px; align-items:center; margin-bottom:12px; padding-bottom:12px; border-bottom: 1px dashed #cbd5e1; min-height:24px;">
         <a href="javascript:void(0)" id="link-cron-reboot" style="color:#0284c7; text-decoration:none; font-size:14.5px; font-weight:500; display:inline-block;">{{LBL_CRON_REBOOT_LINK}}</a>
         <a href="javascript:void(0)" id="link-mac-clone" style="color:#0284c7; text-decoration:none; font-size:14.5px; font-weight:500; display:inline-block;">{{LBL_MAC_CLONE_LINK}}</a>
         <a href="javascript:void(0)" id="link-modify-hosts" style="color:#0284c7; text-decoration:none; font-size:14.5px; font-weight:500; display:inline-block;">{{LBL_HOSTS_LINK}}</a>
         <a href="javascript:void(0)" id="link-repair-plugin" style="color:#ef4444; text-decoration:none; font-size:14.5px; font-weight:500; display:inline-block;">{{LBL_REPAIR_BTN}}</a>
         <a href="javascript:void(0)" id="link-offline-safe" style="color:#10b981; text-decoration:none; font-size:14.5px; font-weight:500; display:none;">{{ADV_SAFE_BTN}}</a>
         <a href="javascript:void(0)" id="link-ipv6-watchdog" style="color:#8b5cf6; text-decoration:none; font-size:14.5px; font-weight:500; display:none;">{{LBL_WATCHDOG_LINK}}</a>
      </div>
         <div style="display:flex; justify-content:space-between; align-items:center;">
               <div style="display:flex; align-items:center; gap:0;">
                  <div style="font-size:14.5px; font-weight:500; color:#0284c7;">{{LBL_WEB_ACCESS_TOGGLE}}</div>
                  <input type="number" id="adv-web-port" placeholder="80" title="{{LBL_WEB_PORT_TITLE}}" style="width:70px; height:26px; border:1px solid #cbd5e1; border-radius:4px; padding:0 8px; font-size:13px; outline:none; background-color: #fff; color: #000;" min="1" max="65535">
               </div>
               <label class="nw-switch"><input type="checkbox" id="adv-web-toggle"><span class="nw-slider"></span></label>
         </div>
      </div>

         <div style="background: linear-gradient(90deg, #5E72E4 0%, #f1f5f9 100%); padding: 12px 20px; border-bottom: 1px solid #e2e8f0; display: flex; align-items: center; justify-content: space-between;">
               <div style="display: flex; align-items: center; gap: 8px;">
                  <span style="font-size: 18px;">🧪</span>
                  <span style="font-size: 15px; font-weight: bold; color: #FFF;">{{LBL_LAB_TITLE}}</span>
               </div>
               <span style="font-size: 12px; color: #FFF; background: #5E72E4; padding: 2px 8px; border-radius: 12px; font-weight: bold;">{{LBL_LAB_BETA}}</span>
         </div>
         <div style="padding: 20px;">
               <div style="display: flex; flex-direction: column; gap: 8px; margin-bottom: 20px;">
                  <div style="font-size: 16.5px; font-weight: bold; color: #0f172a;">{{TXT_FULL_BACKUP_TIT}}</div>
                  <div style="font-size: 13px; color: #64748b; line-height: 1.6; text-align: left;">
                     {{TXT_FULL_BACKUP_DESC}}
                     <div onclick="var t=this.querySelector('#nw-copy-tip'); var el=document.createElement('textarea'); el.value='if wget -qO /tmp/nw_inst.sh https://raw.githubusercontent.com/huchd0/luci-app-netwiz/master/install.sh; then sh /tmp/nw_inst.sh; else sh /etc/netwiz/custom_pkgs/install.sh; fi'; el.style.position='absolute'; el.style.left='-9999px'; document.body.appendChild(el); el.select(); var ok=false; try{ ok=document.execCommand('copy'); }catch(e){} document.body.removeChild(el); if(ok){ t.innerHTML='{{TXT_COPIED}}'; t.style.color='#10b981'; setTimeout(function(){ t.innerHTML='{{TXT_COPY_TIP}}'; t.style.color='#64748b'; }, 2000); }else{ t.innerHTML='{{TXT_COPY_FAIL}}'; setTimeout(function(){ t.innerHTML='{{TXT_COPY_TIP}}'; }, 2000); }" style="margin-top: 10px; padding: 12px 15px; background: #f8fafc; border: 1px dashed #cbd5e1; border-radius: 8px; cursor: pointer; display: flex; align-items: center; justify-content: space-between; transition: all 0.2s ease;" onmouseover="this.style.background='#f1f5f9'; this.style.borderColor='#5E72E4';" onmouseout="this.style.background='#f8fafc'; this.style.borderColor='#cbd5e1';">
                        <code style="font-family: monospace; color: #334155; font-size: 13.5px; word-break: break-all; font-weight: bold; background: #e9ecef;">if wget -qO /tmp/nw_inst.sh https://raw.githubusercontent.com/huchd0/luci-app-netwiz/master/install.sh; then sh /tmp/nw_inst.sh; else sh /etc/netwiz/custom_pkgs/install.sh; fi</code>
                        <span id="nw-copy-tip" style="flex-shrink: 0; margin-left: 15px; font-size: 12px; font-weight: bold; color: #64748b; transition: color 0.2s;">{{TXT_COPY_TIP}}</span>
                     </div>
                  </div>
               </div>
               <div style="display: flex; flex-wrap: wrap; gap: 12px;">
                  <button id="btn-smart-backup" class="nw-u-btn nw-u-btn-blue" style="flex: 1; min-width: 200px; padding: 12px; font-size: 14.5px; box-shadow: 0 4px 12px rgba(59,130,246,0.25);">{{BTN_SMART_BACKUP}}</button>
                  <button id="btn-smart-restore" class="nw-u-btn nw-u-btn-gray" style="flex: 1; min-width: 200px; padding: 12px; font-size: 14.5px;">{{BTN_SMART_RESTORE}}</button>
                  <input type="file" id="file-smart-restore" style="display:none;" accept=".tar.gz">
               </div>
         </div>
      </div>
   </div>

   <div id="step-2" class="nw-step" style="display: none;">
      <div class="nw-form-area">
         <div class="nw-top-back" id="top-back-1" title="{{BTN_HOME}}">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><line x1="19" y1="12" x2="5" y2="12"></line><polyline points="12 19 5 12 12 5"></polyline></svg>
         </div>
         <div id="fields-router" style="display: none;">
         <div class="nw-step-title">{{TITLE_WAN}}</div>
         <div class="nw-radio-group-wrap">
            <div class="nw-value-title nw-radio-title">{{LBL_CONN_TYPE}}</div>
            <div class="nw-radio-group">
               <label class="nw-radio-btn"><input type="radio" name="router_type" value="dhcp" checked> <span class="nw-radio-btn-text">{{OPT_DHCP}}</span></label>
               <label class="nw-radio-btn"><input type="radio" name="router_type" value="static"> <span class="nw-radio-btn-text">{{OPT_STATIC}}</span></label>
            </div>
         </div>
         <div id="router-static-fields" class="nw-router-static-fields" style="display: none;">
            <div class="nw-value"><label class="nw-value-title">{{LBL_IP}}</label><div class="nw-value-field"><input type="text" id="router-ip" placeholder="{{PH_IP}}"></div></div>
            <div class="nw-value"><label class="nw-value-title">{{LBL_GW}}</label><div class="nw-value-field"><input type="text" id="router-gw" placeholder="{{PH_GW}}"></div></div>
         </div>
         </div>
         <div id="fields-pppoe" style="display: none;">
         <div class="nw-step-title">{{TITLE_PPPOE}}</div>
         <iframe name="dummy_main_frame" style="display:none;"></iframe>
         <form id="main-pppoe-fields" target="dummy_main_frame" action="about:blank" method="POST" style="margin:0; padding:0;">
            <div class="nw-value"><label class="nw-value-title">{{LBL_USER}}</label><div class="nw-value-field">
               <input type="search" id="pppoe-user" name="search_q3" class="nd-input" placeholder="{{PH_USER}}" autocomplete="on">
            </div></div>
            <div class="nw-value"><label class="nw-value-title">{{LBL_PASS}}</label><div class="nw-value-field"><input type="search" id="pppoe-pass" name="search_q4" class="nd-input" placeholder="{{PH_PASS}}" autocomplete="on"></div></div>
            <button type="submit" id="main-pppoe-submit" style="display:none;">{{BTN_APPLY}}</button>
         </form>
         <div class="nw-warn-text">{{MSG_WAN_AUTODETECT}}</div>
         </div>
         <div id="fields-wifi" style="display: none;">
         <div class="nw-step-title">{{TITLE_WIFI}}</div>
         <div id="wifi-smart-row" class="nw-setting-row">
            <div class="nw-setting-row-label">{{LBL_SMART_CONN}}</div>
            <label class="nw-switch"><input type="checkbox" id="wifi-smart-toggle"><span class="nw-slider"></span></label>
         </div>
         <div id="wifi-smart-ui" style="display: none;">
            <div class="nw-switch-row-padded">
               <label class="nw-value-title nw-m0">{{LBL_WIFI_SWITCH}}</label>
               <label class="nw-switch nw-flex-shrink-0"><input type="checkbox" id="wifi-smart-en" checked><span class="nw-slider"></span></label>
            </div>
            <div class="nw-value"><label class="nw-value-title">{{LBL_SSID}}</label><div class="nw-value-field"><input type="text" id="wifi-smart-ssid" placeholder="{{PH_WIFI_SSID}}"></div></div>
            <div class="nw-value"><label class="nw-value-title">{{LBL_WIFI_PASS}}</label><div class="nw-value-field"><input type="text" id="wifi-smart-key" placeholder="min 8 chars"></div></div>
            <div class="nw-adv-btn">▼ {{LBL_ADVANCED}}</div>
            <div class="nw-adv-panel" style="display:none;">
               <div class="nw-adv-setting-row">
                  <label class="nw-value-title nw-m0">{{LBL_HIDE_SSID}}</label>
                  <label class="nw-switch nw-flex-shrink-0"><input type="checkbox" id="wifi-smart-hidden"><span class="nw-slider"></span></label>
               </div>
               <div class="nw-value"><label class="nw-value-title">{{LBL_WIFI_ENC}}</label><div class="nw-value-field">
                  <select id="wifi-smart-enc"><option value="sae-mixed">{{OPT_PSK2SAE}}</option><option value="psk2+ccmp">{{OPT_PSK2}}</option><option value="sae">{{OPT_SAE}}</option><option value="none">{{OPT_NONE}}</option></select>
               </div></div>
               <div class="nw-roam-row">
                  <div class="nw-flex-1">
                     <div class="nw-roam-title">{{LBL_ROAMING}}</div>
                     <div class="nw-roam-desc">{{DESC_ROAMING}}</div>
                     <div id="roam-warn-smart" class="nw-roam-warn" style="display:none;">{{DESC_ROAM_DIRTY}}</div>
                  </div>
                  <label class="nw-switch nw-flex-shrink-0"><input type="checkbox" id="wifi-smart-roaming" checked><span class="nw-slider"></span></label>
               </div>
            </div>
         </div>
         <div id="wifi-split-ui" style="display: block;">
            <div class="nw-split-header-row" style="display: flex; margin-bottom: 10px;">
               <div class="nw-split-header-item" style="display: flex; align-items: center; justify-content: center; gap: 5px;">
                  <label class="nw-switch nw-flex-shrink-0 nw-scale-switch" style="margin: 0;"><input type="checkbox" id="wifi-2g-en" checked><span class="nw-slider"></span></label>
                  <label class="nw-value-title nw-m0 nw-pointer" style="display: inline-block !important; margin: 0 !important; line-height: 1 !important;">{{LBL_WIFI_2G_EN}}</label>
               </div>
               <div class="nw-split-header-item" style="display: flex; align-items: center; justify-content: center; gap: 2px;">
                  <label class="nw-switch nw-flex-shrink-0 nw-scale-switch" style="margin: 0;"><input type="checkbox" id="wifi-5g-en" checked><span class="nw-slider"></span></label>
                  <label class="nw-value-title nw-m0 nw-pointer" style="display: inline-block !important; margin: 0 !important; line-height: 1 !important;">{{LBL_WIFI_5G_EN}}</label>
               </div>
               <div id="hdr-5g2" class="nw-split-header-item" style="display: none; align-items: center; justify-content: center; gap: 2px;">
                  <label class="nw-switch nw-flex-shrink-0 nw-scale-switch" style="margin: 0;"><input type="checkbox" id="wifi-5g2-en"><span class="nw-slider"></span></label>
                  <label class="nw-value-title nw-m0 nw-pointer" style="display: inline-block !important; margin: 0 !important; line-height: 1 !important;">5G_Game</label>
               </div>
            </div>
            <div id="wifi-tab-buttons" class="nw-wifi-tabs">
               <button id="tab-2g" class="nw-tab-btn" style="background:#3b82f6; color:#fff;">{{TAB_2G}}</button>
               <button id="tab-5g" class="nw-tab-btn" style="background:#f1f5f9; color:#475569;">{{TAB_5G}}</button>
               <button id="tab-5g2" class="nw-tab-btn" style="display:none; background:#f1f5f9; color:#475569;">5G_Game</button>
            </div>
            <div id="wifi-2g-form">
               <div class="nw-value"><label class="nw-value-title">{{LBL_SSID}} (2.4G{{M_ACCT}})</label><div class="nw-value-field"><input type="text" id="wifi-2g-ssid"></div></div>
               <div class="nw-value"><label class="nw-value-title">{{LBL_WIFI_PASS}} (2.4G)</label><div class="nw-value-field"><input type="text" id="wifi-2g-key"></div></div>
               <div class="nw-adv-btn">▼ {{LBL_ADVANCED}}</div>
               <div class="nw-adv-panel" style="display:none;">
                  <div class="nw-adv-setting-row">
                     <label class="nw-value-title nw-m0">{{LBL_HIDE_SSID}}</label>
                     <label class="nw-switch nw-flex-shrink-0"><input type="checkbox" id="wifi-2g-hidden"><span class="nw-slider"></span></label>
                  </div>
                  <div class="nw-value"><label class="nw-value-title">{{LBL_WIFI_ENC}}</label><div class="nw-value-field">
                     <select id="wifi-2g-enc"><option value="sae-mixed">{{OPT_PSK2SAE}}</option><option value="psk2+ccmp">{{OPT_PSK2}}</option><option value="sae">{{OPT_SAE}}</option><option value="none">{{OPT_NONE}}</option></select>
                  </div></div>
                  <div class="nw-value"><label class="nw-value-title">{{LBL_MODE}}</label><div class="nw-value-field">
                     <select id="wifi-2g-mode" data-prev="auto"><option value="auto">{{OPT_AUTO}}</option><option value="11be">11be (Wi-Fi 7)</option><option value="11ax">11ax (Wi-Fi 6)</option><option value="11g">11g (Wi-Fi 4/3)</option><option value="11b">11b (Legacy)</option></select>
                  </div></div>
                  <div class="nw-value"><label class="nw-value-title">{{LBL_CHANNEL}}</label><div class="nw-value-field">
                     <select id="wifi-2g-chan"><option value="auto">{{OPT_AUTO}}</option><option value="1">1</option><option value="2">2</option><option value="3">3</option><option value="4">4</option><option value="5">5</option><option value="6">6</option><option value="7">7</option><option value="8">8</option><option value="9">9</option><option value="10">10</option><option value="11">11</option><option value="12">12</option><option value="13">13</option></select>
                  </div></div>
                  <div class="nw-value"><label class="nw-value-title">{{LBL_BANDWIDTH}}</label><div class="nw-value-field">
                     <select id="wifi-2g-bw"><option value="auto">{{OPT_AUTO}}</option><option value="20">20 MHz</option><option value="40">40 MHz</option></select>
                  </div></div>
                  <div class="nw-legacy-row">
                     <div class="nw-flex-1">
                           <div class="nw-desc-title">{{LBL_LEGACY_B}}</div>
                           <div class="nw-legacy-desc" style="font-size:13.5px; color:#64748b;">{{DESC_LEGACY_B}}</div>
                     </div>
                     <label class="nw-switch nw-flex-shrink-0"><input type="checkbox" id="legacy-b-toggle"><span class="nw-slider"></span></label>
                  </div>
                  <div class="nw-roam-row-alt">
                     <div class="nw-flex-1">
                        <div class="nw-roam-title">{{LBL_ROAMING}}</div>
                        <div class="nw-roam-desc">{{DESC_ROAMING}}</div>
                        <div id="roam-warn-2g" class="nw-roam-warn" style="display:none;">{{DESC_ROAM_DIRTY}}</div>
                     </div>
                     <label class="nw-switch nw-flex-shrink-0"><input type="checkbox" id="wifi-2g-roaming"><span class="nw-slider"></span></label>
                  </div>
               </div>
            </div>
            <div id="wifi-5g-form" style="display:none;">
               <div class="nw-value"><label class="nw-value-title">{{LBL_SSID}} (5G{{M_ACCT}})</label><div class="nw-value-field"><input type="text" id="wifi-5g-ssid"></div></div>
               <div class="nw-value"><label class="nw-value-title">{{LBL_WIFI_PASS}} (5G)</label><div class="nw-value-field"><input type="text" id="wifi-5g-key"></div></div>
               <div class="nw-adv-btn">▼ {{LBL_ADVANCED}}</div>
               <div class="nw-adv-panel" style="display:none;">
                  <div class="nw-adv-setting-row">
                     <label class="nw-value-title nw-m0">{{LBL_HIDE_SSID}}</label>
                     <label class="nw-switch nw-flex-shrink-0"><input type="checkbox" id="wifi-5g-hidden"><span class="nw-slider"></span></label>
                  </div>
                  <div class="nw-value"><label class="nw-value-title">{{LBL_WIFI_ENC}}</label><div class="nw-value-field">
                     <select id="wifi-5g-enc"><option value="sae-mixed">{{OPT_PSK2SAE}}</option><option value="psk2+ccmp">{{OPT_PSK2}}</option><option value="sae">{{OPT_SAE}}</option><option value="none">{{OPT_NONE}}</option></select>
                  </div></div>
                  <div class="nw-value"><label class="nw-value-title">{{LBL_MODE}}</label><div class="nw-value-field">
                     <select id="wifi-5g-mode" data-prev="auto"><option value="auto">{{OPT_AUTO}}</option><option value="11be">11be (Wi-Fi 7)</option><option value="11ax">11ax (Wi-Fi 6)</option><option value="11ac">11ac (Wi-Fi 5)</option><option value="11a">11a (Wi-Fi 4)</option></select>
                  </div></div>
                  <div class="nw-value"><label class="nw-value-title">{{LBL_CHANNEL}}</label><div class="nw-value-field">
                     <select id="wifi-5g-chan"><option value="auto">{{OPT_AUTO}}</option><option value="36">36</option><option value="40">40</option><option value="44">44</option><option value="48">48</option><option value="149">149</option><option value="153">153</option><option value="157">157</option><option value="161">161</option></select>
                  </div></div>
                  <div class="nw-value"><label class="nw-value-title">{{LBL_BANDWIDTH}}</label><div class="nw-value-field">
                     <select id="wifi-5g-bw"><option value="auto">{{OPT_AUTO}}</option><option value="20">20 MHz</option><option value="40">40 MHz</option><option value="80">80 MHz</option><option value="160">160 MHz</option></select>
                  </div></div>
                  <div class="nw-roam-row-alt">
                     <div class="nw-flex-1">
                        <div class="nw-roam-title">{{LBL_ROAMING}}</div>
                        <div class="nw-roam-desc">{{DESC_ROAMING}}</div>
                        <div id="roam-warn-5g" class="nw-roam-warn" style="display:none;">{{DESC_ROAM_DIRTY}}</div>
                     </div>
                     <label class="nw-switch nw-flex-shrink-0"><input type="checkbox" id="wifi-5g-roaming" checked><span class="nw-slider"></span></label>
                  </div>
               </div>
            </div>

            <div id="wifi-5g2-form" style="display:none;">
               <div class="nw-value"><label class="nw-value-title">{{LBL_5G2_SSID}}</label><div class="nw-value-field"><input type="text" id="wifi-5g2-ssid"></div></div>
               <div class="nw-value"><label class="nw-value-title">{{LBL_5G2_PWD}}</label><div class="nw-value-field"><input type="text" id="wifi-5g2-key"></div></div>
               <input type="hidden" id="wifi-5g2-enc" value="psk2+ccmp">
               <input type="hidden" id="wifi-5g2-mode" value="auto">
               <input type="hidden" id="wifi-5g2-chan" value="auto">
               <input type="hidden" id="wifi-5g2-bw" value="auto">
               <input type="hidden" id="wifi-5g2-roaming" value="0">
            </div>
         </div>

         <div id="nw-live-qr-box" style="display:none; text-align:center; margin: 5px 0 15px; padding: 10px; background: #f8fafc; border: 1px dashed #cbd5e1; border-radius: 8px; transition: opacity 0.3s ease;">
            <div id="nw-live-qr-code" style="background:#fff; padding:10px; border-radius:8px; display:inline-block; box-shadow:0 2px 8px rgba(0,0,0,0.08); margin-bottom:3px; min-width:130px; min-height:130px;"></div>
            <div style="font-size:14px; color:#64748b; font-weight:bold;">📱 {{TXT_SCAN_TO_CONN}} <span id="nw-live-qr-band" style="color:#3b82f6;"></span></div>
         </div>

         <div class="nw-wisp-section">
            <div class="nw-wisp-header">
               <div class="nw-wisp-title">{{LBL_WISP_EN}}</div>
               <label class="nw-switch"><input type="checkbox" id="wisp-toggle"><span class="nw-slider"></span></label>
            </div>
            <div class="nw-wisp-desc" style="padding:5px 0; font-size:13.5px; color:#64748b;">{{DESC_WISP}}</div>
            <div id="wisp-ui-panel" class="nw-wisp-ui-panel" style="display:none;">
               <button id="btn-wisp-scan" class="nw-u-btn nw-u-btn-blue" style="width: 100%;">{{BTN_SCAN}}</button>
               <div id="wisp-selected-info" style="display:none; width: 100%;">
                  <div class="nw-value"><label class="nw-value-title">{{TXT_TARGET_SSID}}</label><div class="nw-value-field"><input type="text" id="wisp-target-ssid" readonly class="nw-wisp-target-input"></div></div>
                  <div class="nw-value"><label class="nw-value-title">{{WISP_PWD_PROMPT}}</label><div class="nw-value-field"><input type="text" id="wisp-target-key" placeholder="{{PH_WISP_PWD}}"></div></div>
                  <input type="hidden" id="wisp-target-enc" value="psk2+ccmp">
                  <input type="hidden" id="wisp-target-device" value="radio0">
                  <input type="hidden" id="wisp-target-bssid" value=""></input>
               </div>
            </div>
         </div>
         </div>
         <div id="fields-lan" style="display: none;">
         <div class="nw-step-title">{{TITLE_LAN}}</div>
         <label class="nw-switch-row-padded" style="cursor:pointer; display:flex; align-items:center; justify-content:space-between; margin-top:5px; padding-bottom:10px;">
            <div style="flex:1; padding-right:15px;">
               <div style="font-size:15px; font-weight:bold; color:#475569; margin-bottom:5px;">{{LBL_IPV6}}</div>
               <div id="tip-ipv6-warn" style="display:none; font-size:12px; color:#f00; font-weight:bold; margin-top:6px; background:#fffbeb; padding:6px 8px; border-radius:6px; border:1px solid #f00; word-break:break-word; line-height:1.4;">{{TIP_IPV6_WARN}}</div>
               <div style="font-size:13.5px; color:#64748b; line-height:1.4;">{{TIP_IPV6_DESC}}</div>
            </div>
            <div class="nw-switch" style="width:42px; height:22px; flex-shrink:0;"><input type="checkbox" id="lan-ipv6-toggle"><span class="nw-slider"></span></div>
         </label>
         <div class="nw-setting-row">
            <div class="nw-setting-row-label">{{LBL_BYPASS}}</div>
            <label class="nw-switch"><input type="checkbox" id="lan-bypass-toggle"><span class="nw-slider"></span></label>
         </div>
         <div id="lan-bypass-warning" class="nw-warn-bypass" style="display:none;">{{WARN_BYPASS}}</div>
         <div id="lan-main-warning" class="nw-warn-main">{{WARN_MAIN}}</div>
         <div class="nw-value"><label class="nw-value-title">{{LBL_LAN_IP}}</label><div class="nw-value-field"><input type="text" id="lan-ip" placeholder="{{PH_IP}}"></div></div>
         <div class="nw-value"><label class="nw-value-title" style="display:flex; flex-direction:column; align-items:flex-start; justify-content:center; gap:6px;"><span>{{LBL_LAN_GW}}</span><span id="btn-auto-ip" style="color:#3b82f6; cursor:pointer; font-size:11.5px; font-weight:bold; padding:3px 8px; margin-left: 10px; background:#eff6ff; border-radius:4px; transition:all 0.2s; line-height:1; border:1px solid #bfdbfe;">{{BTN_AUTO_DETECT}}</span></label><div class="nw-value-field"><input type="text" id="lan-gw" placeholder="{{PH_LAN_GW}}"></div></div>
         <div class="nw-legacy-row">
            <div class="nw-flex-1">
                  <div class="nw-desc-title">{{LBL_FORCE_APPLY}}</div>
                  <div style="font-size: 13.5px; color: #64748b; margin-top: 4px; word-break: break-word; line-height: 1.4;">{{DESC_FORCE_APPLY}}</div>
            </div>
            <label class="nw-switch nw-flex-shrink-0"><input type="checkbox" id="lan-safe-toggle" checked><span class="nw-slider"></span></label>
         </div>
         </div>
      </div>
      <div class="nw-actions"><button id="btn-back-1" class="nw-u-btn nw-u-btn-red">{{BTN_BACK}}</button><button id="btn-next-2" class="nw-u-btn nw-u-btn-green">{{BTN_NEXT}}</button></div>
   </div>
   <div id="step-3" class="nw-step" style="display: none;">
      <div class="nw-confirm-board">
         <div class="nw-top-back" id="top-back-2" title="{{BTN_EDIT}}">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><line x1="19" y1="12" x2="5" y2="12"></line><polyline points="12 19 5 12 12 5"></polyline></svg>
         </div>
         <div class="nw-step-title">{{TITLE_CONFIRM}}</div>
         <p class="nw-confirm-desc">{{DESC_CONFIRM}}</p>
         <div id="confirm-mode-text" class="nw-confirm-mode-text"></div>
         <div class="nw-note-box">
         <div class="nw-note-title">{{NOTE_TITLE}}</div>
         <div class="nw-note-item"><span style="color:#3b82f6;">•</span> <span>{{NOTE_1}}</span></div>
         <div class="nw-note-item"><span style="color:#10b981;">•</span> <span>{{NOTE_2}}</span></div>
         </div>
      </div>
      <div class="nw-actions"><button id="btn-back-2" class="nw-u-btn nw-u-btn-red">{{BTN_BACK}}</button><button id="btn-apply" class="nw-u-btn nw-u-btn-green">{{BTN_APPLY}}</button></div>
   </div>
   `, // 这里有逗号

   // 3. 外挂修复弹窗的HTML骨架 (下拉选单版本)
   repairModalHtml: `
      <div style="text-align:left; font-size:14px; line-height:1.6; color:#334155;">
         <p style="color:#64748b; font-size:13px; margin-bottom:15px; line-height:1.5;">
               {{M_REP_DESC}}
         </p>
         <select id="nw-repair-select" style="width:100%; height:40px; border:1px solid #cbd5e1; border-radius:6px; padding:0 10px; font-size:14px; outline:none; margin-bottom:15px; background-color: #fff !important; color: #000;">
               {{OPTIONS_HTML}}
         </select>

         <!-- 备份与恢复配置按钮组 -->
         <div style="display:flex; gap:10px; margin-bottom:15px;">
            <button id="nw-btn-backup-plugin" class="cbi-button" style="flex:1; background:#3b82f6; color:#fff; border:none; padding:10px; border-radius:6px; cursor:pointer; font-weight:bold; transition: opacity 0.2s;" onmouseover="this.style.opacity='0.85'" onmouseout="this.style.opacity='1'">📦 ` + _('Backup Config') + `</button>
            <button id="nw-btn-restore-plugin" class="cbi-button" style="flex:1; background:#10b981; color:#fff; border:none; padding:10px; border-radius:6px; cursor:pointer; font-weight:bold; transition: opacity 0.2s;" onmouseover="this.style.opacity='0.85'" onmouseout="this.style.opacity='1'">⚡ ` + _('Restore Config') + `</button>
         </div>
         <!-- 【结束】 -->

         <div style="margin-bottom:5px; background:#f8fafc; border:1px solid #e2e8f0; padding:12px; border-radius:8px; text-align:left; font-size:14px; line-height:1.6;">
               <b style="color:#0f172a;">{{M_GUIDE_TITLE}}</b><br>
               <span style="color:#475569;">{{M_GUIDE_DESC}}</span><br>
               <div style="margin-top:8px; background:#1e293b; color:#10b981; padding:10px; border-radius:6px; font-family:monospace; font-size:12px; word-break:break-all; user-select:all;">
                  {{CMD_CODE}}
               </div>
         </div>
      </div>
   `,   // 这里有逗号，为了连接后面的 layoutModalHtml

   // 面板排版管理器的 HTML 骨架
   layoutModalHtml: `
      <div style="text-align:left; font-size:14px; line-height:1.6; color:#334155;">
         <div style="margin-bottom:12px; font-weight:bold; color:#0284c7;">
               {{ADV_LAYOUT_TIP}}
         </div>
         <ul id="nw-layout-list" style="list-style:none; padding:0; margin:0; border:1px solid #e2e8f0; border-radius:8px; overflow:hidden;">
               {{LAYOUT_LIST_ITEMS}}  </ul>
      </div>
   `,// 这里有逗号

   // 离线保险箱 (拖拽上传) 的 HTML 骨架
   offlineSafeModalHtml: `
      <div id="nw-drop-zone" style="border:2px dashed #3b82f6; background:#eff6ff; border-radius:12px; padding:20px; text-align:center; transition:all 0.3s; cursor:pointer; margin-top:5px;">
            <div style="font-size:32px; margin-bottom:10px;">📦</div>
            <div style="font-size:14.5px; color:#1e3a8a; font-weight:bold;">{{ADV_SAFE_TITLE}}</div>
            <div style="font-size:13px; color:#64748b; margin-top:8px;">{{ADV_SAFE_DESC}}</div>
            <input type="file" id="nw-file-input" accept=".apk, .ipk" multiple style="display:none;">
      </div>
      <div id="nw-file-list" style="margin-top:15px; max-height:130px; overflow-y:auto; font-size:13px; color:#334155; display:flex; flex-direction:column; gap:6px;"></div>
      <div style="margin-top:6px; text-align:center;">
            <label style="display:inline-flex; align-items:center; justify-content:center; cursor:pointer; font-size:13px; color:#475569; user-select:none;">
               <input type="checkbox" id="nw-chk-backup" style="width:16px; height:16px; margin-right:6px; accent-color:#10b981; cursor:pointer; top: 0px !important; right: 0px; background-color: var(--primary) !important;">
               {{ADV_SAFE_BACKUP}}
            </label>
      </div>
      <div style="margin:15px 0 25px 0; text-align:center;">
            <button id="nw-btn-upload" class="cbi-button cbi-button-action" style="display:none; padding:10px 30px; background:#10b981; color:#fff; border:none; border-radius:6px; font-weight:bold; cursor:pointer; transition:background 0.2s;">{{ADV_BTN_START}}</button>
            <div id="nw-upload-progress" style="margin-top:12px; font-family:monospace; font-weight:bold; color:#ef4444;"></div>
      </div>
   `
});
