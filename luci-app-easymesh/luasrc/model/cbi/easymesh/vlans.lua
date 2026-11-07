-- luci-app-easymesh — VLANs tab
-- Copyright (C) 2026 Arafat Rahman Zami Mondol <zamimondol@gmail.com>

local m, o
local fs   = require "nixio.fs"
local uci  = require "luci.model.uci".cursor()

m = Map("easymesh", translate("EasyMesh — VLANs"),
        translate("Extend guest / IoT / hotspot networks across the mesh. " ..
                  "The init script creates bat0.<vid> as an 8021q device for each ID."))

-- ─── Anti-lockout status banner ───────────────────────────────
local has_backup    = fs.access("/etc/easymesh/network.bak")
local rollback_pending = fs.access("/tmp/easymesh-vlan-rollback.pending")

local status = m:section(SimpleSection)
status.template = "easymesh/vlan_status"
status.data = {
    has_backup       = has_backup,
    rollback_pending = rollback_pending,
}

-- ─── Mesh VLANs configuration ─────────────────────────────────
local mv = m:section(TypedSection, "easymesh", translate("Mesh VLANs"),
    translate("Enter a comma-separated list of VLAN IDs (e.g. 10,20,30). " ..
              "If a bridge named br-<vid>, br-lan<vid>, br-vlan<vid>, " ..
              "br-guest<vid>, or br-iot<vid> already exists, it is auto-added " ..
              "to that bridge. Otherwise, add the bat0.<vid> device manually " ..
              "in Network → Interfaces → Devices."))
mv.anonymous = true

o = mv:option(Value, "mesh_vlans",
    translate("VLAN IDs (comma-separated)"),
    translate("Example: 10,20,30 — Leave empty to disable"))
o.default = ""
o.datatype = "maxlength(200)"
o.rmempty = false

-- ─── Safety & rollback ────────────────────────────────────────
local rollback = m:section(TypedSection, "easymesh",
    translate("VLAN Safety & Rollback"),
    translate("Applying VLAN changes can lock you out if a port or bridge " ..
              "is misconfigured. With Safe Apply enabled, the previous network " ..
              "config is snapshotted and auto-restored after 90 seconds unless " ..
              "you click 'Confirm VLAN Change' first."))
rollback.anonymous = true

o = rollback:option(Flag, "vlan_safe_apply",
    translate("Safe apply (90-second rollback)"))
o.default = "1"
o.rmempty = false

local bkbtn = rollback:option(Button, "_vlan_backup",
    translate("Backup network config now"))
bkbtn.inputstyle = "apply"
bkbtn.description = translate("Manually snapshot /etc/config/network to " ..
                              "/etc/easymesh/network.bak.")
function bkbtn.write(self, section)
    luci.sys.call("/usr/bin/easymesh-vlan-backup")
    luci.http.redirect(luci.dispatcher.build_url("admin", "network", "easymesh", "vlans"))
end

local cfbtn = rollback:option(Button, "_vlan_confirm",
    translate("Confirm VLAN Change"))
cfbtn.inputstyle = "apply"
cfbtn.description = translate("Cancel the pending auto-rollback. Click within " ..
                              "90 seconds of applying to keep your changes.")
function cfbtn.write(self, section)
    luci.sys.call("/usr/bin/easymesh-vlan-confirm")
    luci.http.redirect(luci.dispatcher.build_url("admin", "network", "easymesh", "vlans"))
end

local rsbtn = rollback:option(Button, "_vlan_restore",
    translate("Restore last working network config"))
rsbtn.inputstyle = "reset"
rsbtn.description = translate("Emergency restore. Reverts /etc/config/network " ..
                              "to the last snapshot and reloads the network.")
function rsbtn.write(self, section)
    luci.sys.call("/usr/bin/easymesh-vlan-restore")
    luci.http.redirect(luci.dispatcher.build_url("admin", "network", "easymesh", "vlans"))
end

-- ─── Auto-arm rollback on commit ──────────────────────────────
function m.on_after_commit(self)
    luci.sys.call("/usr/bin/easymesh-vlan-arm 90 >/tmp/easymesh-vlan-arm.log 2>&1 &")
end

-- ─── Educational guide (collapsible) ──────────────────────────
local guide = m:section(SimpleSection)
guide.template = "easymesh/vlan_guide"

return m
