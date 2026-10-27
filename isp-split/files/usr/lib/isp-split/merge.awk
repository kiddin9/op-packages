# 合并重叠/相邻区间
# 输入：已按字典序排好的 "<起始> <结束>"（零填充定宽，字典序 == 数值序）
# 输出：互不重叠、已合并的区间，同样零填充
#
# 注意：不能依赖 sort -n —— busybox 的 sort -n 对大数不生效。
#       输入已经是零填充格式，普通 sort 即可得到正确数值序。

function pad(n,	s) {
	s = sprintf("%.0f", n)
	while (length(s) < 10)
		s = "0" s
	return s
}

BEGIN {
	have = 0
}
{
	s = $1 + 0
	e = $2 + 0
	if (s > e)
		next

	if (!have) {
		cs = s
		ce = e
		have = 1
		next
	}

	# 与当前合并段重叠或正好相邻
	if (s <= ce + 1) {
		if (e > ce)
			ce = e
		next
	}

	print pad(cs), pad(ce)
	cs = s
	ce = e
}
END {
	if (have)
		print pad(cs), pad(ce)
}
