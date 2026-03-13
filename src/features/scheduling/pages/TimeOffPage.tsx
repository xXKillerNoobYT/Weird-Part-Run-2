/**
 * TimeOffPage — time-off request management with three tabs:
 *   1. Pending Requests (manager approval queue)
 *   2. All Requests (historical view with filters)
 *   3. My Requests (self-service for any employee)
 *
 * Supports creating new requests, approving/denying pending ones,
 * and viewing historical records.
 */

import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  Sun, Clock, Check, X, Plus, Calendar, User,
  Wallet, TrendingUp, TrendingDown, RefreshCw, Settings, ChevronDown, ChevronUp,
} from 'lucide-react';
import { PageSpinner } from '../../../components/ui/Spinner';
import { EmptyState } from '../../../components/ui/EmptyState';
import { Badge } from '../../../components/ui/Badge';
import { Button } from '../../../components/ui/Button';
import { Input } from '../../../components/ui/Input';
import { Modal } from '../../../components/ui/Modal';
import { Card } from '../../../components/ui/Card';
import { useAuthStore } from '../../../stores/auth-store';
import { PERMISSIONS } from '../../../lib/constants';
import {
  getPendingTimeOff,
  getUserTimeOff,
  requestTimeOff,
  approveTimeOff,
  denyTimeOff,
  deleteTimeOff,
  getPtoBalance,
  getAllPtoBalances,
  createPtoPolicy,
  createPtoTransaction,
  runPtoAccruals,
} from '../../../api/scheduling';
import type {
  ScheduleExceptionResponse, ExceptionType,
} from '../../../lib/types';
import type {
  PtoBalanceSummary, PtoTransaction,
} from '../../../api/scheduling';


// ── Constants ─────────────────────────────────────────────────────

const EXCEPTION_TYPE_LABELS: Record<ExceptionType, string> = {
  time_off: 'Time Off',
  sick: 'Sick',
  vacation: 'Vacation',
  holiday: 'Holiday',
  modified_hours: 'Modified Hours',
  unpaid_leave: 'Unpaid Leave',
  jury_duty: 'Jury Duty',
  bereavement: 'Bereavement',
};

const EXCEPTION_TYPE_BADGE: Record<ExceptionType, 'info' | 'warning' | 'success' | 'danger' | 'neutral'> = {
  time_off: 'neutral',
  sick: 'warning',
  vacation: 'info',
  holiday: 'success',
  modified_hours: 'neutral',
  unpaid_leave: 'danger',
  jury_duty: 'neutral',
  bereavement: 'danger',
};

type TabId = 'pending' | 'all' | 'mine' | 'pto';

const TABS: { id: TabId; label: string; icon: typeof Clock }[] = [
  { id: 'pending', label: 'Pending', icon: Clock },
  { id: 'all', label: 'All Requests', icon: Calendar },
  { id: 'mine', label: 'My Requests', icon: User },
  { id: 'pto', label: 'PTO Balance', icon: Wallet },
];


// ═══════════════════════════════════════════════════════════════════
// MAIN PAGE
// ═══════════════════════════════════════════════════════════════════

