/**
 * AppConfigPage — global application configuration.
 *
 * Currently implements:
 *   - Warranty Settings (default warranty length in days)
 *
 * Future sections: company info, default units, tax rates, feature flags.
 */

import { useState, useEffect } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Check } from 'lucide-react';
import { Card, CardHeader } from '../../../components/ui/Card';
import { Input } from '../../../components/ui/Input';
import { Button } from '../../../components/ui/Button';
import { ErrorFallback } from '../../../components/ui/ErrorFallback';
import { getWarrantyLengthDays, updateWarrantyLengthDays } from '../../../api/settings';
import { DataStorageSection } from '../components/DataStorageSection';

export function AppConfigPage() {
  const queryClient = useQueryClient();

  // ── Warranty Settings ──────────────────────────────────────────
  const { data: warrantyDays, isLoading, isError, refetch } = useQuery({
    queryKey: ['warranty-length-days'],
    queryFn: getWarrantyLengthDays,
    staleTime: 30_000,
  });

  const [localDays, setLocalDays] = useState<number>(365);
  const [saved, setSaved] = useState(false);

  useEffect(() => {
    if (warrantyDays != null) setLocalDays(warrantyDays);
  }, [warrantyDays]);

  const saveMutation = useMutation({
    mutationFn: () => updateWarrantyLengthDays(localDays),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['warranty-length-days'] });
      setSaved(true);
      setTimeout(() => setSaved(false), 2500);
    },
  });

  const hasChanges = warrantyDays != null && localDays !== warrantyDays;

  if (isError) return <ErrorFallback onRetry={refetch} />;

  return (
    <div className="space-y-6">
      {/* Warranty Settings */}
      <Card>
        <CardHeader
          title="Warranty Settings"
        />
        <div className="px-4 pb-4 space-y-4">
          <p className="text-sm text-gray-500 dark:text-gray-400">
            Set the default warranty duration for jobs placed in Warranty mode.
            This determines the auto-calculated end date when a warranty starts.
          </p>

          <div className="flex items-end gap-3">
            <div className="w-48">
              <Input
                label="Default Length (days)"
                type="number"
                value={isLoading ? '' : String(localDays)}
                onChange={(e) => {
                  const v = parseInt(e.target.value, 10);
                  if (!isNaN(v) && v > 0) setLocalDays(v);
                }}
                min={1}
                max={3650}
              />
            </div>
            <Button
              onClick={() => saveMutation.mutate()}
              isLoading={saveMutation.isPending}
              disabled={!hasChanges}
            >
              Save
            </Button>
            {saved && (
              <span className="flex items-center gap-1 text-sm text-green-600 dark:text-green-400 font-medium">
                <Check className="h-4 w-4" /> Saved
              </span>
            )}
          </div>

          {/* Quick-reference presets */}
          <div className="flex items-center gap-2 text-xs text-gray-500 dark:text-gray-400">
            <span>Quick set:</span>
            {[
              { label: '90 days', value: 90 },
              { label: '6 months', value: 182 },
              { label: '1 year', value: 365 },
              { label: '2 years', value: 730 },
            ].map((preset) => (
              <button
                key={preset.value}
                type="button"
                onClick={() => setLocalDays(preset.value)}
                className={`px-2 py-1 rounded border text-xs transition-colors ${localDays === preset.value
                    ? 'border-sky-300 bg-sky-50 dark:bg-sky-900/20 text-sky-700 dark:text-sky-300'
                    : 'border-border bg-surface hover:bg-surface-secondary'
                  }`}
              >
                {preset.label}
              </button>
            ))}
          </div>
        </div>
      </Card>
      {/* Data Storage — desktop only, renders nothing on mobile/web */}
      <DataStorageSection />

      {/* Developer Tools — DEV builds only */}
      {import.meta.env.DEV && <DevToolsSection />}
    </div>
  );
}

// ── DEV-only: Developer Tools Section ────────────────────────────────

function DevToolsSection() {
  const [debugHidden, setDebugHidden] = useState(
    () => localStorage.getItem('__dev_debug_hidden') === '1',
  );

  function toggleDebugOverlay() {
    const newHidden = !debugHidden;
    if (newHidden) {
      localStorage.setItem('__dev_debug_hidden', '1');
      // Remove overlay + CSS variable from DOM if currently visible
      document.getElementById('__dev_debug')?.remove();
      document.documentElement.style.removeProperty('--dev-overlay-h');
    } else {
      localStorage.removeItem('__dev_debug_hidden');
    }
    setDebugHidden(newHidden);
  }

  return (
    <Card>
      <CardHeader title="Developer Tools" />
      <div className="px-4 pb-4 space-y-3">
        <div className="flex items-center justify-between">
          <div>
            <p className="text-sm font-medium text-gray-900 dark:text-gray-100">
              Dev Overlay
            </p>
            <p className="text-xs text-gray-500 dark:text-gray-400">
              Show auth flow debug log at the bottom of the screen during startup.
              {debugHidden ? ' Restart the app to see it again after enabling.' : ''}
            </p>
          </div>
          <button
            type="button"
            role="switch"
            aria-checked={!debugHidden}
            onClick={toggleDebugOverlay}
            className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors ${
              !debugHidden ? 'bg-primary-500' : 'bg-gray-300 dark:bg-gray-600'
            }`}
          >
            <span
              className={`inline-block h-4 w-4 transform rounded-full bg-white transition-transform ${
                !debugHidden ? 'translate-x-6' : 'translate-x-1'
              }`}
            />
          </button>
        </div>
      </div>
    </Card>
  );
}
