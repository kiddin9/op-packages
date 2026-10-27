# 找出不合法的 CIDR 行（校验规则与 cidr2range.awk 保持一致）
# 输出格式：<行号>: <原始内容>
{
	line = $0
	sub(/#.*/, "", line)
	gsub(/[ \t\r]/, "", line)
	if (line == "")
		next

	n = split(line, p, "/")
	if (n != 2) {
		print NR ": " $0
		next
	}

	alen = split(p[1], q, ".")
	if (alen != 4) {
		print NR ": " $0
		next
	}

	# 与 cidr2range.awk 保持一致：前缀必须是纯数字，不能靠 +0 转换
	if (p[2] !~ /^[0-9]+$/) {
		print NR ": " $0
		next
	}
	len = p[2] + 0
	if (len < 0 || len > 32) {
		print NR ": " $0
		next
	}

	bad = 0
	for (i = 1; i <= 4; i++) {
		if (q[i] !~ /^[0-9]+$/)
			bad = 1
		else if (q[i] + 0 > 255)
			bad = 1
	}
	if (bad)
		print NR ": " $0
}
