"""Offline checks for SDK selection and the actual translation catalogue."""
import importlib.util
import io
import json
import pathlib
import re
import tempfile
import subprocess
import unittest
from unittest.mock import patch

ROOT = pathlib.Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("resolve_sdk", ROOT / "tools/resolve-sdk.py")
SDK = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SDK)


class SDKTests(unittest.TestCase):
    def test_requested_version_and_target_select_the_corresponding_sdk(self):
        for version, target in [("24.10.0", "x86/64"), ("23.05.5", "mediatek/filogic")]:
            filename = f"openwrt-sdk-{version}-test_gcc.Linux-x86_64.tar.zst"
            checksum = "a" * 64
            listing = f'<a href="{filename}">{filename}</a><a href="../">Parent</a>'
            with patch.object(SDK, "urlopen", side_effect=[io.BytesIO(listing.encode()), io.BytesIO(f"{checksum} *{filename}\n".encode())]) as fetch:
                url, sha = SDK.resolve(version, target)
                self.assertEqual(url, f"https://downloads.openwrt.org/releases/{version}/targets/{target}/{filename}")
                self.assertEqual(sha, checksum)
                self.assertEqual(fetch.call_args_list[0].args[0], f"https://downloads.openwrt.org/releases/{version}/targets/{target}/")

    def test_invalid_inputs_fail_before_any_network_request(self):
        for version, target in [("$(id)", "x86/64"), ("24.10.0", "../x86"), ("24.10.0", "x86/64\nextra")]:
            with patch.object(SDK, "urlopen") as fetch:
                with self.assertRaises(ValueError):
                    SDK.resolve(version, target)
                fetch.assert_not_called()

    def test_missing_sdk_or_checksum_is_rejected(self):
        with patch.object(SDK, "urlopen", return_value=io.BytesIO(b"<html></html>")):
            with self.assertRaisesRegex(ValueError, "found 0"):
                SDK.resolve("24.10.0", "x86/64")
        filename = "openwrt-sdk-24.10.0-test.Linux-x86_64.tar.xz"
        with patch.object(SDK, "urlopen", side_effect=[io.BytesIO(f'<a href="{filename}">SDK</a>'.encode()), io.BytesIO(b"invalid checksum")]):
            with self.assertRaisesRegex(ValueError, "No checksum"):
                SDK.resolve("24.10.0", "x86/64")

    def test_catalogues_cover_native_extracted_messages_including_menu_and_acl(self):
        def ids(content):
            result = set()
            key = None
            for line in content.splitlines():
                if line.startswith("msgid "):
                    key = json.loads(line[6:])
                elif key is not None and line.startswith('"'):
                    key += json.loads(line)
                elif line.startswith("msgstr "):
                    if key:
                        result.add(re.sub(r" +", " ", key.strip()))
                    key = None
            return result
        strings = set()
        for file in (ROOT / "htdocs").rglob("*.js"):
            extracted = subprocess.run(["xgettext", "--from-code=UTF-8", "--language=JavaScript",
                                        "--keyword=_:1", "--keyword=N_:2,3", "--no-wrap", "-o", "-", "-"],
                                       input=file.read_text(), capture_output=True, text=True, check=True).stdout
            strings.update(ids(extracted))
        for directory in ["root/usr/share/luci/menu.d", "root/usr/share/rpcd/acl.d"]:
            for file in (ROOT / directory).glob("*.json"):
                strings.update(re.findall(r'"(?:title|description)"\s*:\s*"([^"]+)"', file.read_text()))
        for file in [ROOT / "po/templates/device-manager.pot", ROOT / "po/zh_Hans/device-manager.po"]:
            self.assertEqual(ids(file.read_text()), strings)

    def test_snapshot_sdk_uses_snapshot_directory_and_unversioned_sdk_name(self):
        filename = "openwrt-sdk-x86-64_gcc-14_musl.Linux-x86_64.tar.zst"
        checksum = "b" * 64
        with patch.object(SDK, "urlopen", side_effect=[
            io.BytesIO(f'<a href="{filename}">SDK</a>'.encode()),
            io.BytesIO(f"{checksum} *{filename}\n".encode())
        ]) as fetch:
            url, sha = SDK.resolve("SNAPSHOT", "x86/64")
            self.assertEqual(url, f"https://downloads.openwrt.org/snapshots/targets/x86/64/{filename}")
            self.assertEqual(sha, checksum)
            self.assertEqual(fetch.call_args_list[0].args[0],
                             "https://downloads.openwrt.org/snapshots/targets/x86/64/")

    def test_selected_configuration_preserves_target_and_disables_sdk_all_defaults(self):
        spec = importlib.util.spec_from_file_location("configure_sdk", ROOT / "tools/configure-sdk.py")
        configure = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(configure)
        with tempfile.TemporaryDirectory() as tmp:
            directory = pathlib.Path(tmp)
            (directory / "rules.mk").touch()
            (directory / "Makefile").touch()
            (directory / ".config").write_text("CONFIG_TARGET_x86=y\nCONFIG_ALL=y\nCONFIG_ALL_KMODS=y\nCONFIG_ALL_NONSHARED=y\nCONFIG_PACKAGE_unrelated=y\nCONFIG_LUCI_LANG_de=y\n")
            configure.configure(directory)
            result = (directory / ".config").read_text()
            self.assertIn("CONFIG_TARGET_x86=y", result)
            self.assertIn("# CONFIG_ALL_KMODS is not set", result)
            self.assertIn("CONFIG_PACKAGE_luci-app-device-manager=m", result)
            self.assertIn("CONFIG_PACKAGE_luci-i18n-device-manager-zh-cn=m", result)
            self.assertNotIn("CONFIG_PACKAGE_unrelated", result)
            self.assertNotIn("CONFIG_LUCI_LANG_de", result)
            configure.configure(directory)
            self.assertEqual((directory / ".config").read_text(), result)
            with self.assertRaises(ValueError):
                configure.configure(directory / "not-an-sdk")

    def test_upstream_export_is_bounded_and_preserves_existing_checkout(self):
        spec = importlib.util.spec_from_file_location("prepare_upstream", ROOT / "tools/prepare-upstream.py")
        export = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(export)
        with tempfile.TemporaryDirectory() as tmp:
            checkout = pathlib.Path(tmp)
            (checkout / "luci.mk").touch()
            target = export.prepare(checkout)
            self.assertTrue((target / "htdocs").is_dir())
            self.assertIn("include ../../luci.mk", (target / "Makefile").read_text())
            self.assertNotIn("feeds/luci/luci.mk", (target / "Makefile").read_text())
            self.assertTrue((target / "root/etc/config/device_manager").is_file())
            self.assertFalse((target / "root/etc/uci-defaults/80_device_manager").exists())
            readme = (target / "README.md").read_text()
            self.assertIn("opkg install luci-app-device-manager\n", readme)
            self.assertIn("apk add luci-app-device-manager\n", readme)
            for obsolete in ["尚未合并到官方源", "--allow-untrusted", "GitHub Actions", "workflow 默认"]:
                self.assertNotIn(obsolete, readme)
            for name in [".github", "tools", "test", "device-icons"]:
                self.assertFalse((target / name).exists())
            self.assertFalse((target / "docs/upstream-submission.md").exists())
            (target / "user-sentinel").write_text("preserve")
            with self.assertRaises(FileExistsError):
                export.prepare(checkout)
            self.assertEqual((target / "user-sentinel").read_text(), "preserve")

    def test_scan_acl_requires_write_permission_but_keeps_passive_discovery_readable(self):
        acl = json.loads((ROOT / "root/usr/share/rpcd/acl.d/luci-app-device-manager.json").read_text())["luci-app-device-manager"]
        self.assertIn("getNetworkDevices", acl["read"]["ubus"]["luci-rpc"])
        self.assertIn("get_online_status", acl["read"]["ubus"]["luci.device-manager"])
        self.assertNotIn("scan_devices", acl["read"]["ubus"]["luci.device-manager"])
        self.assertIn("scan_devices", acl["write"]["ubus"]["luci.device-manager"])


if __name__ == "__main__":
    unittest.main()
