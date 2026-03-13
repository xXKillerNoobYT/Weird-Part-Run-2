/**
 * SharedChannelsPage — Cross-company data sharing with scope enforcement,
 * redaction rules, and full audit trail.
 *
 * Card sections:
 * 1. Channel List — overview of all shared channels, create new
 * 2. Channel Detail (selected) — scope, members, permissions, renew, revoke
 * 3. Redaction Rules — per-channel field-level redaction management
 * 4. Data Exchange Log — audit trail of records exchanged per channel
 * 5. Channel Statistics — aggregate exchange stats
 */

import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
    Share2, Plus, Shield, ShieldCheck, ShieldOff,
    Eye, Trash2, RefreshCw, Clock, AlertTriangle,
    CheckCircle, XCircle, ArrowUpRight, ArrowDownLeft,
    Lock, Hash, Scissors, Replace, Users, ScrollText,
    ChevronLeft,
} from 'lucide-react';
import { Badge } from '../../../components/ui/Badge';
import { Button } from '../../../components/ui/Button';
import { Card, CardHeader } from '../../../components/ui/Card';
import { PageSpinner } from '../../../components/ui/Spinner';
import { EmptyState } from '../../../components/ui/EmptyState';
import { toast } from '../../../lib/toast';
import {
    listSharedChannels, getSharedChannel, createSharedChannel,
    updateSharedChannel, renewSharedChannel, revokeSharedChannel,
    addRedactionRule, listRedactionRules, removeRedactionRule,
    getChannelDataLog, getChannelStats,
    type SharedChannelEnhanced, type RedactionRule,
    type SharedDataLogEntry, type ChannelStats,
} from '../../../api/remote-sync';


// ── Page Root ───────────────────────────────────────────────────

export function SharedChannelsPage() {
    const [selectedId, setSelectedId] = useState<number | null>(null);

    return (
        <div className="space-y-6">
            <h2 className="text-xl font-bold text-gray-900 dark:text-gray-100 flex items-center gap-2">
                <Share2 className="h-5 w-5" />
                Shared Channels
            </h2>

            {selectedId === null ? (
                <ChannelListCard onSelect={setSelectedId} />
            ) : (
                <>
                    <Button
                        size="sm"
                        variant="ghost"
                        onClick={() => setSelectedId(null)}
                        className="mb-2"
                    >
                        <ChevronLeft className="h-4 w-4 mr-1" /> Back to Channels
                    </Button>
                    <ChannelDetailCard channelId={selectedId} />
                    <RedactionRulesCard channelId={selectedId} />
                    <DataExchangeLogCard channelId={selectedId} />
                    <ChannelStatsCard channelId={selectedId} />
                </>
            )}
        </div>
    );
}


// ── 1. Channel List ─────────────────────────────────────────────

