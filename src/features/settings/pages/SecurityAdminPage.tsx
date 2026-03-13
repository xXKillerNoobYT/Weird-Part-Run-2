/**
 * SecurityAdminPage — Company key management, device certificates,
 * shared channels, and security audit log.
 *
 * Five card-sections:
 * 1. Company Setup — initialise or view the company key profile
 * 2. Device Certificates — view issued certs, revoke, issue new
 * 3. Cross-Company Sharing — create, manage, accept shared channels
 * 4. Key Rotation — rotate company keys (danger zone)
 * 5. Security Audit Log — immutable event trail
 */

import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
    Shield, ShieldCheck, ShieldAlert, ShieldX,
    Key, KeyRound, RotateCcw, ScrollText,
    Plus, RefreshCw, AlertTriangle,
    CheckCircle, XCircle, Smartphone,
    Link2, Link2Off, UserCheck, Clock,
} from 'lucide-react';
import { Badge } from '../../../components/ui/Badge';
import { Button } from '../../../components/ui/Button';
import { PageSpinner } from '../../../components/ui/Spinner';
import { EmptyState } from '../../../components/ui/EmptyState';
import {
    initCompany, getCompany, listCompanies, rotateCompanyKeys,
    getDeviceCert, revokeCertificate,
    getSecurityAuditLog,
    createSharedChannel, listSharedChannels, deactivateSharedChannel,
    acceptChannelInvitation,
    type CompanyKeySummary,
    type SecurityAuditEvent,
    type SharedChannel,
} from '../../../api/security';
import { listSyncDevices, type SyncDevice } from '../../../api/sync';


// ── Page Root ───────────────────────────────────────────────────

export function SecurityAdminPage() {
    return (
        <div className="space-y-6">
            <h2 className="text-xl font-bold text-gray-900 dark:text-gray-100 flex items-center gap-2">
                <Shield className="h-5 w-5" />
                Device Security
            </h2>

            <CompanySetupCard />
            <DeviceCertificatesCard />
            <SharedChannelsCard />
            <KeyRotationCard />
            <AuditLogCard />
        </div>
    );
}


// ── 1. Company Setup ────────────────────────────────────────────

function CompanySetupCard() {
    const queryClient = useQueryClient();
    const [companyId, setCompanyId] = useState('default');
    const [companyName, setCompanyName] = useState('My Company');

    const { data: companies = [], isLoading } = useQuery({
        queryKey: ['security-companies'],
        queryFn: listCompanies,
    });

    const initMutation = useMutation({
        mutationFn: () => initCompany(companyId, companyName),
        onSuccess: () => {
            queryClient.invalidateQueries({ queryKey: ['security-companies'] });
            queryClient.invalidateQueries({ queryKey: ['security-company'] });
        },
    });

    if (isLoading) return <PageSpinner />;

    return (
        <div className="bg-surface border border-border rounded-lg p-4 space-y-4">
            <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100 flex items-center gap-2">
                <Key className="h-4 w-4" />
                Company Key Setup
            </h3>

            {companies.length === 0 ? (
                <div className="space-y-3">
                    <p className="text-sm text-gray-500 dark:text-gray-400">
                        No company keys configured yet. Initialise your company to enable device certificate security.
                    </p>
                    <div className="flex flex-wrap gap-2">
                        <input
                            type="text"
                            value={companyId}
                            onChange={(e) => setCompanyId(e.target.value)}
                            placeholder="Company ID"
                            className="flex-1 min-w-[140px] px-3 py-2 text-sm border border-border rounded-md bg-surface text-gray-900 dark:text-gray-100"
                        />
                        <input
                            type="text"
                            value={companyName}
                            onChange={(e) => setCompanyName(e.target.value)}
                            placeholder="Company Name"
                            className="flex-1 min-w-[180px] px-3 py-2 text-sm border border-border rounded-md bg-surface text-gray-900 dark:text-gray-100"
                        />
                        <Button
                            size="sm"
                            onClick={() => initMutation.mutate()}
                            disabled={initMutation.isPending || !companyId.trim()}
                        >
                            {initMutation.isPending ? <RefreshCw className="h-4 w-4 animate-spin" /> : <Plus className="h-4 w-4" />}
                            <span className="hidden sm:inline ml-1">Initialise</span>
                        </Button>
                    </div>
                </div>
            ) : (
                <div className="space-y-2">
                    {companies.map((c) => (
                        <CompanyRow key={c.company_id} company={c} />
                    ))}
                </div>
            )}
        </div>
    );
}

