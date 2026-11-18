import { duration } from '../../../config/values.uc';

// streamSettings.network 为 Xray 原生传输名；只接收当前核心支持的传输。
// WS 的 early data 通过 URL 的 ed 参数传递，必须保留已有 query 和 fragment。
/** @typedef {import('../../../types/transport.uc').TransportOptions} TransportOptions */
/** @typedef {import('../../../types/transport.uc').GrpcTransportOptions} GrpcTransportOptions */
/** @typedef {import('../../../types/core.uc').StreamSettings} StreamSettings */
/** @typedef {import('../../../types/core.uc').GrpcSettings} GrpcSettings */
/**
 * 把已解码的 gRPC 选项转换成 Xray 设置，并将时长换成整数秒。
 * @param {GrpcTransportOptions} options
 * @returns {GrpcSettings} 未配置的超时保持 null，permit_without_stream 仅在开启时写入。
 */
function grpcSettings(options) {
	let settings = {
		serviceName: options.transport_grpc_service_name || 'TunService',
		idle_timeout: int(duration(options.transport_grpc_idle_timeout)) || null,
		health_check_timeout: int(duration(options.transport_grpc_ping_timeout)) || null,
	};
	if (options.transport_grpc_permit_without_stream) {
		settings.permit_without_stream = true;
	}
	return settings;
}
/**
 * 将节点传输选项填入 Xray streamSettings。
 * @param {StreamSettings} stream Xray streamSettings，原地填充传输选项。
 * @param {TransportOptions} n 已经 UCI 解码并校验的传输字段。
 * @returns {null} 无业务返回值；原地修改 stream，未指定传输时跳过。
 */
export function apply(stream, n) {
	switch (n.transport_type) {
	case '': break;
	case 'xhttp':
		stream.network = 'xhttp';
		stream.xhttpSettings = {
			host: n.transport_xhttp_host, path: n.transport_xhttp_path || '/',
			mode: n.transport_xhttp_mode || 'auto', uplinkHTTPMethod: n.transport_xhttp_method,
		};
		break;
	case 'httpupgrade':
		stream.network = 'httpupgrade';
		stream.httpupgradeSettings = { host: n.transport_httpupgrade_host, path: n.transport_httpupgrade_path || '/' };
		break;
	case 'ws':
		let path = n.transport_ws_path || '/';
		if (n.transport_ws_max_early_data) {
			let hash = index(path, '#') ?? -1, base = hash < 0 ? path : substr(path, 0, hash);
			let separator = '?', fragment = '';
			if (index(base, '?') >= 0) {
				separator = '&';
			}
			if (hash >= 0) {
				fragment = substr(path, hash);
			}
			path = base + separator + `ed=${n.transport_ws_max_early_data}` + fragment;
		}
		stream.network = 'websocket';
		stream.wsSettings = { host: n.transport_ws_host, path };
		break;
	case 'grpc':
		stream.network = 'grpc';
		stream.grpcSettings = grpcSettings(n);
		break;
	default: die(`unsupported Xray transport "${n.transport_type}"`);
	}
};
