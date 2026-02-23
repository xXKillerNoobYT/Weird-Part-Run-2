/**
 * Axios API client with token management.
 *
 * All API calls go through this client. It:
 * 1. Sets the Authorization header from the auth store
 * 2. Unwraps the ApiResponse envelope
 * 3. Handles 401 errors (token expired → redirect to login)
 */

import axios from 'axios';
import { API_BASE_URL } from '../lib/constants';

const apiClient = axios.create({
  baseURL: API_BASE_URL,
  headers: {
    'Content-Type': 'application/json',
  },
});

// ── Request Interceptor: Attach JWT Token ──────────────────────────
apiClient.interceptors.request.use((config) => {
  const token = localStorage.getItem('wiredpart_token');
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
});

// ── Response Interceptor: Handle Auth Errors ───────────────────────
apiClient.interceptors.response.use(
  (response) => response,
  (error) => {
    if (error.response?.status === 401) {
      // Token expired or invalid — clear auth state
      localStorage.removeItem('wiredpart_token');
      // The auth store will detect this and show the login screen
      window.dispatchEvent(new CustomEvent('auth:expired'));
    }
    return Promise.reject(error);
  },
);

export default apiClient;
