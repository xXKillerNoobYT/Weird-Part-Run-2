/**
 * BluetoothPage — PC-to-PC Bluetooth RFCOMM pairing, tunnel management,
 * and sync controls for two-device field sync.
 *
 * Tabs:
 *   Status   — BT hardware availability + active tunnel status & stats
 *   Paired   — Manage paired devices, connect/disconnect tunnel
 *   Scan     — Discover nearby BT devices and pair with them
 *   History  — Connection session log
 *   Config   — BT sync settings (role, interval, auto-connect)
 */

import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
    Bluetooth, BluetoothOff, RefreshCw,
    Clock, Loader2, Radio, Monitor,
    AlertTriangle, Link, Unlink, Settings2,
    Plus, Trash2, Wifi,
    CheckCircle, XCircle, Activity,
} from 'lucide-react';
import { Card } from '../../../components/ui/Card';
import { Badge } from '../../../components/ui/Badge';
import { Button } from '../../../components/ui/Button';
import { Spinner } from '../../../components/ui/Spinner';
import { EmptyState } from '../../../components/ui/EmptyState';
import {
    checkBtAvailability,
    scanBtDevices,
    listPairedDevices,
    pairDevice,
    unpairDevice,
    connectBt,
    disconnectBt,
    getBtTunnelStatus,
    getBtConnectionLog,
    getBtConfig,
    updateBtConfig,
} from '../../../api/bluetooth';
import type {
    BtDiscoveredDevice,
    BtConnectionLogEntry,
    BtSyncConfig,
} from '../../../api/bluetooth';
import { toast } from '../../../lib/toast';

// ── Helpers ──────────────────────────────────────────────────────

function relativeTime(isoStr: string | null | undefined): string {
    if (!isoStr) return 'Never';
    try {
        const ms = Date.now() - new Date(isoStr + (isoStr.endsWith('Z') ? '' : 'Z')).getTime();
        const secs = Math.floor(ms / 1000);
        if (secs < 60) return 'Just now';
        const mins = Math.floor(secs / 60);
        if (mins < 60) return `${mins}m ago`;
        const hrs = Math.floor(mins / 60);
        if (hrs < 24) return `${hrs}h ago`;
        const days = Math.floor(hrs / 24);
        return `${days}d ago`;
    } catch { return isoStr; }
}

function formatBytes(bytes: number): string {
    if (bytes === 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(1024));
    return `${(bytes / Math.pow(1024, i)).toFixed(i > 0 ? 1 : 0)} ${units[i]}`;
}

function formatDuration(seconds: number | null | undefined): string {
    if (!seconds) return '—';
    if (seconds < 60) return `${Math.round(seconds)}s`;
    const mins = Math.floor(seconds / 60);
    const secs = Math.round(seconds % 60);
    if (mins < 60) return `${mins}m ${secs}s`;
    const hrs = Math.floor(mins / 60);
    return `${hrs}h ${mins % 60}m`;
}

const TUNNEL_STATE_CONFIG: Record<string, { label: string; color: string; bg: string }> = {
    stopped:       { label: 'Stopped',       color: 'text-gray-400',  bg: 'bg-gray-100 dark:bg-gray-800' },
    starting:      { label: 'Starting…',     color: 'text-amber-500', bg: 'bg-amber-50 dark:bg-amber-900/20' },
    listening:     { label: 'Listening',      color: 'text-blue-500',  bg: 'bg-blue-50 dark:bg-blue-900/20' },
    connecting:    { label: 'Connecting…',    color: 'text-amber-500', bg: 'bg-amber-50 dark:bg-amber-900/20' },
    connected:     { label: 'Connected',      color: 'text-green-500', bg: 'bg-green-50 dark:bg-green-900/20' },
    reconnecting:  { label: 'Reconnecting…', color: 'text-amber-500', bg: 'bg-amber-50 dark:bg-amber-900/20' },
    error:         { label: 'Error',          color: 'text-red-500',   bg: 'bg-red-50 dark:bg-red-900/20' },
};


// ── Tab: Status ──────────────────────────────────────────────────

