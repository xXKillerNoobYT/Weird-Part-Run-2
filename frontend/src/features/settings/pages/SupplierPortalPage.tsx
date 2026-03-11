/**
 * SupplierPortalPage — Public-facing page for suppliers to view & acknowledge POs.
 *
 * Access: Token-based (via URL query param or manual entry)
 * Route: /supplier-portal (outside AppShell + AuthGate)
 *
 * Features:
 *   - Token validation with supplier info display
 *   - PO list with status badges
 *   - Expandable PO detail with line items
 *   - Acknowledge PO with optional ETA + notes
 *   - Clean, branded UI (no app chrome — supplier-friendly)
 */

import { useState, useCallback } from 'react';
import { useSearchParams } from 'react-router-dom';
import { useQuery, useMutation, useQueryClient, QueryClient, QueryClientProvider } from '@tanstack/react-query';
import {
    Building2,
    Package,
    CheckCircle2,
    AlertCircle,
    ChevronDown,
    ChevronRight,
    Clock,
    FileText,
    Loader2,
    LogIn,
    ShieldCheck,
    Calendar,
    MessageSquare,
    Truck,
    Send,
} from 'lucide-react';
import {
    getPortalInfo,
    getPortalPOs,
    getPortalPODetail,
    acknowledgePortalPO,
    addPortalNote,
} from '../../../api/supplier-portal';
import type {
    SupplierPortalPO,
    SupplierPortalPODetail,
} from '../../../lib/types';


// ── Standalone query client (outside app's QueryClient) ─────────

const portalQueryClient = new QueryClient({
    defaultOptions: {
        queries: { retry: 1, staleTime: 30_000, refetchOnWindowFocus: false },
    },
});


// ── Currency formatter ──────────────────────────────────────────

function fmtCost(v: number | null | undefined): string {
    if (v == null) return '—';
    return `$${v.toFixed(2)}`;
}

function fmtDate(d: string | null | undefined): string {
    if (!d) return '—';
    return new Date(d).toLocaleDateString();
}


// ── Status badge for PO status ──────────────────────────────────

const STATUS_COLORS: Record<string, string> = {
    draft: 'bg-gray-100 text-gray-600',
    submitted: 'bg-blue-100 text-blue-700',
    acknowledged: 'bg-purple-100 text-purple-700',
    confirmed: 'bg-green-100 text-green-700',
    partially_received: 'bg-amber-100 text-amber-700',
    received: 'bg-emerald-100 text-emerald-700',
    cancelled: 'bg-red-100 text-red-700',
};


// ── Wrapper component with its own QueryClientProvider ──────────

export function SupplierPortalPage() {
    return (
        <QueryClientProvider client={portalQueryClient}>
            <PortalContent />
        </QueryClientProvider>
    );
}


// ── Main portal content ─────────────────────────────────────────