export function TimeOffPage() {
  const queryClient = useQueryClient();
  const { user, hasPermission } = useAuthStore();
  const canApprove = hasPermission(PERMISSIONS.APPROVE_TIME_OFF);
  const canRequest = hasPermission(PERMISSIONS.REQUEST_TIME_OFF);

  const [activeTab, setActiveTab] = useState<TabId>(canApprove ? 'pending' : 'mine');
  const [showCreateModal, setShowCreateModal] = useState(false);

  // ── Pending requests ─────────────────────────────────────────────
  // Always enabled so the "All" tab can combine pending + mine
  const { data: pending, isLoading: pendingLoading } = useQuery({
    queryKey: ['time-off', 'pending'],
    queryFn: () => getPendingTimeOff(),
    enabled: canApprove,
    staleTime: 15_000,
  });

  // ── My requests ──────────────────────────────────────────────────
  const { data: myRequests, isLoading: myLoading } = useQuery({
    queryKey: ['time-off', 'user', user?.id],
    queryFn: () => getUserTimeOff(user!.id),
    enabled: !!user?.id,
    staleTime: 30_000,
  });

  // ── All requests = pending union my (manager gets broader view) ──
  // For now, show pending + my. A full "all" would need a backend endpoint.
  const allRequests = activeTab === 'all' ? [...(pending ?? []), ...(myRequests ?? [])] : [];
  // Deduplicate by id
  const allDeduped = activeTab === 'all'
    ? Array.from(new Map(allRequests.map(r => [r.id, r])).values())
      .sort((a, b) => b.exception_date.localeCompare(a.exception_date))
    : [];

  const isLoading = (activeTab === 'pending' && pendingLoading)
    || (activeTab === 'mine' && myLoading)
    || (activeTab === 'all' && (pendingLoading || myLoading));

  // ── Mutations ────────────────────────────────────────────────────
  const approveMut = useMutation({
    mutationFn: approveTimeOff,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['time-off'] });
    },
  });

  const denyMut = useMutation({
    mutationFn: denyTimeOff,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['time-off'] });
    },
  });

  const deleteMut = useMutation({
    mutationFn: deleteTimeOff,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['time-off'] });
    },
  });

  // ── Request lists ────────────────────────────────────────────────
  function getActiveList(): ScheduleExceptionResponse[] {
    switch (activeTab) {
      case 'pending': return pending ?? [];
      case 'mine': return myRequests ?? [];
      case 'all': return allDeduped;
      default: return [];
    }
  }

  const requests = getActiveList();

  return (
    <div className="space-y-4">
      {/* ── Header ──────────────────────────────────────────────── */}
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div className="flex items-center gap-3">
          <Sun size={24} className="text-amber-500 dark:text-amber-400" />
          <div>
            <h1 className="text-xl font-bold text-gray-900 dark:text-white">
              Time Off
            </h1>
            <p className="text-sm text-gray-500 dark:text-gray-400">
              {requests.length} request{requests.length !== 1 ? 's' : ''}
            </p>
          </div>
        </div>

        {canRequest && (
          <Button variant="primary" onClick={() => setShowCreateModal(true)}>
            <Plus size={16} />
            <span className="hidden sm:inline ml-1">Request Time Off</span>
          </Button>
        )}
      </div>

      {/* ── Tabs ─────────────────────────────────────────────────── */}
      <div className="flex gap-1 overflow-x-auto pb-1 border-b border-gray-200 dark:border-gray-700">
        {TABS.map(tab => {
          // Hide pending tab from non-managers
          if (tab.id === 'pending' && !canApprove) return null;
          const Icon = tab.icon;
          const active = activeTab === tab.id;
          return (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id)}
              className={`
                flex items-center gap-1.5 px-4 py-2 text-sm font-medium border-b-2 whitespace-nowrap transition-colors
                ${active
                  ? 'border-blue-600 text-blue-600 dark:text-blue-400 dark:border-blue-400'
                  : 'border-transparent text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-300'
                }
              `}
            >
              <Icon size={14} />
              {tab.label}
              {tab.id === 'pending' && pending && pending.length > 0 && (
                <Badge variant="warning" className="text-[10px] ml-1">
                  {pending.length}
                </Badge>
              )}
            </button>
          );
        })}
      </div>

      {/* ── Content ──────────────────────────────────────────────── */}
      {activeTab === 'pto' ? (
        <PtoBalanceTab userId={user?.id ?? 0} canManage={canApprove} />
      ) : isLoading ? (
        <PageSpinner />
      ) : requests.length === 0 ? (
        <EmptyState
          icon={Sun}
          title={activeTab === 'pending' ? 'No pending requests' : 'No time-off requests'}
          description={
            activeTab === 'pending'
              ? 'All time-off requests have been reviewed.'
              : activeTab === 'mine'
              ? 'You haven\'t submitted any time-off requests.'
              : 'No time-off records found.'
          }
        />
      ) : (
        <div className="space-y-2">
          {requests.map(req => (
            <TimeOffCard
              key={req.id}
              request={req}
              showActions={activeTab === 'pending' && canApprove}
              showDelete={activeTab === 'mine' && !req.is_approved}
              onApprove={() => approveMut.mutate(req.id)}
              onDeny={() => denyMut.mutate(req.id)}
              onDelete={() => deleteMut.mutate(req.id)}
            />
          ))}
        </div>
      )}

      {/* ── Create Modal ────────────────────────────────────────── */}
      {showCreateModal && (
        <CreateTimeOffModal
          onClose={() => setShowCreateModal(false)}
          onSuccess={() => {
            setShowCreateModal(false);
            queryClient.invalidateQueries({ queryKey: ['time-off'] });
          }}
        />
      )}
    </div>
  );
}


