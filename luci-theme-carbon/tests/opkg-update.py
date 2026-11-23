"""Upgrade legacy and 23.05 SDK IPKs using real OpenWrt 23.05 and 24.10 opkg managers."""
import hashlib
import io
import json
from pathlib import Path
import subprocess
import tarfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / '.cache' / 'opkg-update'
IMAGES = {
    '24.10': 'openwrt/rootfs:x86_64-24.10.8@sha256:9972a4b4747cd136abd597475d7b88c51a49fd849d0d53f069a2f4bf446061b9',
    '23.05': 'openwrt/rootfs:x86_64-23.05.6@sha256:f53afb386d05651ada9a4a964e0779930f30962a2abc2fadf1b03bfcbcbabb14',
}


def docker(*args, input=None):
    r = subprocess.run(['docker', *args], input=input.encode() if input is not None else None,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=180, check=True)
    return r.stdout.decode()


def archive(files):
    out = io.BytesIO()
    with tarfile.open(fileobj=out, mode='w:gz') as tar:
        for name, content in files.items():
            content = content.encode() if isinstance(content, str) else content
            entry = tarfile.TarInfo('./' + name)
            entry.size = len(content)
            entry.mode = 0o755 if name == 'postrm' else 0o644
            tar.addfile(entry, io.BytesIO(content))
    return out.getvalue()


def make_ipk(path, version, postrm=None):
    control_files = {'control': f'Package: luci-theme-carbon\nVersion: {version}\nArchitecture: all\nDescription: Upgrade regression fixture\n'}
    if postrm is not None:
        control_files['postrm'] = postrm
    control = archive(control_files)
    path.write_bytes(archive({'control.tar.gz': control, 'data.tar.gz': archive({'usr/share/carbon-test-marker': 'old'}), 'debian-binary': '2.0\n'}))


