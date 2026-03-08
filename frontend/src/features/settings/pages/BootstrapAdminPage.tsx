import { useMemo, useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import {
    Rocket, KeyRound, Package, Activity,
    RefreshCw, Copy, CheckCircle, AlertTriangle,
} from 'lucide-react';
import { Badge } from '../../../components/ui/Badge';
import { Button } from '../../../components/ui/Button';
import { EmptyState } from '../../../components/ui/EmptyState';
import { PageSpinner } from '../../../components/ui/Spinner';
import {
    bootstrapHandshake,
    createPairingCode,
    listBootstrapArtifacts,
    listBootstrapInstallEvents,
    listPairingCodes,
    logBootstrapInstallEvent,
    type BootstrapPlatform,
    type InstallStatus,
    upsertBootstrapArtifact,
} from '../../../api/bootstrap';

const PLATFORM_OPTIONS: BootstrapPlatform[] = ['ios', 'android', 'windows', 'macos'];

export function BootstrapAdminPage() {
    return (
        <div className="space-y-6">
            <h2 className="text-xl font-bold text-gray-900 dark:text-gray-100 flex items-center gap-2">
                <Rocket className="h-5 w-5" />
                Mobile Bootstrap
            </h2>

            <PairingCodeManagementCard />
            <ArtifactManagementCard />
            <InstallTelemetryCard />
            <BootstrapClientFlowCard />
        </div>
    );
}

function PairingCodeManagementCard() {
    const queryClient = useQueryClient();
    const [ttlMinutes, setTtlMinutes] = useState(15);
    const [notes, setNotes] = useState('');
    const [latestCode, setLatestCode] = useState<string | null>(null);

    const { data: codes = [], isLoading } = useQuery({
        queryKey: ['bootstrap-pairing-codes'],
        queryFn: () => listPairingCodes(25),
    });

    const createMutation = useMutation({
        mutationFn: createPairingCode,
        onSuccess: (row) => {
            setLatestCode(row.code);
            queryClient.invalidateQueries({ queryKey: ['bootstrap-pairing-codes'] });
        },
    });

    async function copyCode(code: string) {
        try {
            await navigator.clipboard.writeText(code);
        } catch {
            // no-op fallback
        }
    }

    return (
        <div className="bg-surface border border-border rounded-lg p-4 space-y-4">
            <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100 flex items-center gap-2">
                <KeyRound className="h-4 w-4" />
                Pairing Code Management
            </h3>

            <div className="flex flex-wrap gap-2">
                <select
                    value={ttlMinutes}
                    onChange={(e) => setTtlMinutes(Number(e.target.value))}
                    className="min-h-11 px-3 py-2 text-sm border border-border rounded-md bg-surface text-gray-900 dark:text-gray-100"
                >
                    <option value={5}>5 min</option>
                    <option value={15}>15 min</option>
                    <option value={30}>30 min</option>
                    <option value={60}>60 min</option>
                    <option value={120}>120 min</option>
                </select>

                <input
                    value={notes}
                    onChange={(e) => setNotes(e.target.value)}
                    placeholder="Optional notes"
                    className="flex-1 min-w-[220px] min-h-11 px-3 py-2 text-sm border border-border rounded-md bg-surface text-gray-900 dark:text-gray-100"
                />

                <Button
                    size="sm"
                    onClick={() => createMutation.mutate({ ttl_minutes: ttlMinutes, notes: notes.trim() || undefined })}
                    isLoading={createMutation.isPending}
                >
                    Generate Code
                </Button>
            </div>

            {latestCode && (
                <div className="flex flex-wrap items-center gap-2 rounded-md border border-green-200 dark:border-green-800/40 bg-green-50 dark:bg-green-900/10 p-3">
                    <span className="text-sm text-green-700 dark:text-green-300">Latest code:</span>
                    <code className="font-mono text-sm font-semibold text-green-700 dark:text-green-300">{latestCode}</code>
                    <Button size="sm" variant="secondary" onClick={() => copyCode(latestCode)}>
                        <Copy className="h-4 w-4" />
                    </Button>
                </div>
            )}

            {isLoading ? (
                <PageSpinner label="Loading pairing codes..." />
            ) : codes.length === 0 ? (
                <p className="text-sm text-gray-500 dark:text-gray-400">No pairing codes generated yet.</p>
            ) : (
                <div className="overflow-x-auto">
                    <table className="w-full text-sm">
                        <thead>
                            <tr className="text-left text-xs text-gray-500 dark:text-gray-400 border-b border-border">
                                <th className="pb-2 pr-3">Code</th>
                                <th className="pb-2 pr-3">Status</th>
                                <th className="pb-2 pr-3">Created</th>
                                <th className="pb-2 pr-3">Expires</th>
                                <th className="pb-2">Device</th>
                            </tr>
                        </thead>
                        <tbody className="divide-y divide-border">
                            {codes.map((c) => {
                                const status = pairingStatus(c.used_at, c.expires_at);
                                return (
                                    <tr key={`${c.code}-${c.created_at}`}>
                                        <td className="py-1.5 pr-3 font-mono">{c.code}</td>
                                        <td className="py-1.5 pr-3"><Badge variant={status.variant}>{status.label}</Badge></td>
                                        <td className="py-1.5 pr-3 whitespace-nowrap">{formatDate(c.created_at)}</td>
                                        <td className="py-1.5 pr-3 whitespace-nowrap">{formatDate(c.expires_at)}</td>
                                        <td className="py-1.5">{c.device_name || c.device_id || '—'}</td>
                                    </tr>
                                );
                            })}
                        </tbody>
                    </table>
                </div>
            )}
        </div>
    );
}

function ArtifactManagementCard() {
    const queryClient = useQueryClient();
    const [platform, setPlatform] = useState<BootstrapPlatform>('android');
    const [version, setVersion] = useState('1.0.0');
    const [downloadUrl, setDownloadUrl] = useState('');
    const [checksum, setChecksum] = useState('');
    const [signature, setSignature] = useState('');
    const [minBootstrapVersion, setMinBootstrapVersion] = useState('0.0.0-bootstrap');
    const [manifestJson, setManifestJson] = useState('{\n  "bundle": "app.apk",\n  "size": 0\n}');

    const { data: artifacts = [], isLoading } = useQuery({
        queryKey: ['bootstrap-artifacts'],
        queryFn: () => listBootstrapArtifacts(undefined, 50),
    });

    const upsertMutation = useMutation({
        mutationFn: upsertBootstrapArtifact,
        onSuccess: () => {
            queryClient.invalidateQueries({ queryKey: ['bootstrap-artifacts'] });
        },
    });

    const activeByPlatform = useMemo(() => {
        const map: Record<string, string> = {};
        for (const a of artifacts) {
            if (a.is_active && !map[a.platform]) map[a.platform] = a.version;
        }
        return map;
    }, [artifacts]);

    function submitArtifact() {
        let parsedManifest: Record<string, any>;
        try {
            parsedManifest = JSON.parse(manifestJson || '{}');
        } catch {
            return;
        }

        upsertMutation.mutate({
            platform,
            version,
            manifest: parsedManifest,
            download_url: downloadUrl,
            checksum_sha256: checksum,
            signature: signature.trim() || undefined,
            min_bootstrap_version: minBootstrapVersion,
        });
    }

    return (
        <div className="bg-surface border border-border rounded-lg p-4 space-y-4">
            <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100 flex items-center gap-2">
                <Package className="h-4 w-4" />
                Artifact Upload & Activation
            </h3>

            <div className="flex flex-wrap gap-2">
                {PLATFORM_OPTIONS.map((p) => (
                    <Badge key={p} variant={activeByPlatform[p] ? 'success' : 'neutral'}>
                        {p}: {activeByPlatform[p] || 'none'}
                    </Badge>
                ))}
            </div>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                <select
                    value={platform}
                    onChange={(e) => setPlatform(e.target.value as BootstrapPlatform)}
                    className="min-h-11 px-3 py-2 text-sm border border-border rounded-md bg-surface text-gray-900 dark:text-gray-100"
                >
                    {PLATFORM_OPTIONS.map((p) => <option key={p} value={p}>{p}</option>)}
                </select>

                <input
                    value={version}
                    onChange={(e) => setVersion(e.target.value)}
                    placeholder="Artifact version"
                    className="min-h-11 px-3 py-2 text-sm border border-border rounded-md bg-surface text-gray-900 dark:text-gray-100"
                />

                <input
                    value={downloadUrl}
                    onChange={(e) => setDownloadUrl(e.target.value)}
                    placeholder="Download URL"
                    className="min-h-11 px-3 py-2 text-sm border border-border rounded-md bg-surface text-gray-900 dark:text-gray-100 md:col-span-2"
                />

                <input
                    value={checksum}
                    onChange={(e) => setChecksum(e.target.value)}
                    placeholder="SHA256 checksum"
                    className="min-h-11 px-3 py-2 text-sm border border-border rounded-md bg-surface text-gray-900 dark:text-gray-100"
                />

                <input
                    value={signature}
                    onChange={(e) => setSignature(e.target.value)}
                    placeholder="Optional signature"
                    className="min-h-11 px-3 py-2 text-sm border border-border rounded-md bg-surface text-gray-900 dark:text-gray-100"
                />

                <input
                    value={minBootstrapVersion}
                    onChange={(e) => setMinBootstrapVersion(e.target.value)}
                    placeholder="Min bootstrap version"
                    className="min-h-11 px-3 py-2 text-sm border border-border rounded-md bg-surface text-gray-900 dark:text-gray-100"
                />

                <Button
                    size="sm"
                    onClick={submitArtifact}
                    isLoading={upsertMutation.isPending}
                    disabled={!downloadUrl || !version || !checksum}
                >
                    Activate Artifact
                </Button>
            </div>

            <textarea
                value={manifestJson}
                onChange={(e) => setManifestJson(e.target.value)}
                rows={6}
                className="w-full px-3 py-2 text-sm border border-border rounded-md bg-surface text-gray-900 dark:text-gray-100 font-mono"
            />

            {upsertMutation.isError && (
                <p className="text-sm text-red-600 dark:text-red-400">Invalid manifest JSON or request failed.</p>
            )}

            {isLoading ? (
                <PageSpinner label="Loading artifacts..." />
            ) : artifacts.length === 0 ? (
                <p className="text-sm text-gray-500 dark:text-gray-400">No artifacts registered yet.</p>
            ) : (
                <div className="overflow-x-auto">
                    <table className="w-full text-sm">
                        <thead>
                            <tr className="text-left text-xs text-gray-500 dark:text-gray-400 border-b border-border">
                                <th className="pb-2 pr-3">Platform</th>
                                <th className="pb-2 pr-3">Version</th>
                                <th className="pb-2 pr-3">Active</th>
                                <th className="pb-2 pr-3">Created</th>
                                <th className="pb-2">URL</th>
                            </tr>
                        </thead>
                        <tbody className="divide-y divide-border">
                            {artifacts.map((a) => (
                                <tr key={a.id}>
                                    <td className="py-1.5 pr-3">{a.platform}</td>
                                    <td className="py-1.5 pr-3">{a.version}</td>
                                    <td className="py-1.5 pr-3">
                                        <Badge variant={a.is_active ? 'success' : 'neutral'}>{a.is_active ? 'active' : 'inactive'}</Badge>
                                    </td>
                                    <td className="py-1.5 pr-3 whitespace-nowrap">{formatDate(a.created_at)}</td>
                                    <td className="py-1.5 max-w-[260px] truncate">{a.download_url}</td>
                                </tr>
                            ))}
                        </tbody>
                    </table>
                </div>
            )}
        </div>
    );
}

function InstallTelemetryCard() {
    const [deviceFilter, setDeviceFilter] = useState('');
    const [limit, setLimit] = useState(100);

    const { data: events = [], isLoading, refetch, isFetching } = useQuery({
        queryKey: ['bootstrap-install-events', deviceFilter, limit],
        queryFn: () => listBootstrapInstallEvents(deviceFilter.trim() || undefined, limit),
    });

    return (
        <div className="bg-surface border border-border rounded-lg p-4 space-y-3">
            <div className="flex flex-wrap items-center justify-between gap-2">
                <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100 flex items-center gap-2">
                    <Activity className="h-4 w-4" />
                    Bootstrap Install Telemetry
                </h3>
                <Button size="sm" variant="ghost" onClick={() => refetch()}>
                    <RefreshCw className={`h-4 w-4 ${isFetching ? 'animate-spin' : ''}`} />
                </Button>
            </div>

            <div className="flex flex-wrap gap-2">
                <input
                    value={deviceFilter}
                    onChange={(e) => setDeviceFilter(e.target.value)}
                    placeholder="Filter by device_id"
                    className="flex-1 min-w-[220px] min-h-11 px-3 py-2 text-sm border border-border rounded-md bg-surface text-gray-900 dark:text-gray-100"
                />
                <select
                    value={limit}
                    onChange={(e) => setLimit(Number(e.target.value))}
                    className="min-h-11 px-3 py-2 text-sm border border-border rounded-md bg-surface text-gray-900 dark:text-gray-100"
                >
                    <option value={25}>25</option>
                    <option value={50}>50</option>
                    <option value={100}>100</option>
                    <option value={250}>250</option>
                </select>
            </div>

            {isLoading ? (
                <PageSpinner label="Loading install events..." />
            ) : events.length === 0 ? (
                <EmptyState
                    icon={Activity}
                    title="No install events"
                    description="Bootstrap install telemetry will appear as devices report progress."
                />
            ) : (
                <div className="overflow-x-auto">
                    <table className="w-full text-sm">
                        <thead>
                            <tr className="text-left text-xs text-gray-500 dark:text-gray-400 border-b border-border">
                                <th className="pb-2 pr-3">Time</th>
                                <th className="pb-2 pr-3">Device</th>
                                <th className="pb-2 pr-3">Platform</th>
                                <th className="pb-2 pr-3">Status</th>
                                <th className="pb-2">Error</th>
                            </tr>
                        </thead>
                        <tbody className="divide-y divide-border">
                            {events.map((e) => (
                                <tr key={e.id}>
                                    <td className="py-1.5 pr-3 whitespace-nowrap">{formatDate(e.created_at)}</td>
                                    <td className="py-1.5 pr-3 font-mono">{e.device_id}</td>
                                    <td className="py-1.5 pr-3">{e.platform}</td>
                                    <td className="py-1.5 pr-3"><Badge variant={statusVariant(e.status)}>{e.status}</Badge></td>
                                    <td className="py-1.5 max-w-[260px] truncate">{e.error_message || '—'}</td>
                                </tr>
                            ))}
                        </tbody>
                    </table>
                </div>
            )}
        </div>
    );
}

function BootstrapClientFlowCard() {
    const queryClient = useQueryClient();
    const [pairingCode, setPairingCode] = useState('');
    const [deviceId, setDeviceId] = useState('bootstrap-device-demo');
    const [deviceName, setDeviceName] = useState('Bootstrap Device');
    const [platform, setPlatform] = useState<BootstrapPlatform>('android');
    const [bootstrapVersion, setBootstrapVersion] = useState('0.0.0-bootstrap');
    const [publicKey, setPublicKey] = useState('');
    const [artifactId, setArtifactId] = useState<number | null>(null);

    const handshakeMutation = useMutation({
        mutationFn: bootstrapHandshake,
        onSuccess: (data) => {
            setArtifactId(data.artifact?.id ?? null);
        },
    });

    const eventMutation = useMutation({
        mutationFn: logBootstrapInstallEvent,
        onSuccess: () => {
            queryClient.invalidateQueries({ queryKey: ['bootstrap-install-events'] });
        },
    });

    function runHandshake() {
        handshakeMutation.mutate({
            pairing_code: pairingCode.trim(),
            device_id: deviceId.trim(),
            device_name: deviceName.trim() || 'Bootstrap Device',
            platform,
            bootstrap_version: bootstrapVersion.trim() || '0.0.0-bootstrap',
            public_key: publicKey.trim() || undefined,
        });
    }

    function logStatus(status: InstallStatus) {
        eventMutation.mutate({
            pairing_code: pairingCode.trim(),
            device_id: deviceId.trim(),
            platform,
            artifact_id: artifactId,
            status,
            metadata: {
                source: 'admin-simulator',
                bootstrap_version: bootstrapVersion,
            },
        });
    }

    return (
        <div className="bg-surface border border-border rounded-lg p-4 space-y-4">
            <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100 flex items-center gap-2">
                <Rocket className="h-4 w-4" />
                Bootstrap Client Flow (Simulator)
            </h3>

            <p className="text-sm text-gray-600 dark:text-gray-400">
                Simulates bootstrap app pairing + install progress reporting against live backend endpoints.
            </p>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                <input
                    value={pairingCode}
                    onChange={(e) => setPairingCode(e.target.value.toUpperCase())}
                    placeholder="Pairing code"
                    className="min-h-11 px-3 py-2 text-sm border border-border rounded-md bg-surface text-gray-900 dark:text-gray-100"
                />
                <select
                    value={platform}
                    onChange={(e) => setPlatform(e.target.value as BootstrapPlatform)}
                    className="min-h-11 px-3 py-2 text-sm border border-border rounded-md bg-surface text-gray-900 dark:text-gray-100"
                >
                    {PLATFORM_OPTIONS.map((p) => <option key={p} value={p}>{p}</option>)}
                </select>

                <input
                    value={deviceId}
                    onChange={(e) => setDeviceId(e.target.value)}
                    placeholder="Device ID"
                    className="min-h-11 px-3 py-2 text-sm border border-border rounded-md bg-surface text-gray-900 dark:text-gray-100"
                />
                <input
                    value={deviceName}
                    onChange={(e) => setDeviceName(e.target.value)}
                    placeholder="Device name"
                    className="min-h-11 px-3 py-2 text-sm border border-border rounded-md bg-surface text-gray-900 dark:text-gray-100"
                />

                <input
                    value={bootstrapVersion}
                    onChange={(e) => setBootstrapVersion(e.target.value)}
                    placeholder="Bootstrap version"
                    className="min-h-11 px-3 py-2 text-sm border border-border rounded-md bg-surface text-gray-900 dark:text-gray-100"
                />
                <input
                    value={publicKey}
                    onChange={(e) => setPublicKey(e.target.value)}
                    placeholder="Optional public key"
                    className="min-h-11 px-3 py-2 text-sm border border-border rounded-md bg-surface text-gray-900 dark:text-gray-100"
                />
            </div>

            <div className="flex flex-wrap gap-2">
                <Button size="sm" onClick={runHandshake} isLoading={handshakeMutation.isPending} disabled={!pairingCode || !deviceId}>
                    Run Handshake
                </Button>
                <Button size="sm" variant="secondary" onClick={() => logStatus('requested')} disabled={eventMutation.isPending || !pairingCode}>Requested</Button>
                <Button size="sm" variant="secondary" onClick={() => logStatus('downloaded')} disabled={eventMutation.isPending || !pairingCode}>Downloaded</Button>
                <Button size="sm" variant="secondary" onClick={() => logStatus('installed')} disabled={eventMutation.isPending || !pairingCode}>Installed</Button>
                <Button size="sm" variant="danger" onClick={() => logStatus('failed')} disabled={eventMutation.isPending || !pairingCode}>Failed</Button>
            </div>

            {handshakeMutation.data && (
                <div className="rounded-md border border-green-200 dark:border-green-800/40 bg-green-50 dark:bg-green-900/10 p-3 text-sm text-green-700 dark:text-green-300 space-y-1">
                    <div className="flex items-center gap-2"><CheckCircle className="h-4 w-4" /> Handshake successful</div>
                    <div>Artifact: {handshakeMutation.data.artifact ? `${handshakeMutation.data.artifact.platform} ${handshakeMutation.data.artifact.version}` : 'none active'}</div>
                    <div>Certificate: {handshakeMutation.data.certificate ? 'issued' : 'not issued'}</div>
                </div>
            )}

            {handshakeMutation.isError && (
                <div className="rounded-md border border-red-200 dark:border-red-800/40 bg-red-50 dark:bg-red-900/10 p-3 text-sm text-red-700 dark:text-red-300 flex items-center gap-2">
                    <AlertTriangle className="h-4 w-4" />
                    Handshake failed. Check code validity and platform/artifact setup.
                </div>
            )}

            {eventMutation.isSuccess && (
                <div className="text-sm text-blue-700 dark:text-blue-300">Install event recorded.</div>
            )}
        </div>
    );
}

function pairingStatus(usedAt: string | null, expiresAt: string): { label: string; variant: 'success' | 'warning' | 'danger' | 'neutral' } {
    if (usedAt) return { label: 'used', variant: 'success' };
    if (new Date(expiresAt) < new Date()) return { label: 'expired', variant: 'danger' };
    return { label: 'active', variant: 'warning' };
}

function statusVariant(status: InstallStatus): 'warning' | 'success' | 'danger' | 'info' {
    if (status === 'installed') return 'success';
    if (status === 'failed') return 'danger';
    if (status === 'downloaded') return 'info';
    return 'warning';
}

function formatDate(iso: string): string {
    try {
        return new Date(iso).toLocaleString();
    } catch {
        return iso;
    }
}