// ═══════════════════════════════════════════════════════════════════
// TIME OFF CARD
// ═══════════════════════════════════════════════════════════════════

function TimeOffCard({
  request: req,
  showActions,
  showDelete,
  onApprove,
  onDeny,
  onDelete,
}: {
  request: ScheduleExceptionResponse;
  showActions: boolean;
  showDelete: boolean;
  onApprove: () => void;
  onDeny: () => void;
  onDelete: () => void;
}) {
  const dateDisplay = new Date(req.exception_date + 'T00:00').toLocaleDateString('en-US', {
    weekday: 'short', month: 'short', day: 'numeric', year: 'numeric',
  });

  return (
    <Card className="p-3">
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0 flex-1">
          {/* Name + date */}
          <div className="flex items-center gap-2 flex-wrap">
            {req.user_name && (
              <span className="font-medium text-sm text-gray-900 dark:text-white">
                {req.user_name}
              </span>
            )}
            <span className="text-sm text-gray-500 dark:text-gray-400">
              {dateDisplay}
            </span>
          </div>

          {/* Type + status badges */}
          <div className="flex items-center gap-2 mt-1">
            <Badge variant={EXCEPTION_TYPE_BADGE[req.exception_type]}>
              {EXCEPTION_TYPE_LABELS[req.exception_type]}
            </Badge>
            {req.is_approved ? (
              <Badge variant="success">Approved</Badge>
            ) : (
              <Badge variant="warning">Pending</Badge>
            )}
          </div>

          {/* Time range if partial day */}
          {(req.start_time || req.end_time) && (
            <div className="flex items-center gap-1 text-xs text-gray-500 dark:text-gray-400 mt-1">
              <Clock size={10} />
              {req.start_time ?? 'Start'} – {req.end_time ?? 'End'}
            </div>
          )}

          {/* Reason */}
          {req.reason && (
            <p className="text-xs text-gray-600 dark:text-gray-400 mt-1">
              {req.reason}
            </p>
          )}

          {/* Approved by */}
          {req.approved_by_name && (
            <div className="text-[10px] text-gray-400 dark:text-gray-500 mt-1">
              Approved by {req.approved_by_name}
            </div>
          )}
        </div>

        {/* Actions */}
        <div className="flex items-center gap-1 flex-shrink-0">
          {showActions && (
            <>
              <Button size="sm" variant="success" onClick={onApprove} title="Approve">
                <Check size={14} />
                <span className="hidden sm:inline ml-1">Approve</span>
              </Button>
              <Button size="sm" variant="danger" onClick={onDeny} title="Deny">
                <X size={14} />
                <span className="hidden sm:inline ml-1">Deny</span>
              </Button>
            </>
          )}
          {showDelete && (
            <Button size="sm" variant="danger" onClick={onDelete} title="Delete">
              <X size={14} />
            </Button>
          )}
        </div>
      </div>
    </Card>
  );
}


// ═══════════════════════════════════════════════════════════════════
// CREATE TIME OFF MODAL
// ═══════════════════════════════════════════════════════════════════