function CompanyRow({ company }: { company: CompanyKeySummary }) {
    const [expanded, setExpanded] = useState(false);

    const { data: detail } = useQuery({
        queryKey: ['security-company', company.company_id],
        queryFn: () => getCompany(company.company_id),
        enabled: expanded,
    });

    return (
        <div className="border border-border rounded-md p-3 space-y-2">
            <div className="flex items-center justify-between">
                <div className="flex items-center gap-2">
                    <ShieldCheck className="h-4 w-4 text-green-600 dark:text-green-400" />
                    <span className="text-sm font-medium text-gray-900 dark:text-gray-100">{company.company_name}</span>
                    <Badge variant="neutral">{company.company_id}</Badge>
                    <Badge variant="info">v{company.key_version}</Badge>
                </div>
                <Button size="sm" variant="ghost" onClick={() => setExpanded(!expanded)}>
                    {expanded ? 'Hide' : 'Details'}
                </Button>
            </div>
            {expanded && detail && (
                <div className="text-xs text-gray-500 dark:text-gray-400 space-y-1 pl-6">
                    <p><strong>Root Public:</strong> <code className="text-xs break-all">{detail.root_key_public}</code></p>
                    <p><strong>Shop Public:</strong> <code className="text-xs break-all">{detail.shop_node_public}</code></p>
                    <p><strong>Key Version:</strong> {detail.key_version}</p>
                    <p><strong>Created:</strong> {new Date(detail.created_at).toLocaleString()}</p>
                    {detail.rotated_at && (
                        <p><strong>Last Rotated:</strong> {new Date(detail.rotated_at).toLocaleString()}</p>
                    )}
                </div>
            )}
        </div>
    );
}


// ── 2. Device Certificates ──────────────────────────────────────

function DeviceCertificatesCard() {
    const queryClient = useQueryClient();

    const { data: companies = [] } = useQuery({
        queryKey: ['security-companies'],
        queryFn: listCompanies,
    });

    const { data: devices = [], isLoading } = useQuery({
        queryKey: ['sync-devices'],
        queryFn: listSyncDevices,
    });

    const revokeMutation = useMutation({
        mutationFn: ({ deviceId, companyId }: { deviceId: string; companyId: string }) =>
            revokeCertificate({ device_id: deviceId, company_id: companyId, reason: 'manual_admin' }),
        onSuccess: () => {
            queryClient.invalidateQueries({ queryKey: ['device-certs'] });
            queryClient.invalidateQueries({ queryKey: ['security-audit'] });
        },
    });

    if (companies.length === 0) {
        return (
            <div className="bg-surface border border-border rounded-lg p-4">
                <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100 flex items-center gap-2 mb-2">
                    <ShieldCheck className="h-4 w-4" />
                    Device Certificates
                </h3>
                <p className="text-sm text-gray-500 dark:text-gray-400">
                    Initialise a company above to manage device certificates.
                </p>
            </div>
        );
    }

    if (isLoading) return <PageSpinner />;

    return (
        <div className="bg-surface border border-border rounded-lg p-4 space-y-3">
            <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100 flex items-center gap-2">
                <ShieldCheck className="h-4 w-4" />
                Device Certificates
            </h3>

            {devices.length === 0 ? (
                <EmptyState
                    icon={Smartphone}
                    title="No devices registered"
                    description="Devices will appear here after they complete bootstrap pairing."
                />
            ) : (
                <div className="space-y-2">
                    {devices.map((d) => (
                        <DeviceCertRow
                            key={d.device_id}
                            device={d}
                            companyId={companies[0].company_id}
                            onRevoke={(deviceId, companyId) => revokeMutation.mutate({ deviceId, companyId })}
                            revoking={revokeMutation.isPending}
                        />
                    ))}
                </div>
            )}
        </div>
    );
}

