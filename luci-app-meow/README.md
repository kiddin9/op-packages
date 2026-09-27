本仓库完全自包含:init 脚本、UCI 默认配置、默认 YAML、LuCI JS/JSON 均已收录
(取自 meow-rs 仓库 `openwrt/` 目录),CI 里不需要再从上游仓库复制任何文件;
构建时唯一的外部依赖是 `meow/Makefile` 声明的官方 release tarball
(`PKG_SOURCE_URL` + `PKG_HASH` 校验)。

## 参考

- meow-rs: https://github.com/meow-rs/meow-rs
- OpenWrt feeds 文档: https://openwrt.org/docs/guide-developer/feeds
- OpenWrt apk 包管理器(25.12+): https://openwrt.org/docs/guide-user/additional-software/apk
