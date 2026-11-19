-- SPDX-License-Identifier: GPL-3.0-only
-- Copyright (C) 2026 smallprogram & Kiddin'
-- Adapted exclusively for https://dl.openwrt.ai/firmware with built-in firmware filtering, auto-selection & flash.js validation

module("luci.controller.ghfu", package.seeall)

local http = require "luci.http"
local jsonc = require "luci.jsonc"
local i18n = require "luci.i18n"
local uci = require("luci.model.uci").cursor()
local fs = require "nixio.fs"
local sys = require "luci.sys"
local util = require "luci.util"

local CFG = "ghfu"
local SEC = "main"
local tr = i18n.translate

local FIRMWARE_BASE_URL = "https://dl.openwrt.ai/firmware"
local DEFAULT_FETCH_TIMEOUT = 15
local BUILTIN_VALID_EXTS = {
    ".img.gz", ".img", ".bin", ".tar.gz", ".tar", ".itb", ".trx", ".chk", ".dlf", ".ari"
}

local function json_resp(tbl)
    http.prepare_content("application/json")
    http.write_json(tbl)
end

local function to_bool(v)
    return v == "1" or v == "true" or v == "on" or v == "yes"
end

local function trim(s)
    if not s then
        return ""
    end
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function read_lines(path)
    local f = io.open(path, "r")
    if not f then
        return {}
    end
    local lines = {}
    for line in f:lines() do
        lines[#lines + 1] = line
    end
    f:close()
    return lines
end

local function read_all(path)
    local f = io.open(path, "r")
    if not f then
        return ""
    end
    local content = f:read("*a") or ""
    f:close()
    return content
end

local function read_first_line(path)
    local f = io.open(path, "r")
    if not f then
        return ""
    end
    local line = f:read("*l") or ""
    f:close()
    return trim(line)
end

local function human_bytes(n)
    n = tonumber(n) or 0
    if n < 0 then
        n = 0
    end
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

local function parse_size_str(s)
    s = trim(s or "")
    if s == "" or s == "-" then
        return 0
    end
    local num_only = tonumber(s)
    if num_only then
        return math.floor(num_only)
    end
    local val, unit = s:match("([%d%.]+)%s*([%a]+)")
    if not val then
        return 0
    end
    local n = tonumber(val) or 0
    unit = (unit or ""):upper()
    if unit == "K" or unit == "KB" or unit == "KIB" then
        n = n * 1024
    elseif unit == "M" or unit == "MB" or unit == "MIB" then
        n = n * 1024 * 1024
    elseif unit == "G" or unit == "GB" or unit == "GIB" then
        n = n * 1024 * 1024 * 1024
    elseif unit == "T" or unit == "TB" or unit == "TIB" then
        n = n * 1024 * 1024 * 1024 * 1024
    end
    return math.floor(n + 0.5)
end

local MONTHS = {
    jan = 1, feb = 2, mar = 3, apr = 4, may = 5, jun = 6,
    jul = 7, aug = 8, sep = 9, oct = 10, nov = 11, dec = 12
}

local function parse_version_token(ver_str)
    ver_str = trim(ver_str or "")
    if ver_str == "" then
        return "", 0, "", ""
    end
    local mm, dd, yyyy = ver_str:match("(%d%d)%.(%d%d)%.(%d%d%d%d)")
    if mm and dd and yyyy then
        local m, d, y = tonumber(mm), tonumber(dd), tonumber(yyyy)
        local num_str = string.format("%04d%02d%02d", y, m, d)
        local iso = string.format("%04d-%02d-%02dT00:00:00Z", y, m, d)
        local epoch = os.time({ year = y, month = m, day = d, hour = 0, min = 0, sec = 0 }) or 0
        return string.format("%02d.%02d.%04d", m, d, y), epoch, num_str, iso
    end
    local yyyy2, mm2, dd2 = ver_str:match("(%d%d%d%d)[%.%-](%d%d)[%.%-](%d%d)")
    if yyyy2 and mm2 and dd2 then
        local y, m, d = tonumber(yyyy2), tonumber(mm2), tonumber(dd2)
        local num_str = string.format("%04d%02d%02d", y, m, d)
        local iso = string.format("%04d-%02d-%02dT00:00:00Z", y, m, d)
        local epoch = os.time({ year = y, month = m, day = d, hour = 0, min = 0, sec = 0 }) or 0
        return string.format("%02d.%02d.%04d", m, d, y), epoch, num_str, iso
    end
    local yyyy3, mm3, dd3 = ver_str:match("(20%d%d)(%d%d)(%d%d)")
    if yyyy3 and mm3 and dd3 then
        local y, m, d = tonumber(yyyy3), tonumber(mm3), tonumber(dd3)
        if m >= 1 and m <= 12 and d >= 1 and d <= 31 then
            local num_str = string.format("%04d%02d%02d", y, m, d)
            local iso = string.format("%04d-%02d-%02dT00:00:00Z", y, m, d)
            local epoch = os.time({ year = y, month = m, day = d, hour = 0, min = 0, sec = 0 }) or 0
            return string.format("%02d.%02d.%04d", m, d, y), epoch, num_str, iso
        end
    end
    return "", 0, "", ""
end

local function normalize_date_str(date_str, filename)
    date_str = trim(date_str or "")

    local y, m, d, hh, mm, ss = date_str:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)[T%s]+(%d%d):(%d%d):?(%d*)")
    if y and m and d then
        ss = (ss and ss ~= "") and ss or "00"
        return string.format("%04d-%02d-%02dT%02d:%02d:%02dZ", tonumber(y), tonumber(m), tonumber(d), tonumber(hh), tonumber(mm), tonumber(ss))
    end

    local y2, mon2, d2, hh2, mm2 = date_str:match("^(%d%d%d%d)%-(%a+)%-(%d%d)%s+(%d%d):(%d%d)")
    if y2 and mon2 and d2 then
        local m_num = MONTHS[mon2:lower():sub(1, 3)]
        if m_num then
            return string.format("%04d-%02d-%02dT%02d:%02d:00Z", tonumber(y2), m_num, tonumber(d2), tonumber(hh2), tonumber(mm2))
        end
    end

    local d3, mon3, y3, hh3, mm3 = date_str:match("^(%d%d)%-(%a+)%-(%d%d%d%d)%s+(%d%d):(%d%d)")
    if d3 and mon3 and y3 then
        local m_num = MONTHS[mon3:lower():sub(1, 3)]
        if m_num then
            return string.format("%04d-%02d-%02dT%02d:%02d:00Z", tonumber(y3), m_num, tonumber(d3), tonumber(hh3), tonumber(mm3))
        end
    end

    local d4, mon4, y4, hh4, mm4, ss4 = date_str:match("(%d+)%s+(%a+)%s+(%d%d%d%d)%s+(%d%d):(%d%d):?(%d*)")
    if d4 and mon4 and y4 then
        local m_num = MONTHS[mon4:lower():sub(1, 3)]
        if m_num then
            ss4 = (ss4 and ss4 ~= "") and ss4 or "00"
            return string.format("%04d-%02d-%02dT%02d:%02d:%02dZ", tonumber(y4), m_num, tonumber(d4), tonumber(hh4), tonumber(mm4), tonumber(ss4))
        end
    end

    local _, _, _, iso_from_fn = parse_version_token(filename or "")
    return iso_from_fn or ""
