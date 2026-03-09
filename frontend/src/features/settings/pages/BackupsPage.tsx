/**
 * BackupsPage — automatic backup management for database and application.
 *
 * Two independent backup systems:
 *   1. Database backup — hot-copy via sqlite3.backup(), safe with WAL mode
 *   2. App backup — zip archive of backend code (excludes venv/cache/logs)
 *
 * Each has:
 *   - Enable/disable toggle
 *   - Scheduled time (hour:minute)
 *   - Retention count (how many to keep)
 *   - Manual "Backup Now" trigger
 *   - List of existing backups with download, restore (db only), delete
 *
 * Settings are persisted under the "backup" category via the settings API.
 */

import { useState, useEffect } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  Database, Archive, Clock, Trash2, Download, RotateCcw,
  Loader2, Save, HardDrive, FolderOpen, Shield, Info,
  AlertTriangle, CheckCircle, X,
} from 'lucide-react';
import { Button } from '../../../components/ui/Button';
import { Card, CardHeader } from '../../../components/ui/Card';
import { toast } from '../../../lib/toast';
import {
  getBackupSettings,
  updateBackupSettings,
  listBackups,
  triggerBackup,
  deleteBackup,
  restoreBackup,
  downloadBackup,
} from '../../../api/backups';
import type { BackupRecord, BackupSettings } from '../../../api/backups';


// ── Toggle switch (same as AiConfigPage) ─────────────────────────

function Toggle({
  checked, onChange, disabled = false,
}: {
  checked: boolean;
  onChange: (v: boolean) => void;
  disabled?: boolean;
}) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={checked}
      disabled={disabled}
      onClick={() => onChange(!checked)}
      className={`relative inline-flex h-6 w-11 flex-shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 focus:outline-none focus:ring-2 focus:ring-primary focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50 ${
        checked ? 'bg-green-500' : 'bg-gray-200 dark:bg-gray-700'
      }`}
    >
      <span
        className={`pointer-events-none inline-block h-5 w-5 rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out ${
          checked ? 'translate-x-5' : 'translate-x-0'
        }`}
      />
    </button>
  );
}


// ── Confirm Dialog ───────────────────────────────────────────────

function ConfirmDialog({
  open,
  title,
  children,
  confirmLabel = 'Confirm',
  confirmVariant = 'primary',
  loading = false,
  onConfirm,
  onCancel,
}: {
  open: boolean;
  title: string;
  children: React.ReactNode;
  confirmLabel?: string;
  confirmVariant?: 'primary' | 'danger';
  loading?: boolean;
  onConfirm: () => void;
  onCancel: () => void;
}) {
  if (!open) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
      {/* Backdrop */}
      <div className="absolute inset-0 bg-black/50" onClick={onCancel} />
      {/* Dialog */}
      <div className="relative bg-white dark:bg-gray-800 rounded-xl shadow-xl max-w-md w-full p-5 space-y-4">
        <div className="flex items-start justify-between">
          <h3 className="text-base font-semibold text-gray-900 dark:text-gray-100">
            {title}
          </h3>
          <button
            onClick={onCancel}
            className="p-1 rounded-md text-gray-400 hover:text-gray-600 dark:hover:text-gray-300"
          >
            <X className="h-4 w-4" />
          </button>
        </div>
        <div className="text-sm text-gray-600 dark:text-gray-300 space-y-2">
          {children}
        </div>
        <div className="flex items-center justify-end gap-2 pt-1">
          <Button size="sm" variant="secondary" onClick={onCancel} disabled={loading}>
            Cancel
          </Button>
          <Button
            size="sm"
            variant={confirmVariant === 'danger' ? 'danger' : 'primary'}
            onClick={onConfirm}
            disabled={loading}
            icon={loading ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : undefined}
          >
            {confirmLabel}
          </Button>
        </div>
      </div>
    </div>
  );
}


// ── Helpers ──────────────────────────────────────────────────────

