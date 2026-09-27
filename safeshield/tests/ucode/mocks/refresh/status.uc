'use strict';

let state = { value: 'test-status' };

return {
    state: state,
    build: function() { return { marker: state.value }; }
};
