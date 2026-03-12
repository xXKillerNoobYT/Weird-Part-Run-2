/**
 * FuelPage — fleet fuel tracking dashboard.
 *
 * Two sub-views:
 *  - Fleet: fuel summary cards, fleet-wide log table
 *  - By Vehicle: select a vehicle and see its fuel history + summary
 *
 * Managers can log fuel purchases, edit entries, and view cost trends.
 */

import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
    Fuel,
    Plus,
    TrendingUp,
    DollarSign,
    Gauge,
    Edit2,
} from 'lucide-react';
import { PageSpinner } from '../../../components/ui/Spinner';
import { ErrorFallback } from '../../../components/ui/ErrorFallback';
import { EmptyState } from '../../../components/ui/EmptyState';
import { Badge } from '../../../components/ui/Badge';
import { Button } from '../../../components/ui/Button';
import { Input } from '../../../components/ui/Input';
import { Modal } from '../../../components/ui/Modal';
import { useAuthStore } from '../../../stores/auth-store';
import { PERMISSIONS } from '../../../lib/constants';
import {
    listVehicles,
    logFuel,
    getVehicleFuelLogs,
    updateFuelLog,
    getVehicleFuelSummary,
    getFleetFuelSummary,
} from '../../../api/vehicles';
import type { FuelLog, FuelLogCreate, FuelLogUpdate, FuelSummary, VehicleListItem } from '../../../lib/types';

