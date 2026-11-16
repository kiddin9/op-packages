#!/usr/bin/env python3
"""
luci-app-hermes — Web PTY Server (Python implementation)
Provides WebSocket-based terminal access for Hermes Agent configuration.
Replaces the Node.js web-pty.js from luci-app-openclaw.
"""

import http.server
import socketserver
import json
import os
import sys
import signal
import struct
import hashlib
import base64
import subprocess
import threading
import time
import select
import pty
import fcntl
import termios
import urllib.parse

# ── Configuration ──
PORT = int(os.environ.get('HERMES_PTY_PORT', '3001'))
HOST = os.environ.get('HERMES_PTY_HOST', '0.0.0.0')
AUTH_TOKEN = os.environ.get('HERMES_PTY_TOKEN', '')
HERMES_VENV = os.environ.get('HERMES_VENV', '/opt/hermes/venv')
HERMES_DATA = os.environ.get('HERMES_DATA', '/opt/hermes/data')
MAX_SESSIONS = int(os.environ.get('HERMES_MAX_SESSIONS', '5'))
UI_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'ui')

# Load token from UCI if not set via env
if not AUTH_TOKEN:
    try:
        result = subprocess.run(
            ['uci', '-q', 'get', 'hermes.main.pty_token'],
            capture_output=True, text=True, timeout=3
        )
        AUTH_TOKEN = result.stdout.strip()
    except Exception:
        pass

# ── WebSocket helpers (RFC 6455) ──

def decode_ws_frame(data):
    """Decode a WebSocket frame. Returns (opcode, payload, total_consumed) or None."""
    if len(data) < 2:
        return None
    opcode = data[0] & 0x0f
    masked = bool(data[1] & 0x80)
    payload_len = data[1] & 0x7f
    offset = 2

    if payload_len == 126:
        if len(data) < 4:
            return None
        payload_len = struct.unpack('>H', data[2:4])[0]
        offset = 4
    elif payload_len == 127:
        if len(data) < 10:
            return None
        payload_len = struct.unpack('>Q', data[2:10])[0]
        offset = 10

    mask = None
    if masked:
        if len(data) < offset + 4:
            return None
        mask = data[offset:offset + 4]
        offset += 4

    if len(data) < offset + payload_len:
        return None

    payload = bytearray(data[offset:offset + payload_len])
    if mask:
        for i in range(len(payload)):
            payload[i] ^= mask[i & 3]

    return (opcode, bytes(payload), offset + payload_len)


def encode_ws_frame(data, opcode=0x01):
    """Encode data into a WebSocket frame."""
    if isinstance(data, str):
        payload = data.encode('utf-8')
    else:
        payload = data
    length = len(payload)

    if length < 126:
        header = struct.pack('>BB', 0x80 | opcode, length)
    elif length < 65536:
        header = struct.pack('>BBH', 0x80 | opcode, 126, length)
    else:
        header = struct.pack('>BBQ', 0x80 | opcode, 127, length)

    return header + payload


# ── PTY Session ──

active_sessions = 0


