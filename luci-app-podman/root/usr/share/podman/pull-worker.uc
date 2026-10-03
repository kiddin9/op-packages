'use strict';

import { open, unlink } from 'fs';
import { urlencode, ENCODE_FULL } from 'lucihttp'; // ucode-lsp disable
import * as podman_socket from 'luci.podman_socket'; // ucode-lsp disable
import { API_BASE } from 'luci.podman_socket'; // ucode-lsp disable
import { build_request, parse_status, read_headers } from 'luci.podman_http'; // ucode-lsp disable

const BLOCKSIZE = 4096;

const reference = ARGV[0];
const logfile   = ARGV[1];
const pidfile   = ARGV[2];

/**
 * @param {string} msg
 */
function write_error(msg) {
	let f = open(logfile, 'a');
	if (f) {
		f.write('{"error":"' + replace(replace(msg, /\\/g, '\\\\'), /"/g, '\\"') + '"}\n');
		f.flush();
		f.close();
	}
}

/**
 * @param {int} code
 */
function cleanup(code) {
	unlink(pidfile);
	exit(code ?? 0);
}

if (!reference || !logfile || !pidfile)
	exit(1);

// Write own PID to pidfile so the streaming endpoint can check if we are running
let ps = open('/proc/self/stat', 'r');
if (ps) {
	let pid = +(split(ps.read(200) || '0', ' ')[0]);
	ps.close();
	let pf = open(pidfile, 'w');
	if (pf) { pf.write(pid + '\n'); pf.close(); }
}

// Connect to Podman socket
let sock = podman_socket.connect();
if (!sock) {
	write_error('Cannot connect to Podman socket');
	cleanup(1);
}

let encoded = urlencode(reference, ENCODE_FULL);

sock.send(build_request(
	'POST',
	sprintf('%s/images/pull?reference=%s&quiet=false', API_BASE, encoded),
	null
));

// Read HTTP response headers (blocking recv - no uloop needed in standalone process)
let lf = null;

let hdrs = read_headers(sock, BLOCKSIZE);
if (!hdrs) {
	write_error('Podman closed connection before responding');
	sock.close();
	cleanup(1);
}

let code = parse_status(hdrs.header_buf) || 502;
let body = hdrs.body_remainder;

if (code !== 200) {
	let parsed = null;
	try { parsed = json(body); } catch(e) {}
	let msg = (parsed?.message) || (parsed?.cause)
	       || replace(body, /\s+$/, '')
	       || sprintf('Podman error %d', code);
	write_error(msg);
	sock.close();
	cleanup(1);
}

lf = open(logfile, 'a');
if (!lf) { sock.close(); cleanup(1); }

// Write any body bytes that arrived together with headers
if (length(body)) { lf.write(body); lf.flush(); }

// Stream response body to logfile - Podman sends NDJSON, we write it as-is
while (true) {
	let chunk = sock.recv(BLOCKSIZE);
	if (!chunk) break; // EOF or error - Podman finished
	lf.write(chunk);
	lf.flush();
}

lf.close();
sock.close();
cleanup(0);
