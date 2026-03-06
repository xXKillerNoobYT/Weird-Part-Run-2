/**
 * POManagementTab — Office module tab for managing POs by supplier.
 *
 * Three-panel layout:
 *   1. Supplier selector (sidebar on desktop, dropdown on mobile)
 *   2. PO list with status badges, confirmation checklist, quick actions
 *   3. Conversation thread panel (right on desktop, below on mobile)
 *
 * Key features:
 *   - Filter POs by supplier, then by status
 *   - Expandable confirmation checklist per PO (track which lines are confirmed ordered)
 *   - Conversation thread per PO (CRM-style notes, calls, emails)
 *   - Quick actions: Submit PO, Update Status, Generate PDF
 *   - Navigate to Review & Send for converting approved JPOs → POs
 *
 * Lives under: Orders > Office group > Purchase Orders tab
 * Permission: manage_orders
 */

import { useState, useMemo, useCallback } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useNavigate } from 'react-router-dom';
import {
  Building2,
  ChevronDown,
  ChevronRight,
  FileText,
  Loader2,
  Send,
  CheckCircle,
  Circle,
  ClipboardCheck,
  MessageSquare,
  Package,
  X,
  Filter,
  TrendingUp,
  AlertTriangle,
  Copy,
  Check,
} from 'lucide-react';
import { PageSpinner } from '../../../components/ui/Spinner';
import { EmptyState } from '../../../components/ui/EmptyState';
import { Badge } from '../../../components/ui/Badge';
import { OrderStatusBadge } from '../../orders/components/OrderStatusBadge';
import { ConversationThread } from '../../orders/components/ConversationThread';
import {
  listPOs,
  getPO,
  submitPO,
  updatePOStatus,
  generatePOPdf,
  getPOClipboardText,
  getConfirmationChecklist,
  updateConfirmationChecklist,
} from '../../../api/orders';
import { listSuppliers } from '../../../api/parts';
import { formatRelativeTime } from '../../../lib/utils';
import { cn } from '../../../lib/utils';
import type {
  POListItem,
  POResponse,
  POLineResponse,
  Supplier,
  ConfirmationChecklistItem,
} from '../../../lib/types';


// ── Status filter chips ─────────────────────────────────────────

type StatusFilter = 'all' | 'draft' | 'submitted' | 'acknowledged' | 'partially_received' | 'received';

const STATUS_FILTERS: { label: string; value: StatusFilter }[] = [
  { label: 'All', value: 'all' },
  { label: 'Draft', value: 'draft' },
  { label: 'Submitted', value: 'submitted' },
  { label: 'Acknowledged', value: 'acknowledged' },
  { label: 'Partial', value: 'partially_received' },
  { label: 'Received', value: 'received' },
];


// ── Format currency ─────────────────────────────────────────────

function fmtCost(v: number | null | undefined): string {
  if (v == null) return '—';
  return `$${v.toFixed(2)}`;
}


// ── Main component ──────────────────────────────────────────────

