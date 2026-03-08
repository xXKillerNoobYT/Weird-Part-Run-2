/**
 * ReviewAndSendPage — batch overview of approved JPOs ready for PO generation.
 *
 * Shows approved JPO lines grouped by suggested supplier, allowing office
 * staff to:
 *   - Review all approved orders at a glance
 *   - See supplier groupings (which lines go to which supplier)
 *   - Generate POs per JPO (auto-assign or manual)
 *   - Create PO groups to bundle multiple POs for the same supplier
 *   - Generate PDF bundles (group or individual)
 *
 * This replaces the old single-JPO GeneratePOsPage for the "office overview"
 * use case. The per-JPO generate page still exists for direct JPO → PO flows.
 *
 * Route: /orders/review-and-send
 * Permission: manage_orders
 */

import { useState, useMemo, useCallback } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Link, useNavigate } from 'react-router-dom';
import {
  ArrowRight,
  Building2,
  ChevronDown,
  ChevronRight,
  Loader2,
  Package,
  ShoppingCart,
  Sparkles,
  Zap,
  AlertCircle,
  CheckCircle2,
  Briefcase,
} from 'lucide-react';
import { PageSpinner } from '../../../components/ui/Spinner';
import { EmptyState } from '../../../components/ui/EmptyState';
import { Badge } from '../../../components/ui/Badge';
import { OrderStatusBadge } from '../../orders/components/OrderStatusBadge';
import { PartIdentity } from '../../../components/ui/PartIdentity';
import {
  listJPOs,
  getJPO,
  createPOFromJPO,
} from '../../../api/orders';
import { formatRelativeTime } from '../../../lib/utils';
import type {
  JPOListItem,
  JPOResponse,
  JPOLineResponse,
} from '../../../lib/types';


// ── Supplier group computed from JPO lines ──────────────────────

interface SupplierGroup {
  supplierId: number | null;
  supplierName: string | null;
  lines: {
    jpoId: number;
    jpoOrderNumber: string;
    jobName: string | null;
    lineId: number;
    partId: number;
    partNumber: string | null;
    partDescription: string | null;
    partName: string | null;
    categoryName: string | null;
    typeName: string | null;
    colorName: string | null;
    colorHex: string | null;
    brandName: string | null;
    qtyNeeded: number;
  }[];
}