end

local function get_system_version()
    local ver = read_first_line("/etc/openwrt_version")
    if ver ~= "" then
        return ver
    end
    local rel_lines = read_lines("/etc/openwrt_release")
    for _, line in ipairs(rel_lines) do
        local k, v = line:match("^([%w_]+)=['\"]?(.-)['\"]?$")
        if k == "DISTRIB_REVISION" and trim(v) ~= "" then
            return trim(v)
        end
    end
    return ""
end

local function get_install_epoch()
    local f = io.open("/etc/ghfu_flash_epoch", "r")
    if f then
        local v = f:read("*l")
        f:close()
        local epoch = tonumber(v)
        if epoch and epoch > 0 then
            return epoch
        end
    end
    local st = fs.stat("/etc/openwrt_version") or fs.stat("/etc/openwrt_release")
    if st and st.mtime then
        return tonumber(st.mtime) or 0
    end
    return 0
end

local function epoch_to_iso_utc(epoch)
    if not epoch or epoch <= 0 then
        return ""
    end
    return os.date("!%Y-%m-%dT%H:%M:%SZ", epoch)
end

local function epoch_to_local_string(epoch)
    if not epoch or epoch <= 0 then
        return ""
    end
    return os.date("%Y-%m-%d %H:%M:%S", epoch)
end

local function get_tz_offset_minutes()
    local z = os.date("%z") or "+0000"
    local sign, hh, mm = z:match("([%+%-])(%d%d)(%d%d)")
    if not sign then
        return 0
    end
    local v = (tonumber(hh) or 0) * 60 + (tonumber(mm) or 0)
    if sign == "-" then
        v = -v
    end
    return v
end

-- Comprehensive partition table ("gpt" vs "dos") and UEFI boot detection (via blkid + /sys/firmware/efi)
local function detect_boot_and_part_type()
    local is_efi = fs.access("/sys/firmware/efi") and true or false
    local part_type = ""
    local pttype = trim(sys.exec("blkid -s PTTYPE -o value /dev/sda /dev/vda /dev/nvme0n1 /dev/mmcblk0 2>/dev/null | head -n1"):lower())
    if pttype == "gpt" then
        part_type = "gpt"
        is_efi = true
    elseif pttype == "dos" then
        part_type = "dos"
    else
        part_type = is_efi and "gpt" or "dos"
    end
    return is_efi, part_type
end

local function detect_device_info()
    local target = ""
    local distrib_id = ""
    local distrib_rev = ""
    local distrib_desc = ""

    local rel_lines = read_lines("/etc/openwrt_release")
    for _, line in ipairs(rel_lines) do
        local k, v = line:match("^([%w_]+)=['\"]?(.-)['\"]?$")
        if k == "DISTRIB_TARGET" then
            target = trim(v)
        elseif k == "DISTRIB_ID" then
            distrib_id = trim(v)
        elseif k == "DISTRIB_REVISION" then
            distrib_rev = trim(v)
        elseif k == "DISTRIB_DESCRIPTION" then
            distrib_desc = trim(v)
        end
    end

    local board_name = read_first_line("/tmp/sysinfo/board_name")
    local model = read_first_line("/tmp/sysinfo/model")
    local arch = nixio.uname and nixio.uname().machine or ""

    local board_json_raw = read_all("/etc/board.json")
    if board_json_raw ~= "" then
        local bj = jsonc.parse(board_json_raw)
        if bj and type(bj.model) == "table" then
            if board_name == "" and bj.model.id then
                board_name = trim(tostring(bj.model.id))
            end
            if model == "" and bj.model.name then
                model = trim(tostring(bj.model.name))
            end
        end
    end

    local ubus_board = util.ubus and util.ubus("system", "board") or nil
    if not ubus_board then
        local ubus_out = sys.exec("ubus call system board 2>/dev/null")
        if ubus_out and ubus_out ~= "" then
            ubus_board = jsonc.parse(ubus_out)
        end
    end

    if ubus_board then
        if ubus_board.release then
            if target == "" and ubus_board.release.target then
                target = trim(tostring(ubus_board.release.target))
            end
            if distrib_id == "" and ubus_board.release.distribution then
                distrib_id = trim(tostring(ubus_board.release.distribution))
            end
        end
        if board_name == "" and ubus_board.board_name then
            board_name = trim(tostring(ubus_board.board_name))
        end
        if model == "" and ubus_board.model then
            model = trim(tostring(ubus_board.model))
        end
    end

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

    local candidates = {}
    local seen = {}
    local function add_candidate(p)
        p = trim(p or ""):gsub("^/+", ""):gsub("/+$", "")
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

    if target_dash ~= "" then
        add_candidate(target_dash)
    end

    if target_under ~= "" then
        add_candidate(target_under)
    end

    local is_efi, part_type = detect_boot_and_part_type()
    local sys_ver = get_system_version()

    return {
        target = target,
        target_dir = (arch == "x86_64" or target == "x86/64") and "x86_64" or target_dash,
        board_name = board_name,
        board_dir = board_norm,
        model = model,
        arch = arch,
        is_efi = is_efi,
        part_type = part_type,
        system_version = sys_ver,
        distrib_id = distrib_id,
        distrib_rev = distrib_rev,
        distrib_desc = distrib_desc,
        is_kwrt = (distrib_id == "Kwrt" or distrib_id == "1536"),
        candidates = candidates
    }
