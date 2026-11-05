"""APK v3 via OpenWrt 25.12 SDK's apk mkpkg; only tracked files are input.
Reference: openwrt/openwrt openwrt-25.12 include/package-pack.mk.
"""
import hashlib, io, os, pathlib, re, shutil, struct, subprocess, tarfile, tempfile, urllib.request, zipfile
ROOT = pathlib.Path(__file__).resolve().parents[1]
make = (ROOT / 'Makefile').read_text()
NAME = re.search(r'PKG_NAME:=(\S+)', make)[1]
VERSION = re.search(r'PKG_VERSION:=(\S+)', make)[1]
RELEASE = re.search(r'PKG_RELEASE:=(\S+)', make)[1]
APK = os.environ.get('APK', 'apk')
OUT = ROOT / 'dist'
FILES = subprocess.check_output(['git', '-c', f'safe.directory={ROOT}', 'ls-files', '-z'], cwd=ROOT).decode().split('\0')
EPOCH = int(subprocess.check_output(['git', '-c', f'safe.directory={ROOT}', 'log', '-1', '--format=%ct'], cwd=ROOT))
CF_URL = 'https://github.com/XIU2/CloudflareSpeedTest/releases/download/v2.3.5/cfst_linux_arm64.tar.gz'
CF_SHA256 = '0ac992fcf24d4684caed33620deb9b83ce82f32d2418dc1f90be490ce5900300'

def allowed(f):
    return f and not f.startswith(('.git/', 'docs/images/', 'docs/screenshots/')) and pathlib.Path(f).suffix.lower() not in {'.apk', '.ipk', '.zip', '.gz', '.run', '.png', '.jpg', '.jpeg', '.webp', '.pyc'}

def checked(f, data):
    if b'\0' in data[:2000]:
        if f != 'root/usr/share/cf-dns-speedtest/cfst':
            raise ValueError('Unexpected binary: ' + f)
        return data
    text = data.decode('utf-8')
    if re.search(r'[A-Za-z]:[\\/]Users[\\/]|/home/[A-Za-z0-9_.-]+/|\b192\.168\.\d+\.\d+\b', text):
        raise ValueError('Private path or LAN address: ' + f)
    for mail in re.findall(r'[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}', text):
        if not mail.endswith('@users.noreply.github.com'):
            raise ValueError('Personal email: ' + f)
    return data.replace(b'\r\n', b'\n')

