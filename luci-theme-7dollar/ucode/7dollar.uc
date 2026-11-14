// 7Dollar: helpers shared by the theme templates (sidebar and login page).

/* What to call this box. x86 boards often keep a BIOS placeholder ("Default string",
 * "To be filled by O.E.M.") as their model: name them by CPU instead, e.g. "Intel Celeron N5105". */
export function model(board) {
	const m = board?.model;
	if (m && !match(m, /default string|to be filled|o\.e\.m|system product name|not (specified|applicable)/i))
		return m;
	return trim(replace(replace(board?.system ?? '', /\((R|TM)\)|\bCPU\b|@.*$/g, ''), /\s+/g, ' '))
		|| board?.release?.distribution || 'OpenWrt';
};