export function FuelPage() {
    const queryClient = useQueryClient();
    const { hasPermission } = useAuthStore();
    const canManage = hasPermission(PERMISSIONS.MANAGE_FLEET);

    const [selectedVehicleId, setSelectedVehicleId] = useState<number | null>(null);
    const [showLogModal, setShowLogModal] = useState(false);
    const [editingLog, setEditingLog] = useState<FuelLog | null>(null);

    // ----- Data Queries -----
    const { data: vehicles } = useQuery({
        queryKey: ['vehicles-list-brief'],
        queryFn: () => listVehicles(),
    });

    const { data: fleetSummary, isLoading: loadingFleetSummary, isError: fleetError, refetch: refetchFleet } = useQuery({
        queryKey: ['fleet-fuel-summary'],
        queryFn: () => getFleetFuelSummary(),
    });

    const { data: vehicleLogs, isLoading: loadingLogs } = useQuery({
        queryKey: ['vehicle-fuel-logs', selectedVehicleId],
        queryFn: () => getVehicleFuelLogs(selectedVehicleId!, { limit: 100 }),
        enabled: !!selectedVehicleId,
    });

    const { data: vehicleSummary } = useQuery({
        queryKey: ['vehicle-fuel-summary', selectedVehicleId],
        queryFn: () => getVehicleFuelSummary(selectedVehicleId!),
        enabled: !!selectedVehicleId,
    });

    // ----- Mutations -----
    const logMut = useMutation({
        mutationFn: (data: { vehicleId: number; body: FuelLogCreate }) =>
            logFuel(data.vehicleId, data.body),
        onSuccess: () => {
            queryClient.invalidateQueries({ queryKey: ['vehicle-fuel-logs'] });
            queryClient.invalidateQueries({ queryKey: ['fleet-fuel-summary'] });
            queryClient.invalidateQueries({ queryKey: ['vehicle-fuel-summary'] });
            setShowLogModal(false);
        },
    });

    const updateMut = useMutation({
        mutationFn: (data: { logId: number; body: FuelLogUpdate }) =>
            updateFuelLog(data.logId, data.body),
        onSuccess: () => {
            queryClient.invalidateQueries({ queryKey: ['vehicle-fuel-logs'] });
            queryClient.invalidateQueries({ queryKey: ['fleet-fuel-summary'] });
            queryClient.invalidateQueries({ queryKey: ['vehicle-fuel-summary'] });
            setEditingLog(null);
        },
    });

    // ----- Helpers -----
    const vList: VehicleListItem[] = Array.isArray(vehicles) ? vehicles : [];

    const SummaryCards = ({ data: s }: { data: FuelSummary | undefined }) => {
        if (!s) return null;
        return (
            <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-3">
                <KpiCard icon={Fuel} label="Fill-ups" value={s.fill_count ?? 0} />
                <KpiCard icon={Fuel} label="Total Gallons" value={s.total_gallons?.toFixed(1) ?? '—'} />
                <KpiCard
                    icon={DollarSign}
                    label="Total Cost"
                    value={`$${(s.total_cost ?? 0).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`}
                />
                <KpiCard
                    icon={DollarSign}
                    label="Avg $/gal"
                    value={s.avg_price ? `$${s.avg_price.toFixed(3)}` : '—'}
                />
                <KpiCard icon={Gauge} label="Avg MPG" value={s.avg_mpg?.toFixed(1) ?? '—'} />
                <KpiCard
                    icon={TrendingUp}
                    label="Miles Driven"
                    value={s.total_miles_driven?.toLocaleString() ?? '—'}
                />
            </div>
        );
    };

    return (
        <div className="space-y-4">
            {/* Header */}
            <div className="flex items-center justify-between flex-wrap gap-3">
                <h2 className="text-lg font-semibold flex items-center gap-2">
                    <Fuel className="h-5 w-5 text-amber-600" />
                    Fuel Tracking
                </h2>
                {canManage && (
                    <Button size="sm" onClick={() => setShowLogModal(true)}>
                        <Plus className="h-4 w-4 mr-1" />
                        <span className="hidden sm:inline">Log Fuel</span>
                    </Button>
                )}
            </div>

            {/* Fleet Summary */}
            <div className="rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 p-4">
                <h3 className="text-sm font-medium text-gray-600 dark:text-gray-400 mb-3">
                    Fleet Fuel Summary
                </h3>
                {fleetError ? <ErrorFallback compact onRetry={refetchFleet} /> : loadingFleetSummary ? <PageSpinner /> : <SummaryCards data={fleetSummary} />}
            </div>

            {/* Vehicle Selector */}
            <div className="flex items-center gap-3 flex-wrap">
                <label className="text-sm font-medium text-gray-700 dark:text-gray-300">
                    Filter by Vehicle:
                </label>
                <select
                    value={selectedVehicleId ?? ''}
                    onChange={(e) => setSelectedVehicleId(e.target.value ? Number(e.target.value) : null)}
                    className="px-3 py-1.5 rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-sm min-w-[200px]"
                >
                    <option value="">All Vehicles</option>
                    {vList.map((v: VehicleListItem) => (
                        <option key={v.id} value={v.id}>
                            {v.vehicle_number} — {v.year} {v.make} {v.model}
                        </option>
                    ))}
                </select>
            </div>

            {/* Per-vehicle summary */}
            {selectedVehicleId && vehicleSummary && (
                <div className="rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 p-4">
                    <h3 className="text-sm font-medium text-gray-600 dark:text-gray-400 mb-3">
                        Vehicle Summary
                    </h3>
                    <SummaryCards data={vehicleSummary} />
                </div>
            )}

            {/* Logs Table */}
            {selectedVehicleId && (
                <div className="rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 overflow-hidden">
                    {loadingLogs ? (
                        <PageSpinner />
                    ) : !vehicleLogs || vehicleLogs.length === 0 ? (
                        <EmptyState icon={Fuel} title="No fuel logs for this vehicle" />
                    ) : (
                        <div className="overflow-x-auto">
                            <table className="w-full text-sm">
                                <thead className="bg-gray-50 dark:bg-gray-800 border-b border-gray-200 dark:border-gray-700">
                                    <tr>
                                        <th className="text-left p-3 font-medium">Date</th>
                                        <th className="text-right p-3 font-medium">Odometer</th>
                                        <th className="text-right p-3 font-medium">Gallons</th>
                                        <th className="text-right p-3 font-medium">$/gal</th>
                                        <th className="text-right p-3 font-medium">Total</th>
                                        <th className="text-right p-3 font-medium">MPG</th>
                                        <th className="text-left p-3 font-medium">Station</th>
                                        {canManage && <th className="p-3 w-10" />}
                                    </tr>
                                </thead>
                                <tbody className="divide-y divide-gray-100 dark:divide-gray-700">
                                    {vehicleLogs.map((log) => (
                                        <tr key={log.id} className="hover:bg-gray-50 dark:hover:bg-gray-700/40">
                                            <td className="p-3">{log.fill_date}</td>
                                            <td className="p-3 text-right tabular-nums">
                                                {log.odometer_reading?.toLocaleString()}
                                            </td>
                                            <td className="p-3 text-right tabular-nums">{log.gallons?.toFixed(2)}</td>
                                            <td className="p-3 text-right tabular-nums">
                                                ${log.price_per_gallon?.toFixed(3)}
                                            </td>
                                            <td className="p-3 text-right tabular-nums font-medium">
                                                ${log.total_cost?.toFixed(2)}
                                            </td>
                                            <td className="p-3 text-right">
                                                {log.mpg ? (
                                                    <Badge
                                                        variant={log.mpg >= 15 ? 'success' : log.mpg >= 10 ? 'warning' : 'danger'}
                                                    >
                                                        {log.mpg} mpg
                                                    </Badge>
                                                ) : (
                                                    <span className="text-gray-400">—</span>
                                                )}
                                            </td>
                                            <td className="p-3 text-gray-600 dark:text-gray-400 truncate max-w-[140px]">
                                                {log.station_name ?? '—'}
                                            </td>
                                            {canManage && (
                                                <td className="p-3">
                                                    <button
                                                        onClick={() => setEditingLog(log)}
                                                        className="p-1 hover:bg-gray-200 dark:hover:bg-gray-600 rounded"
                                                    >
                                                        <Edit2 className="h-3.5 w-3.5" />
                                                    </button>
                                                </td>
                                            )}
                                        </tr>
                                    ))}
                                </tbody>
                            </table>
                        </div>
                    )}
                </div>
            )}

            {/* Log Fuel Modal */}
            {showLogModal && (
                <FuelLogModal
                    vehicles={vList}
                    defaultVehicleId={selectedVehicleId}
                    onSubmit={(vehicleId, body) => logMut.mutate({ vehicleId, body })}
                    onClose={() => setShowLogModal(false)}
                    isPending={logMut.isPending}
                />
            )}

            {/* Edit Fuel Modal */}
            {editingLog && (
                <FuelEditModal
                    log={editingLog}
                    onSubmit={(body) => updateMut.mutate({ logId: editingLog.id, body })}
                    onClose={() => setEditingLog(null)}
                    isPending={updateMut.isPending}
                />
            )}
        </div>
    );
}