function ChannelListCard({ onSelect }: { onSelect: (id: number) => void }) {
    const queryClient = useQueryClient();
    const [showCreate, setShowCreate] = useState(false);
    const [newName, setNewName] = useState('');
    const [newOwner, setNewOwner] = useState('');
    const [newDesc, setNewDesc] = useState('');
    const [newExpireDays, setNewExpireDays] = useState('90');

    const { data: channels = [], isLoading } = useQuery<SharedChannelEnhanced[]>({
        queryKey: ['shared-channels', 'list'],
        queryFn: () => listSharedChannels({ include_inactive: true }),
        staleTime: 30_000,
    });

    const createMut = useMutation({
        mutationFn: () => createSharedChannel({
            channel_name: newName,
            owner_company_id: newOwner,
            description: newDesc || undefined,
            auto_expire_days: parseInt(newExpireDays) || 90,
        }),
        onSuccess: (ch) => {
            queryClient.invalidateQueries({ queryKey: ['shared-channels'] });
            toast.success(`Channel "${ch.channel_name}" created`);
            setShowCreate(false);
            setNewName('');
            setNewOwner('');
            setNewDesc('');
        },
        onError: () => toast.error('Failed to create channel'),
    });

    return (
        <Card>
            <CardHeader
                title="Shared Channels"
                subtitle="Cross-company data sharing with scope enforcement and redaction"
                action={
                    <Button size="sm" onClick={() => setShowCreate(!showCreate)}>
                        <Plus className="h-4 w-4 mr-1" />
                        <span className="hidden sm:inline">New Channel</span>
                    </Button>
                }
            />

            {/* Create Form */}
            {showCreate && (
                <div className="mb-4 p-3 bg-gray-50 dark:bg-gray-800/50 rounded-lg space-y-3">
                    <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
                        <input
                            value={newName}
                            onChange={(e) => setNewName(e.target.value)}
                            placeholder="Channel name"
                            className="px-3 py-2 text-sm border border-gray-300 dark:border-gray-600 rounded-md bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100"
                        />
                        <input
                            value={newOwner}
                            onChange={(e) => setNewOwner(e.target.value)}
                            placeholder="Owner company ID"
                            className="px-3 py-2 text-sm border border-gray-300 dark:border-gray-600 rounded-md bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100"
                        />
                    </div>
                    <input
                        value={newDesc}
                        onChange={(e) => setNewDesc(e.target.value)}
                        placeholder="Description (optional)"
                        className="w-full px-3 py-2 text-sm border border-gray-300 dark:border-gray-600 rounded-md bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100"
                    />
                    <div className="flex flex-wrap items-center gap-3">
                        <label className="text-xs text-gray-500 dark:text-gray-400">
                            Auto-expire (days):
                            <input
                                type="number"
                                value={newExpireDays}
                                onChange={(e) => setNewExpireDays(e.target.value)}
                                className="ml-2 w-20 px-2 py-1 text-sm border border-gray-300 dark:border-gray-600 rounded bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100"
                            />
                        </label>
                    </div>
                    <div className="flex gap-2">
                        <Button
                            size="sm"
                            onClick={() => createMut.mutate()}
                            disabled={!newName || !newOwner || createMut.isPending}
                        >
                            {createMut.isPending ? <RefreshCw className="h-4 w-4 animate-spin" /> : 'Create'}
                        </Button>
                        <Button size="sm" variant="secondary" onClick={() => setShowCreate(false)}>
                            Cancel
                        </Button>
                    </div>
                </div>
            )}

            {/* Channel List */}
            {isLoading ? (
                <PageSpinner />
            ) : channels.length === 0 ? (
                <EmptyState icon={Share2} title="No shared channels yet" />
            ) : (
                <div className="space-y-2">
                    {channels.map(ch => (
                        <ChannelRow key={ch.id} channel={ch} onSelect={() => onSelect(ch.id)} />
                    ))}
                </div>
            )}
        </Card>
    );
}

function ChannelRow({ channel, onSelect }: { channel: SharedChannelEnhanced; onSelect: () => void }) {
    const isActive = !!channel.is_active && !channel.revoked_at;
    const isExpired = channel.expires_at && new Date(channel.expires_at) < new Date();
    const statusVariant = !isActive ? 'danger' : isExpired ? 'warning' : 'success';
    const statusLabel = channel.revoked_at ? 'Revoked' : !isActive ? 'Inactive' : isExpired ? 'Expired' : 'Active';

    return (
        <button
            onClick={onSelect}
            className="w-full text-left p-3 bg-gray-50 dark:bg-gray-800/50 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-700/50 transition-colors space-y-1"
        >
            <div className="flex items-center justify-between gap-2">
                <div className="flex items-center gap-2 min-w-0">
                    <ShieldCheck className={`h-4 w-4 flex-shrink-0 ${isActive && !isExpired ? 'text-green-500' : 'text-gray-400'}`} />
                    <span className="text-sm font-medium text-gray-900 dark:text-gray-100 truncate">
                        {channel.channel_name}
                    </span>
                </div>
                <div className="flex items-center gap-2 flex-shrink-0">
                    <Badge variant={statusVariant}>{statusLabel}</Badge>
                    <Badge variant="secondary">{channel.members?.length ?? 0} members</Badge>
                </div>
            </div>
            {channel.description && (
                <p className="text-xs text-gray-500 dark:text-gray-400 truncate">
                    {channel.description}
                </p>
            )}
            <div className="flex flex-wrap gap-3 text-xs text-gray-500 dark:text-gray-400">
                <span>Owner: {channel.owner_company_id}</span>
                {channel.expires_at && (
                    <span>Expires: {new Date(channel.expires_at).toLocaleDateString()}</span>
                )}
                {channel.auto_expire_days && (
                    <span>Auto-expire: {channel.auto_expire_days}d</span>
                )}
            </div>
        </button>
    );
}


