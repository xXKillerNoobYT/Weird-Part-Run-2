/**
 * About / Version page — shows app version, build info, and system stats.
 */

import { useQuery } from '@tanstack/react-query';
import { Info, Server, Database, Monitor } from 'lucide-react';
import apiClient from '../../../api/client';
import type { ApiResponse } from '../../../lib/types';
import { getPlatform } from '../../../lib/environment';

// App version — single source of truth
const APP_VERSION = '1.0.0';
const APP_NAME = 'Wired Part';

interface SystemInfo {
  db_tables: number;
  db_size_mb: number;
  active_users: number;
  total_jobs: number;
  total_parts: number;
  total_tools: number;
  uptime_seconds: number;
}

function useSystemInfo() {
  return useQuery({
    queryKey: ['system-info'],
    queryFn: async () => {
      try {
        const { data } = await apiClient.get<ApiResponse<SystemInfo>>(
          '/settings/system-info',
        );
        return data.data;
      } catch {
        return null;
      }
    },
    staleTime: 60_000,
  });
}

function formatUptime(seconds: number): string {
  const days = Math.floor(seconds / 86400);
  const hours = Math.floor((seconds % 86400) / 3600);
  const mins = Math.floor((seconds % 3600) / 60);
  if (days > 0) return `${days}d ${hours}h ${mins}m`;
  if (hours > 0) return `${hours}h ${mins}m`;
  return `${mins}m`;
}

export default function AboutPage() {
  const { data: info } = useSystemInfo();
  const plat = getPlatform();
  const platform = plat === 'web' ? 'Browser' : `Native (${plat})`;

  return (
    <div className="max-w-2xl mx-auto space-y-6">
      {/* App Identity */}
      <div className="bg-surface rounded-lg border border-border p-6 text-center">
        <div className="inline-flex items-center justify-center w-16 h-16 rounded-2xl bg-blue-500/10 mb-4">
          <Info className="h-8 w-8 text-blue-500" />
        </div>
        <h1 className="text-2xl font-bold text-gray-900 dark:text-white">
          {APP_NAME}
        </h1>
        <p className="text-sm text-gray-500 dark:text-gray-400 mt-1">
          Version {APP_VERSION}
        </p>
        <p className="text-xs text-gray-400 dark:text-gray-500 mt-2">
          Electrical supply inventory &amp; workforce management
        </p>
      </div>

      {/* Platform Info */}
      <div className="bg-surface rounded-lg border border-border p-4">
        <h2 className="text-sm font-semibold text-gray-700 dark:text-gray-300 mb-3 flex items-center gap-2">
          <Monitor className="h-4 w-4" />
          Platform
        </h2>
        <dl className="grid grid-cols-2 gap-y-2 text-sm">
          <dt className="text-gray-500 dark:text-gray-400">Client</dt>
          <dd className="text-gray-900 dark:text-white font-medium">{platform}</dd>
          <dt className="text-gray-500 dark:text-gray-400">User Agent</dt>
          <dd className="text-gray-900 dark:text-white font-medium truncate text-xs">
            {navigator.userAgent.split('(')[0].trim()}
          </dd>
        </dl>
      </div>

      {/* System Stats */}
      {info && (
        <div className="bg-surface rounded-lg border border-border p-4">
          <h2 className="text-sm font-semibold text-gray-700 dark:text-gray-300 mb-3 flex items-center gap-2">
            <Server className="h-4 w-4" />
            Shop Server
          </h2>
          <dl className="grid grid-cols-2 gap-y-2 text-sm">
            <dt className="text-gray-500 dark:text-gray-400">Uptime</dt>
            <dd className="text-gray-900 dark:text-white font-medium">
              {formatUptime(info.uptime_seconds)}
            </dd>
            <dt className="text-gray-500 dark:text-gray-400">Database Size</dt>
            <dd className="text-gray-900 dark:text-white font-medium">
              {info.db_size_mb.toFixed(1)} MB
            </dd>
            <dt className="text-gray-500 dark:text-gray-400">Tables</dt>
            <dd className="text-gray-900 dark:text-white font-medium">{info.db_tables}</dd>
          </dl>
        </div>
      )}

      {info && (
        <div className="bg-surface rounded-lg border border-border p-4">
          <h2 className="text-sm font-semibold text-gray-700 dark:text-gray-300 mb-3 flex items-center gap-2">
            <Database className="h-4 w-4" />
            Data Counts
          </h2>
          <dl className="grid grid-cols-2 gap-y-2 text-sm">
            <dt className="text-gray-500 dark:text-gray-400">Active Users</dt>
            <dd className="text-gray-900 dark:text-white font-medium">{info.active_users}</dd>
            <dt className="text-gray-500 dark:text-gray-400">Jobs</dt>
            <dd className="text-gray-900 dark:text-white font-medium">{info.total_jobs}</dd>
            <dt className="text-gray-500 dark:text-gray-400">Parts Catalog</dt>
            <dd className="text-gray-900 dark:text-white font-medium">{info.total_parts}</dd>
            <dt className="text-gray-500 dark:text-gray-400">Tools</dt>
            <dd className="text-gray-900 dark:text-white font-medium">{info.total_tools}</dd>
          </dl>
        </div>
      )}

      {/* Footer */}
      <p className="text-center text-xs text-gray-400 dark:text-gray-500 pb-4">
        Built with React + SQLite + Tauri
      </p>
    </div>
  );
}