class PtySession:
    def __init__(self, request_handler):
        global active_sessions
        self.handler = request_handler
        self.proc = None
        self.cols = 80
        self.rows = 24
        self.alive = True
        self.buffer = b''
        self._spawn_fail_count = 0
        self._MAX_SPAWN_RETRIES = 5
        self._ping_timer = None
        self._pong_received = True

        active_sessions += 1
        print(f"[hermes-pty] Session created (active: {active_sessions}/{MAX_SESSIONS})", flush=True)

        self._spawn_pty()

    def _spawn_pty(self):
        """Spawn the shell process with a PTY."""
        env = os.environ.copy()
        env.update({
            'TERM': 'xterm-256color',
            'COLUMNS': str(self.cols),
            'LINES': str(self.rows),
            'COLORTERM': 'truecolor',
            'LANG': 'en_US.UTF-8',
            'HERMES_VENV': HERMES_VENV,
            'HERMES_DATA': HERMES_DATA,
            'HOME': '/root',
            'PATH': f"{HERMES_VENV}/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
        })

        try:
            # Create PTY
            master_fd, slave_fd = pty.openpty()

            # Set terminal size
            winsize = struct.pack('HHHH', self.rows, self.cols, 0, 0)
            fcntl.ioctl(slave_fd, termios.TIOCSWINSZ, winsize)

            # Spawn shell
            self.proc = subprocess.Popen(
                ['/bin/sh', '-l'],
                stdin=slave_fd,
                stdout=slave_fd,
                stderr=slave_fd,
                env=env,
                preexec_fn=os.setsid,
            )
            os.close(slave_fd)
            self.master_fd = master_fd
            self._spawn_fail_count = 0

            # Set master_fd to non-blocking
            flags = fcntl.fcntl(master_fd, fcntl.F_GETFL)
            fcntl.fcntl(master_fd, fcntl.F_SETFL, flags | os.O_NONBLOCK)

            # Start reader thread
            self._reader_thread = threading.Thread(target=self._read_pty, daemon=True)
            self._reader_thread.start()

            print(f"[hermes-pty] Shell spawned (PID: {self.proc.pid})", flush=True)

        except Exception as e:
            print(f"[hermes-pty] Failed to spawn shell: {e}", flush=True)
            self._cleanup()

    def _read_pty(self):
        """Read from PTY and send to WebSocket."""
        while self.alive and self.proc and self.proc.poll() is None:
            try:
                r, _, _ = select.select([self.master_fd], [], [], 0.1)
                if r:
                    data = os.read(self.master_fd, 4096)
                    if data:
                        self._send_to_client(data)
            except (OSError, IOError):
                break
            except Exception as e:
                if self.alive:
                    print(f"[hermes-pty] Read error: {e}", flush=True)
                break

        if self.alive:
            print(f"[hermes-pty] Shell exited", flush=True)
            self._spawn_fail_count += 1
            if self._spawn_fail_count > self._MAX_SPAWN_RETRIES:
                print(f"[hermes-pty] Shell failed {self._spawn_fail_count} times, stopping", flush=True)
                self._send_to_client(b'\r\n\x1b[31mShell failed to start after multiple attempts.\x1b[0m\r\n')
                return

            # Auto-restart
            self._send_to_client(b'\r\n\x1b[33mShell exited, restarting...\x1b[0m\r\n')
            time.sleep(1)
            if self.alive:
                self._spawn_pty()

    def _send_to_client(self, data):
        """Send data to WebSocket client."""
        if not self.alive:
            return
        try:
            frame = encode_ws_frame(data, 0x01)
            self.handler.request.sendall(frame)
        except Exception:
            pass

    def handle_message(self, text):
        """Handle incoming WebSocket text message."""
        try:
            msg = json.loads(text)
            msg_type = msg.get('type', '')

            if msg_type == 'stdin':
                data = msg.get('data', '')
                # Clean bracketed paste escape sequences
                data = data.replace('\x1b[?2004l', '').replace('\x1b[?2004h', '')
                data = data.replace('\x1b[200~', '').replace('\x1b[201~', '')
                if self.proc and self.proc.poll() is None:
                    os.write(self.master_fd, data.encode('utf-8'))

            elif msg_type == 'resize':
                self.cols = msg.get('cols', 80)
                self.rows = msg.get('rows', 24)
                if self.master_fd:
                    winsize = struct.pack('HHHH', self.rows, self.cols, 0, 0)
                    try:
                        fcntl.ioctl(self.master_fd, termios.TIOCSWINSZ, winsize)
                    except Exception:
                        pass

            elif msg_type == 'ping':
                self._send_to_client(json.dumps({'type': 'pong'}))

        except json.JSONDecodeError:
            # Plain text, send directly to PTY
            if self.proc and self.proc.poll() is None:
                os.write(self.master_fd, text.encode('utf-8'))

    def handle_binary(self, data):
        """Handle incoming binary WebSocket data."""
        if self.proc and self.proc.poll() is None:
            os.write(self.master_fd, data)

    def _cleanup(self):
        """Clean up session resources."""
        if not self.alive:
            return
        self.alive = False

        global active_sessions
        active_sessions = max(0, active_sessions - 1)
        print(f"[hermes-pty] Session ended (active: {active_sessions}/{MAX_SESSIONS})", flush=True)

        if self.proc and self.proc.poll() is None:
            try:
                os.kill(-self.proc.pid, signal.SIGTERM)
            except Exception:
                pass
            try:
                self.proc.terminate()
            except Exception:
                pass

        try:
            if hasattr(self, 'master_fd'):
                os.close(self.master_fd)
        except Exception:
            pass

    def __del__(self):
        self._cleanup()