function PortalContent() {
    const [searchParams] = useSearchParams();
    const tokenFromUrl = searchParams.get('token') || '';

    const [tokenInput, setTokenInput] = useState(tokenFromUrl);
    const [activeToken, setActiveToken] = useState(tokenFromUrl);

    // ── Validate token ──────────────────────────────────────────
    const infoQ = useQuery({
        queryKey: ['portal-info', activeToken],
        queryFn: () => getPortalInfo(activeToken),
        enabled: !!activeToken,
        retry: false,
    });

    // ── Handle token submit ─────────────────────────────────────
    const handleLogin = useCallback(
        (e: React.FormEvent) => {
            e.preventDefault();
            if (tokenInput.trim()) {
                setActiveToken(tokenInput.trim());
            }
        },
        [tokenInput]
    );

    const isValidated = infoQ.isSuccess && !!infoQ.data;
    const isError = infoQ.isError;

    return (
        <div className="min-h-screen bg-gray-50 dark:bg-gray-950">
            {/* Header */}
            <header className="bg-white dark:bg-gray-900 border-b border-gray-200 dark:border-gray-800 px-4 py-4">
                <div className="max-w-4xl mx-auto flex items-center gap-3">
                    <div className="p-2 bg-indigo-100 dark:bg-indigo-900/30 rounded-lg">
                        <Truck className="h-5 w-5 text-indigo-600 dark:text-indigo-400" />
                    </div>
                    <div>
                        <h1 className="text-lg font-bold text-gray-900 dark:text-white">
                            Supplier Portal
                        </h1>
                        {isValidated && infoQ.data && (
                            <p className="text-xs text-gray-500 dark:text-gray-400">
                                Welcome, {infoQ.data.supplier_name}
                            </p>
                        )}
                    </div>
                </div>
            </header>

            <main className="max-w-4xl mx-auto px-4 py-6">
                {!activeToken || isError ? (
                    /* Token entry / error */
                    <div className="max-w-md mx-auto mt-12">
                        <div className="bg-white dark:bg-gray-900 border border-gray-200 dark:border-gray-800 rounded-xl shadow-sm p-6 space-y-5">
                            <div className="text-center">
                                <div className="mx-auto w-14 h-14 bg-indigo-100 dark:bg-indigo-900/30 rounded-full flex items-center justify-center mb-3">
                                    <LogIn className="h-7 w-7 text-indigo-600 dark:text-indigo-400" />
                                </div>
                                <h2 className="text-xl font-semibold text-gray-900 dark:text-white">
                                    Access Portal
                                </h2>
                                <p className="text-sm text-gray-500 dark:text-gray-400 mt-1">
                                    Enter your portal access token to view purchase orders
                                </p>
                            </div>

                            {isError && (
                                <div className="flex items-start gap-2 p-3 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-lg">
                                    <AlertCircle className="h-4 w-4 text-red-500 flex-shrink-0 mt-0.5" />
                                    <p className="text-sm text-red-600 dark:text-red-400">
                                        Invalid or expired token. Please check your access link.
                                    </p>
                                </div>
                            )}

                            <form onSubmit={handleLogin} className="space-y-4">
                                <div>
                                    <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                                        Access Token
                                    </label>
                                    <input
                                        type="text"
                                        required
                                        value={tokenInput}
                                        onChange={(e) => setTokenInput(e.target.value)}
                                        placeholder="Paste your access token…"
                                        className="w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-4 py-3 text-sm focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500"
                                        autoFocus
                                    />
                                </div>
                                <button
                                    type="submit"
                                    disabled={!tokenInput.trim()}
                                    className="w-full py-3 bg-indigo-600 hover:bg-indigo-700 disabled:opacity-50 text-white text-sm font-medium rounded-lg transition-colors flex items-center justify-center gap-2"
                                >
                                    <LogIn className="h-4 w-4" />
                                    Access Portal
                                </button>
                            </form>
                        </div>
                    </div>
                ) : infoQ.isLoading ? (
                    <div className="flex items-center justify-center py-20">
                        <Loader2 className="h-8 w-8 animate-spin text-indigo-500" />
                    </div>
                ) : isValidated && infoQ.data ? (
                    <PortalDashboard
                        token={activeToken}
                        supplierName={infoQ.data.supplier_name}
                        expiresAt={infoQ.data.token_expires_at}
                    />
                ) : null}
            </main>

            {/* Footer */}
            <footer className="border-t border-gray-200 dark:border-gray-800 mt-auto py-4 px-4">
                <p className="text-center text-xs text-gray-400 dark:text-gray-600">
                    Supplier Portal — Secure access to your purchase orders
                </p>
            </footer>
        </div>
    );
}


// ═══════════════════════════════════════════════════════════════
// PortalDashboard — PO list + detail after token validated
// ═══════════════════════════════════════════════════════════════

