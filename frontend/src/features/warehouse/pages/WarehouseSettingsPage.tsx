/**
 * WarehouseSettingsPage — warehouse-specific configuration.
 *
 * Controls aging thresholds for staging area, rolling audit intervals,
 * spot check defaults, and low-stock display preferences.
 * All settings persist to the backend via the generic settings API.
 */

import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Settings2, Save } from 'lucide-react';
import { useState, useEffect } from 'react';
import { Card, CardHeader } from '../../../components/ui/Card';
import { Button } from '../../../components/ui/Button';
import { getSetting, updateSetting } from '../../../api/settings';
import { toast } from '../../../lib/toast';

// ── Setting key constants ────────────────────────────────────────

const KEYS = {
  STAGING_WARN_HOURS:      'warehouse_staging_warning_hours',
  STAGING_CRITICAL_HOURS:  'warehouse_staging_critical_hours',
  ROLLING_INTERVAL_DAYS:   'warehouse_audit_rolling_interval_days',
  SPOT_CHECK_COUNT:        'warehouse_spot_check_default_count',
  LOW_STOCK_BADGE_ENABLED: 'warehouse_low_stock_badges_enabled',
} as const;

const DEFAULTS = {
  [KEYS.STAGING_WARN_HOURS]:      '24',
  [KEYS.STAGING_CRITICAL_HOURS]:  '48',
  [KEYS.ROLLING_INTERVAL_DAYS]:   '30',
  [KEYS.SPOT_CHECK_COUNT]:        '3',
  [KEYS.LOW_STOCK_BADGE_ENABLED]: 'true',
};

function useSettingValue(key: string) {
  return useQuery({
    queryKey: ['setting', key],
    queryFn: () => getSetting(key),
    staleTime: 60_000,
    select: (v) => v ?? DEFAULTS[key as keyof typeof DEFAULTS] ?? '',
  });
}


// ── Number input section ─────────────────────────────────────────

function NumberSetting({
  label,
  description,
  settingKey,
  min,
  max,
  unit,
}: {
  label: string;
  description: string;
  settingKey: string;
  min: number;
  max: number;
  unit: string;
}) {
  const queryClient = useQueryClient();
  const { data: saved, isLoading } = useSettingValue(settingKey);
  const [value, setValue] = useState('');

  useEffect(() => {
    if (saved !== undefined) setValue(saved);
  }, [saved]);

  const mut = useMutation({
    mutationFn: (v: string) => updateSetting(settingKey, v, 'warehouse'),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['setting', settingKey] });
      toast.success(`${label} saved`);
    },
    onError: () => toast.error(`Failed to save ${label}`),
  });

  return (
    <div className="flex items-center justify-between gap-4 py-3 border-b border-gray-100 dark:border-gray-800 last:border-0">
      <div className="flex-1 min-w-0">
        <p className="text-sm font-medium text-gray-900 dark:text-gray-100">{label}</p>
        <p className="text-xs text-gray-500 dark:text-gray-400 mt-0.5">{description}</p>
      </div>
      <div className="flex items-center gap-2 flex-shrink-0">
        <input
          type="number"
          min={min}
          max={max}
          value={value}
          disabled={isLoading}
          onChange={e => setValue(e.target.value)}
          className="w-20 rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-700
                     text-sm text-gray-900 dark:text-gray-100 px-2 py-1.5 text-right
                     focus:ring-2 focus:ring-primary-400 focus:border-transparent"
        />
        <span className="text-xs text-gray-500 dark:text-gray-400 w-12">{unit}</span>
        <Button
          size="sm"
          variant="secondary"
          onClick={() => mut.mutate(value)}
          isLoading={mut.isPending}
          icon={<Save size={13} />}
        >
          Save
        </Button>
      </div>
    </div>
  );
}


// ── Toggle setting ───────────────────────────────────────────────

