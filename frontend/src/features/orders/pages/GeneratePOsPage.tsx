/**
 * GeneratePOsPage — convert an approved JPO into one or more Purchase Orders.
 *
 * This page loads the JPO detail, shows its line items, and lets the user
 * either auto-assign suppliers (system picks best via ranking algorithm)
 * or manually assign a supplier per line. On submit, the backend creates
 * one PO per unique supplier.
 *
 * Route: /orders/parts-requests/:id/generate-pos
 */

import { useState, useMemo, useEffect } from 'react';
import { useParams, Link, useNavigate } from 'react-router-dom';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  ArrowLeft,
  Loader2,
  AlertCircle,
  Zap,
  Settings2,
  ShoppingCart,
  CheckCircle2,
  Package,
  ChevronDown,
} from 'lucide-react';
import {
  getJPO,
  createPOFromJPO,
  getPartSupplierSuggestions,
} from '../../../api/orders';
import { listSuppliers } from '../../../api/parts';
import type {
  JPOResponse,
  JPOLineResponse,
  SupplierRanking,
  Supplier,
  POFromJPO,
  SupplierLineGroup,
} from '../../../lib/types';


// ── Per-line supplier assignment ─────────────────────────────────
interface LineAssignment {
  line_id: number;
  part_id: number;
  part_number: string | null;
  part_description: string | null;
  qty_requested: number;
  qty_ordered: number;
  supplier_id: number | null;
  supplier_name: string | null;
  // Top suggestion from ranking algorithm
  suggested_supplier_id: number | null;
  suggested_supplier_name: string | null;
}


