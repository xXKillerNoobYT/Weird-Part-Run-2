/**
 * Auth API functions — device login, PIN login, user profile, PIN verification.
 *
 * On browser: routes to FastAPI via HTTP (existing behavior)
 * On Capacitor: routes to local TS auth service + SQLite
 */

import apiClient from './client';
import { adaptedRequest } from './adapter';
import type {
  ApiResponse,
  DeviceLoginResponse,
  PinTokenResponse,
  TokenResponse,
  UserPickerItem,
  UserProfile,
} from '../lib/types';

/** Step 1: Attempt auto-login by device fingerprint. */
export async function deviceLogin(
  deviceFingerprint: string,
  deviceName: string,
): Promise<DeviceLoginResponse> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<DeviceLoginResponse>>(
        '/auth/device-login',
        { device_fingerprint: deviceFingerprint, device_name: deviceName },
      );
      return data.data!;
    },
    // On Capacitor, no auto-login concept — always show user picker
    async () => ({
      auto_login: false,
      token: null,
      requires_user_selection: true,
      is_public_device: true,
      device_id: null,
    }),
  );
}

/** Get the list of active users for the user picker screen. */
export async function getUsers(): Promise<UserPickerItem[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<UserPickerItem[]>>(
        '/auth/users',
      );
      return data.data ?? [];
    },
    async () => {
      const { getActiveUsers, getUserHatNames } = await import(
        '../local/services/auth-service'
      );
      const users = await getActiveUsers();
      const items: UserPickerItem[] = [];
      for (const u of users) {
        const hats = await getUserHatNames(u.id);
        items.push({
          id: u.id,
          display_name: u.display_name,
          avatar_url: u.avatar_url,
          hats,
        });
      }
      return items;
    },
  );
}

/** Step 2: Login with user ID + PIN. */
export async function pinLogin(
  userId: number,
  pin: string,
  deviceFingerprint: string,
  deviceName: string,
): Promise<TokenResponse> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<TokenResponse>>(
        '/auth/pin-login',
        {
          user_id: userId,
          pin,
          device_fingerprint: deviceFingerprint,
          device_name: deviceName,
        },
      );
      return data.data!;
    },
    async () => {
      const { authenticateByPin } = await import(
        '../local/services/auth-service'
      );
      const result = await authenticateByPin(userId, pin);
      if (!result.success || !result.token) {
<<<<<<< Updated upstream
<<<<<<< Updated upstream
<<<<<<< Updated upstream
=======
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
>>>>>>> Stashed changes
=======
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
>>>>>>> Stashed changes
=======
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
>>>>>>> Stashed changes
        const err: any = new Error(result.message);
        err.response = { data: { detail: result.message } };
        throw err;
      }
      return {
        access_token: result.token,
        token_type: 'bearer',
        expires_in: 86400,
      };
    },
  );
}

/** Get current authenticated user profile with permissions. */
export async function getMe(): Promise<UserProfile> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<UserProfile>>(
        '/auth/me',
      );
      return data.data!;
    },
    async () => {
      const { getLocalUserProfile } = await import(
        '../local/services/auth-service'
      );
      const token = localStorage.getItem('wiredpart_token');
      if (!token) throw new Error('No token');
      return getLocalUserProfile(token);
    },
  );
}

/** Verify PIN for sensitive actions. Returns a short-lived PIN token. */
export async function verifyPin(pin: string): Promise<PinTokenResponse> {
  // Remains HTTP-only — sensitive actions are shop-only
  const { data } = await apiClient.post<ApiResponse<PinTokenResponse>>(
    '/auth/verify-pin',
    { pin },
  );
  return data.data!;
}
