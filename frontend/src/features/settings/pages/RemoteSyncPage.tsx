/**
 * RemoteSyncPage — Internet-based remote sync configuration and monitoring.
 *
 * Card sections:
 * 1. Dashboard — overview stats (enabled?, active peers, sessions, last-24h summary)
 * 2. Configuration — toggle remote sync, URLs, TLS, rate limiting, fail2ban
 * 3. Peer Management — register/verify/deactivate partner shops + health
 * 4. Multi-Site — primary/secondary role management
 * 5. File-Based Sync — export/import for USB sneakernet fallback
 * 6. Fail2Ban — blocked IPs and clear action
 * 7. Session History — recent remote sync sessions
 */

import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
    Globe, Activity, Shield, ShieldAlert,
    Server, Plus, CheckCircle, XCircle, RefreshCw,
    Wifi, WifiOff, HardDrive, Upload,
    Trash2, AlertTriangle, Link2, ChevronDown, ChevronUp,
    Eye, EyeOff, Clock, Ban,
} from 'lucide-react';
import { Badge } from '../../../components/ui/Badge';
import { Button } from '../../../components/ui/Button';
import { Card, CardHeader } from '../../../components/ui/Card';
import { PageSpinner } from '../../../components/ui/Spinner';
import { EmptyState } from '../../../components/ui/EmptyState';
import { toast } from '../../../lib/toast';
import {
    getRemoteSyncConfig, updateRemoteSyncConfig,
    getRemoteSyncDashboard,
    listPeers, registerPeer, verifyPeer, deactivatePeer,
    checkPeerHealth,
    getMultiSiteStatus, setMultiSiteRole,
    listSessions,
    exportFileSyncPackage, listFileSyncPackages,
    listFailban, clearFailban,
    type RemoteSyncConfig, type RemotePeer, type RemoteSyncSession,
    type RemoteSyncDashboard, type PeerHealthStatus,
    type MultiSiteStatus, type FileSyncPackage, type FailbanEntry,
} from '../../../api/remote-sync';


// ── Toggle switch ────────────────────────────────────────────────

function Toggle({
    checked, onChange, disabled = false,
}: {
    checked: boolean;
    onChange: (v: boolean) => void;
    disabled?: boolean;
}) {
    return (
        <button
            type="button"
            role="switch"
            aria-checked={checked}
            disabled={disabled}
            onClick={() => onChange(!checked)}
            className={`relative inline-flex h-6 w-11 flex-shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 focus:outline-none focus:ring-2 focus:ring-primary focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50 ${
                checked ? 'bg-green-500' : 'bg-gray-200 dark:bg-gray-700'
            }`}
        >
            <span
                className={`pointer-events-none inline-block h-5 w-5 rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out ${
                    checked ? 'translate-x-5' : 'translate-x-0'
                }`}
            />
        </button>
    );
}


// ── Page Root ───────────────────────────────────────────────────

export function RemoteSyncPage() {
    return (
        <div className="space-y-6">
            <h2 className="text-xl font-bold text-gray-900 dark:text-gray-100 flex items-center gap-2">
                <Globe className="h-5 w-5" />
                Remote Sync
            </h2>

            <DashboardCard />
            <ConfigCard />
            <PeerManagementCard />
            <MultiSiteCard />
            <FileSyncCard />
            <FailBanCard />
            <SessionHistoryCard />
        </div>
    );
}


// ── 1. Dashboard ────────────────────────────────────────────────

function DashboardCard() {
    const { data: dash, isLoading } = useQuery<RemoteSyncDashboard>({
        queryKey: ['remote-sync', 'dashboard'],
        queryFn: getRemoteSyncDashboard,
        staleTime: 30_000,
    });

    if (isLoading) return <PageSpinner />;
    if (!dash) return null;

    const enabled = !!dash.is_enabled;

    return (
        <Card>
            <CardHeader
                title="Remote Sync Overview"
                action={
                    <Badge variant={enabled ? 'success' : 'secondary'}>
                        {enabled ? 'Enabled' : 'Disabled'}
                    </Badge>
                }
            />
            <div className="grid grid-cols-2 sm:grid-cols-4 gap-4">
                <StatBox
                    label="Role"
                    value={dash.multi_site_role}
                    icon={<Server className="h-4 w-4 text-primary-500" />}
                />
                <StatBox
                    label="Active Peers"
                    value={String(dash.active_peers)}
                    icon={<Link2 className="h-4 w-4 text-blue-500" />}
                />
                <StatBox
                    label="Sessions (24h)"
                    value={`${dash.last_24h.completed}/${dash.last_24h.total}`}
                    icon={<Activity className="h-4 w-4 text-green-500" />}
                />
                <StatBox
                    label="Failed (24h)"
                    value={String(dash.last_24h.failed)}
                    icon={<AlertTriangle className="h-4 w-4 text-red-500" />}
                />
            </div>
            {dash.public_url && (
                <p className="mt-3 text-xs text-gray-500 dark:text-gray-400">
                    Public URL: <span className="font-mono">{dash.public_url}</span>
                </p>
            )}
        </Card>
    );
}

