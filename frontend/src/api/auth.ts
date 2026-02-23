/**
 * Auth API functions — device login, PIN login, user profile, PIN verification.
 */

import apiClient from './client';
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
  const { data } = await apiClient.post<ApiResponse<DeviceLoginResponse>>(
    '/auth/device-login',
    { device_fingerprint: deviceFingerprint, device_name: deviceName },
  );
  return data.data!;
}

/** Get the list of active users for the user picker screen. */
export async function getUsers(): Promise<UserPickerItem[]> {
  const { data } = await apiClient.get<ApiResponse<UserPickerItem[]>>(
    '/auth/users',
  );
  return data.data ?? [];
}

/** Step 2: Login with user ID + PIN. */
export async function pinLogin(
  userId: number,
  pin: string,
  deviceFingerprint: string,
  deviceName: string,
): Promise<TokenResponse> {
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
}

/** Get current authenticated user profile with permissions. */
export async function getMe(): Promise<UserProfile> {
  const { data } = await apiClient.get<ApiResponse<UserProfile>>('/auth/me');
  return data.data!;
}

/** Verify PIN for sensitive actions. Returns a short-lived PIN token. */
export async function verifyPin(pin: string): Promise<PinTokenResponse> {
  const { data } = await apiClient.post<ApiResponse<PinTokenResponse>>(
    '/auth/verify-pin',
    { pin },
  );
  return data.data!;
}