function DeviceCertRow({
    device,
    companyId,
    onRevoke,
    revoking,
}: {
    device: SyncDevice;
    companyId: string;
    onRevoke: (deviceId: string, companyId: string) => void;
    revoking: boolean;
}) {
    const { data: cert, isLoading } = useQuery({
        queryKey: ['device-certs', device.device_id, companyId],
        queryFn: () => getDeviceCert(device.device_id, companyId),
    });

    const isExpired = cert?.expires_at
        ? new Date(cert.expires_at) < new Date()
        : false;

    return (
        <div className="flex flex-wrap items-center justify-between gap-2 border border-border rounded-md p-3">
            <div className="flex items-center gap-2 min-w-0">
                <Smartphone className="h-4 w-4 shrink-0 text-gray-400" />
                <div className="min-w-0">
                    <p className="text-sm font-medium text-gray-900 dark:text-gray-100 truncate">
                        {device.device_name || device.device_id}
                    </p>
                    <p className="text-xs text-gray-500 dark:text-gray-400 truncate">
                        {device.platform} · {device.device_id}
                    </p>
                </div>
            </div>

            <div className="flex items-center gap-2">
                {isLoading ? (
                    <Badge variant="neutral">Loading…</Badge>
                ) : cert ? (
                    <>
                        {isExpired ? (
                            <Badge variant="danger">Expired</Badge>
                        ) : cert.revoked_at ? (
                            <Badge variant="danger">Revoked</Badge>
                        ) : (
                            <Badge variant="success">Active</Badge>
                        )}
                        <span className="text-xs text-gray-400">
                            expires {new Date(cert.expires_at).toLocaleDateString()}
                        </span>
                        {!cert.revoked_at && !isExpired && (
                            <Button
                                size="sm"
                                variant="ghost"
                                onClick={() => onRevoke(device.device_id, companyId)}
                                disabled={revoking}
                                title="Revoke certificate"
                            >
                                <ShieldX className="h-4 w-4 text-red-500" />
                            </Button>
                        )}
                    </>
                ) : (
                    <Badge variant="neutral">No cert</Badge>
                )}
            </div>
        </div>
    );
}


// ── 3. Shared Channels (Cross-Company) ──────────────────────────