function ToggleSetting({
  label,
  description,
  settingKey,
}: {
  label: string;
  description: string;
  settingKey: string;
}) {
  const queryClient = useQueryClient();
  const { data: saved } = useSettingValue(settingKey);
  const enabled = saved === 'true';

  const mut = useMutation({
    mutationFn: (v: string) => updateSetting(settingKey, v, 'warehouse'),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['setting', settingKey] }),
    onError: () => toast.error(`Failed to update ${label}`),
  });

  return (
    <div className="flex items-center justify-between gap-4 py-3 border-b border-gray-100 dark:border-gray-800 last:border-0">
      <div className="flex-1 min-w-0">
        <p className="text-sm font-medium text-gray-900 dark:text-gray-100">{label}</p>
        <p className="text-xs text-gray-500 dark:text-gray-400 mt-0.5">{description}</p>
      </div>
      <button
        onClick={() => mut.mutate(enabled ? 'false' : 'true')}
        disabled={mut.isPending}
        className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors flex-shrink-0 ${
          enabled ? 'bg-primary-500' : 'bg-gray-300 dark:bg-gray-600'
        }`}
      >
        <span
          className={`inline-block h-4 w-4 transform rounded-full bg-white shadow transition-transform ${
            enabled ? 'translate-x-6' : 'translate-x-1'
          }`}
        />
      </button>
    </div>
  );
}


// ═══════════════════════════════════════════════════════════════════
// MAIN PAGE
// ═══════════════════════════════════════════════════════════════════

export function WarehouseSettingsPage() {
  return (
    <div className="mx-auto max-w-2xl space-y-6">
      {/* Page header */}
      <div className="flex items-center gap-3">
        <Settings2 size={22} className="text-gray-500 dark:text-gray-400 flex-shrink-0" />
        <div>
          <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-100">
            Warehouse Settings
          </h2>
          <p className="text-sm text-gray-500 dark:text-gray-400">
            Configure thresholds, defaults, and display preferences for the warehouse.
          </p>
        </div>
      </div>

      {/* Staging / Aging thresholds */}
      <Card>
        <CardHeader
          title="Staging Area Aging"
          subtitle="How long items can sit in staging before color-coding changes"
        />
        <div className="px-4 pb-2">
          <NumberSetting
            label="Warning Threshold"
            description="Items staged longer than this show an amber/warning badge."
            settingKey={KEYS.STAGING_WARN_HOURS}
            min={1}
            max={168}
            unit="hours"
          />
          <NumberSetting
            label="Critical Threshold"
            description="Items staged longer than this show a red/critical badge."
            settingKey={KEYS.STAGING_CRITICAL_HOURS}
            min={1}
            max={336}
            unit="hours"
          />
        </div>
      </Card>

      {/* Audit defaults */}
      <Card>
        <CardHeader
          title="Audit Defaults"
          subtitle="Control how rolling audits and spot checks are suggested"
        />
        <div className="px-4 pb-2">
          <NumberSetting
            label="Rolling Audit Interval"
            description="Parts not counted within this period are suggested for rolling audits."
            settingKey={KEYS.ROLLING_INTERVAL_DAYS}
            min={7}
            max={365}
            unit="days"
          />
          <NumberSetting
            label="Spot Check Part Count"
            description="Number of parts pre-selected when starting a spot check."
            settingKey={KEYS.SPOT_CHECK_COUNT}
            min={1}
            max={20}
            unit="parts"
          />
        </div>
      </Card>

      {/* Display preferences */}
      <Card>
        <CardHeader
          title="Display Preferences"
          subtitle="Control what information is shown in inventory views"
        />
        <div className="px-4 pb-2">
          <ToggleSetting
            label="Low-Stock Badges on Inventory Grid"
            description="Show red/amber badges on inventory rows that are below min stock level."
            settingKey={KEYS.LOW_STOCK_BADGE_ENABLED}
          />
        </div>
      </Card>
    </div>
  );
}
