'use strict';

let state = {
    last_action: '',
    refresh_count: 0,
    service_ok: true,
    service_rc: 0,
    refresh_accepted: true,
    refresh_reason: ''
};

return {
    state: state,
    run_service_action: function(action) {
        state.last_action = action;
        return { ok: state.service_ok, rc: state.service_rc };
    },
    start_refresh_async: function() {
        state.refresh_count++;
        return { accepted: state.refresh_accepted, reason: state.refresh_reason };
    }
};