function SharedChannelsCard() {
    const queryClient = useQueryClient();
    const [showCreate, setShowCreate] = useState(false);
    const [channelName, setChannelName] = useState('');
    const [partnerIds, setPartnerIds] = useState('');
    const [scope, setScope] = useState('');
    const [permissions, setPermissions] = useState('{"read": true, "write": false}');

    const { data: companies = [] } = useQuery({
        queryKey: ['security-companies'],
        queryFn: listCompanies,
    });

    const ownerCompanyId = companies[0]?.company_id ?? '';

    const { data: channels = [], isLoading } = useQuery({
        queryKey: ['shared-channels', ownerCompanyId],
        queryFn: () => listSharedChannels(ownerCompanyId),
        enabled: !!ownerCompanyId,
    });

    const createMutation = useMutation({
        mutationFn: () => {
            const partnerList = partnerIds.split(',').map(s => s.trim()).filter(Boolean);
            let scopeObj = {};
            let permsObj = { read: true, write: false };
            try { scopeObj = scope ? JSON.parse(scope) : {}; } catch { /* empty */ }
            try { permsObj = permissions ? JSON.parse(permissions) : permsObj; } catch { /* empty */ }
            return createSharedChannel({
                channel_name: channelName,
                owner_company_id: ownerCompanyId,
                partner_company_ids: partnerList,
                scope: scopeObj,
                permissions: permsObj,
            });
        },
        onSuccess: () => {
            queryClient.invalidateQueries({ queryKey: ['shared-channels'] });
            queryClient.invalidateQueries({ queryKey: ['security-audit'] });
            setShowCreate(false);
            setChannelName('');
            setPartnerIds('');
            setScope('');
        },
    });

    const deactivateMutation = useMutation({
        mutationFn: (channelId: number) => deactivateSharedChannel(channelId),
        onSuccess: () => {
            queryClient.invalidateQueries({ queryKey: ['shared-channels'] });
            queryClient.invalidateQueries({ queryKey: ['security-audit'] });
        },
    });

    const acceptMutation = useMutation({
        mutationFn: ({ channelId, companyId }: { channelId: number; companyId: string }) =>
            acceptChannelInvitation(channelId, companyId),
        onSuccess: () => {
            queryClient.invalidateQueries({ queryKey: ['shared-channels'] });
        },
    });

    if (companies.length === 0) {
        return (
            <div className="bg-surface border border-border rounded-lg p-4">
                <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100 flex items-center gap-2 mb-2">
                    <Link2 className="h-4 w-4" />
                    Cross-Company Sharing
                </h3>
                <p className="text-sm text-gray-500 dark:text-gray-400">
                    Initialise a company above to manage cross-company sharing channels.
                </p>
            </div>
        );
    }

    return (
        <div className="bg-surface border border-border rounded-lg p-4 space-y-3">
            <div className="flex flex-wrap items-center justify-between gap-2">
                <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100 flex items-center gap-2">
                    <Link2 className="h-4 w-4" />
                    Cross-Company Sharing
                </h3>
                <Button size="sm" variant="secondary" onClick={() => setShowCreate(!showCreate)}>
                    <Plus className="h-4 w-4 mr-1" />
                    <span className="hidden sm:inline">New Channel</span>
                </Button>
            </div>

            <p className="text-xs text-gray-500 dark:text-gray-400">
                Share scoped data with partner companies. Only supervisors/managers can create channels.
                Workers see shared data automatically.
            </p>

            {/* Create Form */}
            {showCreate && (
                <div className="space-y-2 border border-border rounded-md p-3 bg-gray-50 dark:bg-gray-800/50">
                    <input
                        type="text"
                        value={channelName}
                        onChange={(e) => setChannelName(e.target.value)}
                        placeholder="Channel name (e.g. 'Job 42 Shared Data')"
                        className="w-full px-3 py-2 text-sm border border-border rounded-md bg-surface text-gray-900 dark:text-gray-100"
                    />
                    <input
                        type="text"
                        value={partnerIds}
                        onChange={(e) => setPartnerIds(e.target.value)}
                        placeholder="Partner company IDs (comma-separated)"
                        className="w-full px-3 py-2 text-sm border border-border rounded-md bg-surface text-gray-900 dark:text-gray-100"
                    />
                    <input
                        type="text"
                        value={scope}
                        onChange={(e) => setScope(e.target.value)}
                        placeholder='Scope JSON (e.g. {"job_ids": [42]})'
                        className="w-full px-3 py-2 text-sm border border-border rounded-md bg-surface text-gray-900 dark:text-gray-100"
                    />
                    <input
                        type="text"
                        value={permissions}
                        onChange={(e) => setPermissions(e.target.value)}
                        placeholder='Permissions JSON'
                        className="w-full px-3 py-2 text-sm border border-border rounded-md bg-surface text-gray-900 dark:text-gray-100"
                    />
                    <div className="flex gap-2">
                        <Button
                            size="sm"
                            onClick={() => createMutation.mutate()}
                            disabled={createMutation.isPending || !channelName.trim()}
                        >
                            {createMutation.isPending ? <RefreshCw className="h-4 w-4 animate-spin" /> : <Plus className="h-4 w-4" />}
                            <span className="ml-1">Create Channel</span>
                        </Button>
                        <Button size="sm" variant="ghost" onClick={() => setShowCreate(false)}>
                            Cancel
                        </Button>
                    </div>
                </div>
            )}

            {/* Channel List */}
            {isLoading ? (
                <PageSpinner />
            ) : channels.length === 0 ? (
                <EmptyState
                    icon={Link2Off}
                    title="No shared channels"
                    description="Create a channel to share scoped data with a partner company."
                />
            ) : (
                <div className="space-y-2">
                    {channels.map((ch) => (
                        <ChannelRow
                            key={ch.id}
                            channel={ch}
                            myCompanyId={ownerCompanyId}
                            onDeactivate={(id) => deactivateMutation.mutate(id)}
                            onAccept={(id, cid) => acceptMutation.mutate({ channelId: id, companyId: cid })}
                            deactivating={deactivateMutation.isPending}
                        />
                    ))}
                </div>
            )}
        </div>
    );
}

