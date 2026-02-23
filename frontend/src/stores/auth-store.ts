/**
 * Auth store — manages authentication state via Zustand.
 *
 * This store tracks:
 * - Whether the user is authenticated
 * - The current user profile (with hats & permissions)
 * - Auth loading states
 *
 * The token itself is stored in localStorage (for persistence across reloads).
 * The store reads it on initialization and validates it with the backend.
 */

import { create } from 'zustand';
import type { UserProfile } from '../lib/types';
import { getMe } from '../api/auth';

interface AuthState {
  /** Current authenticated user (null if not logged in) */
  user: UserProfile | null;
  /** Whether auth check is in progress */
  isLoading: boolean;
  /** Whether the user is authenticated */
  isAuthenticated: boolean;

  /** Set the JWT token and fetch the user profile */
  login: (token: string) => Promise<void>;
  /** Clear auth state and token */
  logout: () => void;
  /** Check if the stored token is still valid */
  checkAuth: () => Promise<void>;
  /** Check if the user has a specific permission */
  hasPermission: (key: string) => boolean;
  /** Check if the user has ALL of the specified permissions */
  hasAllPermissions: (...keys: string[]) => boolean;
  /** Check if the user has ANY of the specified permissions */
  hasAnyPermission: (...keys: string[]) => boolean;
}

export const useAuthStore = create<AuthState>((set, get) => ({
  user: null,
  isLoading: false,
  isAuthenticated: false,

  login: async (token: string) => {
    localStorage.setItem('wiredpart_token', token);
    set({ isLoading: true });

    try {
      const user = await getMe();
      set({ user, isAuthenticated: true, isLoading: false });
    } catch {
      localStorage.removeItem('wiredpart_token');
      set({ user: null, isAuthenticated: false, isLoading: false });
    }
  },

  logout: () => {
    localStorage.removeItem('wiredpart_token');
    set({ user: null, isAuthenticated: false, isLoading: false });
  },

  checkAuth: async () => {
    const token = localStorage.getItem('wiredpart_token');
    if (!token) {
      set({ user: null, isAuthenticated: false, isLoading: false });
      return;
    }

    set({ isLoading: true });
    try {
      const user = await getMe();
      set({ user, isAuthenticated: true, isLoading: false });
    } catch {
      localStorage.removeItem('wiredpart_token');
      set({ user: null, isAuthenticated: false, isLoading: false });
    }
  },

  hasPermission: (key: string) => {
    const { user } = get();
    return user?.permissions?.includes(key) ?? false;
  },

  hasAllPermissions: (...keys: string[]) => {
    const { user } = get();
    if (!user?.permissions) return false;
    return keys.every((k) => user.permissions.includes(k));
  },

  hasAnyPermission: (...keys: string[]) => {
    const { user } = get();
    if (!user?.permissions) return false;
    return keys.some((k) => user.permissions.includes(k));
  },
}));

// Listen for token expiration events from the API client
if (typeof window !== 'undefined') {
  window.addEventListener('auth:expired', () => {
    useAuthStore.getState().logout();
  });
}
