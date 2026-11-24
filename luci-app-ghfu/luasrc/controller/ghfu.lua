-- SPDX-License-Identifier: GPL-3.0-only
-- Copyright (C) 2026 smallprogram & Kiddin'
-- Adapted exclusively for https://dl.openwrt.ai/firmware with built-in firmware filtering, auto-selection & flash.js validation

module("luci.controller.ghfu", package.seeall)

local http = require "luci.http"
local jsonc = require "luci.jsonc"
local i18n = require "luci.i18n"
local uci = require("luci.model.uci").cursor()
local nixio = require "nixio"
local fs = require "nixio.fs"
local sys = require "luci.sys"
local util = require "luci.util"

local CFG = "ghfu"
local SEC = "main"
local tr = i18n.translate

local FIRMWARE_BASE_URL = "https://dl.openwrt.ai/firmware"
local DEFAULT_FETCH_TIMEOUT = 15
local DEFAULT_ROOTFS_PARTSIZE_MB = 1536
local CHECK_CACHE_FILE = "/tmp/ghfu-check-cache.json"
local CHECK_CACHE_TTL = 600
local VALIDATE_CACHE_FILE = "/tmp/ghfu-validate.json"
local PROGRESS_LOG_FILE = "/tmp/ghfu-download-progress.log"
local RAW_LOG_FILE = "/tmp/ghfu-download-raw.log"
local PID_FILE = "/tmp/ghfu-download.pid"

local BUILTIN_VALID_EXTS = {
    ".img.gz", ".img", ".bin", ".tar.gz", ".tar", ".itb", ".trx", ".chk", ".dlf", ".ari"
}

local GENERIC_BOARD_NAMES = {
    [""] = true, ["generic"] = true, ["efi"] = true, ["64"] = true,
    ["armv8"] = true, ["default"] = true, ["x86_64"] = true,
    ["x86-64"] = true, ["x86_generic"] = true, ["x86-generic"] = true
}

local LEGACY_CFG_KEYS = {
    "github_repo", "firmware_url", "device_path", "fetch_timeout",
    "filter_ext_enabled", "valid_extensions",
    "filter_prefix_enabled", "filter_prefix",
    "filter_min_size_enabled", "filter_min_size"
}

local MONTHS = {
    jan = 1, feb = 2, mar = 3, apr = 4, may = 5, jun = 6,
    jul = 7, aug = 8, sep = 9, oct = 10, nov = 11, dec = 12
}

local function json_resp(tbl)
    http.prepare_content("application/json")
    http.write_json(tbl)
end

local function to_bool(v)
    return v == "1" or v == "true" or v == "on" or v == "yes"
end

local function trim(s)
    return s and (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) or ""
end

local function read_lines(path)
    local f = io.open(path, "r")
    if not f then return {} end
    local lines = {}
    for line in f:lines() do
        lines[#lines + 1] = line
    end
    f:close()
    return lines
end

local function read_all(path)
    local f = io.open(path, "r")
    if not f then return "" end
    local content = f:read("*a") or ""
    f:close()
    return content
end

local function read_first_line(path)
    local f = io.open(path, "r")
    if not f then return "" end
    local line = f:read("*l") or ""
    f:close()
    return trim(line)
end

local function write_file(path, content)
    local f = io.open(path, "w")
    if not f then return false end
    f:write(content or "")
    f:close()
    return true
end

local function human_bytes(n)
    n = math.max(0, tonumber(n) or 0)
    local units = { "B", "KB", "MB", "GB", "TB" }
    local idx = 1
    while n >= 1024 and idx < #units do
        n = n / 1024
        idx = idx + 1
    end
    if idx == 1 then
        return string.format("%d %s", math.floor(n + 0.5), units[idx])
    end
    return string.format("%.2f %s", n, units[idx])
end

local UNIT_MULT = {
    B = 1,
    K = 1024, KB = 1024, KIB = 1024,
    M = 1048576, MB = 1048576, MIB = 1048576,
    G = 1073741824, GB = 1073741824, GIB = 1073741824,
    T = 1099511627776, TB = 1099511627776, TIB = 1099511627776
}

local function parse_size_str(s)
    s = trim(s)
    if s == "" or s == "-" then return 0 end
    local num_only = tonumber(s)
    if num_only then return math.floor(num_only) end
    local val, unit = s:match("([%d%.]+)%s*([%a]+)")
    if not val then return 0 end
    local mult = UNIT_MULT[(unit or ""):upper()] or 1
    return math.floor((tonumber(val) or 0) * mult + 0.5)
end

-- Convert calendar components + offset_minutes (e.g. +480 for UTC+8) to standard UTC ISO-8601 "...Z" and UTC epoch
local function components_to_utc_iso(y, m, d, hh, mm, ss, offset_min)
    local local_epoch = os.time({
        year = tonumber(y),
        month = tonumber(m),
        day = tonumber(d),
        hour = tonumber(hh) or 0,
        min = tonumber(mm) or 0,
        sec = tonumber(ss) or 0
    })
    if not local_epoch then return "", 0 end
    local utc_tbl = os.date("!*t", local_epoch)
    utc_tbl.isdst = false
    local router_tz_sec = os.difftime(local_epoch, os.time(utc_tbl))
    local true_utc_epoch = local_epoch + router_tz_sec - ((tonumber(offset_min) or 0) * 60)
    return os.date("!%Y-%m-%dT%H:%M:%SZ", true_utc_epoch), true_utc_epoch
end

local function epoch_to_iso_utc(epoch)
    if not epoch or epoch <= 0 then return "" end
    return os.date("!%Y-%m-%dT%H:%M:%SZ", epoch)
end

local function epoch_to_local_string(epoch)
    if not epoch or epoch <= 0 then return "" end
    return os.date("%Y-%m-%d %H:%M:%S", epoch)
end

-- Extract explicit timezone offset in minutes; default to +480 (UTC+8 Beijing time on dl.openwrt.ai) when omitted
local function detect_date_tz_offset_min(date_str)
    local upper = (date_str or ""):upper()
    if upper:match("GMT") or upper:match("UTC") or upper:match("%dZ$") then
        return 0
    end
    local sign, th, tm = date_str:match("([%+%-])(%d%d):?(%d%d)$")
    if sign and th and tm then
        local mins = (tonumber(th) or 0) * 60 + (tonumber(tm) or 0)
        return (sign == "-") and -mins or mins
    end
    return 480
end

local function build_ver_tuple(y, m, d)
    if not (y and m and d and y >= 2020 and y <= 2099 and m >= 1 and m <= 12 and d >= 1 and d <= 31) then
        return nil
    end
    local num_str = string.format("%04d%02d%02d", y, m, d)
    local iso, utc_epoch = components_to_utc_iso(y, m, d, 0, 0, 0, 480)
    return string.format("%02d.%02d.%04d", m, d, y), utc_epoch, num_str, iso
end

local function parse_version_token(ver_str)
    ver_str = trim(ver_str)
    if ver_str == "" then return "", 0, "", "" end

    local mm, dd, yyyy = ver_str:match("(%d%d)%.(%d%d)%.(%d%d%d%d)")
    if mm then
        local tag, ep, num, iso = build_ver_tuple(tonumber(yyyy), tonumber(mm), tonumber(dd))
        if tag then return tag, ep, num, iso end
    end

    local y2, m2, d2 = ver_str:match("(%d%d%d%d)[%.%-](%d%d)[%.%-](%d%d)")
    if y2 then
        local tag, ep, num, iso = build_ver_tuple(tonumber(y2), tonumber(m2), tonumber(d2))
        if tag then return tag, ep, num, iso end
    end

    local y3, m3, d3 = ver_str:match("(20%d%d)(%d%d)(%d%d)")
    if y3 then
        local tag, ep, num, iso = build_ver_tuple(tonumber(y3), tonumber(m3), tonumber(d3))
        if tag then return tag, ep, num, iso end
    end

    return "", 0, "", ""
end

local function normalize_date_str(date_str, filename)
    date_str = trim(date_str)
    if date_str:match("^%d+$") and #date_str >= 9 then
        return epoch_to_iso_utc(tonumber(date_str))
    end

    local tz_min = detect_date_tz_offset_min(date_str)

    local y, m, d, hh, mm, ss = date_str:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)[T%s]+(%d%d):(%d%d):?(%d*)")
    if y then
        local iso = components_to_utc_iso(y, m, d, hh, mm, (ss ~= "" and ss or "00"), tz_min)
        return iso
    end

    local y2, mon2, d2, hh2, mm2, ss2 = date_str:match("^(%d%d%d%d)%-(%a+)%-(%d%d)%s+(%d%d):(%d%d):?(%d*)")
    if y2 then
        local m_num = MONTHS[mon2:lower():sub(1, 3)]
        if m_num then
            local iso = components_to_utc_iso(y2, m_num, d2, hh2, mm2, (ss2 ~= "" and ss2 or "00"), tz_min)
            return iso
        end
    end

    local d3, mon3, y3, hh3, mm3, ss3 = date_str:match("^(%d%d)%-(%a+)%-(%d%d%d%d)%s+(%d%d):(%d%d):?(%d*)")
    if not d3 then
        d3, mon3, y3, hh3, mm3, ss3 = date_str:match("(%d+)%s+(%a+)%s+(%d%d%d%d)%s+(%d%d):(%d%d):?(%d*)")
    end
    if d3 then
        local m_num = MONTHS[mon3:lower():sub(1, 3)]
        if m_num then
            local iso = components_to_utc_iso(y3, m_num, d3, hh3, mm3, (ss3 ~= "" and ss3 or "00"), tz_min)
            return iso
        end
    end

    local _, _, _, iso_from_fn = parse_version_token(filename or "")
    return iso_from_fn or ""
