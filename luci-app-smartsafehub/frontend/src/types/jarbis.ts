export interface JarbisStatus {
  apiVersion: number;
  version: string;
  enabled: boolean;
  mqttConfigured: boolean;
  brokerMode: 'managed' | 'external';
  brokerHost: string;
  brokerPort: string;
  brokerReady: boolean;
  /** True only when the installed Jarbis implements the Shelly H&T Gen3 contract. */
  features?: { shellyHtg3?: boolean; shellyQuickPair?: boolean; rooms?: boolean };
}

export interface JarbisDevice {
  id: string;
  name: string;
  kind: string;
  protocol: string;
  topic: string;
  enabled: boolean;
  /** Stored by Jarbis; absent on older installations. */
  room?: string;
  capabilities: string[];
}

export interface JarbisCandidate {
  protocol: string;
  source: 'http' | 'mqtt' | 'dhcp';
  ip: string;
  mac: string;
  topic: string;
  name: string;
  registered: boolean;
  /** Tasmota candidates in older Jarbis versions omit this field. */
  kind?: 'light' | 'sensor';
}

export interface JarbisCredentials {
  host: string;
  port: string;
  username: string;
  secret: string;
}

// STATUS11 from the device (not the MQTT publisher acknowledgement).
export interface JarbisLightState {
  id: string;
  observed: boolean;
  source?: 'mqtt' | 'http' | null;
  reason?: 'HTTP_NO_CANDIDATE' | 'HTTP_CLIENT_MISSING' | 'HTTP_FETCH_FAILED' | 'HTTP_INVALID_STATE' | 'STATE_TIMEOUT_OR_UNAVAILABLE' | null;
  power: 'ON' | 'OFF' | null;
  brightness: number | null;
  color: string | null;
  colorTemperature: number | null; // Tasmota mired, 153..500
}

/** Latest cached measurement, NOT a permanent network/online presence indication.
 * Jarbis owns the MQTT subscriber and timestamp persistence across UI sessions.
 * lastSeen is Unix seconds of the last verified device report, not an RPC poll time.
 */
export interface JarbisSensorState {
  id: string;
  observed: boolean;
  source?: 'mqtt' | 'http' | null;
  temperatureC: number | null;
  humidityPercent: number | null;
  batteryPercent: number | null;
  lastSeen: number | null;
}

export const SHELLY_HTG3_PROTOCOL = 'shelly_htg3';
export function isShellyHtg3(device: Pick<JarbisDevice, 'protocol'>): boolean {
  return device.protocol === SHELLY_HTG3_PROTOCOL;
}
