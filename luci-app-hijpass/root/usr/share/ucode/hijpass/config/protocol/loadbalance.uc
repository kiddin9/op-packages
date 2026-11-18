import { BASE_FIELDS } from './options.uc';

// loadbalance 的字段契约；不包含其它协议的专用字段。
export const fields = {
	...BASE_FIELDS,
	url: ["text", ""], // sing-box URLTest 探测地址；空值使用核心默认值
	interval: ["duration", ""], // sing-box URLTest 探测间隔，保留时长字符串
	tolerance: ["integer", null, 65535], // sing-box URLTest 切换容差，单位毫秒
	idle_timeout: ["duration", ""], // sing-box URLTest 空闲停止探测时长，保留时长字符串
	interrupt_exist_connections: ["bool", false], // 0/1；URLTest 切换成员时中断现有连接
	strategy: ["text", "leastLoad"], // Xray 均衡策略（leastPing/leastLoad/random/roundRobin）
	strategy_expected: ["integer", 1, 2147483647], // Xray leastLoad 期望选中节点数
	strategy_max_rtt: ["duration", "1s"], // Xray leastLoad 最大 RTT，保留时长字符串
	strategy_tolerance: ["number", 0.05], // Xray leastLoad 偏差容忍比例，默认 0.05
	fallback_tag: ["text", ""], // Xray 回退成员名称；预检时校验它属于成员列表
	probe_url: ["text", "https://connectivitycheck.gstatic.com/generate_204"], // Xray HTTP 探测 URL
	probe_connectivity: ["text", ""], // Xray 连接探测目标
	probe_interval: ["duration", "60s"], // Xray 探测间隔，保留时长字符串
	probe_timeout: ["duration", "2s"], // Xray 探测超时，保留时长字符串
	probe_sampling: ["integer", 3, 2147483647], // Xray 探测样本数，默认 3
	probe_http_method: ["text", ""], // Xray HTTP 探测方法
};
