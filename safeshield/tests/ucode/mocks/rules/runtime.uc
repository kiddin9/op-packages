'use strict';

let state = { apply_count: 0, accepted: true, reason: '' };

return {
    state: state,
    start_local_apply_async: function() {
        state.apply_count++;
        return { accepted: state.accepted, reason: state.reason };
    }
};