end

local function read_openwrt_release()
    local info = {}
    for _, line in ipairs(read_lines("/etc/openwrt_release")) do
        local k, v = line:match("^([%w_]+)=['\"]?(.-)['\"]?$")
        if k then info[k] = trim(v) end
    end
    return info
end

local function get_system_version(rel_info)
    local ver = read_first_line("/etc/openwrt_version")
    local rel = rel_info or read_openwrt_release()
    local rev = rel.DISTRIB_REVISION or ""
    local desc = rel.DISTRIB_DESCRIPTION or ""

    if ver ~= "" and parse_version_token(ver) ~= "" then
        return ver
    end
    if rev ~= "" and parse_version_token(rev) ~= "" then
        return rev
    end
    if desc ~= "" then
        local dtag = parse_version_token(desc)
        if dtag ~= "" then return dtag end
    end
    return (ver ~= "" and ver ~= "SNAPSHOT") and ver or (rev ~= "" and rev or ver)
end

local function get_install_epoch()
    local epoch = tonumber(read_first_line("/etc/ghfu_flash_epoch"))
    if epoch and epoch > 0 then return epoch end
    local st = fs.stat("/etc/openwrt_version") or fs.stat("/etc/openwrt_release")
    return (st and tonumber(st.mtime)) or 0
end

local function get_tz_offset_minutes()
    local z = os.date("%z") or "+0000"
    local sign, hh, mm = z:match("([%+%-])(%d%d)(%d%d)")
    if not sign then return 0 end
    local v = (tonumber(hh) or 0) * 60 + (tonumber(mm) or 0)
    return (sign == "-") and -v or v
end

local function parent_disk_from_part(part_short)
    if not part_short or part_short == "" then return "" end
    local nvme_mmc = part_short:match("^(nvme%d+n%d+)p%d+$") or part_short:match("^(mmcblk%d+)p%d+$")
    if nvme_mmc then return nvme_mmc end
    return part_short:match("^([a-z]+)%d+$") or ""
end

local function detect_storage_and_boot(target, arch)
    local t_low = (target or ""):lower()
    local is_soft_target = (
        t_low:match("^x86/") or t_low:match("^armsr/") or t_low:match("^rockchip/") or
        t_low:match("^bcm27xx/") or t_low:match("^sunxi/") or t_low:match("^amlogic/") or
        t_low:match("^meson/") or arch == "x86_64"
    ) and true or false

    local function extract_dev_short(dev_path)
        dev_path = trim(dev_path)
        if dev_path == "" then return "" end
        local short = (dev_path:match("^/dev/(.+)$") or dev_path):gsub("%s.*$", "")
        if short:match("^sd[a-z]+%d+$") or short:match("^vd[a-z]+%d+$")
            or short:match("^hd[a-z]+%d+$") or short:match("^xvd[a-z]+%d+$")
            or short:match("^nvme%d+n%d+p%d+$") or short:match("^mmcblk%d+p%d+$") then
            return short
        end
        return ""
    end

    local dev_short = ""
    local root_arg = read_first_line("/proc/cmdline"):match("root=([^%s]+)")
    if root_arg and root_arg ~= "" then
        local tag_k, tag_v = root_arg:match("^(PARTUUID)=(.+)$")
        if not tag_k then tag_k, tag_v = root_arg:match("^(UUID)=(.+)$") end
        if tag_k and tag_v then
            local resolved = trim(sys.exec("blkid -t " .. tag_k .. "=" .. util.shellquote(tag_v) .. " -o device 2>/dev/null | head -n1"))
            dev_short = extract_dev_short(resolved)
        else
            dev_short = extract_dev_short(root_arg)
        end
    end

    if dev_short == "" then
        dev_short = extract_dev_short(read_first_line("/sys/block/loop0/loop/backing_file"))
    end

    local rootfs_fstype = ""
    for _, line in ipairs(read_lines("/proc/mounts")) do
        local mdev, mpoint, fstype = line:match("^([^%s]+)%s+([^%s]+)%s+([^%s]+)")
        if mpoint == "/rom" and fstype == "squashfs" then
            rootfs_fstype = "squashfs"
        elseif mpoint == "/" and rootfs_fstype == "" and fstype == "ext4" then
            rootfs_fstype = "ext4"
        end
        if dev_short == "" and (mpoint == "/rom" or mpoint == "/") and mdev and mdev:sub(1, 5) == "/dev/" then
            local cand = extract_dev_short(mdev)
            if cand ~= "" then dev_short = cand end
        end
    end

    if dev_short == "" and is_soft_target then
        for _, d in ipairs({ "nvme0n1p2", "mmcblk0p2", "mmcblk1p2", "vda2", "sda2", "xvda2" }) do
            if fs.access("/sys/class/block/" .. d .. "/size") then
                dev_short = d
                break
            end
        end
    end

    local is_soft_router = is_soft_target or (dev_short ~= "")
    local rootfs_partsize_mb = 0
    if is_soft_router and dev_short ~= "" then
        local sectors = tonumber(read_first_line("/sys/class/block/" .. dev_short .. "/size")) or 0
        if sectors > 0 then
            rootfs_partsize_mb = math.floor(sectors / 2048 + 0.5)
        else
            local bytes = tonumber(trim(sys.exec("blockdev --getsize64 " .. util.shellquote("/dev/" .. dev_short) .. " 2>/dev/null"))) or 0
            if bytes > 0 then
                rootfs_partsize_mb = math.floor(bytes / 1048576 + 0.5)
            end
        end
    end

    local show_part_warn = is_soft_router and rootfs_partsize_mb > 0
        and (math.abs(rootfs_partsize_mb - DEFAULT_ROOTFS_PARTSIZE_MB) > 8)

    local is_efi = fs.access("/sys/firmware/efi") and true or false
    local boot_disk = parent_disk_from_part(dev_short)
    local probe_disks = (boot_disk ~= "" and ("/dev/" .. boot_disk .. " ") or "") .. "/dev/nvme0n1 /dev/mmcblk0 /dev/vda /dev/sda"
    local pttype = trim(sys.exec("blkid -s PTTYPE -o value " .. probe_disks .. " 2>/dev/null | head -n1")):lower()
    local part_type
    if pttype == "gpt" then
        part_type = "gpt"
        is_efi = true
    elseif pttype == "dos" then
        part_type = "dos"
    else
        part_type = is_efi and "gpt" or "dos"
    end

    return {
        is_efi = is_efi,
        part_type = part_type,
        is_soft_router = is_soft_router,
        rootfs_partsize_mb = rootfs_partsize_mb,
        rootfs_fstype = rootfs_fstype,
        show_part_warn = show_part_warn
    }
end