function StatusTab() {
    const { data: availability, isLoading: loadingAvail } = useQuery({
        queryKey: ['bt-availability'],
        queryFn: checkBtAvailability,
        staleTime: 60_000,
        retry: 1,
    });

    const { data: tunnel, isLoading: loadingTunnel } = useQuery({
        queryKey: ['bt-tunnel-status'],
        queryFn: getBtTunnelStatus,
        refetchInterval: 5_000,
        retry: 1,
    });

    const state = tunnel?.state ?? 'stopped';
    const cfg = TUNNEL_STATE_CONFIG[state] ?? TUNNEL_STATE_CONFIG.stopped;
    const isActive = state === 'connected' || state === 'listening';

    if (loadingAvail || loadingTunnel) {
        return <div className="flex items-center justify-center py-12"><Spinner size="lg" /></div>;
    }

    return (
        <div className="space-y-4">
            {/* Hardware status */}
            <div className={`p-4 rounded-xl border border-border ${availability?.available ? 'bg-green-50 dark:bg-green-900/20' : 'bg-gray-100 dark:bg-gray-800'}`}>
                <div className="flex items-center gap-3">
                    <div className="w-12 h-12 rounded-full flex items-center justify-center bg-white/50 dark:bg-white/10">
                        {availability?.available
                            ? <Bluetooth className="h-6 w-6 text-green-500" />
                            : <BluetoothOff className="h-6 w-6 text-gray-400" />}
                    </div>
                    <div>
                        <h3 className="font-semibold text-gray-900 dark:text-gray-100">Bluetooth Hardware</h3>
                        <p className={`text-sm font-medium ${availability?.available ? 'text-green-600 dark:text-green-400' : 'text-gray-500'}`}>
                            {availability?.available ? 'Ready — Adapter found' : availability?.error ?? 'Not available'}
                        </p>
                    </div>
                </div>
            </div>

            {/* Tunnel status */}
            <div className={`p-4 rounded-xl border border-border ${cfg.bg}`}>
                <div className="flex items-center gap-3">
                    <div className="w-12 h-12 rounded-full flex items-center justify-center bg-white/50 dark:bg-white/10">
                        {isActive
                            ? <Link className={`h-6 w-6 ${cfg.color}`} />
                            : state === 'error'
                                ? <AlertTriangle className="h-6 w-6 text-red-500" />
                                : <Unlink className="h-6 w-6 text-gray-400" />}
                    </div>
                    <div className="flex-1 min-w-0">
                        <h3 className="font-semibold text-gray-900 dark:text-gray-100">RFCOMM Tunnel</h3>
                        <p className={`text-sm font-medium ${cfg.color}`}>{cfg.label}</p>
                        {tunnel?.remote_address && (
                            <p className="text-xs text-gray-500 mt-0.5">
                                {tunnel.mode === 'primary' ? 'Accepting from' : 'Connected to'}: <span className="font-mono">{tunnel.remote_address}</span>
                            </p>
                        )}
                    </div>
                    {isActive && (
                        <Badge variant="success">
                            <Activity className="h-3 w-3 mr-1" />
                            Live
                        </Badge>
                    )}
                </div>
            </div>

            {/* Stats (when connected) */}
            {tunnel && state !== 'stopped' && (
                <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
                    <div className="p-3 rounded-xl border border-border bg-surface space-y-1">
                        <p className="text-[10px] text-gray-400 uppercase tracking-wide">Uptime</p>
                        <p className="text-sm font-medium text-gray-900 dark:text-gray-100">
                            {formatDuration(tunnel.uptime_seconds)}
                        </p>
                    </div>
                    <div className="p-3 rounded-xl border border-border bg-surface space-y-1">
                        <p className="text-[10px] text-gray-400 uppercase tracking-wide">Requests</p>
                        <p className="text-sm font-medium text-gray-900 dark:text-gray-100">
                            {tunnel.requests_forwarded}
                        </p>
                    </div>
                    <div className="p-3 rounded-xl border border-border bg-surface space-y-1">
                        <p className="text-[10px] text-gray-400 uppercase tracking-wide">Data Sent</p>
                        <p className="text-sm font-medium text-gray-900 dark:text-gray-100">
                            {formatBytes(tunnel.bytes_sent)}
                        </p>
                    </div>
                    <div className="p-3 rounded-xl border border-border bg-surface space-y-1">
                        <p className="text-[10px] text-gray-400 uppercase tracking-wide">Data Recv</p>
                        <p className="text-sm font-medium text-gray-900 dark:text-gray-100">
                            {formatBytes(tunnel.bytes_received)}
                        </p>
                    </div>
                </div>
            )}

            {/* Error message */}
            {tunnel?.last_error && (
                <div className="p-3 rounded-xl bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800">
                    <p className="text-sm text-red-700 dark:text-red-300">
                        <AlertTriangle className="h-4 w-4 inline mr-1" />
                        {tunnel.last_error}
                    </p>
                </div>
            )}

            {/* Last heartbeat */}
            {tunnel?.last_heartbeat_at && (
                <p className="text-xs text-gray-400">
                    Last heartbeat: {relativeTime(tunnel.last_heartbeat_at)}
                    {tunnel.reconnect_count > 0 && ` · ${tunnel.reconnect_count} reconnect${tunnel.reconnect_count !== 1 ? 's' : ''}`}
                </p>
            )}
        </div>
    );
}


