import { CoreAdapter, ProxyNode } from '../module/luci'
import { CORE_TYPE, normalizeCoreType } from '../enum/hijpass'
import { SingBoxUtils } from './singbox/builder'
import { XrayUtils } from './xray/builder'

const FactoryType = CORE_TYPE

const CoreAdapterFactory = {
    getCoreAdapter: function (type: string): CoreAdapter {
        switch (normalizeCoreType(type)) {
            case FactoryType.SING_BOX: return SingBoxUtils
            case FactoryType.XRAY: return XrayUtils
            default: throw new Error('Unsupported core: ' + type)
        }
    }
}

const LuciConverterFactory = {
    genProxyConf: function (type: string, proxyNode: ProxyNode): {} {
        switch (normalizeCoreType(type)) {
            case FactoryType.SING_BOX: return SingBoxUtils.genProxyConf(proxyNode)
            case FactoryType.XRAY: return XrayUtils.genProxyConf(proxyNode)
            default: throw new Error('Unsupported core: ' + type)
        }
    }
}

export { FactoryType, CoreAdapterFactory, LuciConverterFactory }
