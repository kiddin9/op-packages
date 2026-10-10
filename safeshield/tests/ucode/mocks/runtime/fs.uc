'use strict';

let ubus = require('ubus');
let state = { calls: [], timeout: false };

function popen(command, mode) {
    push(state.calls, command);
    if (state.timeout) return null;
    let name = match(command, /\"name\":\"([^\"]+)\"/);
    let service_name = name ? name[1] : null;
    let instance = service_name ? ubus.state.services[service_name] : null;
    let response = {};
    if (instance != null) response[service_name] = instance;
    return {
        read: function() { return sprintf('%J', response); },
        close: function() { return true; }
    };
}

return {
    state: state,
    popen: popen,
    unlink: function() { return true; }
};