// ── Tab: Paired Devices ──────────────────────────────────────────

function PairedTab() {
    const qc = useQueryClient();

    const { data: devices, isLoading } = useQuery({
        queryKey: ['bt-paired'],
        queryFn: listPairedDevices,
        staleTime: 10_000,
    });

    const { data: tunnel } = useQuery({
        queryKey: ['bt-tunnel-status'],
        queryFn: getBtTunnelStatus,
        refetchInterval: 5_000,
        retry: 1,
    });

    const { data: config } = useQuery({
        queryKey: ['bt-config'],
        queryFn: getBtConfig,
        staleTime: 30_000,
    });

    const connectMut = useMutation({
        mutationFn: (args: { bt_address: string; role: string }) => connectBt(args),
        onSuccess: (result) => {
            if (result.success) {
                toast.success('Bluetooth tunnel started');
                qc.invalidateQueries({ queryKey: ['bt-tunnel-status'] });
                qc.invalidateQueries({ queryKey: ['bt-paired'] });
            } else {
                toast.error(result.error ?? 'Connect failed');
            }
        },
        onError: () => toast.error('Failed to start tunnel'),
    });

    const disconnectMut = useMutation({
        mutationFn: () => disconnectBt('manual'),
        onSuccess: () => {
            toast.success('Bluetooth tunnel disconnected');
            qc.invalidateQueries({ queryKey: ['bt-tunnel-status'] });
            qc.invalidateQueries({ queryKey: ['bt-paired'] });
        },
        onError: () => toast.error('Failed to disconnect'),
    });

    const unpairMut = useMutation({
        mutationFn: (id: number) => unpairDevice(id),
        onSuccess: () => {
            toast.success('Device unpaired');
            qc.invalidateQueries({ queryKey: ['bt-paired'] });
        },
        onError: () => toast.error('Failed to unpair device'),
    });

    const tunnelActive = tunnel?.state === 'connected' || tunnel?.state === 'listening';

    if (isLoading) {
        return <div className="flex items-center justify-center py-12"><Spinner size="lg" /></div>;
    }

    if (!devices || devices.length === 0) {
        return (
            <EmptyState
                icon={<Bluetooth className="h-12 w-12" />}
                title="No Paired Devices"
                description="Go to the Scan tab to discover nearby Bluetooth devices and pair with one."
            />
        );
    }

    return (
        <div className="space-y-3">
            {/* Active connection banner */}
            {tunnelActive && tunnel && (
                <div className="p-3 rounded-xl bg-green-50 dark:bg-green-900/20 border border-green-200 dark:border-green-800 flex items-center gap-3 flex-wrap">
                    <Wifi className="h-4 w-4 text-green-500 shrink-0" />
                    <span className="text-sm text-green-700 dark:text-green-300 flex-1">
                        Tunnel active ({tunnel.mode}) — syncing every {config?.bt_sync_interval ?? 120}s
                    </span>
                    <Button size="sm" variant="danger"
                        icon={<Unlink className="h-3.5 w-3.5" />}
                        onClick={() => disconnectMut.mutate()}
                        isLoading={disconnectMut.isPending}>
                        Disconnect
                    </Button>
                </div>
            )}

            {/* Device list */}
            {devices.map((dev) => (
                <div key={dev.id}
                    className="flex items-center gap-3 p-3 bg-surface border border-border rounded-xl">
                    <Monitor className={`h-5 w-5 shrink-0 ${dev.is_currently_connected ? 'text-green-500' : 'text-blue-500'}`} />
                    <div className="flex-1 min-w-0">
                        <div className="flex items-center gap-2 flex-wrap">
                            <span className="text-sm font-medium text-gray-900 dark:text-gray-100 truncate">
                                {dev.display_name}
                            </span>
                            <Badge variant={dev.role === 'primary' ? 'info' : 'neutral'} className="text-[10px]">
                                {dev.role}
                            </Badge>
                            {dev.is_currently_connected && (
                                <Badge variant="success" className="text-[10px]">
                                    <Activity className="h-2.5 w-2.5 mr-0.5" />
                                    Connected
                                </Badge>
                            )}
                        </div>
                        <div className="flex items-center gap-3 mt-0.5 text-xs text-gray-500">
                            <span className="font-mono">{dev.bt_address}</span>
                            {dev.last_sync_at && (
                                <span>Synced: {relativeTime(dev.last_sync_at)}</span>
                            )}
                        </div>
                    </div>

                    {/* Actions */}
                    <div className="flex items-center gap-2 shrink-0">
                        {!dev.is_currently_connected && !tunnelActive && (
                            <Button size="sm" variant="primary"
                                icon={<Link className="h-3.5 w-3.5" />}
                                onClick={() => connectMut.mutate({
                                    bt_address: dev.bt_address,
                                    role: dev.role,
                                })}
                                isLoading={connectMut.isPending}>
                                <span className="hidden sm:inline">Connect</span>
                            </Button>
                        )}
                        <Button size="sm" variant="ghost"
                            icon={<Trash2 className="h-3.5 w-3.5 text-red-500" />}
                            onClick={() => {
                                if (confirm(`Unpair "${dev.display_name}"?`)) {
                                    unpairMut.mutate(dev.id);
                                }
                            }}
                            disabled={dev.is_currently_connected} />
                    </div>
                </div>
            ))}

            {/* Pairing code info */}
            {devices.some(d => d.pairing_code) && (
                <p className="text-xs text-gray-400">
                    Pairing codes are shown for verification. Both devices should display the same code.
                </p>
            )}
        </div>
    );
}


