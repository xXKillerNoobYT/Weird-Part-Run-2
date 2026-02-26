/**
 * AuditPage — inventory audit with three modes:
 *
 * 1. Setup — pick type (spot check / category / rolling), start or resume
 * 2. Counting — card-swipe flow with large touch targets
 * 3. Summary — results + apply adjustments
 *
 * Uses local state to track which screen is active.
 */

import { useState, useCallback } from 'react';
import { useQuery } from '@tanstack/react-query';
import { ArrowLeft } from 'lucide-react';
import { Button } from '../../../components/ui/Button';
import { Spinner } from '../../../components/ui/Spinner';
import {
  getAudit, getNextAuditItem, completeAudit,
} from '../../../api/warehouse';
import { AuditSetup } from '../components/audit/AuditSetup';
import { AuditProgressBar } from '../components/audit/AuditProgressBar';
import { AuditCard } from '../components/audit/AuditCard';
import { AuditSummaryView } from '../components/audit/AuditSummaryView';
import type { AuditResponse, AuditSummary } from '../../../lib/types';

type AuditScreen = 'setup' | 'counting' | 'summary';

export function AuditPage() {
  const [screen, setScreen] = useState<AuditScreen>('setup');
  const [activeAuditId, setActiveAuditId] = useState<number | null>(null);
  const [summary, setSummary] = useState<AuditSummary | null>(null);
  const [itemVersion, setItemVersion] = useState(0);

  // Fetch the active audit (if any)
  const { data: audit, refetch: refetchAudit } = useQuery({
    queryKey: ['audit', activeAuditId],
    queryFn: () => getAudit(activeAuditId!),
    enabled: activeAuditId != null && screen === 'counting',
    staleTime: 5_000,
  });

  // Fetch the next un-counted item
  const { data: nextItem, isLoading: loadingNextItem, refetch: refetchNextItem } = useQuery({
    queryKey: ['audit-next-item', activeAuditId, itemVersion],
    queryFn: () => getNextAuditItem(activeAuditId!),
    enabled: activeAuditId != null && screen === 'counting',
    staleTime: 0,
  });

  const handleAuditStarted = useCallback((auditResp: AuditResponse) => {
    setActiveAuditId(auditResp.id);
    setScreen('counting');
  }, []);

  const handleResume = useCallback((auditResp: AuditResponse) => {
    setActiveAuditId(auditResp.id);
    setScreen('counting');
  }, []);

  const handleItemCounted = useCallback(() => {
    // Bump version to trigger fresh next-item fetch
    setItemVersion((v) => v + 1);
    refetchAudit();
    refetchNextItem();
  }, [refetchAudit, refetchNextItem]);

  const handleCompleteAudit = useCallback(async () => {
    if (!activeAuditId) return;
    try {
      const result = await completeAudit(activeAuditId);
      setSummary(result);
      setScreen('summary');
    } catch {
      // Stay on counting screen — user can try again
    }
  }, [activeAuditId]);

  const handleDone = useCallback(() => {
    setActiveAuditId(null);
    setSummary(null);
    setScreen('setup');
  }, []);

  const handleBackToSetup = useCallback(() => {
    setActiveAuditId(null);
    setScreen('setup');
  }, []);

  // ── Render ────────────────────────────────────────────

  if (screen === 'setup') {
    return (
      <AuditSetup
        onAuditStarted={handleAuditStarted}
        onResumeAudit={handleResume}
      />
    );
  }

  if (screen === 'summary' && summary) {
    return <AuditSummaryView summary={summary} onDone={handleDone} />;
  }

  // ── Counting screen ───────────────────────────────────

  return (
    <div className="space-y-6">
      {/* Header with back button and progress */}
      <div className="flex items-center gap-4">
        <Button
          variant="ghost"
          size="sm"
          icon={<ArrowLeft className="h-4 w-4" />}
          onClick={handleBackToSetup}
        >
          Exit
        </Button>
        <div className="flex-1">
          {audit && <AuditProgressBar progress={audit.progress} />}
        </div>
      </div>

      {/* Card-swipe area */}
      {loadingNextItem ? (
        <div className="flex justify-center py-12">
          <Spinner label="Loading next item..." />
        </div>
      ) : nextItem ? (
        <AuditCard
          key={nextItem.id}
          auditId={activeAuditId!}
          item={nextItem}
          onCounted={handleItemCounted}
        />
      ) : (
        /* No more items — audit can be completed */
        <div className="text-center py-12 space-y-4">
          <p className="text-lg font-medium text-gray-900 dark:text-gray-100">
            All items counted!
          </p>
          <p className="text-sm text-gray-500 dark:text-gray-400">
            You've gone through every item in this audit.
          </p>
          <Button onClick={handleCompleteAudit}>
            Complete Audit
          </Button>
        </div>
      )}
    </div>
  );
}
