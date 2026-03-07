/**
 * TimeOffPage — time-off request management with three tabs:
 *   1. Pending Requests (manager approval queue)
 *   2. All Requests (historical view with filters)
 *   3. My Requests (self-service for any employee)
 *
 * Supports creating new requests, approving/denying pending ones,
 * and viewing historical records.
 */

import { useState, useEffect } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  Sun, Clock, Check, X, Plus, AlertTriangle, Calendar, User,
  Filter, ChevronDown,
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
} from '../../../api/scheduling';
import type {
  ScheduleExceptionResponse, ScheduleExceptionCreate, ExceptionType,
} from '../../../lib/types';


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

type TabId = 'pending' | 'all' | 'mine';

const TABS: { id: TabId; label: string; icon: typeof Clock }[] = [
  { id: 'pending', label: 'Pending', icon: Clock },
  { id: 'all', label: 'All Requests', icon: Calendar },
  { id: 'mine', label: 'My Requests', icon: User },
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
      {isLoading ? (
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
