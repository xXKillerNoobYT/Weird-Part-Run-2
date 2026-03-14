/**
 * Shared helpers, constants, and formatters for Sync page components.
 */

// ── Badge variant helpers ────────────────────────────────────────

/** Badge variant for relay event types */
export function relayTypeBadge(type: string): 'success' | 'warning' | 'danger' | 'neutral' | 'default' {
  if (type === 'shop_ack') return 'success';
  if (type === 'shop_delivery') return 'success';
  if (type === 'gossip') return 'neutral';
  if (type === 'handoff') return 'warning';
  return 'default';
}

/** Badge variant for relay package status */
export function packageStatusBadge(status: string): 'success' | 'warning' | 'danger' | 'neutral' | 'default' {
  if (status === 'confirmed') return 'success';
  if (status === 'transferred') return 'neutral';
  if (status === 'created') return 'warning';
  if (status === 'failed') return 'danger';
  return 'default';
}

export function hardSyncStatusVariant(status: string): 'default' | 'success' | 'warning' | 'danger' | 'info' {
  if (status === 'completed') return 'success';
  if (status === 'failed') return 'danger';
  if (status === 'requested' || status === 'package_ready' || status === 'in_progress') return 'warning';
  return 'default';
}

// ── Formatters ───────────────────────────────────────────────────

export function formatDate(iso: string): string {
  try {
    const d = new Date(iso);
    return d.toLocaleString(undefined, {
      month: 'short',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
    });
  } catch {
    return iso;
  }
}

/** Truncate a UUID-style device ID for display -> first 8 chars */
export function truncateId(id: string): string {
  return id.length > 12 ? `${id.slice(0, 8)}…` : id;
}

export function formatBytesCompact(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

export function formatUptimeCompact(seconds: number): string {
  if (seconds < 60) return `${Math.round(seconds)}s`;
  if (seconds < 3600) return `${Math.round(seconds / 60)}m`;
  const h = Math.floor(seconds / 3600);
  const m = Math.round((seconds % 3600) / 60);
  return `${h}h ${m}m`;
}

// ── Constants ────────────────────────────────────────────────────

export const BT_STATE_COLORS: Record<string, string> = {
  connected: 'text-green-600 dark:text-green-400',
  listening: 'text-blue-600 dark:text-blue-400',
  connecting: 'text-yellow-600 dark:text-yellow-400',
  reconnecting: 'text-yellow-600 dark:text-yellow-400',
  idle: 'text-gray-500 dark:text-gray-400',
  stopped: 'text-gray-400 dark:text-gray-500',
  error: 'text-red-600 dark:text-red-400',
};

export const BT_STATE_LABELS: Record<string, string> = {
  connected: 'Connected',
  listening: 'Listening for devices…',
  connecting: 'Connecting…',
  reconnecting: 'Reconnecting…',
  idle: 'Idle',
  stopped: 'Stopped',
  error: 'Error',
};

export const STORAGE_POLICIES = [
  { value: 'active_jobs_core_only', label: 'Active Jobs Only', desc: 'Only store data for currently active jobs' },
  { value: 'all_jobs_core', label: 'All Jobs', desc: 'Store data for all jobs (active, completed, on-hold)' },
  { value: 'minimal', label: 'Minimal', desc: 'Bare minimum — only what\'s needed to operate' },
];

export const MEDIA_POLICIES = [
  { value: 'all_jobs', label: 'All Jobs Media', desc: 'Photos/attachments for all jobs' },
  { value: 'assigned_jobs_only', label: 'Assigned Jobs Only', desc: 'Media only for jobs assigned to this device\'s primary user' },
  { value: 'thumbnails_only', label: 'Thumbnails Only', desc: 'Save bandwidth — only download thumbnails' },
  { value: 'last_n_days', label: 'Recent Only', desc: 'Media from the last N days (see retention setting)' },
  { value: 'none', label: 'No Media', desc: 'Don\'t store media locally (view on demand)' },
];