function CreateTimeOffModal({
  onClose,
  onSuccess,
}: {
  onClose: () => void;
  onSuccess: () => void;
}) {
  const [exceptionDate, setExceptionDate] = useState('');
  const [exceptionType, setExceptionType] = useState<ExceptionType>('time_off');
  const [startTime, setStartTime] = useState('');
  const [endTime, setEndTime] = useState('');
  const [reason, setReason] = useState('');
  const [notes, setNotes] = useState('');
  const [saving, setSaving] = useState(false);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!exceptionDate) return;

    setSaving(true);
    try {
      await requestTimeOff({
        exception_date: exceptionDate,
        exception_type: exceptionType,
        start_time: startTime || undefined,
        end_time: endTime || undefined,
        reason: reason || undefined,
        notes: notes || undefined,
      });
      onSuccess();
    } catch (err) {
      console.error('Time off request failed:', err);
    } finally {
      setSaving(false);
    }
  }

  return (
    <Modal isOpen onClose={onClose} title="Request Time Off">
      <form onSubmit={handleSubmit} className="space-y-4">
        {/* Date */}
        <div>
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
            Date *
          </label>
          <Input
            type="date"
            value={exceptionDate}
            onChange={e => setExceptionDate(e.target.value)}
            required
          />
        </div>

        {/* Type */}
        <div>
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
            Type
          </label>
          <select
            value={exceptionType}
            onChange={e => setExceptionType(e.target.value as ExceptionType)}
            className="w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm text-gray-900 dark:text-white"
          >
            {Object.entries(EXCEPTION_TYPE_LABELS).map(([val, label]) => (
              <option key={val} value={val}>{label}</option>
            ))}
          </select>
        </div>

        {/* Partial-day times */}
        <div className="grid grid-cols-2 gap-3">
          <div>
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
              Start Time
            </label>
            <Input
              type="time"
              value={startTime}
              onChange={e => setStartTime(e.target.value)}
              placeholder="Leave blank for full day"
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
              End Time
            </label>
            <Input
              type="time"
              value={endTime}
              onChange={e => setEndTime(e.target.value)}
            />
          </div>
        </div>
        <p className="text-xs text-gray-400 dark:text-gray-500 -mt-2">
          Leave times blank for a full-day request.
        </p>

        {/* Reason */}
        <div>
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
            Reason
          </label>
          <textarea
            value={reason}
            onChange={e => setReason(e.target.value)}
            rows={2}
            className="w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm text-gray-900 dark:text-white resize-none"
            placeholder="Why are you requesting time off?"
          />
        </div>

        {/* Notes */}
        <div>
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
            Notes
          </label>
          <textarea
            value={notes}
            onChange={e => setNotes(e.target.value)}
            rows={2}
            className="w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm text-gray-900 dark:text-white resize-none"
            placeholder="Any additional notes..."
          />
        </div>

        {/* Actions */}
        <div className="flex justify-end gap-2 pt-2">
          <Button type="button" variant="secondary" onClick={onClose}>
            Cancel
          </Button>
          <Button type="submit" variant="primary" disabled={saving || !exceptionDate}>
            {saving ? 'Submitting...' : 'Submit Request'}
          </Button>
        </div>
      </form>
    </Modal>
  );
}


// ═══════════════════════════════════════════════════════════════════
// PTO BALANCE TAB
// ═══════════════════════════════════════════════════════════════════

const TXN_TYPE_LABELS: Record<string, { label: string; variant: 'success' | 'danger' | 'info' | 'warning' | 'neutral' }> = {
  accrual:    { label: 'Accrual',    variant: 'success' },
  usage:      { label: 'Usage',      variant: 'danger' },
  adjustment: { label: 'Adjustment', variant: 'info' },
  carryover:  { label: 'Carryover',  variant: 'warning' },
  forfeit:    { label: 'Forfeit',    variant: 'neutral' },
};

