# OpenWrt APK release key

`nikitid-openwrt-release.pem` is the shared public P-256 key for the author's
OpenWrt 25.12 application feed. It is byte-for-byte identical to the existing
IKEv2 Manager release public key.

The matching private key is not stored in this repository. Release builds read
it from the protected `OPENWRT_APK_SIGNING_KEY` CI secret. Compromise of that
private key would affect every package in the shared feed.

Public-key SHA-256:

```text
f27474d9261f1084350cf4ba34ecdff29e533769c36483d8dd85566e30a6a703
```
