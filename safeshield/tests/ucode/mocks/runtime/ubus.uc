'use strict';

let state = {
    services: {}
};

function connect() {
    return {
        call: function(object, method, args) {
            if (object != 'service' || method != 'list' || !args || !args.name) {
                return null;
            }

            let result = {};
            let service = state.services[args.name];
            if (service != null) {
                result[args.name] = service;
            }
            return result;
        }
    };
}

return {
    state: state,
    connect: connect
};
