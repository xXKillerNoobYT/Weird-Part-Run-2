/**
 * KeyManagementPage — Certificate & encryption key dashboard.
 *
 * Tabs:
 *   Company Keys   — company root key status, version, rotation
 *   Certificates   — per-device certificate list with expiry tracking
 *   Audit Log      — immutable security event log
 */

import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
    ShieldCheck, Key, RotateCcw, RefreshCw, Check, XCircle, Clock,
    AlertTriangle, ChevronDown, ChevronUp, FileKey, Shield, Eye,
    EyeOff, Copy, Smartphone,
} from 'lucide-react';
import { Card } from '../../../components/ui/Card';
import { Badge } from '../../../components/ui/Badge';
import { Button } from '../../../components/ui/Button';
import { Spinner } from '../../../components/ui/Spinner';
import { EmptyState } from '../../../components/ui/EmptyState';
import {
    listCompanies, getCompany, rotateCompanyKeys,
    revokeCertificate, getSecurityAuditLog,
} from '../../../api/security';
import type {
    SecurityAuditEvent,
} from '../../../api/security';
import { listDevices } from '../../../api/devices';
import type { DeviceSummary } from '../../../api/devices';
import { toast } from '../../../lib/toast';

// ── Helpers ──────────────────────────────────────────────────────

