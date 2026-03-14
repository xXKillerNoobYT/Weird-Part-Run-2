/**
 * DeviceSyncProfilesCard — per-device sync profile editor (storage policy,
 * media policy, toggles).
 */

import { useState, useEffect } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import {
  Settings2, Smartphone, Monitor, ChevronDown, ChevronRight,
  Save, CheckCircle,
} from 'lucide-react';
import { Button } from '../../../../components/ui/Button';
import { PageSpinner } from '../../../../components/ui/Spinner';
import {
  listSyncDevices,
  getDeviceSyncProfile,
  updateDeviceSyncProfile,
} from '../../../../api/sync';
import type {
  SyncDevice,
  DeviceSyncProfileUpdate,
} from '../../../../api/sync';
import { STORAGE_POLICIES, MEDIA_POLICIES, formatDate } from './helpers';

export function DeviceSyncProfilesCard() {
  const [expandedDevice, setExpandedDevice] = useState<string | null>(null);

  const { data: devices = [], isLoading: devicesLoading } = useQuery({
    queryKey: ['sync-devices'],
    queryFn: listSyncDevices,
    retry: 1,
    staleTime: 30000,
  });

  return (
    <div className="bg-surface border border-border rounded-lg p-4 space-y-3">
      <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100 flex items-center gap-2">
        <Settings2 className="h-4 w-4" />
        Device Sync Profiles
      </h3>
      <p className="text-xs text-gray-500 dark:text-gray-400">
        Configure how each device stores data, handles media, and syncs.
        Profiles belong to the device's primary user — borrowed users cannot change these.
      </p>

      {devicesLoading ? (
        <PageSpinner label="Loading devices..." />
      ) : devices.length === 0 ? (
        <p className="text-sm text-gray-500 dark:text-gray-400">
          No devices registered. Profiles will appear after a device syncs.
        </p>
      ) : (
        <div className="space-y-2">
          {devices.map((d) => (
            <DeviceProfileRow
              key={d.device_id}
              device={d}
              expanded={expandedDevice === d.device_id}
              onToggle={() =>
                setExpandedDevice(expandedDevice === d.device_id ? null : d.device_id)
              }
            />
          ))}
        </div>
      )}
    </div>
  );
}

// ── Device Profile Row (inline sub-component) ───────────────────