function ChannelRow({
    channel,
    myCompanyId,
    onDeactivate,
    onAccept,
    deactivating,
}: {
    channel: SharedChannel;
    myCompanyId: string;
    onDeactivate: (id: number) => void;
    onAccept: (id: number, companyId: string) => void;
    deactivating: boolean;
}) {
    const [expanded, setExpanded] = useState(false);
    const members = channel.members ?? [];
    const isOwner = channel.owner_company_id === myCompanyId;
    const myMembership = members.find(m => m.company_id === myCompanyId);
    const isPending = myMembership && !myMembership.accepted_at && !isOwner;

    return (
        <div className="border border-border rounded-md p-3 space-y-2">
            <div className="flex flex-wrap items-center justify-between gap-2">
                <div className="flex items-center gap-2 min-w-0">
                    <Link2 className="h-4 w-4 shrink-0 text-purple-500" />
                    <span className="text-sm font-medium text-gray-900 dark:text-gray-100 truncate">
                        {channel.channel_name}
                    </span>
                    {isOwner && <Badge variant="info">Owner</Badge>}
                    {isPending && <Badge variant="warning">Pending</Badge>}
                    {channel.expires_at && (
                        <span className="text-xs text-gray-400 flex items-center gap-1">
                            <Clock className="h-3 w-3" />
                            expires {new Date(channel.expires_at).toLocaleDateString()}
                        </span>
                    )}
                </div>
                <div className="flex items-center gap-1">
                    {isPending && (
                        <Button
                            size="sm"
                            variant="secondary"
                            onClick={() => onAccept(channel.id, myCompanyId)}
                            title="Accept invitation"
                        >
                            <UserCheck className="h-4 w-4 text-green-500" />
                        </Button>
                    )}
                    {isOwner && (
                        <Button
                            size="sm"
                            variant="ghost"
                            onClick={() => onDeactivate(channel.id)}
                            disabled={deactivating}
                            title="Deactivate channel"
                        >
                            <Link2Off className="h-4 w-4 text-red-500" />
                        </Button>
                    )}
                    <Button size="sm" variant="ghost" onClick={() => setExpanded(!expanded)}>
                        {expanded ? 'Hide' : 'Details'}
                    </Button>
                </div>
            </div>

            {expanded && (
                <div className="text-xs text-gray-500 dark:text-gray-400 space-y-1 pl-6">
                    <p><strong>Channel ID:</strong> {channel.id}</p>
                    <p><strong>Owner:</strong> {channel.owner_company_id}</p>
                    {channel.scope && Object.keys(channel.scope).length > 0 && (
                        <p><strong>Scope:</strong> <code className="text-xs break-all">{JSON.stringify(channel.scope)}</code></p>
                    )}
                    {channel.permissions && Object.keys(channel.permissions).length > 0 && (
                        <p><strong>Permissions:</strong> <code className="text-xs break-all">{JSON.stringify(channel.permissions)}</code></p>
                    )}
                    <p><strong>Created:</strong> {new Date(channel.created_at).toLocaleString()}</p>
                    {members.length > 0 && (
                        <div className="mt-2">
                            <strong>Members:</strong>
                            <ul className="ml-4 mt-1 space-y-0.5">
                                {members.map((m) => (
                                    <li key={m.id} className="flex items-center gap-2">
                                        <span className="font-mono">{m.company_id}</span>
                                        <Badge variant={m.role === 'owner' ? 'info' : 'neutral'}>{m.role}</Badge>
                                        {m.accepted_at ? (
                                            <Badge variant="success">Accepted</Badge>
                                        ) : (
                                            <Badge variant="warning">Pending</Badge>
                                        )}
                                    </li>
                                ))}
                            </ul>
                        </div>
                    )}
                </div>
            )}
        </div>
    );
}