end

local function is_valid_firmware_file(name)
    if not name or name == "" then
        return false
    end
    local lower = name:lower()

    if lower == "parent directory" or lower == "parent directory/" or lower == "../" or lower == "./" or lower:match("/$") then
        return false
    end

    if lower:find("preloader", 1, true)
        or lower:find("uboot", 1, true)
        or lower:find("u-boot", 1, true)
        or lower:find("gpt.bin", 1, true)
        or lower:find("bl2.bin", 1, true)
        or lower:find("bl31", 1, true)
        or lower:find("fip.bin", 1, true)
        or lower:find("-kernel.bin", 1, true)
        or lower:find("_kernel.bin", 1, true)
        or lower:find("initramfs", 1, true)
        or lower:find("-rootfs", 1, true)
        or lower:find("-factory", 1, true)
        or lower:find("-recovery", 1, true)
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

local function score_firmware_preference(name, dev_info)
    local lower = tostring(name or ""):lower()
    local score = 0
    local is_efi = dev_info and dev_info.is_efi
    local is_x86 = dev_info and (dev_info.target_dir == "x86_64" or dev_info.target == "x86/64" or dev_info.arch == "x86_64" or dev_info.board_dir == "x86_generic")
    local target_str = tostring(dev_info and dev_info.target or ""):lower()
    local board_str = tostring(dev_info and dev_info.board_dir or ""):lower()

    if lower:find("squashfs", 1, true) then
        score = score + 20
    end

    if is_x86 then
        if is_efi then
            if lower:find("combined-efi", 1, true) then
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
        if lower:find("squashfs.trx", 1, true) then
            score = score + 100
        end
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
    if not uci:get(CFG, SEC) then
        uci:section(CFG, "ghfu", SEC, {})
    end

    local changed = false
    if uci:get(CFG, SEC, "keep_config") == nil then
        uci:set(CFG, SEC, "keep_config", "1")
        changed = true
    end
    if uci:get(CFG, SEC, "retain_packages") == nil then
        uci:set(CFG, SEC, "retain_packages", "0")
        changed = true
    end

    for _, old_key in ipairs({
        "github_repo", "firmware_url", "device_path", "fetch_timeout",
        "filter_ext_enabled", "valid_extensions",
        "filter_prefix_enabled", "filter_prefix",
        "filter_min_size_enabled", "filter_min_size"
    }) do
        if uci:get(CFG, SEC, old_key) ~= nil then
            uci:delete(CFG, SEC, old_key)
            changed = true
        end
    end

    if changed then
        uci:commit(CFG)
    end
end

local function get_cfg()
    ensure_cfg_defaults()
    return {
        selected_release = uci:get(CFG, SEC, "selected_release") or "",
        keep_config = uci:get(CFG, SEC, "keep_config") or "1",
        retain_packages = uci:get(CFG, SEC, "retain_packages") or "0"
    }
end

local function set_cfg(opts)
    if not opts then return end
    ensure_cfg_defaults()

    if opts.selected_release ~= nil then
        uci:set(CFG, SEC, "selected_release", opts.selected_release)
    end
    if opts.keep_config ~= nil then
        uci:set(CFG, SEC, "keep_config", to_bool(opts.keep_config) and "1" or "0")
    end
    if opts.retain_packages ~= nil then
        uci:set(CFG, SEC, "retain_packages", to_bool(opts.retain_packages) and "1" or "0")
    end

    uci:commit(CFG)
end

local function normalize_version(v)
    v = trim(v or "")
    if v == "" then
        return ""
    end
    v = v:gsub("^luci%-app%-ghfu[-%s]+", "")
    local token = v:match("([0-9][%w%.%+%-%_~]*)")
    return token or ""
end

local function read_apk_db_version(path)
    local f = io.open(path, "r")
    if not f then
        return ""
    end
    local found = false
    for line in f:lines() do
        if line == "P:luci-app-ghfu" then
            found = true
        elseif found and line:match("^V:") then
            f:close()
            return normalize_version(line:sub(3))
        elseif found and line == "" then
            found = false
        end
    end
    f:close()
    return ""
end

local function get_app_version()
    local apk_db_ver = read_apk_db_version("/lib/apk/db/installed")
    if apk_db_ver ~= "" then return apk_db_ver end
    apk_db_ver = read_apk_db_version("/usr/lib/apk/db/installed")
    if apk_db_ver ~= "" then return apk_db_ver end

    local opkg_ctrl_ver = normalize_version(sys.exec("sh -c \"awk -F': ' '/^Version:/{print $2; exit}' /usr/lib/opkg/info/luci-app-ghfu.control 2>/dev/null\""))
    if opkg_ctrl_ver ~= "" then return opkg_ctrl_ver end

    local opkg_status_ver = normalize_version(sys.exec("sh -c \"awk 'BEGIN{f=0} /^Package: luci-app-ghfu$/{f=1;next} f&&/^Version:/{sub(/^Version: /,\"\"); print; exit} f&&/^$/{f=0}' /usr/lib/opkg/status 2>/dev/null\""))
    if opkg_status_ver ~= "" then return opkg_status_ver end

    local verfile = normalize_version(read_first_line("/usr/share/ghfu/version"))
    if verfile ~= "" then return verfile end

    return ""
end

local function http_get(url, timeout, custom_header)
    local t = math.floor(tonumber(timeout) or DEFAULT_FETCH_TIMEOUT)
    if t < 3 then t = 3 end
    if t > 300 then t = 300 end

    local raw = ""
    if custom_header and custom_header ~= "" then
        raw = sys.exec("curl -skfL --connect-timeout 4 -m " .. tostring(t) .. " -H " .. util.shellquote(custom_header) .. " " .. util.shellquote(url) .. " 2>/dev/null")
    else
        raw = sys.exec("curl -skfL --connect-timeout 4 -m " .. tostring(t) .. " " .. util.shellquote(url) .. " 2>/dev/null")
    end

    if not raw or raw == "" then
        if custom_header and custom_header ~= "" then
            raw = sys.exec("wget -T " .. tostring(t) .. " --header=" .. util.shellquote(custom_header) .. " -qO- " .. util.shellquote(url) .. " 2>/dev/null")
        end
        if not raw or raw == "" then
            raw = sys.exec("wget -T " .. tostring(t) .. " -qO- " .. util.shellquote(url) .. " 2>/dev/null")
        end
    end

    return raw or ""
