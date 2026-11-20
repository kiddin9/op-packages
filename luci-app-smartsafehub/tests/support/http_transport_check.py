#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""실제 TLS curl 요청에서 리다이렉트와 응답 코드 정책을 검증한다."""

from __future__ import annotations

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from tempfile import TemporaryDirectory
from threading import Thread
import os
import shutil
import ssl
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
HTTP_LIB = ROOT / 'root/usr/lib/smartsafehub/http.sh'


class Recorder(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    records: list[tuple[str, str, str]]
    redirect_url: str

    def do_GET(self):
        self._handle()

    def do_POST(self):
        self._handle()

    def _handle(self):
        payload = self.rfile.read(int(self.headers.get('Content-Length', '0')))
        self.records.append((self.path, self.headers.get('Authorization', ''), payload.decode()))
        if self.path in ('/redirect', '/redirect-post'):
            self.send_response(302)
            self.send_header('Location', self.redirect_url)
            self.send_header('Content-Length', '0')
            self.end_headers()
        elif self.path == '/redirect-no-location':
            self.send_response(301)
            self.send_header('Content-Length', '0')
            self.end_headers()
        elif self.path == '/error':
            self.send_error(404)
        elif self.path == '/empty':
            self.send_response(204)
            self.send_header('Content-Length', '0')
            self.end_headers()
        else:
            self.send_response(200)
            self.send_header('Content-Length', '11')
            self.end_headers()
            self.wfile.write(b'{"ok":true}')

    def log_message(self, *_args):
        pass


def server(cert: Path, key: Path, handler: type[Recorder]):
    httpd = ThreadingHTTPServer(('127.0.0.1', 0), handler)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(str(cert), str(key))
    httpd.socket = context.wrap_socket(httpd.socket, server_side=True)
    worker = Thread(target=httpd.serve_forever, daemon=True)
    worker.start()
    return httpd, worker


def curl_request(tmp: Path, url: str, method: str = 'GET', output: Path | None = None):
    path = output or tmp / 'received'
    body = tmp / 'payload.json'
    body.write_text('{"secret":"credential-must-not-redirect"}')
    script = '. "$1"; ssh_http_request "$2" "$3" 5 "$4" "$5" ${6:+-H} ${6:+"Authorization: Device credential-123"}'
    # Avoid variable-expansion tricks in test code: method and URL are passed as positional arguments.
    argv = ['sh', '-c', script, 'test', str(HTTP_LIB), method, str(path), url, str(body), 'auth' if method == 'POST' else '']
    result = subprocess.run(argv, capture_output=True, text=True, timeout=15, env={
        **os.environ,
        'CURL_CA_BUNDLE': str(tmp / 'ca.pem'),
        'SSL_CERT_FILE': str(tmp / 'ca.pem'),
        'SMARTSAFEHUB_HTTP_CURL_BIN': shutil.which('curl') or 'curl',
        'HTTPS_PROXY': 'http://127.0.0.1:1',  # --noproxy must override this.
    })
    return result, path


def test_리다이렉트_시_자격증명_재전송_금지(tmp: Path, origin: str, target: type[Recorder]):
    result, output = curl_request(tmp, origin + '/redirect-post', 'POST')
    assert result.returncode != 0, result
    assert not output.exists(), 'redirect failure must remove output'
    assert not target.records, 'secret or payload reached redirected host'


def test_HTTP_상태_및_HTTPS_제한(tmp: Path, origin: str):
    result, output = curl_request(tmp, origin + '/success')
    assert result.returncode == 0 and output.read_bytes() == b'{"ok":true}', result
    result, output = curl_request(tmp, origin + '/redirect')
    assert result.returncode != 0 and not output.exists(), 'GET followed redirect'
    result, output = curl_request(tmp, origin + '/redirect-no-location')
    assert result.returncode != 0 and not output.exists(), '3xx without Location accepted'
    result, output = curl_request(tmp, origin + '/error')
    assert result.returncode != 0 and not output.exists(), '404 accepted'
    result, output = curl_request(tmp, origin.replace('https://', 'http://') + '/success')
    assert result.returncode != 0 and not output.exists(), 'plaintext HTTP accepted'
    result, _ = curl_request(tmp, origin + '/empty', output=Path('/dev/null'))
    assert result.returncode == 0 and Path('/dev/null').exists(), '204 status must preserve /dev/null'


def main():
    with TemporaryDirectory(prefix='ssh-curl-') as directory:
        tmp = Path(directory)
        config = tmp / 'openssl.cnf'
        config.write_text('''[req]
prompt=no
distinguished_name=dn
x509_extensions=ext
[dn]
CN=localhost
[ext]
subjectAltName=DNS:localhost,IP:127.0.0.1
basicConstraints=critical,CA:TRUE
keyUsage=critical,keyCertSign,digitalSignature,keyEncipherment
''')
        subprocess.run([
            'openssl', 'req', '-x509', '-nodes', '-newkey', 'rsa:2048',
            '-keyout', str(tmp / 'key.pem'), '-out', str(tmp / 'ca.pem'),
            '-days', '1', '-config', str(config)
        ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=15)
        class Target(Recorder):
            records = []
            redirect_url = ''
        class Source(Recorder):
            records = []
            redirect_url = ''
        target, target_worker = server(tmp / 'ca.pem', tmp / 'key.pem', Target)
        source, source_worker = server(tmp / 'ca.pem', tmp / 'key.pem', Source)
        try:
            origin = f'https://127.0.0.1:{source.server_port}'
            Source.redirect_url = f'https://127.0.0.1:{target.server_port}/intercept'
            test_리다이렉트_시_자격증명_재전송_금지(tmp, origin, Target)
            test_HTTP_상태_및_HTTPS_제한(tmp, origin)
            assert not Target.records, 'redirect target unexpectedly contacted'
        finally:
            source.shutdown()
            target.shutdown()
            source.server_close()
            target.server_close()
            source_worker.join(timeout=3)
            target_worker.join(timeout=3)
    print('PASS: curl HTTPS no-redirect, credential isolation and 2xx response policy')


if __name__ == '__main__':
    try:
        main()
    except Exception as exc:
        print(f'FAIL: {exc}', file=sys.stderr)
        raise