# ── WebSocket Upgrade Handler ──

class WebSocketHandler(http.server.BaseHTTPRequestHandler):
    """HTTP + WebSocket upgrade handler."""

    sessions = []

    def log_message(self, format, *args):
        """Override to add prefix."""
        print(f"[hermes-pty] {args[0] if args else format}", flush=True)

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', '*')
        self.end_headers()

    def do_GET(self):
        path = urllib.parse.urlparse(self.path).path

        if path == '/health':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            self.wfile.write(json.dumps({
                'status': 'ok',
                'port': PORT,
                'uptime': time.time()
            }).encode())
            return

        # Serve static files from UI_DIR
        if path == '/' or path == '':
            path = '/index.html'

        # Security: prevent directory traversal
        full_path = os.path.normpath(os.path.join(UI_DIR, path.lstrip('/')))
        if not full_path.startswith(UI_DIR):
            self.send_response(403)
            self.end_headers()
            return

        try:
            with open(full_path, 'rb') as f:
                data = f.read()

            # Determine content type
            ext = os.path.splitext(full_path)[1]
            content_types = {
                '.html': 'text/html; charset=utf-8',
                '.css': 'text/css',
                '.js': 'application/javascript',
                '.png': 'image/png',
                '.svg': 'image/svg+xml',
                '.json': 'application/json',
            }
            ct = content_types.get(ext, 'application/octet-stream')

            self.send_response(200)
            self.send_header('Content-Type', ct)
            self.send_header('Cache-Control', 'no-cache' if ext == '.html' else 'max-age=3600')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.send_header('X-Frame-Options', 'ALLOWALL')
            self.send_header('Content-Security-Policy',
                            "default-src * 'unsafe-inline' 'unsafe-eval' data: blob: ws: wss:; frame-ancestors *")
            self.end_headers()
            self.wfile.write(data)

        except FileNotFoundError:
            # Fallback to index.html for SPA routing
            try:
                with open(os.path.join(UI_DIR, 'index.html'), 'rb') as f:
                    data = f.read()
                self.send_response(200)
                self.send_header('Content-Type', 'text/html; charset=utf-8')
                self.send_header('Access-Control-Allow-Origin', '*')
                self.end_headers()
                self.wfile.write(data)
            except FileNotFoundError:
                self.send_response(404)
                self.end_headers()

    def do_GET_ws(self):
        """Handle WebSocket upgrade for GET requests to /ws."""
        self._do_websocket_upgrade()

    def _do_websocket_upgrade(self):
        """Perform WebSocket handshake and start PTY session."""
        # Authenticate
        parsed = urllib.parse.urlparse(self.path)
        params = urllib.parse.parse_qs(parsed.query)
        client_token = params.get('token', [''])[0]

        if AUTH_TOKEN and client_token != AUTH_TOKEN:
            print(f"[hermes-pty] Auth failed from {self.client_address[0]}", flush=True)
            self.send_error(403, 'Forbidden')
            return

        # Check session limit
        if active_sessions >= MAX_SESSIONS:
            print(f"[hermes-pty] Max sessions reached ({active_sessions}/{MAX_SESSIONS})", flush=True)
            self.send_error(503, 'Service Unavailable')
            return

        # WebSocket handshake
        key = self.headers.get('Sec-WebSocket-Key', '')
        if not key:
            self.send_error(400, 'Missing Sec-WebSocket-Key')
            return

        accept = base64.b64encode(
            hashlib.sha1((key + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').encode()).digest()
        ).decode()

        response = (
            'HTTP/1.1 101 Switching Protocols\r\n'
            'Upgrade: websocket\r\n'
            'Connection: Upgrade\r\n'
            f'Sec-WebSocket-Accept: {accept}\r\n'
            '\r\n'
        )
        self.wfile.write(response.encode())
        self.wfile.flush()

        # Create PTY session
        session = PtySession(self)
        self.__class__.sessions.append(session)

        # Read WebSocket frames
        buffer = b''
        while session.alive:
            try:
                self.request.setblocking(True)
                self.request.settimeout(1.0)
                data = self.request.recv(4096)
                if not data:
                    break
                buffer += data

                while len(buffer) > 0:
                    result = decode_ws_frame(buffer)
                    if result is None:
                        break
                    opcode, payload, consumed = result
                    buffer = buffer[consumed:]

                    if opcode == 0x01:  # Text
                        session.handle_message(payload.decode('utf-8', errors='replace'))
                    elif opcode == 0x02:  # Binary
                        session.handle_binary(payload)
                    elif opcode == 0x08:  # Close
                        print("[hermes-pty] WS close frame received", flush=True)
                        session._cleanup()
                        return
                    elif opcode == 0x09:  # Ping
                        self.request.sendall(encode_ws_frame(payload, 0x0a))
                    elif opcode == 0x0a:  # Pong
                        session._pong_received = True

            except socket.timeout:
                continue
            except (ConnectionResetError, BrokenPipeError, OSError):
                break
            except Exception as e:
                if session.alive:
                    print(f"[hermes-pty] Read error: {e}", flush=True)
                break

        session._cleanup()

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

        if path == '/ws' or path.startswith('/ws?'):
            self._do_websocket_upgrade()
        else:
            # Serve static files
            if path == '/' or path == '':
                path = '/index.html'

            full_path = os.path.normpath(os.path.join(UI_DIR, path.lstrip('/')))
            if not full_path.startswith(UI_DIR):
                self.send_response(403)
                self.end_headers()
                return

            try:
                with open(full_path, 'rb') as f:
                    data = f.read()

                ext = os.path.splitext(full_path)[1]
                content_types = {
                    '.html': 'text/html; charset=utf-8',
                    '.css': 'text/css',
                    '.js': 'application/javascript',
                    '.png': 'image/png',
                    '.svg': 'image/svg+xml',
                    '.json': 'application/json',
                }
                ct = content_types.get(ext, 'application/octet-stream')

                self.send_response(200)
                self.send_header('Content-Type', ct)
                self.send_header('Cache-Control', 'no-cache' if ext == '.html' else 'max-age=3600')
                self.send_header('Access-Control-Allow-Origin', '*')
                self.end_headers()
                self.wfile.write(data)

            except FileNotFoundError:
                try:
                    with open(os.path.join(UI_DIR, 'index.html'), 'rb') as f:
                        data = f.read()
                    self.send_response(200)
                    self.send_header('Content-Type', 'text/html; charset=utf-8')
                    self.send_header('Access-Control-Allow-Origin', '*')
                    self.end_headers()
                    self.wfile.write(data)
                except FileNotFoundError:
                    self.send_response(404)
                    self.end_headers()


# ── Main ──

if __name__ == '__main__':
    import socket

    socketserver.TCPServer.allow_reuse_address = True

    class ReusableTCPServer(socketserver.TCPServer):
        allow_reuse_address = True

        def handle_request_noblock(self):
            try:
                request, client_address = self.get_request()
            except OSError:
                return
            if self.verify_request(request, client_address):
                try:
                    self.process_request(request, client_address)
                except Exception:
                    self.handle_error(request, client_address)
                    self.shutdown_request(request)
            else:
                self.shutdown_request(request)

    server = ReusableTCPServer((HOST, PORT), WebSocketHandler)
    print(f"[hermes-pty] HTTP listening on {HOST}:{PORT}", flush=True)
    print(f"[hermes-pty] UI directory: {UI_DIR}", flush=True)

    def shutdown(signum, frame):
        print("[hermes-pty] Shutdown", flush=True)
        server.shutdown()
        sys.exit(0)

    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        shutdown(None, None)