// ── 4. Key Rotation (Danger Zone) ───────────────────────────────

function KeyRotationCard() {
    const queryClient = useQueryClient();
    const [confirmId, setConfirmId] = useState<string | null>(null);

    const { data: companies = [] } = useQuery({
        queryKey: ['security-companies'],
        queryFn: listCompanies,
    });

    const rotateMutation = useMutation({
        mutationFn: rotateCompanyKeys,
        onSuccess: () => {
            setConfirmId(null);
            queryClient.invalidateQueries({ queryKey: ['security-companies'] });
            queryClient.invalidateQueries({ queryKey: ['security-company'] });
            queryClient.invalidateQueries({ queryKey: ['device-certs'] });
            queryClient.invalidateQueries({ queryKey: ['security-audit'] });
        },
    });

    if (companies.length === 0) return null;

    return (
        <div className="bg-surface border border-red-200 dark:border-red-800 rounded-lg p-4 space-y-3">
            <h3 className="text-sm font-semibold text-red-700 dark:text-red-400 flex items-center gap-2">
                <AlertTriangle className="h-4 w-4" />
                Key Rotation (Danger Zone)
            </h3>
            <p className="text-sm text-gray-500 dark:text-gray-400">
                Rotating keys generates new root + shop keypairs and <strong>revokes all device
                    certificates</strong>. Every device will need to re-pair to get a new certificate.
                Only do this if you suspect a key compromise.
            </p>

            {companies.map((c) => (
                <div key={c.company_id} className="flex flex-wrap items-center gap-2">
                    <span className="text-sm text-gray-700 dark:text-gray-300">{c.company_name}</span>
                    <Badge variant="neutral">v{c.key_version}</Badge>

                    {confirmId === c.company_id ? (
                        <>
                            <Button
                                size="sm"
                                variant="danger"
                                onClick={() => rotateMutation.mutate(c.company_id)}
                                disabled={rotateMutation.isPending}
                            >
                                {rotateMutation.isPending ? (
                                    <RefreshCw className="h-4 w-4 animate-spin" />
                                ) : (
                                    'Confirm Rotation'
                                )}
                            </Button>
                            <Button size="sm" variant="ghost" onClick={() => setConfirmId(null)}>
                                Cancel
                            </Button>
                        </>
                    ) : (
                        <Button
                            size="sm"
                            variant="secondary"
                            onClick={() => setConfirmId(c.company_id)}
                        >
                            <RotateCcw className="h-4 w-4 mr-1" />
                            <span className="hidden sm:inline">Rotate Keys</span>
                        </Button>
                    )}
                </div>
            ))}
        </div>
    );
}


// ── 5. Security Audit Log ───────────────────────────────────────