// ── 2. Channel Detail ───────────────────────────────────────────

function ChannelDetailCard({ channelId }: { channelId: number }) {
    const queryClient = useQueryClient();
    const [editDesc, setEditDesc] = useState<string | null>(null);
    const [editScope, setEditScope] = useState<string | null>(null);
    const [revokeReason, setRevokeReason] = useState('');
    const [showRevoke, setShowRevoke] = useState(false);

    const { data: channel, isLoading } = useQuery<SharedChannelEnhanced | null>({
        queryKey: ['shared-channels', channelId],
        queryFn: () => getSharedChannel(channelId),
        staleTime: 30_000,
    });

    const updateMut = useMutation({
        mutationFn: (fields: Record<string, unknown>) => updateSharedChannel(channelId, fields),
        onSuccess: () => {
            queryClient.invalidateQueries({ queryKey: ['shared-channels'] });
            toast.success('Channel updated');
            setEditDesc(null);
            setEditScope(null);
        },
        onError: () => toast.error('Failed to update channel'),
    });

    const renewMut = useMutation({
        mutationFn: () => renewSharedChannel(channelId),
        onSuccess: () => {
            queryClient.invalidateQueries({ queryKey: ['shared-channels'] });
            toast.success('Channel renewed');
        },
        onError: () => toast.error('Failed to renew'),
    });

    const revokeMut = useMutation({
        mutationFn: () => revokeSharedChannel(channelId, revokeReason || undefined),
        onSuccess: () => {
            queryClient.invalidateQueries({ queryKey: ['shared-channels'] });
            toast.success('Channel revoked');
            setShowRevoke(false);
        },
        onError: () => toast.error('Failed to revoke'),
    });

    if (isLoading) return <PageSpinner />;
    if (!channel) return <EmptyState icon={Share2} title="Channel not found" />;

    const isActive = !!channel.is_active && !channel.revoked_at;
    const isExpired = channel.expires_at ? new Date(channel.expires_at) < new Date() : false;

    return (
        <Card>
            <CardHeader
                title={channel.channel_name}
                subtitle={channel.description || 'No description'}
                action={
                    <div className="flex gap-2">
                        {isActive && (
                            <Button size="sm" onClick={() => renewMut.mutate()} disabled={renewMut.isPending}>
                                <RefreshCw className="h-3 w-3 mr-1" /> Renew
                            </Button>
                        )}
                        {isActive && (
                            <Button
                                size="sm"
                                variant="danger"
                                onClick={() => setShowRevoke(!showRevoke)}
                            >
                                <ShieldOff className="h-3 w-3 mr-1" /> Revoke
                            </Button>
                        )}
                    </div>
                }
            />

            {/* Status Banner */}
            {channel.revoked_at && (
                <div className="mb-4 p-3 bg-red-50 dark:bg-red-900/20 rounded-lg flex items-center gap-2">
                    <AlertTriangle className="h-4 w-4 text-red-500" />
                    <div className="text-sm text-red-700 dark:text-red-400">
                        <strong>Revoked</strong> on {new Date(channel.revoked_at).toLocaleDateString()}
                        {channel.revoke_reason && <span> — {channel.revoke_reason}</span>}
                    </div>
                </div>
            )}

            {isExpired && !channel.revoked_at && (
                <div className="mb-4 p-3 bg-yellow-50 dark:bg-yellow-900/20 rounded-lg flex items-center gap-2">
                    <Clock className="h-4 w-4 text-yellow-500" />
                    <span className="text-sm text-yellow-700 dark:text-yellow-400">
                        Channel expired on {new Date(channel.expires_at!).toLocaleDateString()}. Renew to reactivate.
                    </span>
                </div>
            )}

            {/* Revoke Form */}
            {showRevoke && (
                <div className="mb-4 p-3 bg-red-50 dark:bg-red-900/20 rounded-lg space-y-2">
                    <p className="text-sm text-red-700 dark:text-red-400 font-medium">
                        Revoke this channel? This immediately stops all data sharing.
                    </p>
                    <input
                        value={revokeReason}
                        onChange={(e) => setRevokeReason(e.target.value)}
                        placeholder="Reason for revocation (optional)"
                        className="w-full px-3 py-2 text-sm border border-red-300 dark:border-red-600 rounded-md bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100"
                    />
                    <div className="flex gap-2">
                        <Button
                            size="sm"
                            variant="danger"
                            onClick={() => revokeMut.mutate()}
                            disabled={revokeMut.isPending}
                        >
                            {revokeMut.isPending ? <RefreshCw className="h-4 w-4 animate-spin" /> : 'Confirm Revoke'}
                        </Button>
                        <Button size="sm" variant="secondary" onClick={() => setShowRevoke(false)}>
                            Cancel
                        </Button>
                    </div>
                </div>
            )}

            <div className="space-y-4">
                {/* Info Grid */}
                <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
                    <InfoItem label="Status">
                        <Badge variant={channel.revoked_at ? 'danger' : !isActive ? 'secondary' : isExpired ? 'warning' : 'success'}>
                            {channel.revoked_at ? 'Revoked' : !isActive ? 'Inactive' : isExpired ? 'Expired' : 'Active'}
                        </Badge>
                    </InfoItem>
                    <InfoItem label="Owner">
                        <span className="text-sm font-mono">{channel.owner_company_id}</span>
                    </InfoItem>
                    <InfoItem label="Auto-Expire">
                        <span className="text-sm">{channel.auto_expire_days ? `${channel.auto_expire_days} days` : 'None'}</span>
                    </InfoItem>
                    <InfoItem label="Last Renewed">
                        <span className="text-sm">
                            {channel.last_renewed_at ? new Date(channel.last_renewed_at).toLocaleDateString() : 'Never'}
                        </span>
                    </InfoItem>
                </div>

                {/* Description (editable) */}
                <div>
                    <p className="text-xs font-medium text-gray-500 dark:text-gray-400 mb-1">Description</p>
                    {editDesc !== null ? (
                        <div className="flex gap-2">
                            <input
                                autoFocus
                                value={editDesc}
                                onChange={(e) => setEditDesc(e.target.value)}
                                className="flex-1 px-3 py-1.5 text-sm border border-gray-300 dark:border-gray-600 rounded bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100"
                            />
                            <Button size="sm" onClick={() => updateMut.mutate({ description: editDesc })}>Save</Button>
                            <Button size="sm" variant="ghost" onClick={() => setEditDesc(null)}>Cancel</Button>
                        </div>
                    ) : (
                        <button
                            onClick={() => setEditDesc(channel.description ?? '')}
                            className="text-sm text-gray-700 dark:text-gray-300 hover:text-primary-500"
                        >
                            {channel.description || <span className="italic text-gray-400">Click to add description</span>}
                        </button>
                    )}
                </div>

                {/* Scope (editable as JSON) */}
                <div>
                    <p className="text-xs font-medium text-gray-500 dark:text-gray-400 mb-1">
                        Scope (JSON)
                    </p>
                    {editScope !== null ? (
                        <div className="space-y-2">
                            <textarea
                                autoFocus
                                value={editScope}
                                onChange={(e) => setEditScope(e.target.value)}
                                rows={4}
                                className="w-full px-3 py-2 text-xs font-mono border border-gray-300 dark:border-gray-600 rounded bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100"
                            />
                            <div className="flex gap-2">
                                <Button
                                    size="sm"
                                    onClick={() => {
                                        try {
                                            const parsed = JSON.parse(editScope);
                                            updateMut.mutate({ scope: parsed });
                                        } catch {
                                            toast.error('Invalid JSON');
                                        }
                                    }}
                                >
                                    Save Scope
                                </Button>
                                <Button size="sm" variant="ghost" onClick={() => setEditScope(null)}>Cancel</Button>
                            </div>
                        </div>
                    ) : (
                        <button
                            onClick={() => setEditScope(JSON.stringify(channel.scope ?? {}, null, 2))}
                            className="w-full text-left"
                        >
                            <pre className="text-xs font-mono bg-gray-50 dark:bg-gray-800/50 rounded p-2 text-gray-700 dark:text-gray-300 overflow-x-auto">
                                {JSON.stringify(channel.scope ?? {}, null, 2)}
                            </pre>
                        </button>
                    )}
                </div>

                {/* Permissions */}
                <div>
                    <p className="text-xs font-medium text-gray-500 dark:text-gray-400 mb-1">Permissions</p>
                    <pre className="text-xs font-mono bg-gray-50 dark:bg-gray-800/50 rounded p-2 text-gray-700 dark:text-gray-300 overflow-x-auto">
                        {JSON.stringify(channel.permissions ?? {}, null, 2)}
                    </pre>
                </div>

                {/* Members */}
                <div>
                    <p className="text-xs font-medium text-gray-500 dark:text-gray-400 mb-2 flex items-center gap-1">
                        <Users className="h-3 w-3" /> Members ({channel.members?.length ?? 0})
                    </p>
                    {(!channel.members || channel.members.length === 0) ? (
                        <p className="text-xs text-gray-400 italic">No members</p>
                    ) : (
                        <div className="space-y-1">
                            {channel.members.map(m => (
                                <div
                                    key={m.id}
                                    className="flex items-center justify-between p-2 bg-gray-50 dark:bg-gray-800/50 rounded text-xs"
                                >
                                    <div className="flex items-center gap-2">
                                        <span className="font-mono text-gray-700 dark:text-gray-300">
                                            {m.company_id}
                                        </span>
                                        <Badge variant="secondary">{m.role}</Badge>
                                        {m.accepted_at && (
                                            <Badge variant="success">
                                                <CheckCircle className="h-3 w-3 mr-0.5" /> Accepted
                                            </Badge>
                                        )}
                                    </div>
                                    <div className="flex gap-3 text-gray-500 dark:text-gray-400">
                                        <span>↑ {m.data_sent_count}</span>
                                        <span>↓ {m.data_received_count}</span>
                                        {m.last_sync_at && (
                                            <span>Last: {new Date(m.last_sync_at).toLocaleDateString()}</span>
                                        )}
                                    </div>
                                </div>
                            ))}
                        </div>
                    )}
                </div>
            </div>
        </Card>
    );
}


