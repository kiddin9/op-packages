'use strict';

let runtime = require('runtime');
let status = require('status');

let start_refresh_async = runtime.start_refresh_async;
let build_status = status.build;

function refresh_call() {
    let r = start_refresh_async();

    if (!r.accepted) {
        return {
            ok: r.reason == 'already_running',
            accepted: false,
            reason: r.reason,
            status: build_status()
        };
    }

    return {
        ok: true,
        accepted: true,
        status: build_status()
    };
}

return {
    call: refresh_call
};