export function ReviewAndSendPage() {
  const queryClient = useQueryClient();
  const navigate = useNavigate();

  // ── State ───────────────────────────────────────────────────
  const [expandedJpoId, setExpandedJpoId] = useState<number | null>(null);
  const [generatingJpoId, setGeneratingJpoId] = useState<number | null>(null);
  const [error, setError] = useState('');
  const [success, setSuccess] = useState('');

  // ── Fetch approved JPOs ─────────────────────────────────────
  const jposQ = useQuery({
    queryKey: ['jpos', { status: 'approved' }],
    queryFn: () => listJPOs({ status: 'approved' }),
    refetchInterval: 30_000,
  });

  // Fetch detail for expanded JPO (to see line items)
  const jpoDetailQ = useQuery({
    queryKey: ['jpo-detail', expandedJpoId],
    queryFn: () => getJPO(expandedJpoId!),
    enabled: !!expandedJpoId,
  });

  // ── Generate POs mutation ───────────────────────────────────
  const generateMut = useMutation({
    mutationFn: createPOFromJPO,
    onSuccess: (pos, _variables) => {
      setSuccess(
        `Created ${pos.length} PO${pos.length !== 1 ? 's' : ''} from order — POs are now in Draft status`
      );
      setGeneratingJpoId(null);
      setExpandedJpoId(null);
      // Refresh queries
      queryClient.invalidateQueries({ queryKey: ['jpos'] });
      queryClient.invalidateQueries({ queryKey: ['pos'] });
    },
    onError: (err: Error) => {
      setError(err.message || 'Failed to generate purchase orders');
      setGeneratingJpoId(null);
    },
  });

  // ── Derived data ────────────────────────────────────────────
  const approvedJPOs: JPOListItem[] = jposQ.data ?? [];
  const expandedJPO: JPOResponse | undefined = jpoDetailQ.data;

  // Compute supplier groupings for expanded JPO
  const supplierGroups = useMemo((): SupplierGroup[] => {
    if (!expandedJPO?.lines) return [];

    // Only lines that still need ordering
    const needsOrdering = expandedJPO.lines.filter(
      (l: JPOLineResponse) => l.qty_requested > l.qty_ordered
    );

    // Group by suggested_supplier_id
    const groupMap = new Map<number | null, SupplierGroup>();
    for (const l of needsOrdering) {
      const key = l.suggested_supplier_id;
      if (!groupMap.has(key)) {
        groupMap.set(key, {
          supplierId: key,
          supplierName: l.supplier_name,
          lines: [],
        });
      }
      groupMap.get(key)!.lines.push({
        jpoId: expandedJPO.id,
        jpoOrderNumber: expandedJPO.order_number,
        jobName: expandedJPO.job_name,
        lineId: l.id,
        partId: l.part_id,
        partNumber: l.part_number,
        partDescription: l.part_description,
        partName: l.part_name,
        categoryName: l.category_name,
        typeName: l.type_name,
        colorName: l.color_name,
        colorHex: l.color_hex,
        brandName: l.brand_name,
        qtyNeeded: l.qty_requested - l.qty_ordered,
      });
    }

    // Sort: assigned suppliers first, then unassigned
    return Array.from(groupMap.values()).sort((a, b) => {
      if (a.supplierId && !b.supplierId) return -1;
      if (!a.supplierId && b.supplierId) return 1;
      return (a.supplierName ?? '').localeCompare(b.supplierName ?? '');
    });
  }, [expandedJPO]);

  const totalNeedsOrdering = supplierGroups.reduce(
    (sum, g) => sum + g.lines.length,
    0
  );

  // ── Handlers ────────────────────────────────────────────────
  const handleToggleExpand = useCallback((jpoId: number) => {
    setExpandedJpoId((prev) => (prev === jpoId ? null : jpoId));
    setError('');
    setSuccess('');
  }, []);

  const handleGenerateAuto = useCallback(
    (jpoId: number) => {
      setError('');
      setSuccess('');
      setGeneratingJpoId(jpoId);
      generateMut.mutate({ jpo_id: jpoId });
    },
    [generateMut]
  );

  const handleGoToManualGenerate = useCallback(
    (jpoId: number) => {
      navigate(`/orders/parts-requests/${jpoId}/generate-pos`);
    },
    [navigate]
  );

  // ── Loading ─────────────────────────────────────────────────
  if (jposQ.isLoading) return <PageSpinner />;

  // ── Render ──────────────────────────────────────────────────
  return (
    <div className="space-y-4">
      {/* Header */}
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div>
          <h1 className="text-xl font-semibold text-gray-900 dark:text-white">
            Review & Send
          </h1>
          <p className="text-sm text-gray-500 dark:text-gray-400 mt-0.5">
            {approvedJPOs.length} approved order{approvedJPOs.length !== 1 ? 's' : ''} ready for
            PO generation
          </p>
        </div>
        <Link
          to="/orders/purchase-orders"
          className="inline-flex items-center gap-2 rounded-lg bg-gray-100 dark:bg-gray-700 px-3 py-2 text-sm font-medium text-gray-700 dark:text-gray-300 hover:bg-gray-200 dark:hover:bg-gray-600 transition-colors"
        >
          <Package className="h-4 w-4" />
          <span className="hidden sm:inline">PO Management</span>
        </Link>
      </div>

      {/* Status banners */}
      {error && (
        <div className="flex items-start gap-3 p-3 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-lg">
          <AlertCircle className="h-5 w-5 text-red-500 flex-shrink-0 mt-0.5" />
          <p className="text-sm text-red-600 dark:text-red-400">{error}</p>
        </div>
      )}
      {success && (
        <div className="flex items-start gap-3 p-3 bg-green-50 dark:bg-green-900/20 border border-green-200 dark:border-green-800 rounded-lg">
          <CheckCircle2 className="h-5 w-5 text-green-500 flex-shrink-0 mt-0.5" />
          <p className="text-sm text-green-600 dark:text-green-400">{success}</p>
        </div>
      )}

      {/* Empty state */}
      {approvedJPOs.length === 0 ? (
        <EmptyState
          icon={CheckCircle2}
          title="All caught up!"
          description="No approved orders are waiting for PO generation. Check back after approving new orders."
        />
      ) : (
        <div className="space-y-3">
          {approvedJPOs.map((jpo) => (
            <JPOCard
              key={jpo.id}
              jpo={jpo}
              isExpanded={expandedJpoId === jpo.id}
              isGenerating={generatingJpoId === jpo.id}
              supplierGroups={expandedJpoId === jpo.id ? supplierGroups : []}
              detailLoading={expandedJpoId === jpo.id && jpoDetailQ.isLoading}
              totalNeedsOrdering={expandedJpoId === jpo.id ? totalNeedsOrdering : 0}
              onToggle={() => handleToggleExpand(jpo.id)}
              onGenerateAuto={() => handleGenerateAuto(jpo.id)}
              onGoToManual={() => handleGoToManualGenerate(jpo.id)}
            />
          ))}
        </div>
      )}

      {/* Footer info */}
      <div className="rounded-lg border border-blue-200 dark:border-blue-800 bg-blue-50 dark:bg-blue-900/10 px-4 py-3">
        <p className="text-xs text-blue-700 dark:text-blue-400">
          <strong>Tip:</strong> Use <strong>Auto-Generate</strong> to let the system assign
          suppliers based on the ranking algorithm, or <strong>Manual</strong> to choose
          suppliers per line. Generated POs start in Draft status — submit them from{' '}
          <Link to="/orders/purchase-orders" className="underline hover:no-underline">
            PO Management
          </Link>
          .
        </p>
      </div>
    </div>
  );
}