function PortalDashboard({
    token,
    supplierName,
    expiresAt,
}: {
    token: string;
    supplierName: string;
    expiresAt: string | null;
}) {
    const queryClient = useQueryClient();
    const [expandedPoId, setExpandedPoId] = useState<number | null>(null);

    // ── PO list ─────────────────────────────────────────────────
    const posQ = useQuery({
        queryKey: ['portal-pos', token],
        queryFn: () => getPortalPOs(token, { limit: 100 }),
        refetchInterval: 60_000,
    });

    // ── PO detail ───────────────────────────────────────────────
    const detailQ = useQuery({
        queryKey: ['portal-po-detail', token, expandedPoId],
        queryFn: () => getPortalPODetail(token, expandedPoId!),
        enabled: !!expandedPoId,
    });

    const pos: SupplierPortalPO[] = posQ.data ?? [];
    const pendingCount = pos.filter((p) => !p.acknowledged).length;

    return (
        <div className="space-y-5">
            {/* Supplier info card */}
            <div className="bg-white dark:bg-gray-900 border border-gray-200 dark:border-gray-800 rounded-xl p-5">
                <div className="flex items-center gap-3 flex-wrap">
                    <div className="p-2 bg-indigo-100 dark:bg-indigo-900/30 rounded-lg">
                        <Building2 className="h-5 w-5 text-indigo-600 dark:text-indigo-400" />
                    </div>
                    <div className="flex-1 min-w-0">
                        <h2 className="text-lg font-semibold text-gray-900 dark:text-white">
                            {supplierName}
                        </h2>
                        <div className="flex items-center gap-3 text-xs text-gray-500 dark:text-gray-400 mt-0.5">
                            <span>{pos.length} purchase order{pos.length !== 1 ? 's' : ''}</span>
                            {pendingCount > 0 && (
                                <span className="text-amber-600 dark:text-amber-400 font-medium">
                                    {pendingCount} pending acknowledgment
                                </span>
                            )}
                        </div>
                    </div>
                    {expiresAt && (
                        <div className="flex items-center gap-1.5 text-xs text-gray-500 dark:text-gray-400">
                            <Clock className="h-3.5 w-3.5" />
                            Expires {fmtDate(expiresAt)}
                        </div>
                    )}
                </div>
            </div>

            {/* PO list */}
            {posQ.isLoading ? (
                <div className="flex items-center justify-center py-12">
                    <Loader2 className="h-6 w-6 animate-spin text-gray-400" />
                </div>
            ) : pos.length === 0 ? (
                <div className="text-center py-16">
                    <Package className="mx-auto h-12 w-12 text-gray-300 dark:text-gray-600 mb-3" />
                    <h3 className="text-lg font-semibold text-gray-900 dark:text-white">
                        No Purchase Orders
                    </h3>
                    <p className="text-sm text-gray-500 dark:text-gray-400 mt-1">
                        No purchase orders are currently assigned to your account.
                    </p>
                </div>
            ) : (
                <div className="space-y-3">
                    {pos.map((po) => (
                        <PortalPOCard
                            key={po.po_id}
                            po={po}
                            isExpanded={expandedPoId === po.po_id}
                            detail={expandedPoId === po.po_id ? detailQ.data : undefined}
                            detailLoading={expandedPoId === po.po_id && detailQ.isLoading}
                            token={token}
                            onToggle={() =>
                                setExpandedPoId((prev) =>
                                    prev === po.po_id ? null : po.po_id
                                )
                            }
                            onAcknowledged={() => {
                                queryClient.invalidateQueries({
                                    queryKey: ['portal-pos', token],
                                });
                                queryClient.invalidateQueries({
                                    queryKey: ['portal-po-detail', token, po.po_id],
                                });
                            }}
                        />
                    ))}
                </div>
            )}
        </div>
    );
}


// ═══════════════════════════════════════════════════════════════
// PortalPOCard — Single PO card with expand + acknowledge
// ═══════════════════════════════════════════════════════════════