def main():
    if os.geteuid() != 0:
        raise ValueError('Run with sudo to preserve root ownership in APK metadata')
    OUT.mkdir(exist_ok=True)
    if any(OUT.iterdir()):
        raise ValueError('Use an empty dist directory to avoid stale release files')
    with tempfile.TemporaryDirectory(prefix='apk-build-') as work:
        work = pathlib.Path(work)
        stage = work / 'root'
        stage.mkdir()
        prefix = 'files/' if NAME == 'luci-app-wan-latency' else 'root/'
        for f in filter(allowed, FILES):
            if not f.startswith(prefix):
                continue
            rel = f[len(prefix):]
            target = stage / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(checked(f, (ROOT / f).read_bytes()))
            target.chmod(0o755 if rel.startswith(('etc/init.d/', 'usr/sbin/', 'usr/bin/', 'usr/libexec/')) else 0o644)
            os.utime(target, (EPOCH, EPOCH))
        if NAME == 'luci-app-cf-dns-speedtest':
            blob = urllib.request.urlopen(CF_URL, timeout=120).read()
            if hashlib.sha256(blob).hexdigest() != CF_SHA256:
                raise ValueError('Upstream checksum mismatch')
            with tarfile.open(fileobj=io.BytesIO(blob), mode='r:gz') as tf:
                member = next(m for m in tf if pathlib.PurePosixPath(m.name).name == 'cfst' and m.isfile())
                data = tf.extractfile(member).read()
            if data[:4] != b'\x7fELF' or struct.unpack('<H', data[18:20])[0] != 183:
                raise ValueError('Expected ARM64 ELF')
            target = stage / 'usr/share/cf-dns-speedtest/cfst'
            target.write_bytes(data)
            target.chmod(0o755)
            os.utime(target, (EPOCH, EPOCH))
            # Official OpenWrt feeds do not carry mosdns. Ship only its runtime
            # package, not luci-app-mosdns or unrelated geo databases.
            url = 'https://github.com/sbwml/luci-app-mosdns/releases/download/v5.3.4-r14/aarch64_generic-openwrt-25.12.tar.gz'
            bundle = urllib.request.urlopen(url, timeout=120).read()
            if hashlib.sha256(bundle).hexdigest() != '1c889fe6b0845c073653e9e7973ea926e90efb0669f641d2a31fcc8e107286c5':
                raise ValueError('mosdns dependency checksum mismatch')
            with tarfile.open(fileobj=io.BytesIO(bundle), mode='r:gz') as tf:
                member = next(m for m in tf if pathlib.PurePosixPath(m.name).name == 'mosdns-5.3.4-r14.apk' and m.isfile())
                (OUT / 'mosdns-5.3.4-r14.apk').write_bytes(tf.extractfile(member).read())
        arch = 'aarch64_generic' if NAME == 'luci-app-cf-dns-speedtest' else 'noarch'
        deps = re.search(r'  DEPENDS:=(.*)', make)[1].replace('+', '').split()
        if NAME == 'luci-app-cpemonitor':
            deps = [d for d in deps if not d.startswith('kmod-')] + ['ip-full', 'flock']
        scripts = []
        for section, event in [('postinst', 'post-install'), ('postinst', 'post-upgrade'), ('prerm', 'pre-deinstall')]:
            match = re.search(r'define Package/' + re.escape(NAME) + '/' + section + r'\n(.*?)\nendef', make, re.S)
            if match:
                dest = work / event
                dest.write_text(match[1].replace('$$', '$') + '\n')
                scripts += ['--script', event + ':' + str(dest)]
        package = OUT / f'{NAME}-{VERSION}-r{RELEASE}-{arch}.apk'
        info = {'name': NAME, 'version': f'{VERSION}-r{RELEASE}', 'arch': arch,
                'license': 'GPL-3.0-only' if NAME.endswith('cf-dns-speedtest') else 'GPL-2.0-only',
                'description': 'LuCI ' + NAME.removeprefix('luci-app-') + ' for OpenWrt 25.12',
                'maintainer': 'Project contributors', 'depends': ' '.join(deps)}
        command = [APK, 'mkpkg']
        for key, value in info.items():
            command += ['--info', key + ':' + value]
        subprocess.run(command + scripts + ['--files', str(stage), '--output', str(package)], check=True)
        if package.read_bytes()[:3] != b'ADB':
            raise ValueError('Expected native APK v3 ADB container')
        unpack = work / 'unpacked'
        unpack.mkdir()
        subprocess.run([APK, 'extract', '--allow-untrusted', '--destination', str(unpack), str(package)], check=True)
        for source in stage.rglob('*'):
            if source.is_file():
                actual = unpack / source.relative_to(stage)
                if not actual.exists() or actual.read_bytes() != source.read_bytes() or actual.stat().st_uid != 0 or (actual.stat().st_mode & 0o777) != (source.stat().st_mode & 0o777):
                    raise ValueError('Extracted payload mismatch: ' + str(source.relative_to(stage)))
        with zipfile.ZipFile(OUT / f'{NAME}-{VERSION}-{RELEASE}-source.zip', 'w', zipfile.ZIP_DEFLATED) as archive:
            for f in filter(allowed, FILES):
                if f == 'root/usr/share/cf-dns-speedtest/cfst':
                    continue
                entry = zipfile.ZipInfo(NAME + '/' + f, (2026, 1, 1, 0, 0, 0))
                entry.compress_type = zipfile.ZIP_DEFLATED
                entry.external_attr = 0o100644 << 16
                archive.writestr(entry, checked(f, (ROOT / f).read_bytes()))
        shutil.copyfile(ROOT / 'docs/APK.md', OUT / 'INSTALL-APK.md')
        sums = ''.join(hashlib.sha256(p.read_bytes()).hexdigest() + '  ' + p.name + '\n' for p in sorted(OUT.iterdir()) if p.name != 'SHA256SUMS')
        (OUT / 'SHA256SUMS').write_text(sums)
        print('PASS native APK v3, exact payload round-trip, source privacy checks and SHA256SUMS')

if __name__ == '__main__':
    main()