function StatBox({ label, value, icon }: { label: string; value: string; icon: React.ReactNode }) {
    return (
        <div className="bg-gray-50 dark:bg-gray-800/50 rounded-lg p-3 text-center">
            <div className="flex items-center justify-center mb-1">{icon}</div>
            <p className="text-lg font-bold text-gray-900 dark:text-gray-100">{value}</p>
            <p className="text-xs text-gray-500 dark:text-gray-400">{label}</p>
        </div>
    );
}


// ── 2. Configuration ────────────────────────────────────────────

function ConfigCard() {
    const queryClient = useQueryClient();
    const [expanded, setExpanded] = useState(false);

    const { data: config, isLoading } = useQuery<RemoteSyncConfig>({
        queryKey: ['remote-sync', 'config'],
        queryFn: getRemoteSyncConfig,
        staleTime: 60_000,
    });

    const updateMut = useMutation({
        mutationFn: (fields: Record<string, unknown>) => updateRemoteSyncConfig(fields),
        onSuccess: () => {
            queryClient.invalidateQueries({ queryKey: ['remote-sync'] });
            toast.success('Configuration saved');
        },
        onError: () => toast.error('Failed to save configuration'),
    });

    if (isLoading) return <PageSpinner />;
    if (!config) return null;

    const enabled = !!config.is_enabled;

    function saveField(field: string, value: unknown) {
        updateMut.mutate({ [field]: value });
    }

    return (
        <Card>
            <CardHeader
                title="Configuration"
                subtitle="Internet access, TLS, rate limiting, and security settings"
                action={
                    <Button
                        size="sm"
                        variant="ghost"
                        onClick={() => setExpanded(!expanded)}
                    >
                        {expanded ? <ChevronUp className="h-4 w-4" /> : <ChevronDown className="h-4 w-4" />}
                    </Button>
                }
            />

            {/* Always visible: Enable toggle */}
            <div className="flex items-center justify-between py-2">
                <div>
                    <p className="text-sm font-medium text-gray-900 dark:text-gray-100">
                        Enable Remote Sync
                    </p>
                    <p className="text-xs text-gray-500 dark:text-gray-400">
                        Allow remote devices and peer shops to connect over the internet
                    </p>
                </div>
                <Toggle
                    checked={enabled}
                    onChange={(v) => saveField('is_enabled', v ? 1 : 0)}
                    disabled={updateMut.isPending}
                />
            </div>

            {expanded && (
                <div className="mt-4 space-y-4 border-t border-gray-200 dark:border-gray-700 pt-4">
                    {/* Public URL */}
                    <FieldRow label="Public URL" helpText="HTTPS URL where this shop is reachable from the internet">
                        <EditableField
                            value={config.public_url ?? ''}
                            placeholder="https://shop.example.com"
                            onSave={(v) => saveField('public_url', v || null)}
                        />
                    </FieldRow>

                    {/* Listen Port */}
                    <FieldRow label="Listen Port">
                        <EditableField
                            value={String(config.listen_port)}
                            onSave={(v) => saveField('listen_port', parseInt(v) || 8443)}
                        />
                    </FieldRow>

                    {/* TLS Cert Path */}
                    <FieldRow label="TLS Certificate Path">
                        <EditableField
                            value={config.tls_cert_path ?? ''}
                            placeholder="/etc/ssl/certs/shop.pem"
                            onSave={(v) => saveField('tls_cert_path', v || null)}
                        />
                    </FieldRow>

                    {/* TLS Key Path */}
                    <FieldRow label="TLS Key Path">
                        <EditableField
                            value={config.tls_key_path ?? ''}
                            placeholder="/etc/ssl/private/shop-key.pem"
                            onSave={(v) => saveField('tls_key_path', v || null)}
                        />
                    </FieldRow>

                    {/* Proxy Mode */}
                    <FieldRow label="Proxy Mode">
                        <select
                            value={config.proxy_mode}
                            onChange={(e) => saveField('proxy_mode', e.target.value)}
                            className="px-3 py-1.5 text-sm border border-gray-300 dark:border-gray-600 rounded-md bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100"
                        >
                            <option value="none">None (Direct)</option>
                            <option value="nginx">Nginx Reverse Proxy</option>
                            <option value="caddy">Caddy</option>
                            <option value="cloudflare">Cloudflare Tunnel</option>
                        </select>
                    </FieldRow>

                    {/* Rate Limit */}
                    <FieldRow label="Rate Limit (req/min)">
                        <EditableField
                            value={String(config.rate_limit_rpm)}
                            onSave={(v) => saveField('rate_limit_rpm', parseInt(v) || 60)}
                        />
                    </FieldRow>

                    {/* Max Payload */}
                    <FieldRow label="Max Payload (KB)">
                        <EditableField
                            value={String(config.max_payload_kb)}
                            onSave={(v) => saveField('max_payload_kb', parseInt(v) || 10240)}
                        />
                    </FieldRow>

                    {/* Require Cert Auth */}
                    <div className="flex items-center justify-between">
                        <div>
                            <p className="text-sm font-medium text-gray-900 dark:text-gray-100">
                                Require Certificate Auth
                            </p>
                            <p className="text-xs text-gray-500 dark:text-gray-400">
                                Devices must present a valid certificate to connect
                            </p>
                        </div>
                        <Toggle
                            checked={!!config.require_cert_auth}
                            onChange={(v) => saveField('require_cert_auth', v ? 1 : 0)}
                        />
                    </div>

                    {/* Fail2Ban */}
                    <div className="flex items-center justify-between">
                        <div>
                            <p className="text-sm font-medium text-gray-900 dark:text-gray-100">
                                Fail2Ban Protection
                            </p>
                            <p className="text-xs text-gray-500 dark:text-gray-400">
                                Auto-block IPs after {config.failban_max_attempts} failures for {config.failban_lockout_minutes} min
                            </p>
                        </div>
                        <Toggle
                            checked={!!config.failban_enabled}
                            onChange={(v) => saveField('failban_enabled', v ? 1 : 0)}
                        />
                    </div>

                    {/* Allowed CIDRs */}
                    <FieldRow label="Allowed CIDRs" helpText="Comma-separated CIDR ranges (empty = allow all)">
                        <EditableField
                            value={(config.allowed_cidrs ?? []).join(', ')}
                            placeholder="0.0.0.0/0"
                            onSave={(v) => saveField(
                                'allowed_cidrs',
                                v ? v.split(',').map((s: string) => s.trim()).filter(Boolean) : [],
                            )}
                        />
                    </FieldRow>
                </div>
            )}
        </Card>
    );
}


