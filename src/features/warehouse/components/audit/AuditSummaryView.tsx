/**
 * AuditSummaryView — results screen shown after audit completion.
 *
 * Shows match/discrepancy/skipped counts and provides
 * an "Apply Adjustments" button to create stock correction movements.
 */

import { useMutation, useQueryClient } from '@tanstack/react-query';
import {
  CheckCircle, AlertTriangle, SkipForward, Wrench,
} from 'lucide-react';
import { Card, CardHeader } from '../../../../components/ui/Card';
import { Button } from '../../../../components/ui/Button';
import { Badge } from '../../../../components/ui/Badge';
import { applyAuditAdjustments } from '../../../../api/warehouse';
import type { AuditSummary } from '../../../../lib/types';

interface AuditSummaryViewProps {
  summary: AuditSummary;
  onDone: () => void;
}

export function AuditSummaryView({ summary, onDone }: AuditSummaryViewProps) {
  const queryClient = useQueryClient();

  const applyMutation = useMutation({
    mutationFn: () => applyAuditAdjustments(summary.audit_id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['audits'] });
      queryClient.invalidateQueries({ queryKey: ['warehouse-inventory'] });
    },
  });

  const stats = [
    {
      icon: CheckCircle,
      label: 'Matched',
      count: summary.progress.matched,
      color: 'text-green-500',
      bg: 'bg-green-50 dark:bg-green-900/20',
    },
    {
      icon: AlertTriangle,
      label: 'Discrepancies',
      count: summary.progress.discrepancies,
      color: 'text-red-500',
      bg: 'bg-red-50 dark:bg-red-900/20',
    },
    {
      icon: SkipForward,
      label: 'Skipped',
      count: summary.progress.skipped,
      color: 'text-gray-500',
      bg: 'bg-gray-50 dark:bg-gray-900/50',
    },
  ];

  return (
    <Card className="max-w-lg mx-auto">
      <CardHeader title="Audit Complete" />

      {/* Summary stats */}
      <div className="grid grid-cols-3 gap-4 mb-6">
        {stats.map(({ icon: Icon, label, count, color, bg }) => (
          <div key={label} className={`p-4 rounded-xl text-center ${bg}`}>
            <Icon className={`h-6 w-6 mx-auto mb-2 ${color}`} />
            <p className="text-2xl font-bold text-gray-900 dark:text-gray-100">
              {count}
            </p>
            <p className="text-xs text-gray-500 dark:text-gray-400">
              {label}
            </p>
          </div>
        ))}
      </div>

      {/* Total */}
      <div className="text-center mb-6 p-3 rounded-lg bg-gray-50 dark:bg-gray-900/50">
        <span className="text-sm text-gray-500 dark:text-gray-400">
          Total items: {summary.progress.total_items} ·{' '}
          {summary.progress.pct_complete}% complete
        </span>
      </div>

      {/* Apply adjustments */}
      {summary.has_unapplied_adjustments && summary.adjustments_needed > 0 && (
        <div className="mb-6 p-4 rounded-xl bg-amber-50 dark:bg-amber-900/20 border border-amber-200 dark:border-amber-800">
          <div className="flex items-center gap-2 mb-2">
            <Wrench className="h-4 w-4 text-amber-600 dark:text-amber-400" />
            <span className="text-sm font-medium text-amber-700 dark:text-amber-300">
              {summary.adjustments_needed} adjustment{summary.adjustments_needed !== 1 ? 's' : ''} needed
            </span>
          </div>
          <p className="text-xs text-amber-600 dark:text-amber-400 mb-3">
            Apply adjustments to correct stock levels based on discrepancies found.
          </p>
          <Button
            variant="primary"
            size="sm"
            icon={<Wrench className="h-4 w-4" />}
            onClick={() => applyMutation.mutate()}
            isLoading={applyMutation.isPending}
            disabled={applyMutation.isPending}
          >
            Apply Adjustments
          </Button>
          {applyMutation.isSuccess && (
            <Badge variant="success" className="ml-3">
              Applied!
            </Badge>
          )}
          {applyMutation.error && (
            <p className="text-sm text-red-500 mt-2">
              {(applyMutation.error as Error).message}
            </p>
          )}
        </div>
      )}

      <Button variant="secondary" onClick={onDone} fullWidth>
        Done
      </Button>
    </Card>
  );
}
