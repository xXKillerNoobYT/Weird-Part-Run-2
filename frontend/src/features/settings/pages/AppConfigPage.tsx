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
import { Shield, Check } from 'lucide-react';
import { Card, CardHeader } from '../../../components/ui/Card';
import { Input } from '../../../components/ui/Input';
import { Button } from '../../../components/ui/Button';
import { getWarrantyLengthDays, updateWarrantyLengthDays } from '../../../api/settings';

export function AppConfigPage() {
  const queryClient = useQueryClient();

  // ── Warranty Settings ──────────────────────────────────────────
  const { data: warrantyDays, isLoading } = useQuery({
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

  return (
    <div className="space-y-6">
      {/* Warranty Settings */}
      <Card>
        <CardHeader
          title="Warranty Settings"
          icon={<Shield className="h-5 w-5 text-sky-500" />}
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
                className={`px-2 py-1 rounded border text-xs transition-colors ${
                  localDays === preset.value
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
    </div>
  );
}
