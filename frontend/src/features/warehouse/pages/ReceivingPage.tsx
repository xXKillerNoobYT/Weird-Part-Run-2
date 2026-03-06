/**
 * ReceivingPage — session-based receiving for POs (Phase 7C).
 *
 * Two modes:
 *   - Packing Slip (default): show all expected lines, user enters qty per line
 *   - Scan: QR scanner active → scan part → match PO line → enter qty
 *
 * Workflow:
 *   1. Enter PO number (or pick from dropdown of open POs)
 *   2. Start session → pre-populated items appear
 *   3. Enter received quantities per line
 *   4. Commit → creates stock movements, updates PO status
 *
 * Lives under: Warehouse > Receiving tab
 * Permission: manage_orders
 */

import { useState, useMemo, useCallback, useRef, useEffect } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  Package,
  ScanLine,
  ClipboardList,
  Check,
  X,
  Loader2,
  Search,
  AlertTriangle,
  CheckCircle2,
  Clock,
  Hash,
} from 'lucide-react';
import { PageSpinner } from '../../../components/ui/Spinner';
import { EmptyState } from '../../../components/ui/EmptyState';
import { Badge } from '../../../components/ui/Badge';
import { Modal } from '../../../components/ui/Modal';
import {
  startReceivingSession,
  getReceivingSession,
  listReceivingSessions,
  updateReceivingSessionItem,
  commitReceivingSession,
  cancelReceivingSession,
  findPOLineByPartScan,
  listStagingZones,
} from '../../../api/orders';
import { formatRelativeTime } from '../../../lib/utils';
import type {
  ReceivingSessionResponse,
  ReceivingSessionItemResponse,
  ReceivingSessionListItem,
  ReceivingMode,
  StagingZoneResponse,
} from '../../../lib/types';
import toast from '../../../lib/toast';


// ── Types & constants ───────────────────────────────────────────

type PageView = 'start' | 'active' | 'history';

const MODE_LABELS: Record<ReceivingMode, string> = {
  packing_slip: 'Packing Slip',
  scan: 'Scan',
};


// ── Component ───────────────────────────────────────────────────

