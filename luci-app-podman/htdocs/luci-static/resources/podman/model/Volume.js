'use strict';

'require baseclass';

'require podman.model.Model as Model';

const VolumeRPC = {
	inspect: Model.declareRPC({
		object: 'podman',
		method: 'volume_inspect',
		params: ['name']
	}),

	remove: Model.declareRPC({
		object: 'podman',
		method: 'volume_remove',
		params: ['name', 'force']
	}),
};

const Volume = Model.base.extend({
	__name__: 'Podman.Model.Volume',

	getName() {
		return this.Name || _('Unknown');
	},

	async inspect() {
		return VolumeRPC.inspect(this.getName());
	},

	async remove(force) {
		return VolumeRPC.remove(this.getName(), force || false);
	},
});

return baseclass.extend({
	getSingleton(volume) {
		return Volume.extend(volume).instantiate([]);
	},
});
