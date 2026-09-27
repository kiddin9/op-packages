'use strict';

function cursor() {
    return {
        load: function() { return true; },
        get: function() { return null; },
        set: function() { return true; },
        delete: function() { return true; },
        commit: function() { return true; },
        revert: function() { return true; }
    };
}

return {
    cursor: cursor
};
