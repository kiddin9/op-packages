#!/bin/sh
# 构建期剥离线路体检（FEATURE_LINECHECK=0）。
#
# 用法：sh strip-linecheck.sh <staging-root>
#
# 这是**唯一**的剥离实现。手工打包（scripts/build-ipk.sh）与 SDK/buildroot
# （主包 / LuCI 包两份 Makefile 的 Build/Prepare）都必须调用它，不许再手抄
# sed。F7 的根因就是 SDK 侧另抄了三行 sed：只覆盖 config.js，漏了 htdocs 的
# isp-split.css，于是本地（走本脚本，全树扫）、VM 全绿，24.10 SDK 产物泄漏。
#
# 源文件里用成对标记包住 feature 专属内容（shell/conf/js/css 用 `lc:begin` /
# `lc:end` 注释，Markdown 用 `<!-- lc:begin -->` / `<!-- lc:end -->`）。
# 标记必须包住内容本体，不能只包一行标题注释：CSS 曾经只包了标题，`.lc-*`
# 样式体裸奔进包，而“grep linecheck 字符串”的断言看不见它——所以本脚本除了
# 字符串零残留，还断言标记配对、剥离后标记清零、CSS 里不留 `.lc-*` 样式类。
#
# 这不是运行时开关：删掉的内容不会进入包、不会进入安装目录，也不存在
# 一个环境变量或 UCI 键能把它打开。
set -eu

ROOT=${1:-}
[ -n "$ROOT" ] || { echo "用法: sh strip-linecheck.sh <staging-root>" >&2; exit 1; }
[ -d "$ROOT" ] || { echo "目录不存在: $ROOT" >&2; exit 1; }

WORK=$(mktemp -d 2>/dev/null) || WORK=$(mktemp -d /tmp/lcstrip.XXXXXX) ||
	{ echo "无法创建临时目录" >&2; exit 1; }
trap 'rm -rf "$WORK"' EXIT

# 0) 标记配对自检：缺 lc:end 时 sed 会静默删到文件末尾，必须在剥离前拦住。
cat > "$WORK/check-marks.sh" <<'EOS'
#!/bin/sh
rc=0
for f do
	grep -Iq 'lc:begin\|lc:end' "$f" 2>/dev/null || continue
	awk '
		FNR == 1 { d = 0 }
		/lc:begin/ { d++ }
		/lc:end/ {
			d--
			if (d < 0) {
				printf "lc:end 出现在 lc:begin 之前: %s\n", FILENAME > "/dev/stderr"
				bad = 1
				exit 1
			}
		}
		END {
			if (!bad && d != 0) {
				printf "lc:begin 缺 lc:end（%d 层未闭合）: %s\n", d, FILENAME > "/dev/stderr"
				exit 1
			}
		}
	' "$f" || { echo "标记不配对: $f" >&2; rc=1; }
done
exit $rc
EOS
find "$ROOT" -type f -exec sh "$WORK/check-marks.sh" {} \; || exit 1

del_blocks() {
	_f=$1
	grep -Iq 'lc:begin' "$_f" 2>/dev/null || return 0
	_tmp=$_f.lcstrip.$$
	sed '/lc:begin/,/lc:end/d' "$_f" > "$_tmp" || { rm -f "$_tmp"; return 1; }
	# 保留原权限位（isp-split 必须仍可执行）
	chmod --reference="$_f" "$_tmp" 2>/dev/null || chmod 644 "$_tmp"
	mv -f "$_tmp" "$_f"
}

# 1) 文本文件里的标记区
find "$ROOT" -type f | while IFS= read -r f; do
	del_blocks "$f" || touch "$WORK/del-failed"
done
[ ! -e "$WORK/del-failed" ] || { echo "剥离时有文件写入失败" >&2; exit 1; }

# 2) feature=1 专属文件
find "$ROOT" -type f \
	\( -name 'linecheck.js' -o -name 'lc-run' -o -name 'luci-app-isp-split-linecheck.json' \) \
	-exec rm -f {} +

# 3) 空目录顺手收掉（LuCI view 目录只有 linecheck.js 时）
find "$ROOT" -type d -empty -delete 2>/dev/null || true

# 4) 零残留断言（白名单为空）
_leak=$(grep -rIl 'linecheck\|LINE_CHECK\|线路体检' "$ROOT" 2>/dev/null || true)
if [ -n "$_leak" ]; then
	echo "剥离失败，以下文件仍有 linecheck 残留：" >&2
	printf '%s\n' "$_leak" | sed 's/^/  /' >&2
	exit 1
fi

# 4b) 标记必须被吃干净（配对自检通过 + sed 正常时必然成立；写死断言防回归）
_marks=$(grep -rIl 'lc:begin\|lc:end' "$ROOT" 2>/dev/null || true)
if [ -n "$_marks" ]; then
	echo "剥离失败，以下文件仍残留 lc:begin / lc:end 标记：" >&2
	printf '%s\n' "$_marks" | sed 's/^/  /' >&2
	exit 1
fi

# 4c) CSS：标记必须包住样式体。`.lc-*` 不含 linecheck 字样，字符串断言抓不到，
#     所以单独断言；顺手断言花括号平衡，防止把规则体切成半截。
find "$ROOT" -type f -name '*.css' | while IFS= read -r _css; do
	if grep -q '\.lc-' "$_css"; then
		echo "CSS 仍有 .lc-* 样式（标记没有包住样式体）: $_css" >&2
		touch "$WORK/fail"
	fi
	# 用 tr 数花括号：老 busybox awk 对 gsub(/{/) 会报 "bad regex"
	_o=$(tr -cd '{' <"$_css" | wc -c | tr -d ' \n')
	_c=$(tr -cd '}' <"$_css" | wc -c | tr -d ' \n')
	if [ "$_o" != "$_c" ]; then
		echo "CSS 花括号不平衡（剥离切坏了规则体）: $_css（{=$_o }=$_c）" >&2
		touch "$WORK/fail"
	fi
done
[ ! -e "$WORK/fail" ] || exit 1

# 5) 语法自检（脚本仍能被 shell 解析）
_main=$ROOT/usr/sbin/isp-split
if [ -f "$_main" ]; then
	sh -n "$_main" || { echo "剥离后 isp-split 语法错误" >&2; exit 1; }
fi
_conf=$ROOT/etc/isp-split.conf
if [ -f "$_conf" ]; then
	sh -n "$_conf" || { echo "剥离后 isp-split.conf 语法错误" >&2; exit 1; }
fi

echo "已剥离线路体检: $ROOT"