export function ReceivingPage() {
  const queryClient = useQueryClient();

  // ── View state ──
  const [view, setView] = useState<PageView>('start');
  const [activeSessionId, setActiveSessionId] = useState<number | null>(null);

  // ── Start session form ──
  const [poNumber, setPoNumber] = useState('');
  const [selectedMode, setSelectedMode] = useState<ReceivingMode>('packing_slip');
  const [sessionNotes, setSessionNotes] = useState('');

  // ── Commit modal ──
  const [showCommitModal, setShowCommitModal] = useState(false);
  const [showCancelModal, setShowCancelModal] = useState(false);

  // ── Scan mode state ──
  const [scanInput, setScanInput] = useState('');
  const scanRef = useRef<HTMLInputElement>(null);

  // ── Queries ──
  const { data: activeSession, isLoading: sessionLoading, refetch: refetchSession } = useQuery({
    queryKey: ['receiving-session', activeSessionId],
    queryFn: () => getReceivingSession(activeSessionId!),
    enabled: !!activeSessionId,
    staleTime: 10_000,
    refetchInterval: 15_000,
  });

  const { data: recentSessions, isLoading: historyLoading } = useQuery({
    queryKey: ['receiving-sessions-recent'],
    queryFn: () => listReceivingSessions({ limit: 20 }),
    staleTime: 30_000,
  });

  const { data: stagingZones } = useQuery({
    queryKey: ['staging-zones'],
    queryFn: listStagingZones,
    staleTime: 60_000,
  });

  // ── Mutations ──
  const startMutation = useMutation({
    mutationFn: startReceivingSession,
    onSuccess: (session) => {
      setActiveSessionId(session.id);
      setView('active');
      queryClient.invalidateQueries({ queryKey: ['receiving-sessions-recent'] });
      toast.success(`Session started for PO ${session.po_number || session.po_id}`);
    },
    onError: (err: Error) => {
      toast.error(err.message || 'Failed to start session');
    },
  });

  const updateItemMutation = useMutation({
    mutationFn: ({ sessionId, body }: { sessionId: number; body: Parameters<typeof updateReceivingSessionItem>[1] }) =>
      updateReceivingSessionItem(sessionId, body),
    onSuccess: () => {
      refetchSession();
    },
    onError: (err: Error) => {
      toast.error(err.message || 'Failed to update item');
    },
  });

  const commitMutation = useMutation({
    mutationFn: (sessionId: number) => commitReceivingSession(sessionId),
    onSuccess: () => {
      toast.success('Session committed — items received!');
      setShowCommitModal(false);
      setActiveSessionId(null);
      setView('start');
      setPoNumber('');
      queryClient.invalidateQueries({ queryKey: ['receiving-sessions-recent'] });
      queryClient.invalidateQueries({ queryKey: ['purchase-orders'] });
    },
    onError: (err: Error) => {
      toast.error(err.message || 'Failed to commit session');
    },
  });

  const cancelMutation = useMutation({
    mutationFn: (sessionId: number) => cancelReceivingSession(sessionId),
    onSuccess: () => {
      toast.success('Session cancelled');
      setShowCancelModal(false);
      setActiveSessionId(null);
      setView('start');
      queryClient.invalidateQueries({ queryKey: ['receiving-sessions-recent'] });
    },
    onError: (err: Error) => {
      toast.error(err.message || 'Failed to cancel session');
    },
  });

  const scanMutation = useMutation({
    mutationFn: ({ sessionId, partId }: { sessionId: number; partId: number }) =>
      findPOLineByPartScan(sessionId, partId),
    onSuccess: (match) => {
      if (match) {
        toast.success(`Match: ${match.part_description || 'Part found'}`);
      }
    },
    onError: () => {
      toast.error('No matching PO line found for this part');
    },
  });

  // ── Handlers ──
  const handleStartSession = useCallback(() => {
    if (!poNumber.trim()) {
      toast.error('Enter a PO number');
      return;
    }
    // The backend accepts po_id — we need to resolve PO number to ID.
    // For now, we'll try parsing as integer (PO ID).
    const poId = parseInt(poNumber.trim(), 10);
    if (isNaN(poId)) {
      toast.error('Enter a valid PO number (numeric ID)');
      return;
    }
    startMutation.mutate({
      po_id: poId,
      mode: selectedMode,
      notes: sessionNotes || undefined,
    });
  }, [poNumber, selectedMode, sessionNotes, startMutation]);

  const handleScan = useCallback(() => {
    if (!scanInput.trim() || !activeSessionId) return;
    const partId = parseInt(scanInput.trim(), 10);
    if (isNaN(partId)) {
      toast.error('Invalid scan — expected part ID');
      setScanInput('');
      return;
    }
    scanMutation.mutate({ sessionId: activeSessionId, partId });
    setScanInput('');
    scanRef.current?.focus();
  }, [scanInput, activeSessionId, scanMutation]);

  const handleItemQtyChange = useCallback(
    (item: ReceivingSessionItemResponse, qty: number) => {
      if (!activeSessionId) return;
      updateItemMutation.mutate({
        sessionId: activeSessionId,
        body: {
          po_line_id: item.po_line_id,
          received_qty: qty,
          actual_cost: item.actual_cost,
          staging_zone_id: item.staging_zone_id,
        },
      });
    },
    [activeSessionId, updateItemMutation],
  );

  const handleItemZoneChange = useCallback(
    (item: ReceivingSessionItemResponse, zoneId: number | null) => {
      if (!activeSessionId) return;
      updateItemMutation.mutate({
        sessionId: activeSessionId,
        body: {
          po_line_id: item.po_line_id,
          received_qty: item.received_qty,
          staging_zone_id: zoneId,
        },
      });
    },
    [activeSessionId, updateItemMutation],
  );

  const handleResumeSession = useCallback((sessionId: number) => {
    setActiveSessionId(sessionId);
    setView('active');
  }, []);

  // Focus scan input when in scan mode
  useEffect(() => {
    if (activeSession?.mode === 'scan' && scanRef.current) {
      scanRef.current.focus();
    }
  }, [activeSession?.mode]);

  // ── Derived ──
  const progress = useMemo(() => {
    if (!activeSession) return { percent: 0, received: 0, expected: 0 };
    const expected = activeSession.total_expected || 1;
    const received = activeSession.total_received || 0;
    return {
      percent: Math.min(100, Math.round((received / expected) * 100)),
      received,
      expected: activeSession.total_expected,
    };
  }, [activeSession]);

  const inProgressSessions = useMemo(
    () => (recentSessions ?? []).filter((s) => s.status === 'in_progress'),
    [recentSessions],
  );

  // ══════════════════════════════════════════════════════════════
  // RENDER
  // ══════════════════════════════════════════════════════════════

  // ── Start / History view ──
  if (view === 'start' || view === 'history') {
    return (
      <div className="space-y-6">
        {/* Header */}
        <div className="flex items-center justify-between flex-wrap gap-3">
          <h2 className="text-lg font-semibold text-gray-900 dark:text-white">
            Receiving
          </h2>
          <div className="flex gap-2">
            <button
              onClick={() => setView('start')}
              className={`px-3 py-1.5 text-sm rounded-lg transition-colors ${
                view === 'start'
                  ? 'bg-primary-500 text-white'
                  : 'bg-gray-100 text-gray-700 dark:bg-gray-700 dark:text-gray-300'
              }`}
            >
              New Session
            </button>
            <button
              onClick={() => setView('history')}
              className={`px-3 py-1.5 text-sm rounded-lg transition-colors ${
                view === 'history'
                  ? 'bg-primary-500 text-white'
                  : 'bg-gray-100 text-gray-700 dark:bg-gray-700 dark:text-gray-300'
              }`}
            >
              History
            </button>
          </div>
        </div>

        {/* In-progress sessions banner */}
        {inProgressSessions.length > 0 && (
          <div className="rounded-xl bg-amber-50 dark:bg-amber-900/30 border border-amber-200 dark:border-amber-700 p-4">
            <div className="flex items-center gap-2 text-amber-700 dark:text-amber-400 mb-2">
              <Clock className="h-4 w-4" />
              <span className="text-sm font-medium">
                {inProgressSessions.length} session{inProgressSessions.length > 1 ? 's' : ''} in progress
              </span>
            </div>
            <div className="space-y-2">
              {inProgressSessions.map((s) => (
                <button
                  key={s.id}
                  onClick={() => handleResumeSession(s.id)}
                  className="w-full text-left px-3 py-2 rounded-lg bg-white dark:bg-gray-800 border border-amber-200 dark:border-amber-700 hover:bg-amber-50 dark:hover:bg-amber-900/40 transition-colors"
                >
                  <span className="text-sm font-medium text-gray-900 dark:text-white">
                    PO #{s.po_number || s.po_id}
                  </span>
                  <span className="text-xs text-gray-500 dark:text-gray-400 ml-2">
                    {s.supplier_name} · {MODE_LABELS[s.mode]} · {s.total_received}/{s.total_expected} received
                  </span>
                </button>
              ))}
            </div>
          </div>
        )}

        {view === 'start' && (
          <div className="rounded-xl bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 p-6 max-w-lg">
            <h3 className="text-base font-medium text-gray-900 dark:text-white mb-4">
              Start Receiving Session
            </h3>

            {/* PO Number */}
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
              PO Number
            </label>
            <div className="relative mb-4">
              <Hash className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-gray-400 dark:text-gray-500" />
              <input
                type="text"
                value={poNumber}
                onChange={(e) => setPoNumber(e.target.value)}
                placeholder="Enter PO ID…"
                className="w-full pl-10 pr-4 py-2.5 rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-700 text-gray-900 dark:text-white placeholder-gray-400 dark:placeholder-gray-500 focus:ring-2 focus:ring-primary-500 focus:border-transparent text-sm"
                onKeyDown={(e) => e.key === 'Enter' && handleStartSession()}
              />
            </div>

            {/* Mode toggle */}
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
              Mode
            </label>
            <div className="flex gap-2 mb-4">
              <button
                onClick={() => setSelectedMode('packing_slip')}
                className={`flex-1 flex items-center justify-center gap-2 px-4 py-2.5 rounded-lg text-sm font-medium transition-colors ${
                  selectedMode === 'packing_slip'
                    ? 'bg-primary-500 text-white'
                    : 'bg-gray-100 text-gray-700 dark:bg-gray-700 dark:text-gray-300 hover:bg-gray-200 dark:hover:bg-gray-600'
                }`}
              >
                <ClipboardList className="h-4 w-4" />
                Packing Slip
              </button>
              <button
                onClick={() => setSelectedMode('scan')}
                className={`flex-1 flex items-center justify-center gap-2 px-4 py-2.5 rounded-lg text-sm font-medium transition-colors ${
                  selectedMode === 'scan'
                    ? 'bg-primary-500 text-white'
                    : 'bg-gray-100 text-gray-700 dark:bg-gray-700 dark:text-gray-300 hover:bg-gray-200 dark:hover:bg-gray-600'
                }`}
              >
                <ScanLine className="h-4 w-4" />
                Scan
              </button>
            </div>

            {/* Notes */}
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
              Notes <span className="text-gray-400 dark:text-gray-500">(optional)</span>
            </label>
            <textarea
              value={sessionNotes}
              onChange={(e) => setSessionNotes(e.target.value)}
              rows={2}
              className="w-full px-4 py-2.5 rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-700 text-gray-900 dark:text-white placeholder-gray-400 dark:placeholder-gray-500 text-sm resize-none mb-4"
              placeholder="e.g., FedEx delivery, 3 boxes"
            />

            {/* Start button */}
            <button
              onClick={handleStartSession}
              disabled={startMutation.isPending || !poNumber.trim()}
              className="w-full flex items-center justify-center gap-2 px-4 py-3 rounded-lg bg-primary-500 text-white font-medium text-sm hover:bg-primary-600 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
            >
              {startMutation.isPending ? (
                <Loader2 className="h-4 w-4 animate-spin" />
              ) : (
                <Package className="h-4 w-4" />
              )}
              Start Receiving
            </button>
          </div>
        )}

        {view === 'history' && (
          <div className="rounded-xl bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 overflow-hidden">
            {historyLoading && <PageSpinner label="Loading sessions…" />}
            {!historyLoading && (!recentSessions || recentSessions.length === 0) && (
              <EmptyState
                icon={<ClipboardList className="h-12 w-12" />}
                title="No Sessions Yet"
                description="Start a new receiving session to begin."
              />
            )}
            {!historyLoading && recentSessions && recentSessions.length > 0 && (
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead>
                    <tr className="border-b border-gray-200 dark:border-gray-700 bg-gray-50 dark:bg-gray-750">
                      <th className="px-4 py-3 text-left font-medium text-gray-500 dark:text-gray-400">PO</th>
                      <th className="px-4 py-3 text-left font-medium text-gray-500 dark:text-gray-400">Supplier</th>
                      <th className="px-4 py-3 text-left font-medium text-gray-500 dark:text-gray-400">Mode</th>
                      <th className="px-4 py-3 text-left font-medium text-gray-500 dark:text-gray-400">Progress</th>
                      <th className="px-4 py-3 text-left font-medium text-gray-500 dark:text-gray-400">Status</th>
                      <th className="px-4 py-3 text-left font-medium text-gray-500 dark:text-gray-400">Started</th>
                      <th className="px-4 py-3" />
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-gray-200 dark:divide-gray-700">
                    {recentSessions.map((s) => (
                      <SessionRow key={s.id} session={s} onResume={handleResumeSession} />
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </div>
        )}
      </div>
    );
  }

  // ── Active session view ──
  if (sessionLoading) {
    return <PageSpinner label="Loading session…" />;
  }

  if (!activeSession) {
    return (
      <EmptyState
        icon={<AlertTriangle className="h-12 w-12" />}
        title="Session Not Found"
        description="This receiving session could not be loaded."
      />
    );
  }

  return (
    <div className="space-y-4">
      {/* ── Session Header ── */}
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div>
          <h2 className="text-lg font-semibold text-gray-900 dark:text-white">
            Receiving: PO #{activeSession.po_number || activeSession.po_id}
          </h2>
          <p className="text-sm text-gray-500 dark:text-gray-400">
            {activeSession.supplier_name} ·{' '}
            <Badge variant={activeSession.mode === 'scan' ? 'info' : 'default'}>
              {MODE_LABELS[activeSession.mode]}
            </Badge>
          </p>
        </div>
        <div className="flex gap-2">
          <button
            onClick={() => setShowCancelModal(true)}
            className="flex items-center gap-1.5 px-3 py-2 rounded-lg border border-gray-300 dark:border-gray-600 text-gray-700 dark:text-gray-300 text-sm hover:bg-gray-50 dark:hover:bg-gray-700 transition-colors"
          >
            <X className="h-4 w-4" />
            <span className="hidden sm:inline">Cancel</span>
          </button>
          <button
            onClick={() => setShowCommitModal(true)}
            disabled={progress.received === 0}
            className="flex items-center gap-1.5 px-4 py-2 rounded-lg bg-green-600 text-white text-sm font-medium hover:bg-green-700 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
          >
            <Check className="h-4 w-4" />
            <span className="hidden sm:inline">Commit</span>
          </button>
        </div>
      </div>

      {/* ── Progress Bar ── */}
      <div className="rounded-xl bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 p-4">
        <div className="flex items-center justify-between text-sm mb-2">
          <span className="text-gray-500 dark:text-gray-400">
            {progress.received} of {progress.expected} items received
          </span>
          <span className="font-medium text-gray-900 dark:text-white">
            {progress.percent}%
          </span>
        </div>
        <div className="w-full h-3 bg-gray-200 dark:bg-gray-700 rounded-full overflow-hidden">
          <div
            className="h-full bg-green-500 rounded-full transition-all duration-300"
            style={{ width: `${progress.percent}%` }}
          />
        </div>
      </div>

      {/* ── Scan Mode Input ── */}
      {activeSession.mode === 'scan' && (
        <div className="rounded-xl bg-blue-50 dark:bg-blue-900/20 border border-blue-200 dark:border-blue-700 p-4">
          <label className="block text-sm font-medium text-blue-700 dark:text-blue-400 mb-2">
            <ScanLine className="inline h-4 w-4 mr-1" />
            Scan Part QR / Enter Part ID
          </label>
          <div className="flex gap-2">
            <input
              ref={scanRef}
              type="text"
              value={scanInput}
              onChange={(e) => setScanInput(e.target.value)}
              onKeyDown={(e) => e.key === 'Enter' && handleScan()}
              placeholder="Scan or type part ID…"
              className="flex-1 px-4 py-2.5 rounded-lg border border-blue-300 dark:border-blue-600 bg-white dark:bg-gray-700 text-gray-900 dark:text-white placeholder-gray-400 dark:placeholder-gray-500 text-sm focus:ring-2 focus:ring-blue-500 min-h-[44px]"
            />
            <button
              onClick={handleScan}
              disabled={scanMutation.isPending}
              className="flex items-center gap-1.5 px-4 py-2.5 rounded-lg bg-blue-600 text-white text-sm font-medium hover:bg-blue-700 disabled:opacity-50 transition-colors min-h-[44px]"
            >
              {scanMutation.isPending ? (
                <Loader2 className="h-4 w-4 animate-spin" />
              ) : (
                <Search className="h-4 w-4" />
              )}
              Find
            </button>
          </div>
        </div>
      )}

      {/* ── Line Items ── */}
      <div className="rounded-xl bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-gray-200 dark:border-gray-700 bg-gray-50 dark:bg-gray-750">
                <th className="px-4 py-3 text-left font-medium text-gray-500 dark:text-gray-400">Part</th>
                <th className="px-4 py-3 text-center font-medium text-gray-500 dark:text-gray-400 w-20">Expected</th>
                <th className="px-4 py-3 text-center font-medium text-gray-500 dark:text-gray-400 w-28">Received</th>
                <th className="px-4 py-3 text-left font-medium text-gray-500 dark:text-gray-400 hidden md:table-cell">Zone</th>
                <th className="px-4 py-3 text-center font-medium text-gray-500 dark:text-gray-400 w-16">Status</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-200 dark:divide-gray-700">
              {activeSession.items.map((item) => (
                <ReceivingItemRow
                  key={item.id}
                  item={item}
                  zones={stagingZones ?? []}
                  onQtyChange={handleItemQtyChange}
                  onZoneChange={handleItemZoneChange}
                  isUpdating={updateItemMutation.isPending}
                />
              ))}
            </tbody>
          </table>
        </div>
        {activeSession.items.length === 0 && (
          <div className="p-8 text-center text-gray-500 dark:text-gray-400 text-sm">
            No items in this session. The PO may not have open lines.
          </div>
        )}
      </div>

      {/* ── Commit Confirmation Modal ── */}
      <Modal
        isOpen={showCommitModal}
        onClose={() => setShowCommitModal(false)}
        title="Commit Receiving Session?"
      >
        <p className="text-sm text-gray-600 dark:text-gray-400 mb-4">
          This will apply <strong>{progress.received}</strong> received items
          to PO #{activeSession.po_number || activeSession.po_id}.
          Stock movements will be created and the PO status will be updated.
        </p>
        <div className="flex justify-end gap-3">
          <button
            onClick={() => setShowCommitModal(false)}
            className="px-4 py-2 rounded-lg border border-gray-300 dark:border-gray-600 text-gray-700 dark:text-gray-300 text-sm hover:bg-gray-50 dark:hover:bg-gray-700"
          >
            Cancel
          </button>
          <button
            onClick={() => commitMutation.mutate(activeSession.id)}
            disabled={commitMutation.isPending}
            className="flex items-center gap-2 px-4 py-2 rounded-lg bg-green-600 text-white text-sm font-medium hover:bg-green-700 disabled:opacity-50"
          >
            {commitMutation.isPending && <Loader2 className="h-4 w-4 animate-spin" />}
            Commit & Receive
          </button>
        </div>
      </Modal>

      {/* ── Cancel Confirmation Modal ── */}
      <Modal
        isOpen={showCancelModal}
        onClose={() => setShowCancelModal(false)}
        title="Cancel Receiving Session?"
      >
        <p className="text-sm text-gray-600 dark:text-gray-400 mb-4">
          All progress in this session will be discarded. No items will be received.
        </p>
        <div className="flex justify-end gap-3">
          <button
            onClick={() => setShowCancelModal(false)}
            className="px-4 py-2 rounded-lg border border-gray-300 dark:border-gray-600 text-gray-700 dark:text-gray-300 text-sm hover:bg-gray-50 dark:hover:bg-gray-700"
          >
            Go Back
          </button>
          <button
            onClick={() => cancelMutation.mutate(activeSession.id)}
            disabled={cancelMutation.isPending}
            className="flex items-center gap-2 px-4 py-2 rounded-lg bg-red-600 text-white text-sm font-medium hover:bg-red-700 disabled:opacity-50"
          >
            {cancelMutation.isPending && <Loader2 className="h-4 w-4 animate-spin" />}
            Discard Session
          </button>
        </div>
      </Modal>
    </div>
  );
}


// ── Sub-components ──────────────────────────────────────────────


/** A single line item row in the receiving table. */
function ReceivingItemRow({
  item,
  zones,
  onQtyChange,
  onZoneChange,
  isUpdating,
}: {
  item: ReceivingSessionItemResponse;
  zones: StagingZoneResponse[];
  onQtyChange: (item: ReceivingSessionItemResponse, qty: number) => void;
  onZoneChange: (item: ReceivingSessionItemResponse, zoneId: number | null) => void;
  isUpdating: boolean;
}) {
  const [localQty, setLocalQty] = useState(item.received_qty);

  // Sync local state when item updates from server
  useEffect(() => {
    setLocalQty(item.received_qty);
  }, [item.received_qty]);

  const isComplete = localQty >= item.expected_qty;
  const isPartial = localQty > 0 && localQty < item.expected_qty;

  const handleBlur = () => {
    if (localQty !== item.received_qty) {
      onQtyChange(item, localQty);
    }
  };

  return (
    <tr className={`${isComplete ? 'bg-green-50/50 dark:bg-green-900/10' : ''}`}>
      {/* Part info */}
      <td className="px-4 py-3">
        <div className="font-medium text-gray-900 dark:text-white text-sm">
          {item.part_description || `Part #${item.part_id}`}
        </div>
        {item.part_number && (
          <div className="text-xs text-gray-500 dark:text-gray-400">
            {item.part_number}
          </div>
        )}
      </td>

      {/* Expected qty */}
      <td className="px-4 py-3 text-center text-gray-700 dark:text-gray-300">
        {item.expected_qty}
      </td>

      {/* Received qty input — large touch target */}
      <td className="px-4 py-3 text-center">
        <input
          type="number"
          min={0}
          max={item.expected_qty * 2}
          value={localQty}
          onChange={(e) => setLocalQty(Math.max(0, parseInt(e.target.value) || 0))}
          onBlur={handleBlur}
          onKeyDown={(e) => e.key === 'Enter' && (e.target as HTMLInputElement).blur()}
          className={`w-20 min-h-[44px] text-center rounded-lg border text-sm font-medium transition-colors ${
            isComplete
              ? 'border-green-300 dark:border-green-700 bg-green-50 dark:bg-green-900/30 text-green-700 dark:text-green-400'
              : isPartial
                ? 'border-amber-300 dark:border-amber-700 bg-amber-50 dark:bg-amber-900/30 text-amber-700 dark:text-amber-400'
                : 'border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-700 text-gray-900 dark:text-white'
          } focus:ring-2 focus:ring-primary-500 focus:border-transparent`}
        />
      </td>

      {/* Staging zone — hidden on mobile */}
      <td className="px-4 py-3 hidden md:table-cell">
        {zones.length > 0 ? (
          <select
            value={item.staging_zone_id ?? ''}
            onChange={(e) => onZoneChange(item, e.target.value ? parseInt(e.target.value) : null)}
            className="w-full min-h-[36px] rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-700 text-gray-900 dark:text-white text-xs px-2 py-1"
          >
            <option value="">—</option>
            {zones.map((z) => (
              <option key={z.id} value={z.id}>{z.label || z.qr_code}</option>
            ))}
          </select>
        ) : (
          <span className="text-xs text-gray-400 dark:text-gray-500">—</span>
        )}
      </td>

      {/* Status icon */}
      <td className="px-4 py-3 text-center">
        {isComplete ? (
          <CheckCircle2 className="h-5 w-5 text-green-500 mx-auto" />
        ) : isPartial ? (
          <Clock className="h-5 w-5 text-amber-500 mx-auto" />
        ) : (
          <div className="h-5 w-5 rounded-full border-2 border-gray-300 dark:border-gray-600 mx-auto" />
        )}
      </td>
    </tr>
  );
}


/** A single row in the session history table. */
function SessionRow({
  session,
  onResume,
}: {
  session: ReceivingSessionListItem;
  onResume: (id: number) => void;
}) {
  const statusColors: Record<string, string> = {
    in_progress: 'bg-amber-100 text-amber-800 dark:bg-amber-900/40 dark:text-amber-400',
    completed: 'bg-green-100 text-green-800 dark:bg-green-900/40 dark:text-green-400',
    cancelled: 'bg-gray-100 text-gray-600 dark:bg-gray-700 dark:text-gray-400',
  };

  return (
    <tr className="hover:bg-gray-50 dark:hover:bg-gray-750 transition-colors">
      <td className="px-4 py-3 font-medium text-gray-900 dark:text-white">
        #{session.po_number || session.po_id}
      </td>
      <td className="px-4 py-3 text-gray-700 dark:text-gray-300">
        {session.supplier_name || '—'}
      </td>
      <td className="px-4 py-3">
        <Badge variant="default">{MODE_LABELS[session.mode]}</Badge>
      </td>
      <td className="px-4 py-3 text-gray-700 dark:text-gray-300">
        {session.total_received}/{session.total_expected}
      </td>
      <td className="px-4 py-3">
        <span className={`inline-flex px-2 py-0.5 rounded-full text-xs font-medium ${statusColors[session.status] ?? ''}`}>
          {session.status.replace('_', ' ')}
        </span>
      </td>
      <td className="px-4 py-3 text-gray-500 dark:text-gray-400 text-xs">
        {session.created_at ? formatRelativeTime(session.created_at) : '—'}
      </td>
      <td className="px-4 py-3">
        {session.status === 'in_progress' && (
          <button
            onClick={() => onResume(session.id)}
            className="text-xs text-primary-600 dark:text-primary-400 hover:underline font-medium"
          >
            Resume
          </button>
        )}
      </td>
    </tr>
  );
}