// ── Sub-components ────────────────────────────────────────────────

function KpiCard({
    icon: Icon,
    label,
    value,
}: {
    icon: React.ElementType;
    label: string;
    value: string | number;
}) {
    return (
        <div className="rounded-lg border border-gray-200 dark:border-gray-700 p-3 text-center">
            <Icon className="h-4 w-4 mx-auto mb-1 text-gray-500" />
            <div className="text-xs text-gray-500 dark:text-gray-400">{label}</div>
            <div className="text-lg font-semibold mt-0.5">{value}</div>
        </div>
    );
}

function FuelLogModal({
    vehicles,
    defaultVehicleId,
    onSubmit,
    onClose,
    isPending,
}: {
    vehicles: VehicleListItem[];
    defaultVehicleId: number | null;
    onSubmit: (vehicleId: number, body: FuelLogCreate) => void;
    onClose: () => void;
    isPending: boolean;
}) {
    const [vehicleId, setVehicleId] = useState<number>(defaultVehicleId ?? 0);
    const [form, setForm] = useState({
        fill_date: new Date().toISOString().split('T')[0],
        odometer_reading: '',
        gallons: '',
        price_per_gallon: '',
        fuel_type: 'regular',
        station_name: '',
        notes: '',
    });

    const handleSubmit = () => {
        if (!vehicleId || !form.odometer_reading || !form.gallons || !form.price_per_gallon) return;
        onSubmit(vehicleId, {
            fill_date: form.fill_date,
            odometer_reading: Number(form.odometer_reading),
            gallons: Number(form.gallons),
            price_per_gallon: Number(form.price_per_gallon),
            fuel_type: form.fuel_type as any,
            station_name: form.station_name || null,
            notes: form.notes || null,
        });
    };

    return (
        <Modal isOpen={true} onClose={onClose} title="Log Fuel Purchase" size="md">
            <div className="space-y-4">
                <div>
                    <label className="block text-sm font-medium mb-1">Vehicle *</label>
                    <select
                        value={vehicleId}
                        onChange={(e) => setVehicleId(Number(e.target.value))}
                        className="w-full px-3 py-2 rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-sm"
                    >
                        <option value={0}>Select vehicle...</option>
                        {vehicles.map((v) => (
                            <option key={v.id} value={v.id}>
                                {v.vehicle_number} — {v.year} {v.make} {v.model}
                            </option>
                        ))}
                    </select>
                </div>
                <div className="grid grid-cols-2 gap-3">
                    <Input
                        label="Date *"
                        type="date"
                        value={form.fill_date}
                        onChange={(e) => setForm((f) => ({ ...f, fill_date: e.target.value }))}
                    />
                    <Input
                        label="Odometer *"
                        type="number"
                        placeholder="e.g. 48,520"
                        value={form.odometer_reading}
                        onChange={(e) => setForm((f) => ({ ...f, odometer_reading: e.target.value }))}
                    />
                </div>
                <div className="grid grid-cols-2 gap-3">
                    <Input
                        label="Gallons *"
                        type="number"
                        step="0.01"
                        placeholder="e.g. 15.25"
                        value={form.gallons}
                        onChange={(e) => setForm((f) => ({ ...f, gallons: e.target.value }))}
                    />
                    <Input
                        label="Price/Gallon *"
                        type="number"
                        step="0.001"
                        placeholder="e.g. 3.299"
                        value={form.price_per_gallon}
                        onChange={(e) => setForm((f) => ({ ...f, price_per_gallon: e.target.value }))}
                    />
                </div>
                <div className="grid grid-cols-2 gap-3">
                    <div>
                        <label className="block text-sm font-medium mb-1">Fuel Type</label>
                        <select
                            value={form.fuel_type}
                            onChange={(e) => setForm((f) => ({ ...f, fuel_type: e.target.value }))}
                            className="w-full px-3 py-2 rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-sm"
                        >
                            <option value="regular">Regular</option>
                            <option value="premium">Premium</option>
                            <option value="diesel">Diesel</option>
                            <option value="e85">E85</option>
                        </select>
                    </div>
                    <Input
                        label="Station"
                        value={form.station_name}
                        onChange={(e) => setForm((f) => ({ ...f, station_name: e.target.value }))}
                        placeholder="e.g. Shell on Main"
                    />
                </div>
                <Input
                    label="Notes"
                    value={form.notes}
                    onChange={(e) => setForm((f) => ({ ...f, notes: e.target.value }))}
                />
                <div className="flex justify-end gap-2 pt-2">
                    <Button variant="ghost" onClick={onClose}>
                        Cancel
                    </Button>
                    <Button onClick={handleSubmit} disabled={isPending || !vehicleId}>
                        {isPending ? 'Saving...' : 'Log Fuel'}
                    </Button>
                </div>
            </div>
        </Modal>
    );
}