// ── Tab: Scan ────────────────────────────────────────────────────

function ScanTab() {
    const qc = useQueryClient();
    const [scanning, setScanning] = useState(false);
    const [discovered, setDiscovered] = useState<BtDiscoveredDevice[]>([]);
    const [pairingAddr, setPairingAddr] = useState<string | null>(null);

    const handleScan = async () => {
        setScanning(true);
        setDiscovered([]);
        try {
            const result = await scanBtDevices(10);
            setDiscovered(result.devices ?? []);
            if (result.error) toast.error(result.error);
        } catch (e: any) {
            toast.error(e?.message ?? 'Scan failed');
        } finally {
            setScanning(false);
        }
    };

    const pairMut = useMutation({
        mutationFn: (dev: BtDiscoveredDevice) => pairDevice({
            bt_address: dev.address,
            display_name: dev.name || 'Unknown Device',
            role: 'secondary',  // Default; user sets real role via config
        }),
        onSuccess: (result) => {
            toast.success(`Paired with ${result.display_name}`);
            qc.invalidateQueries({ queryKey: ['bt-paired'] });
            setPairingAddr(null);
            // Mark device as paired in local list
            setDiscovered(prev => prev.map(d =>
                d.address === result.bt_address ? { ...d, is_paired: true } : d
            ));
        },
        onError: () => {
            toast.error('Pairing failed');
            setPairingAddr(null);
        },
    });

    return (
        <div className="space-y-4">
            {/* Scan controls */}
            <div className="flex items-center gap-3 flex-wrap">
                <Button variant="primary"
                    icon={scanning
                        ? <Loader2 className="h-4 w-4 animate-spin" />
                        : <Radio className="h-4 w-4" />}
                    onClick={handleScan}
                    disabled={scanning}>
                    {scanning ? 'Scanning…' : 'Scan for Devices'}
                </Button>
                <p className="text-sm text-gray-500 dark:text-gray-400">
                    {scanning
                        ? 'Discovering nearby Bluetooth devices…'
                        : `${discovered.length} device${discovered.length !== 1 ? 's' : ''} found`}
                </p>
            </div>

            {/* Results */}
            {discovered.length === 0 && !scanning && (
                <EmptyState
                    icon={<Bluetooth className="h-10 w-10" />}
                    title="No Devices Found"
                    description="Make sure the other PC has Bluetooth enabled and is discoverable. Click 'Scan for Devices' to search."
                />
            )}

            {discovered.length > 0 && (
                <div className="space-y-2">
                    {discovered.map((dev) => (
                        <div key={dev.address}
                            className="flex items-center gap-3 p-3 bg-surface border border-border rounded-xl">
                            <Monitor className="h-5 w-5 text-blue-500 shrink-0" />
                            <div className="flex-1 min-w-0">
                                <div className="flex items-center gap-2 flex-wrap">
                                    <span className="text-sm font-medium text-gray-900 dark:text-gray-100 truncate">
                                        {dev.name || 'Unknown Device'}
                                    </span>
                                    {dev.is_paired && (
                                        <Badge variant="success" className="text-[10px]">Already Paired</Badge>
                                    )}
                                </div>
                                <span className="text-xs font-mono text-gray-500">{dev.address}</span>
                            </div>
                            {!dev.is_paired && (
                                <Button size="sm" variant="primary"
                                    icon={<Plus className="h-3.5 w-3.5" />}
                                    onClick={() => {
                                        setPairingAddr(dev.address);
                                        pairMut.mutate(dev);
                                    }}
                                    isLoading={pairingAddr === dev.address && pairMut.isPending}>
                                    <span className="hidden sm:inline">Pair</span>
                                </Button>
                            )}
                        </div>
                    ))}
                </div>
            )}

            {/* Tip */}
            <p className="text-xs text-gray-400">
                Both PCs need Bluetooth enabled. The other PC should be set to discoverable
                in Windows Bluetooth settings. After pairing here, use the Paired tab to connect.
            </p>
        </div>
    );
}


