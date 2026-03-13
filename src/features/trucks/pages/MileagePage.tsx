/**
 * MileagePage — fleet-wide mileage tracking with daily logs, trip breakdown,
 * estimation calculator, and reimbursement management.
 *
 * Sub-tabs:
 *   Daily Logs — per-vehicle daily odometer logs + trip leg expansion
 *   Reimbursements — private vehicle mileage reimbursement workflow
 *
 * Accessible via Trucks > Mileage tab.
 */

import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  Gauge,
  DollarSign,
  Plus,
  ChevronDown,
  ChevronRight,
  Check,
  X,
  Clock,
} from 'lucide-react';
import { PageSpinner } from '../../../components/ui/Spinner';
import { EmptyState } from '../../../components/ui/EmptyState';
import { Badge } from '../../../components/ui/Badge';
import { Button } from '../../../components/ui/Button';
import { Input } from '../../../components/ui/Input';
import { Modal } from '../../../components/ui/Modal';
import { useAuthStore } from '../../../stores/auth-store';
import { PERMISSIONS } from '../../../lib/constants';
import {
  listVehicles,
  logMileage,
  getMileageLogs,
  getMileageSummary,
  listReimbursements,
  createReimbursement,
  approveReimbursement,
} from '../../../api/vehicles';
import type {
  MileageLog,
  TripLeg,
} from '../../../lib/types';

type SubView = 'logs' | 'reimbursements';

export function MileagePage() {
  const { hasPermission, user } = useAuthStore();
  const canManageFleet = hasPermission(PERMISSIONS.MANAGE_FLEET);

  const [subView, setSubView] = useState<SubView>('logs');

  return (
    <div className="space-y-4">
      {/* Sub-view toggle */}
      <div className="flex items-center gap-2">
        <button
          onClick={() => setSubView('logs')}
          className={`px-3 py-1.5 text-sm rounded-lg transition-colors min-h-[36px] ${
            subView === 'logs'
              ? 'bg-blue-100 dark:bg-blue-900/40 text-blue-700 dark:text-blue-300 font-medium'
              : 'text-gray-600 dark:text-gray-400 hover:bg-gray-100 dark:hover:bg-gray-800'
          }`}
        >
          <span className="flex items-center gap-1.5">
            <Gauge className="h-4 w-4" />
            <span className="hidden sm:inline">Daily Logs</span>
          </span>
        </button>
        <button
          onClick={() => setSubView('reimbursements')}
          className={`px-3 py-1.5 text-sm rounded-lg transition-colors min-h-[36px] ${
            subView === 'reimbursements'
              ? 'bg-blue-100 dark:bg-blue-900/40 text-blue-700 dark:text-blue-300 font-medium'
              : 'text-gray-600 dark:text-gray-400 hover:bg-gray-100 dark:hover:bg-gray-800'
          }`}
        >
          <span className="flex items-center gap-1.5">
            <DollarSign className="h-4 w-4" />
            <span className="hidden sm:inline">Reimbursements</span>
          </span>
        </button>
      </div>

      {subView === 'logs' ? (
        <DailyLogsView canManageFleet={canManageFleet} />
      ) : (
        <ReimbursementsView canManageFleet={canManageFleet} userId={user?.id} />
      )}
    </div>
  );
}


// ── Daily Logs View ───────────────────────────────────────────────────