// ═══════════════════════════════════════════════════════════════
// JPOCard — expandable card for a single approved JPO
// ═══════════════════════════════════════════════════════════════

function JPOCard({
  jpo,
  isExpanded,
  isGenerating,
  supplierGroups,
  detailLoading,
  totalNeedsOrdering,
  onToggle,
  onGenerateAuto,
  onGoToManual,
}: {
  jpo: JPOListItem;
  isExpanded: boolean;
  isGenerating: boolean;
  supplierGroups: SupplierGroup[];
  detailLoading: boolean;
  totalNeedsOrdering: number;
  onToggle: () => void;
  onGenerateAuto: () => void;
  onGoToManual: () => void;
}) {
  return (
    <div className="rounded-xl border border-border bg-surface overflow-hidden">
      {/* Collapsed row */}
      <button
        onClick={onToggle}
        className="w-full text-left px-4 py-3 flex items-center gap-3 hover:bg-gray-50 dark:hover:bg-gray-800/50 transition-colors"
      >
        {isExpanded ? (
          <ChevronDown className="h-4 w-4 text-gray-400 flex-shrink-0" />
        ) : (
          <ChevronRight className="h-4 w-4 text-gray-400 flex-shrink-0" />
        )}
        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-2 flex-wrap">
            <span className="font-semibold text-sm text-gray-900 dark:text-white">
              {jpo.order_number}
            </span>
            <OrderStatusBadge status={jpo.status} type="jpo" />
            {jpo.has_special_items && (
              <Badge variant="warning">
                <Sparkles className="h-3 w-3 mr-0.5" />
                Special
              </Badge>
            )}
            {jpo.order_type === 'warehouse' && (
              <Badge variant="info">Restock</Badge>
            )}
          </div>
          <div className="flex items-center gap-3 mt-1 text-xs text-gray-500 dark:text-gray-400">
            {jpo.job_name && (
              <span className="flex items-center gap-1">
                <Briefcase className="h-3 w-3" />
                {jpo.job_name}
              </span>
            )}
            <span>{jpo.line_count} line{jpo.line_count !== 1 ? 's' : ''}</span>
            <span>by {jpo.requester_name ?? 'Unknown'}</span>
          </div>
        </div>
        <span className="text-xs text-gray-500 dark:text-gray-400 flex-shrink-0">
          {formatRelativeTime(jpo.created_at)}
        </span>
      </button>

      {/* Expanded content */}
      {isExpanded && (
        <div className="border-t border-border px-4 py-4 space-y-4">
          {detailLoading ? (
            <div className="flex items-center gap-2 py-6 justify-center">
              <Loader2 className="h-5 w-5 animate-spin text-gray-400" />
              <span className="text-sm text-gray-400">Loading line items…</span>
            </div>
          ) : totalNeedsOrdering === 0 ? (
            <div className="text-center py-6">
              <CheckCircle2 className="mx-auto h-10 w-10 text-green-500 mb-2" />
              <p className="text-sm font-medium text-gray-700 dark:text-gray-300">
                All items already ordered
              </p>
              <p className="text-xs text-gray-500 dark:text-gray-400">
                Every line has been fully ordered — no POs needed
              </p>
            </div>
          ) : (
            <>
              {/* Supplier groupings */}
              <div className="space-y-3">
                <h3 className="text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400">
                  Supplier Groupings ({totalNeedsOrdering} line{totalNeedsOrdering !== 1 ? 's' : ''})
                </h3>

                {supplierGroups.map((group, idx) => (
                  <div
                    key={group.supplierId ?? `unassigned-${idx}`}
                    className="rounded-lg border border-gray-200 dark:border-gray-700 bg-gray-50 dark:bg-gray-800/50 p-3"
                  >
                    <div className="flex items-center gap-2 mb-2">
                      <Building2 className="h-4 w-4 text-gray-400" />
                      <span className="text-sm font-medium text-gray-800 dark:text-gray-200">
                        {group.supplierName ?? (
                          <span className="text-amber-600 dark:text-amber-400 italic">
                            No supplier assigned
                          </span>
                        )}
                      </span>
                      <Badge variant={group.supplierId ? 'info' : 'warning'}>
                        {group.lines.length} item{group.lines.length !== 1 ? 's' : ''}
                      </Badge>
                    </div>
                    <div className="space-y-1">
                      {group.lines.map((line) => (
                        <div
                          key={line.lineId}
                          className="flex items-center gap-2 text-xs text-gray-600 dark:text-gray-400 pl-6"
                        >
                          <PartIdentity
                            compact
                            partName={line.partName}
                            partDescription={line.partDescription}
                            partNumber={line.partNumber}
                            partId={line.partId}
                            brandName={line.brandName}
                            colorName={line.colorName}
                            colorHex={line.colorHex}
                            categoryName={line.categoryName}
                            typeName={line.typeName}
                            className="flex-1 min-w-0"
                          />
                          <span className="ml-auto flex-shrink-0 font-medium text-gray-700 dark:text-gray-300">
                            ×{line.qtyNeeded}
                          </span>
                        </div>
                      ))}
                    </div>
                  </div>
                ))}
              </div>

              {/* Action buttons */}
              <div className="flex items-center gap-3 flex-wrap pt-2 border-t border-border">
                <button
                  onClick={onGenerateAuto}
                  disabled={isGenerating}
                  className="inline-flex items-center gap-2 rounded-lg bg-green-600 px-4 py-2 text-sm font-medium text-white hover:bg-green-700 disabled:opacity-50 transition-colors min-h-[44px]"
                >
                  {isGenerating ? (
                    <Loader2 className="h-4 w-4 animate-spin" />
                  ) : (
                    <Zap className="h-4 w-4" />
                  )}
                  <span>Auto-Generate POs</span>
                </button>

                <button
                  onClick={onGoToManual}
                  className="inline-flex items-center gap-2 rounded-lg bg-gray-100 dark:bg-gray-700 px-4 py-2 text-sm font-medium text-gray-700 dark:text-gray-300 hover:bg-gray-200 dark:hover:bg-gray-600 transition-colors min-h-[44px]"
                >
                  <ShoppingCart className="h-4 w-4" />
                  <span className="hidden sm:inline">Manual Assignment</span>
                  <span className="sm:hidden">Manual</span>
                  <ArrowRight className="h-3.5 w-3.5" />
                </button>

                <Link
                  to={`/orders/parts-requests/${jpo.id}`}
                  className="inline-flex items-center gap-1.5 text-sm text-gray-500 dark:text-gray-400 hover:text-primary transition-colors ml-auto min-h-[44px]"
                >
                  View Details
                  <ArrowRight className="h-3.5 w-3.5" />
                </Link>
              </div>
            </>
          )}
        </div>
      )}
    </div>
  );
}
