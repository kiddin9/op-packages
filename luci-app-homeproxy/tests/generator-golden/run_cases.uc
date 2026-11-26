#!/usr/bin/ucode
'use strict';

import { readfile, writefile, stat } from 'fs';

const base_dir = ARGV?.[0] || 'tests/generator-golden';
const generator = ARGV?.[1] || '/etc/homeproxy/scripts/generate_client.uc';
const module_dir = ARGV?.[2];

function hasFlag(flag) {
	const argv = (type(ARGV) === 'array') ? ARGV : [];

	for (let item in argv)
		if (item === flag)
			return true;

	return false;
}

const update_expected = hasFlag('--update');

function shellquote(s) {
	return `'${replace(s, "'", "'\\''")}'`;
}

function fail(message) {
	warn(message + '\n');
	exit(1);
}

function path(...parts) {
	return join('/', parts);
}

function exists(file) {
	return stat(file)?.type === 'file';
}

function readJson(file, fallback) {
	if (!exists(file))
		return fallback;

	return json(readfile(file));
}

function normalize(value, test_root) {
	let value_type = type(value);

	if (value_type === 'string')
		return replace(value, test_root, '__TEST_ROOT__');

	if (value_type === 'array') {
		let result = [];
		for (let item in value)
			push(result, normalize(item, test_root));
		return result;
	}

	if (value_type === 'object') {
		let result = {};
		for (let key in value) {
			if (key === 'time')
				continue;
			result[key] = normalize(value[key], test_root);
		}
		return result;
	}

	return value;
}

function canonical(value) {
	return sprintf('%.J', value);
}

function compareJson(case_name, label, actual, expected) {
	if (canonical(actual) === canonical(expected))
		return;

	warn(sprintf('%s: %s golden mismatch\n', case_name, label));
	warn('expected:\n' + sprintf('%.J\n', expected));
	warn('actual:\n' + sprintf('%.J\n', actual));
	exit(1);
}

function generatorCommand() {
	if (module_dir && module_dir !== '--update')
		return sprintf('ucode -S -L %s %s', shellquote(module_dir), shellquote(generator));

	return shellquote(generator);
}

function prepareRoot(case_name, fixture_dir) {
	const test_root = '/tmp/homeproxy-golden-' + replace(case_name, /[^A-Za-z0-9_-]/g, '_');

	system('rm -rf ' + shellquote(test_root));
	system('mkdir -p ' +
		shellquote(path(test_root, 'etc/config')) + ' ' +
		shellquote(path(test_root, 'etc/homeproxy/resources')) + ' ' +
		shellquote(path(test_root, 'var/run/homeproxy')));

	writefile(path(test_root, 'etc/config/homeproxy'), readfile(path(fixture_dir, 'homeproxy')));

	const direct_list = path(fixture_dir, 'resources/direct_list.txt'),
	      proxy_list = path(fixture_dir, 'resources/proxy_list.txt');
	writefile(path(test_root, 'etc/homeproxy/resources/direct_list.txt'), exists(direct_list) ? readfile(direct_list) : '');
	writefile(path(test_root, 'etc/homeproxy/resources/proxy_list.txt'), exists(proxy_list) ? readfile(proxy_list) : '');

	return test_root;
}

function runCase(item) {
	const case_name = item.name,
	      fixture_dir = path(base_dir, 'fixtures', case_name),
	      meta = readJson(path(fixture_dir, 'case.json'), null);

	if (!meta)
		fail(sprintf('%s: missing fixture case.json', case_name));

	const test_root = prepareRoot(case_name, fixture_dir),
	      stdout_path = path(test_root, 'var/run/homeproxy/stdout.log'),
	      stderr_path = path(test_root, 'var/run/homeproxy/stderr.log'),
	      command = sprintf('%s --test-root %s >%s 2>%s',
		generatorCommand(),
		shellquote(test_root),
		shellquote(stdout_path),
		shellquote(stderr_path)),
	      status = system(command),
	      success = (status === 0);

	if (!!meta.success !== success) {
		warn(sprintf('%s: expected success=%J, got status=%d\n', case_name, meta.success, status));
		warn(readfile(stderr_path) || '');
		system('rm -rf ' + shellquote(test_root));
		exit(1);
	}

	const actual_config_path = path(test_root, 'var/run/homeproxy/sing-box-c.json'),
	      expected_config_path = path(fixture_dir, 'expected/sing-box-c.json');

	if (meta.success) {
		if (!exists(actual_config_path))
			fail(sprintf('%s: generator succeeded but sing-box-c.json is missing', case_name));
		const actual_config = normalize(json(readfile(actual_config_path)), test_root);

		if (update_expected)
			writefile(expected_config_path, sprintf('%.J\n', actual_config));
		else
			compareJson(case_name, 'sing-box-c.json',
				actual_config,
				readJson(expected_config_path, null));
	}

	const actual_diagnostics = exists(path(test_root, 'var/run/homeproxy/config-diagnostics.json'))
		? json(readfile(path(test_root, 'var/run/homeproxy/config-diagnostics.json')))
		: { items: [] };
	const normalized_diagnostics = normalize(actual_diagnostics, test_root),
	      expected_diagnostics_path = path(fixture_dir, 'expected/config-diagnostics.json');

	if (update_expected)
		writefile(expected_diagnostics_path, sprintf('%.J\n', normalized_diagnostics));
	else
		compareJson(case_name, 'config-diagnostics.json',
			normalized_diagnostics,
			readJson(expected_diagnostics_path, { items: [] }));

	system('rm -rf ' + shellquote(test_root));
	printf('%s ok\n', case_name);
}

const cases = readJson(path(base_dir, 'cases.json'), []);
let count = 0;

for (let item in cases) {
	if (!item.generator_fixture)
		continue;

	runCase(item);
	count++;
}

printf('generator golden fixtures: %d ok\n', count);
