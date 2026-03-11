import { useState, useCallback } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
    Link2, Building2, Users, ShieldCheck, Network, Boxes, FileText, PlugZap,
    Plus, Trash2, Copy, Check, Clock, ExternalLink, Loader2, AlertCircle,
} from 'lucide-react';
import { Card } from '../../../components/ui/Card';
import { Badge } from '../../../components/ui/Badge';
import { Modal } from '../../../components/ui/Modal';
import { Button } from '../../../components/ui/Button';
import { listSuppliers } from '../../../api/parts';
import {
    createPortalToken,
    listPortalTokens,
    revokePortalToken,
} from '../../../api/orders';
import type { Supplier } from '../../../lib/types';

const PHASES = [
    {
        phase: 'Phase S1',
        title: 'Communication Bridge Core',
        status: 'planned',
        items: [
            'Supplier-side login mode (communication-first, not ERP replacement)',
            'Contractor ↔ Supplier partner channels for PO + RFI communication',
            'Rich attachments (PDF/photos/videos/docs) with clear context',
            'Optional quick-link sharing (supplier part links + references)',
        ],
    },
    {
        phase: 'Phase S2',
        title: 'Supplier Suggest Catalog (Backup)',
        status: 'planned',
        items: [
            'Rep-level lightweight catalog for frequently suggested parts',
            'Price sharing OFF by default',
            'One-click “Send to Contractor” from suggest catalog',
            'Contractor-side “Import Part” flow to create internal part + supplier mapping',
        ],
    },
    {
        phase: 'Phase S3',
        title: 'Optional Supplier API Connectors',
        status: 'planned',
        items: [
            'Pluggable connector layer for supplier catalog APIs',
            'Versioned mapping by supplier part ID / supplier org ID',
            'Live availability/pricing optional and guarded by capability flags',
            'Integration contracts designed so either side can evolve independently',
        ],
    },
    {
        phase: 'Phase S4',
        title: 'Remote Pairing + Recovery',
        status: 'planned',
        items: [
            'Shop identity + known-partner records',
            'Automatic one-sided IP recovery',
            'Guided manual recovery when both IPs change',
            'Certificate/PIN validation for secure re-linking',
        ],
    },
];

function PhaseCard({
    phase,
    title,
    status,
    items,
}: {
    phase: string;
    title: string;
    status: 'planned' | 'in-progress' | 'done';
    items: string[];
}) {
    const variant = status === 'done' ? 'success' : status === 'in-progress' ? 'warning' : 'default';
    const statusLabel = status === 'done' ? 'Done' : status === 'in-progress' ? 'In Progress' : 'Planned';

    return (
        <Card>
            <div className="p-4 space-y-3">
                <div className="flex items-center justify-between gap-3 flex-wrap">
                    <div>
                        <p className="text-xs uppercase tracking-wide text-gray-400">{phase}</p>
                        <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100">{title}</h3>
                    </div>
                    <Badge variant={variant}>{statusLabel}</Badge>
                </div>

                <ul className="space-y-1.5">
                    {items.map((item, idx) => (
                        <li key={idx} className="text-sm text-gray-700 dark:text-gray-300 flex gap-2">
                            <span className="text-gray-400">•</span>
                            <span>{item}</span>
                        </li>
                    ))}
                </ul>
            </div>
        </Card>
    );
}

