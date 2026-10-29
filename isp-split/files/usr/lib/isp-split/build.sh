#!/bin/sh
# 数据管线：原始 CIDR -> 归一化 -> 按优先级互斥化 -> 每运营商一个 CIDR 文件
#
# 用法: build.sh <rawdir> <outdir> <优先级列表> [<占位列表>]
#   rawdir  : 含 <isp>.raw 的目录，每行一个 CIDR
#   优先级  : 空格分隔的运营商名，排在前面的优先占有重叠地址
#   占位列表: 可选，只有列在这里的运营商会把地址记入 claimed（差集占位）。
#             缺省=全部优先级行都占位（保持旧行为）。cmd_fetch 传
#             enabled=1 的行：禁用行仍按原顺序生成自己的 .txt，但不抢地址。
#
# 设计要点：
#   1. 每个集合内部先合并去重（RFC1918 无关，只做区间合并）
#   2. 逐级做差集：后一个集合要扣掉所有前面已占用的地址
#      -> 保证同一 IP 只出现在一个集合里，规则顺序不再影响归属
#   3. 全程只依赖 awk + sort，无 Python、无 ipcalc
set -eu

RAW=$1
OUT=$2
PRIORITY=$3
if [ $# -ge 4 ]; then
	CLAIM=$4
else
	CLAIM=$PRIORITY
fi

LIB=${ISP_SPLIT_LIB:-$(dirname "$0")}
WORK=$OUT/.work

mkdir -p "$OUT" "$WORK"
: > "$WORK/claimed"

printf '%-16s %8s %8s %14s\n' "运营商" "原始" "互斥后" "地址数" > "$WORK/report"

for isp in $PRIORITY; do
	src=$RAW/$isp.raw
	[ -f "$src" ] || {
		printf '%-16s %8s\n' "$isp" "缺失" >> "$WORK/report"
		continue
	}

	# 1. CIDR -> 区间，排序，合并
	awk -f "$LIB/cidr2range.awk" "$src" |
		sort |
		awk -f "$LIB/merge.awk" > "$WORK/$isp.ranges"

	# 2. 扣掉高优先级运营商已占用的地址
	awk -v claimed="$WORK/claimed" -f "$LIB/exclude.awk" "$WORK/$isp.ranges" > "$WORK/$isp.excl"

	# 3. 区间 -> 最小 CIDR 集合
	awk -f "$LIB/range2cidr.awk" "$WORK/$isp.excl" > "$OUT/$isp.txt"

	# 4. 已占用集合累加（需重新合并以保持有序且互不重叠）。
	#    F-27：只有占位列表里的行才累加——禁用行不再抢低优先级启用集合
	#    的地址；但它的 .txt 仍按原优先级序号生成，方便重新启用/预演。
	case " $CLAIM " in
	*" $isp "*)
		cat "$WORK/claimed" "$WORK/$isp.excl" |
			sort |
			awk -f "$LIB/merge.awk" > "$WORK/claimed.new"
		mv "$WORK/claimed.new" "$WORK/claimed"
		;;
	esac

	# 统计
	n_raw=$(awk -f "$LIB/cidr2range.awk" "$src" | wc -l | tr -d ' ')
	n_out=$(wc -l < "$OUT/$isp.txt" | tr -d ' ')
	n_addr=$(awk '{ split($0, p, "/"); t += 2 ^ (32 - (p[2] + 0)) } END { printf "%.0f", t }' "$OUT/$isp.txt")
	printf '%-16s %8s %8s %14s\n' "$isp" "$n_raw" "$n_out" "$n_addr" >> "$WORK/report"
done

cat "$WORK/report" >&2
