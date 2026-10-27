# 数值区间 -> 最小 CIDR 集合
# 输入：每行 "<起始> <结束>"（升序、互不重叠）
# 输出：每行一个 CIDR
#
# 注意：awk 函数里除第一个参数外，多写的形参才是局部变量。
#       int2ip(n, a,b,c,d) 中的 a,b,c,d 若不加在形参列表里就会变成全局变量，
#       直接污染外层的块大小 b，导致死循环。这是本项目踩过的一个坑。
function int2ip(n,	a, b, c, d) {
	a = int(n / 16777216) % 256
	b = int(n / 65536) % 256
	c = int(n / 256) % 256
	d = n % 256
	return a "." b "." c "." d
}

function log2(x,	r) {
	r = 0
	while (x > 1) {
		x = x / 2
		r++
	}
	return r
}

{
	s = $1 + 0
	e = $2 + 0
	if (s > e)
		next

	while (s <= e) {
		# 找出以 s 为起点、长度不超过 e 的最大 2 的幂块
		blk = 1
		while (s % (blk * 2) == 0 && s + blk * 2 - 1 <= e)
			blk = blk * 2
		if (blk < 1)
			blk = 1

		printf "%s/%d\n", int2ip(s), 32 - log2(blk)
		s = s + blk
	}
}
