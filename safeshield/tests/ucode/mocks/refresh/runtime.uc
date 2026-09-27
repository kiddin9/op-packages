'use strict';

let state = { accepted: true, reason: '' };

return {
    state: state,
    start_refresh_async: function() {
        return { accepted: state.accepted, reason: state.reason };
    }
};
