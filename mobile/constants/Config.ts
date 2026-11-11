/**
 * Global Configuration for CircleGuard Mobile.
 *
 * Web: runtime URLs from window.__CG_CONFIG__.
 * Native: preserves the existing local development URLs.
 */

import { Platform } from 'react-native';

type ApiConfig = {
  AUTH_BASE_URL?: string;
  DASHBOARD_BASE_URL?: string;
  FILE_BASE_URL?: string;
  FORM_BASE_URL?: string;
  GATEWAY_BASE_URL?: string;
  IDENTITY_BASE_URL?: string;
  NOTIFICATION_BASE_URL?: string;
  PROMOTION_BASE_URL?: string;
};

const runtime: ApiConfig =
  Platform.OS === 'web' && typeof window !== 'undefined'
    ? (
        (window as typeof window & {
          __CG_CONFIG__?: ApiConfig;
        }).__CG_CONFIG__ ?? {}
      )
    : {};

function api(
  name: keyof ApiConfig,
  webPath: string,
  nativeLocal: string
): string {
  return Platform.OS === 'web'
    ? (runtime[name] || webPath)
    : nativeLocal;
}

export const AUTH_BASE_URL = api(
  'AUTH_BASE_URL',
  '/auth',
  'http://localhost:8180'
);

export const DASHBOARD_BASE_URL = api(
  'DASHBOARD_BASE_URL',
  '/dashboard',
  'http://localhost:8084'
);

export const FILE_BASE_URL = api(
  'FILE_BASE_URL',
  '/file',
  'http://localhost:8085'
);

export const FORM_BASE_URL = api(
  'FORM_BASE_URL',
  '/form',
  'http://localhost:8086'
);

export const GATEWAY_BASE_URL = api(
  'GATEWAY_BASE_URL',
  '/gateway',
  'http://localhost:8087'
);

export const IDENTITY_BASE_URL = api(
  'IDENTITY_BASE_URL',
  '/identity',
  'http://localhost:8083'
);

export const NOTIFICATION_BASE_URL = api(
  'NOTIFICATION_BASE_URL',
  '/notification',
  'http://localhost:8082'
);

export const PROMOTION_BASE_URL = api(
  'PROMOTION_BASE_URL',
  '/promotion',
  'http://localhost:8088'
);

export const API_BASE_URL = GATEWAY_BASE_URL;