// ── 3. Peer Management ──────────────────────────────────────────

function PeerManagementCard() {
    const queryClient = useQueryClient();
    const [showAdd, setShowAdd] = useState(false);
    const [newName, setNewName] = useState('');
    const [newUrl, setNewUrl] = useState('');
    const [newType, setNewType] = useState<'partner' | 'multi_site'>('partner');

    const { data: peers = [], isLoading } = useQuery<RemotePeer[]>({
        queryKey: ['remote-sync', 'peers'],
        queryFn: () => listPeers(),
        staleTime: 30_000,
    });

    const { data: health = [] } = useQuery<PeerHealthStatus[]>({
        queryKey: ['remote-sync', 'health'],
        queryFn: checkPeerHealth,
        staleTime: 30_000,
    });

    const registerMut = useMutation({
        mutationFn: () => registerPeer({ peer_name: newName, peer_url: newUrl, peer_type: newType }),
        onSuccess: (peer) => {
            queryClient.invalidateQueries({ queryKey: ['remote-sync'] });
            toast.success(`Peer "${peer.peer_name}" registered. Share the secret to verify.`);
            setShowAdd(false);
            setNewName('');
            setNewUrl('');
        },
        onError: () => toast.error('Failed to register peer'),
    });

    const verifyMut = useMutation({
        mutationFn: ({ peerId, key }: { peerId: string; key: string }) => verifyPeer(peerId, key),
        onSuccess: () => {
            queryClient.invalidateQueries({ queryKey: ['remote-sync'] });
            toast.success('Peer verified');
        },
        onError: () => toast.error('Verification failed'),
    });

    const deactivateMut = useMutation({
        mutationFn: (peerId: string) => deactivatePeer(peerId),
        onSuccess: () => {
            queryClient.invalidateQueries({ queryKey: ['remote-sync'] });
            toast.success('Peer deactivated');
        },
        onError: () => toast.error('Failed to deactivate'),
    });

    const healthMap = new Map(health.map(h => [h.peer_id, h]));

    return (
        <Card>
            <CardHeader
                title="Peer Shops"
                subtitle="Manage connections to partner shops and multi-site nodes"
                action={
                    <Button size="sm" onClick={() => setShowAdd(!showAdd)}>
                        <Plus className="h-4 w-4 mr-1" />
                        <span className="hidden sm:inline">Add Peer</span>
                    </Button>
                }
            />

            {/* Add Peer Form */}
            {showAdd && (
                <div className="mb-4 p-3 bg-gray-50 dark:bg-gray-800/50 rounded-lg space-y-3">
                    <div className="grid grid-cols-1 sm:grid-cols-3 gap-2">
                        <input
                            value={newName}
                            onChange={(e) => setNewName(e.target.value)}
                            placeholder="Peer shop name"
                            className="px-3 py-2 text-sm border border-gray-300 dark:border-gray-600 rounded-md bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100"
                        />
                        <input
                            value={newUrl}
                            onChange={(e) => setNewUrl(e.target.value)}
                            placeholder="https://peer.example.com"
                            className="px-3 py-2 text-sm border border-gray-300 dark:border-gray-600 rounded-md bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100"
                        />
                        <select
                            value={newType}
                            onChange={(e) => setNewType(e.target.value as 'partner' | 'multi_site')}
                            className="px-3 py-2 text-sm border border-gray-300 dark:border-gray-600 rounded-md bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100"
                        >
                            <option value="partner">Partner Shop</option>
                            <option value="multi_site">Multi-Site Node</option>
                        </select>
                    </div>
                    <div className="flex gap-2">
                        <Button
                            size="sm"
                            onClick={() => registerMut.mutate()}
                            disabled={!newName || !newUrl || registerMut.isPending}
                        >
                            {registerMut.isPending ? <RefreshCw className="h-4 w-4 animate-spin" /> : 'Register'}
                        </Button>
                        <Button size="sm" variant="secondary" onClick={() => setShowAdd(false)}>Cancel</Button>
                    </div>
                </div>
            )}

            {/* Peer List */}
            {isLoading ? (
                <PageSpinner />
            ) : peers.length === 0 ? (
                <EmptyState icon={Link2} title="No peer shops registered" />
            ) : (
                <div className="space-y-2">
                    {peers.map(peer => (
                        <PeerRow
                            key={peer.peer_id}
                            peer={peer}
                            health={healthMap.get(peer.peer_id)}
                            onVerify={(key) => verifyMut.mutate({ peerId: peer.peer_id, key })}
                            onDeactivate={() => deactivateMut.mutate(peer.peer_id)}
                        />
                    ))}
                </div>
            )}
        </Card>
    );
}

