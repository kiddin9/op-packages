import { callApi } from './rpc';
import type { RpcPriority } from './rpcScheduler';
import type { JarbisCandidate, JarbisCredentials, JarbisDevice, JarbisStatus, JarbisLightState, JarbisSensorState } from '../types/jarbis';

const rpc = <T>(method: string, params: Record<string, unknown> = {}, timeoutMs = 6500,
  priority: RpcPriority = 'high', signal?: AbortSignal) =>
  callApi<T>('jarbis', method, params, { priority, timeoutMs, ...(signal ? { signal } : {}) });

// Background page reads use the ordinary queue, leaving high priority to
// explicit control commands. Abort queued and running reads on navigation.
export const getJarbisStatus = (signal?: AbortSignal) => rpc<JarbisStatus>('status', {}, 6500, 'normal', signal);
export const getJarbisDevices = (signal?: AbortSignal) => rpc<{ devices: JarbisDevice[] }>('devices_list', {}, 6500, 'normal', signal);
export const getJarbisCandidates = (signal?: AbortSignal) => rpc<{ devices: JarbisCandidate[] }>('discovery_list', {}, 6500, 'normal', signal);
export const scanJarbis = () => rpc<{ devices: JarbisCandidate[] }>('discovery_scan', {}, 35000);
export const setJarbisEnabled = (enabled: boolean) => rpc<{ enabled: boolean }>('settings_update', { enabled }, 15000);
export const addJarbisDevice = (id: string, name: string, topic: string, protocol?: 'shelly_htg3') =>
  rpc<{ id: string; added: boolean }>('device_add', protocol
    ? { id, name, topic, protocol, kind: 'sensor' } : { id, name, topic });
export const updateJarbisDevice = (id: string, name: string, enabled: boolean) => rpc<{ id: string; updated: boolean }>('device_update', { id, name, enabled });
export const setJarbisDeviceRoom = (id: string, room: string) =>
  rpc<{ id: string; room: string; updated: boolean }>('device_room_set', { id, room });
export const removeJarbisDevice = (id: string) => rpc<{ id: string; removed: boolean }>('device_remove', { id });
export const getJarbisLightState = (id: string, priority: RpcPriority = 'high') => rpc<JarbisLightState>('light_state', { id }, 11500, priority);
// An optional Jarbis v2 method. Never query battery sensors at the 30s bulb cadence.
export const getJarbisSensorState = (id: string, priority: RpcPriority = 'normal') =>
  rpc<JarbisSensorState>('sensor_state', { id }, 6500, priority);
export const setJarbisLight = (id: string, capability: 'power' | 'brightness' | 'color' | 'color_temperature', value: string) =>
  rpc<{ accepted: boolean }>('light_set', { id, capability, value });
export const getJarbisCredentials = () => rpc<JarbisCredentials>('broker_credentials');

// Pairing never exposes the managed MQTT secret to the browser. The optional
// Tasmota web-admin password is sent only in this explicit RPC request.
export const pairJarbisDevice = (id: string, adminPassword = '', replaceExisting = false) =>
  rpc<{ id: string; configured: boolean; mqttConfirmed: boolean; observed?: boolean; rebootPending?: boolean }>(
    'device_pair', { id, admin_password: adminPassword, replace_existing: replaceExisting }, 36000,
  );
