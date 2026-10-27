# 把运营商分流规则块插入 /etc/config/mwan3 的正确位置
#
# 为什么不直接 uci add：
#   mwan3 按配置文件中的顺序渲染 nft 规则链（first-match），而 uci add 只能追加到末尾。
#   追加的规则必然排在 default_rule 之后，永远匹配不到 —— 等于白装。
#
# 用法：
#   awk -v insert=<规则片段文件> -v anchor=<锚点正则> -f rules-splice.awk /etc/config/mwan3
#
# 行为：
#   1. 只删掉带精确标记 option isp_split '1' 的本工具规则块
#      （不再按 isp_ 前缀或注释里的 isp_split 字符串判定，避免误删用户规则）
#   2. 在第一个匹配 anchor 的 rule 块之前插入 insert 文件内容
#   3. 找不到锚点且 insert 非空时，输出警告到 stderr 并以 3 退出，
#      绝不静默追加到链尾（追加在 catch-all 之后永远不命中）
#
# 注意：awk 函数除首参外多写的形参才是局部变量，务必写全，否则污染全局。

function blocktext(i,	e,	j,	t) {
	e = (i < nb) ? bs[i + 1] - 1 : NR
	t = ""
	# 只拼接块内的 option/list 行。块间注释、空行不能算进前一个块，
	# 否则一段含 isp_split 字样的注释就会把上面的用户规则误判成我们的。
	for (j = bs[i]; j <= e; j++)
		if (line[j] ~ /^[[:space:]]*(option|list)[[:space:]]/)
			t = t " " line[j]
	return t
}

function is_ours(i,	t) {
	if (bt[i] != "rule")
		return 0
	t = blocktext(i)
	if (t ~ /option[[:space:]]+isp_split[[:space:]]+['"]1['"]/)
		return 1
	return 0
}

function warn_no_anchor() {
	print "rules-splice.awk: 找不到锚点 '" anchor "'，拒绝把规则追加到链尾（inserted=0）" > "/dev/stderr"
}

BEGIN {
	if (insert == "") {
		print "rules-splice.awk: 缺少参数 -v insert=<规则片段文件>" > "/dev/stderr"
		exit 2
	}
	# 先读入待插入片段，顺便判断是否为空（卸载时 insert 为空是合法的）
	ni = 0
	while ((getline l < insert) > 0)
		ins[++ni] = l
	close(insert)
}

{
	line[NR] = $0
	if ($1 == "config") {
		nb++
		bs[nb] = NR
		bt[nb] = $2
		bn[nb] = $3
	}
}

END {
	for (i = 1; i <= nb; i++) {
		gsub(/['\''"]/, "", bt[i])
		gsub(/['\''"]/, "", bn[i])
	}

	# 找锚点：第一个不是我们的、且匹配 anchor 的 rule 块
	aidx = 0
	for (i = 1; i <= nb && aidx == 0; i++) {
		if (bt[i] != "rule")
			continue
		if (is_ours(i))
			continue
		# blocktext 只含 option/list 行；section 名（如 default_rule_v4）
		# 也要参与锚点匹配，否则默认锚点里的 default_rule 会失效。
		if (blocktext(i) ~ anchor || bn[i] ~ anchor)
			aidx = i
	}

	if (nb == 0) {
		if (ni > 0) {
			warn_no_anchor()
			exit 3
		}
		exit 0
	}

	# 文件头（第一个 config 之前的内容）
	for (j = 1; j < bs[1]; j++)
		print line[j]

	inserted = 0
	for (i = 1; i <= nb; i++) {
		if (is_ours(i))
			continue
		if (!inserted && i == aidx) {
			for (k = 1; k <= ni; k++)
				print ins[k]
			inserted = 1
		}
		e = (i < nb) ? bs[i + 1] - 1 : NR
		for (j = bs[i]; j <= e; j++)
			print line[j]
	}

	# 没有锚点：insert 为空（卸载）时原样输出；非空时拒绝追加
	if (!inserted && ni > 0) {
		warn_no_anchor()
		exit 3
	}
}