local function detect_device_info()
    local ubus_board = util.ubus and util.ubus("system", "board") or nil
    local rel = read_openwrt_release()

    local target = rel.DISTRIB_TARGET or (ubus_board and ubus_board.release and trim(ubus_board.release.target)) or ""
    local distrib_rev = rel.DISTRIB_REVISION or (ubus_board and ubus_board.release and trim(ubus_board.release.revision)) or ""
    local distrib_desc = rel.DISTRIB_DESCRIPTION or (ubus_board and ubus_board.release and trim(ubus_board.release.description)) or ""
    local board_name = (ubus_board and trim(ubus_board.board_name)) or ""
    local model = (ubus_board and trim(ubus_board.model)) or ""

    if board_name == "" then board_name = read_first_line("/tmp/sysinfo/board_name") end
    if model == "" then model = read_first_line("/tmp/sysinfo/model") end

    if board_name == "" or model == "" then
        local bj = jsonc.parse(read_all("/etc/board.json"))
        if bj and type(bj.model) == "table" then
            if board_name == "" and bj.model.id then board_name = trim(bj.model.id) end
            if model == "" and bj.model.name then model = trim(bj.model.name) end
        end
    end

    local uname_tbl = nixio.uname and nixio.uname() or nil
    local arch = (uname_tbl and uname_tbl.machine) or ""

    if arch == "x86_64" and (board_name == "" or target == "x86/64") then
        board_name = board_name ~= "" and board_name or "x86_64"
    end

    local target_dash = target:gsub("/", "-")
    local target_under = target:gsub("/", "_")
    if target == "x86/64" or target_dash == "x86-64" or arch == "x86_64" then
        target_under = "x86_64"
        target_dash = "x86-64"
    end

    local board_norm = board_name:gsub(",", "_"):gsub("/", "_")
    local board_short = board_name:match(",(.+)$") or board_norm

    local candidates, seen = {}, {}
    local function add_candidate(p)
        p = trim(p):gsub("^/+", ""):gsub("/+$", "")
        if p ~= "" and not seen[p] then
            seen[p] = true
            candidates[#candidates + 1] = p
        end
    end

    if arch == "x86_64" or target == "x86/64" or board_norm == "x86_64" then
        add_candidate("x86_64")
    elseif board_norm == "x86_generic" or target == "x86/generic" then
        add_candidate("x86_32")
        add_candidate("x86-generic")
    end

    if target_dash ~= "" and board_norm ~= "" and board_norm ~= "x86_64" then
        add_candidate(target_dash .. "/" .. board_norm)
        if board_short ~= board_norm then
            add_candidate(target_dash .. "/" .. board_short)
        end
    end
    if target_under ~= "" and target_under ~= target_dash and board_norm ~= "" then
        add_candidate(target_under .. "/" .. board_norm)
    end
    if target ~= "" and target ~= target_dash and board_norm ~= "" and board_norm ~= "x86_64" then
        add_candidate(target .. "/" .. board_norm)
    end
    if target_dash ~= "" then add_candidate(target_dash) end
    if target_under ~= "" then add_candidate(target_under) end
    if target ~= "" then add_candidate(target) end

    local storage = detect_storage_and_boot(target, arch)

    return {
        target = target,
        target_dir = (arch == "x86_64" or target == "x86/64") and "x86_64" or target_dash,
        board_name = board_name,
        board_dir = board_norm,
        board_short = board_short,
        model = model,
        arch = arch,
        is_efi = storage.is_efi,
        part_type = storage.part_type,
        is_soft_router = storage.is_soft_router,
        rootfs_partsize_mb = storage.rootfs_partsize_mb,
        rootfs_fstype = storage.rootfs_fstype,
        show_part_warn = storage.show_part_warn,
        system_version = get_system_version(rel),
        distrib_rev = distrib_rev,
        distrib_desc = distrib_desc,
        candidates = candidates
    }
end

local function is_valid_firmware_file(name)
    if not name or name == "" then return false end
    local lower = name:lower()
    if lower == "parent directory" or lower:match("^%.%.?/$") or lower:match("/$") then
        return false
    end

    if lower:find("preloader", 1, true)
        or lower:find("uboot", 1, true)
        or lower:find("u-boot", 1, true)
        or lower:find("gpt.bin", 1, true)
        or lower:find("bl2.bin", 1, true)
        or lower:find("bl31", 1, true)
        or lower:find("fip.bin", 1, true)
        or lower:find("initramfs", 1, true)
        or lower:match("[-_%.]kernel%.bin$")
        or lower:match("[-_%.]rootfs")
        or lower:match("[-_%.]factory")
        or lower:match("[-_%.]recovery")
    then
        return false
    end

    for _, ext in ipairs(BUILTIN_VALID_EXTS) do
        if #lower > #ext and lower:sub(-#ext) == ext then
            return true
        end
    end
    return false
end

local function matches_board_token(lower_name, token)
    token = trim(token):lower()
    if token == "" or GENERIC_BOARD_NAMES[token] then return false end
    local init = 1
    while true do
        local s, e = lower_name:find(token, init, true)
        if not s then return false end
        local prev_ch = (s > 1) and lower_name:sub(s - 1, s - 1) or ""
        local next_ch = (e < #lower_name) and lower_name:sub(e + 1, e + 1) or ""
        if (prev_ch == "" or prev_ch:match("[^%w]")) and (next_ch == "" or next_ch:match("[^%w]")) then
            return true
        end
        init = s + 1
    end
end

local function filter_items_for_board(items, dev_info)
    if not dev_info then return items end
    local b_full = trim(dev_info.board_dir):lower()
    local b_short = trim(dev_info.board_short):lower()
    if GENERIC_BOARD_NAMES[b_full] and GENERIC_BOARD_NAMES[b_short] then
        return items
    end

    local want_ubootmod = b_full:find("ubootmod", 1, true) ~= nil
    local exact, fallback = {}, {}
    for _, item in ipairs(items) do
        local ln = tostring(item.name or ""):lower()
        if matches_board_token(ln, b_full) or matches_board_token(ln, b_short) then
            local has_ubootmod = ln:find("ubootmod", 1, true) ~= nil
            if want_ubootmod == has_ubootmod then
                exact[#exact + 1] = item
            else
                fallback[#fallback + 1] = item
            end
        end
    end

    if #exact > 0 then return exact end
    if #fallback > 0 then return fallback end
    return items
end

local function score_firmware_preference(name, dev_info)
    local lower = tostring(name or ""):lower()
    local score = 0
    local is_efi = dev_info and dev_info.is_efi
    local target_str = tostring(dev_info and dev_info.target or ""):lower()
    local board_str = tostring(dev_info and dev_info.board_dir or ""):lower()
    local fstype = tostring(dev_info and dev_info.rootfs_fstype or ""):lower()
    local is_efi_capable_target = dev_info and (
        dev_info.target_dir == "x86_64" or target_str:match("^x86/") or
        target_str:match("^armsr/") or dev_info.arch == "x86_64" or board_str == "x86_generic"
    )

    if matches_board_token(lower, board_str) then
        score = score + 50
    elseif dev_info and matches_board_token(lower, dev_info.board_short) then
        score = score + 40
    end

    if not board_str:find("ubootmod", 1, true) and lower:find("ubootmod", 1, true) then
        score = score - 150
    end

    if fstype == "ext4" then
        if lower:find("ext4", 1, true) then score = score + 25 end
    else
        if lower:find("squashfs", 1, true) then score = score + 25 end
    end

    if lower:sub(-3) == ".gz" then
        score = score + 5
    end

    if is_efi_capable_target then
        if is_efi then
            if lower:find("combined-efi", 1, true) or lower:find("-efi", 1, true) then
                score = score + 100
            elseif lower:find("combined", 1, true) then
                score = score + 30
            end
        else
            if lower:find("combined", 1, true) and not lower:find("-efi", 1, true) then
                score = score + 100
            elseif lower:find("combined-efi", 1, true) then
                score = score + 30
            end
        end
    elseif board_str:find("phicomm_k3", 1, true) or board_str:find("rt-ac88u", 1, true) then
        if lower:find("squashfs.trx", 1, true) then score = score + 100 end
    elseif target_str:find("sunxi", 1, true) then
        if lower:find("squashfs-sdcard", 1, true) or lower:find("sysupgrade", 1, true) then
            score = score + 100
        end
    else
        if lower:find("squashfs-sysupgrade", 1, true) then
            score = score + 100
        elseif lower:find("sysupgrade", 1, true) then
            score = score + 80
        end
    end

    return score
end

local function ensure_cfg_defaults()
    local changed = false
    if not uci:get(CFG, SEC) then
        uci:section(CFG, "ghfu", SEC, {})
        changed = true
    end
    if uci:get(CFG, SEC, "keep_config") == nil then
        uci:set(CFG, SEC, "keep_config", "1")
        changed = true
    end
    if uci:get(CFG, SEC, "retain_packages") == nil then
        uci:set(CFG, SEC, "retain_packages", "0")
        changed = true
    end
    for _, old_key in ipairs(LEGACY_CFG_KEYS) do
        if uci:get(CFG, SEC, old_key) ~= nil then
            uci:delete(CFG, SEC, old_key)
            changed = true
        end
    end
    if changed then uci:commit(CFG) end
end

local function get_cfg()
    ensure_cfg_defaults()
    local keep = uci:get(CFG, SEC, "keep_config") or "1"
    local retain = (keep == "1") and (uci:get(CFG, SEC, "retain_packages") or "0") or "0"
    return {
        selected_release = uci:get(CFG, SEC, "selected_release") or "",
        keep_config = keep,
        retain_packages = retain
    }
end

local function set_cfg(opts)
    if not opts then return end
    ensure_cfg_defaults()
    if opts.selected_release ~= nil then
        uci:set(CFG, SEC, "selected_release", opts.selected_release)
    end
    local keep = uci:get(CFG, SEC, "keep_config") or "1"
    if opts.keep_config ~= nil then
        keep = to_bool(opts.keep_config) and "1" or "0"
        uci:set(CFG, SEC, "keep_config", keep)
    end
    if opts.retain_packages ~= nil then
        local retain = (keep == "1" and to_bool(opts.retain_packages)) and "1" or "0"
        uci:set(CFG, SEC, "retain_packages", retain)
    elseif keep ~= "1" then
        uci:set(CFG, SEC, "retain_packages", "0")
    end
    uci:commit(CFG)
end

local function normalize_version(v)
    v = trim(v):gsub("^luci%-app%-ghfu[-%s]+", "")
    return v:match("([0-9][%w%.%+%-%_~]*)") or ""
end

local function read_pkg_db_version(path, pkg_prefix, ver_prefix)
    local f = io.open(path, "r")
    if not f then return "" end
    local found = (pkg_prefix == nil)
    for line in f:lines() do
        if pkg_prefix and line == pkg_prefix then
            found = true
        elseif found and line:sub(1, #ver_prefix) == ver_prefix then
            f:close()
            return normalize_version(line:sub(#ver_prefix + 1))
        elseif pkg_prefix and found and line == "" then
            found = false
        end
    end
    f:close()
    return ""
end

local function get_app_version()
    for _, p in ipairs({ "/lib/apk/db/installed", "/usr/lib/apk/db/installed" }) do
        local v = read_pkg_db_version(p, "P:luci-app-ghfu", "V:")
        if v ~= "" then return v end
    end
    local ctrl_v = read_pkg_db_version("/usr/lib/opkg/info/luci-app-ghfu.control", nil, "Version:")
    if ctrl_v ~= "" then return ctrl_v end
    local status_v = read_pkg_db_version("/usr/lib/opkg/status", "Package: luci-app-ghfu", "Version:")
    if status_v ~= "" then return status_v end
    return normalize_version(read_first_line("/usr/share/ghfu/version"))
end

local HAS_CURL = nil
local function http_get(url, timeout, custom_header)
    local t = math.min(300, math.max(3, math.floor(tonumber(timeout) or DEFAULT_FETCH_TIMEOUT)))
    local tmp = "/tmp/.ghfu_http_" .. tostring(nixio.getpid())
    fs.unlink(tmp)

    if HAS_CURL == nil then
        HAS_CURL = (fs.access("/usr/bin/curl") or fs.access("/bin/curl")) and true or false
    end

    local rc = 127
    if HAS_CURL then
        local hdr = (custom_header and custom_header ~= "") and (" -H " .. util.shellquote(custom_header)) or ""
        local base_args = " --connect-timeout 4 -m " .. tostring(t) .. hdr .. " -o " .. util.shellquote(tmp) .. " " .. util.shellquote(url)
        rc = tonumber(trim(sys.exec("curl -sfL" .. base_args .. " 2>/dev/null; printf '%d' $?"))) or 1
        if rc == 60 or rc == 77 or rc == 35 then
            rc = tonumber(trim(sys.exec("curl -skfL" .. base_args .. " 2>/dev/null; printf '%d' $?"))) or 1
        end
    else
        local hdr = (custom_header and custom_header ~= "") and (" --header=" .. util.shellquote(custom_header)) or ""
        rc = tonumber(trim(sys.exec("wget -T " .. tostring(t) .. hdr .. " -qO " .. util.shellquote(tmp) .. " " .. util.shellquote(url) .. " 2>/dev/null; printf '%d' $?"))) or 1
    end

    if rc == 0 then
        local body = read_all(tmp)
        fs.unlink(tmp)
        return body, "ok"
    end
    fs.unlink(tmp)
    if rc == 22 or rc == 8 then
        return "", "http_err"
    end
    return "", "net_err"
end

local function parse_sha256sums(raw)
    local map = {}
    for line in (raw or ""):gmatch("[^\r\n]+") do
        local hash, fname = line:match("^([a-fA-F0-9]+)%s+%*?(.+)$")
        if hash and fname and #hash == 64 then
            fname = trim(fname):gsub("^%./", "")
            local base = fname:match("([^/]+)$") or fname
            local h = hash:lower()
            map[fname] = h
            map[base] = h
        end
    end
    return map
end

local function url_decode(s)
    return (s:gsub("%%(%x%x)", function(h)
        return string.char(tonumber(h, 16))
    end))
end

local function parse_directory_json(raw, dir_url, sha256_map)
    local obj = jsonc.parse(raw)
    if type(obj) ~= "table" then return nil end

    local base = dir_url:gsub("/+$", "")
    local items = {}

    local function collect_entry(entry, fallback_date)
        if type(entry) ~= "table" or entry.type == "directory" or not entry.name then return end
        local fname = tostring(entry.name)
        if not is_valid_firmware_file(fname) then return end
        local fsize = tonumber(entry.size) or parse_size_str(tostring(entry.size or "0"))
        local fdate = normalize_date_str(tostring(entry.mtime or entry.date or entry.published_at or fallback_date or ""), fname)
        local fsha = tostring(entry.sha256 or ""):lower()
        if fsha == "" and sha256_map then fsha = sha256_map[fname] or "" end
        items[#items + 1] = {
            name = fname,
            url = entry.url or (base .. "/" .. fname),
            size = fsize,
            sha256 = fsha,
            date_iso = fdate
        }
    end

    if #obj > 0 then
        for _, entry in ipairs(obj) do collect_entry(entry, nil) end
    elseif type(obj.files or obj.assets or obj.images) == "table" then
        for _, entry in pairs(obj.files or obj.assets or obj.images) do
            collect_entry(entry, obj.build_at)
        end
    end

    return (#items > 0) and items or nil
end

local function parse_directory_html(html, dir_url, sha256_map)
    if not html or html == "" then return nil end
    local base_url = dir_url:gsub("/+$", "")
    local origin = base_url:match("^(https?://[^/]+)") or ""
    local items, seen = {}, {}

    local function add_item(href, size_str, date_str)
        href = trim(href)
        if href == "" or href:match("^[%?#]") or href:match("^javascript:") then return end
        local clean_href = href:gsub("%?.*$", "")
        if clean_href == "../" or clean_href == "./" or clean_href == "/" or clean_href:match("/$") then return end

        local fname = clean_href:match("([^/]+)$")
        if not fname then return end
        fname = url_decode(fname)
        if not is_valid_firmware_file(fname) or seen[fname] then return end

        local full_url
        if href:match("^https?://") then
            full_url = href
        elseif href:sub(1, 1) == "/" then
            full_url = origin .. clean_href
        else
            full_url = base_url .. "/" .. clean_href
        end

        seen[fname] = true
        items[#items + 1] = {
            name = fname,
            url = full_url,
            size = parse_size_str(size_str),
            sha256 = (sha256_map and sha256_map[fname]) or "",
            date_iso = normalize_date_str(date_str, fname)
        }
    end

    for tr_block in html:gmatch("<tr[^>]*>(.-)</tr>") do
        local href = tr_block:match('<a[^>]+href=["\']([^"\']+)["\']')
        if href then
            local size_str, date_str = "", ""
            for td in tr_block:gmatch("<td[^>]*>(.-)</td>") do
                local c = trim(td:gsub("<[^>]+>", " "):gsub("&nbsp;", " "):gsub("&#160;", " "):gsub("%s+", " "))
                if size_str == "" and (c:match("^%d+%.?%d*%s*[KMGTkmgt][iI]?[bB]?$") or c:match("^%d+%s*[bB]?$")) then
                    size_str = c
                elseif date_str == "" and (
                    c:match("%d%d%d%d%-%a+%-%d%d") or c:match("%d%d%-%a+%-%d%d%d%d") or
                    c:match("%d%d%d%d%-%d%d%-%d%d") or c:match("%d+%s+%a+%s+%d%d%d%d")
                ) then
                    date_str = c
                end
            end
            add_item(href, size_str, date_str)
        end
    end

    if #items == 0 then
        for line in html:gmatch("[^\r\n]+") do
            local href, rest = line:match('<a[^>]+href=["\']([^"\']+)["\'][^>]*>.-</a>%s*(.*)$')
            if href then
                rest = (rest or ""):gsub("<[^>]+>", " "):gsub("&nbsp;", " ")
                local date_str = rest:match("(%d%d%-%a+%-%d%d%d%d%s+%d%d:%d%d)")
                    or rest:match("(%d%d%d%d%-%a+%-%d%d%s+%d%d:%d%d)")
                    or rest:match("(%d%d%d%d%-%d%d%-%d%d%s+%d%d:%d%d)")
                    or rest:match("(%d+%s+%a+%s+%d%d%d%d%s+%d%d:%d%d)")
                    or ""
                local size_str = rest:match("%s+(%d+%.?%d*%s*[KMGTkmgt]?[iI]?[bB]?)%s*$")
                    or rest:match("%s+(%d+)%s*$")
                    or ""
                add_item(href, size_str, date_str)
            end
        end
    end

    return (#items > 0) and items or nil
end

local function build_release_from_items(items, dir_url, resolved_subpath, dev_info)
    items = filter_items_for_board(items, dev_info)
    local sys_ver = (dev_info and dev_info.system_version) or get_system_version()
    local _, _, sys_ver_num = parse_version_token(sys_ver)

    for _, item in ipairs(items) do
        local vtag, vepoch, vnum, viso = parse_version_token(item.name)
        if vtag == "" and item.date_iso and item.date_iso ~= "" then
            vtag, vepoch, vnum, viso = parse_version_token(item.date_iso)
        end
        if (not item.date_iso or item.date_iso == "") and viso ~= "" then
            item.date_iso = viso
        end
        item.version_tag = vtag
        item.version_num = vnum
        item.version_epoch = vepoch
        item.pref_score = score_firmware_preference(item.name, dev_info)
    end

    table.sort(items, function(a, b)
        if a.version_num ~= "" and b.version_num ~= "" and a.version_num ~= b.version_num then
            return a.version_num > b.version_num
        end
        if a.pref_score ~= b.pref_score then
            return a.pref_score > b.pref_score
        end
        if a.date_iso ~= "" and b.date_iso ~= "" and a.date_iso ~= b.date_iso then
            return a.date_iso > b.date_iso
        end
        return a.name < b.name
    end)

    local newest = items[1]
    local latest_ver = (newest and newest.version_tag) or ""
    local latest_ver_num = (newest and newest.version_num) or ""
    local latest_epoch = (newest and newest.version_epoch) or 0

    local latest_date = ""
    for _, item in ipairs(items) do
        if (latest_ver_num == "" or item.version_num == latest_ver_num) and item.date_iso and item.date_iso > latest_date then
            latest_date = item.date_iso
        end
    end

    local is_formal = (latest_epoch <= 0) or (((os.time() or 0) - 172800) > latest_epoch)

    local assets = {}
    for _, item in ipairs(items) do
        local is_latest_item
        if latest_ver_num ~= "" and item.version_num ~= "" then
            is_latest_item = (item.version_num == latest_ver_num)
        elseif latest_ver ~= "" and item.version_tag ~= "" then
            is_latest_item = (item.version_tag == latest_ver)
        elseif latest_date ~= "" and item.date_iso ~= "" then
            is_latest_item = (item.date_iso:sub(1, 10) == latest_date:sub(1, 10))
        else
            is_latest_item = (item == newest)
        end

        local relation = "older"
        if item.version_num ~= "" and sys_ver_num ~= "" then
            if item.version_num > sys_ver_num then
                relation = "newer"
            elseif item.version_num == sys_ver_num then
                relation = "same"
            end
        elseif is_latest_item then
            relation = "latest"
        end

        assets[#assets + 1] = {
            name = item.name,
            url = item.url,
            size = item.size or 0,
            sha256 = item.sha256 or "",
            published_at = item.date_iso or "",
            version_tag = item.version_tag or "",
            version_num = item.version_num or "",
            is_latest = is_latest_item,
            relation = relation,
            recommended = (item == newest)
        }
    end

    return {
        tag_name = latest_ver ~= "" and latest_ver or "latest",
        release_name = latest_ver ~= "" and latest_ver or (resolved_subpath ~= "" and resolved_subpath or "Latest"),
        version_num = latest_ver_num,
        version_epoch = latest_epoch,
        notice = is_formal,
        published_at = latest_date,
        html_url = dir_url:gsub("/+$", "") .. "/",
        resolved_path = resolved_subpath or "",
        assets = assets
    }
end

local function try_fetch_firmware_dir(dir_url, timeout, subpath_label, dev_info)
    dir_url = dir_url:gsub("/+$", "")
    local raw, status_kind = http_get(dir_url .. "/", timeout, "Accept: application/json, text/html;q=0.9")
    if status_kind == "net_err" then
        return nil, "net_err"
    end
    local trimmed = trim(raw)
    if trimmed == "" then
        return nil, "empty"
    end

    local sha256_map = {}
    if raw:lower():find("sha256sums", 1, true) then
        local sha_raw = http_get(dir_url .. "/sha256sums", math.min(timeout, 5))
        sha256_map = parse_sha256sums(sha_raw)
    end

    local first_ch = trimmed:sub(1, 1)
    local items = (first_ch == "{" or first_ch == "[")
        and parse_directory_json(trimmed, dir_url, sha256_map)
        or parse_directory_html(raw, dir_url, sha256_map)

    if not items or #items == 0 then
        return nil, "no_items"
    end
    return build_release_from_items(items, dir_url, subpath_label, dev_info), "ok"
end

local function fetch_dl_openwrt_firmware(dev_info, timeout)
    local base_url = FIRMWARE_BASE_URL
    local net_failed = false

    for _, subpath in ipairs((dev_info and dev_info.candidates) or {}) do
        local rel, kind = try_fetch_firmware_dir(base_url .. "/" .. subpath, timeout, subpath, dev_info)
        if rel and #rel.assets > 0 then
            return rel, nil, { resolved_path = subpath }
        end
        if kind == "net_err" then
            net_failed = true
            break
        end
    end

    if not net_failed and dev_info and dev_info.target_dir ~= "" and dev_info.board_dir ~= "" then
        local target_html, kind = http_get(base_url .. "/" .. dev_info.target_dir .. "/", timeout)
        if kind == "ok" and target_html ~= "" then
            local subdirs = {}
            for href in target_html:gmatch('<a[^>]+href=["\']([^"\']+/)["\']') do
                local dname = href:gsub("/+$", ""):match("([^/]+)$")
                if dname and dname ~= ".." and dname ~= "." and not dname:match("^%?") then
                    subdirs[#subdirs + 1] = url_decode(dname)
                end
            end

            local b_full = dev_info.board_dir:lower()
            local b_short = (dev_info.board_short or dev_info.board_dir):lower()
            local best_dir = nil

            for _, d in ipairs(subdirs) do
                local dl = d:lower()
                if dl == b_full or dl == b_short then
                    best_dir = d
                    break
                end
            end
            if not best_dir then
                for _, d in ipairs(subdirs) do
                    local dl = d:lower()
                    if matches_board_token(dl, b_full) or (b_short ~= "" and matches_board_token(dl, b_short)) then
                        best_dir = d
                        break
                    end
                end
            end

            if best_dir then
                local matched_subpath = dev_info.target_dir .. "/" .. best_dir
                local rel = try_fetch_firmware_dir(base_url .. "/" .. matched_subpath, timeout, matched_subpath, dev_info)
                if rel and #rel.assets > 0 then
                    return rel, nil, { resolved_path = matched_subpath }
                end
            end
        end
    end

    if net_failed then
        return nil, tr("Unable to fetch firmware list, please check your network connection")
    end
    local hint_path = (dev_info and dev_info.candidates and dev_info.candidates[1]) or ""
    return nil, tr("Failed to fetch firmware list from server") .. (hint_path ~= "" and (" (" .. base_url .. "/" .. hint_path .. ")") or "")
end

local function evaluate_update_status(latest, dev_info, install_epoch)
    local sys_ver = (dev_info and dev_info.system_version) or get_system_version()
    local _, sys_ver_epoch, sys_ver_num = parse_version_token(sys_ver)
    local _, rem_ver_epoch, rem_ver_num = parse_version_token(latest.release_name or latest.tag_name or "")

    if rem_ver_num ~= "" and sys_ver_num ~= "" then
        return rem_ver_num > sys_ver_num
    elseif rem_ver_epoch > 0 and sys_ver_epoch > 0 then
        return rem_ver_epoch > sys_ver_epoch
    end
    local install_iso = epoch_to_iso_utc(install_epoch)
    return (latest.published_at ~= "" and install_iso ~= "" and latest.published_at > install_iso) or false
end

local function save_sysver_cache(has_new, is_formal, now_version, latest_version)
    write_file(CHECK_CACHE_FILE, jsonc.stringify({
        ts = os.time() or 0,
        now_version = now_version or "",
        version = latest_version or "",
        update = has_new and true or false,
        is_formal = (is_formal ~= false)
    }))
end

local function load_sysver_cache(now_version)
    local parsed = jsonc.parse(read_all(CHECK_CACHE_FILE))
    if type(parsed) ~= "table" then return nil end
    local age = (os.time() or 0) - (tonumber(parsed.ts) or 0)
    if age < 0 or age > CHECK_CACHE_TTL or parsed.now_version ~= (now_version or "") then
        return nil
    end
    return parsed
end

local function kill_active_download()
    local pid_raw = read_all(PID_FILE)
    for pid in pid_raw:gmatch("%d+") do
        sys.call("kill -9 " .. pid .. " 2>/dev/null")
    end
    fs.unlink(PID_FILE)
end

local function validate_downloaded_firmware(fw_path, known_sha256)
    local st = fs.stat(fw_path)
    local fsize = (st and st.size) or 0
    local fmtime = (st and st.mtime) or 0

    local cached = jsonc.parse(read_all(VALIDATE_CACHE_FILE))
    if type(cached) == "table" and cached.fw_path == fw_path and cached.size == fsize and cached.mtime == fmtime then
        return cached
    end

    local res = util.ubus and util.ubus("system", "validate_firmware_image", { path = fw_path }) or nil
    if type(res) ~= "table" and fs.access("/usr/libexec/validate_firmware_image") then
        res = jsonc.parse(sys.exec("/usr/libexec/validate_firmware_image " .. util.shellquote(fw_path) .. " 2>/dev/null"))
    end

    local valid = true
    local forceable = true
    local allow_backup = true
    local detail_msg = ""

    if type(res) == "table" then
        valid = (res.valid == true)
        forceable = (res.forceable ~= false)
        allow_backup = (res.allow_backup ~= false)
        if not valid then
            detail_msg = trim(sys.exec("/sbin/sysupgrade -T " .. util.shellquote(fw_path) .. " 2>&1"))
            if detail_msg == "" and type(res.tests) == "table" then
                local failed = {}
                for k, v in pairs(res.tests) do
                    if v == false then failed[#failed + 1] = tostring(k) .. ": false" end
                end
                detail_msg = table.concat(failed, "\n")
            end
        end
    else
        local val_tmp = "/tmp/.ghfu_val_" .. tostring(nixio.getpid())
        local rc = tonumber(trim(sys.exec("/sbin/sysupgrade -T " .. util.shellquote(fw_path) .. " >" .. util.shellquote(val_tmp) .. " 2>&1; printf '%d' $?"))) or 1
        valid = (rc == 0)
        if not valid then
            detail_msg = trim(read_all(val_tmp))
        end
        fs.unlink(val_tmp)
    end

    local sha256 = (known_sha256 and known_sha256:match("^[a-f0-9]+$") and #known_sha256 == 64)
        and known_sha256
        or trim(sys.exec("sha256sum " .. util.shellquote(fw_path) .. " 2>/dev/null | awk '{print $1}'"))

    local result = {
        fw_path = fw_path,
        mtime = fmtime,
        valid = valid,
        forceable = forceable,
        allow_backup = allow_backup,
        message = detail_msg,
        size = fsize,
        sha256 = sha256
    }

    write_file(VALIDATE_CACHE_FILE, jsonc.stringify(result))
    return result
end

local function build_local_status()
    local cfg = get_cfg()
    local app_version = get_app_version()
    local install_epoch = get_install_epoch()
    local dev_info = detect_device_info()
    local uci_changes = uci:changes()
    local has_unsaved_uci = (uci_changes and next(uci_changes) ~= nil) and true or false

    return {
        ok = true,
        app_version = app_version,
        config = cfg,
        device_info = dev_info,
        has_unsaved_uci = has_unsaved_uci,
        install_epoch = install_epoch,
        install_time = epoch_to_local_string(install_epoch),
        tz_offset_min = get_tz_offset_minutes()
    }
end

function index()
    if not fs.access("/etc/config/ghfu") then return end

    entry({"admin", "system", "ghfu"}, call("action_index"), _("System Online Upgrade"), 2)
    entry({"admin", "system", "ghfu", "status"}, call("action_status")).leaf = true
    entry({"admin", "system", "ghfu", "local_status"}, call("action_local_status")).leaf = true
    entry({"admin", "system", "ghfu", "sysversion_check"}, call("action_sysversion_check")).leaf = true
    entry({"admin", "system", "ghfu", "config"}, call("action_config")).leaf = true
    entry({"admin", "system", "ghfu", "download"}, call("action_download")).leaf = true
    entry({"admin", "system", "ghfu", "download_status"}, call("action_download_status")).leaf = true
    entry({"admin", "system", "ghfu", "upgrade"}, call("action_upgrade")).leaf = true
    entry({"admin", "system", "ghfu", "cancel_upgrade"}, call("action_cancel_upgrade")).leaf = true
    entry({"admin", "system", "ghfu", "backup"}, call("action_backup")).leaf = true
end

function action_index()
    local init_state = build_local_status()
    local safe_json = (jsonc.stringify(init_state) or "{}")
        :gsub("</", "<\\/")
        :gsub("\226\128\168", "\\u2028")
        :gsub("\226\128\169", "\\u2029")
    luci.template.render("ghfu/main", {
        app_version = init_state.app_version,
        initial_json = safe_json
    })
end

function action_local_status()
    json_resp(build_local_status())
end

function action_sysversion_check()
    local dev_info = detect_device_info()
    local cached = load_sysver_cache(dev_info.system_version)
    if cached then
        json_resp({
            code = 0,
            update = cached.update,
            notice = cached.update,
            is_formal = cached.is_formal,
            now_version = cached.now_version,
            version = cached.version
        })
        return
    end

    local install_epoch = get_install_epoch()
    local latest = fetch_dl_openwrt_firmware(dev_info, 6)
    if not latest then
        json_resp({ code = 1 })
        return
    end

    local has_new = evaluate_update_status(latest, dev_info, install_epoch)
    save_sysver_cache(has_new, latest.notice, dev_info.system_version, latest.release_name)

    json_resp({
        code = 0,
        update = has_new,
        notice = has_new,
        is_formal = latest.notice,
        now_version = dev_info.system_version,
        version = latest.release_name
    })
end

function action_status()
    local state = build_local_status()
    local dev_info = state.device_info

    local latest, err, rel_info = fetch_dl_openwrt_firmware(dev_info, DEFAULT_FETCH_TIMEOUT)
    if not latest then
        state.ok = false
        state.msg = err or tr("Unable to fetch firmware list, please check your network connection")
        json_resp(state)
        return
    end

    local function fetch_valid_updatelogs(base_dir_url)
        if not base_dir_url or base_dir_url == "" then return "" end
        local raw, kind = http_get(base_dir_url:gsub("/+$", "") .. "/updatelogs.txt", 8)
        if kind ~= "ok" then return "" end
        local txt = trim(raw)
        local low = txt:lower()
        if low:match("^<!doctype") or low:match("^<html") then return "" end
        return txt
    end

    local base_url_clean = FIRMWARE_BASE_URL:gsub("/+$", "")
    local fw_dir_url = (latest.html_url or ""):gsub("/+$", "")
    local parent_target_url = (fw_dir_url ~= "") and (fw_dir_url:match("^(.*)/[^/]+$") or "") or ""

    local updatelogs = ""
    if fw_dir_url ~= "" and fw_dir_url ~= base_url_clean then
        updatelogs = fetch_valid_updatelogs(fw_dir_url)
    end
    if updatelogs == "" and parent_target_url ~= "" and parent_target_url ~= fw_dir_url
        and parent_target_url ~= base_url_clean
        and parent_target_url:sub(1, #base_url_clean + 1) == (base_url_clean .. "/") then
        updatelogs = fetch_valid_updatelogs(parent_target_url)
    end
    if updatelogs == "" then
        updatelogs = fetch_valid_updatelogs(base_url_clean)
    end

    latest.release_total_count = (latest.assets and #latest.assets) or 0
    latest.updatelogs = updatelogs

    local has_new = evaluate_update_status(latest, dev_info, state.install_epoch)
    save_sysver_cache(has_new, latest.notice, dev_info.system_version, latest.release_name)

    state.ok = true
    state.msg = has_new and tr("New firmware is available") or tr("No firmware newer than current system was found")
    state.has_new = has_new
    state.notice = latest.notice
    state.resolved_path = latest.resolved_path or (rel_info and rel_info.resolved_path) or ""
    state.updatelogs = updatelogs
    state.latest = latest
    json_resp(state)
end

function action_config()
    set_cfg({
        keep_config = http.formvalue("keep_config"),
        retain_packages = http.formvalue("retain_packages")
    })
    json_resp({ ok = true, config = get_cfg() })
end

function action_download()
    local selected_release = trim(http.formvalue("selected_release"))
    local keep_config = to_bool(http.formvalue("keep_config")) and "1" or "0"
    local retain_packages = (keep_config == "1" and to_bool(http.formvalue("retain_packages"))) and "1" or "0"
    local asset_url = trim(http.formvalue("asset_url"))
    local asset_name = trim(http.formvalue("asset_name"))
    local asset_size = math.max(0, math.floor(tonumber(trim(http.formvalue("asset_size"))) or 0))
    local asset_digest = trim(http.formvalue("asset_digest")):lower()
    if not asset_digest:match("^[a-f0-9]+$") or #asset_digest ~= 64 then
        asset_digest = ""
    end

    set_cfg({ keep_config = keep_config, retain_packages = retain_packages })

    if selected_release == "" then
        json_resp({ ok = false, logs = { tr("Please select firmware to upgrade") } })
        return
    end
    if asset_url == "" then
        json_resp({ ok = false, logs = { tr("Please select a firmware asset") } })
        return
    end
    if not asset_url:match("^https://dl%.openwrt%.ai/firmware/") or asset_url:find("..", 1, true) or asset_url:match("%s") then
        json_resp({ ok = false, logs = { tr("Invalid firmware URL, only https://dl.openwrt.ai/firmware is supported") } })
        return
    end

    local clean_name = asset_name:gsub("[^%w%._%-]", "_"):gsub("^%.+", "")
    if clean_name == "" then clean_name = "firmware.bin.gz" end

    kill_active_download()
    sys.call("rm -f /tmp/ghfu_* /tmp/ghfu-validate.json 2>/dev/null")
    fs.unlink(PROGRESS_LOG_FILE)
    fs.unlink(RAW_LOG_FILE)

    if asset_size > 0 and fs.statvfs then
        local vfs = fs.statvfs("/tmp")
        if vfs and vfs.bfree and vfs.frsize then
            local free_bytes = (tonumber(vfs.bavail or vfs.bfree) or 0) * (tonumber(vfs.frsize) or 4096)
            if free_bytes > 0 and free_bytes < (asset_size + 4 * 1048576) then
                json_resp({
                    ok = false,
                    logs = { tr("Insufficient /tmp memory space for firmware download") .. " (" .. human_bytes(free_bytes) .. " < " .. human_bytes(asset_size) .. ")" }
                })
                return
            end
        end
    end

    local fw_path = "/tmp/ghfu_" .. clean_name
    local download_timeout = 300

    local shell_script = table.concat({
        "progress_log=", util.shellquote(PROGRESS_LOG_FILE), "\n",
        "raw_log=", util.shellquote(RAW_LOG_FILE), "\n",
        "pid_file=", util.shellquote(PID_FILE), "\n",
        "target=", util.shellquote(fw_path), "\n",
        "total=", tostring(asset_size), "\n",
        "timeout=", tostring(download_timeout), "\n",
        "url=", util.shellquote(asset_url), "\n",
        "expected=", util.shellquote(asset_digest), "\n",
        ": > \"$progress_log\"\n",
        ": > \"$raw_log\"\n",
        "start_dl() {\n",
        "  if command -v curl >/dev/null 2>&1; then\n",
        "    if [ \"$1\" = \"1\" ]; then\n",
        "      curl -skfL --connect-timeout 15 -m \"$timeout\" -o \"$target\" \"$url\" >\"$raw_log\" 2>&1 &\n",
        "    else\n",
        "      curl -sfL --connect-timeout 15 -m \"$timeout\" -o \"$target\" \"$url\" >\"$raw_log\" 2>&1 &\n",
        "    fi\n",
        "  elif command -v wget >/dev/null 2>&1; then\n",
        "    wget -T \"$timeout\" -O \"$target\" \"$url\" >\"$raw_log\" 2>&1 &\n",
        "  else\n",
        "    echo \"curl/wget is not installed\" >\"$raw_log\"\n",
        "    return 127\n",
        "  fi\n",
        "  dlpid=$!\n",
        "  printf '%s %s\\n' \"$$\" \"$dlpid\" > \"$pid_file\"\n",
        "  return 0\n",
        "}\n",
        "monitor_dl() {\n",
        "  prev_size=0\n",
        "  prev_ts=$(date +%s)\n",
        "  last_pct=-1\n",
        "  while kill -0 \"$dlpid\" 2>/dev/null; do\n",
        "    sleep 1\n",
        "    size=$(wc -c < \"$target\" 2>/dev/null)\n",
        "    [ -z \"$size\" ] && size=0\n",
        "    now=$(date +%s)\n",
        "    elapsed=$((now - prev_ts))\n",
        "    [ \"$elapsed\" -le 0 ] && elapsed=1\n",
        "    rate=$(((size - prev_size) / elapsed))\n",
        "    [ \"$rate\" -lt 0 ] && rate=0\n",
        "    if [ \"$total\" -gt 0 ]; then\n",
        "      pct=$((size * 100 / total))\n",
        "      [ \"$pct\" -gt 100 ] && pct=100\n",
        "      if [ \"$pct\" -ne \"$last_pct\" ]; then\n",
        "        echo \"PROGRESS|$pct|$size|$total|$rate\" >> \"$progress_log\"\n",
        "        last_pct=$pct\n",
        "      fi\n",
        "    else\n",
        "      echo \"PROGRESS|0|$size|0|$rate\" >> \"$progress_log\"\n",
        "    fi\n",
        "    prev_size=$size\n",
        "    prev_ts=$now\n",
        "  done\n",
        "  wait \"$dlpid\"\n",
        "  return $?\n",
        "}\n",
        "if start_dl 0; then\n",
        "  monitor_dl\n",
        "  rc=$?\n",
        "  if [ \"$rc\" -eq 60 ] || [ \"$rc\" -eq 77 ] || [ \"$rc\" -eq 35 ]; then\n",
        "    if start_dl 1; then monitor_dl; rc=$?; fi\n",
        "  fi\n",
        "else\n",
        "  rc=$?\n",
        "fi\n",
        "rm -f \"$pid_file\"\n",
        "size=$(wc -c < \"$target\" 2>/dev/null)\n",
        "[ -z \"$size\" ] && size=0\n",
        "if [ \"$rc\" -eq 0 ] && [ -s \"$target\" ]; then\n",
        "  sha256=$(sha256sum \"$target\" 2>/dev/null | awk '{print $1}')\n",
        "  if [ -n \"$expected\" ] && [ -n \"$sha256\" ]; then\n",
        "    if [ \"$sha256\" = \"$expected\" ]; then\n",
        "      echo \"SHA256OK|$sha256\" >> \"$progress_log\"\n",
        "      echo \"DONE|OK|$size|$total|$target|$sha256\" >> \"$progress_log\"\n",
        "    else\n",
        "      echo \"SHA256FAIL|$sha256|$expected\" >> \"$progress_log\"\n",
        "      echo \"DONE|FAIL|$size|$total|$target|\" >> \"$progress_log\"\n",
        "      rm -f \"$target\"\n",
        "    fi\n",
        "  else\n",
        "    echo \"DONE|OK|$size|$total|$target|$sha256\" >> \"$progress_log\"\n",
        "  fi\n",
        "else\n",
        "  echo \"DONE|FAIL|$size|$total|$target|\" >> \"$progress_log\"\n",
        "  rm -f \"$target\"\n",
        "  [ -s \"$raw_log\" ] && sed 's/^/ERR|/' \"$raw_log\" >> \"$progress_log\"\n",
        "fi\n"
    })

    local logs = { tr("Downloading firmware:") .. " " .. clean_name }
    local start_rc = tonumber(trim(sys.exec("sh -c " .. util.shellquote("(" .. shell_script .. ") </dev/null >/dev/null 2>&1 &") .. "; printf '%d' $?"))) or 1
    if start_rc ~= 0 then
        logs[#logs + 1] = tr("Firmware download failed, please check network connection")
        json_resp({ ok = false, logs = logs })
        return
    end

    json_resp({ ok = true, started = true, logs = logs })
end

function action_download_status()
    local offset = math.max(0, tonumber(trim(http.formvalue("offset") or "0")) or 0)
    local lines = read_lines(PROGRESS_LOG_FILE)
    local total_lines = #lines

    local done = false
    local download_ok = false
    local sha256_fail = false
    local fw_name = ""
    local fw_target_path = ""
    local fw_sha256 = ""
    local progress_pct = -1
    local downloaded_size = 0
    local total_size = 0

    for _, line in ipairs(lines) do
        local p_pct, p_size, p_total = line:match("^PROGRESS|(%d+)|(%d+)|(%d+)|%-?%d+$")
        if p_pct then
            downloaded_size = tonumber(p_size) or 0
            total_size = tonumber(p_total) or 0
            progress_pct = (total_size > 0) and (tonumber(p_pct) or 0) or -1
        end
        local status, _, _, rest = line:match("^DONE|([A-Z]+)|(%d+)|(%d+)|(.+)$")
        if status then
            done = true
            download_ok = (status == "OK")
            local target, sha = rest:match("^(.-)|([a-f0-9]*)$")
            fw_target_path = trim(target or rest)
            fw_sha256 = trim(sha or "")
            fw_name = fw_target_path:match("^/tmp/ghfu_(.+)$") or ""
        end
        if line:match("^SHA256FAIL|") then
            sha256_fail = true
        end
    end

    if sha256_fail then download_ok = false end

    local logs = {}
    for i = offset + 1, total_lines do
        local line = lines[i]
        local pct, size, total, rate = line:match("^PROGRESS|(%d+)|(%d+)|(%d+)|(%-?%d+)$")
        if pct then
            local speed_text = human_bytes(rate) .. "/s"
            if (tonumber(total) or 0) > 0 then
                logs[#logs + 1] = tr("Download progress:") .. " " .. pct .. "% (" .. human_bytes(size) .. "/" .. human_bytes(total) .. "), " .. tr("Speed:") .. " " .. speed_text
            else
                logs[#logs + 1] = tr("Download progress:") .. " " .. human_bytes(size) .. ", " .. tr("Speed:") .. " " .. speed_text
            end
        else
            local status2, done_size, done_total, rest2 = line:match("^DONE|([A-Z]+)|(%d+)|(%d+)|(.+)$")
            if status2 then
                if status2 == "OK" then
                    if (tonumber(done_total) or 0) > 0 then
                        logs[#logs + 1] = tr("Download finished:") .. " " .. human_bytes(done_size) .. "/" .. human_bytes(done_total)
                    else
                        logs[#logs + 1] = tr("Download finished:") .. " " .. human_bytes(done_size)
                    end
                    local target2 = rest2:match("^(.-)|[a-f0-9]*$") or rest2
                    local name2 = trim(target2):match("^/tmp/ghfu_(.+)$")
                    if name2 and name2 ~= "" then
                        logs[#logs + 1] = name2 .. " " .. tr("downloaded successfully")
                    end
                else
                    logs[#logs + 1] = tr("Firmware download failed, please check network connection")
                end
            else
                local sha256ok_hash = line:match("^SHA256OK|([a-f0-9]+)$")
                if sha256ok_hash then
                    logs[#logs + 1] = tr("SHA256 verification passed:") .. " " .. sha256ok_hash
                else
                    local comp, exp = line:match("^SHA256FAIL|([a-f0-9]+)|([a-f0-9]+)$")
                    if comp then
                        logs[#logs + 1] = tr("SHA256 verification failed, upgrade cancelled")
                        logs[#logs + 1] = "  " .. tr("Expected:") .. " " .. exp
                        logs[#logs + 1] = "  " .. tr("Got:") .. " " .. comp
                    else
                        local err_line = line:match("^ERR|(.+)$")
                        if err_line and trim(err_line) ~= "" then
                            logs[#logs + 1] = err_line
                        end
                    end
                end
            end
        end
    end

    local validation = nil
    if done and download_ok and fw_target_path ~= "" and fs.access(fw_target_path) then
        logs[#logs + 1] = tr("Verifying firmware image format...")
        validation = validate_downloaded_firmware(fw_target_path, fw_sha256)
        if validation.valid then
            logs[#logs + 1] = tr("Firmware image validation passed")
        else
            logs[#logs + 1] = tr("Image check failed:") .. " " .. (validation.message ~= "" and validation.message or tr("The uploaded image file does not contain a supported format."))
        end
    end

    json_resp({
        ok = true,
        done = done,
        download_ok = download_ok,
        progress_pct = progress_pct,
        downloaded_size = downloaded_size,
        total_size = total_size,
        fw_name = fw_name,
        validation = validation,
        logs = logs,
        next_offset = total_lines
    })
end

function action_cancel_upgrade()
    kill_active_download()
    local fw_name = trim(http.formvalue("fw_name"))
    if fw_name ~= "" and fw_name:match("^[%w%._%-]+$") then
        fs.unlink("/tmp/ghfu_" .. fw_name)
    else
        sys.call("rm -f /tmp/ghfu_* 2>/dev/null")
    end
    fs.unlink(VALIDATE_CACHE_FILE)
    fs.unlink(PROGRESS_LOG_FILE)
    fs.unlink(RAW_LOG_FILE)
    json_resp({
        ok = true,
        msg = tr("Upgrade cancelled, temporary firmware file removed")
    })
end

local function save_installed_packages_before_upgrade()
    if (fs.access("/bin/opkg") or fs.access("/usr/bin/opkg")) and fs.access("/etc/profile.d/opkg.sh") then
        sys.call("sh -c '. /etc/profile.d/opkg.sh && opkg save' >/dev/null 2>&1")
    elseif fs.access("/etc/apk/world") then
        local rom_set = {}
        for _, pkg in ipairs(read_lines("/rom/etc/apk/world")) do
            local p = trim(pkg):gsub("[=<>~].*$", "")
            if p ~= "" then rom_set[p] = true end
        end
        local added = {}
        for _, pkg in ipairs(read_lines("/etc/apk/world")) do
            local p = trim(pkg):gsub("[=<>~].*$", "")
            if p ~= "" and not rom_set[p] then
                added[#added + 1] = p
            end
        end
        if #added > 0 then
            write_file("/etc/config/.ghfu_apk_world", table.concat(added, "\n") .. "\n")
        else
            fs.unlink("/etc/config/.ghfu_apk_world")
        end
    end
    fs.unlink("/etc/opkg-restore-auto")
end

function action_upgrade()
    local keep_config = to_bool(http.formvalue("keep_config")) and "1" or "0"
    local retain_packages = to_bool(http.formvalue("retain_packages")) and "1" or "0"
    local force_upgrade = to_bool(http.formvalue("force"))
    local selected_release = trim(http.formvalue("selected_release"))
    local fw_name = trim(http.formvalue("fw_name"))
    local logs = {}

    if fw_name == "" or not fw_name:match("^[%w%._%-]+$") then
        json_resp({ ok = false, logs = { tr("Invalid firmware file name") } })
        return
    end

    local fw_path = "/tmp/ghfu_" .. fw_name
    if not fs.access(fw_path) then
        json_resp({ ok = false, logs = { tr("Firmware file not found, please download again") } })
        return
    end

    local val = validate_downloaded_firmware(fw_path)
    if not val.valid then
        if not force_upgrade then
            json_resp({
                ok = false,
                logs = { tr("Image check failed, confirmation of force upgrade is required") },
                need_force = true,
                validation = val
            })
            return
        end
        if not val.forceable then
            json_resp({
                ok = false,
                logs = { tr("Firmware image validation failed and force upgrade is disallowed by system") }
            })
            return
        end
    end

    if not val.allow_backup and keep_config == "1" then
        keep_config = "0"
        logs[#logs + 1] = tr("Firmware metadata does not allow keeping configuration, switched to -n")
    end
    if keep_config ~= "1" then
        retain_packages = "0"
    end

    set_cfg({
        selected_release = (selected_release ~= "" and selected_release or fw_name),
        keep_config = keep_config,
        retain_packages = retain_packages
    })
    fs.unlink(CHECK_CACHE_FILE)

    local flags = {}
    if force_upgrade then flags[#flags + 1] = "--force" end
    if keep_config ~= "1" then flags[#flags + 1] = "-n" end
    if retain_packages == "1" then
        flags[#flags + 1] = "-k"
        save_installed_packages_before_upgrade()
    end

    local flag_str = table.concat(flags, " ")
    local up_cmd = "/sbin/sysupgrade " .. (flag_str ~= "" and (flag_str .. " ") or "") .. util.shellquote(fw_path)

    logs[#logs + 1] = tr("Starting system upgrade")
    if force_upgrade then logs[#logs + 1] = tr("Force upgrade enabled (--force)") end
    logs[#logs + 1] = (keep_config == "1") and tr("Upgrade mode: keep configuration") or tr("Upgrade mode: do not keep configuration")
    if retain_packages == "1" then
        logs[#logs + 1] = tr("Package mode: retain installed packages (-k)")
    end

    sys.call("sh -c " .. util.shellquote(string.format("(sleep 2; %s) </dev/null >/tmp/ghfu-upgrade.log 2>&1 &", up_cmd)))

    json_resp({
        ok = true,
        logs = logs,
        rebooting = true
    })
end

function action_backup()
    local tmp = "/tmp/ghfu-backup.tar.gz"
    fs.unlink(tmp)
    local rc = tonumber(trim(sys.exec("/sbin/sysupgrade --create-backup " .. util.shellquote(tmp) .. " >/dev/null 2>&1; printf '%d' $?"))) or 1
    if rc ~= 0 or not fs.access(tmp) then
        http.status(500, "Internal Server Error")
        http.prepare_content("text/plain; charset=utf-8")
        http.write(tr("Backup failed"))
        return
    end
    local st = fs.stat(tmp)
    local hostname = read_first_line("/proc/sys/kernel/hostname")
    hostname = (hostname ~= "" and hostname or "OpenWrt"):gsub("[^%w%._%-]", "_")
    local fname = "backup-" .. hostname .. "-" .. os.date("%Y-%m-%d") .. ".tar.gz"

    http.header("Content-Disposition", 'attachment; filename="' .. fname .. '"')
    if st and st.size then
        http.header("Content-Length", tostring(st.size))
    end
    http.prepare_content("application/octet-stream")

    local f = io.open(tmp, "rb")
    if f then
        while true do
            local chunk = f:read(65536)
            if not chunk then break end
            http.write(chunk)
        end
        f:close()
    end
    fs.unlink(tmp)
end
