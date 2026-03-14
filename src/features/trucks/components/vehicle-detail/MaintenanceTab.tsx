/**
 * MaintenanceTab — schedule, overdue alerts, log service form, and service history.
 */

import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Wrench, Plus, AlertTriangle, DollarSign } from 'lucide-react';
import { PageSpinner } from '../../../../components/ui/Spinner';
import { Button } from '../../../../components/ui/Button';
import { Input } from '../../../../components/ui/Input';
import { CollapsibleSection } from './shared';
import {
  getMaintenanceSchedule,
  getServiceHistory,
  logService,
  getMaintenanceCosts,
  listMaintenanceTypes,
} from '../../../../api/vehicles';
import type { MaintenanceSchedule, MaintenanceRecord, MaintenanceRecordCreate } from '../../../../lib/types';


export function MaintenanceTab({ vehicleId }: { vehicleId: number }) {
  const queryClient = useQueryClient();
  const [showSchedule, setShowSchedule] = useState(true);
  const [showHistory, setShowHistory] = useState(true);
  const [showLogService, setShowLogService] = useState(false);

  const { data: schedule, isLoading: loadingSchedule } = useQuery({
    queryKey: ['vehicle-maintenance-schedule', vehicleId],
    queryFn: () => getMaintenanceSchedule(vehicleId),
    staleTime: 30_000,
  });

  const { data: history, isLoading: loadingHistory } = useQuery({
    queryKey: ['vehicle-maintenance-history', vehicleId],
    queryFn: () => getServiceHistory(vehicleId, { limit: 20 }),
    staleTime: 30_000,
  });

  const { data: costs } = useQuery({
    queryKey: ['vehicle-maintenance-costs', vehicleId],
    queryFn: () => getMaintenanceCosts(vehicleId),
    staleTime: 60_000,
  });

  const isLoading = loadingSchedule || loadingHistory;
  if (isLoading) return <PageSpinner label="Loading maintenance..." />;

  // Separate overdue items
  const overdue = (schedule ?? []).filter((s) => s.urgency === 'overdue');

  return (
    <div className="space-y-4">
      {/* Cost summary */}
      {costs && (
        <div className="flex items-center gap-4 text-sm flex-wrap">
          <div className="flex items-center gap-1.5 text-gray-500 dark:text-gray-400">
            <DollarSign className="h-4 w-4 shrink-0" />
            <span>Total: <span className="font-medium text-gray-900 dark:text-gray-100">${costs.total_cost?.toFixed(2) ?? '0.00'}</span></span>
          </div>
          <div className="flex items-center gap-1.5 text-gray-500 dark:text-gray-400">
            <Wrench className="h-4 w-4 shrink-0" />
            <span>{costs.total_records ?? 0} service{(costs.total_records ?? 0) !== 1 ? 's' : ''}</span>
          </div>
        </div>
      )}

      {/* Overdue alerts */}
      {overdue.length > 0 && (
        <div className="p-3 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-lg">
          <div className="flex items-center gap-2 mb-2">
            <AlertTriangle className="h-4 w-4 text-red-500" />
            <span className="text-sm font-medium text-red-700 dark:text-red-300">
              {overdue.length} Overdue
            </span>
          </div>
          <div className="space-y-1">
            {overdue.map((s) => (
              <p key={s.id} className="text-xs text-red-600 dark:text-red-400">
                {s.maintenance_type_name}
                {s.next_due_miles != null && s.current_odometer != null && ` — ${(s.current_odometer - s.next_due_miles).toLocaleString()} mi overdue`}
              </p>
            ))}
          </div>
        </div>
      )}

      {/* Schedule Section */}
      <CollapsibleSection
        title="Maintenance Schedule"
        count={(schedule ?? []).filter((s) => s.is_enabled).length}
        open={showSchedule}
        onToggle={() => setShowSchedule(!showSchedule)}
      >
        {!schedule || schedule.length === 0 ? (
          <p className="text-sm text-gray-400 dark:text-gray-500 text-center py-4">
            No maintenance schedule configured.
          </p>
        ) : (
          <div className="space-y-1">
            {schedule.filter((s) => s.is_enabled).map((s) => (
              <ScheduleRow key={s.id} schedule={s} />
            ))}
          </div>
        )}
      </CollapsibleSection>

      {/* Log Service */}
      <div className="flex justify-end">
        <Button size="sm" icon={<Plus className="h-4 w-4" />} onClick={() => setShowLogService(!showLogService)}>
          <span className="hidden sm:inline">Log Service</span>
        </Button>
      </div>

      {showLogService && (
        <LogServiceForm
          vehicleId={vehicleId}
          onDone={() => {
            setShowLogService(false);
            queryClient.invalidateQueries({ queryKey: ['vehicle-maintenance-history', vehicleId] });
            queryClient.invalidateQueries({ queryKey: ['vehicle-maintenance-schedule', vehicleId] });
            queryClient.invalidateQueries({ queryKey: ['vehicle-maintenance-costs', vehicleId] });
          }}
        />
      )}

      {/* Service History */}
      <CollapsibleSection
        title="Service History"
        count={(history ?? []).length}
        open={showHistory}
        onToggle={() => setShowHistory(!showHistory)}
      >
        {!history || history.length === 0 ? (
          <p className="text-sm text-gray-400 dark:text-gray-500 text-center py-4">
            No service records yet.
          </p>
        ) : (
          <div className="space-y-2">
            {history.map((r) => (
              <ServiceRecordRow key={r.id} record={r} />
            ))}
          </div>
        )}
      </CollapsibleSection>
    </div>
  );
}


