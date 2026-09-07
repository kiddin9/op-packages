import { PROXY_TYPE } from "../../../enum/hijpass";
import {
    CustomProxyNode,
    Hysteria2Config,
    LoadBalanceProxyNode,
    ProxyNode,
    ShadowsocksConfig,
    ShadowTLSConfig,
    TuicConfig,
    VlessConfig
} from "../../../module/luci";

const ProxyUtils = {

    /**
     * 从 UCI 配置段创建对应的 ProxyNode 配置类
     */
    createProxyConfigFromSection: function (section: any): ProxyNode | null {
        const type = section.type;
        let config: ProxyNode;

        switch (type) {
            case PROXY_TYPE.LOAD_BALANCE:
                config = new LoadBalanceProxyNode();
                break;
            case PROXY_TYPE.HYSTERIA2:
                config = new Hysteria2Config();
                break;
            case PROXY_TYPE.SHADOWSOCKS:
                config = new ShadowsocksConfig();
                break;
            case PROXY_TYPE.TUIC:
                config = new TuicConfig();
                break;
            case PROXY_TYPE.SHADOWTLS:
                config = new ShadowTLSConfig();
                break;
            case PROXY_TYPE.VLESS:
                config = new VlessConfig();
                break;
            case PROXY_TYPE.CUSTOM:
                config = new CustomProxyNode();
                break;
            default:
                return null;
        }

        // 从 UCI 配置复制所有字段
        Object.keys(section).forEach((key) => {
            if (key !== '.type' && key !== '.name' && key !== '.anonymous') {
                Reflect.set(config, key, section[key]);
            }
        });
        config.cfgid = section['.name'];

        return config;
    }
}

export { ProxyUtils }