function AuditLogCard() {
    const [filterType, setFilterType] = useState<string>('');
    const [limit, setLimit] = useState(50);

    const { data: events = [], isLoading, refetch } = useQuery({
        queryKey: ['security-audit', filterType, limit],
        queryFn: () => getSecurityAuditLog({
            event_type: filterType || undefined,
            limit,
        }),
    });

    const eventTypes = [
        '', 'company_initialised', 'key_rotated',
        'cert_issued', 'cert_revoked', 'cert_expired',
        'handshake_failed', 'shared_channel_created',
    ];

    return (
        <div className="bg-surface border border-border rounded-lg p-4 space-y-3">
            <div className="flex flex-wrap items-center justify-between gap-2">
                <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100 flex items-center gap-2">
                    <ScrollText className="h-4 w-4" />
                    Security Audit Log
                </h3>
                <Button size="sm" variant="ghost" onClick={() => refetch()}>
                    <RefreshCw className="h-4 w-4" />
                </Button>
            </div>

            {/* Filters */}
            <div className="flex flex-wrap gap-2">
                <select
                    value={filterType}
                    onChange={(e) => setFilterType(e.target.value)}
                    className="text-sm border border-border rounded-md px-2 py-1 bg-surface text-gray-900 dark:text-gray-100"
                >
                    {eventTypes.map((t) => (
                        <option key={t} value={t}>{t || 'All events'}</option>
                    ))}
                </select>
                <select
                    value={limit}
                    onChange={(e) => setLimit(Number(e.target.value))}
                    className="text-sm border border-border rounded-md px-2 py-1 bg-surface text-gray-900 dark:text-gray-100"
                >
                    <option value={25}>25</option>
                    <option value={50}>50</option>
                    <option value={100}>100</option>
                    <option value={250}>250</option>
                </select>
            </div>

            {isLoading ? (
                <PageSpinner />
            ) : events.length === 0 ? (
                <EmptyState
                    icon={Shield}
                    title="No audit events"
                    description="Security events will be logged here as devices pair and sync."
                />
            ) : (
                <div className="overflow-x-auto">
                    <table className="w-full text-sm">
                        <thead>
                            <tr className="text-left text-xs text-gray-500 dark:text-gray-400 border-b border-border">
                                <th className="pb-2 pr-3">Time</th>
                                <th className="pb-2 pr-3">Event</th>
                                <th className="pb-2 pr-3">Device</th>
                                <th className="pb-2 pr-3">Company</th>
                                <th className="pb-2">Details</th>
                            </tr>
                        </thead>
                        <tbody className="divide-y divide-border">
                            {events.map((e) => (
                                <AuditRow key={e.id} event={e} />
                            ))}
                        </tbody>
                    </table>
                </div>
            )}
        </div>
    );
}

function AuditRow({ event }: { event: SecurityAuditEvent }) {
    const iconMap: Record<string, typeof CheckCircle> = {
        company_initialised: Key,
        key_rotated: RotateCcw,
        cert_issued: ShieldCheck,
        cert_revoked: ShieldX,
        cert_expired: ShieldAlert,
        handshake_failed: XCircle,
        shared_channel_created: KeyRound,
    };
    const Icon = iconMap[event.event_type] || ScrollText;

    const colorMap: Record<string, string> = {
        company_initialised: 'text-blue-500',
        key_rotated: 'text-amber-500',
        cert_issued: 'text-green-500',
        cert_revoked: 'text-red-500',
        cert_expired: 'text-orange-500',
        handshake_failed: 'text-red-600',
        shared_channel_created: 'text-purple-500',
    };
    const color = colorMap[event.event_type] || 'text-gray-400';

    return (
        <tr className="text-gray-700 dark:text-gray-300">
            <td className="py-2 pr-3 text-xs whitespace-nowrap text-gray-500 dark:text-gray-400">
                {new Date(event.recorded_at).toLocaleString()}
            </td>
            <td className="py-2 pr-3">
                <span className={`flex items-center gap-1 ${color}`}>
                    <Icon className="h-3.5 w-3.5" />
                    <span className="text-xs font-medium">{event.event_type}</span>
                </span>
            </td>
            <td className="py-2 pr-3 text-xs font-mono truncate max-w-[120px]">
                {event.device_id || '—'}
            </td>
            <td className="py-2 pr-3 text-xs truncate max-w-[100px]">
                {event.company_id || '—'}
            </td>
            <td className="py-2 text-xs text-gray-500 dark:text-gray-400 max-w-[200px] truncate">
                {Object.keys(event.details).length > 0
                    ? JSON.stringify(event.details)
                    : '—'}
            </td>
        </tr>
    );
}