export function SupplierBridgePage() {
    const queryClient = useQueryClient();
    const [showCreateModal, setShowCreateModal] = useState(false);
    const [copiedToken, setCopiedToken] = useState<string | null>(null);

    // Fetch active tokens
    const tokensQ = useQuery({
        queryKey: ['portal-tokens'],
        queryFn: () => listPortalTokens(),
        staleTime: 30_000,
    });

    // Revoke mutation
    const revokeMut = useMutation({
        mutationFn: (tokenId: number) => revokePortalToken(tokenId),
        onSuccess: () => {
            queryClient.invalidateQueries({ queryKey: ['portal-tokens'] });
        },
    });

    const handleCopyLink = useCallback((token: string) => {
        const url = `${window.location.origin}/supplier-portal?token=${token}`;
        navigator.clipboard.writeText(url);
        setCopiedToken(token);
        setTimeout(() => setCopiedToken(null), 2000);
    }, []);

    const tokens = tokensQ.data ?? [];

    return (
        <div className="space-y-5">
            <div>
                <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-100 flex items-center gap-2">
                    <Link2 className="h-5 w-5 text-indigo-500" />
                    Supplier Communication Bridge
                </h2>
                <p className="text-sm text-gray-500 dark:text-gray-400 mt-0.5">
                    Manage supplier portal access tokens and view the integration roadmap.
                </p>
            </div>

            {/* ── Portal Access Tokens ──────────────────────────── */}
            <Card>
                <div className="p-4 space-y-4">
                    <div className="flex items-center justify-between flex-wrap gap-3">
                        <div>
                            <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100">
                                Portal Access Tokens
                            </h3>
                            <p className="text-xs text-gray-500 dark:text-gray-400 mt-0.5">
                                Generate time-limited links for suppliers to view and acknowledge their POs.
                            </p>
                        </div>
                        <button
                            onClick={() => setShowCreateModal(true)}
                            className="inline-flex items-center gap-1.5 rounded-lg bg-indigo-600 px-3 py-2 text-xs font-medium text-white hover:bg-indigo-700 transition-colors"
                        >
                            <Plus className="h-3.5 w-3.5" />
                            New Token
                        </button>
                    </div>

                    {tokensQ.isLoading ? (
                        <div className="flex items-center justify-center py-6">
                            <Loader2 className="h-5 w-5 animate-spin text-gray-400" />
                        </div>
                    ) : tokens.length === 0 ? (
                        <div className="text-center py-6">
                            <ShieldCheck className="mx-auto h-8 w-8 text-gray-300 dark:text-gray-600 mb-2" />
                            <p className="text-sm text-gray-500 dark:text-gray-400">
                                No portal tokens yet. Create one to give a supplier access.
                            </p>
                        </div>
                    ) : (
                        <div className="space-y-2">
                            {tokens.map((t) => {
                                const isExpired = t.expires_at && new Date(t.expires_at) < new Date();
                                return (
                                    <div
                                        key={t.id}
                                        className="flex items-center gap-3 rounded-lg border border-border bg-surface p-3"
                                    >
                                        <div className="min-w-0 flex-1">
                                            <div className="flex items-center gap-2 flex-wrap">
                                                <span className="text-sm font-medium text-gray-900 dark:text-white">
                                                    {t.supplier_name || `Supplier #${t.supplier_id}`}
                                                </span>
                                                {t.is_active && !isExpired ? (
                                                    <Badge variant="success">Active</Badge>
                                                ) : isExpired ? (
                                                    <Badge variant="danger">Expired</Badge>
                                                ) : (
                                                    <Badge variant="neutral">Revoked</Badge>
                                                )}
                                            </div>
                                            <div className="flex items-center gap-3 mt-1 text-xs text-gray-500 dark:text-gray-400">
                                                <span className="font-mono">{t.token.slice(0, 8)}…</span>
                                                {t.expires_at && (
                                                    <span className="flex items-center gap-1">
                                                        <Clock className="h-3 w-3" />
                                                        Expires {new Date(t.expires_at).toLocaleDateString()}
                                                    </span>
                                                )}
                                                {t.last_used_at && (
                                                    <span>
                                                        Last used {new Date(t.last_used_at).toLocaleDateString()}
                                                    </span>
                                                )}
                                                {t.note && <span className="italic">{t.note}</span>}
                                            </div>
                                        </div>
                                        <div className="flex items-center gap-1">
                                            <button
                                                onClick={() => handleCopyLink(t.token)}
                                                className="p-2 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors"
                                                title="Copy portal link"
                                            >
                                                {copiedToken === t.token ? (
                                                    <Check className="h-4 w-4 text-green-500" />
                                                ) : (
                                                    <Copy className="h-4 w-4 text-gray-400" />
                                                )}
                                            </button>
                                            <a
                                                href={`/supplier-portal?token=${t.token}`}
                                                target="_blank"
                                                rel="noopener"
                                                className="p-2 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors"
                                                title="Open portal"
                                            >
                                                <ExternalLink className="h-4 w-4 text-gray-400" />
                                            </a>
                                            {t.is_active && (
                                                <button
                                                    onClick={() => revokeMut.mutate(t.id)}
                                                    disabled={revokeMut.isPending}
                                                    className="p-2 rounded-lg hover:bg-red-50 dark:hover:bg-red-900/20 transition-colors"
                                                    title="Revoke token"
                                                >
                                                    <Trash2 className="h-4 w-4 text-red-400 hover:text-red-600" />
                                                </button>
                                            )}
                                        </div>
                                    </div>
                                );
                            })}
                        </div>
                    )}
                </div>
            </Card>

            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3">
                <MiniPill icon={<Building2 className="h-4 w-4" />} label="Supplier App Mode" />
                <MiniPill icon={<Users className="h-4 w-4" />} label="Multi-Customer Support" />
                <MiniPill icon={<Network className="h-4 w-4" />} label="Dynamic IP Recovery" />
                <MiniPill icon={<ShieldCheck className="h-4 w-4" />} label="Secure Pairing" />
            </div>

            <Card>
                <div className="p-4 space-y-3">
                    <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100">Design Guardrails</h3>
                    <ul className="space-y-1.5 text-sm text-gray-700 dark:text-gray-300">
                        <li className="flex gap-2"><span className="text-gray-400">•</span><span>This does <strong>not</strong> replace supplier ERP systems; it is a communication bridge.</span></li>
                        <li className="flex gap-2"><span className="text-gray-400">•</span><span>Price sharing remains <strong>off by default</strong>; live pricing is optional via API connectors.</span></li>
                        <li className="flex gap-2"><span className="text-gray-400">•</span><span>Attachment-first communication for PO/RFI context (PDFs, photos, videos, docs, links).</span></li>
                        <li className="flex gap-2"><span className="text-gray-400">•</span><span>Supplier-sent parts should be importable into contractor catalog with supplier mapping metadata.</span></li>
                    </ul>
                </div>
            </Card>

            <div className="grid grid-cols-1 xl:grid-cols-2 gap-4">
                {PHASES.map((p) => (
                    <PhaseCard
                        key={p.phase}
                        phase={p.phase}
                        title={p.title}
                        status={p.status as 'planned' | 'in-progress' | 'done'}
                        items={p.items}
                    />
                ))}
            </div>

            <Card>
                <div className="p-4 space-y-2">
                    <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100">Planned Feature Areas</h3>
                    <div className="grid grid-cols-1 md:grid-cols-2 gap-2 text-sm text-gray-700 dark:text-gray-300">
                        <div className="flex items-center gap-2"><Boxes className="h-4 w-4 text-gray-500" /> Supplier Suggest Catalog</div>
                        <div className="flex items-center gap-2"><PlugZap className="h-4 w-4 text-gray-500" /> API Connector Framework</div>
                        <div className="flex items-center gap-2"><FileText className="h-4 w-4 text-gray-500" /> PO/RFI Attachment Channels</div>
                        <div className="flex items-center gap-2"><ShieldCheck className="h-4 w-4 text-gray-500" /> Partner Recovery Wizard</div>
                    </div>
                </div>
            </Card>

            {/* ── Create Token Modal ───────────────────────────── */}
            {showCreateModal && (
                <CreateTokenModal
                    onClose={() => setShowCreateModal(false)}
                    onCreated={() => {
                        setShowCreateModal(false);
                        queryClient.invalidateQueries({ queryKey: ['portal-tokens'] });
                    }}
                />
            )}
        </div>
    );
}

