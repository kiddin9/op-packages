# 区间差集：target 减去 claimed
# 用法：awk -v claimed=<已占用区间文件> -f exclude.awk < target
#   claimed：已按字典序排好的互不重叠区间 "<起始> <结束>"（零填充定宽）
#   target ：同样已排序去重叠的区间（stdin）
# 输出：target 中未被 claimed 覆盖的部分（零填充、升序、互不重叠）
# 目的：让同一个 IP 只归属一个运营商集合，消除归属歧义

function pad(n,	s) {
	s = sprintf("%.0f", n)
	while (length(s) < 10)
		s = "0" s
	return s
}

BEGIN {
	if (claimed == "") {
		print "exclude.awk: 缺少参数 -v claimed=<已占用区间文件>" > "/dev/stderr"
		exit 2
	}
	nc = 0
	while ((getline l < claimed) > 0) {
		n = split(l, f, " ")
		if (n < 2)
			continue
		nc++
		cs[nc] = f[1] + 0
		ce[nc] = f[2] + 0
	}
	close(claimed)
	ci = 1
}
{
	s = $1 + 0
	e = $2 + 0
	if (s > e)
		next

	# 跳过完全位于 s 之前的已占用区间
	while (ci <= nc && ce[ci] < s)
		ci++

	cur = ci
	while (cur <= nc && cs[cur] <= e) {
		if (cs[cur] > s)
			print pad(s), pad(cs[cur] - 1)
		if (ce[cur] + 1 > s)
			s = ce[cur] + 1
		if (s > e)
			break
		cur++
	}

	if (s <= e)
		print pad(s), pad(e)
}