function PeerRow({
    peer, health, onVerify, onDeactivate,
}: {
    peer: RemotePeer;
    health?: PeerHealthStatus;
    onVerify: (key: string) => void;
    onDeactivate: () => void;
}) {
    const [showKey, setShowKey] = useState(false);
    const [verifyKey, setVerifyKey] = useState('');
    const [showVerify, setShowVerify] = useState(false);

    const statusColor = !peer.is_active
        ? 'secondary'
        : peer.is_verified
            ? (health?.health === 'healthy' ? 'success' : health?.health === 'stale' ? 'warning' : 'danger')
            : 'warning';

    const statusLabel = !peer.is_active
        ? 'Inactive'
        : !peer.is_verified
            ? 'Unverified'
            : health?.health ?? 'Unknown';

    return (
        <div className="p-3 bg-gray-50 dark:bg-gray-800/50 rounded-lg space-y-2">
            <div className="flex items-center justify-between gap-2 flex-wrap">
                <div className="flex items-center gap-2 min-w-0">
                    {peer.is_active ? (
                        <Wifi className="h-4 w-4 text-green-500 flex-shrink-0" />
                    ) : (
                        <WifiOff className="h-4 w-4 text-gray-400 flex-shrink-0" />
                    )}
                    <div className="min-w-0">
                        <p className="text-sm font-medium text-gray-900 dark:text-gray-100 truncate">
                            {peer.peer_name}
                        </p>
                        <p className="text-xs text-gray-500 dark:text-gray-400 font-mono truncate">
                            {peer.peer_url}
                        </p>
                    </div>
                </div>
                <div className="flex items-center gap-2 flex-shrink-0">
                    <Badge variant={statusColor}>{statusLabel}</Badge>
                    <Badge variant="secondary">{peer.peer_type}</Badge>
                </div>
            </div>

            {/* Stats row */}
            <div className="flex flex-wrap gap-3 text-xs text-gray-500 dark:text-gray-400">
                <span>Syncs: {peer.total_syncs}</span>
                <span>↑ {peer.total_changes_sent}</span>
                <span>↓ {peer.total_changes_received}</span>
                {peer.error_count > 0 && (
                    <span className="text-red-500">Errors: {peer.error_count}</span>
                )}
                {peer.last_sync_at && (
                    <span>Last: {new Date(peer.last_sync_at).toLocaleString()}</span>
                )}
            </div>

            {/* Shared Secret (only for unverified) */}
            {peer.shared_secret && !peer.is_verified && (
                <div className="flex items-center gap-2 text-xs">
                    <span className="text-gray-500 dark:text-gray-400">Secret:</span>
                    <code className="bg-gray-200 dark:bg-gray-700 px-2 py-0.5 rounded font-mono">
                        {showKey ? peer.shared_secret : '••••••••'}
                    </code>
                    <button onClick={() => setShowKey(!showKey)} className="text-primary-500 hover:underline">
                        {showKey ? <EyeOff className="h-3 w-3" /> : <Eye className="h-3 w-3" />}
                    </button>
                </div>
            )}

            {/* Actions */}
            <div className="flex gap-2 flex-wrap">
                {peer.is_active && !peer.is_verified && (
                    <>
                        {showVerify ? (
                            <div className="flex gap-2 items-center">
                                <input
                                    value={verifyKey}
                                    onChange={(e) => setVerifyKey(e.target.value)}
                                    placeholder="Public key from peer"
                                    className="px-2 py-1 text-xs border border-gray-300 dark:border-gray-600 rounded bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 w-48"
                                />
                                <Button size="sm" onClick={() => { onVerify(verifyKey); setShowVerify(false); }}>
                                    <CheckCircle className="h-3 w-3 mr-1" /> Verify
                                </Button>
                                <Button size="sm" variant="secondary" onClick={() => setShowVerify(false)}>Cancel</Button>
                            </div>
                        ) : (
                            <Button size="sm" variant="secondary" onClick={() => setShowVerify(true)}>
                                <ShieldAlert className="h-3 w-3 mr-1" /> Verify
                            </Button>
                        )}
                    </>
                )}
                {peer.is_active && (
                    <Button size="sm" variant="danger" onClick={onDeactivate}>
                        <XCircle className="h-3 w-3 mr-1" /> Deactivate
                    </Button>
                )}
            </div>
        </div>
    );
}