function FuelEditModal({
    log,
    onSubmit,
    onClose,
    isPending,
}: {
    log: FuelLog;
    onSubmit: (body: FuelLogUpdate) => void;
    onClose: () => void;
    isPending: boolean;
}) {
    const [form, setForm] = useState({
        fill_date: log.fill_date,
        odometer_reading: String(log.odometer_reading),
        gallons: String(log.gallons),
        price_per_gallon: String(log.price_per_gallon),
        station_name: log.station_name ?? '',
        notes: log.notes ?? '',
    });

    return (
        <Modal isOpen={true} onClose={onClose} title="Edit Fuel Log" size="md">
            <div className="space-y-4">
                <div className="grid grid-cols-2 gap-3">
                    <Input
                        label="Date"
                        type="date"
                        value={form.fill_date}
                        onChange={(e) => setForm((f) => ({ ...f, fill_date: e.target.value }))}
                    />
                    <Input
                        label="Odometer"
                        type="number"
                        value={form.odometer_reading}
                        onChange={(e) => setForm((f) => ({ ...f, odometer_reading: e.target.value }))}
                    />
                </div>
                <div className="grid grid-cols-2 gap-3">
                    <Input
                        label="Gallons"
                        type="number"
                        step="0.01"
                        value={form.gallons}
                        onChange={(e) => setForm((f) => ({ ...f, gallons: e.target.value }))}
                    />
                    <Input
                        label="Price/Gallon"
                        type="number"
                        step="0.001"
                        value={form.price_per_gallon}
                        onChange={(e) => setForm((f) => ({ ...f, price_per_gallon: e.target.value }))}
                    />
                </div>
                <Input
                    label="Station"
                    value={form.station_name}
                    onChange={(e) => setForm((f) => ({ ...f, station_name: e.target.value }))}
                />
                <Input
                    label="Notes"
                    value={form.notes}
                    onChange={(e) => setForm((f) => ({ ...f, notes: e.target.value }))}
                />
                <div className="flex justify-end gap-2 pt-2">
                    <Button variant="ghost" onClick={onClose}>
                        Cancel
                    </Button>
                    <Button
                        onClick={() =>
                            onSubmit({
                                fill_date: form.fill_date,
                                odometer_reading: Number(form.odometer_reading),
                                gallons: Number(form.gallons),
                                price_per_gallon: Number(form.price_per_gallon),
                                station_name: form.station_name || null,
                                notes: form.notes || null,
                            })
                        }
                        disabled={isPending}
                    >
                        {isPending ? 'Saving...' : 'Update'}
                    </Button>
                </div>
            </div>
        </Modal>
    );
}