function PortalPOCard({
    po,
    isExpanded,
    detail,
    detailLoading,
    token,
    onToggle,
    onAcknowledged,
}: {
    po: SupplierPortalPO;
    isExpanded: boolean;
    detail?: SupplierPortalPODetail;
    detailLoading: boolean;
    token: string;
    onToggle: () => void;
    onAcknowledged: () => void;
}) {
    const [showAckForm, setShowAckForm] = useState(false);
    const [estDelivery, setEstDelivery] = useState('');
    const [supplierNotes, setSupplierNotes] = useState('');
    const [noteText, setNoteText] = useState('');
    const [noteSuccess, setNoteSuccess] = useState('');

    const ackMut = useMutation({
        mutationFn: () =>
            acknowledgePortalPO(token, {
                po_id: po.po_id,
                estimated_delivery: estDelivery || undefined,
                supplier_notes: supplierNotes.trim() || undefined,
            }),
        onSuccess: () => {
            setShowAckForm(false);
            onAcknowledged();
        },
    });

    const noteMut = useMutation({
        mutationFn: () => addPortalNote(token, po.po_id, noteText.trim()),
        onSuccess: () => {
            setNoteText('');
            setNoteSuccess('Note sent successfully!');
            setTimeout(() => setNoteSuccess(''), 3000);
        },
    });

    const statusColor = STATUS_COLORS[po.status] || STATUS_COLORS.draft;

    return (
        <div className="bg-white dark:bg-gray-900 border border-gray-200 dark:border-gray-800 rounded-xl overflow-hidden">
            {/* Header row */}
            <button
                onClick={onToggle}
                className="w-full text-left px-5 py-4 flex items-center gap-3 hover:bg-gray-50 dark:hover:bg-gray-800/50 transition-colors"
            >
                {isExpanded ? (
                    <ChevronDown className="h-4 w-4 text-gray-400 flex-shrink-0" />
                ) : (
                    <ChevronRight className="h-4 w-4 text-gray-400 flex-shrink-0" />
                )}
                <div className="min-w-0 flex-1">
                    <div className="flex items-center gap-2 flex-wrap">
                        <FileText className="h-4 w-4 text-gray-400" />
                        <span className="font-semibold text-sm text-gray-900 dark:text-white">
                            {po.po_number}
                        </span>
                        <span className={`inline-flex px-2 py-0.5 rounded-full text-xs font-medium ${statusColor}`}>
                            {po.status.replace(/_/g, ' ')}
                        </span>
                        {po.acknowledged && (
                            <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-700">
                                <CheckCircle2 className="h-3 w-3" />
                                Acknowledged
                            </span>
                        )}
                    </div>
                    <div className="flex items-center gap-4 mt-1.5 text-xs text-gray-500 dark:text-gray-400">
                        <span>{po.line_count} item{po.line_count !== 1 ? 's' : ''}</span>
                        <span className="font-medium text-gray-700 dark:text-gray-300">
                            {fmtCost(po.total_cost)}
                        </span>
                        {po.expected_delivery && (
                            <span className="flex items-center gap-1">
                                <Calendar className="h-3 w-3" />
                                ETA {fmtDate(po.expected_delivery)}
                            </span>
                        )}
                        <span>Created {fmtDate(po.created_at)}</span>
                    </div>
                </div>
            </button>

            {/* Expanded detail */}
            {isExpanded && (
                <div className="border-t border-gray-200 dark:border-gray-800 px-5 py-4 space-y-4">
                    {detailLoading ? (
                        <div className="flex items-center justify-center py-6">
                            <Loader2 className="h-5 w-5 animate-spin text-gray-400" />
                        </div>
                    ) : detail ? (
                        <>
                            {/* Line items table */}
                            <div>
                                <h4 className="text-xs font-semibold uppercase tracking-wider text-gray-500 mb-2">
                                    Order Lines
                                </h4>
                                <div className="overflow-x-auto">
                                    <table className="w-full text-sm">
                                        <thead>
                                            <tr className="border-b border-gray-200 dark:border-gray-700 text-left text-xs text-gray-500">
                                                <th className="pb-2 font-medium">Part</th>
                                                <th className="pb-2 font-medium text-right">Qty</th>
                                                <th className="pb-2 font-medium text-right">Unit Cost</th>
                                                <th className="pb-2 font-medium text-right">Total</th>
                                            </tr>
                                        </thead>
                                        <tbody className="divide-y divide-gray-100 dark:divide-gray-800">
                                            {detail.lines.map((line: Record<string, unknown>, idx: number) => (
                                                <tr key={idx}>
                                                    <td className="py-2 pr-3">
                                                        <div className="font-medium text-gray-900 dark:text-white">
                                                            {String(line.part_number || '—')}
                                                        </div>
                                                        {line.part_description ? (
                                                            <div className="text-xs text-gray-500 dark:text-gray-400">
                                                                {String(line.part_description)}
                                                            </div>
                                                        ) : null}
                                                    </td>
                                                    <td className="py-2 text-right text-gray-700 dark:text-gray-300">
                                                        {String(line.qty_ordered)}
                                                    </td>
                                                    <td className="py-2 text-right text-gray-700 dark:text-gray-300">
                                                        {fmtCost(line.unit_cost as number | null | undefined)}
                                                    </td>
                                                    <td className="py-2 text-right font-medium text-gray-900 dark:text-white">
                                                        {fmtCost(line.line_total as number | null | undefined)}
                                                    </td>
                                                </tr>
                                            ))}
                                        </tbody>
                                        <tfoot>
                                            <tr className="border-t-2 border-gray-300 dark:border-gray-600">
                                                <td colSpan={3} className="pt-2 text-right font-semibold text-gray-700 dark:text-gray-300">
                                                    Total:
                                                </td>
                                                <td className="pt-2 text-right font-bold text-gray-900 dark:text-white">
                                                    {fmtCost(detail.total_cost)}
                                                </td>
                                            </tr>
                                        </tfoot>
                                    </table>
                                </div>
                            </div>

                            {/* Notes */}
                            {detail.notes && (
                                <div className="bg-gray-50 dark:bg-gray-800/50 rounded-lg p-3">
                                    <div className="flex items-center gap-1.5 text-xs font-medium text-gray-500 mb-1">
                                        <MessageSquare className="h-3.5 w-3.5" />
                                        Notes
                                    </div>
                                    <p className="text-sm text-gray-700 dark:text-gray-300">{detail.notes}</p>
                                </div>
                            )}

                            {/* Acknowledgment info or form */}
                            {detail.acknowledgment ? (
                                <>
                                <div className="bg-green-50 dark:bg-green-900/20 border border-green-200 dark:border-green-800 rounded-lg p-4 space-y-2">
                                    <div className="flex items-center gap-2">
                                        <CheckCircle2 className="h-5 w-5 text-green-600" />
                                        <span className="font-semibold text-sm text-green-800 dark:text-green-300">
                                            Acknowledged
                                        </span>
                                        <span className="text-xs text-green-600 dark:text-green-400">
                                            {fmtDate(detail.acknowledgment.acknowledged_at)}
                                        </span>
                                    </div>
                                    {detail.acknowledgment.estimated_delivery && (
                                        <p className="text-sm text-green-700 dark:text-green-400 pl-7">
                                            <strong>Estimated Delivery:</strong>{' '}
                                            {fmtDate(detail.acknowledgment.estimated_delivery)}
                                        </p>
                                    )}
                                    {detail.acknowledgment.supplier_notes && (
                                        <p className="text-sm text-green-700 dark:text-green-400 pl-7">
                                            <strong>Notes:</strong> {detail.acknowledgment.supplier_notes}
                                        </p>
                                    )}
                                </div>

                                {/* Supplier Note Form (Phase 17 Gap 2) */}
                                <div className="bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-lg p-4 space-y-3">
                                    <h4 className="text-sm font-semibold text-gray-700 dark:text-gray-300 flex items-center gap-2">
                                        <MessageSquare className="h-4 w-4" />
                                        Add a Note
                                    </h4>
                                    <p className="text-xs text-gray-500 dark:text-gray-400">
                                        Questions, delays, partial availability? Add a note and we&apos;ll see it right away.
                                    </p>

                                    {noteSuccess && (
                                        <div className="flex items-center gap-2 p-2 bg-green-50 dark:bg-green-900/20 border border-green-200 dark:border-green-800 rounded-lg">
                                            <CheckCircle2 className="h-4 w-4 text-green-500" />
                                            <p className="text-xs text-green-600 dark:text-green-400">{noteSuccess}</p>
                                        </div>
                                    )}
                                    {noteMut.error && (
                                        <div className="flex items-start gap-2 p-2 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-lg">
                                            <AlertCircle className="h-4 w-4 text-red-500 flex-shrink-0 mt-0.5" />
                                            <p className="text-xs text-red-600 dark:text-red-400">
                                                {(noteMut.error as Error).message || 'Failed to send note'}
                                            </p>
                                        </div>
                                    )}

                                    <div className="flex gap-2">
                                        <textarea
                                            value={noteText}
                                            onChange={(e) => setNoteText(e.target.value)}
                                            rows={2}
                                            placeholder="Type your note here…"
                                            className="flex-1 rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm resize-none focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500"
                                        />
                                        <button
                                            onClick={() => noteMut.mutate()}
                                            disabled={!noteText.trim() || noteMut.isPending}
                                            className="self-end px-4 py-2 bg-indigo-600 hover:bg-indigo-700 disabled:opacity-50 text-white text-sm font-medium rounded-lg transition-colors flex items-center gap-1.5"
                                        >
                                            {noteMut.isPending ? (
                                                <Loader2 className="h-4 w-4 animate-spin" />
                                            ) : (
                                                <Send className="h-4 w-4" />
                                            )}
                                            <span className="hidden sm:inline">Send</span>
                                        </button>
                                    </div>
                                </div>
                                </>
                            ) : !showAckForm ? (
                                <button
                                    onClick={() => setShowAckForm(true)}
                                    className="w-full py-3 bg-indigo-600 hover:bg-indigo-700 text-white text-sm font-medium rounded-lg transition-colors flex items-center justify-center gap-2"
                                >
                                    <ShieldCheck className="h-4 w-4" />
                                    Acknowledge This Order
                                </button>
                            ) : (
                                <div className="bg-indigo-50 dark:bg-indigo-900/20 border border-indigo-200 dark:border-indigo-800 rounded-lg p-4 space-y-3">
                                    <h4 className="text-sm font-semibold text-indigo-800 dark:text-indigo-300">
                                        Acknowledge Order
                                    </h4>

                                    {ackMut.error && (
                                        <div className="flex items-start gap-2 p-2 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-lg">
                                            <AlertCircle className="h-4 w-4 text-red-500 flex-shrink-0 mt-0.5" />
                                            <p className="text-xs text-red-600 dark:text-red-400">
                                                {(ackMut.error as Error).message || 'Failed to acknowledge'}
                                            </p>
                                        </div>
                                    )}

                                    <div>
                                        <label className="block text-xs font-medium text-gray-700 dark:text-gray-300 mb-1">
                                            Estimated Delivery Date <span className="text-gray-400">(optional)</span>
                                        </label>
                                        <input
                                            type="date"
                                            value={estDelivery}
                                            onChange={(e) => setEstDelivery(e.target.value)}
                                            className="w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm"
                                        />
                                    </div>

                                    <div>
                                        <label className="block text-xs font-medium text-gray-700 dark:text-gray-300 mb-1">
                                            Notes <span className="text-gray-400">(optional)</span>
                                        </label>
                                        <textarea
                                            value={supplierNotes}
                                            onChange={(e) => setSupplierNotes(e.target.value)}
                                            rows={3}
                                            placeholder="Any notes about this order (lead time, partial availability, etc.)"
                                            className="w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm resize-none"
                                        />
                                    </div>

                                    <div className="flex items-center gap-2">
                                        <button
                                            onClick={() => ackMut.mutate()}
                                            disabled={ackMut.isPending}
                                            className="flex-1 py-2.5 bg-indigo-600 hover:bg-indigo-700 disabled:opacity-50 text-white text-sm font-medium rounded-lg transition-colors flex items-center justify-center gap-2"
                                        >
                                            {ackMut.isPending ? (
                                                <Loader2 className="h-4 w-4 animate-spin" />
                                            ) : (
                                                <CheckCircle2 className="h-4 w-4" />
                                            )}
                                            Confirm Acknowledgment
                                        </button>
                                        <button
                                            onClick={() => setShowAckForm(false)}
                                            className="px-4 py-2.5 text-sm text-gray-600 dark:text-gray-400 hover:bg-gray-100 dark:hover:bg-gray-800 rounded-lg transition-colors"
                                        >
                                            Cancel
                                        </button>
                                    </div>
                                </div>
                            )}
                        </>
                    ) : null}
                </div>
            )}
        </div>
    );
}