export function POManagementTab() {
  const queryClient = useQueryClient();
  const navigate = useNavigate();

  // Selection state
  const [selectedSupplierId, setSelectedSupplierId] = useState<number | null>(null);
  const [selectedPoId, setSelectedPoId] = useState<number | null>(null);
  const [statusFilter, setStatusFilter] = useState<StatusFilter>('all');
  const [expandedChecklist, setExpandedChecklist] = useState<number | null>(null);
  const [copiedPoId, setCopiedPoId] = useState<number | null>(null);

  // ── Data queries ────────────────────────────────────────────

  // Supplier list (for sidebar)
  const suppliersQ = useQuery({
    queryKey: ['suppliers', { is_active: true }],
    queryFn: () => listSuppliers({ is_active: true }),
    staleTime: 60_000,
  });

  // POs for selected supplier
  const posQ = useQuery({
    queryKey: ['pos', { supplier_id: selectedSupplierId }],
    queryFn: () => listPOs({ supplier_id: selectedSupplierId! }),
    enabled: !!selectedSupplierId,
    refetchInterval: 30_000,
  });

  // Full PO detail for selected PO (includes line items)
  const poDetailQ = useQuery({
    queryKey: ['po', selectedPoId],
    queryFn: () => getPO(selectedPoId!),
    enabled: !!selectedPoId,
  });

  // Confirmation checklist for expanded PO
  const checklistQ = useQuery({
    queryKey: ['po-checklist', expandedChecklist],
    queryFn: () => getConfirmationChecklist(expandedChecklist!),
    enabled: !!expandedChecklist,
  });

  // ── Mutations ───────────────────────────────────────────────

  const submitMut = useMutation({
    mutationFn: (poId: number) => submitPO(poId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['pos'] });
      queryClient.invalidateQueries({ queryKey: ['po', selectedPoId] });
    },
  });

  const statusMut = useMutation({
    mutationFn: ({ poId, status }: { poId: number; status: string }) =>
      updatePOStatus(poId, status),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['pos'] });
      queryClient.invalidateQueries({ queryKey: ['po', selectedPoId] });
    },
  });

  const pdfMut = useMutation({
    mutationFn: (poId: number) => generatePOPdf(poId),
  });

  const checklistMut = useMutation({
    mutationFn: ({ poId, checklist }: { poId: number; checklist: ConfirmationChecklistItem[] }) =>
      updateConfirmationChecklist(poId, { checklist }),
    onSuccess: (_data, variables) => {
      queryClient.invalidateQueries({ queryKey: ['po-checklist', variables.poId] });
    },
  });

  // ── Derived data ────────────────────────────────────────────

  const suppliers: Supplier[] = suppliersQ.data ?? [];

  // Count POs per supplier (from all POs would require separate queries — for now just show selected)
  const filteredPOs = useMemo(() => {
    const all: POListItem[] = posQ.data ?? [];
    if (statusFilter === 'all') return all;
    return all.filter((po) => po.status === statusFilter);
  }, [posQ.data, statusFilter]);

  const selectedPO: POResponse | undefined = poDetailQ.data;

  // ── Handlers ────────────────────────────────────────────────

  const handleSelectSupplier = useCallback((id: number) => {
    setSelectedSupplierId(id);
    setSelectedPoId(null); // reset PO selection when supplier changes
    setExpandedChecklist(null);
    setStatusFilter('all');
  }, []);

  const handleSelectPO = useCallback((poId: number) => {
    setSelectedPoId(poId);
    setExpandedChecklist(null);
  }, []);

  const handleToggleChecklist = useCallback((poId: number) => {
    setExpandedChecklist((prev) => (prev === poId ? null : poId));
  }, []);

  const handleCheckItem = useCallback(
    (poId: number, poLineId: number, currentChecked: boolean) => {
      const currentChecklist = checklistQ.data ?? [];
      const updated = currentChecklist.map((item) =>
        item.po_line_id === poLineId
          ? { ...item, confirmed: !currentChecked }
          : item
      );
      checklistMut.mutate({ poId, checklist: updated });
    },
    [checklistQ.data, checklistMut]
  );

  const handleCopyClipboard = useCallback(
    async (poId: number) => {
      try {
        const { text } = await getPOClipboardText(poId);
        await navigator.clipboard.writeText(text);
        setCopiedPoId(poId);
        setTimeout(() => setCopiedPoId(null), 2000);
      } catch {
        /* fail silently */
      }
    },
    []
  );

  // ── Loading state ───────────────────────────────────────────

  if (suppliersQ.isLoading) return <PageSpinner />;

  // ── Render ──────────────────────────────────────────────────

  return (
    <div className="flex flex-col gap-4 h-full">
      {/* Header */}
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div>
          <h1 className="text-xl font-semibold text-gray-900 dark:text-white">
            PO Management
          </h1>
          <p className="text-sm text-gray-500 dark:text-gray-400 mt-0.5">
            Manage purchase orders by supplier — track confirmations, communicate, generate PDFs
          </p>
        </div>
        <button
          onClick={() => navigate('/orders/review-and-send')}
          className="inline-flex items-center gap-2 rounded-lg bg-blue-600 px-3 py-2 text-sm font-medium text-white hover:bg-blue-700 transition-colors"
        >
          <TrendingUp className="h-4 w-4" />
          <span className="hidden sm:inline">Review & Send</span>
        </button>
      </div>

      {/* Main 3-panel layout */}
      <div className="flex flex-col lg:flex-row gap-4 min-h-0 flex-1">
        {/* ── Panel 1: Supplier Selector ──────────────────────── */}
        <SupplierPanel
          suppliers={suppliers}
          selectedId={selectedSupplierId}
          onSelect={handleSelectSupplier}
        />

        {/* ── Panel 2: PO List ────────────────────────────────── */}
        <div className="flex-1 min-w-0 flex flex-col gap-3">
          {selectedSupplierId ? (
            <>
              {/* Status filter chips */}
              <div className="flex items-center gap-2 overflow-x-auto pb-1">
                <Filter className="h-4 w-4 text-gray-400 flex-shrink-0" />
                {STATUS_FILTERS.map((f) => (
                  <button
                    key={f.value}
                    onClick={() => setStatusFilter(f.value)}
                    className={cn(
                      'whitespace-nowrap rounded-full px-3 py-1 text-xs font-medium transition-colors',
                      statusFilter === f.value
                        ? 'bg-blue-600 text-white'
                        : 'bg-gray-100 text-gray-600 hover:bg-gray-200 dark:bg-gray-700 dark:text-gray-300 dark:hover:bg-gray-600'
                    )}
                  >
                    {f.label}
                  </button>
                ))}
              </div>

              {/* PO cards */}
              {posQ.isLoading ? (
                <PageSpinner />
              ) : filteredPOs.length === 0 ? (
                <EmptyState
                  icon={Package}
                  title="No purchase orders"
                  description={
                    statusFilter !== 'all'
                      ? `No POs with status "${statusFilter}" for this supplier`
                      : 'No POs found for this supplier'
                  }
                />
              ) : (
                <div className="space-y-2 overflow-y-auto max-h-[calc(100vh-320px)]">
                  {filteredPOs.map((po) => (
                    <POCard
                      key={po.id}
                      po={po}
                      isSelected={selectedPoId === po.id}
                      isChecklistExpanded={expandedChecklist === po.id}
                      checklistItems={expandedChecklist === po.id ? checklistQ.data : undefined}
                      checklistLoading={expandedChecklist === po.id && checklistQ.isLoading}
                      isCopied={copiedPoId === po.id}
                      onSelect={() => handleSelectPO(po.id)}
                      onToggleChecklist={() => handleToggleChecklist(po.id)}
                      onCheckItem={(lineId, checked) => handleCheckItem(po.id, lineId, checked)}
                      onSubmit={() => submitMut.mutate(po.id)}
                      onGeneratePdf={() => pdfMut.mutate(po.id)}
                      onCopyClipboard={() => handleCopyClipboard(po.id)}
                      onUpdateStatus={(status) => statusMut.mutate({ poId: po.id, status })}
                      submitting={submitMut.isPending}
                      generatingPdf={pdfMut.isPending}
                    />
                  ))}
                </div>
              )}
            </>
          ) : (
            <EmptyState
              icon={Building2}
              title="Select a supplier"
              description="Choose a supplier from the list to view their purchase orders"
            />
          )}
        </div>

        {/* ── Panel 3: Conversation Thread ────────────────────── */}
        <div className="w-full lg:w-80 xl:w-96 flex-shrink-0">
          {selectedPoId ? (
            <div className="rounded-xl border border-border bg-surface p-4">
              <div className="flex items-center gap-2 mb-3">
                <MessageSquare className="h-4 w-4 text-blue-500" />
                <h3 className="text-sm font-semibold text-gray-900 dark:text-white">
                  Conversation
                </h3>
                {selectedPO && (
                  <span className="text-xs text-gray-500 dark:text-gray-400">
                    — {selectedPO.po_number}
                  </span>
                )}
              </div>
              <ConversationThread
                poId={selectedPoId}
                canEdit
                maxHeight="calc(100vh - 400px)"
              />
            </div>
          ) : selectedSupplierId ? (
            <div className="rounded-xl border border-border bg-surface p-4">
              <div className="flex items-center gap-2 mb-3">
                <MessageSquare className="h-4 w-4 text-purple-500" />
                <h3 className="text-sm font-semibold text-gray-900 dark:text-white">
                  Supplier Notes
                </h3>
              </div>
              <ConversationThread
                supplierId={selectedSupplierId}
                canEdit
                maxHeight="calc(100vh - 400px)"
              />
            </div>
          ) : (
            <div className="rounded-xl border border-border bg-surface p-6 flex items-center justify-center min-h-[200px]">
              <p className="text-sm text-gray-500 dark:text-gray-400 text-center">
                Select a PO to view its conversation thread
              </p>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}


// ═══════════════════════════════════════════════════════════════
// SupplierPanel — sidebar on desktop, horizontal scroll on mobile
// ═══════════════════════════════════════════════════════════════

function SupplierPanel({
  suppliers,
  selectedId,
  onSelect,
}: {
  suppliers: Supplier[];
  selectedId: number | null;
  onSelect: (id: number) => void;
}) {
  const [search, setSearch] = useState('');

  const filtered = useMemo(() => {
    if (!search.trim()) return suppliers;
    const q = search.toLowerCase();
    return suppliers.filter((s) => s.name.toLowerCase().includes(q));
  }, [suppliers, search]);

  return (
    <div className="w-full lg:w-56 xl:w-64 flex-shrink-0">
      <div className="rounded-xl border border-border bg-surface overflow-hidden">
        {/* Search */}
        <div className="p-2 border-b border-border">
          <input
            type="text"
            placeholder="Search suppliers…"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-1.5 text-sm text-gray-900 dark:text-white placeholder-gray-400 dark:placeholder-gray-500 focus:border-blue-500 focus:ring-1 focus:ring-blue-500"
          />
        </div>

        {/* Supplier list — horizontal scroll on mobile, vertical on desktop */}
        <div className="flex lg:flex-col overflow-x-auto lg:overflow-x-hidden lg:overflow-y-auto lg:max-h-[calc(100vh-340px)] p-1 gap-1">
          {filtered.length === 0 ? (
            <p className="text-xs text-gray-500 dark:text-gray-400 p-3 text-center w-full">
              No suppliers found
            </p>
          ) : (
            filtered.map((s) => (
              <button
                key={s.id}
                onClick={() => onSelect(s.id)}
                className={cn(
                  'flex items-center gap-2 rounded-lg px-3 py-2 text-left text-sm transition-colors w-full whitespace-nowrap lg:whitespace-normal min-w-[140px] lg:min-w-0',
                  selectedId === s.id
                    ? 'bg-blue-50 text-blue-700 dark:bg-blue-900/30 dark:text-blue-300 font-medium'
                    : 'text-gray-700 dark:text-gray-300 hover:bg-gray-50 dark:hover:bg-gray-800'
                )}
              >
                <Building2 className="h-4 w-4 flex-shrink-0" />
                <span className="truncate">{s.name}</span>
              </button>
            ))
          )}
        </div>
      </div>
    </div>
  );
}


// ═══════════════════════════════════════════════════════════════
// POCard — single PO with quick actions and expandable checklist
// ═══════════════════════════════════════════════════════════════

function POCard({
  po,
  isSelected,
  isChecklistExpanded,
  checklistItems,
  checklistLoading,
  isCopied,
  onSelect,
  onToggleChecklist,
  onCheckItem,
  onSubmit,
  onGeneratePdf,
  onCopyClipboard,
  onUpdateStatus,
  submitting,
  generatingPdf,
}: {
  po: POListItem;
  isSelected: boolean;
  isChecklistExpanded: boolean;
  checklistItems?: ConfirmationChecklistItem[];
  checklistLoading?: boolean;
  isCopied: boolean;
  onSelect: () => void;
  onToggleChecklist: () => void;
  onCheckItem: (lineId: number, currentChecked: boolean) => void;
  onSubmit: () => void;
  onGeneratePdf: () => void;
  onCopyClipboard: () => void;
  onUpdateStatus: (status: string) => void;
  submitting: boolean;
  generatingPdf: boolean;
}) {
  const confirmedCount = checklistItems?.filter((c) => c.confirmed).length ?? 0;
  const totalCount = checklistItems?.length ?? 0;

  return (
    <div
      className={cn(
        'rounded-xl border bg-surface transition-all',
        isSelected
          ? 'border-blue-400 dark:border-blue-600 ring-1 ring-blue-200 dark:ring-blue-800'
          : 'border-border hover:border-gray-300 dark:hover:border-gray-600'
      )}
    >
      {/* Main row — clickable to select PO */}
      <button
        onClick={onSelect}
        className="w-full text-left px-4 py-3 flex items-center gap-3"
      >
        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-2 flex-wrap">
            <span className="font-semibold text-sm text-gray-900 dark:text-white">
              {po.po_number}
            </span>
            <OrderStatusBadge status={po.status} type="po" />
          </div>
          <div className="flex items-center gap-3 mt-1 text-xs text-gray-500 dark:text-gray-400">
            <span>{po.line_count} item{po.line_count !== 1 ? 's' : ''}</span>
            <span>{fmtCost(po.total_cost)}</span>
            {po.expected_delivery && (
              <span>ETA {new Date(po.expected_delivery).toLocaleDateString()}</span>
            )}
          </div>
        </div>
        <span className="text-xs text-gray-500 dark:text-gray-400 flex-shrink-0">
          {formatRelativeTime(po.created_at)}
        </span>
      </button>

      {/* Quick actions row */}
      {isSelected && (
        <div className="px-4 pb-2 flex items-center gap-2 flex-wrap border-t border-border pt-2">
          {/* Submit (only if draft) */}
          {po.status === 'draft' && (
            <ActionButton
              icon={Send}
              label="Submit"
              onClick={(e) => { e.stopPropagation(); onSubmit(); }}
              loading={submitting}
              variant="primary"
            />
          )}

          {/* Acknowledge (only if submitted) */}
          {po.status === 'submitted' && (
            <ActionButton
              icon={CheckCircle}
              label="Acknowledged"
              onClick={(e) => { e.stopPropagation(); onUpdateStatus('acknowledged'); }}
            />
          )}

          {/* Generate PDF */}
          <ActionButton
            icon={FileText}
            label="PDF"
            onClick={(e) => { e.stopPropagation(); onGeneratePdf(); }}
            loading={generatingPdf}
          />

          {/* Copy to clipboard */}
          <ActionButton
            icon={isCopied ? Check : Copy}
            label={isCopied ? 'Copied' : 'Copy'}
            onClick={(e) => { e.stopPropagation(); onCopyClipboard(); }}
          />

          {/* Confirmation checklist toggle */}
          <button
            onClick={(e) => { e.stopPropagation(); onToggleChecklist(); }}
            className={cn(
              'inline-flex items-center gap-1.5 rounded-lg px-2.5 py-1.5 text-xs font-medium transition-colors min-h-[36px]',
              isChecklistExpanded
                ? 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400'
                : 'bg-gray-100 text-gray-600 hover:bg-gray-200 dark:bg-gray-700 dark:text-gray-300 dark:hover:bg-gray-600'
            )}
          >
            <ClipboardCheck className="h-3.5 w-3.5" />
            <span className="hidden sm:inline">Checklist</span>
            {isChecklistExpanded && totalCount > 0 && (
              <span className="ml-0.5">
                {confirmedCount}/{totalCount}
              </span>
            )}
          </button>
        </div>
      )}

      {/* Expandable checklist */}
      {isChecklistExpanded && (
        <div className="border-t border-border px-4 py-3">
          <div className="flex items-center gap-2 mb-2">
            <ClipboardCheck className="h-4 w-4 text-green-600 dark:text-green-400" />
            <span className="text-xs font-semibold text-gray-700 dark:text-gray-300">
              Confirmation Checklist
            </span>
            {totalCount > 0 && (
              <Badge variant={confirmedCount === totalCount ? 'green' : 'amber'}>
                {confirmedCount}/{totalCount}
              </Badge>
            )}
          </div>
          {checklistLoading ? (
            <div className="flex items-center gap-2 py-3">
              <Loader2 className="h-4 w-4 animate-spin text-gray-400" />
              <span className="text-xs text-gray-400">Loading checklist…</span>
            </div>
          ) : !checklistItems || checklistItems.length === 0 ? (
            <p className="text-xs text-gray-500 dark:text-gray-400 py-2">
              No checklist items — this PO may not have line items yet
            </p>
          ) : (
            <div className="space-y-1">
              {checklistItems.map((item) => (
                <button
                  key={item.po_line_id}
                  onClick={() => onCheckItem(item.po_line_id, item.confirmed)}
                  className="w-full flex items-center gap-2.5 rounded-lg px-2 py-1.5 text-left hover:bg-gray-50 dark:hover:bg-gray-800 transition-colors"
                >
                  {item.confirmed ? (
                    <CheckCircle className="h-4 w-4 text-green-500 flex-shrink-0" />
                  ) : (
                    <Circle className="h-4 w-4 text-gray-300 dark:text-gray-600 flex-shrink-0" />
                  )}
                  <span
                    className={cn(
                      'text-sm flex-1 min-w-0 truncate',
                      item.confirmed
                        ? 'text-gray-500 dark:text-gray-400 line-through'
                        : 'text-gray-800 dark:text-gray-200'
                    )}
                  >
                    {item.part_description ?? `Part #${item.part_id}`}
                  </span>
                  {item.confirmed && item.confirmer_name && (
                    <span className="text-[10px] text-gray-500 dark:text-gray-400 flex-shrink-0">
                      {item.confirmer_name}
                    </span>
                  )}
                </button>
              ))}
            </div>
          )}
        </div>
      )}
    </div>
  );
}


// ═══════════════════════════════════════════════════════════════
// ActionButton — small icon+text button for quick actions
// ═══════════════════════════════════════════════════════════════

function ActionButton({
  icon: Icon,
  label,
  onClick,
  loading,
  variant = 'default',
}: {
  icon: React.ComponentType<{ className?: string }>;
  label: string;
  onClick: (e: React.MouseEvent) => void;
  loading?: boolean;
  variant?: 'default' | 'primary';
}) {
  return (
    <button
      onClick={onClick}
      disabled={loading}
      className={cn(
        'inline-flex items-center gap-1.5 rounded-lg px-2.5 py-1.5 text-xs font-medium transition-colors disabled:opacity-50 min-h-[36px]',
        variant === 'primary'
          ? 'bg-blue-600 text-white hover:bg-blue-700'
          : 'bg-gray-100 text-gray-600 hover:bg-gray-200 dark:bg-gray-700 dark:text-gray-300 dark:hover:bg-gray-600'
      )}
    >
      {loading ? (
        <Loader2 className="h-3.5 w-3.5 animate-spin" />
      ) : (
        <Icon className="h-3.5 w-3.5" />
      )}
      <span className="hidden sm:inline">{label}</span>
    </button>
  );
}