// ── 4. Multi-Site ───────────────────────────────────────────────

function MultiSiteCard() {
    const queryClient = useQueryClient();

    const { data: status, isLoading } = useQuery<MultiSiteStatus>({
        queryKey: ['remote-sync', 'multi-site'],
        queryFn: getMultiSiteStatus,
        staleTime: 60_000,
    });

    const roleMut = useMutation({
        mutationFn: (params: { role: string; primary_shop_url?: string; primary_shop_id?: string }) =>
            setMultiSiteRole(params),
        onSuccess: () => {
            queryClient.invalidateQueries({ queryKey: ['remote-sync'] });
            toast.success('Multi-site role updated');
        },
        onError: () => toast.error('Failed to update role'),
    });

    if (isLoading) return <PageSpinner />;
    if (!status) return null;

    return (
        <Card>
            <CardHeader
                title="Multi-Site Deployment"
                subtitle="Configure this shop as part of a multi-location network"
            />
            <div className="space-y-4">
                {/* Current Role */}
                <div className="flex items-center justify-between">
                    <div>
                        <p className="text-sm font-medium text-gray-900 dark:text-gray-100">
                            Current Role
                        </p>
                        <p className="text-xs text-gray-500 dark:text-gray-400">
                            {status.role === 'standalone'
                                ? 'Single independent shop'
                                : status.role === 'primary'
                                    ? 'Primary hub — secondaries sync to this shop'
                                    : 'Secondary — syncs data from primary shop'}
                        </p>
                    </div>
                    <Badge variant={
                        status.role === 'primary' ? 'success'
                            : status.role === 'secondary' ? 'warning'
                                : 'secondary'
                    }>
                        {status.role}
                    </Badge>
                </div>

                {/* Role Buttons */}
                <div className="flex flex-wrap gap-2">
                    {(['standalone', 'primary', 'secondary'] as const).map(role => (
                        <Button
                            key={role}
                            size="sm"
                            variant={status.role === role ? 'primary' : 'secondary'}
                            onClick={() => roleMut.mutate({ role })}
                            disabled={roleMut.isPending || status.role === role}
                        >
                            {role === 'standalone' ? 'Standalone' : role === 'primary' ? 'Primary Hub' : 'Secondary'}
                        </Button>
                    ))}
                </div>

                {/* Primary Shop URL (if secondary) */}
                {status.role === 'secondary' && (
                    <div className="p-3 bg-yellow-50 dark:bg-yellow-900/20 rounded-lg space-y-1">
                        <p className="text-xs font-medium text-yellow-700 dark:text-yellow-400">
                            Primary Shop Connection
                        </p>
                        <p className="text-xs text-yellow-600 dark:text-yellow-500 font-mono">
                            {status.primary_shop_url ?? 'Not configured'}
                        </p>
                        <p className="text-xs text-yellow-600 dark:text-yellow-500">
                            Sync interval: {status.sync_interval_minutes} min
                        </p>
                    </div>
                )}

                {/* Cluster Nodes */}
                {status.cluster_nodes.length > 0 && (
                    <div>
                        <p className="text-xs font-medium text-gray-700 dark:text-gray-300 mb-2">
                            Cluster Nodes ({status.cluster_nodes.length})
                        </p>
                        <div className="space-y-1">
                            {status.cluster_nodes.map((node: any, i: number) => (
                                <div
                                    key={i}
                                    className="text-xs bg-gray-50 dark:bg-gray-800/50 rounded p-2 flex items-center justify-between"
                                >
                                    <span className="font-mono text-gray-700 dark:text-gray-300">
                                        {node.node_url || node.node_id || `Node ${i + 1}`}
                                    </span>
                                    <Badge variant={node.is_online ? 'success' : 'secondary'}>
                                        {node.is_online ? 'Online' : 'Offline'}
                                    </Badge>
                                </div>
                            ))}
                        </div>
                    </div>
                )}

                {/* Multi-site peers */}
                {status.multi_site_peers.length > 0 && (
                    <div>
                        <p className="text-xs font-medium text-gray-700 dark:text-gray-300 mb-2">
                            Multi-Site Peers ({status.multi_site_peers.length})
                        </p>
                        <div className="space-y-1">
                            {status.multi_site_peers.map(p => (
                                <div
                                    key={p.peer_id}
                                    className="text-xs bg-gray-50 dark:bg-gray-800/50 rounded p-2 flex items-center justify-between"
                                >
                                    <span className="text-gray-700 dark:text-gray-300">
                                        {p.peer_name}
                                    </span>
                                    <Badge variant={p.is_active ? 'success' : 'secondary'}>
                                        {p.is_active ? 'Active' : 'Inactive'}
                                    </Badge>
                                </div>
                            ))}
                        </div>
                    </div>
                )}
            </div>
        </Card>
    );
}


