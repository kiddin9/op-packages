'use strict';

let state = { service_running: true, dnsmasq_running: true };

return {
    state: state,
    service_running: function() { return state.service_running; },
    dnsmasq_running: function() { return state.dnsmasq_running; }
};
