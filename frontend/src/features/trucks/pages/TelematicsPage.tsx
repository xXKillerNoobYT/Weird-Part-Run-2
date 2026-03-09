/**
 * TelematicsPage — GPS & telematics device management.
 *
 * Two sub-views:
 *  - Fleet Map: last known positions for all vehicles (list view)
 *  - Devices: register/manage telematics devices
 *
 * Position data comes from devices that push via auth_token.
 * This page consumes the admin-side view of that data.
 */

import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
    MapPin,
    Radio,
    Plus,
    Activity,
    Trash2,
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
    listTelematicsDevices,
    registerTelematicsDevice,
    deactivateTelematicsDevice,
    getFleetPositions,
    getVehicleEvents,
} from '../../../api/vehicles';
import type {
    TelematicsDeviceCreate,
    VehicleListItem,
} from '../../../lib/types';

type SubView = 'positions' | 'devices' | 'events';

export function TelematicsPage() {
    const queryClient = useQueryClient();
    const { hasPermission } = useAuthStore();
    const canManage = hasPermission(PERMISSIONS.MANAGE_FLEET);

    const [subView, setSubView] = useState<SubView>('positions');
    const [showRegisterModal, setShowRegisterModal] = useState(false);
    const [selectedVehicleId, setSelectedVehicleId] = useState<number | null>(null);

    // ── Queries ──
    const { data: vehicles } = useQuery({
        queryKey: ['vehicles-list-brief'],
        queryFn: () => listVehicles(),
    });

    const { data: fleetPositions, isLoading: loadingPositions } = useQuery({
        queryKey: ['fleet-positions'],
        queryFn: getFleetPositions,
        refetchInterval: 30_000, // Refresh every 30s
    });

    const { data: devices, isLoading: loadingDevices } = useQuery({
        queryKey: ['telematics-devices'],
        queryFn: () => listTelematicsDevices({ active_only: false }),
        enabled: subView === 'devices',
    });

    const { data: vehicleEvents } = useQuery({
        queryKey: ['telematics-events', selectedVehicleId],
        queryFn: () => getVehicleEvents(selectedVehicleId!, { limit: 100 }),
        enabled: subView === 'events' && !!selectedVehicleId,
    });

    // ── Mutations ──
    const registerMut = useMutation({
        mutationFn: (body: TelematicsDeviceCreate) => registerTelematicsDevice(body),
        onSuccess: () => {
            queryClient.invalidateQueries({ queryKey: ['telematics-devices'] });
            setShowRegisterModal(false);
        },
    });

    const deactivateMut = useMutation({
        mutationFn: (deviceId: number) => deactivateTelematicsDevice(deviceId),
        onSuccess: () => queryClient.invalidateQueries({ queryKey: ['telematics-devices'] }),
    });

    const vList: VehicleListItem[] = Array.isArray(vehicles) ? vehicles : [];

    const SubViewTab = ({
        value,
        icon: Icon,
        label,
    }: {
        value: SubView;
        icon: React.ElementType;
        label: string;
    }) => (
        <button
            onClick={() => setSubView(value)}
            className={`px-3 py-1.5 text-sm rounded-lg transition-colors min-h-[36px] flex items-center gap-1.5 ${subView === value
                    ? 'bg-blue-100 dark:bg-blue-900/40 text-blue-700 dark:text-blue-300 font-medium'
                    : 'text-gray-600 dark:text-gray-400 hover:bg-gray-100 dark:hover:bg-gray-800'
                }`}
        >
            <Icon className="h-4 w-4" />
            <span className="hidden sm:inline">{label}</span>
        </button>
    );

    return (
        <div className="space-y-4">
            {/* Header */}
            <div className="flex items-center justify-between flex-wrap gap-3">
                <div className="flex items-center gap-2">
                    <SubViewTab value="positions" icon={MapPin} label="Fleet Positions" />
                    <SubViewTab value="events" icon={Activity} label="Events" />
                    {canManage && <SubViewTab value="devices" icon={Radio} label="Devices" />}
                </div>
                {canManage && subView === 'devices' && (
                    <Button size="sm" onClick={() => setShowRegisterModal(true)}>
                        <Plus className="h-4 w-4 mr-1" />
                        <span className="hidden sm:inline">Register Device</span>
                    </Button>
                )}
            </div>

            {/* Fleet Positions View */}
            {subView === 'positions' && (
                <div className="rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 overflow-hidden">
                    {loadingPositions ? (
                        <PageSpinner />
                    ) : !fleetPositions || fleetPositions.length === 0 ? (
                        <EmptyState
                            icon={MapPin}
                            title="No GPS positions available"
                            description="Register telematics devices to start tracking vehicle locations."
                        />
                    ) : (
                        <div className="overflow-x-auto">
                            <table className="w-full text-sm">
                                <thead className="bg-gray-50 dark:bg-gray-800 border-b border-gray-200 dark:border-gray-700">
                                    <tr>
                                        <th className="text-left p-3 font-medium">Vehicle</th>
                                        <th className="text-left p-3 font-medium">Location</th>
                                        <th className="text-right p-3 font-medium">Speed</th>
                                        <th className="text-center p-3 font-medium">Engine</th>
                                        <th className="text-left p-3 font-medium">Last Update</th>
                                    </tr>
                                </thead>
                                <tbody className="divide-y divide-gray-100 dark:divide-gray-700">
                                    {fleetPositions.map((pos) => (
                                        <tr key={pos.vehicle_id} className="hover:bg-gray-50 dark:hover:bg-gray-700/40">
                                            <td className="p-3 font-medium">
                                                {pos.vehicle_number}
                                                {pos.vehicle_make && (
                                                    <span className="ml-1 text-xs text-gray-500">
                                                        {pos.vehicle_make} {pos.vehicle_model}
                                                    </span>
                                                )}
                                            </td>
                                            <td className="p-3 text-xs text-gray-600 dark:text-gray-400 tabular-nums">
                                                {pos.lat.toFixed(5)}, {pos.lng.toFixed(5)}
                                            </td>
                                            <td className="p-3 text-right tabular-nums">
                                                {pos.speed_mph != null ? `${pos.speed_mph} mph` : '—'}
                                            </td>
                                            <td className="p-3 text-center">
                                                <Badge variant={pos.engine_on ? 'success' : 'neutral'}>
                                                    {pos.engine_on ? 'ON' : 'OFF'}
                                                </Badge>
                                            </td>
                                            <td className="p-3 text-xs text-gray-500">
                                                {new Date(pos.recorded_at).toLocaleString()}
                                            </td>
                                        </tr>
                                    ))}
                                </tbody>
                            </table>
                        </div>
                    )}
                </div>
            )}

            {/* Events View */}
            {subView === 'events' && (
                <div className="space-y-3">
                    <div className="flex items-center gap-3 flex-wrap">
                        <label className="text-sm font-medium">Vehicle:</label>
                        <select
                            value={selectedVehicleId ?? ''}
                            onChange={(e) =>
                                setSelectedVehicleId(e.target.value ? Number(e.target.value) : null)
                            }
                            className="px-3 py-1.5 rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-sm min-w-[200px]"
                        >
                            <option value="">Select vehicle...</option>
                            {vList.map((v: VehicleListItem) => (
                                <option key={v.id} value={v.id}>
                                    {v.vehicle_number}
                                </option>
                            ))}
                        </select>
                    </div>
                    {selectedVehicleId && vehicleEvents && (
                        <div className="rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 overflow-hidden">
                            {vehicleEvents.length === 0 ? (
                                <EmptyState icon={Activity} title="No events recorded" />
                            ) : (
                                <div className="overflow-x-auto">
                                    <table className="w-full text-sm">
                                        <thead className="bg-gray-50 dark:bg-gray-800 border-b border-gray-200 dark:border-gray-700">
                                            <tr>
                                                <th className="text-left p-3 font-medium">Type</th>
                                                <th className="text-left p-3 font-medium">Data</th>
                                                <th className="text-left p-3 font-medium">Location</th>
                                                <th className="text-left p-3 font-medium">Time</th>
                                            </tr>
                                        </thead>
                                        <tbody className="divide-y divide-gray-100 dark:divide-gray-700">
                                            {vehicleEvents.map((evt) => (
                                                <tr key={evt.id} className="hover:bg-gray-50 dark:hover:bg-gray-700/40">
                                                    <td className="p-3">
                                                        <Badge
                                                            variant={
                                                                evt.event_type === 'hard_brake'
                                                                    ? 'warning'
                                                                    : evt.event_type === 'speeding'
                                                                        ? 'danger'
                                                                        : 'info'
                                                            }
                                                        >
                                                            {evt.event_type.replace(/_/g, ' ')}
                                                        </Badge>
                                                    </td>
                                                    <td className="p-3 text-xs text-gray-600 dark:text-gray-400 max-w-[200px] truncate">
                                                        {evt.event_data ?? '—'}
                                                    </td>
                                                    <td className="p-3 text-xs tabular-nums">
                                                        {evt.lat && evt.lng
                                                            ? `${evt.lat.toFixed(4)}, ${evt.lng.toFixed(4)}`
                                                            : '—'}
                                                    </td>
                                                    <td className="p-3 text-xs text-gray-500">
                                                        {new Date(evt.recorded_at).toLocaleString()}
                                                    </td>
                                                </tr>
                                            ))}
                                        </tbody>
                                    </table>
                                </div>
                            )}
                        </div>
                    )}
                </div>
            )}

            {/* Devices View */}
            {subView === 'devices' && (
                <div className="rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 overflow-hidden">
                    {loadingDevices ? (
                        <PageSpinner />
                    ) : !devices || devices.length === 0 ? (
                        <EmptyState
                            icon={Radio}
                            title="No devices registered"
                            description="Register a telematics device to start tracking."
                        />
                    ) : (
                        <div className="overflow-x-auto">
                            <table className="w-full text-sm">
                                <thead className="bg-gray-50 dark:bg-gray-800 border-b border-gray-200 dark:border-gray-700">
                                    <tr>
                                        <th className="text-left p-3 font-medium">Device</th>
                                        <th className="text-left p-3 font-medium">Serial</th>
                                        <th className="text-left p-3 font-medium">Vehicle</th>
                                        <th className="text-center p-3 font-medium">Status</th>
                                        <th className="text-left p-3 font-medium">Last Seen</th>
                                        {canManage && <th className="p-3 w-10" />}
                                    </tr>
                                </thead>
                                <tbody className="divide-y divide-gray-100 dark:divide-gray-700">
                                    {devices.map((dev) => (
                                        <tr key={dev.id} className="hover:bg-gray-50 dark:hover:bg-gray-700/40">
                                            <td className="p-3 font-medium">
                                                {dev.device_name ?? dev.device_type}
                                            </td>
                                            <td className="p-3 text-xs tabular-nums text-gray-600 dark:text-gray-400">
                                                {dev.device_serial}
                                            </td>
                                            <td className="p-3">
                                                {dev.vehicle_number ?? `Vehicle #${dev.vehicle_id}`}
                                            </td>
                                            <td className="p-3 text-center">
                                                <Badge variant={dev.is_active ? 'success' : 'neutral'}>
                                                    {dev.is_active ? 'Active' : 'Inactive'}
                                                </Badge>
                                            </td>
                                            <td className="p-3 text-xs text-gray-500">
                                                {dev.last_seen_at
                                                    ? new Date(dev.last_seen_at).toLocaleString()
                                                    : 'Never'}
                                            </td>
                                            {canManage && (
                                                <td className="p-3">
                                                    {dev.is_active && (
                                                        <button
                                                            onClick={() => deactivateMut.mutate(dev.id)}
                                                            className="p-1 hover:bg-red-100 dark:hover:bg-red-900/30 rounded text-red-600"
                                                            title="Deactivate"
                                                        >
                                                            <Trash2 className="h-3.5 w-3.5" />
                                                        </button>
                                                    )}
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

            {/* Register Device Modal */}
            {showRegisterModal && (
                <RegisterDeviceModal
                    vehicles={vList}
                    onSubmit={(body) => registerMut.mutate(body)}
                    onClose={() => setShowRegisterModal(false)}
                    isPending={registerMut.isPending}
                />
            )}
        </div>
    );
}

function RegisterDeviceModal({
    vehicles,
    onSubmit,
    onClose,
    isPending,
}: {
    vehicles: VehicleListItem[];
    onSubmit: (body: TelematicsDeviceCreate) => void;
    onClose: () => void;
    isPending: boolean;
}) {
    const [form, setForm] = useState({
        vehicle_id: 0,
        device_serial: '',
        device_name: '',
        device_type: 'gps_tracker',
    });

    return (
        <Modal isOpen={true} onClose={onClose} title="Register Telematics Device" size="md">
            <div className="space-y-4">
                <div>
                    <label className="block text-sm font-medium mb-1">Vehicle *</label>
                    <select
                        value={form.vehicle_id}
                        onChange={(e) => setForm((f) => ({ ...f, vehicle_id: Number(e.target.value) }))}
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
                        label="Serial Number *"
                        value={form.device_serial}
                        onChange={(e) => setForm((f) => ({ ...f, device_serial: e.target.value }))}
                        placeholder="e.g. TRK-GPS-001"
                    />
                    <Input
                        label="Device Name"
                        value={form.device_name}
                        onChange={(e) => setForm((f) => ({ ...f, device_name: e.target.value }))}
                        placeholder="e.g. Main GPS"
                    />
                </div>
                <div>
                    <label className="block text-sm font-medium mb-1">Device Type</label>
                    <select
                        value={form.device_type}
                        onChange={(e) => setForm((f) => ({ ...f, device_type: e.target.value }))}
                        className="w-full px-3 py-2 rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-sm"
                    >
                        <option value="gps_tracker">GPS Tracker</option>
                        <option value="obd2">OBD-II</option>
                        <option value="dashcam">Dashcam</option>
                        <option value="eld">ELD</option>
                    </select>
                </div>
                <div className="flex justify-end gap-2 pt-2">
                    <Button variant="ghost" onClick={onClose}>
                        Cancel
                    </Button>
                    <Button
                        onClick={() =>
                            onSubmit({
                                vehicle_id: form.vehicle_id,
                                device_serial: form.device_serial,
                                device_name: form.device_name || undefined,
                                device_type: form.device_type,
                            })
                        }
                        disabled={isPending || !form.vehicle_id || !form.device_serial}
                    >
                        {isPending ? 'Registering...' : 'Register'}
                    </Button>
                </div>
            </div>
        </Modal>
    );
}