function ScheduleRow({ schedule: s }: { schedule: MaintenanceSchedule }) {
  const urgencyColors = {
    overdue: 'text-red-600 dark:text-red-400',
    soon: 'text-amber-600 dark:text-amber-400',
    normal: 'text-gray-500 dark:text-gray-400',
  };

  return (
    <div className="flex items-center justify-between py-2 px-1">
      <div className="min-w-0">
        <p className="text-sm text-gray-900 dark:text-gray-100">{s.maintenance_type_name}</p>
        <p className="text-xs text-gray-500 dark:text-gray-400">
          Every {s.interval_miles?.toLocaleString() ?? '—'} mi / {s.interval_months ?? '—'} mo
        </p>
      </div>
      <div className="text-right shrink-0 ml-2">
        {s.next_due_date && (
          <p className={`text-xs ${urgencyColors[s.urgency ?? 'normal']}`}>
            Due: {s.next_due_date}
          </p>
        )}
        {s.next_due_miles != null && (
          <p className={`text-xs ${urgencyColors[s.urgency ?? 'normal']}`}>
            {s.next_due_miles.toLocaleString()} mi
          </p>
        )}
        {s.last_performed_at && (
          <p className="text-[10px] text-gray-400 dark:text-gray-500">
            Last: {s.last_performed_at}
          </p>
        )}
      </div>
    </div>
  );
}


function ServiceRecordRow({ record: r }: { record: MaintenanceRecord }) {
  return (
    <div className="flex items-center gap-3 p-2 bg-surface-secondary rounded-lg">
      <div className="flex items-center justify-center h-8 w-8 rounded-full bg-blue-50 dark:bg-blue-900/20 text-blue-500 shrink-0">
        <Wrench className="h-4 w-4" />
      </div>
      <div className="flex-1 min-w-0">
        <p className="text-sm text-gray-900 dark:text-gray-100 truncate">
          {r.maintenance_type_name ?? 'Service'}
        </p>
        <p className="text-xs text-gray-500 dark:text-gray-400">
          {r.service_date}
          {r.vendor && ` · ${r.vendor}`}
          {r.invoice_number && ` · #${r.invoice_number}`}
          {r.odometer_reading && ` · ${r.odometer_reading.toLocaleString()} mi`}
        </p>
      </div>
      {r.cost > 0 && (
        <span className="text-sm font-mono text-gray-900 dark:text-gray-100 shrink-0">
          ${r.cost.toFixed(2)}
        </span>
      )}
    </div>
  );
}


/** Inline form to log a new maintenance service. */
function LogServiceForm({ vehicleId, onDone }: { vehicleId: number; onDone: () => void }) {
  const { data: mtypes } = useQuery({
    queryKey: ['maintenance-types'],
    queryFn: () => listMaintenanceTypes({ active_only: true }),
    staleTime: 120_000,
  });

  const [typeId, setTypeId] = useState<number | ''>('');
  const [serviceDate, setServiceDate] = useState(new Date().toISOString().slice(0, 10));
  const [odometer, setOdometer] = useState('');
  const [cost, setCost] = useState('');
  const [vendor, setVendor] = useState('');
  const [invoiceNumber, setInvoiceNumber] = useState('');
  const [description, setDescription] = useState('');
  const [error, setError] = useState('');

  const mutation = useMutation({
    mutationFn: (data: MaintenanceRecordCreate) => logService(vehicleId, data),
    onSuccess: () => onDone(),
    onError: (err: any) => setError(err?.message || 'Failed to log service'),
  });

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!typeId) { setError('Select a maintenance type'); return; }
    mutation.mutate({
      maintenance_type_id: typeId as number,
      service_date: serviceDate || undefined,
      odometer_reading: odometer ? parseInt(odometer) : undefined,
      cost: cost ? parseFloat(cost) : undefined,
      vendor: vendor.trim() || undefined,
      invoice_number: invoiceNumber.trim() || undefined,
      description: description.trim() || undefined,
    });
  }

  return (
    <form onSubmit={handleSubmit} className="p-4 bg-surface border border-border rounded-xl space-y-3">
      <h4 className="text-sm font-semibold text-gray-900 dark:text-gray-100">Log Service</h4>

      {error && (
        <p className="text-sm text-red-500">{error}</p>
      )}

      <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
        <div className="space-y-1.5">
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300">Type *</label>
          <select
            value={typeId}
            onChange={(e) => setTypeId(e.target.value ? Number(e.target.value) : '')}
            className="block w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm"
          >
            <option value="">Select type...</option>
            {(mtypes ?? []).map((t) => (
              <option key={t.id} value={t.id}>{t.name}</option>
            ))}
          </select>
        </div>
        <Input label="Service Date" type="date" value={serviceDate} onChange={(e) => setServiceDate(e.target.value)} />
      </div>
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3">
        <Input label="Odometer" type="number" placeholder="45000" value={odometer} onChange={(e) => setOdometer(e.target.value)} />
        <Input label="Cost ($)" type="number" placeholder="0.00" value={cost} onChange={(e) => setCost(e.target.value)} />
        <Input label="Vendor" placeholder="Shop name" value={vendor} onChange={(e) => setVendor(e.target.value)} />
        <Input label="Invoice #" placeholder="INV-12345" value={invoiceNumber} onChange={(e) => setInvoiceNumber(e.target.value)} />
      </div>
      <Input label="Description" placeholder="What was done..." value={description} onChange={(e) => setDescription(e.target.value)} />

      <div className="flex items-center justify-end gap-2 pt-1">
        <Button variant="secondary" size="sm" type="button" onClick={onDone}>Cancel</Button>
        <Button size="sm" type="submit" isLoading={mutation.isPending}>Log Service</Button>
      </div>
    </form>
  );
}