function DailyLogsView({ canManageFleet: _canManageFleet }: { canManageFleet: boolean }) {
  const [selectedVehicle, setSelectedVehicle] = useState<number | 'all'>('all');
  const [showLogMileage, setShowLogMileage] = useState(false);

  const { data: vehicles } = useQuery({
    queryKey: ['vehicles-active'],
    queryFn: () => listVehicles({ status: 'active' }),
    staleTime: 60_000,
  });

  // When a vehicle is selected, fetch its mileage logs
  const vehicleId = selectedVehicle === 'all' ? undefined : selectedVehicle;

  const { data: logs, isLoading } = useQuery({
    queryKey: ['mileage-logs', vehicleId],
    queryFn: () => getMileageLogs(vehicleId!, { limit: 50 }),
    staleTime: 30_000,
    enabled: vehicleId != null,
  });

  // Summary for selected vehicle (or fleet-wide)
  const { data: summary } = useQuery({
    queryKey: ['mileage-summary', vehicleId],
    queryFn: () =>
      getMileageSummary({
        vehicle_id: vehicleId,
        period_start: new Date(Date.now() - 30 * 86400000).toISOString().slice(0, 10),
        period_end: new Date().toISOString().slice(0, 10),
      }),
    staleTime: 30_000,
  });

  return (
    <div className="space-y-4">
      {/* Header: vehicle picker + actions */}
      <div className="flex items-center gap-3 flex-wrap">
        <div className="flex-1 min-w-[200px]">
          <select
            value={selectedVehicle}
            onChange={(e) => setSelectedVehicle(e.target.value === 'all' ? 'all' : Number(e.target.value))}
            className="block w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm min-h-[36px]"
          >
            <option value="all">Select a vehicle...</option>
            {vehicles?.map((v) => (
              <option key={v.id} value={v.id}>
                {v.vehicle_number} — {v.vehicle_name || `${v.make || ''} ${v.model || ''}`.trim()}
              </option>
            ))}
          </select>
        </div>

        <Button
          size="sm"
          icon={<Plus className="h-4 w-4" />}
          onClick={() => setShowLogMileage(true)}
          disabled={!vehicleId}
        >
          <span className="hidden sm:inline">Log Mileage</span>
        </Button>
      </div>

      {/* 30-day summary cards */}
      {summary && (
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
          <SummaryCard label="Total Miles (30d)" value={`${summary.total_miles.toLocaleString()} mi`} />
          <SummaryCard label="Days Logged" value={String(summary.total_days_logged)} />
          <SummaryCard label="Avg/Day" value={`${summary.avg_miles_per_day.toFixed(1)} mi`} />
          <SummaryCard label="Billable Drive" value={`${Math.floor(summary.total_billable_drive_minutes / 60)}h ${summary.total_billable_drive_minutes % 60}m`} />
        </div>
      )}

      {/* Logs table */}
      {selectedVehicle === 'all' ? (
        <EmptyState
          icon={<Gauge className="h-12 w-12" />}
          title="Select a Vehicle"
          description="Choose a vehicle above to view its mileage logs."
        />
      ) : isLoading ? (
        <PageSpinner label="Loading mileage logs..." />
      ) : !logs || logs.length === 0 ? (
        <EmptyState
          icon={<Gauge className="h-12 w-12" />}
          title="No Mileage Logs"
          description="No mileage has been recorded for this vehicle yet."
          action={
            <Button icon={<Plus className="h-4 w-4" />} onClick={() => setShowLogMileage(true)}>
              Log Mileage
            </Button>
          }
        />
      ) : (
        <div className="bg-surface border border-border rounded-xl overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-border bg-gray-50 dark:bg-gray-800/50">
                  <th className="text-left px-3 py-2 font-medium text-gray-500 dark:text-gray-400 w-8" />
                  <th className="text-left px-3 py-2 font-medium text-gray-500 dark:text-gray-400">Date</th>
                  <th className="text-right px-3 py-2 font-medium text-gray-500 dark:text-gray-400">Start</th>
                  <th className="text-right px-3 py-2 font-medium text-gray-500 dark:text-gray-400">End</th>
                  <th className="text-right px-3 py-2 font-medium text-gray-500 dark:text-gray-400">Total</th>
                  <th className="text-left px-3 py-2 font-medium text-gray-500 dark:text-gray-400">Driver</th>
                  <th className="text-center px-3 py-2 font-medium text-gray-500 dark:text-gray-400">Take-Home</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-border">
                {logs.map((log) => (
                  <MileageLogRow key={log.id} log={log} />
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* Log Mileage Modal */}
      {showLogMileage && vehicleId && (
        <LogMileageModal
          isOpen={showLogMileage}
          onClose={() => setShowLogMileage(false)}
          vehicleId={vehicleId}
        />
      )}
    </div>
  );
}


// ── Mileage Log Row (expandable for trip legs) ────────────────────────

function MileageLogRow({ log }: { log: MileageLog }) {
  const [expanded, setExpanded] = useState(false);
  const hasLegs = log.trip_legs && log.trip_legs.length > 0;

  return (
    <>
      <tr
        className={`hover:bg-gray-50 dark:hover:bg-gray-800/50 transition-colors ${hasLegs ? 'cursor-pointer' : ''}`}
        onClick={() => hasLegs && setExpanded(!expanded)}
      >
        <td className="px-3 py-2">
          {hasLegs && (
            expanded
              ? <ChevronDown className="h-3.5 w-3.5 text-gray-400" />
              : <ChevronRight className="h-3.5 w-3.5 text-gray-400" />
          )}
        </td>
        <td className="px-3 py-2 text-gray-900 dark:text-gray-100 whitespace-nowrap">
          {log.log_date}
        </td>
        <td className="px-3 py-2 text-right font-mono text-gray-700 dark:text-gray-300">
          {log.odometer_start?.toLocaleString() ?? '—'}
        </td>
        <td className="px-3 py-2 text-right font-mono text-gray-700 dark:text-gray-300">
          {log.odometer_end?.toLocaleString() ?? '—'}
        </td>
        <td className="px-3 py-2 text-right font-mono font-medium text-gray-900 dark:text-gray-100">
          {log.total_miles?.toLocaleString() ?? '—'} mi
        </td>
        <td className="px-3 py-2 text-gray-600 dark:text-gray-400 truncate max-w-[120px]">
          {log.driver_name || '—'}
        </td>
        <td className="px-3 py-2 text-center">
          {log.is_take_home_day && <Badge variant="info">TH</Badge>}
        </td>
      </tr>

      {/* Trip legs expansion */}
      {expanded && hasLegs && (
        <tr>
          <td colSpan={7} className="px-0 py-0">
            <div className="bg-gray-50 dark:bg-gray-800/30 border-l-4 border-blue-300 dark:border-blue-700 px-6 py-2">
              <p className="text-xs font-medium text-gray-500 dark:text-gray-400 mb-2">Trip Legs</p>
              <div className="space-y-1.5">
                {log.trip_legs!.map((leg, i) => (
                  <TripLegRow key={leg.id ?? i} leg={leg} />
                ))}
              </div>
            </div>
          </td>
        </tr>
      )}
    </>
  );
}


function TripLegRow({ leg }: { leg: TripLeg }) {
  const typeLabel = leg.leg_type.replace(/_/g, ' → ').replace(/to/g, '→');

  return (
    <div className="flex items-center gap-3 text-xs text-gray-600 dark:text-gray-400 flex-wrap min-w-0">
      <span className="font-mono bg-gray-100 dark:bg-gray-700 px-2 py-0.5 rounded shrink-0">
        #{leg.leg_order}
      </span>
      <span className="capitalize shrink-0">{typeLabel}</span>
      <span className="text-gray-400 dark:text-gray-500 truncate min-w-0">
        {leg.from_label || '?'} → {leg.to_label || '?'}
      </span>
      {leg.actual_miles != null && (
        <span className="font-mono">{leg.actual_miles} mi</span>
      )}
      {leg.actual_drive_minutes != null && (
        <span className="flex items-center gap-0.5">
          <Clock className="h-3 w-3" />
          {leg.actual_drive_minutes}m
        </span>
      )}
      {leg.is_billable && <Badge variant="success">Billable</Badge>}
    </div>
  );
}


// ── Log Mileage Modal ─────────────────────────────────────────────────

function LogMileageModal({
  isOpen,
  onClose,
  vehicleId,
}: {
  isOpen: boolean;
  onClose: () => void;
  vehicleId: number;
}) {
  const queryClient = useQueryClient();
  const [logDate, setLogDate] = useState(new Date().toISOString().slice(0, 10));
  const [odometerStart, setOdometerStart] = useState('');
  const [odometerEnd, setOdometerEnd] = useState('');
  const [isTakeHome, setIsTakeHome] = useState(false);
  const [notes, setNotes] = useState('');
  const [error, setError] = useState('');

  const mutation = useMutation({
    mutationFn: () =>
      logMileage(vehicleId, {
        log_date: logDate,
        odometer_start: odometerStart ? Number(odometerStart) : undefined,
        odometer_end: odometerEnd ? Number(odometerEnd) : undefined,
        is_take_home_day: isTakeHome,
        notes: notes.trim() || undefined,
      }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['mileage-logs', vehicleId] });
      queryClient.invalidateQueries({ queryKey: ['mileage-summary'] });
      queryClient.invalidateQueries({ queryKey: ['my-vehicle'] });
      onClose();
    },
    onError: (err: any) => {
      setError(err?.response?.data?.detail || err?.response?.data?.message || err?.message || 'Failed to log mileage');
    },
  });

  return (
    <Modal isOpen={isOpen} onClose={onClose} title="Log Daily Mileage" size="md">
      <form
        onSubmit={(e) => {
          e.preventDefault();
          setError('');
          mutation.mutate();
        }}
        className="space-y-4"
      >
        {error && (
          <div className="p-3 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-lg text-sm text-red-600 dark:text-red-400">
            {error}
          </div>
        )}

        <Input
          label="Date *"
          type="date"
          value={logDate}
          onChange={(e) => setLogDate(e.target.value)}
        />

        <div className="grid grid-cols-2 gap-4">
          <Input
            label="Odometer Start"
            type="number"
            placeholder="e.g. 48250"
            value={odometerStart}
            onChange={(e) => setOdometerStart(e.target.value)}
          />
          <Input
            label="Odometer End"
            type="number"
            placeholder="e.g. 48312"
            value={odometerEnd}
            onChange={(e) => setOdometerEnd(e.target.value)}
          />
        </div>

        {odometerStart && odometerEnd && Number(odometerEnd) > Number(odometerStart) && (
          <p className="text-sm text-gray-500 dark:text-gray-400">
            Total: <span className="font-mono font-medium text-gray-900 dark:text-gray-100">
              {(Number(odometerEnd) - Number(odometerStart)).toLocaleString()} mi
            </span>
          </p>
        )}

        <label className="flex items-center gap-2 cursor-pointer">
          <input
            type="checkbox"
            checked={isTakeHome}
            onChange={(e) => setIsTakeHome(e.target.checked)}
            className="rounded border-gray-300 dark:border-gray-600 text-blue-600 focus:ring-blue-500"
          />
          <span className="text-sm text-gray-700 dark:text-gray-300">Take-Home Day</span>
        </label>

        <Input
          label="Notes"
          placeholder="Optional..."
          value={notes}
          onChange={(e) => setNotes(e.target.value)}
        />

        <div className="flex items-center justify-end gap-3 pt-2">
          <Button variant="secondary" type="button" onClick={onClose}>Cancel</Button>
          <Button type="submit" isLoading={mutation.isPending}>Log Mileage</Button>
        </div>
      </form>
    </Modal>
  );
}


// ── Reimbursements View ───────────────────────────────────────────────

function ReimbursementsView({
  canManageFleet,
  userId,
}: {
  canManageFleet: boolean;
  userId?: number;
}) {
  const queryClient = useQueryClient();
  const [statusFilter, setStatusFilter] = useState<string>('all');
  const [showCreate, setShowCreate] = useState(false);

  const { data: reimbursements, isLoading } = useQuery({
    queryKey: ['reimbursements', statusFilter],
    queryFn: () =>
      listReimbursements({
        status: statusFilter === 'all' ? undefined : statusFilter,
        user_id: canManageFleet ? undefined : userId,
      }),
    staleTime: 30_000,
  });

  const approveMut = useMutation({
    mutationFn: ({ id, action }: { id: number; action: 'approve' | 'reject' }) =>
      approveReimbursement(id, { action }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['reimbursements'] });
    },
  });

  if (isLoading) return <PageSpinner label="Loading reimbursements..." />;

  return (
    <div className="space-y-4">
      {/* Header */}
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div className="flex items-center gap-2 flex-wrap">
          {['all', 'pending', 'approved', 'paid', 'rejected'].map((s) => (
            <button
              key={s}
              onClick={() => setStatusFilter(s)}
              className={`px-3 py-1.5 text-xs rounded-full transition-colors min-h-[36px] capitalize ${
                statusFilter === s
                  ? 'bg-blue-100 dark:bg-blue-900/40 text-blue-700 dark:text-blue-300'
                  : 'bg-gray-100 dark:bg-gray-800 text-gray-600 dark:text-gray-400 hover:bg-gray-200 dark:hover:bg-gray-700'
              }`}
            >
              {s}
            </button>
          ))}
        </div>

        <Button
          size="sm"
          icon={<Plus className="h-4 w-4" />}
          onClick={() => setShowCreate(true)}
        >
          <span className="hidden sm:inline">New Reimbursement</span>
        </Button>
      </div>

      {/* Reimbursements list */}
      {!reimbursements || reimbursements.length === 0 ? (
        <EmptyState
          icon={<DollarSign className="h-12 w-12" />}
          title="No Reimbursements"
          description="No mileage reimbursement requests found."
        />
      ) : (
        <div className="bg-surface border border-border rounded-xl divide-y divide-border">
          {reimbursements.map((r) => (
            <div key={r.id} className="p-3 flex items-center justify-between flex-wrap gap-2">
              <div className="min-w-0 flex-1">
                <div className="flex items-center gap-2 flex-wrap">
                  <span className="text-sm font-medium text-gray-900 dark:text-gray-100">
                    {r.user_name || `User #${r.user_id}`}
                  </span>
                  <span className="text-xs text-gray-500 dark:text-gray-400">
                    {r.vehicle_name || `Vehicle #${r.vehicle_id}`}
                  </span>
                  <ReimbursementStatusBadge status={r.status} />
                </div>
                <div className="flex items-center gap-3 text-xs text-gray-500 dark:text-gray-400 mt-0.5 min-w-0 flex-wrap">
                  <span className="shrink-0">{r.period_start} → {r.period_end}</span>
                  <span className="font-mono">{r.total_miles.toLocaleString()} mi</span>
                  <span className="font-mono">@ ${r.rate_per_mile}/mi</span>
                </div>
              </div>

              <div className="flex items-center gap-2">
                <span className="text-sm font-bold text-gray-900 dark:text-gray-100">
                  ${(r.total_amount ?? 0).toFixed(2)}
                </span>

                {canManageFleet && r.status === 'pending' && (
                  <div className="flex items-center gap-1 ml-2">
                    <Button
                      size="sm"
                      variant="ghost"
                      onClick={() => approveMut.mutate({ id: r.id, action: 'approve' })}
                      isLoading={approveMut.isPending}
                    >
                      <Check className="h-4 w-4 text-green-500" />
                    </Button>
                    <Button
                      size="sm"
                      variant="ghost"
                      onClick={() => approveMut.mutate({ id: r.id, action: 'reject' })}
                      isLoading={approveMut.isPending}
                    >
                      <X className="h-4 w-4 text-red-500" />
                    </Button>
                  </div>
                )}
              </div>
            </div>
          ))}
        </div>
      )}

      {/* Create Reimbursement Modal */}
      {showCreate && (
        <CreateReimbursementModal
          isOpen={showCreate}
          onClose={() => setShowCreate(false)}
        />
      )}
    </div>
  );
}


