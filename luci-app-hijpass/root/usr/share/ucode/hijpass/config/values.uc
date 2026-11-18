/** @typedef {import('../types/config.uc').DecodedValues} DecodedValues */
/** @typedef {import('../types/config.uc').FieldDeclarations} FieldDeclarations */
/** @typedef {import('../types/sections.uc').UciSection} UciSection */
// 配置字段转换：保留 option/list、未设置和显式 false/0 的差异。
// 本模块处理业务类型与范围，不解释 UCI 文件语法，也不访问原生 cursor。
/**
 * 将 UCI 单值和列表统一为数组。
 * @param {string|string[]|null} value 原始 option/list；缺失时返回空数组。
 * @returns {string[]} 原数组或单项数组；缺失或空值返回空数组。
 */
export function list(value) {
	if (type(value) == 'array') {
		return value;
	}
	if (type(value) == 'string' && value) {
		return [value];
	}
	return [];
};

/**
 * 将十进制端口文本转换为整数，并检查范围。
 * @returns {integer} 1–65535 的端口整数；格式或范围无效时抛错。
 */
export function port(value) {
	if (type(value) != 'string' || !match(value, /^[0-9]+$/) || int(value) < 1 || int(value) > 65535) {
		die(`invalid port "${value}"`);
	}
	return int(value);
};

// 校验时长并按需换算成秒；无需换算的核心字段仍保留原始时长字符串。
/**
 * 解析带单位的时长，并换算成秒。
 * @param {string} value
 * @returns {number} 秒数，可含小数；空字符串或 "0" 返回 0。
 */
export function duration(value) {
	if (value == '' || value == '0') {
		return 0;
	}
	let remaining = value, seconds = 0;
	const units = { ns: 1e-9, us: 1e-6, 'µs': 1e-6, ms: 0.001, s: 1, m: 60, h: 3600 };
	while (length(remaining)) {
		let m = match(remaining, /^([0-9]+([.][0-9]*)?|[.][0-9]+)(ns|us|µs|ms|s|m|h)/);
		if (!m) {
			die(`invalid duration "${value}"`);
		}
		seconds += +m[1] * units[m[3]];
		remaining = substr(remaining, length(m[0]));
	}
	if (seconds > 9223372036) {
		die('duration out of range');
	}
	return seconds;
};

// 字段声明为 [类型, 默认值, 最大值（可选）]；只转换当前协议声明的字段。
// 不属于该协议的旧字段不会误触发校验，也不会混入解码结果。
/**
 * 按字段声明读取配置、应用默认值并转换类型。
 * @param {UciSection} section
 * @param {FieldDeclarations} declarations
 * @returns {DecodedValues} 仅含声明字段的新对象，保留未设置与显式 false/0 的差异。
 */
export function decode(section, declarations) {
	let result = {};
	for (let key, spec in declarations) {
		let value = section[key];
		if (value == null) {
			result[key] = spec[1];
			continue;
		}
		if (spec[0] == 'list') {
			result[key] = list(value);
			continue;
		}
		if (type(value) != 'string') {
			die(`${key} must be a string`);
		}
		switch (spec[0]) {
		case 'text': result[key] = value; break;
		case 'port': result[key] = value ? port(value) : 0; break;
		case 'bool':
			if (value != '' && value != '0' && value != '1') {
				die(`invalid UCI boolean "${value}"`);
			}
			result[key] = value == '1'; break;
		case 'duration': duration(value); result[key] = value; break;
		case 'integer':
			if (value && !match(value, /^[+]?[0-9]+$/)) {
				die(`invalid nonnegative integer "${value}"`);
			}
			result[key] = value ? int(value) : 0;
			if (result[key] < 0 || result[key] > (spec[2] || 9223372036854775807)) {
				die(`${key}: numeric option out of range`);
			}
			break;
		case 'number':
			if (value && !match(value, /^[+]?[0-9]+([.][0-9]+)?([eE][+-]?[0-9]+)?$/)) {
				die(`invalid number "${value}"`);
			}
			result[key] = value ? +value : 0;
			if (result[key] != result[key] || result[key] < 0 || result[key] > 1.7976931348623157e308) {
				die(`${key}: invalid number`);
			}
			break;
		}
	}
	return result;
};
