#!/bin/sh
# substore cron job — 按订阅定时更新
# 用法：substore-cron.sh [订阅ID]（不传则更新全部已启用订阅）
# 注意：显式传 -L /usr/share/ucode，确保独立 cron 进程能找到 substore.* 模块

# 数据目录可被环境变量覆盖，仅用于测试；生产环境仍为 /etc/substore
DATA_DIR="${SUBSTORE_DATA_DIR:-/etc/substore}"
LIST_FILE="$DATA_DIR/subscriptions.json"
SUB_ID="${1:-}"
UCODE_BIN="$(command -v ucode 2>/dev/null)"

if [ -z "$UCODE_BIN" ]; then
	# 没有解释器 = 整个订阅更新链路不可用，属于必须暴露的故障，
	# 不能静默 exit 0 让 cron 看起来一切正常。
	logger -t luci-app-substore "cron: no ucode interpreter found"
	exit 1
fi

[ -f "$LIST_FILE" ] || exit 0

# 2>&1：把 ucode 的 stderr（逐条失败原因）与结果行合并后统一记录。
# --：SUB_ID 以 - 开头时也不会被当成选项。
OUT=$(
"$UCODE_BIN" -L /usr/share/ucode -e '
const core = require("substore.core");

const sub_id = length(ARGV) ? `${ARGV[0] ?? ""}` : "";
let ok_count = 0, fail_count = 0;

// core.sync 失败时是「返回 [null, err]」而非抛异常，因此要同时处理两层结果：
// 没有抛错只说明调用完成，返回值的数组首元素才是 sync 自身的结果。
// 只判断有没有抛错会把「sync 返回 [null, err]」统计成成功。
function sync_one(id) {
	try {
		const r = core.sync(id);
		const res = r ? r[0] : null;
		const err = r ? r[1] : null;
		if (res != null && res !== false) {
			ok_count++;
			return;
		}
		fail_count++;
		warn(sprintf("Failed sync %s: %s\n", id, err ?? "unknown error"));
	} catch (e) {
		fail_count++;
		warn(sprintf("Failed sync %s: %s\n", id, e ?? "unknown error"));
	}
}

if (sub_id != "") {
	sync_one(sub_id);
} else {
	const r = core.list();
	const items = r ? r[0] : null;
	// 列不出订阅 = 本轮什么都没做，抛出去让进程非 0 退出；
	// 打印结果行会把这种彻底失败伪装成「0 个失败」。
	if (items == null)
		die("Failed to list subscriptions: " + `${(r ? r[1] : null) ?? "unknown error"}`);
	for (let it in items)
		if (it.enabled)
			sync_one(it.id);
}

printf("substore cron done: %d ok, %d failed\n", ok_count, fail_count);
' -- "$SUB_ID" 2>&1
)

# 输出到 stdout（cron 会按需邮件/记录），同时写 syslog
printf '%s\n' "$OUT"
if command -v logger >/dev/null 2>&1; then
	printf '%s\n' "$OUT" | logger -t luci-app-substore
fi

# 退出码反映本轮结果：有订阅更新失败就返回非 0，让 cron 的 MAILTO / 外部监控
# 能据此判断，而不是无论成败都 exit 0。日志行由上面 ucode 以 %d 格式打印，
# 不存在前导零，故可直接按字面比较。
FAILED=$(printf '%s\n' "$OUT" | sed -n 's/.*: [0-9][0-9]* ok, \([0-9][0-9]*\) failed.*/\1/p' | tail -1)
case "$FAILED" in
	'')
		# 没有结果行 ≠「0 个失败」，而是 ucode 根本没跑到最后：模块加载失败、
		# core.list() 抛异常、解释器中途死掉等等。旧实现把这种情况和成功归为
		# 一类（''|0) exit 0），于是一次彻底失败的更新在 cron / 外部监控看来与
		# 成功无异 —— 故障永远不会被发现。
		echo "substore cron: no result line, ucode did not complete" >&2
		exit 1
		;;
	0) exit 0 ;;
	*) exit 1 ;;
esac