function PtoBalanceTab({ userId, canManage }: { userId: number; canManage: boolean }) {
  const queryClient = useQueryClient();
  const [showAllBalances, setShowAllBalances] = useState(false);
  const [showPolicyModal, setShowPolicyModal] = useState(false);
  const [showAdjustModal, setShowAdjustModal] = useState(false);
  const [policyTargetUser, setPolicyTargetUser] = useState<number | null>(null);
  const [adjustTargetUser, setAdjustTargetUser] = useState<number | null>(null);
  const [showTxns, setShowTxns] = useState(true);

  // ── My PTO balance ────────────────────────────────────────────
  const { data: myBalance, isLoading } = useQuery({
    queryKey: ['pto', 'balance', userId],
    queryFn: () => getPtoBalance(userId),
    enabled: userId > 0,
    staleTime: 30_000,
  });

  // ── All balances (manager view) ──────────────────────────────
  const { data: allBalances, isLoading: allLoading } = useQuery({
    queryKey: ['pto', 'balances'],
    queryFn: getAllPtoBalances,
    enabled: canManage && showAllBalances,
    staleTime: 30_000,
  });

  // ── Run accruals mutation ────────────────────────────────────
  const accrualMut = useMutation({
    mutationFn: runPtoAccruals,
    onSuccess: (data) => {
      queryClient.invalidateQueries({ queryKey: ['pto'] });
      alert(`Accruals processed: ${data.processed} accrued, ${data.skipped} skipped (of ${data.total_policies} policies)`);
    },
  });

  if (isLoading) return <PageSpinner />;

  return (
    <div className="space-y-4">
      {/* ── My Balance Card ───────────────────────────────────── */}
      <Card className="p-5">
        <div className="flex items-start justify-between flex-wrap gap-3">
          <div>
            <h2 className="text-lg font-semibold text-gray-900 dark:text-white flex items-center gap-2">
              <Wallet size={18} className="text-blue-500" />
              My PTO Balance
            </h2>
            {myBalance?.policy ? (
              <p className="text-xs text-gray-500 dark:text-gray-400 mt-0.5">
                Policy: {myBalance.policy.policy_name} &middot; {myBalance.policy.accrual_rate} hrs/{myBalance.policy.accrual_period}
                {myBalance.policy.max_balance != null && ` · Max: ${myBalance.policy.max_balance} hrs`}
              </p>
            ) : (
              <p className="text-xs text-amber-600 dark:text-amber-400 mt-0.5">
                No active PTO policy — contact your manager
              </p>
            )}
          </div>

          <div className="text-right">
            <div className="text-3xl font-bold text-gray-900 dark:text-white">
              {(myBalance?.current_balance ?? 0).toFixed(1)}
              <span className="text-sm font-normal text-gray-500 dark:text-gray-400 ml-1">hrs</span>
            </div>
          </div>
        </div>

        {/* YTD stats row */}
        <div className="grid grid-cols-2 gap-3 mt-4">
          <div className="bg-emerald-50 dark:bg-emerald-900/20 rounded-lg p-3 flex items-center gap-2">
            <TrendingUp size={16} className="text-emerald-600 dark:text-emerald-400" />
            <div>
              <div className="text-sm font-semibold text-emerald-700 dark:text-emerald-300">
                {(myBalance?.accrued_ytd ?? 0).toFixed(1)} hrs
              </div>
              <div className="text-[10px] text-emerald-600 dark:text-emerald-400">Accrued YTD</div>
            </div>
          </div>
          <div className="bg-red-50 dark:bg-red-900/20 rounded-lg p-3 flex items-center gap-2">
            <TrendingDown size={16} className="text-red-600 dark:text-red-400" />
            <div>
              <div className="text-sm font-semibold text-red-700 dark:text-red-300">
                {(myBalance?.used_ytd ?? 0).toFixed(1)} hrs
              </div>
              <div className="text-[10px] text-red-600 dark:text-red-400">Used YTD</div>
            </div>
          </div>
        </div>
      </Card>

      {/* ── Recent Transactions ───────────────────────────────── */}
      {myBalance && myBalance.recent_transactions.length > 0 && (
        <Card className="overflow-hidden">
          <button
            onClick={() => setShowTxns(!showTxns)}
            className="w-full flex items-center justify-between p-3 hover:bg-gray-50 dark:hover:bg-gray-800/50 transition-colors"
          >
            <span className="text-sm font-semibold text-gray-700 dark:text-gray-300">
              Recent Transactions ({myBalance.recent_transactions.length})
            </span>
            {showTxns ? <ChevronUp size={14} /> : <ChevronDown size={14} />}
          </button>
          {showTxns && (
            <div className="border-t border-gray-100 dark:border-gray-800 divide-y divide-gray-100 dark:divide-gray-800">
              {myBalance.recent_transactions.map((txn: PtoTransaction) => (
                <TransactionRow key={txn.id} txn={txn} />
              ))}
            </div>
          )}
        </Card>
      )}

      {/* ── Manager Controls ──────────────────────────────────── */}
      {canManage && (
        <Card className="p-4 space-y-3">
          <h3 className="text-sm font-semibold text-gray-700 dark:text-gray-300 flex items-center gap-2">
            <Settings size={14} />
            Manager Controls
          </h3>
          <div className="flex flex-wrap gap-2">
            <Button
              size="sm"
              variant="secondary"
              onClick={() => accrualMut.mutate()}
              disabled={accrualMut.isPending}
            >
              <RefreshCw size={14} className={accrualMut.isPending ? 'animate-spin' : ''} />
              <span className="ml-1">Run Accruals</span>
            </Button>
            <Button
              size="sm"
              variant="secondary"
              onClick={() => setShowAllBalances(!showAllBalances)}
            >
              <User size={14} />
              <span className="ml-1">{showAllBalances ? 'Hide' : 'View'} All Balances</span>
            </Button>
            <Button
              size="sm"
              variant="secondary"
              onClick={() => { setPolicyTargetUser(null); setShowPolicyModal(true); }}
            >
              <Settings size={14} />
              <span className="ml-1">Manage Policy</span>
            </Button>
            <Button
              size="sm"
              variant="secondary"
              onClick={() => { setAdjustTargetUser(null); setShowAdjustModal(true); }}
            >
              <Plus size={14} />
              <span className="ml-1">Manual Adjustment</span>
            </Button>
          </div>

          {/* All balances table */}
          {showAllBalances && (
            <div className="mt-3">
              {allLoading ? (
                <PageSpinner />
              ) : !allBalances || allBalances.length === 0 ? (
                <p className="text-sm text-gray-400 dark:text-gray-500 italic">No PTO policies configured.</p>
              ) : (
                <div className="overflow-x-auto">
                  <table className="w-full text-sm">
                    <thead>
                      <tr className="border-b border-gray-200 dark:border-gray-700 text-left">
                        <th className="py-2 px-2 font-medium text-gray-500 dark:text-gray-400">Employee</th>
                        <th className="py-2 px-2 font-medium text-gray-500 dark:text-gray-400">Balance</th>
                        <th className="py-2 px-2 font-medium text-gray-500 dark:text-gray-400 hidden sm:table-cell">Policy</th>
                        <th className="py-2 px-2 font-medium text-gray-500 dark:text-gray-400 hidden sm:table-cell">Rate</th>
                        <th className="py-2 px-2 font-medium text-gray-500 dark:text-gray-400 hidden md:table-cell">Max</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-gray-100 dark:divide-gray-800">
                      {allBalances.map((b: PtoBalanceSummary) => (
                        <tr key={b.user_id} className="hover:bg-gray-50 dark:hover:bg-gray-800/50">
                          <td className="py-2 px-2 font-medium text-gray-900 dark:text-white">{b.user_name}</td>
                          <td className="py-2 px-2">
                            <span className={`font-semibold ${b.current_balance <= 0 ? 'text-red-600' : 'text-gray-900 dark:text-white'}`}>
                              {b.current_balance.toFixed(1)} hrs
                            </span>
                          </td>
                          <td className="py-2 px-2 hidden sm:table-cell text-gray-600 dark:text-gray-400">{b.policy_name}</td>
                          <td className="py-2 px-2 hidden sm:table-cell text-gray-600 dark:text-gray-400">
                            {b.accrual_rate} / {b.accrual_period}
                          </td>
                          <td className="py-2 px-2 hidden md:table-cell text-gray-600 dark:text-gray-400">
                            {b.max_balance != null ? `${b.max_balance} hrs` : '∞'}
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )}
            </div>
          )}
        </Card>
      )}

      {/* ── Policy Modal ──────────────────────────────────────── */}
      {showPolicyModal && (
        <PtoPolicyModal
          targetUserId={policyTargetUser}
          onClose={() => setShowPolicyModal(false)}
          onSuccess={() => {
            setShowPolicyModal(false);
            queryClient.invalidateQueries({ queryKey: ['pto'] });
          }}
        />
      )}

      {/* ── Adjustment Modal ──────────────────────────────────── */}
      {showAdjustModal && (
        <PtoAdjustmentModal
          targetUserId={adjustTargetUser}
          onClose={() => setShowAdjustModal(false)}
          onSuccess={() => {
            setShowAdjustModal(false);
            queryClient.invalidateQueries({ queryKey: ['pto'] });
          }}
        />
      )}
    </div>
  );
}


// ── Transaction Row ──────────────────────────────────────────────

function TransactionRow({ txn }: { txn: PtoTransaction }) {
  const cfg = TXN_TYPE_LABELS[txn.transaction_type] ?? { label: txn.transaction_type, variant: 'neutral' as const };
  const isPositive = txn.hours > 0;
  const dateStr = new Date(txn.effective_date + 'T00:00').toLocaleDateString('en-US', {
    month: 'short', day: 'numeric', year: 'numeric',
  });

  return (
    <div className="flex items-center justify-between gap-2 px-3 py-2">
      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-2">
          <Badge variant={cfg.variant} className="text-[10px]">{cfg.label}</Badge>
          <span className="text-xs text-gray-500 dark:text-gray-400">{dateStr}</span>
        </div>
        {txn.note && (
          <p className="text-xs text-gray-500 dark:text-gray-400 mt-0.5 truncate">{txn.note}</p>
        )}
      </div>
      <div className="flex items-center gap-2 flex-shrink-0">
        <span className={`text-sm font-semibold ${isPositive ? 'text-emerald-600' : 'text-red-600'}`}>
          {isPositive ? '+' : ''}{txn.hours.toFixed(1)}
        </span>
        <span className="text-xs text-gray-400 dark:text-gray-500">
          → {txn.balance_after.toFixed(1)}
        </span>
      </div>
    </div>
  );
}


// ═══════════════════════════════════════════════════════════════════
// PTO POLICY MODAL (manager)
// ═══════════════════════════════════════════════════════════════════

function PtoPolicyModal({
  targetUserId,
  onClose,
  onSuccess,
}: {
  targetUserId: number | null;
  onClose: () => void;
  onSuccess: () => void;
}) {
  const [userId, setUserId] = useState(targetUserId?.toString() ?? '');
  const [policyName, setPolicyName] = useState('Standard PTO');
  const [accrualRate, setAccrualRate] = useState('3.33');
  const [accrualPeriod, setAccrualPeriod] = useState<'weekly' | 'biweekly' | 'monthly'>('monthly');
  const [maxBalance, setMaxBalance] = useState('');
  const [carryoverLimit, setCarryoverLimit] = useState('');
  const [startDate, setStartDate] = useState(new Date().toISOString().slice(0, 10));
  const [saving, setSaving] = useState(false);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!userId || !startDate) return;

    setSaving(true);
    try {
      await createPtoPolicy({
        user_id: parseInt(userId),
        policy_name: policyName,
        accrual_rate: parseFloat(accrualRate),
        accrual_period: accrualPeriod,
        max_balance: maxBalance ? parseFloat(maxBalance) : null,
        carryover_limit: carryoverLimit ? parseFloat(carryoverLimit) : null,
        start_date: startDate,
      });
      onSuccess();
    } catch (err) {
      console.error('Failed to create PTO policy:', err);
    } finally {
      setSaving(false);
    }
  }

  return (
    <Modal isOpen onClose={onClose} title="Create PTO Policy">
      <form onSubmit={handleSubmit} className="space-y-4">
        <div>
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
            Employee ID *
          </label>
          <Input
            type="number"
            value={userId}
            onChange={e => setUserId(e.target.value)}
            required
            min={1}
          />
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
            Policy Name
          </label>
          <Input value={policyName} onChange={e => setPolicyName(e.target.value)} />
        </div>

        <div className="grid grid-cols-2 gap-3">
          <div>
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
              Accrual Rate (hrs)
            </label>
            <Input
              type="number"
              step="0.01"
              value={accrualRate}
              onChange={e => setAccrualRate(e.target.value)}
              min={0}
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
              Accrual Period
            </label>
            <select
              value={accrualPeriod}
              onChange={e => setAccrualPeriod(e.target.value as 'weekly' | 'biweekly' | 'monthly')}
              className="w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm text-gray-900 dark:text-white"
            >
              <option value="weekly">Weekly</option>
              <option value="biweekly">Biweekly</option>
              <option value="monthly">Monthly</option>
            </select>
          </div>
        </div>

        <div className="grid grid-cols-2 gap-3">
          <div>
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
              Max Balance (hrs)
            </label>
            <Input
              type="number"
              step="0.01"
              value={maxBalance}
              onChange={e => setMaxBalance(e.target.value)}
              placeholder="Unlimited"
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
              Carryover Limit (hrs)
            </label>
            <Input
              type="number"
              step="0.01"
              value={carryoverLimit}
              onChange={e => setCarryoverLimit(e.target.value)}
              placeholder="Unlimited"
            />
          </div>
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
            Start Date *
          </label>
          <Input type="date" value={startDate} onChange={e => setStartDate(e.target.value)} required />
        </div>

        <div className="flex justify-end gap-2 pt-2">
          <Button type="button" variant="secondary" onClick={onClose}>Cancel</Button>
          <Button type="submit" variant="primary" disabled={saving || !userId || !startDate}>
            {saving ? 'Creating...' : 'Create Policy'}
          </Button>
        </div>
      </form>
    </Modal>
  );
}


// ═══════════════════════════════════════════════════════════════════
// PTO ADJUSTMENT MODAL (manager)
// ═══════════════════════════════════════════════════════════════════

function PtoAdjustmentModal({
  targetUserId,
  onClose,
  onSuccess,
}: {
  targetUserId: number | null;
  onClose: () => void;
  onSuccess: () => void;
}) {
  const [userId, setUserId] = useState(targetUserId?.toString() ?? '');
  const [txnType, setTxnType] = useState<'adjustment' | 'usage' | 'forfeit'>('adjustment');
  const [hours, setHours] = useState('');
  const [note, setNote] = useState('');
  const [effectiveDate, setEffectiveDate] = useState(new Date().toISOString().slice(0, 10));
  const [saving, setSaving] = useState(false);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!userId || !hours || !effectiveDate) return;

    setSaving(true);
    try {
      await createPtoTransaction({
        user_id: parseInt(userId),
        transaction_type: txnType,
        hours: parseFloat(hours),
        note: note || undefined,
        effective_date: effectiveDate,
      });
      onSuccess();
    } catch (err) {
      console.error('Failed to create PTO transaction:', err);
    } finally {
      setSaving(false);
    }
  }

  return (
    <Modal isOpen onClose={onClose} title="Manual PTO Adjustment">
      <form onSubmit={handleSubmit} className="space-y-4">
        <div>
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
            Employee ID *
          </label>
          <Input
            type="number"
            value={userId}
            onChange={e => setUserId(e.target.value)}
            required
            min={1}
          />
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
            Type
          </label>
          <select
            value={txnType}
            onChange={e => setTxnType(e.target.value as 'adjustment' | 'usage' | 'forfeit')}
            className="w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm text-gray-900 dark:text-white"
          >
            <option value="adjustment">Adjustment (+/-)</option>
            <option value="usage">Usage (deduct)</option>
            <option value="forfeit">Forfeit (deduct)</option>
          </select>
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
            Hours * <span className="text-xs text-gray-400">(positive to add, negative to deduct)</span>
          </label>
          <Input
            type="number"
            step="0.25"
            value={hours}
            onChange={e => setHours(e.target.value)}
            required
          />
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
            Effective Date *
          </label>
          <Input type="date" value={effectiveDate} onChange={e => setEffectiveDate(e.target.value)} required />
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
            Note
          </label>
          <textarea
            value={note}
            onChange={e => setNote(e.target.value)}
            rows={2}
            className="w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm text-gray-900 dark:text-white resize-none"
            placeholder="Reason for this adjustment..."
          />
        </div>

        <div className="flex justify-end gap-2 pt-2">
          <Button type="button" variant="secondary" onClick={onClose}>Cancel</Button>
          <Button type="submit" variant="primary" disabled={saving || !userId || !hours}>
            {saving ? 'Saving...' : 'Record Adjustment'}
          </Button>
        </div>
      </form>
    </Modal>
  );
}