end

local function parse_sha256sums(raw)
    local map = {}
    if not raw or raw == "" then
        return map
    end
    for line in raw:gmatch("[^\r\n]+") do
        local hash, fname = line:match("^([a-fA-F0-9]+)%s+%*?(.+)$")
        if hash and fname and #hash == 64 then
            fname = trim(fname):gsub("^%./", "")
            local base = fname:match("([^/]+)$") or fname
            map[fname] = hash:lower()
            map[base] = hash:lower()
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
    if not obj or type(obj) ~= "table" then
        return nil
    end

    local items = {}
    if #obj > 0 or next(obj) == nil then
        for _, entry in ipairs(obj) do
            if type(entry) == "table" and entry.type ~= "directory" and entry.name then
                local fname = tostring(entry.name)
                if is_valid_firmware_file(fname) then
                    local fsize = tonumber(entry.size) or parse_size_str(tostring(entry.size or "0"))
                    local fdate = normalize_date_str(tostring(entry.mtime or entry.date or entry.published_at or ""), fname)
                    local fsha = tostring(entry.sha256 or ""):lower()
                    if fsha == "" and sha256_map then
                        fsha = sha256_map[fname] or ""
                    end
                    local furl = entry.url or (dir_url:gsub("/+$", "") .. "/" .. fname)
                    items[#items + 1] = {
                        name = fname,
                        url = furl,
                        size = fsize,
                        sha256 = fsha,
                        date_iso = fdate
                    }
                end
            end
        end
        if #items > 0 then
            return items
        end
    end

    local asset_list = obj.files or obj.assets or obj.images
    if type(asset_list) == "table" then
        for _, entry in pairs(asset_list) do
            if type(entry) == "table" and entry.name then
                local fname = tostring(entry.name)
                if is_valid_firmware_file(fname) then
                    local fsize = tonumber(entry.size) or parse_size_str(tostring(entry.size or "0"))
                    local fdate = normalize_date_str(tostring(entry.mtime or entry.date or entry.published_at or obj.build_at or ""), fname)
                    local fsha = tostring(entry.sha256 or ""):lower()
                    if fsha == "" and sha256_map then
                        fsha = sha256_map[fname] or ""
                    end
                    local furl = entry.url or (dir_url:gsub("/+$", "") .. "/" .. fname)
                    items[#items + 1] = {
                        name = fname,
                        url = furl,
                        size = fsize,
                        sha256 = fsha,
                        date_iso = fdate
                    }
                end
            end
        end
        if #items > 0 then
            return items
        end
    end

    return nil
end