// ── Tab: History ─────────────────────────────────────────────────

function HistoryTab() {
    const { data: log, isLoading, refetch, isFetching } = useQuery({
        queryKey: ['bt-connection-log'],
        queryFn: () => getBtConnectionLog({ limit: 50 }),
        staleTime: 30_000,
    });

    if (isLoading) {
        return <div className="flex items-center justify-center py-12"><Spinner size="lg" /></div>;
    }

    const entries = log?.entries ?? [];

    if (entries.length === 0) {
        return (
            <EmptyState
                icon={<Clock className="h-12 w-12" />}
                title="No Connection History"
                description="Connection sessions will appear here after you connect to a paired device."
            />
        );
    }

    return (
        <div className="space-y-3">
            <div className="flex items-center justify-between">
                <p className="text-sm text-gray-500 dark:text-gray-400">
                    {log?.total ?? entries.length} session{(log?.total ?? entries.length) !== 1 ? 's' : ''}
                </p>
                <Button size="sm" variant="secondary"
                    icon={<RefreshCw className={`h-3.5 w-3.5 ${isFetching ? 'animate-spin' : ''}`} />}
                    onClick={() => refetch()}>
                    <span className="hidden sm:inline">Refresh</span>
                </Button>
            </div>

            {entries.map((entry: BtConnectionLogEntry) => {
                const isActive = !entry.disconnected_at;
                const isErr = entry.disconnect_reason === 'error';

                return (
                    <div key={entry.id}
                        className="flex items-center gap-3 px-3 py-2.5 bg-surface border border-border rounded-lg text-xs">
                        {isActive
                            ? <Activity className="h-4 w-4 text-green-500 shrink-0 animate-pulse" />
                            : isErr
                                ? <XCircle className="h-4 w-4 text-red-500 shrink-0" />
                                : <CheckCircle className="h-4 w-4 text-gray-400 shrink-0" />}
                        <div className="flex-1 min-w-0 grid grid-cols-2 sm:grid-cols-4 gap-x-4 gap-y-1">
                            <div>
                                <span className="text-gray-400">Remote: </span>
                                <span className="font-mono text-gray-900 dark:text-gray-100">{entry.remote_bt_address}</span>
                            </div>
                            <div>
                                <span className="text-gray-400">Duration: </span>
                                <span className="text-gray-900 dark:text-gray-100">
                                    {isActive ? 'Active' : formatDuration(entry.duration_seconds)}
                                </span>
                            </div>
                            <div>
                                <span className="text-gray-400">Synced: </span>
                                <span className="text-gray-900 dark:text-gray-100">
                                    {entry.changes_synced} changes · {entry.requests_forwarded} req
                                </span>
                            </div>
                            <div className="flex items-center gap-2">
                                <span className="text-gray-400">
                                    ↑{formatBytes(entry.bytes_sent)} ↓{formatBytes(entry.bytes_received)}
                                </span>
                                {entry.disconnect_reason && (
                                    <Badge variant={isErr ? 'danger' : 'neutral'} className="text-[10px]">
                                        {entry.disconnect_reason}
                                    </Badge>
                                )}
                            </div>
                        </div>
                        <span className="text-gray-400 shrink-0">{relativeTime(entry.connected_at)}</span>
                    </div>
                );
            })}
        </div>
    );
}


