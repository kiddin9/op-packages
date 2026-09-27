'use strict';

return {
    service_instance_running: function(name, instance) {
        return name == 'safeshield' && instance == 'statistics';
    }
};
