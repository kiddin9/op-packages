// Public demo only. No RPC, network, storage, or credentials are accessed.
import type { SmartHomeOperations } from '../pages/SmartHomePage';
import { demoJarbisCandidates, demoJarbisDevices, demoJarbisLightStates, demoJarbisStatus } from './data';

const blocked = async (): Promise<never> => {
  throw new Error('체험 모드에서는 기기 설정이나 MQTT 연결을 변경할 수 없습니다.');
};

export const demoJarbisOperations: SmartHomeOperations = {
  getJarbisStatus: async () => demoJarbisStatus,
  getJarbisDevices: async () => demoJarbisDevices,
  getJarbisCandidates: async () => demoJarbisCandidates,
  getJarbisLightState: async (id) => demoJarbisLightStates[id] ?? {
    id, observed: false, power: null, brightness: null, color: null, colorTemperature: null,
    reason: 'STATE_TIMEOUT_OR_UNAVAILABLE',
  },
  scanJarbis: blocked,
  setJarbisEnabled: blocked,
  addJarbisDevice: blocked,
  updateJarbisDevice: blocked,
  removeJarbisDevice: blocked,
  setJarbisLight: blocked,
  pairJarbisDevice: blocked,
  getJarbisCredentials: blocked,
};