function relativeTime(isoStr: string | null): string {
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

function formatDate(isoStr: string | null): string {
    if (!isoStr) return '—';
    try {
        return new Date(isoStr + (isoStr.endsWith('Z') ? '' : 'Z')).toLocaleDateString([], {
            month: 'short', day: 'numeric', year: 'numeric',
        });
    } catch { return isoStr; }
}

function formatDateTime(isoStr: string | null): string {
    if (!isoStr) return '—';
    try {
        return new Date(isoStr + (isoStr.endsWith('Z') ? '' : 'Z')).toLocaleString([], {
            month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit',
        });
    } catch { return isoStr; }
}

function copyToClipboard(text: string) {
    navigator.clipboard.writeText(text).then(
        () => toast.success('Copied to clipboard'),
        () => toast.error('Failed to copy'),
    );
}


// ── Tab: Company Keys ────────────────────────────────────────────

function CompanyKeysTab() {
    const queryClient = useQueryClient();
    const [showKeys, setShowKeys] = useState(false);
    const [selectedCompanyId, setSelectedCompanyId] = useState<string | null>(null);
    const [confirmRotate, setConfirmRotate] = useState(false);

    const { data: companies, isLoading } = useQuery({
        queryKey: ['security-companies'],
        queryFn: listCompanies,
        staleTime: 60_000,
    });

    const { data: companyDetail } = useQuery({
        queryKey: ['security-company', selectedCompanyId],
        queryFn: () => selectedCompanyId ? getCompany(selectedCompanyId) : null,
        enabled: !!selectedCompanyId,
        staleTime: 30_000,
    });

    const rotateMutation = useMutation({
        mutationFn: rotateCompanyKeys,
        onSuccess: () => {
            setConfirmRotate(false);
            toast.success('Keys rotated. All device certificates have been revoked.');
            queryClient.invalidateQueries({ queryKey: ['security-companies'] });
            queryClient.invalidateQueries({ queryKey: ['security-company'] });
        },
        onError: () => toast.error('Key rotation failed'),
    });

    if (isLoading) return <div className="flex items-center justify-center py-16"><Spinner size="lg" /></div>;

    if (!companies || companies.length === 0) {
        return (
            <EmptyState icon={<Key className="h-12 w-12" />} title="No Company Initialized"
                description="The company encryption keys are created when the first sync is configured. Go to Sync settings to initialise." />
        );
    }

    // Auto-select first company if none selected
    if (!selectedCompanyId && companies.length > 0) {
        setSelectedCompanyId(companies[0].company_id);
        return null;
    }

    const company = companies.find(c => c.company_id === selectedCompanyId);

    return (
        <div className="space-y-4">
            {companies.length > 1 && (
                <select className="text-sm px-3 py-1.5 rounded-lg border border-border bg-surface text-gray-900 dark:text-gray-100"
                    value={selectedCompanyId ?? ''} onChange={(e) => setSelectedCompanyId(e.target.value)}>
                    {companies.map(c => <option key={c.company_id} value={c.company_id}>{c.company_name ?? c.company_id}</option>)}
                </select>
            )}

            {company && (
                <div className="border border-border rounded-xl bg-surface p-4 space-y-4">
                    <div className="flex items-center gap-3">
                        <div className="w-10 h-10 rounded-full bg-green-100 dark:bg-green-900/30 flex items-center justify-center">
                            <ShieldCheck className="h-5 w-5 text-green-600 dark:text-green-400" />
                        </div>
                        <div>
                            <h3 className="font-semibold text-gray-900 dark:text-gray-100">{company.company_name ?? company.company_id}</h3>
                            <p className="text-xs text-gray-500">
                                Key version: <strong>v{company.key_version}</strong> · Crypto: Ed25519 · Updated: {formatDate(company.updated_at)}
                            </p>
                        </div>
                    </div>

                    {/* Key display */}
                    {companyDetail && (
                        <div className="space-y-3">
                            <div className="flex items-center gap-2">
                                <h4 className="text-xs font-semibold text-gray-600 dark:text-gray-400 uppercase tracking-wide">Public Keys</h4>
                                <button onClick={() => setShowKeys(!showKeys)} className="text-xs text-primary-600 hover:text-primary-700 flex items-center gap-1">
                                    {showKeys ? <EyeOff className="h-3 w-3" /> : <Eye className="h-3 w-3" />}
                                    {showKeys ? 'Hide' : 'Show'}
                                </button>
                            </div>
                            {showKeys && (
                                <div className="space-y-2">
                                    <KeyField label="Root Public Key" value={companyDetail.root_key_public} />
                                    <KeyField label="Shop Node Public Key" value={companyDetail.shop_node_public} />
                                </div>
                            )}
                        </div>
                    )}

                    {/* Actions */}
                    <div className="space-y-2">
                        <h4 className="text-xs font-semibold text-gray-600 dark:text-gray-400 uppercase tracking-wide">Key Rotation</h4>
                        {!confirmRotate ? (
                            <Button size="sm" variant="warning" icon={<RotateCcw className="h-3.5 w-3.5" />}
                                onClick={() => setConfirmRotate(true)}>
                                Rotate Keys
                            </Button>
                        ) : (
                            <div className="p-3 rounded-lg bg-amber-50 dark:bg-amber-900/20 border border-amber-200 dark:border-amber-800 space-y-2">
                                <div className="flex items-start gap-2">
                                    <AlertTriangle className="h-4 w-4 text-amber-500 mt-0.5" />
                                    <div>
                                        <p className="text-sm font-medium text-amber-700 dark:text-amber-300">Rotate Company Keys?</p>
                                        <p className="text-xs text-amber-600 dark:text-amber-400 mt-0.5">
                                            This will generate new root and shop keys. <strong>All existing device certificates will be revoked.</strong> Devices must re-register on their next sync.
                                        </p>
                                    </div>
                                </div>
                                <div className="flex gap-2">
                                    <Button size="sm" variant="warning" isLoading={rotateMutation.isPending}
                                        onClick={() => selectedCompanyId && rotateMutation.mutate(selectedCompanyId)}>
                                        Confirm Rotation
                                    </Button>
                                    <Button size="sm" variant="secondary" onClick={() => setConfirmRotate(false)}>Cancel</Button>
                                </div>
                            </div>
                        )}
                    </div>
                </div>
            )}
        </div>
    );
}

function KeyField({ label, value }: { label: string; value: string }) {
    return (
        <div className="flex items-center gap-2">
            <div className="flex-1 min-w-0">
                <p className="text-[10px] text-gray-400 uppercase tracking-wide">{label}</p>
                <p className="text-xs font-mono text-gray-700 dark:text-gray-300 truncate">{value}</p>
            </div>
            <button onClick={() => copyToClipboard(value)} className="text-gray-400 hover:text-gray-600 p-1" title="Copy">
                <Copy className="h-3.5 w-3.5" />
            </button>
        </div>
    );
}


// ── Tab: Certificates ────────────────────────────────────────────

function CertificatesTab() {
    const queryClient = useQueryClient();
    const [expandedId, setExpandedId] = useState<string | null>(null);

    const { data: devices, isLoading, refetch, isFetching } = useQuery({
        queryKey: ['admin-devices-certs'],
        queryFn: () => listDevices(true),
        staleTime: 30_000,
    });

    const revokeMutation = useMutation({
        mutationFn: ({ deviceId, companyId }: { deviceId: string; companyId: string }) =>
            revokeCertificate({ device_id: deviceId, company_id: companyId, reason: 'Admin revoked from Key Management' }),
        onSuccess: () => {
            toast.success('Certificate revoked');
            queryClient.invalidateQueries({ queryKey: ['admin-devices-certs'] });
        },
        onError: () => toast.error('Revocation failed'),
    });

    if (isLoading) return <div className="flex items-center justify-center py-16"><Spinner size="lg" /></div>;

    if (!devices || devices.length === 0) {
        return (
            <EmptyState icon={<FileKey className="h-12 w-12" />} title="No Devices"
                description="Device certificates are issued when devices register. No devices have registered yet." />
        );
    }

    return (
        <div className="space-y-3">
            <div className="flex items-center justify-between">
                <p className="text-sm text-gray-500 dark:text-gray-400">
                    {devices.length} device{devices.length !== 1 ? 's' : ''}
                </p>
                <Button size="sm" variant="secondary"
                    icon={<RefreshCw className={`h-3.5 w-3.5 ${isFetching ? 'animate-spin' : ''}`} />}
                    onClick={() => refetch()}>
                    <span className="hidden sm:inline">Refresh</span>
                </Button>
            </div>

            {devices.map((device: DeviceSummary) => {
                const isExpanded = expandedId === device.device_id;
                // We don't have cert expiry directly on DeviceSummary, so we'll show device-level info
                // The full cert details would come from getDevice() if expanded

                return (
                    <div key={device.device_id} className="border border-border rounded-xl overflow-hidden bg-surface">
                        <button onClick={() => setExpandedId(isExpanded ? null : device.device_id)}
                            className="w-full flex items-center gap-3 px-4 py-3 text-left hover:bg-surface-secondary transition-colors">
                            <Smartphone className="h-4 w-4 text-gray-400 flex-shrink-0" />
                            <div className="flex-1 min-w-0">
                                <div className="flex items-center gap-2 flex-wrap">
                                    <span className="text-sm font-medium text-gray-900 dark:text-gray-100 truncate">
                                        {device.device_name || 'Unnamed Device'}
                                    </span>
                                    <span className="text-xs font-mono text-gray-500">{device.device_id.slice(0, 12)}…</span>
                                    <CertStatusBadge device={device} />
                                </div>
                                <p className="text-xs text-gray-500 dark:text-gray-400 mt-0.5">
                                    Platform: {device.platform || '—'} · Registered: {formatDate(device.registered_at)}
                                    {device.app_version && ` · App v${device.app_version}`}
                                </p>
                            </div>
                            {isExpanded ? <ChevronUp className="h-4 w-4 text-gray-400" /> : <ChevronDown className="h-4 w-4 text-gray-400" />}
                        </button>

                        {isExpanded && (
                            <div className="px-4 pb-4 pt-2 bg-surface-secondary border-t border-border space-y-3">
                                <div className="grid grid-cols-2 gap-3 text-xs">
                                    <div>
                                        <p className="text-gray-400 text-[10px] uppercase tracking-wide">Last Sync</p>
                                        <p className="text-gray-900 dark:text-gray-100 font-medium">{relativeTime(device.last_sync_at)}</p>
                                    </div>
                                    <div>
                                        <p className="text-gray-400 text-[10px] uppercase tracking-wide">Config Version</p>
                                        <p className="text-gray-900 dark:text-gray-100 font-medium">{device.config_version ?? '—'}</p>
                                    </div>
                                    <div>
                                        <p className="text-gray-400 text-[10px] uppercase tracking-wide">OS Version</p>
                                        <p className="text-gray-900 dark:text-gray-100 font-medium">{device.os_version ?? '—'}</p>
                                    </div>
                                    <div>
                                        <p className="text-gray-400 text-[10px] uppercase tracking-wide">Storage Policy</p>
                                        <p className="text-gray-900 dark:text-gray-100 font-medium">{device.storage_policy ?? 'default'}</p>
                                    </div>
                                </div>

                                <div className="flex gap-2">
                                    <Button size="sm" variant="danger" icon={<XCircle className="h-3.5 w-3.5" />}
                                        isLoading={revokeMutation.isPending}
                                        onClick={() => revokeMutation.mutate({ deviceId: device.device_id, companyId: 'default' })}>
                                        Revoke Certificate
                                    </Button>
                                </div>

                                <p className="text-xs text-gray-400">
                                    Revoking the certificate blocks this device from syncing. It will re-register with a new certificate on next connection attempt.
                                </p>
                            </div>
                        )}
                    </div>
                );
            })}
        </div>
    );
}

function CertStatusBadge({ device }: { device: DeviceSummary }) {
    // Since DeviceSummary doesn't have cert expiry, we use last_sync to infer health
    const lastSyncMs = device.last_sync_at
        ? Date.now() - new Date(device.last_sync_at + (device.last_sync_at.endsWith('Z') ? '' : 'Z')).getTime()
        : null;

    if (device.is_disabled) {
        return <Badge variant="danger"><span className="flex items-center gap-1"><XCircle className="h-3 w-3" /> Disabled</span></Badge>;
    }

    if (lastSyncMs && lastSyncMs < 60 * 60 * 1000) {
        return <Badge variant="success"><span className="flex items-center gap-1"><Check className="h-3 w-3" /> Active</span></Badge>;
    }

    if (lastSyncMs && lastSyncMs > 7 * 24 * 60 * 60 * 1000) {
        return <Badge variant="warning"><span className="flex items-center gap-1"><Clock className="h-3 w-3" /> Stale ({Math.floor(lastSyncMs / (24 * 60 * 60 * 1000))}d)</span></Badge>;
    }

    return <Badge variant="default"><span className="flex items-center gap-1"><Clock className="h-3 w-3" /> Idle</span></Badge>;
}


// ── Tab: Audit Log ───────────────────────────────────────────────

function AuditLogTab() {
    const [eventFilter, setEventFilter] = useState<string>('');

    const { data: events, isLoading, refetch, isFetching } = useQuery({
        queryKey: ['security-audit', eventFilter],
        queryFn: () => getSecurityAuditLog({ event_type: eventFilter || undefined, limit: 200 }),
        staleTime: 15_000,
    });

    if (isLoading) return <div className="flex items-center justify-center py-16"><Spinner size="lg" /></div>;

    const eventTypes = [...new Set((events ?? []).map(e => e.event_type))].sort();

    return (
        <div className="space-y-4">
            <div className="flex items-center gap-3 flex-wrap">
                <select className="text-sm px-3 py-1.5 rounded-lg border border-border bg-surface text-gray-900 dark:text-gray-100"
                    value={eventFilter} onChange={(e) => setEventFilter(e.target.value)}>
                    <option value="">All Events</option>
                    {eventTypes.map(et => <option key={et} value={et}>{et}</option>)}
                </select>
                <div className="ml-auto">
                    <Button size="sm" variant="secondary"
                        icon={<RefreshCw className={`h-3.5 w-3.5 ${isFetching ? 'animate-spin' : ''}`} />}
                        onClick={() => refetch()}>
                        <span className="hidden sm:inline">Refresh</span>
                    </Button>
                </div>
            </div>

            {(!events || events.length === 0) ? (
                <EmptyState icon={<Shield className="h-12 w-12" />} title="No Audit Events"
                    description="Security events (key rotations, certificate operations, etc.) are logged here." />
            ) : (
                <div className="space-y-1">
                    {events.map((evt: SecurityAuditEvent) => (
                        <AuditRow key={evt.id} event={evt} />
                    ))}
                </div>
            )}
        </div>
    );
}

function AuditRow({ event }: { event: SecurityAuditEvent }) {
    const [expanded, setExpanded] = useState(false);

    const icon = event.event_type.includes('revoke') || event.event_type.includes('deactivate')
        ? <XCircle className="h-3.5 w-3.5 text-red-500" />
        : event.event_type.includes('rotate') || event.event_type.includes('issue')
            ? <RotateCcw className="h-3.5 w-3.5 text-amber-500" />
            : <Shield className="h-3.5 w-3.5 text-blue-500" />;

    return (
        <div className="border border-border rounded-lg overflow-hidden">
            <button onClick={() => setExpanded(!expanded)}
                className="w-full flex items-center gap-2.5 px-3 py-2 text-left text-xs hover:bg-surface-secondary transition-colors bg-surface">
                {icon}
                <span className="font-medium text-gray-900 dark:text-gray-100">{event.event_type}</span>
                {event.device_id && <span className="font-mono text-gray-500">{event.device_id.slice(0, 8)}…</span>}
                <span className="ml-auto text-gray-400 flex-shrink-0">{relativeTime(event.recorded_at)}</span>
                {expanded ? <ChevronUp className="h-3 w-3 text-gray-400" /> : <ChevronDown className="h-3 w-3 text-gray-400" />}
            </button>
            {expanded && (
                <div className="px-3 pb-3 pt-1 bg-surface-secondary border-t border-border space-y-2">
                    <div className="grid grid-cols-2 gap-2 text-xs text-gray-500 dark:text-gray-400">
                        <div>Time: {formatDateTime(event.recorded_at)}</div>
                        {event.company_id && <div>Company: {event.company_id}</div>}
                        {event.actor_user_id && <div>User ID: {event.actor_user_id}</div>}
                        {event.ip_address && <div>IP: {event.ip_address}</div>}
                    </div>
                    {event.details && Object.keys(event.details).length > 0 && (
                        <pre className="text-xs bg-surface rounded-lg p-2 border border-border overflow-x-auto text-gray-600 dark:text-gray-400 whitespace-pre-wrap break-all max-h-32 overflow-y-auto">
                            {JSON.stringify(event.details, null, 2)}
                        </pre>
                    )}
                </div>
            )}
        </div>
    );
}


// ── Main Page ────────────────────────────────────────────────────

type Tab = 'keys' | 'certs' | 'audit';

const TABS: { id: Tab; label: string; icon: React.FC<{ className?: string }> }[] = [
    { id: 'keys', label: 'Company Keys', icon: Key },
    { id: 'certs', label: 'Certificates', icon: FileKey },
    { id: 'audit', label: 'Audit Log', icon: Shield },
];

export function KeyManagementPage() {
    const [tab, setTab] = useState<Tab>('keys');

    return (
        <div className="space-y-5">
            <div>
                <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-100">
                    Keys &amp; Certificates
                </h2>
                <p className="text-sm text-gray-500 dark:text-gray-400 mt-0.5">
                    Manage encryption keys, device certificates, and review the security audit trail.
                </p>
            </div>

            {/* Info banner */}
            <div className="flex items-start gap-3 p-3 rounded-xl bg-emerald-50 dark:bg-emerald-900/20 border border-emerald-200 dark:border-emerald-800">
                <ShieldCheck className="h-4 w-4 text-emerald-500 mt-0.5 flex-shrink-0" />
                <p className="text-sm text-emerald-700 dark:text-emerald-300">
                    All device communication uses <strong>Ed25519</strong> asymmetric cryptography.
                    Each device receives a signed certificate that proves its identity during sync and Bluetooth encounters.
                </p>
            </div>

            {/* Tab bar */}
            <div className="flex gap-1 overflow-x-auto bg-surface-secondary rounded-xl p-1 border border-border">
                {TABS.map(({ id, label, icon: Icon }) => (
                    <button key={id} onClick={() => setTab(id)}
                        className={`flex items-center gap-2 px-3 py-2 rounded-lg text-sm font-medium transition-colors whitespace-nowrap flex-1 justify-center ${tab === id
                            ? 'bg-surface text-gray-900 dark:text-gray-100 shadow-sm'
                            : 'text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-300'
                            }`}>
                        <Icon className="h-4 w-4" />
                        <span>{label}</span>
                    </button>
                ))}
            </div>

            <Card>
                <div className="p-1">
                    {tab === 'keys' && <CompanyKeysTab />}
                    {tab === 'certs' && <CertificatesTab />}
                    {tab === 'audit' && <AuditLogTab />}
                </div>
            </Card>
        </div>
    );
}
