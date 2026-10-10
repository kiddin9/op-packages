'use strict';
return {
    service_status: function() {
        return { state: 'running', running: true, lookup_ok: true, instances: { statistics: { running: true } } };
    },
    service_instance_running: function(name, instance) {
        return name == 'safeshield' && instance == 'statistics';
    }
};