// ── 5. File-Based Sync ──────────────────────────────────────────

function FileSyncCard() {
    const queryClient = useQueryClient();
    const [showExport, setShowExport] = useState(false);
    const [passphrase, setPassphrase] = useState('');
    const [keyHint, setKeyHint] = useState('');
    const [expiresDays, setExpiresDays] = useState('7');

    const { data: packages = [], isLoading } = useQuery<FileSyncPackage[]>({
        queryKey: ['remote-sync', 'file-sync', 'packages'],
        queryFn: () => listFileSyncPackages(),
        staleTime: 30_000,
    });

    const exportMut = useMutation({
        mutationFn: () => exportFileSyncPackage({
            passphrase: passphrase || undefined,
            key_hint: keyHint || undefined,
            expires_days: parseInt(expiresDays) || 7,
        }),
        onSuccess: (pkg) => {
            queryClient.invalidateQueries({ queryKey: ['remote-sync', 'file-sync'] });
            toast.success(`Package exported: ${pkg.file_name}`);
            setShowExport(false);
            setPassphrase('');
            setKeyHint('');
        },
        onError: () => toast.error('Export failed'),
    });

    return (
        <Card>
            <CardHeader
                title="File-Based Sync (USB / Sneakernet)"
                subtitle="Export data packages for offline transfer between shops"
                action={
                    <Button size="sm" onClick={() => setShowExport(!showExport)}>
                        <Upload className="h-4 w-4 mr-1" />
                        <span className="hidden sm:inline">Export</span>
                    </Button>
                }
            />

            {/* Export Form */}
            {showExport && (
                <div className="mb-4 p-3 bg-gray-50 dark:bg-gray-800/50 rounded-lg space-y-3">
                    <p className="text-xs text-gray-500 dark:text-gray-400">
                        Creates an encrypted, compressed package of all sync data.
                        Transfer via USB drive to the target shop and import there.
                    </p>
                    <div className="grid grid-cols-1 sm:grid-cols-3 gap-2">
                        <input
                            type="password"
                            value={passphrase}
                            onChange={(e) => setPassphrase(e.target.value)}
                            placeholder="Encryption passphrase (optional)"
                            className="px-3 py-2 text-sm border border-gray-300 dark:border-gray-600 rounded-md bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100"
                        />
                        <input
                            value={keyHint}
                            onChange={(e) => setKeyHint(e.target.value)}
                            placeholder="Key hint (optional)"
                            className="px-3 py-2 text-sm border border-gray-300 dark:border-gray-600 rounded-md bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100"
                        />
                        <input
                            value={expiresDays}
                            onChange={(e) => setExpiresDays(e.target.value)}
                            placeholder="Expires in days"
                            type="number"
                            className="px-3 py-2 text-sm border border-gray-300 dark:border-gray-600 rounded-md bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100"
                        />
                    </div>
                    <div className="flex gap-2">
                        <Button
                            size="sm"
                            onClick={() => exportMut.mutate()}
                            disabled={exportMut.isPending}
                        >
                            {exportMut.isPending ? <RefreshCw className="h-4 w-4 animate-spin" /> : 'Create Package'}
                        </Button>
                        <Button size="sm" variant="secondary" onClick={() => setShowExport(false)}>
                            Cancel
                        </Button>
                    </div>
                </div>
            )}

            {/* Package List */}
            {isLoading ? (
                <PageSpinner />
            ) : packages.length === 0 ? (
                <EmptyState icon={HardDrive} title="No sync packages" />
            ) : (
                <div className="overflow-x-auto">
                    <table className="w-full text-xs">
                        <thead>
                            <tr className="border-b border-gray-200 dark:border-gray-700 text-gray-500 dark:text-gray-400">
                                <th className="text-left py-2 px-2">File</th>
                                <th className="text-left py-2 px-2 hidden sm:table-cell">Type</th>
                                <th className="text-right py-2 px-2">Records</th>
                                <th className="text-right py-2 px-2 hidden sm:table-cell">Size</th>
                                <th className="text-left py-2 px-2">Status</th>
                                <th className="text-left py-2 px-2 hidden md:table-cell">Created</th>
                            </tr>
                        </thead>
                        <tbody>
                            {packages.map(pkg => (
                                <tr key={pkg.package_id} className="border-b border-gray-100 dark:border-gray-800">
                                    <td className="py-2 px-2 font-mono text-gray-700 dark:text-gray-300 truncate max-w-[150px]">
                                        {pkg.file_name}
                                    </td>
                                    <td className="py-2 px-2 hidden sm:table-cell">
                                        <Badge variant={pkg.direction === 'export' ? 'info' : 'success'}>
                                            {pkg.direction}
                                        </Badge>
                                    </td>
                                    <td className="py-2 px-2 text-right text-gray-700 dark:text-gray-300">
                                        {pkg.record_count.toLocaleString()}
                                    </td>
                                    <td className="py-2 px-2 text-right text-gray-500 dark:text-gray-400 hidden sm:table-cell">
                                        {formatBytes(pkg.file_size_bytes)}
                                    </td>
                                    <td className="py-2 px-2">
                                        <Badge variant={
                                            pkg.status === 'completed' ? 'success'
                                                : pkg.status === 'failed' ? 'danger'
                                                    : pkg.status === 'expired' ? 'secondary'
                                                        : 'warning'
                                        }>
                                            {pkg.status}
                                        </Badge>
                                    </td>
                                    <td className="py-2 px-2 text-gray-500 dark:text-gray-400 hidden md:table-cell">
                                        {new Date(pkg.created_at).toLocaleDateString()}
                                    </td>
                                </tr>
                            ))}
                        </tbody>
                    </table>
                </div>
            )}
        </Card>
    );
}