function MiniPill({ icon, label }: { icon: React.ReactNode; label: string }) {
    return (
        <div className="min-h-11 px-3 py-2 rounded-lg border border-border bg-surface flex items-center gap-2 text-sm text-gray-700 dark:text-gray-300">
            <span className="text-gray-500">{icon}</span>
            <span>{label}</span>
        </div>
    );
}


// ═══════════════════════════════════════════════════════════════
// CreateTokenModal — Create a new portal access token
// ═══════════════════════════════════════════════════════════════

function CreateTokenModal({
    onClose,
    onCreated,
}: {
    onClose: () => void;
    onCreated: () => void;
}) {
    const [supplierId, setSupplierId] = useState<number | null>(null);
    const [expiresInDays, setExpiresInDays] = useState(30);
    const [note, setNote] = useState('');
    const [createdToken, setCreatedToken] = useState<string | null>(null);
    const [copiedNew, setCopiedNew] = useState(false);

    const suppliersQ = useQuery({
        queryKey: ['suppliers', { is_active: true }],
        queryFn: () => listSuppliers({ is_active: true }),
        staleTime: 60_000,
    });

    const createMut = useMutation({
        mutationFn: () =>
            createPortalToken({
                supplier_id: supplierId!,
                expires_in_days: expiresInDays,
                note: note.trim() || undefined,
            }),
        onSuccess: (result) => {
            setCreatedToken(result.token);
        },
    });

    const handleCopyNewToken = useCallback(() => {
        if (!createdToken) return;
        const url = `${window.location.origin}/supplier-portal?token=${createdToken}`;
        navigator.clipboard.writeText(url);
        setCopiedNew(true);
        setTimeout(() => setCopiedNew(false), 2000);
    }, [createdToken]);

    const suppliers: Supplier[] = suppliersQ.data ?? [];

    return (
        <Modal isOpen onClose={onClose} title="Create Portal Token" size="md">
            {createdToken ? (
                /* Success — show the token */
                <div className="space-y-4">
                    <div className="flex items-start gap-3 p-4 bg-green-50 dark:bg-green-900/20 border border-green-200 dark:border-green-800 rounded-lg">
                        <ShieldCheck className="h-5 w-5 text-green-600 flex-shrink-0 mt-0.5" />
                        <div>
                            <h3 className="text-sm font-semibold text-green-800 dark:text-green-300">
                                Token Created Successfully
                            </h3>
                            <p className="text-xs text-green-700 dark:text-green-400 mt-1">
                                Copy the portal link below and share it with the supplier. They can use it to view and acknowledge their POs.
                            </p>
                        </div>
                    </div>

                    <div>
                        <label className="block text-xs font-medium text-gray-700 dark:text-gray-300 mb-1">
                            Portal Link
                        </label>
                        <div className="flex items-center gap-2">
                            <code className="flex-1 text-xs bg-gray-100 dark:bg-gray-800 p-3 rounded-lg break-all text-gray-700 dark:text-gray-300 border border-border">
                                {`${window.location.origin}/supplier-portal?token=${createdToken}`}
                            </code>
                            <button
                                onClick={handleCopyNewToken}
                                className="p-2 rounded-lg bg-gray-100 dark:bg-gray-700 hover:bg-gray-200 dark:hover:bg-gray-600 transition-colors flex-shrink-0"
                            >
                                {copiedNew ? (
                                    <Check className="h-4 w-4 text-green-500" />
                                ) : (
                                    <Copy className="h-4 w-4 text-gray-500" />
                                )}
                            </button>
                        </div>
                    </div>

                    <div className="flex justify-end">
                        <Button variant="primary" onClick={onCreated}>
                            Done
                        </Button>
                    </div>
                </div>
            ) : (
                /* Create form */
                <form
                    onSubmit={(e) => { e.preventDefault(); if (supplierId) createMut.mutate(); }}
                    className="space-y-4"
                >
                    {createMut.error && (
                        <div className="flex items-start gap-2 p-3 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-lg">
                            <AlertCircle className="h-4 w-4 text-red-500 flex-shrink-0 mt-0.5" />
                            <p className="text-sm text-red-600 dark:text-red-400">
                                {(createMut.error as Error).message || 'Failed to create token'}
                            </p>
                        </div>
                    )}

                    <div>
                        <label className="block text-xs font-medium text-gray-700 dark:text-gray-300 mb-1">
                            Supplier
                        </label>
                        <select
                            required
                            value={supplierId ?? ''}
                            onChange={(e) => setSupplierId(e.target.value ? Number(e.target.value) : null)}
                            className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm focus:ring-2 focus:ring-indigo-500"
                        >
                            <option value="">Select a supplier…</option>
                            {suppliers.map((s) => (
                                <option key={s.id} value={s.id}>
                                    {s.name}
                                </option>
                            ))}
                        </select>
                    </div>

                    <div>
                        <label className="block text-xs font-medium text-gray-700 dark:text-gray-300 mb-1">
                            Expires In (days)
                        </label>
                        <input
                            type="number"
                            min={1}
                            max={365}
                            value={expiresInDays}
                            onChange={(e) => setExpiresInDays(Number(e.target.value))}
                            className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm focus:ring-2 focus:ring-indigo-500"
                        />
                    </div>

                    <div>
                        <label className="block text-xs font-medium text-gray-700 dark:text-gray-300 mb-1">
                            Note <span className="text-gray-400">(optional)</span>
                        </label>
                        <input
                            type="text"
                            value={note}
                            onChange={(e) => setNote(e.target.value)}
                            placeholder="e.g., For sales rep John"
                            className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm focus:ring-2 focus:ring-indigo-500"
                        />
                    </div>

                    <div className="flex items-center justify-end gap-3 pt-2">
                        <Button variant="secondary" onClick={onClose}>
                            Cancel
                        </Button>
                        <Button
                            variant="primary"
                            type="submit"
                            disabled={!supplierId || createMut.isPending}
                            isLoading={createMut.isPending}
                        >
                            <Plus className="h-4 w-4 mr-1" />
                            Create Token
                        </Button>
                    </div>
                </form>
            )}
        </Modal>
    );
}
