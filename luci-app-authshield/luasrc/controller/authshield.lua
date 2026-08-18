-- AuthShield LuCI Controller
-- Registers the CBI configuration page under System → AuthShield.

module("luci.controller.authshield", package.seeall)

function index()
  -- Only register the menu if the config file exists
  if not nixio.fs.access("/etc/config/authshield") then return end

  -- System → AuthShield
  entry({"admin", "system", "authshield"},
        cbi("authshield"),
        _("AuthShield"),
        60).dependent = true
end
