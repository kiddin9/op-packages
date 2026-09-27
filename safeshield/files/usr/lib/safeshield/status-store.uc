'use strict';

let fs = require('fs');

function empty_obj() {
	return {
		data: {},
		warnings: [],
		errors: []
	};
}

function read_json(path) {
	let raw = fs.readfile(path);
	if (!raw)
		return empty_obj();

	try {
		let obj = json(raw);

		if (!obj || type(obj) != 'object')
			obj = {};

		if (!obj.data || type(obj.data) != 'object')
			obj.data = {};

		if (!obj.warnings || type(obj.warnings) != 'array')
			obj.warnings = [];

		if (!obj.errors || type(obj.errors) != 'array')
			obj.errors = [];

		return obj;
	}
	catch (e) {
		return empty_obj();
	}
}

function usage() {
	print('usage: ucode status-store.uc <path> <command> [args...]\n');
	return 1;
}

let path = ARGV[0];
let cmd = ARGV[1];

if (!path || !cmd)
	exit(usage());

let obj = read_json(path);

if (cmd == 'reset') {
	obj = empty_obj();
}
else if (cmd == 'set') {
	let key = ARGV[2];
	let value = ARGV[3];

	if (!key)
		exit(2);

	obj.data[key] = value;
}
else if (cmd == 'add_error') {
	let code = ARGV[2];

	if (!code)
		exit(2);

	push(obj.errors, { code: code });
}
else if (cmd == 'add_warning') {
	let code = ARGV[2];

	if (!code)
		exit(2);

	push(obj.warnings, { code: code });
}
else if (cmd == 'clear_messages') {
	obj.errors = [];
	obj.warnings = [];
}
else if (cmd == 'dump') {
}
else {
	exit(usage());
}

print(sprintf('%J\n', obj));
exit(0);
