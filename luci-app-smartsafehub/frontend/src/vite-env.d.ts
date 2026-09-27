/// <reference types="vite/client" />

import type { SmartSafeHubBootstrap } from './types/bootstrap';

declare global {
  interface Window {
    __SMARTHUB_BOOTSTRAP__?: SmartSafeHubBootstrap;
  }
}

export {};