// ── 6. Fail2Ban ─────────────────────────────────────────────────

function FailBanCard() {
    const queryClient = useQueryClient();

    const { data: entries = [], isLoading } = useQuery<FailbanEntry[]>({
        queryKey: ['remote-sync', 'failban'],
        queryFn: listFailban,
        staleTime: 30_000,
    });

    const clearMut = useMutation({
        mutationFn: (ip?: string) => clearFailban(ip),
        onSuccess: (result) => {
            queryClient.invalidateQueries({ queryKey: ['remote-sync', 'failban'] });
            toast.success(`Cleared ${result.cleared} entries`);
        },
        onError: () => toast.error('Failed to clear'),
    });

    return (
        <Card>
            <CardHeader
                title="Fail2Ban — Blocked IPs"
                subtitle="IPs blocked due to authentication failures"
                action={
                    entries.length > 0 ? (
                        <Button
                            size="sm"
                            variant="danger"
                            onClick={() => clearMut.mutate(undefined)}
                            disabled={clearMut.isPending}
                        >
                            <Trash2 className="h-4 w-4 mr-1" />
                            <span className="hidden sm:inline">Clear All</span>
                        </Button>
                    ) : undefined
                }
            />

            {isLoading ? (
                <PageSpinner />
            ) : entries.length === 0 ? (
                <EmptyState icon={Shield} title="No blocked IPs" />
            ) : (
                <div className="space-y-2">
                    {entries.map(entry => {
                        const isLocked = entry.locked_until && new Date(entry.locked_until) > new Date();
                        return (
                            <div
                                key={entry.id}
                                className="flex items-center justify-between p-2 bg-gray-50 dark:bg-gray-800/50 rounded-lg"
                            >
                                <div className="flex items-center gap-3">
                                    <Ban className={`h-4 w-4 ${isLocked ? 'text-red-500' : 'text-yellow-500'}`} />
                                    <div>
                                        <p className="text-sm font-mono text-gray-900 dark:text-gray-100">
                                            {entry.ip_address}
                                        </p>
                                        <p className="text-xs text-gray-500 dark:text-gray-400">
                                            {entry.failure_count} failures • Last: {new Date(entry.last_failure).toLocaleString()}
                                        </p>
                                    </div>
                                </div>
                                <div className="flex items-center gap-2">
                                    <Badge variant={isLocked ? 'danger' : 'warning'}>
                                        {isLocked ? 'Locked' : 'Warning'}
                                    </Badge>
                                    <Button
                                        size="sm"
                                        variant="ghost"
                                        onClick={() => clearMut.mutate(entry.ip_address)}
                                    >
                                        <Trash2 className="h-3 w-3" />
                                    </Button>
                                </div>
                            </div>
                        );
                    })}
                </div>
            )}
        </Card>
    );
}


// ── 7. Session History ──────────────────────────────────────────