export function GeneratePOsPage() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const jpoId = Number(id);

  // ── State ─────────────────────────────────────────────────────
  const [mode, setMode] = useState<'auto' | 'manual'>('auto');
  const [assignments, setAssignments] = useState<LineAssignment[]>([]);
  const [validationError, setValidationError] = useState('');

  // ── Fetch JPO ─────────────────────────────────────────────────
  const {
    data: jpo,
    isLoading: jpoLoading,
    isError: jpoError,
    error: jpoErr,
  } = useQuery({
    queryKey: ['jpo-detail', jpoId],
    queryFn: () => getJPO(jpoId),
    enabled: !isNaN(jpoId),
  });

  // ── Fetch all suppliers (for manual mode dropdown) ────────────
  const { data: allSuppliers = [] } = useQuery({
    queryKey: ['suppliers'],
    queryFn: () => listSuppliers({ is_active: true }),
  });

  // ── Initialize assignments when JPO loads ─────────────────────
  useEffect(() => {
    if (!jpo?.lines) return;

    const needsOrdering = jpo.lines.filter(
      (l: JPOLineResponse) => l.qty_requested > l.qty_ordered,
    );

    setAssignments(
      needsOrdering.map((l: JPOLineResponse) => ({
        line_id: l.id,
        part_id: l.part_id,
        part_number: l.part_number,
        part_description: l.part_description,
        qty_requested: l.qty_requested,
        qty_ordered: l.qty_ordered,
        supplier_id: l.suggested_supplier_id,
        supplier_name: l.supplier_name,
        suggested_supplier_id: l.suggested_supplier_id,
        suggested_supplier_name: l.supplier_name,
      })),
    );
  }, [jpo]);

  // ── Generate POs mutation ─────────────────────────────────────
  const generateMut = useMutation({
    mutationFn: createPOFromJPO,
    onSuccess: (pos) => {
      queryClient.invalidateQueries({ queryKey: ['jpos'] });
      queryClient.invalidateQueries({ queryKey: ['jpo-detail', jpoId] });
      queryClient.invalidateQueries({ queryKey: ['pos'] });
      // Navigate back to JPO detail to see the linked POs
      navigate(`/orders/parts-requests/${jpoId}`);
    },
    onError: (err: Error) => {
      setValidationError(err.message || 'Failed to generate purchase orders');
    },
  });

  // ── Derived data ──────────────────────────────────────────────
  const supplierGroups = useMemo(() => {
    if (mode === 'auto') return null; // Backend will auto-assign

    // Group lines by supplier_id for manual mode
    const groups = new Map<number, number[]>();
    for (const a of assignments) {
      if (!a.supplier_id) continue;
      const existing = groups.get(a.supplier_id) ?? [];
      existing.push(a.line_id);
      groups.set(a.supplier_id, existing);
    }

    return Array.from(groups.entries()).map(
      ([supplier_id, line_ids]): SupplierLineGroup => ({
        supplier_id,
        line_ids,
      }),
    );
  }, [assignments, mode]);

  const unassignedCount =
    mode === 'manual' ? assignments.filter((a) => !a.supplier_id).length : 0;

  const poCount = supplierGroups?.length ?? 0;

  // ── Handlers ──────────────────────────────────────────────────
  const updateAssignment = (lineId: number, supplierId: number | null) => {
    const supplier = allSuppliers.find((s: Supplier) => s.id === supplierId);
    setAssignments((prev) =>
      prev.map((a) =>
        a.line_id === lineId
          ? {
              ...a,
              supplier_id: supplierId,
              supplier_name: supplier?.name ?? null,
            }
          : a,
      ),
    );
  };

  const handleSubmit = () => {
    setValidationError('');

    if (mode === 'manual' && unassignedCount > 0) {
      setValidationError(
        `${unassignedCount} line(s) have no supplier assigned. Assign all lines or switch to auto mode.`,
      );
      return;
    }

    if (assignments.length === 0) {
      setValidationError('No lines need ordering.');
      return;
    }

    const payload: POFromJPO = {
      jpo_id: jpoId,
      supplier_line_groups: mode === 'manual' ? supplierGroups : undefined,
    };

    generateMut.mutate(payload);
  };

  // ── Loading / error ───────────────────────────────────────────
  if (jpoLoading) {
    return (
      <div className="flex items-center justify-center py-24">
        <Loader2 className="h-8 w-8 text-primary animate-spin" />
      </div>
    );
  }

  if (jpoError || !jpo) {
    return (
      <div className="space-y-4">
        <Link
          to="/orders/parts-requests"
          className="inline-flex items-center gap-1.5 text-sm text-gray-500 dark:text-gray-400 hover:text-primary transition-colors min-h-[44px]"
        >
          <ArrowLeft className="h-4 w-4" />
          Back to Parts Requests
        </Link>
        <div className="flex items-start gap-3 p-4 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-lg">
          <AlertCircle className="h-5 w-5 text-red-500 mt-0.5" />
          <p className="text-sm text-red-600 dark:text-red-400">
            {(jpoErr as Error)?.message || 'Parts request not found.'}
          </p>
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-4">
      {/* ── Back link ──────────────────────────────────────────── */}
      <Link
        to={`/orders/parts-requests/${jpoId}`}
        className="inline-flex items-center gap-1.5 text-sm text-gray-500 dark:text-gray-400 hover:text-primary transition-colors min-h-[44px]"
      >
        <ArrowLeft className="h-4 w-4" />
        Back to {jpo.order_number}
      </Link>

      {/* ── Header ─────────────────────────────────────────────── */}
      <div>
        <h1 className="text-xl font-semibold text-gray-900 dark:text-gray-100">
          Generate Purchase Orders
        </h1>
        <p className="text-sm text-gray-500 dark:text-gray-400 mt-0.5">
          {jpo.order_number} · {jpo.job_name} ({jpo.job_number}) · {assignments.length} line
          {assignments.length !== 1 ? 's' : ''} to order
        </p>
      </div>

      {/* ── Error banner ───────────────────────────────────────── */}
      {(validationError || generateMut.isError) && (
        <div className="flex items-start gap-3 p-3 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-lg">
          <AlertCircle className="h-5 w-5 text-red-500 flex-shrink-0 mt-0.5" />
          <p className="text-sm text-red-600 dark:text-red-400">
            {validationError || generateMut.error?.message}
          </p>
        </div>
      )}

      {/* ── No lines to order ──────────────────────────────────── */}
      {assignments.length === 0 ? (
        <div className="rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 shadow-sm py-12">
          <div className="text-center">
            <CheckCircle2 className="mx-auto h-12 w-12 text-green-500 mb-3" />
            <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-100">
              All Items Already Ordered
            </h2>
            <p className="text-sm text-gray-500 dark:text-gray-400 mt-1">
              Every line on this parts request has been fully ordered. No new POs are needed.
            </p>
            <Link
              to={`/orders/parts-requests/${jpoId}`}
              className="inline-flex items-center gap-2 mt-4 rounded-lg bg-primary px-4 py-2 text-sm font-medium text-white hover:bg-primary/90 transition-colors"
            >
              <ArrowLeft className="h-4 w-4" />
              Back to Details
            </Link>
          </div>
        </div>
      ) : (
        <>
          {/* ── Mode Toggle ──────────────────────────────────────── */}
          <div className="flex items-center gap-2 rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 shadow-sm p-3">
            <button
              type="button"
              onClick={() => setMode('auto')}
              className={`flex-1 inline-flex items-center justify-center gap-2 rounded-lg px-4 py-2.5 text-sm font-medium transition-colors ${
                mode === 'auto'
                  ? 'bg-primary text-white shadow-sm'
                  : 'text-gray-600 dark:text-gray-400 hover:bg-gray-100 dark:hover:bg-gray-700'
              }`}
            >
              <Zap className="h-4 w-4" />
              Auto-Assign Suppliers
            </button>
            <button
              type="button"
              onClick={() => setMode('manual')}
              className={`flex-1 inline-flex items-center justify-center gap-2 rounded-lg px-4 py-2.5 text-sm font-medium transition-colors ${
                mode === 'manual'
                  ? 'bg-primary text-white shadow-sm'
                  : 'text-gray-600 dark:text-gray-400 hover:bg-gray-100 dark:hover:bg-gray-700'
              }`}
            >
              <Settings2 className="h-4 w-4" />
              Manual Assignment
            </button>
          </div>

          {/* ── Mode description ──────────────────────────────────── */}
          <div className="rounded-lg border border-blue-200 dark:border-blue-800 bg-blue-50 dark:bg-blue-900/10 px-4 py-2.5">
            <p className="text-sm text-blue-700 dark:text-blue-400">
              {mode === 'auto' ? (
                <>
                  <strong>Auto mode:</strong> The system will assign suppliers based on the ranking
                  algorithm (price 35%, on-time delivery 20%, communication 20%, quality 15%, lead
                  time 10%). Each line gets the best available supplier.
                </>
              ) : (
                <>
                  <strong>Manual mode:</strong> Choose a supplier for each line item below. Lines
                  assigned to the same supplier will be grouped into a single PO.
                </>
              )}
            </p>
          </div>

          {/* ── Line Items ──────────────────────────────────────── */}
          <div className="rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 shadow-sm">
            <div className="px-5 py-3 border-b border-gray-200 dark:border-gray-700">
              <h2 className="text-sm font-semibold text-gray-900 dark:text-gray-100">
                Line Items
              </h2>
            </div>

            <div className="divide-y divide-gray-200 dark:divide-gray-700">
              {assignments.map((a) => (
                <div key={a.line_id} className="px-5 py-4">
                  <div className="flex items-start justify-between gap-4 flex-wrap">
                    {/* Part info */}
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2 flex-wrap">
                        {a.part_number && (
                          <span className="text-xs font-mono bg-gray-200 dark:bg-gray-700 text-gray-600 dark:text-gray-300 px-1.5 py-0.5 rounded">
                            {a.part_number}
                          </span>
                        )}
                        <span className="text-sm font-medium text-gray-900 dark:text-gray-100">
                          {a.part_description ?? `Part #${a.part_id}`}
                        </span>
                      </div>
                      <p className="text-xs text-gray-500 dark:text-gray-400 mt-0.5">
                        Requested: {a.qty_requested} · Already ordered: {a.qty_ordered} ·{' '}
                        <span className="font-medium text-primary">
                          Need: {a.qty_requested - a.qty_ordered}
                        </span>
                      </p>
                      {a.suggested_supplier_name && (
                        <p className="text-xs text-green-600 dark:text-green-400 mt-0.5">
                          Suggested: {a.suggested_supplier_name}
                        </p>
                      )}
                    </div>

                    {/* Supplier selector (manual mode only) */}
                    {mode === 'manual' && (
                      <div className="flex-shrink-0 w-full sm:w-64">
                        <select
                          value={a.supplier_id ?? ''}
                          onChange={(e) =>
                            updateAssignment(
                              a.line_id,
                              e.target.value ? Number(e.target.value) : null,
                            )
                          }
                          className={`block w-full rounded-lg border px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-primary-300 transition-colors min-h-[44px] ${
                            !a.supplier_id
                              ? 'border-amber-400 dark:border-amber-600 bg-amber-50 dark:bg-amber-900/20 text-amber-800 dark:text-amber-300'
                              : 'border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100'
                          }`}
                        >
                          <option value="">Select supplier…</option>
                          {allSuppliers.map((s: Supplier) => (
                            <option key={s.id} value={s.id}>
                              {s.name}
                              {s.id === a.suggested_supplier_id ? ' ★' : ''}
                            </option>
                          ))}
                        </select>
                      </div>
                    )}

                    {/* Auto mode: show what will happen */}
                    {mode === 'auto' && (
                      <div className="flex-shrink-0 text-right">
                        <span className="text-xs text-gray-500 dark:text-gray-400">
                          {a.suggested_supplier_name ? (
                            <span className="text-green-600 dark:text-green-400">
                              → {a.suggested_supplier_name}
                            </span>
                          ) : (
                            <span className="text-amber-600 dark:text-amber-400">
                              System will assign
                            </span>
                          )}
                        </span>
                      </div>
                    )}
                  </div>
                </div>
              ))}
            </div>
          </div>

          {/* ── Summary + Submit ──────────────────────────────────── */}
          <div className="rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 shadow-sm p-5">
            <div className="flex items-center justify-between flex-wrap gap-3">
              <div>
                <p className="text-sm text-gray-700 dark:text-gray-300">
                  {mode === 'auto' ? (
                    <>
                      System will create POs for <strong>{assignments.length}</strong> line
                      {assignments.length !== 1 ? 's' : ''}, auto-assigning the best supplier per
                      line.
                    </>
                  ) : (
                    <>
                      Will create <strong>{poCount}</strong> PO{poCount !== 1 ? 's' : ''} covering{' '}
                      <strong>{assignments.length - unassignedCount}</strong> of{' '}
                      {assignments.length} lines.
                      {unassignedCount > 0 && (
                        <span className="text-amber-600 dark:text-amber-400 ml-1">
                          ({unassignedCount} unassigned)
                        </span>
                      )}
                    </>
                  )}
                </p>
              </div>

              <button
                type="button"
                onClick={handleSubmit}
                disabled={generateMut.isPending || assignments.length === 0}
                className="inline-flex items-center gap-2 rounded-lg bg-green-600 px-5 py-2 text-sm font-medium text-white shadow-sm hover:bg-green-700 disabled:opacity-50 transition-colors min-h-[44px]"
              >
                {generateMut.isPending ? (
                  <Loader2 className="h-4 w-4 animate-spin" />
                ) : (
                  <ShoppingCart className="h-4 w-4" />
                )}
                Generate POs
              </button>
            </div>
          </div>
        </>
      )}
    </div>
  );
}