function formatBytes(bytes: number | null): string {
  if (bytes === null || bytes === undefined) return '—';
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

function formatDate(dateStr: string | null): string {
  if (!dateStr) return '—';
  try {
    const d = new Date(dateStr + 'Z'); // UTC from SQLite
    return d.toLocaleString();
  } catch {
    return dateStr;
  }
}

/** Generate hour options for the time picker. */
function hourOptions(): { value: number; label: string }[] {
  return Array.from({ length: 24 }, (_, i) => ({
    value: i,
    label: i.toString().padStart(2, '0'),
  }));
}

/** Generate minute options (every 15 min). */
function minuteOptions(): { value: number; label: string }[] {
  return [0, 15, 30, 45].map((m) => ({
    value: m,
    label: m.toString().padStart(2, '0'),
  }));
}

const RETENTION_OPTIONS = [3, 5, 7, 14, 30];


// ── Main Page ────────────────────────────────────────────────────

export function BackupsPage() {
  const queryClient = useQueryClient();

  // ── Settings query ──────────────────────────────────────────────
  const { data: settings, isLoading: loadingSettings } = useQuery({
    queryKey: ['backup-settings'],
    queryFn: getBackupSettings,
    staleTime: 60_000,
  });

  // ── Backup lists ────────────────────────────────────────────────
  const { data: dbBackups = [], isLoading: loadingDb } = useQuery({
    queryKey: ['backups', 'db'],
    queryFn: () => listBackups('db'),
    staleTime: 30_000,
  });

  const { data: appBackups = [], isLoading: loadingApp } = useQuery({
    queryKey: ['backups', 'app'],
    queryFn: () => listBackups('app'),
    staleTime: 30_000,
  });

  // ── Local form state ────────────────────────────────────────────
  const [form, setForm] = useState<BackupSettings | null>(null);
  const [saving, setSaving] = useState(false);

  // ── Restore dialog state ────────────────────────────────────────
  const [restoreTarget, setRestoreTarget] = useState<BackupRecord | null>(null);
  const [deleteTarget, setDeleteTarget] = useState<BackupRecord | null>(null);
  const [restoreBanner, setRestoreBanner] = useState<{ from: string; safety: string } | null>(null);

  useEffect(() => {
    if (settings) setForm(settings);
  }, [settings]);

  // ── Mutations ───────────────────────────────────────────────────
  const triggerMutation = useMutation({
    mutationFn: (type: 'db' | 'app') => triggerBackup(type),
    onSuccess: (_data, type) => {
      toast.success(`${type === 'db' ? 'Database' : 'App'} backup complete`);
      queryClient.invalidateQueries({ queryKey: ['backups', type] });
    },
    onError: (_err, type) => {
      toast.error(`${type === 'db' ? 'Database' : 'App'} backup failed`);
    },
  });

  const deleteMutation = useMutation({
    mutationFn: (id: number) => deleteBackup(id),
    onSuccess: () => {
      toast.success('Backup deleted');
      setDeleteTarget(null);
      queryClient.invalidateQueries({ queryKey: ['backups'] });
    },
    onError: () => toast.error('Failed to delete backup'),
  });

  const restoreMutation = useMutation({
    mutationFn: (id: number) => restoreBackup(id),
    onSuccess: (result) => {
      setRestoreTarget(null);
      setRestoreBanner({
        from: result.restored_from,
        safety: result.safety_backup,
      });
      queryClient.invalidateQueries({ queryKey: ['backups'] });
    },
    onError: () => {
      toast.error('Restore failed');
      setRestoreTarget(null);
    },
  });

  // ── Save handler ────────────────────────────────────────────────
  const handleSave = async () => {
    if (!form) return;
    setSaving(true);
    try {
      await updateBackupSettings({
        db_enabled: form.backup_db_enabled,
        db_hour: form.backup_db_hour,
        db_minute: form.backup_db_minute,
        db_retention: form.backup_db_retention,
        app_enabled: form.backup_app_enabled,
        app_hour: form.backup_app_hour,
        app_minute: form.backup_app_minute,
        app_retention: form.backup_app_retention,
        backup_dir: form.backup_dir,
        backup_before_update: form.backup_before_update,
      });
      toast.success('Backup settings saved');
      queryClient.invalidateQueries({ queryKey: ['backup-settings'] });
    } catch {
      toast.error('Failed to save backup settings');
    } finally {
      setSaving(false);
    }
  };

  const updateForm = <K extends keyof BackupSettings>(key: K, val: BackupSettings[K]) => {
    setForm((prev) => prev ? { ...prev, [key]: val } : prev);
  };

  // ── Download handler ────────────────────────────────────────────
  const handleDownload = async (backup: BackupRecord) => {
    try {
      await downloadBackup(backup.id, backup.file_name);
      toast.success('Download started');
    } catch {
      toast.error('Download failed');
    }
  };

  // ── Loading state ───────────────────────────────────────────────
  if (loadingSettings || !form) {
    return (
      <div className="flex items-center justify-center py-16">
        <Loader2 className="h-6 w-6 animate-spin text-gray-400" />
      </div>
    );
  }

  return (
    <div className="space-y-5 max-w-2xl">
      {/* Header */}
      <div className="flex items-start justify-between flex-wrap gap-3">
        <div>
          <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-100">
            Backup Management
          </h2>
          <p className="text-sm text-gray-500 dark:text-gray-400 mt-0.5">
            Automatic database and application backups. All data stays on this computer.
          </p>
        </div>
      </div>

      {/* Post-restore banner */}
      {restoreBanner && (
        <div className="flex items-start gap-3 p-3 rounded-xl bg-amber-50 dark:bg-amber-900/20 border border-amber-300 dark:border-amber-700">
          <AlertTriangle className="h-5 w-5 text-amber-600 dark:text-amber-400 mt-0.5 flex-shrink-0" />
          <div className="flex-1 min-w-0">
            <p className="text-sm font-semibold text-amber-800 dark:text-amber-200">
              Database Restored — Restart Required
            </p>
            <p className="text-sm text-amber-700 dark:text-amber-300 mt-1">
              Restored from <strong className="font-mono text-xs">{restoreBanner.from}</strong>.
              A safety backup was created first: <strong className="font-mono text-xs">{restoreBanner.safety}</strong>.
            </p>
            <p className="text-sm text-amber-700 dark:text-amber-300 mt-1">
              The server must be restarted for changes to take effect.
              The current session will continue using the old data until restart.
            </p>
          </div>
          <button
            onClick={() => setRestoreBanner(null)}
            className="p-1 rounded-md text-amber-400 hover:text-amber-600 dark:hover:text-amber-300"
          >
            <X className="h-4 w-4" />
          </button>
        </div>
      )}

      {/* Info banner */}
      <div className="flex items-start gap-3 p-3 rounded-xl bg-blue-50 dark:bg-blue-900/20 border border-blue-200 dark:border-blue-700">
        <Shield className="h-4 w-4 text-blue-600 dark:text-blue-400 mt-0.5 flex-shrink-0" />
        <p className="text-sm text-blue-700 dark:text-blue-300">
          <strong>Database backups</strong> use SQLite&apos;s safe hot-copy method — no downtime required.{' '}
          <strong>App backups</strong> archive the application code for disaster recovery.
          Both run automatically at the scheduled time.
        </p>
      </div>

      {/* ── Database Backup Section ─────────────────────────────── */}
      <Card>
        <CardHeader
          title="Database Backups"
          subtitle="Automatic daily snapshots of your entire database"
          action={<Database className="h-4 w-4 text-gray-400 dark:text-gray-500" />}
        />
        <div className="px-4 pb-4 space-y-4">
          {/* Enable toggle */}
          <div className="flex items-center justify-between gap-4">
            <div className="flex items-center gap-3">
              <div className="p-2 rounded-lg bg-green-100 dark:bg-green-900/30">
                <HardDrive className="h-4 w-4 text-green-600 dark:text-green-400" />
              </div>
              <div>
                <p className="text-sm font-medium text-gray-900 dark:text-gray-100">
                  Enable Auto Backup
                </p>
                <p className="text-xs text-gray-500 dark:text-gray-400 mt-0.5">
                  Daily database backup at the scheduled time
                </p>
              </div>
            </div>
            <Toggle
              checked={form.backup_db_enabled}
              onChange={(v) => updateForm('backup_db_enabled', v)}
            />
          </div>

          {/* Schedule row */}
          <div className={`flex flex-wrap items-center gap-3 ${!form.backup_db_enabled ? 'opacity-50' : ''}`}>
            <div className="flex items-center gap-1.5">
              <Clock className="h-3.5 w-3.5 text-gray-400" />
              <span className="text-xs font-medium text-gray-700 dark:text-gray-300">Time:</span>
            </div>
            <select
              value={form.backup_db_hour}
              onChange={(e) => updateForm('backup_db_hour', Number(e.target.value))}
              disabled={!form.backup_db_enabled}
              className="rounded-lg border border-border bg-surface px-2 py-1.5 text-sm text-gray-900 dark:text-gray-100"
            >
              {hourOptions().map((o) => (
                <option key={o.value} value={o.value}>{o.label}</option>
              ))}
            </select>
            <span className="text-gray-500 dark:text-gray-400 text-sm">:</span>
            <select
              value={form.backup_db_minute}
              onChange={(e) => updateForm('backup_db_minute', Number(e.target.value))}
              disabled={!form.backup_db_enabled}
              className="rounded-lg border border-border bg-surface px-2 py-1.5 text-sm text-gray-900 dark:text-gray-100"
            >
              {minuteOptions().map((o) => (
                <option key={o.value} value={o.value}>{o.label}</option>
              ))}
            </select>

            <div className="flex items-center gap-1.5 ml-4">
              <span className="text-xs font-medium text-gray-700 dark:text-gray-300">Keep:</span>
            </div>
            <select
              value={form.backup_db_retention}
              onChange={(e) => updateForm('backup_db_retention', Number(e.target.value))}
              disabled={!form.backup_db_enabled}
              className="rounded-lg border border-border bg-surface px-2 py-1.5 text-sm text-gray-900 dark:text-gray-100"
            >
              {RETENTION_OPTIONS.map((n) => (
                <option key={n} value={n}>{n} backups</option>
              ))}
            </select>
          </div>

          {/* Manual trigger */}
          <div className="flex items-center justify-between gap-3 pt-1">
            <p className="text-xs text-gray-400 dark:text-gray-500">
              {dbBackups.length} backup{dbBackups.length !== 1 ? 's' : ''} on file
            </p>
            <Button
              size="sm"
              variant="secondary"
              onClick={() => triggerMutation.mutate('db')}
              disabled={triggerMutation.isPending}
              icon={triggerMutation.isPending
                ? <Loader2 className="h-3.5 w-3.5 animate-spin" />
                : <Download className="h-3.5 w-3.5" />
              }
            >
              <span className="hidden sm:inline">Backup Now</span>
              <span className="sm:hidden">Backup</span>
            </Button>
          </div>

          {/* Backup list */}
          {loadingDb ? (
            <div className="flex justify-center py-4">
              <Loader2 className="h-4 w-4 animate-spin text-gray-400" />
            </div>
          ) : dbBackups.length > 0 ? (
            <div className="border border-border rounded-lg overflow-hidden">
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead>
                    <tr className="bg-surface-secondary text-left">
                      <th className="px-3 py-2 text-xs font-medium text-gray-500 dark:text-gray-400">File</th>
                      <th className="px-3 py-2 text-xs font-medium text-gray-500 dark:text-gray-400">Size</th>
                      <th className="px-3 py-2 text-xs font-medium text-gray-500 dark:text-gray-400">Date</th>
                      <th className="px-3 py-2 text-xs font-medium text-gray-500 dark:text-gray-400 text-right">Actions</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-border">
                    {dbBackups.map((b) => (
                      <BackupRow
                        key={b.id}
                        backup={b}
                        showRestore
                        onRestore={() => setRestoreTarget(b)}
                        onDownload={() => handleDownload(b)}
                        onDelete={() => setDeleteTarget(b)}
                        restoring={restoreMutation.isPending}
                        deleting={deleteMutation.isPending}
                      />
                    ))}
                  </tbody>
                </table>
              </div>
            </div>
          ) : null}
        </div>
      </Card>

      {/* ── App Backup Section ──────────────────────────────────── */}
      <Card>
        <CardHeader
          title="Application Backups"
          subtitle="Archive the app code for disaster recovery"
          action={<Archive className="h-4 w-4 text-gray-400 dark:text-gray-500" />}
        />
        <div className="px-4 pb-4 space-y-4">
          {/* Enable toggle */}
          <div className="flex items-center justify-between gap-4">
            <div className="flex items-center gap-3">
              <div className="p-2 rounded-lg bg-violet-100 dark:bg-violet-900/30">
                <Archive className="h-4 w-4 text-violet-600 dark:text-violet-400" />
              </div>
              <div>
                <p className="text-sm font-medium text-gray-900 dark:text-gray-100">
                  Enable Auto Backup
                </p>
                <p className="text-xs text-gray-500 dark:text-gray-400 mt-0.5">
                  Daily zip archive of the application code
                </p>
              </div>
            </div>
            <Toggle
              checked={form.backup_app_enabled}
              onChange={(v) => updateForm('backup_app_enabled', v)}
            />
          </div>

          {/* Schedule row */}
          <div className={`flex flex-wrap items-center gap-3 ${!form.backup_app_enabled ? 'opacity-50' : ''}`}>
            <div className="flex items-center gap-1.5">
              <Clock className="h-3.5 w-3.5 text-gray-400" />
              <span className="text-xs font-medium text-gray-700 dark:text-gray-300">Time:</span>
            </div>
            <select
              value={form.backup_app_hour}
              onChange={(e) => updateForm('backup_app_hour', Number(e.target.value))}
              disabled={!form.backup_app_enabled}
              className="rounded-lg border border-border bg-surface px-2 py-1.5 text-sm text-gray-900 dark:text-gray-100"
            >
              {hourOptions().map((o) => (
                <option key={o.value} value={o.value}>{o.label}</option>
              ))}
            </select>
            <span className="text-gray-500 dark:text-gray-400 text-sm">:</span>
            <select
              value={form.backup_app_minute}
              onChange={(e) => updateForm('backup_app_minute', Number(e.target.value))}
              disabled={!form.backup_app_enabled}
              className="rounded-lg border border-border bg-surface px-2 py-1.5 text-sm text-gray-900 dark:text-gray-100"
            >
              {minuteOptions().map((o) => (
                <option key={o.value} value={o.value}>{o.label}</option>
              ))}
            </select>

            <div className="flex items-center gap-1.5 ml-4">
              <span className="text-xs font-medium text-gray-700 dark:text-gray-300">Keep:</span>
            </div>
            <select
              value={form.backup_app_retention}
              onChange={(e) => updateForm('backup_app_retention', Number(e.target.value))}
              disabled={!form.backup_app_enabled}
              className="rounded-lg border border-border bg-surface px-2 py-1.5 text-sm text-gray-900 dark:text-gray-100"
            >
              {RETENTION_OPTIONS.map((n) => (
                <option key={n} value={n}>{n} backups</option>
              ))}
            </select>
          </div>

          {/* Auto backup before updates */}
          <div className="flex items-center justify-between gap-4">
            <div className="flex items-center gap-3">
              <div className="p-2 rounded-lg bg-amber-100 dark:bg-amber-900/30">
                <Shield className="h-4 w-4 text-amber-600 dark:text-amber-400" />
              </div>
              <div>
                <p className="text-sm font-medium text-gray-900 dark:text-gray-100">
                  Backup Before Updates
                </p>
                <p className="text-xs text-gray-500 dark:text-gray-400 mt-0.5">
                  Automatically create a backup before applying system updates
                </p>
              </div>
            </div>
            <Toggle
              checked={form.backup_before_update}
              onChange={(v) => updateForm('backup_before_update', v)}
            />
          </div>

          {/* Manual trigger */}
          <div className="flex items-center justify-between gap-3 pt-1">
            <p className="text-xs text-gray-400 dark:text-gray-500">
              {appBackups.length} backup{appBackups.length !== 1 ? 's' : ''} on file
            </p>
            <Button
              size="sm"
              variant="secondary"
              onClick={() => triggerMutation.mutate('app')}
              disabled={triggerMutation.isPending}
              icon={triggerMutation.isPending
                ? <Loader2 className="h-3.5 w-3.5 animate-spin" />
                : <Download className="h-3.5 w-3.5" />
              }
            >
              <span className="hidden sm:inline">Backup Now</span>
              <span className="sm:hidden">Backup</span>
            </Button>
          </div>

          {/* Info about app restore */}
          <div className="flex items-start gap-2 p-2.5 rounded-lg bg-gray-50 dark:bg-gray-800/50 border border-gray-200 dark:border-gray-700">
            <Info className="h-3.5 w-3.5 text-gray-400 mt-0.5 flex-shrink-0" />
            <div className="text-xs text-gray-500 dark:text-gray-400 space-y-1">
              <p className="font-medium text-gray-600 dark:text-gray-300">To restore an app backup:</p>
              <ol className="list-decimal list-inside space-y-0.5 pl-1">
                <li>Download the backup zip file using the download button below</li>
                <li>Stop the server</li>
                <li>Extract the zip over the <code className="px-1 py-0.5 rounded bg-gray-200 dark:bg-gray-700 text-xs">backend/</code> directory</li>
                <li>Restart the server</li>
              </ol>
            </div>
          </div>

          {/* Backup list */}
          {loadingApp ? (
            <div className="flex justify-center py-4">
              <Loader2 className="h-4 w-4 animate-spin text-gray-400" />
            </div>
          ) : appBackups.length > 0 ? (
            <div className="border border-border rounded-lg overflow-hidden">
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead>
                    <tr className="bg-surface-secondary text-left">
                      <th className="px-3 py-2 text-xs font-medium text-gray-500 dark:text-gray-400">File</th>
                      <th className="px-3 py-2 text-xs font-medium text-gray-500 dark:text-gray-400">Size</th>
                      <th className="px-3 py-2 text-xs font-medium text-gray-500 dark:text-gray-400">Date</th>
                      <th className="px-3 py-2 text-xs font-medium text-gray-500 dark:text-gray-400 text-right">Actions</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-border">
                    {appBackups.map((b) => (
                      <BackupRow
                        key={b.id}
                        backup={b}
                        showRestore={false}
                        onDownload={() => handleDownload(b)}
                        onDelete={() => setDeleteTarget(b)}
                        deleting={deleteMutation.isPending}
                      />
                    ))}
                  </tbody>
                </table>
              </div>
            </div>
          ) : null}
        </div>
      </Card>

      {/* ── Backup Directory ────────────────────────────────────── */}
      <Card>
        <CardHeader
          title="Storage Location"
          subtitle="Where backups are saved on disk"
          action={<FolderOpen className="h-4 w-4 text-gray-400 dark:text-gray-500" />}
        />
        <div className="px-4 pb-4">
          <label className="block text-xs font-medium text-gray-700 dark:text-gray-300 mb-1">
            Backup Directory
          </label>
          <input
            type="text"
            value={form.backup_dir}
            onChange={(e) => updateForm('backup_dir', e.target.value)}
            placeholder="backend/backups/ (default)"
            className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm text-gray-900 dark:text-gray-100 placeholder:text-gray-400 dark:placeholder:text-gray-500 focus:ring-2 focus:ring-primary focus:border-primary"
          />
          <p className="text-xs text-gray-400 dark:text-gray-500 mt-1">
            Leave empty for the default location. Relative paths resolve from the backend directory.
          </p>
        </div>
      </Card>

      {/* Save button */}
      <div className="flex items-center justify-end pt-1">
        <Button
          variant="primary"
          onClick={handleSave}
          disabled={saving}
          icon={saving
            ? <Loader2 className="h-4 w-4 animate-spin" />
            : <Save className="h-4 w-4" />
          }
        >
          {saving ? 'Saving…' : 'Save Settings'}
        </Button>
      </div>

      {/* ── Restore Confirmation Dialog ─────────────────────────── */}
      <ConfirmDialog
        open={restoreTarget !== null}
        title="Restore Database Backup"
        confirmLabel="Restore Database"
        confirmVariant="danger"
        loading={restoreMutation.isPending}
        onConfirm={() => restoreTarget && restoreMutation.mutate(restoreTarget.id)}
        onCancel={() => setRestoreTarget(null)}
      >
        <div className="space-y-3">
          <div className="flex items-start gap-2 p-2.5 rounded-lg bg-amber-50 dark:bg-amber-900/20 border border-amber-200 dark:border-amber-700">
            <AlertTriangle className="h-4 w-4 text-amber-500 mt-0.5 flex-shrink-0" />
            <p className="text-xs text-amber-700 dark:text-amber-300">
              This will replace the current database with the selected backup.
              The server must be restarted afterward.
            </p>
          </div>
          {restoreTarget && (
            <div className="p-2.5 rounded-lg bg-gray-50 dark:bg-gray-800/50 space-y-1">
              <p className="text-xs">
                <span className="text-gray-500">Restoring:</span>{' '}
                <span className="font-mono font-medium">{restoreTarget.file_name}</span>
              </p>
              <p className="text-xs">
                <span className="text-gray-500">Size:</span>{' '}
                {formatBytes(restoreTarget.size_bytes)}
              </p>
              <p className="text-xs">
                <span className="text-gray-500">Created:</span>{' '}
                {formatDate(restoreTarget.created_at)}
              </p>
            </div>
          )}
          <div className="flex items-start gap-2">
            <CheckCircle className="h-3.5 w-3.5 text-green-500 mt-0.5 flex-shrink-0" />
            <p className="text-xs text-gray-500 dark:text-gray-400">
              A safety backup of the current database will be created automatically before restoring.
            </p>
          </div>
        </div>
      </ConfirmDialog>

      {/* ── Delete Confirmation Dialog ──────────────────────────── */}
      <ConfirmDialog
        open={deleteTarget !== null}
        title="Delete Backup"
        confirmLabel="Delete"
        confirmVariant="danger"
        loading={deleteMutation.isPending}
        onConfirm={() => deleteTarget && deleteMutation.mutate(deleteTarget.id)}
        onCancel={() => setDeleteTarget(null)}
      >
        <p>
          Permanently delete <strong className="font-mono text-xs">{deleteTarget?.file_name}</strong>?
          This removes both the file and the record. This cannot be undone.
        </p>
      </ConfirmDialog>
    </div>
  );
}


// ── Backup Row Component ─────────────────────────────────────────

function BackupRow({
  backup,
  showRestore = false,
  onRestore,
  onDownload,
  onDelete,
  restoring = false,
  deleting = false,
}: {
  backup: BackupRecord;
  showRestore?: boolean;
  onRestore?: () => void;
  onDownload?: () => void;
  onDelete: () => void;
  restoring?: boolean;
  deleting?: boolean;
}) {
  return (
    <tr className="text-gray-900 dark:text-gray-100">
      <td className="px-3 py-2 text-xs font-mono truncate max-w-[200px]" title={backup.file_name}>
        {backup.file_name}
      </td>
      <td className="px-3 py-2 text-xs text-gray-500 dark:text-gray-400 whitespace-nowrap">
        {formatBytes(backup.size_bytes)}
      </td>
      <td className="px-3 py-2 text-xs text-gray-500 dark:text-gray-400 whitespace-nowrap">
        {formatDate(backup.created_at)}
      </td>
      <td className="px-3 py-2 text-right whitespace-nowrap">
        <div className="flex items-center justify-end gap-1">
          {/* Restore button — prominent for DB backups */}
          {showRestore && onRestore && (
            <button
              onClick={onRestore}
              disabled={restoring}
              title="Restore this backup"
              className="inline-flex items-center gap-1 px-2 py-1 rounded-md text-xs font-medium text-blue-600 dark:text-blue-400 bg-blue-50 dark:bg-blue-900/30 hover:bg-blue-100 dark:hover:bg-blue-900/50 transition-colors disabled:opacity-50"
            >
              <RotateCcw className="h-3 w-3" />
              <span className="hidden sm:inline">Restore</span>
            </button>
          )}
          {/* Download button */}
          {onDownload && (
            <button
              onClick={onDownload}
              title="Download this backup"
              className="p-1.5 rounded-md text-gray-500 dark:text-gray-400 hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors"
            >
              <Download className="h-3.5 w-3.5" />
            </button>
          )}
          {/* Delete button */}
          <button
            onClick={onDelete}
            disabled={deleting}
            title="Delete this backup"
            className="p-1.5 rounded-md text-red-500 dark:text-red-400 hover:bg-red-50 dark:hover:bg-red-900/30 transition-colors disabled:opacity-50"
          >
            <Trash2 className="h-3.5 w-3.5" />
          </button>
        </div>
      </td>
    </tr>
  );
}