class OpkgUpgrade(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        OUT.mkdir(parents=True, exist_ok=True)
        cls.fullversion = (ROOT / 'root/usr/share/carbon/version').read_text().strip()
        cls.name = f'luci-theme-carbon_{cls.fullversion}_all.ipk'
        docker('run', '--rm', '--mount', f'type=bind,source={ROOT},target=/source,readonly',
               '--mount', f'type=bind,source={OUT},target=/out',
               'alpine:3.23@sha256:469c9ea410b9215eaee7976ba6c0639039b444be8e5d638f7abbada189971eb2',
               'sh', '-c', 'apk add --no-cache tar && sh /source/scripts/build-ipk.sh /out')
        cls.content = (OUT / cls.name).read_bytes()

    def run_upgrade(self, image, legacy_version, expect_setsid, fallback_to_pages=False):
        make_ipk(
            OUT / f'legacy-{legacy_version}.ipk',
            legacy_version,
            '#!/bin/sh\nuci set luci.main.mediaurlbase=/luci-static/bootstrap\nuci commit luci\n',
        )
        c = docker('run', '-d', '--platform', 'linux/amd64',
                   '--mount', f'type=bind,source={ROOT},target=/source,readonly',
                   image, 'sleep', '600').strip()
        def shell(command): return docker('exec', c, 'sh', '-c', command)
        def put(path, text): docker('exec', '-i', c, 'sh', '-c', 'cat > "$1"', 'sh', path, input=text)
        def rpc(method, payload=None):
            return json.loads(docker('exec', '-i', c, '/usr/libexec/rpcd/luci.carbon_update', 'call', method, input=json.dumps(payload or {})))
        def wait():
            for _ in range(100):
                result = rpc('status')
                if not result.get('busy'): return result
                time.sleep(.1)
            self.fail('Worker did not finish')
        try:
            has_setsid = shell('if command -v setsid >/dev/null 2>&1; then echo yes; else echo no; fi').strip()
            self.assertEqual(has_setsid, 'yes' if expect_setsid else 'no')
            shell('mkdir -p /var/lock; opkg update >/tmp/feeds.log 2>&1; opkg install curl ca-bundle flock >/tmp/tools.log 2>&1')
            shell(f'opkg install /source/.cache/opkg-update/legacy-{legacy_version}.ipk; cp -r /source/root/usr/. /usr/; chmod 755 /usr/libexec/rpcd/luci.carbon_update')
            put('/tmp/release.json', json.dumps(dict(tag_name='v' + self.fullversion.split('-r')[0], draft=False, prerelease=False, body='IPK test',
                assets=[dict(name=self.name, size=len(self.content), digest='sha256:' + hashlib.sha256(self.content).hexdigest())])))
            shell('mv /usr/bin/curl /usr/bin/test-real-curl')
            put('/usr/bin/curl', '''#!/bin/sh
while [ "$#" -gt 0 ]; do
 case "$1" in -o) out=$2; shift ;; https://*) url=$1 ;; esac
 shift
done
case "$url" in
 https://api.github.com/repos/mrjoechen/luci-theme-carbon/releases/latest) [ ! -f /tmp/github-fail ] || exit 22; cp /tmp/release.json "$out" ;;
 https://github.com/mrjoechen/luci-theme-carbon/releases/download/v*/luci-theme-carbon_*_all.ipk) [ ! -f /tmp/github-fail ] || exit 28; cp /source/.cache/opkg-update/''' + self.name + ''' "$out" ;;
 https://mrjoechen.github.io/luci-theme-carbon/updates/latest.json) cp /tmp/release.json "$out" ;;
 https://mrjoechen.github.io/luci-theme-carbon/updates/v*/luci-theme-carbon_*_all.ipk) cp /source/.cache/opkg-update/''' + self.name + ''' "$out" ;;
 *) exit 22 ;;
esac
''')
            shell('chmod 755 /usr/bin/curl; touch /etc/config/luci; uci -q get luci.main >/dev/null || uci set luci.main=core; uci set luci.main.lang=zh_cn; uci set luci.main.mediaurlbase=/luci-static/carbon; uci commit luci')
            if fallback_to_pages:
                shell('touch /tmp/github-fail')
            before = shell('uci show luci.main')
            initial = rpc('status')
            self.assertEqual((initial['current'], initial['reason']), (legacy_version, ''), initial)
            self.assertTrue(rpc('check')['started'])
            checked = wait()
            self.assertTrue(checked['can_upgrade'], checked)
            if fallback_to_pages:
                self.assertIn('Checking release from pages', checked['log'])
            else:
                self.assertIn('Checking release from github', checked['log'])
                self.assertNotIn('Checking release from pages', checked['log'])
            self.assertTrue(rpc('upgrade', dict(version=self.fullversion))['started'])
            result = wait()
            self.assertEqual((result['state'], result['current']), ('success', self.fullversion), result)
            if fallback_to_pages:
                self.assertIn('Downloading from pages', result['log'])
            else:
                self.assertIn('Downloading from github', result['log'])
                self.assertNotIn('Downloading from pages', result['log'])
            self.assertEqual(shell('uci show luci.main'), before)
            self.assertNotIn('syntax error', result['log'])
            self.assertFalse(result['can_upgrade'])
        finally:
            docker('rm', '-f', c)

    def test_legacy_hook_does_not_reset_preferences_24_10(self):
        self.run_upgrade(IMAGES['24.10'], '1.0.0-r1', expect_setsid=True)

    def test_openwrt_24_10_pages_fallback_when_github_fails(self):
        self.run_upgrade(IMAGES['24.10'], '1.0.0-r1', expect_setsid=True, fallback_to_pages=True)

    def test_openwrt_23_05_upgrades_without_setsid_and_from_sdk_version(self):
        self.run_upgrade(IMAGES['23.05'], '1.0.0-1', expect_setsid=False)

    def test_openwrt_23_05_same_sdk_version_is_not_offered_as_upgrade(self):
        same_sdk_ver = self.fullversion.replace('-r', '-')
        make_ipk(OUT / f'same-{same_sdk_ver}.ipk', same_sdk_ver)
        c = docker('run', '-d', '--platform', 'linux/amd64',
                   '--mount', f'type=bind,source={ROOT},target=/source,readonly',
                   IMAGES['23.05'], 'sleep', '600').strip()
        def shell(command): return docker('exec', c, 'sh', '-c', command)
        def put(path, text): docker('exec', '-i', c, 'sh', '-c', 'cat > "$1"', 'sh', path, input=text)
        def rpc(method, payload=None):
            return json.loads(docker('exec', '-i', c, '/usr/libexec/rpcd/luci.carbon_update', 'call', method, input=json.dumps(payload or {})))
        def wait():
            for _ in range(100):
                result = rpc('status')
                if not result.get('busy'): return result
                time.sleep(.1)
            self.fail('Worker did not finish')
        try:
            shell('mkdir -p /var/lock; opkg update >/tmp/feeds.log 2>&1; opkg install curl ca-bundle flock >/tmp/tools.log 2>&1')
            shell(f'opkg install /source/.cache/opkg-update/same-{same_sdk_ver}.ipk; cp -r /source/root/usr/. /usr/; chmod 755 /usr/libexec/rpcd/luci.carbon_update')
            put('/tmp/release.json', json.dumps(dict(tag_name='v' + self.fullversion.split('-r')[0], draft=False, prerelease=False, body='IPK test',
                assets=[dict(name=self.name, size=len(self.content), digest='sha256:' + hashlib.sha256(self.content).hexdigest())])))
            shell('mv /usr/bin/curl /usr/bin/test-real-curl')
            put('/usr/bin/curl', '''#!/bin/sh
while [ "$#" -gt 0 ]; do
 case "$1" in -o) out=$2; shift ;; https://*) url=$1 ;; esac
 shift
done
case "$url" in
 https://api.github.com/repos/mrjoechen/luci-theme-carbon/releases/latest) [ ! -f /tmp/github-fail ] || exit 22; cp /tmp/release.json "$out" ;;
 https://mrjoechen.github.io/luci-theme-carbon/updates/latest.json) cp /tmp/release.json "$out" ;;
 *) exit 22 ;;
esac
''')
            shell('chmod 755 /usr/bin/curl')
            self.assertTrue(rpc('check')['started'])
            checked = wait()
            self.assertEqual((checked['current'], checked['latest'], checked['reason']), (same_sdk_ver, self.fullversion, ''), checked)
            self.assertIn('Checking release from github', checked['log'])
            self.assertNotIn('Checking release from pages', checked['log'])
            self.assertFalse(checked['can_upgrade'], checked)
            self.assertEqual(rpc('upgrade', dict(version=self.fullversion))['error'], 'stale')
            shell('touch /tmp/github-fail')
            self.assertTrue(rpc('check')['started'])
            checked = wait()
            self.assertEqual((checked['current'], checked['latest'], checked['reason']), (same_sdk_ver, self.fullversion, ''), checked)
            self.assertIn('Checking release from pages', checked['log'])
            self.assertFalse(checked['can_upgrade'], checked)
        finally:
            docker('rm', '-f', c)


if __name__ == '__main__':
    unittest.main(verbosity=2)
