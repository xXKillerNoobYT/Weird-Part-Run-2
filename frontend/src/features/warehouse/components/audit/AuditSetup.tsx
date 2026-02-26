/**
 * AuditSetup — pick audit type (spot check / category / rolling)
 * and start a new audit session.
 *
 * Also lists any existing active/paused audits that can be resumed.
 */

import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  Search, Layers, RefreshCw, Play, ClipboardCheck,
} from 'lucide-react';
import { Card, CardHeader } from '../../../../components/ui/Card';
import { Button } from '../../../../components/ui/Button';
import { Badge } from '../../../../components/ui/Badge';
import { Spinner } from '../../../../components/ui/Spinner';
import {
  listAudits, startAudit, getSuggestedRollingParts,
} from '../../../../api/warehouse';
import { formatDateTime } from '../../../../lib/utils';
import type { AuditType, AuditResponse } from '../../../../lib/types';

interface AuditSetupProps {
  onAuditStarted: (audit: AuditResponse) => void;
  onResumeAudit: (audit: AuditResponse) => void;
}

export function AuditSetup({ onAuditStarted, onResumeAudit }: AuditSetupProps) {
  const queryClient = useQueryClient();
  const [selectedType, setSelectedType] = useState<AuditType | null>(null);

  // Active/paused audits
  const { data: activeAudits } = useQuery({
    queryKey: ['audits', 'active'],
    queryFn: () => listAudits({ status: 'in_progress' }),
    staleTime: 10_000,
  });

  // Suggested rolling parts
  const { data: rollingParts } = useQuery({
    queryKey: ['audit-rolling-suggestions'],
    queryFn: () => getSuggestedRollingParts(20),
    staleTime: 60_000,
    enabled: selectedType === 'rolling',
  });

  const startMutation = useMutation({
    mutationFn: startAudit,
    onSuccess: (audit) => {
      queryClient.invalidateQueries({ queryKey: ['audits'] });
      onAuditStarted(audit);
    },
  });

  const handleStart = () => {
    if (!selectedType) return;
    startMutation.mutate({
      audit_type: selectedType,
      location_type: 'warehouse',
      location_id: 1,
    });
  };

  const auditTypes = [
    {
      type: 'spot_check' as AuditType,
      label: 'Spot Check',
      description: 'Quick count of specific parts to verify stock levels.',
      icon: Search,
    },
    {
      type: 'category' as AuditType,
      label: 'Category Audit',
      description: 'Count all parts in a specific category.',
      icon: Layers,
    },
    {
      type: 'rolling' as AuditType,
      label: 'Rolling Audit',
      description: 'System-suggested parts based on rotation schedule and staleness.',
      icon: RefreshCw,
    },
  ];

  return (
    <div className="space-y-6">
      {/* Active audits to resume */}
      {activeAudits && activeAudits.length > 0 && (
        <Card>
          <CardHeader title="Resume Audit" subtitle="You have audits in progress." />
          <div className="space-y-2">
            {activeAudits.map((audit) => (
              <div
                key={audit.id}
                className="flex items-center justify-between p-3 rounded-lg bg-gray-50 dark:bg-gray-900/50 border border-gray-100 dark:border-gray-700/50"
              >
                <div className="min-w-0 flex-1 mr-3">
                  <div className="flex items-center gap-2">
                    <span className="text-sm font-medium text-gray-900 dark:text-gray-100">
                      {audit.audit_type === 'spot_check' ? 'Spot Check' :
                       audit.audit_type === 'category' ? 'Category Audit' : 'Rolling Audit'}
                      {audit.category_name && ` — ${audit.category_name}`}
                    </span>
                    <Badge variant="warning">{audit.progress.pct_complete}%</Badge>
                  </div>
                  <p className="text-xs text-gray-500 dark:text-gray-400 mt-0.5">
                    {audit.progress.counted}/{audit.progress.total_items} counted
                    {audit.created_at && ` · Started ${formatDateTime(audit.created_at)}`}
                  </p>
                </div>
                <Button
                  size="sm"
                  icon={<Play className="h-3.5 w-3.5" />}
                  onClick={() => onResumeAudit(audit)}
                >
                  Resume
                </Button>
              </div>
            ))}
          </div>
        </Card>
      )}

      {/* New audit type selection */}
      <Card>
        <CardHeader title="Start New Audit" />
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-4 mb-6">
          {auditTypes.map(({ type, label, description, icon: Icon }) => (
            <button
              key={type}
              onClick={() => setSelectedType(type)}
              className={`p-4 rounded-xl border-2 text-left transition-colors ${
                selectedType === type
                  ? 'border-primary-500 bg-primary-50 dark:bg-primary-900/20'
                  : 'border-gray-200 dark:border-gray-700 hover:border-gray-300 dark:hover:border-gray-600'
              }`}
            >
              <Icon className={`h-6 w-6 mb-2 ${
                selectedType === type
                  ? 'text-primary-500'
                  : 'text-gray-500 dark:text-gray-400'
              }`} />
              <p className={`font-medium text-sm ${
                selectedType === type
                  ? 'text-primary-700 dark:text-primary-300'
                  : 'text-gray-900 dark:text-gray-100'
              }`}>
                {label}
              </p>
              <p className="text-xs text-gray-500 dark:text-gray-400 mt-1">
                {description}
              </p>
            </button>
          ))}
        </div>

        {/* Rolling audit suggestions */}
        {selectedType === 'rolling' && rollingParts && rollingParts.length > 0 && (
          <div className="mb-4 p-3 rounded-lg bg-blue-50 dark:bg-blue-900/20 border border-blue-200 dark:border-blue-800">
            <p className="text-sm text-blue-700 dark:text-blue-300 font-medium mb-1">
              {rollingParts.length} parts suggested for this round
            </p>
            <p className="text-xs text-blue-600 dark:text-blue-400">
              Based on category rotation schedule and time since last count.
            </p>
          </div>
        )}

        <Button
          onClick={handleStart}
          disabled={!selectedType || startMutation.isPending}
          isLoading={startMutation.isPending}
          icon={<ClipboardCheck className="h-4 w-4" />}
        >
          Start Audit
        </Button>

        {startMutation.error && (
          <p className="text-sm text-red-500 mt-2">
            {(startMutation.error as Error).message}
          </p>
        )}
      </Card>
    </div>
  );
}