function SessionHistoryCard() {
    const [limit, setLimit] = useState(20);

    const { data: sessions = [], isLoading } = useQuery<RemoteSyncSession[]>({
        queryKey: ['remote-sync', 'sessions', limit],
        queryFn: () => listSessions({ limit }),
        staleTime: 30_000,
    });

    return (
        <Card>
            <CardHeader
                title="Session History"
                subtitle="Recent remote sync sessions"
                action={
                    <Button size="sm" variant="ghost" onClick={() => setLimit(l => l + 20)}>
                        Load More
                    </Button>
                }
            />

            {isLoading ? (
                <PageSpinner />
            ) : sessions.length === 0 ? (
                <EmptyState icon={Clock} title="No remote sync sessions yet" />
            ) : (
                <div className="overflow-x-auto">
                    <table className="w-full text-xs">
                        <thead>
                            <tr className="border-b border-gray-200 dark:border-gray-700 text-gray-500 dark:text-gray-400">
                                <th className="text-left py-2 px-2">Type</th>
                                <th className="text-left py-2 px-2 hidden sm:table-cell">Transport</th>
                                <th className="text-left py-2 px-2">Status</th>
                                <th className="text-right py-2 px-2 hidden sm:table-cell">↑ Sent</th>
                                <th className="text-right py-2 px-2 hidden sm:table-cell">↓ Recv</th>
                                <th className="text-right py-2 px-2 hidden md:table-cell">Duration</th>
                                <th className="text-left py-2 px-2">Started</th>
                            </tr>
                        </thead>
                        <tbody>
                            {sessions.map(s => (
                                <tr key={s.session_id} className="border-b border-gray-100 dark:border-gray-800">
                                    <td className="py-2 px-2 text-gray-700 dark:text-gray-300">
                                        {s.session_type.replace(/_/g, ' ')}
                                    </td>
                                    <td className="py-2 px-2 hidden sm:table-cell">
                                        <Badge variant="secondary">{s.transport}</Badge>
                                    </td>
                                    <td className="py-2 px-2">
                                        <Badge variant={
                                            s.status === 'completed' ? 'success'
                                                : s.status === 'failed' ? 'danger'
                                                    : s.status === 'in_progress' ? 'info'
                                                        : 'secondary'
                                        }>
                                            {s.status}
                                        </Badge>
                                    </td>
                                    <td className="py-2 px-2 text-right text-gray-700 dark:text-gray-300 hidden sm:table-cell">
                                        {s.changes_sent}
                                    </td>
                                    <td className="py-2 px-2 text-right text-gray-700 dark:text-gray-300 hidden sm:table-cell">
                                        {s.changes_received}
                                    </td>
                                    <td className="py-2 px-2 text-right text-gray-500 dark:text-gray-400 hidden md:table-cell">
                                        {s.duration_ms ? `${(s.duration_ms / 1000).toFixed(1)}s` : '—'}
                                    </td>
                                    <td className="py-2 px-2 text-gray-500 dark:text-gray-400">
                                        {new Date(s.started_at).toLocaleString()}
                                    </td>
                                </tr>
                            ))}
                        </tbody>
                    </table>
                </div>
            )}
        </Card>
    );
}


// ── Helper Components ───────────────────────────────────────────

function FieldRow({ label, helpText, children }: {
    label: string;
    helpText?: string;
    children: React.ReactNode;
}) {
    return (
        <div className="flex flex-col sm:flex-row sm:items-center gap-1 sm:gap-4">
            <div className="sm:w-48 flex-shrink-0">
                <p className="text-sm font-medium text-gray-900 dark:text-gray-100">{label}</p>
                {helpText && (
                    <p className="text-xs text-gray-500 dark:text-gray-400">{helpText}</p>
                )}
            </div>
            <div className="flex-1">{children}</div>
        </div>
    );
}

function EditableField({ value, placeholder, onSave }: {
    value: string;
    placeholder?: string;
    onSave: (v: string) => void;
}) {
    const [editing, setEditing] = useState(false);
    const [draft, setDraft] = useState(value);

    if (!editing) {
        return (
            <button
                onClick={() => { setDraft(value); setEditing(true); }}
                className="text-sm text-gray-700 dark:text-gray-300 hover:text-primary-500 text-left font-mono truncate max-w-full"
            >
                {value || <span className="text-gray-400 italic">{placeholder || 'Click to set'}</span>}
            </button>
        );
    }

    return (
        <div className="flex gap-2">
            <input
                autoFocus
                value={draft}
                onChange={(e) => setDraft(e.target.value)}
                placeholder={placeholder}
                className="flex-1 px-2 py-1 text-sm border border-gray-300 dark:border-gray-600 rounded bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 font-mono"
                onKeyDown={(e) => {
                    if (e.key === 'Enter') { onSave(draft); setEditing(false); }
                    if (e.key === 'Escape') setEditing(false);
                }}
            />
            <Button size="sm" onClick={() => { onSave(draft); setEditing(false); }}>
                <CheckCircle className="h-3 w-3" />
            </Button>
            <Button size="sm" variant="ghost" onClick={() => setEditing(false)}>
                <XCircle className="h-3 w-3" />
            </Button>
        </div>
    );
}

function formatBytes(bytes: number): string {
    if (bytes === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return `${(bytes / Math.pow(k, i)).toFixed(1)} ${sizes[i]}`;
}
