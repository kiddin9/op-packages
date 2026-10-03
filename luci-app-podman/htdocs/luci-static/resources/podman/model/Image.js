'use strict';

'require baseclass';

'require podman.model.Model as Model';

const ImageRPC = {
	inspect: Model.declareRPC({
		object: 'podman',
		method: 'image_inspect',
		params: ['id'],
	}),

	inspectManifest: Model.declareRPCSilent({
		object: 'podman',
		method: 'image_manifest_inspect',
		params: ['image']
	}),

	remove: Model.declareRPC({
		object: 'podman',
		method: 'image_remove',
		params: ['id', 'force'],
	}),
};

const Image = Model.base.extend({
	__name__: 'Podman.Model.Image',

	getID() {
		return this.Id;
	},

	getDisplayTag() {
		return this.getRepoTags()[0];
	},

	getRepoTags() {
		return this.RepoTags || ['<none>:<none>'];
	},

	getRepository() {
		const tag = this.getDisplayTag() || '<none>:<none>';
		return tag.split(':')[0] || '<none>';
	},

	getTag() {
		const tag = this.getDisplayTag() || '<none>:<none>';
		return tag.split(':')[1] || '<none>';
	},

	getDigest() {
		if (this.Digest) {
			return this.Digest;
		}

		if (this.RepoDigests && this.RepoDigests.length > 0) {
			for (const rd of this.RepoDigests) {
				if (rd.includes('@sha256:')) {
					return rd.split('@')[1];
				}
			}
		}
		return null;
	},

	inspect() {
		return ImageRPC.inspect(this.getID());
	},

	inspectManifest(ref) {
		return ImageRPC.inspectManifest(ref || this.getDisplayTag());
	},

	remove() {
		return ImageRPC.remove(this.getID());
	},

	update(onProgress) {
		return this.streamPull(onProgress);
	},

	streamPull(onProgress) {
		return new Promise((resolve, reject) => {
			let handle;
			handle = this._stream(
				() => L.url('admin/podman/stream/pull') + '?reference=' + encodeURIComponent(this.getDisplayTag()),
				(chunk) => {
					if (chunk.images && chunk.images.length > 0) { resolve(chunk.images[0]); handle.stop(); return; }
					if (chunk.error) { reject(new Error(chunk.error)); handle.stop(); return; }
					if (chunk.stream) onProgress?.(chunk.stream);
					if (chunk.raw) onProgress?.(chunk.raw + '\n');
				}
			);
		});
	},
});

return baseclass.extend({
	getSingleton(image) {
		return Image.extend(image).instantiate([]);
	}
});
