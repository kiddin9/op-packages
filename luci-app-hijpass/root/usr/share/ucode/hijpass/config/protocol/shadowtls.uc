import { BASE_FIELDS, SERVER_FIELDS, TLS_FIELDS } from './options.uc';

// shadowtls 的字段契约；不包含其它协议的专用字段。
export const fields = {
	...BASE_FIELDS,
	...SERVER_FIELDS,
	...TLS_FIELDS,
	password: ["text", ""], // 远端认证密码
	version: ["integer", 1, 2147483647], // ShadowTLS 协议版本（1/2/3），默认 1
};