// ── Tab: Config ──────────────────────────────────────────────────

function ConfigTab() {
    const qc = useQueryClient();

    const { data: config, isLoading } = useQuery({
        queryKey: ['bt-config'],
        queryFn: getBtConfig,
        staleTime: 30_000,
    });

    const saveMut = useMutation({
        mutationFn: (updates: Partial<BtSyncConfig>) => updateBtConfig(updates),
        onSuccess: (result) => {
            qc.setQueryData(['bt-config'], result);
            toast.success('Bluetooth settings saved');
        },
        onError: () => toast.error('Failed to save settings'),
    });

    const [localConfig, setLocalConfig] = useState<Partial<BtSyncConfig>>({});

    // Sync local state when server data arrives
    const merged: BtSyncConfig = {
        bt_enabled: true,
        bt_device_role: 'auto',
        bt_auto_connect: true,
        bt_sync_interval: 120,
        bt_tunnel_port: 9000,
        ...config,
        ...localConfig,
    };

    const handleChange = (key: keyof BtSyncConfig, value: any) => {
        setLocalConfig(prev => ({ ...prev, [key]: value }));
    };

    const handleSave = () => {
        saveMut.mutate(localConfig);
        setLocalConfig({});
    };

    const hasChanges = Object.keys(localConfig).length > 0;

    if (isLoading) {
        return <div className="flex items-center justify-center py-12"><Spinner size="lg" /></div>;
    }

    return (
        <div className="space-y-4">
            {/* Enable toggle */}
            <div className="flex items-center justify-between p-3 bg-surface border border-border rounded-xl">
                <div>
                    <p className="text-sm font-medium text-gray-900 dark:text-gray-100">Bluetooth Sync</p>
                    <p className="text-xs text-gray-500">Enable or disable all Bluetooth features</p>
                </div>
                <label className="relative inline-flex items-center cursor-pointer">
                    <input type="checkbox" className="sr-only peer"
                        checked={merged.bt_enabled}
                        onChange={(e) => handleChange('bt_enabled', e.target.checked)} />
                    <div className="w-11 h-6 bg-gray-200 dark:bg-gray-700 peer-focus:ring-2 peer-focus:ring-blue-300 rounded-full peer peer-checked:after:translate-x-full after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-blue-600" />
                </label>
            </div>

            {/* Role */}
            <div className="p-3 bg-surface border border-border rounded-xl space-y-2">
                <p className="text-sm font-medium text-gray-900 dark:text-gray-100">Device Role</p>
                <p className="text-xs text-gray-500">
                    Primary = shop/truth anchor (listens for connections). Secondary = field PC (connects to primary).
                </p>
                <div className="flex gap-2 flex-wrap">
                    {(['auto', 'primary', 'secondary'] as const).map((role) => (
                        <button key={role}
                            onClick={() => handleChange('bt_device_role', role)}
                            className={`px-3 py-1.5 text-sm rounded-lg border transition-colors ${
                                merged.bt_device_role === role
                                    ? 'border-blue-500 bg-blue-50 dark:bg-blue-900/30 text-blue-700 dark:text-blue-300 font-medium'
                                    : 'border-border text-gray-600 dark:text-gray-400 hover:bg-gray-50 dark:hover:bg-gray-800'
                            }`}>
                            {role.charAt(0).toUpperCase() + role.slice(1)}
                        </button>
                    ))}
                </div>
            </div>

            {/* Auto-connect */}
            <div className="flex items-center justify-between p-3 bg-surface border border-border rounded-xl">
                <div>
                    <p className="text-sm font-medium text-gray-900 dark:text-gray-100">Auto-Connect</p>
                    <p className="text-xs text-gray-500">Automatically connect to paired device on startup</p>
                </div>
                <label className="relative inline-flex items-center cursor-pointer">
                    <input type="checkbox" className="sr-only peer"
                        checked={merged.bt_auto_connect}
                        onChange={(e) => handleChange('bt_auto_connect', e.target.checked)} />
                    <div className="w-11 h-6 bg-gray-200 dark:bg-gray-700 peer-focus:ring-2 peer-focus:ring-blue-300 rounded-full peer peer-checked:after:translate-x-full after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-blue-600" />
                </label>
            </div>

            {/* Sync interval */}
            <div className="p-3 bg-surface border border-border rounded-xl space-y-2">
                <p className="text-sm font-medium text-gray-900 dark:text-gray-100">Sync Interval</p>
                <p className="text-xs text-gray-500">
                    How often to push/pull data when the BT tunnel is active (seconds).
                </p>
                <div className="flex items-center gap-3">
                    <input type="range" min={30} max={600} step={30}
                        value={merged.bt_sync_interval}
                        onChange={(e) => handleChange('bt_sync_interval', Number(e.target.value))}
                        className="flex-1 accent-blue-500" />
                    <span className="text-sm font-mono text-gray-900 dark:text-gray-100 w-16 text-right">
                        {merged.bt_sync_interval}s
                    </span>
                </div>
            </div>

            {/* Tunnel port */}
            <div className="p-3 bg-surface border border-border rounded-xl space-y-2">
                <p className="text-sm font-medium text-gray-900 dark:text-gray-100">Tunnel Port</p>
                <p className="text-xs text-gray-500">
                    Local TCP port for the BT tunnel proxy (secondary mode). Change only if 9000 conflicts.
                </p>
                <input type="number" min={1024} max={65535}
                    value={merged.bt_tunnel_port}
                    onChange={(e) => handleChange('bt_tunnel_port', Number(e.target.value))}
                    className="w-24 px-3 py-1.5 text-sm border border-border rounded-md bg-surface text-gray-900 dark:text-gray-100" />
            </div>

            {/* Save */}
            {hasChanges && (
                <Button variant="primary"
                    icon={<Settings2 className="h-4 w-4" />}
                    onClick={handleSave}
                    isLoading={saveMut.isPending}>
                    Save Settings
                </Button>
            )}
        </div>
    );
}


