'use strict';

let state = { refresh_count: 0, statistics_reset_count: 0, accepted: true, reason: '' };

return {
    state: state,
    reset_statistics_upload_state: function() {
        state.statistics_reset_count++;
    },
    start_refresh_async: function() {
        state.refresh_count++;
        return { accepted: state.accepted, reason: state.reason };
    }
};
