module("luci.controller.easymesh", package.seeall)

function index()
    if not nixio.fs.access("/etc/config/easymesh") then return end

    local page = entry({"admin", "network", "easymesh"},
                       firstchild(), _("EasyMesh"), 60)
    page.dependent = false
    page.acl_depends = { "luci-app-easymesh" }

    entry({"admin", "network", "easymesh", "dashboard"},
          cbi("easymesh/dashboard"), _("Dashboard"), 5)

    entry({"admin", "network", "easymesh", "config"},
          cbi("easymesh/config"), _("Settings"), 10)

    entry({"admin", "network", "easymesh", "ap_mode"},
          cbi("easymesh/ap_mode"), _("AP Mode"), 15)

    entry({"admin", "network", "easymesh", "client_wifi"},
          cbi("easymesh/client_wifi"), _("Client WiFi"), 20)

    entry({"admin", "network", "easymesh", "quick"},
          cbi("easymesh/quick_setup"), _("Quick Setup"), 25)

    entry({"admin", "network", "easymesh", "vlans"},
          cbi("easymesh/vlans"), _("VLANs"), 30)
end