// ── Main Page ────────────────────────────────────────────────────

type Tab = 'status' | 'paired' | 'scan' | 'history' | 'config';

const TABS: { id: Tab; label: string; shortLabel?: string; icon: React.FC<{ className?: string }> }[] = [
    { id: 'status',  label: 'Status',  icon: Bluetooth },
    { id: 'paired',  label: 'Paired',  icon: Link },
    { id: 'scan',    label: 'Scan',    icon: Radio },
    { id: 'history', label: 'History', icon: Clock },
    { id: 'config',  label: 'Config',  icon: Settings2 },
];

export function BluetoothPage() {
    const [tab, setTab] = useState<Tab>('status');

    return (
        <div className="space-y-5">
            <div>
                <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-100">
                    Bluetooth Sync
                </h2>
                <p className="text-sm text-gray-500 dark:text-gray-400 mt-0.5">
                    Pair with another PC and sync data over Bluetooth RFCOMM when no network is available.
                </p>
            </div>

            {/* Tab bar */}
            <div className="flex gap-1 overflow-x-auto bg-surface-secondary rounded-xl p-1 border border-border">
                {TABS.map(({ id, label, icon: Icon }) => (
                    <button key={id} onClick={() => setTab(id)}
                        className={`flex items-center gap-1.5 px-3 py-2 rounded-lg text-sm font-medium transition-colors whitespace-nowrap flex-1 justify-center ${tab === id
                                ? 'bg-surface text-gray-900 dark:text-gray-100 shadow-sm'
                                : 'text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-300'
                            }`}>
                        <Icon className="h-4 w-4" />
                        <span className="hidden sm:inline">{label}</span>
                    </button>
                ))}
            </div>

            <Card>
                <div className="p-1">
                    {tab === 'status' && <StatusTab />}
                    {tab === 'paired' && <PairedTab />}
                    {tab === 'scan' && <ScanTab />}
                    {tab === 'history' && <HistoryTab />}
                    {tab === 'config' && <ConfigTab />}
                </div>
            </Card>
        </div>
    );
}
