# CIDR -> 数值区间
# 输入：每行一个 CIDR（允许 # 注释、行尾空白）
# 输出：每行 "<起始> <结束>"，均为零填充的 10 位定宽数字
#
# 为什么零填充：
#   OpenWrt 的 busybox sort 对大数执行 sort -n 时并不按数值排序
#   （实测 3232235520 会排在 134744064 之前，等于没排序）。
#   把数值零填充到 10 位后，普通字典序 == 数值序，任何平台都成立。
#
# 纯算术实现，不使用位运算，兼容 busybox awk / mawk / gawk

function pad(n,	s) {
	s = sprintf("%.0f", n)
	while (length(s) < 10)
		s = "0" s
	return s
}

{
	line = $0
	sub(/#.*/, "", line)
	gsub(/[ \t\r]/, "", line)
	if (line == "")
		next

	n = split(line, p, "/")
	if (n != 2)
		next

	alen = split(p[1], q, ".")
	if (alen != 4)
		next

	# 前缀必须是纯数字；否则 "abc"/"" 会被 +0 当成 0，单行就吞掉整个 IPv4
	if (p[2] !~ /^[0-9]+$/)
		next
	len = p[2] + 0
	if (len < 0 || len > 32)
		next

	bad = 0
	for (i = 1; i <= 4; i++) {
		if (q[i] !~ /^[0-9]+$/)
			bad = 1
		else if (q[i] + 0 > 255)
			bad = 1
	}
	if (bad)
		next

	ip = q[1] * 16777216 + q[2] * 65536 + q[3] * 256 + q[4]
	if (ip < 0 || ip > 4294967295)
		next

	blk = 2 ^ (32 - len)
	s = int(ip / blk) * blk
	e = s + blk - 1
	print pad(s), pad(e)
}
