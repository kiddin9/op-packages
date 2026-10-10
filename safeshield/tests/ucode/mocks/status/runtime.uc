'use strict';
let state = { service_running: true, dnsmasq_running: true, lookup_ok: true };
return {
    state: state,
    service_status: function(name) {
        let running = name == 'dnsmasq' ? state.dnsmasq_running : state.service_running;
        return { running: running && state.lookup_ok, state: !state.lookup_ok ? 'unknown' : (running ? 'running' : 'stopped'), lookup_ok: state.lookup_ok };
    },
    service_running: function() { return state.service_running; },
    dnsmasq_running: function() { return state.dnsmasq_running; }
};