function DeviceProfileRow({
  device,
  expanded,
  onToggle,
}: {
  device: SyncDevice;
  expanded: boolean;
  onToggle: () => void;
}) {
  const queryClient = useQueryClient();

  const { data: profile, isLoading } = useQuery({
    queryKey: ['device-profile', device.device_id],
    queryFn: () => getDeviceSyncProfile(device.device_id),
    enabled: expanded,
    staleTime: 30000,
  });

  const [form, setForm] = useState<DeviceSyncProfileUpdate>({});
  const [dirty, setDirty] = useState(false);

  // Sync form with profile data when loaded
  useEffect(() => {
    if (profile) {
      setForm({
        storage_policy: profile.storage_policy,
        media_policy: profile.media_policy,
        media_retention_days: profile.media_retention_days,
        force_carry_undelivered_media: !!profile.force_carry_undelivered_media,
        allow_borrowed_user_overrides: !!profile.allow_borrowed_user_overrides,
        active_only_sync: !!profile.active_only_sync,
      });
      setDirty(false);
    }
  }, [profile]);

  const mutation = useMutation({
    mutationFn: (payload: DeviceSyncProfileUpdate) =>
      updateDeviceSyncProfile(device.device_id, payload),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['device-profile', device.device_id] });
      setDirty(false);
    },
  });

  function updateField(key: keyof DeviceSyncProfileUpdate, value: unknown) {
    setForm((prev) => ({ ...prev, [key]: value }));
    setDirty(true);
  }

  return (
    <div className="border border-border rounded-md">
      <button
        type="button"
        onClick={onToggle}
        className="w-full flex items-center gap-3 p-3 text-left hover:bg-gray-50 dark:hover:bg-gray-800/50 transition-colors"
      >
        {device.platform === 'ios' || device.platform === 'android' ? (
          <Smartphone className="h-4 w-4 text-gray-400 shrink-0" />
        ) : (
          <Monitor className="h-4 w-4 text-gray-400 shrink-0" />
        )}
        <div className="flex-1 min-w-0">
          <span className="text-sm font-medium text-gray-900 dark:text-gray-100">
            {device.device_name || device.device_id}
          </span>
          <span className="text-xs text-gray-500 dark:text-gray-400 ml-2">
            {device.platform}
          </span>
        </div>
        {expanded ? (
          <ChevronDown className="h-4 w-4 text-gray-400" />
        ) : (
          <ChevronRight className="h-4 w-4 text-gray-400" />
        )}
      </button>

      {expanded && (
        <div className="px-3 pb-3 pt-1 border-t border-border space-y-3">
          {isLoading ? (
            <PageSpinner label="Loading profile..." />
          ) : !profile ? (
            <p className="text-sm text-gray-500 dark:text-gray-400">
              No profile found — it will be created on the device's next sync.
            </p>
          ) : (
            <>
              {/* Storage Policy */}
              <div>
                <label className="block text-xs font-medium text-gray-700 dark:text-gray-300 mb-1">
                  Storage Policy
                </label>
                <select
                  value={form.storage_policy || ''}
                  onChange={(e) => updateField('storage_policy', e.target.value)}
                  className="w-full min-h-11 px-3 py-2 text-sm border border-border rounded-md bg-surface text-gray-900 dark:text-gray-100"
                >
                  {STORAGE_POLICIES.map((p) => (
                    <option key={p.value} value={p.value}>{p.label}</option>
                  ))}
                </select>
                <p className="text-xs text-gray-400 mt-0.5">
                  {STORAGE_POLICIES.find((p) => p.value === form.storage_policy)?.desc}
                </p>
              </div>

              {/* Media Policy */}
              <div>
                <label className="block text-xs font-medium text-gray-700 dark:text-gray-300 mb-1">
                  Media Policy
                </label>
                <select
                  value={form.media_policy || ''}
                  onChange={(e) => updateField('media_policy', e.target.value)}
                  className="w-full min-h-11 px-3 py-2 text-sm border border-border rounded-md bg-surface text-gray-900 dark:text-gray-100"
                >
                  {MEDIA_POLICIES.map((p) => (
                    <option key={p.value} value={p.value}>{p.label}</option>
                  ))}
                </select>
                <p className="text-xs text-gray-400 mt-0.5">
                  {MEDIA_POLICIES.find((p) => p.value === form.media_policy)?.desc}
                </p>
              </div>

              {/* Media Retention Days */}
              {form.media_policy === 'last_n_days' && (
                <div>
                  <label className="block text-xs font-medium text-gray-700 dark:text-gray-300 mb-1">
                    Media Retention (days)
                  </label>
                  <input
                    type="number"
                    min={1}
                    max={365}
                    value={form.media_retention_days ?? 30}
                    onChange={(e) => updateField('media_retention_days', parseInt(e.target.value) || 30)}
                    className="w-32 min-h-11 px-3 py-2 text-sm border border-border rounded-md bg-surface text-gray-900 dark:text-gray-100"
                  />
                </div>
              )}

              {/* Toggle switches */}
              <div className="space-y-2">
                <label className="flex items-center gap-2 text-sm text-gray-700 dark:text-gray-300">
                  <input
                    type="checkbox"
                    checked={!!form.force_carry_undelivered_media}
                    onChange={(e) => updateField('force_carry_undelivered_media', e.target.checked)}
                    className="h-4 w-4"
                  />
                  Force carry undelivered media
                  <span className="text-xs text-gray-400">(mandatory relay)</span>
                </label>

                <label className="flex items-center gap-2 text-sm text-gray-700 dark:text-gray-300">
                  <input
                    type="checkbox"
                    checked={!!form.active_only_sync}
                    onChange={(e) => updateField('active_only_sync', e.target.checked)}
                    className="h-4 w-4"
                  />
                  Active-only sync
                  <span className="text-xs text-gray-400">(skip completed/on-hold jobs)</span>
                </label>

                <label className="flex items-center gap-2 text-sm text-gray-700 dark:text-gray-300">
                  <input
                    type="checkbox"
                    checked={!!form.allow_borrowed_user_overrides}
                    onChange={(e) => updateField('allow_borrowed_user_overrides', e.target.checked)}
                    className="h-4 w-4"
                  />
                  Allow borrowed user overrides
                  <span className="text-xs text-gray-400">(let guest users change profile)</span>
                </label>
              </div>

              {/* Save button */}
              <div className="flex items-center gap-2">
                <Button
                  size="sm"
                  disabled={!dirty || mutation.isPending}
                  isLoading={mutation.isPending}
                  onClick={() => mutation.mutate(form)}
                >
                  <Save className="h-3.5 w-3.5 mr-1" />
                  Save Profile
                </Button>
                {mutation.isSuccess && !dirty && (
                  <span className="text-xs text-green-600 dark:text-green-400 flex items-center gap-1">
                    <CheckCircle className="h-3.5 w-3.5" /> Saved
                  </span>
                )}
                {mutation.isError && (
                  <span className="text-xs text-red-600 dark:text-red-400">
                    Failed to save
                  </span>
                )}
              </div>

              {/* Last updated */}
              <p className="text-xs text-gray-400">
                Last updated: {formatDate(profile.updated_at)}
                {profile.updated_by ? ` by user #${profile.updated_by}` : ''}
              </p>
            </>
          )}
        </div>
      )}
    </div>
  );
}