// ── 3. Redaction Rules ──────────────────────────────────────────

function RedactionRulesCard({ channelId }: { channelId: number }) {
    const queryClient = useQueryClient();
    const [showAdd, setShowAdd] = useState(false);
    const [newTable, setNewTable] = useState('');
    const [newField, setNewField] = useState('');
    const [newType, setNewType] = useState<string>('remove');
    const [newReplace, setNewReplace] = useState('');

    const { data: rules = [], isLoading } = useQuery<RedactionRule[]>({
        queryKey: ['shared-channels', channelId, 'redactions'],
        queryFn: () => listRedactionRules(channelId),
        staleTime: 30_000,
    });

    const addMut = useMutation({
        mutationFn: () => addRedactionRule(channelId, {
            table_name: newTable,
            field_name: newField,
            redaction_type: newType,
            replacement_value: newType === 'replace' ? newReplace : undefined,
        }),
        onSuccess: () => {
            queryClient.invalidateQueries({ queryKey: ['shared-channels', channelId, 'redactions'] });
            toast.success('Redaction rule added');
            setShowAdd(false);
            setNewTable('');
            setNewField('');
        },
        onError: () => toast.error('Failed to add rule'),
    });

    const removeMut = useMutation({
        mutationFn: (ruleId: number) => removeRedactionRule(channelId, ruleId),
        onSuccess: () => {
            queryClient.invalidateQueries({ queryKey: ['shared-channels', channelId, 'redactions'] });
            toast.success('Rule removed');
        },
        onError: () => toast.error('Failed to remove rule'),
    });

    const redactionIcon = (type: string) => {
        switch (type) {
            case 'remove': return <XCircle className="h-3 w-3 text-red-500" />;
            case 'mask': return <Eye className="h-3 w-3 text-yellow-500" />;
            case 'hash': return <Hash className="h-3 w-3 text-blue-500" />;
            case 'truncate': return <Scissors className="h-3 w-3 text-orange-500" />;
            case 'replace': return <Replace className="h-3 w-3 text-purple-500" />;
            default: return <Lock className="h-3 w-3 text-gray-500" />;
        }
    };

    return (
        <Card>
            <CardHeader
                title="Redaction Rules"
                subtitle="Fields that are stripped or masked before sharing with partners"
                action={
                    <Button size="sm" onClick={() => setShowAdd(!showAdd)}>
                        <Plus className="h-4 w-4 mr-1" />
                        <span className="hidden sm:inline">Add Rule</span>
                    </Button>
                }
            />

            {/* Add Form */}
            {showAdd && (
                <div className="mb-4 p-3 bg-gray-50 dark:bg-gray-800/50 rounded-lg space-y-3">
                    <div className="grid grid-cols-1 sm:grid-cols-3 gap-2">
                        <input
                            value={newTable}
                            onChange={(e) => setNewTable(e.target.value)}
                            placeholder="Table name (e.g. employees)"
                            className="px-3 py-2 text-sm border border-gray-300 dark:border-gray-600 rounded-md bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100"
                        />
                        <input
                            value={newField}
                            onChange={(e) => setNewField(e.target.value)}
                            placeholder="Field name (e.g. hourly_rate)"
                            className="px-3 py-2 text-sm border border-gray-300 dark:border-gray-600 rounded-md bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100"
                        />
                        <select
                            value={newType}
                            onChange={(e) => setNewType(e.target.value)}
                            className="px-3 py-2 text-sm border border-gray-300 dark:border-gray-600 rounded-md bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100"
                        >
                            <option value="remove">Remove (strip field entirely)</option>
                            <option value="mask">Mask (replace with ***)</option>
                            <option value="hash">Hash (SHA-256 prefix)</option>
                            <option value="truncate">Truncate (first 3 chars)</option>
                            <option value="replace">Replace (custom value)</option>
                        </select>
                    </div>
                    {newType === 'replace' && (
                        <input
                            value={newReplace}
                            onChange={(e) => setNewReplace(e.target.value)}
                            placeholder="Replacement value"
                            className="w-full px-3 py-2 text-sm border border-gray-300 dark:border-gray-600 rounded-md bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100"
                        />
                    )}
                    <div className="flex gap-2">
                        <Button
                            size="sm"
                            onClick={() => addMut.mutate()}
                            disabled={!newTable || !newField || addMut.isPending}
                        >
                            {addMut.isPending ? <RefreshCw className="h-4 w-4 animate-spin" /> : 'Add Rule'}
                        </Button>
                        <Button size="sm" variant="secondary" onClick={() => setShowAdd(false)}>
                            Cancel
                        </Button>
                    </div>
                </div>
            )}

            {/* Redaction info */}
            <div className="mb-3 p-2 bg-blue-50 dark:bg-blue-900/20 rounded-lg">
                <p className="text-xs text-blue-700 dark:text-blue-400">
                    <Shield className="h-3 w-3 inline mr-1" />
                    Sensitive fields (passwords, emails, rates) are <strong>always redacted</strong> automatically.
                    Add rules here for additional field-level control.
                </p>
            </div>

            {/* Rules List */}
            {isLoading ? (
                <PageSpinner />
            ) : rules.length === 0 ? (
                <EmptyState icon={Lock} title="No custom redaction rules — built-in safety net still active" />
            ) : (
                <div className="overflow-x-auto">
                    <table className="w-full text-xs">
                        <thead>
                            <tr className="border-b border-gray-200 dark:border-gray-700 text-gray-500 dark:text-gray-400">
                                <th className="text-left py-2 px-2">Table</th>
                                <th className="text-left py-2 px-2">Field</th>
                                <th className="text-left py-2 px-2">Type</th>
                                <th className="text-left py-2 px-2 hidden sm:table-cell">Replacement</th>
                                <th className="py-2 px-2 w-8"></th>
                            </tr>
                        </thead>
                        <tbody>
                            {rules.map(rule => (
                                <tr key={rule.id} className="border-b border-gray-100 dark:border-gray-800">
                                    <td className="py-2 px-2 font-mono text-gray-700 dark:text-gray-300">
                                        {rule.table_name}
                                    </td>
                                    <td className="py-2 px-2 font-mono text-gray-700 dark:text-gray-300">
                                        {rule.field_name}
                                    </td>
                                    <td className="py-2 px-2">
                                        <span className="flex items-center gap-1">
                                            {redactionIcon(rule.redaction_type)}
                                            {rule.redaction_type}
                                        </span>
                                    </td>
                                    <td className="py-2 px-2 text-gray-500 dark:text-gray-400 hidden sm:table-cell">
                                        {rule.replacement_value || '—'}
                                    </td>
                                    <td className="py-2 px-2">
                                        <Button
                                            size="sm"
                                            variant="ghost"
                                            onClick={() => removeMut.mutate(rule.id)}
                                            disabled={removeMut.isPending}
                                        >
                                            <Trash2 className="h-3 w-3 text-red-500" />
                                        </Button>
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


// ── 4. Data Exchange Log ────────────────────────────────────────

function DataExchangeLogCard({ channelId }: { channelId: number }) {
    const [limit, setLimit] = useState(25);
    const [direction, setDirection] = useState<string | undefined>(undefined);

    const { data: logs = [], isLoading } = useQuery<SharedDataLogEntry[]>({
        queryKey: ['shared-channels', channelId, 'data-log', direction, limit],
        queryFn: () => getChannelDataLog(channelId, { direction, limit }),
        staleTime: 30_000,
    });

    return (
        <Card>
            <CardHeader
                title="Data Exchange Log"
                subtitle="Audit trail of records shared through this channel"
                action={
                    <div className="flex gap-2">
                        <select
                            value={direction ?? ''}
                            onChange={(e) => setDirection(e.target.value || undefined)}
                            className="px-2 py-1 text-xs border border-gray-300 dark:border-gray-600 rounded bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100"
                        >
                            <option value="">All</option>
                            <option value="outbound">Outbound</option>
                            <option value="inbound">Inbound</option>
                        </select>
                        <Button size="sm" variant="ghost" onClick={() => setLimit(l => l + 25)}>
                            More
                        </Button>
                    </div>
                }
            />

            {isLoading ? (
                <PageSpinner />
            ) : logs.length === 0 ? (
                <EmptyState icon={ScrollText} title="No data exchanges recorded" />
            ) : (
                <div className="overflow-x-auto">
                    <table className="w-full text-xs">
                        <thead>
                            <tr className="border-b border-gray-200 dark:border-gray-700 text-gray-500 dark:text-gray-400">
                                <th className="text-left py-2 px-2">Direction</th>
                                <th className="text-left py-2 px-2">Table</th>
                                <th className="text-left py-2 px-2 hidden sm:table-cell">Record</th>
                                <th className="text-left py-2 px-2 hidden sm:table-cell">Op</th>
                                <th className="text-left py-2 px-2 hidden md:table-cell">Redactions</th>
                                <th className="text-left py-2 px-2">Time</th>
                            </tr>
                        </thead>
                        <tbody>
                            {logs.map(entry => (
                                <tr key={entry.id} className="border-b border-gray-100 dark:border-gray-800">
                                    <td className="py-2 px-2">
                                        {entry.direction === 'outbound' ? (
                                            <span className="flex items-center gap-1 text-blue-600 dark:text-blue-400">
                                                <ArrowUpRight className="h-3 w-3" /> Out
                                            </span>
                                        ) : (
                                            <span className="flex items-center gap-1 text-green-600 dark:text-green-400">
                                                <ArrowDownLeft className="h-3 w-3" /> In
                                            </span>
                                        )}
                                    </td>
                                    <td className="py-2 px-2 font-mono text-gray-700 dark:text-gray-300">
                                        {entry.table_name}
                                    </td>
                                    <td className="py-2 px-2 text-gray-700 dark:text-gray-300 hidden sm:table-cell">
                                        #{entry.record_id}
                                    </td>
                                    <td className="py-2 px-2 hidden sm:table-cell">
                                        <Badge variant="secondary">{entry.operation}</Badge>
                                    </td>
                                    <td className="py-2 px-2 hidden md:table-cell">
                                        {entry.redactions_applied.length > 0 ? (
                                            <span className="text-yellow-600 dark:text-yellow-400">
                                                {entry.redactions_applied.length} fields
                                            </span>
                                        ) : (
                                            <span className="text-gray-400">none</span>
                                        )}
                                    </td>
                                    <td className="py-2 px-2 text-gray-500 dark:text-gray-400 whitespace-nowrap">
                                        {new Date(entry.synced_at).toLocaleString()}
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


// ── 5. Channel Statistics ───────────────────────────────────────

function ChannelStatsCard({ channelId }: { channelId: number }) {
    const { data: stats, isLoading } = useQuery<ChannelStats>({
        queryKey: ['shared-channels', channelId, 'stats'],
        queryFn: () => getChannelStats(channelId),
        staleTime: 60_000,
    });

    if (isLoading) return <PageSpinner />;
    if (!stats) return null;

    return (
        <Card>
            <CardHeader
                title="Exchange Statistics"
                subtitle="Aggregate data exchange activity for this channel"
            />
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                {/* Outbound */}
                <div className="p-4 bg-blue-50 dark:bg-blue-900/20 rounded-lg space-y-2">
                    <div className="flex items-center gap-2">
                        <ArrowUpRight className="h-4 w-4 text-blue-500" />
                        <p className="text-sm font-medium text-blue-700 dark:text-blue-400">Outbound</p>
                    </div>
                    <div className="grid grid-cols-2 gap-2 text-xs">
                        <div>
                            <p className="text-gray-500 dark:text-gray-400">Records</p>
                            <p className="text-lg font-bold text-gray-900 dark:text-gray-100">
                                {stats.outbound.record_count.toLocaleString()}
                            </p>
                        </div>
                        <div>
                            <p className="text-gray-500 dark:text-gray-400">Tables</p>
                            <p className="text-lg font-bold text-gray-900 dark:text-gray-100">
                                {stats.outbound.table_count}
                            </p>
                        </div>
                    </div>
                    {stats.outbound.last_exchange && (
                        <p className="text-xs text-gray-500 dark:text-gray-400">
                            Last: {new Date(stats.outbound.last_exchange).toLocaleString()}
                        </p>
                    )}
                </div>

                {/* Inbound */}
                <div className="p-4 bg-green-50 dark:bg-green-900/20 rounded-lg space-y-2">
                    <div className="flex items-center gap-2">
                        <ArrowDownLeft className="h-4 w-4 text-green-500" />
                        <p className="text-sm font-medium text-green-700 dark:text-green-400">Inbound</p>
                    </div>
                    <div className="grid grid-cols-2 gap-2 text-xs">
                        <div>
                            <p className="text-gray-500 dark:text-gray-400">Records</p>
                            <p className="text-lg font-bold text-gray-900 dark:text-gray-100">
                                {stats.inbound.record_count.toLocaleString()}
                            </p>
                        </div>
                        <div>
                            <p className="text-gray-500 dark:text-gray-400">Tables</p>
                            <p className="text-lg font-bold text-gray-900 dark:text-gray-100">
                                {stats.inbound.table_count}
                            </p>
                        </div>
                    </div>
                    {stats.inbound.last_exchange && (
                        <p className="text-xs text-gray-500 dark:text-gray-400">
                            Last: {new Date(stats.inbound.last_exchange).toLocaleString()}
                        </p>
                    )}
                </div>
            </div>
        </Card>
    );
}


// ── Helper Component ────────────────────────────────────────────

function InfoItem({ label, children }: { label: string; children: React.ReactNode }) {
    return (
        <div>
            <p className="text-xs text-gray-500 dark:text-gray-400 mb-0.5">{label}</p>
            {children}
        </div>
    );
}