local function parse_directory_html(html, dir_url, sha256_map)
    if not html or html == "" then
        return nil
    end

    local base_url = dir_url:gsub("/+$", "")
    local items = {}
    local seen = {}

    local function add_item(href, size_str, date_str)
        href = trim(href or "")
        if href == "" or href:match("^%?") or href:match("^#") or href:match("^javascript:") then
            return
        end
        local clean_href = href:gsub("%?.*$", "")
        if clean_href == "../" or clean_href == "./" or clean_href == "/" or clean_href:match("/$") then
            return
        end

        local fname = clean_href:match("([^/]+)$")
        if not fname then
            return
        end
        fname = url_decode(fname)
        if not is_valid_firmware_file(fname) or seen[fname] then
            return
        end

        local full_url
        if href:match("^https?://") then
            full_url = href
        elseif href:match("^/") then
            local origin = base_url:match("^(https?://[^/]+)") or ""
            full_url = origin .. clean_href
        else
            full_url = base_url .. "/" .. clean_href
        end

        local fsize = parse_size_str(size_str)
        local fdate = normalize_date_str(date_str, fname)
        local fsha = (sha256_map and sha256_map[fname]) or ""

        seen[fname] = true
        items[#items + 1] = {
            name = fname,
            url = full_url,
            size = fsize,
            sha256 = fsha,
            date_iso = fdate
        }
    end

    for tr_block in html:gmatch("<tr[^>]*>(.-)</tr>") do
        local href = tr_block:match('<a[^>]+href=["\']([^"\']+)["\']')
        if href then
            local cells = {}
            for td in tr_block:gmatch("<td[^>]*>(.-)</td>") do
                local text = td:gsub("<[^>]+>", " ")
                text = text:gsub("&nbsp;", " "):gsub("&#160;", " ")
                text = trim(text:gsub("%s+", " "))
                cells[#cells + 1] = text
            end
            local size_str = ""
            local date_str = ""
            for _, c in ipairs(cells) do
                if size_str == "" and (c:match("^%d+%.?%d*%s*[KMGTkmgt][iI]?[bB]?$") or c:match("^%d+%s*[bB]$")) then
                    size_str = c
                elseif date_str == "" and (c:match("%d%d%d%d%-%a+%-%d%d") or c:match("%d%d%-%a+%-%d%d%d%d") or c:match("%d%d%d%d%-%d%d%-%d%d")) then
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
                    or ""
                local size_str = rest:match("%s+(%d+%.?%d*%s*[KMGTkmgt]?[iI]?[bB]?)%s*$")
                    or rest:match("%s+(%d+)%s*$")
                    or ""
                add_item(href, size_str, date_str)
            end
        end
    end

    if #items == 0 then
        return nil
    end

    return items
end

local function build_release_from_items(items, dir_url, resolved_subpath, dev_info)
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
    local latest_ver = (newest and newest.version_tag ~= "") and newest.version_tag or ""
    local latest_ver_num = (newest and newest.version_num ~= "") and newest.version_num or ""
    local latest_epoch = (newest and newest.version_epoch) or 0

    local latest_date = ""
    for _, item in ipairs(items) do
        if latest_ver_num == "" or item.version_num == latest_ver_num then
            if item.date_iso and item.date_iso ~= "" then
                if latest_date == "" or item.date_iso > latest_date then
                    latest_date = item.date_iso
                end
            end
        end
    end

    local is_formal = true
    if latest_epoch > 0 then
        is_formal = ((os.time() or 0) - 172800) > latest_epoch
    end

    local assets = {}
    for _, item in ipairs(items) do
        local is_latest_item = false
        if latest_ver_num ~= "" and item.version_num ~= "" then
            is_latest_item = (item.version_num == latest_ver_num)
        elseif latest_ver ~= "" and item.version_tag ~= "" then
            is_latest_item = (item.version_tag == latest_ver)
        elseif latest_date ~= "" and item.date_iso ~= "" then
            is_latest_item = (item.date_iso:sub(1, 10) == latest_date:sub(1, 10))
        else
            is_latest_item = (item == newest)
        end

        -- Compare each firmware's version against current running system version: "newer", "same", or "older"
        local relation = "older"
        if item.version_num ~= "" and sys_ver_num ~= "" and item.version_num:match("^%d+$") and sys_ver_num:match("^%d+$") then
            if item.version_num > sys_ver_num then
                relation = "newer"
            elseif item.version_num == sys_ver_num then
                relation = "same"
            else
                relation = "older"
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

    local raw = http_get(dir_url .. "/", timeout, "Accept: application/json, text/html;q=0.9")
    if not raw or trim(raw) == "" then
        return nil
    end

    local sha256_map = {}
    if raw:lower():find("sha256sums", 1, true) then
        local sha_raw = http_get(dir_url .. "/sha256sums", math.min(timeout, 5))
        sha256_map = parse_sha256sums(sha_raw)
    end

    local items = nil
    local trimmed = trim(raw)
    if trimmed:sub(1, 1) == "{" or trimmed:sub(1, 1) == "[" then
        items = parse_directory_json(trimmed, dir_url, sha256_map)
    else
        items = parse_directory_html(raw, dir_url, sha256_map)
    end

    if not items or #items == 0 then
        return nil
    end

    return build_release_from_items(items, dir_url, subpath_label, dev_info)
end

local function fetch_dl_openwrt_firmware(dev_info, timeout)
    local base_url = FIRMWARE_BASE_URL
    local tried = {}
    local candidate_paths = {}

    local function add_path(p)
        p = trim(p or ""):gsub("^/+", ""):gsub("/+$", "")
        if p ~= "" and not tried[p] then
            tried[p] = true
            candidate_paths[#candidate_paths + 1] = p
        end
    end

    if dev_info and dev_info.candidates then
        for _, c in ipairs(dev_info.candidates) do
            add_path(c)
        end
    end

    for _, subpath in ipairs(candidate_paths) do
        local target_url = base_url .. "/" .. subpath
        local rel = try_fetch_firmware_dir(target_url, timeout, subpath, dev_info)
        if rel and #rel.assets > 0 then
            return rel, nil, { resolved_path = subpath }
        end
    end

    if dev_info and dev_info.target_dir and dev_info.target_dir ~= "" and dev_info.board_dir ~= "" then
        local target_index_url = base_url .. "/" .. dev_info.target_dir .. "/"
        local target_html = http_get(target_index_url, timeout)
        if target_html and target_html ~= "" then
            local subdirs = {}
            for href in target_html:gmatch('<a[^>]+href=["\']([^"\']+/)["\']') do
                local dname = href:gsub("/+$", ""):match("([^/]+)$")
                if dname and dname ~= ".." and dname ~= "." and not dname:match("^%?") then
                    subdirs[#subdirs + 1] = url_decode(dname)
                end
            end

            local b_full = dev_info.board_dir:lower()
            local b_short = (dev_info.board_name:match(",(.+)$") or dev_info.board_dir):lower()
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
                    if dl:find(b_full, 1, true) or b_full:find(dl, 1, true) or (b_short ~= "" and dl:find(b_short, 1, true)) then
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

    local hint_path = (dev_info and dev_info.candidates and dev_info.candidates[1]) or ""
    return nil, tr("Failed to fetch firmware list from server") .. (hint_path ~= "" and (" (" .. base_url .. "/" .. hint_path .. ")") or "")
end

local function evaluate_update_status(latest, dev_info, install_epoch)
    local sys_ver = (dev_info and dev_info.system_version) or get_system_version()
    local _, sys_ver_epoch, sys_ver_num = parse_version_token(sys_ver)
    local _, rem_ver_epoch, rem_ver_num = parse_version_token(latest.release_name or latest.tag_name or "")

    local has_new = false
    if rem_ver_num ~= "" and sys_ver_num ~= "" and rem_ver_num:match("^%d+$") and sys_ver_num:match("^%d+$") then
        has_new = (rem_ver_num > sys_ver_num)
    elseif rem_ver_epoch > 0 and sys_ver_epoch > 0 then
        has_new = (rem_ver_epoch > sys_ver_epoch)
    else
        local install_iso = epoch_to_iso_utc(install_epoch)
        if latest.published_at ~= "" and install_iso ~= "" then
            has_new = (latest.published_at > install_iso)
        end
    end

    return has_new
end

-- Validate downloaded firmware image via OpenWrt ubus system.validate_firmware_image / /usr/libexec/validate_firmware_image / sysupgrade -T
-- Caches result in /tmp/ghfu-validate.json so polling or upgrade requests do not repeatedly unpack/check the image
local function validate_downloaded_firmware(fw_path)
    local cache_file = "/tmp/ghfu-validate.json"
    local cached_raw = read_all(cache_file)
    if cached_raw ~= "" then
        local cached = jsonc.parse(cached_raw)
        if type(cached) == "table" and cached.fw_path == fw_path then
            return cached
        end
    end

    local res = nil
    if util.ubus then
        res = util.ubus("system", "validate_firmware_image", { path = fw_path })
    end

    if type(res) ~= "table" and fs.access("/usr/libexec/validate_firmware_image") then
        local raw = sys.exec("/usr/libexec/validate_firmware_image " .. util.shellquote(fw_path) .. " 2>/dev/null")
        if raw and raw ~= "" then
            res = jsonc.parse(raw)
        end
    end

    local test_out = trim(sys.exec("/sbin/sysupgrade -T " .. util.shellquote(fw_path) .. " 2>&1"))
    local test_rc = sys.call("/sbin/sysupgrade -T " .. util.shellquote(fw_path) .. " >/dev/null 2>&1")

    local valid = true
    local forceable = true
    local allow_backup = true
    local detail_msg = ""

    if type(res) == "table" then
        valid = (res.valid == true)
        forceable = (res.forceable ~= false)
        allow_backup = (res.allow_backup ~= false)
        if not valid then
            detail_msg = test_out
            if detail_msg == "" and type(res.tests) == "table" then
                local failed = {}
                for k, v in pairs(res.tests) do
                    if v == false then
                        failed[#failed + 1] = tostring(k) .. ": false"
                    end
                end
                detail_msg = table.concat(failed, "\n")
            end
        end
    else
        valid = (test_rc == 0)
        forceable = true
        allow_backup = true
        if not valid then
            detail_msg = test_out
        end
    end

    local st = fs.stat(fw_path)
    local fsize = (st and st.size) or 0
    local sha256 = trim(sys.exec("sha256sum " .. util.shellquote(fw_path) .. " 2>/dev/null | awk '{print $1}'"))

    local result = {
        fw_path = fw_path,
        valid = valid,
        forceable = forceable,
        allow_backup = allow_backup,
        message = detail_msg,
        size = fsize,
        sha256 = sha256
    }

    local wf = io.open(cache_file, "w")
    if wf then
        wf:write(jsonc.stringify(result))
        wf:close()
    end

    return result
end

function index()
    if not fs.access("/etc/config/ghfu") then
        return
    end

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
    luci.template.render("ghfu/main", {
        app_version = get_app_version()
    })
end

function action_local_status()
    local cfg = get_cfg()
    local app_version = get_app_version()
    local install_epoch = get_install_epoch()
    local install_local = epoch_to_local_string(install_epoch)
    local dev_info = detect_device_info()
    local uci_changes = uci:changes()
    local has_unsaved_uci = (uci_changes and next(uci_changes) ~= nil) and true or false

    json_resp({
        ok = true,
        app_version = app_version,
        config = cfg,
        device_info = dev_info,
        has_unsaved_uci = has_unsaved_uci,
        install_epoch = install_epoch,
        install_time = install_local,
        tz_offset_min = get_tz_offset_minutes()
    })
end

function action_sysversion_check()
    local dev_info = detect_device_info()
    local install_epoch = get_install_epoch()

    local latest = fetch_dl_openwrt_firmware(dev_info, 6)
    if not latest then
        json_resp({ code = 1 })
        return
    end

    local has_new = evaluate_update_status(latest, dev_info, install_epoch)
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
    local cfg = get_cfg()
    local app_version = get_app_version()
    local dev_info = detect_device_info()
    local uci_changes = uci:changes()
    local has_unsaved_uci = (uci_changes and next(uci_changes) ~= nil) and true or false

    local install_epoch = get_install_epoch()
    local install_local = epoch_to_local_string(install_epoch)

    local latest, err, rel_info = fetch_dl_openwrt_firmware(dev_info, DEFAULT_FETCH_TIMEOUT)
    if not latest then
        json_resp({
            ok = false,
            msg = err or tr("Unable to fetch firmware list, please check your network connection"),
            app_version = app_version,
            device_info = dev_info,
            has_unsaved_uci = has_unsaved_uci,
            config = cfg,
            install_epoch = install_epoch,
            install_time = install_local,
            tz_offset_min = get_tz_offset_minutes()
        })
        return
    end

    local updatelogs = trim(http_get(FIRMWARE_BASE_URL .. "/updatelogs.txt", 8))
    if updatelogs:match("^<!DOCTYPE") or updatelogs:match("^<html") then
        updatelogs = ""
    end

    latest.release_total_count = (latest.assets and #latest.assets) or 0
    latest.updatelogs = updatelogs

    local has_new = evaluate_update_status(latest, dev_info, install_epoch)
    local msg
    if has_new then
        msg = tr("New firmware is available")
    else
        msg = tr("No firmware newer than current system was found")
    end

    json_resp({
        ok = true,
        msg = msg,
        app_version = app_version,
        has_new = has_new,
        notice = latest.notice,
        resolved_path = (latest and latest.resolved_path) or (rel_info and rel_info.resolved_path) or "",
        device_info = dev_info,
        has_unsaved_uci = has_unsaved_uci,
        updatelogs = updatelogs,
        install_epoch = install_epoch,
        install_time = install_local,
        tz_offset_min = get_tz_offset_minutes(),
        config = cfg,
        latest = latest
    })
end

function action_config()
    local keep_config = http.formvalue("keep_config")
    local retain_packages = http.formvalue("retain_packages")

    set_cfg({
        keep_config = keep_config,
        retain_packages = retain_packages
    })

    json_resp({
        ok = true,
        config = get_cfg()
    })
end

function action_download()
    local selected_release = trim(http.formvalue("selected_release") or "")
    local keep_config = to_bool(http.formvalue("keep_config")) and "1" or "0"
    local retain_packages = to_bool(http.formvalue("retain_packages")) and "1" or "0"
    local asset_url = trim(http.formvalue("asset_url") or "")
    local asset_name = trim(http.formvalue("asset_name") or "firmware.bin.gz")
    local asset_size = tonumber(trim(http.formvalue("asset_size") or "")) or 0
    local asset_digest = trim(http.formvalue("asset_digest") or "")
    if not asset_digest:match("^[a-f0-9]+$") then
        asset_digest = ""
    end

    local logs = {}

    set_cfg({
        keep_config = keep_config,
        retain_packages = retain_packages
    })

    if selected_release == "" then
        logs[#logs + 1] = tr("Please select firmware to upgrade")
        json_resp({ ok = false, logs = logs })
        return
    end

    if asset_url == "" then
        logs[#logs + 1] = tr("Please select a firmware asset")
        json_resp({ ok = false, logs = logs })
        return
    end

    if not asset_url:match("^https://dl%.openwrt%.ai/firmware/") then
        logs[#logs + 1] = tr("Invalid firmware URL, only https://dl.openwrt.ai/firmware is supported")
        json_resp({ ok = false, logs = logs })
        return
    end

    local clean_name = asset_name:gsub("[^%w%._%-]", "_")
    if clean_name == "" then
        clean_name = "firmware.bin.gz"
    end

    -- Terminate any lingering download process and clean up previous temp files
    local old_pid = read_first_line("/tmp/ghfu-download.pid")
    if old_pid ~= "" and old_pid:match("^%d+$") then
        sys.call("kill -9 " .. old_pid .. " 2>/dev/null")
    end
    sys.call("rm -f /tmp/ghfu_* /tmp/ghfu-validate.json /tmp/ghfu-download.pid 2>/dev/null")

    local fw_path = "/tmp/ghfu_" .. clean_name
    local progress_log = "/tmp/ghfu-download-progress.log"
    local raw_log = "/tmp/ghfu-download-raw.log"
    local pid_file = "/tmp/ghfu-download.pid"
    local download_timeout = 180
    fs.unlink(progress_log)
    fs.unlink(raw_log)

    local shell_script = table.concat({
        "progress_log=", util.shellquote(progress_log), "\n",
        "raw_log=", util.shellquote(raw_log), "\n",
        "pid_file=", util.shellquote(pid_file), "\n",
        "target=", util.shellquote(fw_path), "\n",
        "total=", tostring(math.max(0, math.floor(asset_size))), "\n",
        "timeout=", tostring(download_timeout), "\n",
        "url=", util.shellquote(asset_url), "\n",
        ": > \"$progress_log\"\n",
        ": > \"$raw_log\"\n",
        "(\n",
        "if command -v wget >/dev/null 2>&1; then\n",
        "    wget -T \"$timeout\" -O \"$target\" \"$url\" >\"$raw_log\" 2>&1\n",
        "    rc=$?\n",
        "elif command -v curl >/dev/null 2>&1; then\n",
        "    curl -skfL --connect-timeout 15 -m \"$timeout\" -o \"$target\" \"$url\" >\"$raw_log\" 2>&1\n",
        "    rc=$?\n",
        "else\n",
        "    echo \"wget/curl is not installed\" >\"$raw_log\"\n",
        "    rc=127\n",
        "fi\n",
        "exit \"$rc\"\n",
        ") &\n",
        "dlpid=$!\n",
        "echo \"$dlpid\" > \"$pid_file\"\n",
        "prev_size=0\n",
        "prev_ts=$(date +%s)\n",
        "last_pct=-1\n",
        "while kill -0 \"$dlpid\" 2>/dev/null; do\n",
        "    sleep 1\n",
        "    size=$(wc -c < \"$target\" 2>/dev/null)\n",
        "    [ -z \"$size\" ] && size=0\n",
        "    now=$(date +%s)\n",
        "    elapsed=$((now - prev_ts))\n",
        "    [ \"$elapsed\" -le 0 ] && elapsed=1\n",
        "    delta=$((size - prev_size))\n",
        "    rate=$((delta / elapsed))\n",
        "    if [ \"$total\" -gt 0 ]; then\n",
        "        pct=$((size * 100 / total))\n",
        "        [ \"$pct\" -gt 100 ] && pct=100\n",
        "        if [ \"$pct\" -ne \"$last_pct\" ]; then\n",
        "            echo \"PROGRESS|$pct|$size|$total|$rate\" >> \"$progress_log\"\n",
        "            last_pct=$pct\n",
        "        fi\n",
        "    else\n",
        "        echo \"PROGRESS|0|$size|0|$rate\" >> \"$progress_log\"\n",
        "    fi\n",
        "    prev_size=$size\n",
        "    prev_ts=$now\n",
        "done\n",
        "wait \"$dlpid\"\n",
        "rc=$?\n",
        "rm -f \"$pid_file\"\n",
        "size=$(wc -c < \"$target\" 2>/dev/null)\n",
        "[ -z \"$size\" ] && size=0\n",
        "if [ \"$rc\" -eq 0 ] && [ -s \"$target\" ]; then\n",
        "    sha256=$(sha256sum \"$target\" 2>/dev/null | awk '{print $1}')\n",
        "    expected=", util.shellquote(asset_digest), "\n",
        "    if [ -n \"$expected\" ] && [ -n \"$sha256\" ]; then\n",
        "        if [ \"$sha256\" = \"$expected\" ]; then\n",
        "            echo \"SHA256OK|$sha256\" >> \"$progress_log\"\n",
        "            echo \"DONE|OK|$size|$total|$target\" >> \"$progress_log\"\n",
        "        else\n",
        "            echo \"SHA256FAIL|$sha256|$expected\" >> \"$progress_log\"\n",
        "            echo \"DONE|FAIL|$size|$total|$target\" >> \"$progress_log\"\n",
        "            rm -f \"$target\"\n",
        "        fi\n",
        "    else\n",
        "        echo \"DONE|OK|$size|$total|$target\" >> \"$progress_log\"\n",
        "    fi\n",
        "else\n",
        "    echo \"DONE|FAIL|$size|$total|$target\" >> \"$progress_log\"\n",
        "    if [ -s \"$raw_log\" ]; then\n",
        "        sed 's/^/ERR|/' \"$raw_log\" >> \"$progress_log\"\n",
        "    fi\n",
        "fi\n",
    })

    logs[#logs + 1] = tr("Downloading firmware:") .. " " .. clean_name
    local start_cmd = "sh -c " .. util.shellquote("(" .. shell_script .. ") </dev/null >/dev/null 2>&1 &")
    local rc = sys.call(start_cmd)
    if rc ~= 0 then
        logs[#logs + 1] = tr("Firmware download failed, please check network connection")
        json_resp({ ok = false, logs = logs })
        return
    end

    json_resp({
        ok = true,
        started = true,
        logs = logs
    })
end

function action_download_status()
    local offset = tonumber(trim(http.formvalue("offset") or "0")) or 0
    if offset < 0 then
        offset = 0
    end

    local progress_log = "/tmp/ghfu-download-progress.log"
    local lines = read_lines(progress_log)
    local total_lines = #lines

    local done = false
    local download_ok = false
    local sha256_fail = false
    local fw_name = ""
    local fw_target_path = ""

    for _, line in ipairs(lines) do
        local status, _, _, target = line:match("^DONE|([A-Z]+)|(%d+)|(%d+)|(.+)$")
        if status then
            done = true
            download_ok = (status == "OK")
            fw_target_path = trim(target or "")
            local n = tostring(target or ""):match("/tmp/ghfu_(.+)$")
            if n and n ~= "" then
                fw_name = n
            end
        end
        if line:match("^SHA256FAIL|") then
            sha256_fail = true
        end
    end

    if sha256_fail then
        download_ok = false
    end

    local logs = {}
    local start_idx = offset + 1
    if start_idx < 1 then start_idx = 1 end

    for i = start_idx, total_lines do
        local line = lines[i]
        local pct, size, total, rate = line:match("^PROGRESS|(%d+)|(%d+)|(%d+)|(%-?%d+)$")
        if pct then
            local speed_text = human_bytes(rate) .. "/s"
            if tonumber(total) and tonumber(total) > 0 then
                logs[#logs + 1] = tr("Download progress:") .. " " .. pct .. "% (" .. human_bytes(size) .. "/" .. human_bytes(total) .. "), " .. tr("Speed:") .. " " .. speed_text
            else
                logs[#logs + 1] = tr("Download progress:") .. " " .. human_bytes(size) .. ", " .. tr("Speed:") .. " " .. speed_text
            end
        else
            local status2, done_size, done_total, target2 = line:match("^DONE|([A-Z]+)|(%d+)|(%d+)|(.+)$")
            if status2 then
                if status2 == "OK" then
                    if tonumber(done_total) and tonumber(done_total) > 0 then
                        logs[#logs + 1] = tr("Download finished:") .. " " .. human_bytes(done_size) .. "/" .. human_bytes(done_total)
                    else
                        logs[#logs + 1] = tr("Download finished:") .. " " .. human_bytes(done_size)
                    end

                    local name2 = tostring(target2 or ""):match("/tmp/ghfu_(.+)$")
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
        validation = validate_downloaded_firmware(fw_target_path)
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
        fw_name = fw_name,
        validation = validation,
        logs = logs,
        next_offset = total_lines
    })
end

function action_cancel_upgrade()
    local old_pid = read_first_line("/tmp/ghfu-download.pid")
    if old_pid ~= "" and old_pid:match("^%d+$") then
        sys.call("kill -9 " .. old_pid .. " 2>/dev/null")
    end
    local fw_name = trim(http.formvalue("fw_name") or "")
    if fw_name ~= "" and fw_name:match("^[%w%._%-]+$") then
        fs.unlink("/tmp/ghfu_" .. fw_name)
    else
        sys.call("rm -f /tmp/ghfu_* 2>/dev/null")
    end
    fs.unlink("/tmp/ghfu-validate.json")
    fs.unlink("/tmp/ghfu-download.pid")
    json_resp({
        ok = true,
        msg = tr("Upgrade cancelled, temporary firmware file removed")
    })
end

function action_upgrade()
    local keep_config = to_bool(http.formvalue("keep_config")) and "1" or "0"
    local retain_packages = to_bool(http.formvalue("retain_packages")) and "1" or "0"
    local force_upgrade = to_bool(http.formvalue("force"))
    local selected_release = trim(http.formvalue("selected_release") or "")
    local fw_name = trim(http.formvalue("fw_name") or "")

    local logs = {}

    if fw_name == "" or not fw_name:match("^[%w%._%-]+$") then
        logs[#logs + 1] = tr("Invalid firmware file name")
        json_resp({ ok = false, logs = logs })
        return
    end

    local fw_path = "/tmp/ghfu_" .. fw_name
    if not fs.access(fw_path) then
        logs[#logs + 1] = tr("Firmware file not found, please download again")
        json_resp({ ok = false, logs = logs })
        return
    end

    local val = validate_downloaded_firmware(fw_path)
    if not val.valid then
        if not force_upgrade then
            logs[#logs + 1] = tr("Image check failed, confirmation of force upgrade is required")
            json_resp({ ok = false, logs = logs, need_force = true, validation = val })
            return
        end
        if not val.forceable then
            logs[#logs + 1] = tr("Firmware image validation failed and force upgrade is disallowed by system")
            json_resp({ ok = false, logs = logs })
            return
        end
    end

    if not val.allow_backup and keep_config == "1" then
        keep_config = "0"
        logs[#logs + 1] = tr("Firmware metadata does not allow keeping configuration, switched to -n")
    end

    set_cfg({
        selected_release = (selected_release ~= "" and selected_release or fw_name),
        keep_config = keep_config,
        retain_packages = retain_packages
    })

    local flags = {}
    if force_upgrade then
        flags[#flags + 1] = "--force"
    end
    if keep_config ~= "1" then
        flags[#flags + 1] = "-n"
    end
    if retain_packages == "1" then
        flags[#flags + 1] = "-k"
        if fs.access("/etc/profile.d/opkg.sh") then
            sys.call("sh -c '. /etc/profile.d/opkg.sh && opkg save' >/dev/null 2>&1")
            fs.unlink("/etc/opkg-restore-auto")
        end
    end

    local flag_str = table.concat(flags, " ")
    local up_cmd = "/sbin/sysupgrade " .. (flag_str ~= "" and (flag_str .. " ") or "") .. util.shellquote(fw_path)

    logs[#logs + 1] = tr("Starting system upgrade")
    if force_upgrade then
        logs[#logs + 1] = tr("Force upgrade enabled (--force)")
    end
    logs[#logs + 1] = (keep_config == "1") and tr("Upgrade mode: keep configuration") or tr("Upgrade mode: do not keep configuration")
    if retain_packages == "1" then
        logs[#logs + 1] = tr("Package mode: retain installed packages (-k)")
    end

    local bg = "sh -c " .. util.shellquote(string.format("(sleep 2; %s) </dev/null >/tmp/ghfu-upgrade.log 2>&1 &", up_cmd))
    sys.call(bg)

    json_resp({
        ok = true,
        logs = logs,
        rebooting = true
    })
end

function action_backup()
    local tmp = "/tmp/ghfu-backup.tar.gz"
    fs.unlink(tmp)
    local rc = sys.call("sysupgrade --create-backup " .. util.shellquote(tmp) .. " >/dev/null 2>&1")
    if rc ~= 0 or not fs.access(tmp) then
        http.status(500, "Internal Server Error")
        http.prepare_content("text/plain; charset=utf-8")
        http.write(tr("Backup failed"))
        return
    end
    local st = fs.stat(tmp)
    local hostname = trim(sys.exec("cat /proc/sys/kernel/hostname 2>/dev/null"))
    if hostname == "" then
        hostname = "OpenWrt"
    end
    hostname = hostname:gsub("[^%w%._%-]", "_")
    local fname = "backup-" .. hostname .. "-" .. os.date("%Y-%m-%d") .. ".tar.gz"
    http.header("Content-Disposition", 'attachment; filename="' .. fname .. '"')
    if st then
        http.header("Content-Length", tostring(st.size))
    end
    http.prepare_content("application/octet-stream")
    local f = io.open(tmp, "rb")
    if f then
        repeat
            local chunk = f:read(65536)
            if chunk then http.write(chunk) end
        until not chunk
        f:close()
        fs.unlink(tmp)
    end
end