function ReimbursementStatusBadge({ status }: { status: string }) {
  const variant =
    status === 'approved' || status === 'paid'
      ? 'success'
      : status === 'pending'
        ? 'warning'
        : status === 'rejected'
          ? 'danger'
          : 'default';
  return <Badge variant={variant}>{status}</Badge>;
}


// ── Create Reimbursement Modal ────────────────────────────────────────

function CreateReimbursementModal({ isOpen, onClose }: { isOpen: boolean; onClose: () => void }) {
  const queryClient = useQueryClient();
  const [vehicleId, setVehicleId] = useState<number | ''>('');
  const [periodStart, setPeriodStart] = useState('');
  const [periodEnd, setPeriodEnd] = useState('');
  const [totalMiles, setTotalMiles] = useState('');
  const [ratePerMile, setRatePerMile] = useState('0.67');
  const [notes, setNotes] = useState('');
  const [error, setError] = useState('');

  const { data: vehicles } = useQuery({
    queryKey: ['vehicles-private'],
    queryFn: () => listVehicles({ vehicle_type: 'private_vehicle' }),
    staleTime: 60_000,
    enabled: isOpen,
  });

  const totalAmount = totalMiles && ratePerMile
    ? (Number(totalMiles) * Number(ratePerMile)).toFixed(2)
    : '—';

  const mutation = useMutation({
    mutationFn: () =>
      createReimbursement({
        vehicle_id: vehicleId as number,
        period_start: periodStart,
        period_end: periodEnd,
        total_miles: Number(totalMiles),
        rate_per_mile: Number(ratePerMile),
        notes: notes.trim() || undefined,
      }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['reimbursements'] });
      onClose();
    },
    onError: (err: any) => {
      setError(err?.response?.data?.detail || err?.response?.data?.message || err?.message || 'Failed to create reimbursement');
    },
  });

  return (
    <Modal isOpen={isOpen} onClose={onClose} title="New Reimbursement Request" size="md">
      <form
        onSubmit={(e) => {
          e.preventDefault();
          setError('');
          if (!vehicleId || !periodStart || !periodEnd || !totalMiles) {
            setError('Please fill in all required fields');
            return;
          }
          mutation.mutate();
        }}
        className="space-y-4"
      >
        {error && (
          <div className="p-3 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-lg text-sm text-red-600 dark:text-red-400">
            {error}
          </div>
        )}

        <div className="space-y-1.5">
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300">Private Vehicle *</label>
          <select
            value={vehicleId}
            onChange={(e) => setVehicleId(e.target.value ? Number(e.target.value) : '')}
            className="block w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-primary-300 focus:border-primary-500"
          >
            <option value="">Select vehicle...</option>
            {vehicles?.map((v) => (
              <option key={v.id} value={v.id}>
                {v.vehicle_number} — {v.vehicle_name || `${v.make || ''} ${v.model || ''}`.trim()}
              </option>
            ))}
          </select>
        </div>

        <div className="grid grid-cols-2 gap-4">
          <Input
            label="Period Start *"
            type="date"
            value={periodStart}
            onChange={(e) => setPeriodStart(e.target.value)}
          />
          <Input
            label="Period End *"
            type="date"
            value={periodEnd}
            onChange={(e) => setPeriodEnd(e.target.value)}
          />
        </div>

        <div className="grid grid-cols-2 gap-4">
          <Input
            label="Total Miles *"
            type="number"
            step="0.1"
            placeholder="e.g. 245.8"
            value={totalMiles}
            onChange={(e) => setTotalMiles(e.target.value)}
          />
          <Input
            label="Rate ($/mi)"
            type="number"
            step="0.01"
            value={ratePerMile}
            onChange={(e) => setRatePerMile(e.target.value)}
            hint="IRS standard rate: $0.67/mi"
          />
        </div>

        {totalAmount !== '—' && (
          <div className="p-3 bg-green-50 dark:bg-green-900/20 border border-green-200 dark:border-green-800 rounded-lg">
            <span className="text-sm text-green-700 dark:text-green-400">
              Estimated Total: <span className="font-bold">${totalAmount}</span>
            </span>
          </div>
        )}

        <Input
          label="Notes"
          placeholder="Optional..."
          value={notes}
          onChange={(e) => setNotes(e.target.value)}
        />

        <div className="flex items-center justify-end gap-3 pt-2">
          <Button variant="secondary" type="button" onClick={onClose}>Cancel</Button>
          <Button type="submit" isLoading={mutation.isPending}>Submit Request</Button>
        </div>
      </form>
    </Modal>
  );
}


// ── Summary Card ──────────────────────────────────────────────────────

function SummaryCard({ label, value }: { label: string; value: string }) {
  return (
    <div className="bg-surface border border-border rounded-xl p-3">
      <p className="text-xs text-gray-500 dark:text-gray-400 mb-0.5">{label}</p>
      <p className="text-lg font-bold text-gray-900 dark:text-gray-100 font-mono">{value}</p>
    </div>
  );
}
