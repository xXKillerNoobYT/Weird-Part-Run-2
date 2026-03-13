/**
 * NewReturnPage — create a return (job→warehouse or warehouse→supplier).
 *
 * The form adapts based on return_type:
 *  - job_to_warehouse: select a job, add parts being returned from the field
 *  - warehouse_to_supplier: select a PO + supplier, add parts being sent back
 *
 * Each return line captures: part, qty, condition, disposition, and notes.
 * Disposition determines downstream workflow (restock, return to supplier, or write off).
 */

import { useState, useMemo } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  ArrowLeft,
  Plus,
  Trash2,
  Loader2,
  AlertCircle,
  RotateCcw,
  Package,
} from 'lucide-react';
import { PartSearchModal } from '../components/PartSearchModal';
import { createReturn } from '../../../api/orders';
import { listPOs } from '../../../api/orders';
import { listSuppliers } from '../../../api/parts';
import { getActiveJobs } from '../../../api/jobs';
import type {
  ReturnType,
  ReturnReason,
  ItemCondition,
  DispositionType,
  ReturnCreate,
  ReturnLineCreate,
  PartListItem,
  POListItem,
  Supplier,
} from '../../../lib/types';
import type { JobListItem } from '../../../lib/types';


// ── Per-line form state ──────────────────────────────────────────
interface ReturnFormLine {
  part_id: number;
  part_code: string;
  part_name: string;
  qty: number;
  condition: ItemCondition;
  disposition: DispositionType;
  unit_cost: number | null;
  notes: string;
}

// ── Enum label maps ──────────────────────────────────────────────
const RETURN_TYPE_LABELS: Record<ReturnType, string> = {
  job_to_warehouse: 'Job → Warehouse',
  warehouse_to_supplier: 'Warehouse → Supplier',
};

const REASON_LABELS: Record<ReturnReason, string> = {
  defective: 'Defective',
  wrong_item: 'Wrong Item',
  surplus: 'Surplus / Excess',
  damaged: 'Damaged',
  unused: 'Unused',
};

const CONDITION_LABELS: Record<ItemCondition, string> = {
  new: 'New',
  used: 'Used',
  damaged: 'Damaged',
  defective: 'Defective',
};

const DISPOSITION_LABELS: Record<DispositionType, string> = {
  return_to_supplier: 'Return to Supplier',
  restock: 'Restock in Warehouse',
  write_off: 'Write Off',
};


export function NewReturnPage() {
  const navigate = useNavigate();
  const queryClient = useQueryClient();

  // ── Form state ────────────────────────────────────────────────
  const [returnType, setReturnType] = useState<ReturnType>('job_to_warehouse');
  const [jobId, setJobId] = useState<number | ''>('');
  const [supplierId, setSupplierId] = useState<number | ''>('');
  const [poId, setPoId] = useState<number | ''>('');
  const [reason, setReason] = useState<ReturnReason>('surplus');
  const [notes, setNotes] = useState('');
  const [lines, setLines] = useState<ReturnFormLine[]>([]);
  const [showPartSearch, setShowPartSearch] = useState(false);
  const [validationError, setValidationError] = useState('');

  // ── Queries ───────────────────────────────────────────────────
  const { data: jobs = [] } = useQuery({
    queryKey: ['active-jobs'],
    queryFn: () => getActiveJobs(),
  });

  const { data: suppliers = [] } = useQuery({
    queryKey: ['suppliers'],
    queryFn: () => listSuppliers({ is_active: true }),
  });

  const { data: poList = [] } = useQuery({
    queryKey: ['pos-for-returns'],
    queryFn: () => listPOs(),
  });

  // Filter POs by selected supplier
  const filteredPOs = useMemo(() => {
    if (!supplierId) return poList;
    return poList.filter((po: POListItem) => po.supplier_id === supplierId);
  }, [poList, supplierId]);

  // ── Create mutation ───────────────────────────────────────────
  const createMutation = useMutation({
    mutationFn: createReturn,
    onSuccess: (ret) => {
      queryClient.invalidateQueries({ queryKey: ['returns'] });
      navigate(`/orders/returns/${ret.id}`);
    },
    onError: (err: Error) => {
      setValidationError(err.message || 'Failed to create return');
    },
  });

  // ── Handlers ──────────────────────────────────────────────────
  const handleAddPart = (part: PartListItem) => {
    if (lines.some((l) => l.part_id === part.id)) return; // no dupes
    setLines((prev) => [
      ...prev,
      {
        part_id: part.id,
        part_code: part.code ?? '',
        part_name: part.name,
        qty: 1,
        condition: 'new',
        disposition:
          returnType === 'warehouse_to_supplier' ? 'return_to_supplier' : 'restock',
        unit_cost: part.company_cost_price ?? null,
        notes: '',
      },
    ]);
    setShowPartSearch(false);
  };

  const removeLine = (idx: number) =>
    setLines((prev) => prev.filter((_, i) => i !== idx));

  const updateLine = <K extends keyof ReturnFormLine>(
    idx: number,
    field: K,
    value: ReturnFormLine[K],
  ) =>
    setLines((prev) =>
      prev.map((l, i) => (i === idx ? { ...l, [field]: value } : l)),
    );

  const handleTypeChange = (t: ReturnType) => {
    setReturnType(t);
    // Reset context-specific fields
    setJobId('');
    setSupplierId('');
    setPoId('');
    setLines([]);
    setValidationError('');
  };

  const validate = (): boolean => {
    if (returnType === 'job_to_warehouse' && !jobId) {
      setValidationError('Please select a job.');
      return false;
    }
    if (returnType === 'warehouse_to_supplier' && !supplierId) {
      setValidationError('Please select a supplier.');
      return false;
    }
    if (lines.length === 0) {
      setValidationError('Add at least one item to the return.');
      return false;
    }
    const badQty = lines.find((l) => l.qty < 1);
    if (badQty) {
      setValidationError(`Quantity must be at least 1 for "${badQty.part_name}".`);
      return false;
    }
    return true;
  };

  const handleSubmit = () => {
    if (!validate()) return;
    setValidationError('');

    const payload: ReturnCreate = {
      return_type: returnType,
      job_id: returnType === 'job_to_warehouse' && jobId ? (jobId as number) : undefined,
      supplier_id:
        returnType === 'warehouse_to_supplier' && supplierId
          ? (supplierId as number)
          : undefined,
      po_id:
        returnType === 'warehouse_to_supplier' && poId ? (poId as number) : undefined,
      reason,
      notes: notes.trim() || undefined,
      lines: lines.map(
        (l): ReturnLineCreate => ({
          part_id: l.part_id,
          qty: l.qty,
          condition: l.condition,
          disposition: l.disposition,
          unit_cost: l.unit_cost ?? undefined,
          notes: l.notes.trim() || undefined,
        }),
      ),
    };

    createMutation.mutate(payload);
  };

  return (
    <div className="space-y-4">
      {/* ── Back link ──────────────────────────────────────────── */}
      <Link
        to="/orders/returns"
        className="inline-flex items-center gap-1.5 text-sm text-gray-500 dark:text-gray-400 hover:text-primary transition-colors min-h-[44px]"
      >
        <ArrowLeft className="h-4 w-4" />
        Back to Returns
      </Link>

      {/* ── Header ─────────────────────────────────────────────── */}
      <h1 className="text-xl font-semibold text-gray-900 dark:text-gray-100">
        New Return
      </h1>

      {/* ── Error banner ───────────────────────────────────────── */}
      {(validationError || createMutation.isError) && (
        <div className="flex items-start gap-3 p-3 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-lg">
          <AlertCircle className="h-5 w-5 text-red-500 flex-shrink-0 mt-0.5" />
          <p className="text-sm text-red-600 dark:text-red-400">
            {validationError || createMutation.error?.message}
          </p>
        </div>
      )}

      {/* ── Form Card ──────────────────────────────────────────── */}
      <div className="rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 shadow-sm p-6 space-y-5">
        {/* Row 1: Return Type + Reason */}
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div className="space-y-1.5">
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300">
              Return Type *
            </label>
            <select
              value={returnType}
              onChange={(e) => handleTypeChange(e.target.value as ReturnType)}
              className="block w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm text-gray-900 dark:text-gray-100 focus:outline-none focus:ring-2 focus:ring-primary-300 focus:border-primary-500 transition-colors min-h-[44px]"
            >
              {(Object.entries(RETURN_TYPE_LABELS) as [ReturnType, string][]).map(
                ([val, label]) => (
                  <option key={val} value={val}>
                    {label}
                  </option>
                ),
              )}
            </select>
          </div>

          <div className="space-y-1.5">
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300">
              Reason *
            </label>
            <select
              value={reason}
              onChange={(e) => setReason(e.target.value as ReturnReason)}
              className="block w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm text-gray-900 dark:text-gray-100 focus:outline-none focus:ring-2 focus:ring-primary-300 focus:border-primary-500 transition-colors min-h-[44px]"
            >
              {(Object.entries(REASON_LABELS) as [ReturnReason, string][]).map(
                ([val, label]) => (
                  <option key={val} value={val}>
                    {label}
                  </option>
                ),
              )}
            </select>
          </div>
        </div>

        {/* Row 2: Context-dependent selectors */}
        {returnType === 'job_to_warehouse' && (
          <div className="space-y-1.5">
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300">
              Job *
            </label>
            <select
              value={jobId}
              onChange={(e) => setJobId(e.target.value ? Number(e.target.value) : '')}
              className="block w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm text-gray-900 dark:text-gray-100 focus:outline-none focus:ring-2 focus:ring-primary-300 focus:border-primary-500 transition-colors min-h-[44px]"
            >
              <option value="">Select a job…</option>
              {jobs.map((j: JobListItem) => (
                <option key={j.id} value={j.id}>
                  {j.job_number} — {j.job_name}
                </option>
              ))}
            </select>
          </div>
        )}

        {returnType === 'warehouse_to_supplier' && (
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div className="space-y-1.5">
              <label className="block text-sm font-medium text-gray-700 dark:text-gray-300">
                Supplier *
              </label>
              <select
                value={supplierId}
                onChange={(e) => {
                  setSupplierId(e.target.value ? Number(e.target.value) : '');
                  setPoId(''); // reset PO when supplier changes
                }}
                className="block w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm text-gray-900 dark:text-gray-100 focus:outline-none focus:ring-2 focus:ring-primary-300 focus:border-primary-500 transition-colors min-h-[44px]"
              >
                <option value="">Select a supplier…</option>
                {suppliers.map((s: Supplier) => (
                  <option key={s.id} value={s.id}>
                    {s.name}
                  </option>
                ))}
              </select>
            </div>

            <div className="space-y-1.5">
              <label className="block text-sm font-medium text-gray-700 dark:text-gray-300">
                Related PO (optional)
              </label>
              <select
                value={poId}
                onChange={(e) => setPoId(e.target.value ? Number(e.target.value) : '')}
                className="block w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm text-gray-900 dark:text-gray-100 focus:outline-none focus:ring-2 focus:ring-primary-300 focus:border-primary-500 transition-colors min-h-[44px]"
              >
                <option value="">No specific PO</option>
                {filteredPOs.map((po: POListItem) => (
                  <option key={po.id} value={po.id}>
                    {po.po_number}
                    {po.supplier_name ? ` — ${po.supplier_name}` : ''}
                  </option>
                ))}
              </select>
            </div>
          </div>
        )}

        {/* Notes */}
        <div className="space-y-1.5">
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300">
            Notes
          </label>
          <textarea
            value={notes}
            onChange={(e) => setNotes(e.target.value)}
            rows={2}
            placeholder="Additional context for this return…"
            className="block w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm text-gray-900 dark:text-gray-100 placeholder:text-gray-400 dark:placeholder:text-gray-500 focus:outline-none focus:ring-2 focus:ring-primary-300 focus:border-primary-500 transition-colors"
          />
        </div>

        {/* ── Divider ──────────────────────────────────────────── */}
        <hr className="border-gray-200 dark:border-gray-700" />

        {/* ── Return Lines ─────────────────────────────────────── */}
        <div className="space-y-3">
          <div className="flex items-center justify-between">
            <h2 className="text-sm font-semibold text-gray-900 dark:text-gray-100">
              Return Items ({lines.length})
            </h2>
            <button
              type="button"
              onClick={() => setShowPartSearch(true)}
              className="inline-flex items-center gap-1.5 rounded-lg bg-primary px-3 py-1.5 text-xs font-medium text-white shadow-sm hover:bg-primary/90 transition-colors min-h-[36px]"
            >
              <Plus className="h-3.5 w-3.5" />
              Add Part
            </button>
          </div>

          {lines.length === 0 ? (
            <div className="rounded-lg border-2 border-dashed border-gray-300 dark:border-gray-600 bg-gray-50 dark:bg-gray-800/50 py-8 text-center">
              <Package className="mx-auto h-8 w-8 text-gray-400 dark:text-gray-500 mb-2" />
              <p className="text-sm text-gray-500 dark:text-gray-400">
                No items added yet. Click "Add Part" to begin.
              </p>
            </div>
          ) : (
            <div className="space-y-3">
              {lines.map((line, idx) => (
                <ReturnLineCard
                  key={`${line.part_id}-${idx}`}
                  line={line}
                  index={idx}
                  returnType={returnType}
                  onUpdate={updateLine}
                  onRemove={removeLine}
                />
              ))}
            </div>
          )}
        </div>

        {/* ── Submit ───────────────────────────────────────────── */}
        <div className="flex items-center justify-between pt-2 border-t border-gray-200 dark:border-gray-700">
          <Link
            to="/orders/returns"
            className="text-sm text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-200 transition-colors min-h-[44px] inline-flex items-center"
          >
            Cancel
          </Link>
          <button
            type="button"
            onClick={handleSubmit}
            disabled={createMutation.isPending}
            className="inline-flex items-center gap-2 rounded-lg bg-primary px-5 py-2 text-sm font-medium text-white shadow-sm hover:bg-primary/90 disabled:opacity-50 transition-colors min-h-[44px]"
          >
            {createMutation.isPending ? (
              <Loader2 className="h-4 w-4 animate-spin" />
            ) : (
              <RotateCcw className="h-4 w-4" />
            )}
            Create Return
          </button>
        </div>
      </div>

      {/* ── Part Search Modal ──────────────────────────────────── */}
      {showPartSearch && (
        <PartSearchModal
          isOpen={showPartSearch}
          onSelect={handleAddPart}
          onClose={() => setShowPartSearch(false)}
          excludePartIds={lines.map((l) => l.part_id)}
        />
      )}
    </div>
  );
}


// ═══════════════════════════════════════════════════════════════════
// INTERNAL: ReturnLineCard
// ═══════════════════════════════════════════════════════════════════

interface ReturnLineCardProps {
  line: ReturnFormLine;
  index: number;
  returnType: ReturnType;
  onUpdate: <K extends keyof ReturnFormLine>(idx: number, field: K, value: ReturnFormLine[K]) => void;
  onRemove: (idx: number) => void;
}

function ReturnLineCard({ line, index, returnType: _returnType, onUpdate, onRemove }: ReturnLineCardProps) {
  return (
    <div className="rounded-lg border border-gray-200 dark:border-gray-700 bg-gray-50 dark:bg-gray-800/50 p-4 space-y-3">
      {/* Header: part info + remove */}
      <div className="flex items-start justify-between gap-3">
        <div className="flex items-center gap-2 flex-wrap min-w-0">
          <span className="text-xs font-mono bg-gray-200 dark:bg-gray-700 text-gray-600 dark:text-gray-300 px-1.5 py-0.5 rounded">
            {line.part_code}
          </span>
          <span className="text-sm font-medium text-gray-900 dark:text-gray-100 truncate">
            {line.part_name}
          </span>
        </div>
        <button
          type="button"
          onClick={() => onRemove(index)}
          className="text-gray-400 hover:text-red-500 transition-colors p-1"
          title="Remove line"
        >
          <Trash2 className="h-4 w-4" />
        </button>
      </div>

      {/* Fields grid */}
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
        {/* Qty */}
        <div className="space-y-1">
          <label className="block text-xs font-medium text-gray-600 dark:text-gray-400">
            Qty *
          </label>
          <input
            type="number"
            min={1}
            value={line.qty}
            onChange={(e) => onUpdate(index, 'qty', Math.max(1, Number(e.target.value) || 1))}
            className="block w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-1.5 text-sm text-gray-900 dark:text-gray-100 tabular-nums focus:outline-none focus:ring-2 focus:ring-primary-300 transition-colors"
          />
        </div>

        {/* Condition */}
        <div className="space-y-1">
          <label className="block text-xs font-medium text-gray-600 dark:text-gray-400">
            Condition
          </label>
          <select
            value={line.condition}
            onChange={(e) => onUpdate(index, 'condition', e.target.value as ItemCondition)}
            className="block w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-2 py-1.5 text-sm text-gray-900 dark:text-gray-100 focus:outline-none focus:ring-2 focus:ring-primary-300 transition-colors"
          >
            {(Object.entries(CONDITION_LABELS) as [ItemCondition, string][]).map(
              ([val, label]) => (
                <option key={val} value={val}>
                  {label}
                </option>
              ),
            )}
          </select>
        </div>

        {/* Disposition */}
        <div className="space-y-1">
          <label className="block text-xs font-medium text-gray-600 dark:text-gray-400">
            Disposition
          </label>
          <select
            value={line.disposition}
            onChange={(e) =>
              onUpdate(index, 'disposition', e.target.value as DispositionType)
            }
            className="block w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-2 py-1.5 text-sm text-gray-900 dark:text-gray-100 focus:outline-none focus:ring-2 focus:ring-primary-300 transition-colors"
          >
            {(Object.entries(DISPOSITION_LABELS) as [DispositionType, string][]).map(
              ([val, label]) => (
                <option key={val} value={val}>
                  {label}
                </option>
              ),
            )}
          </select>
        </div>

        {/* Unit Cost */}
        <div className="space-y-1">
          <label className="block text-xs font-medium text-gray-600 dark:text-gray-400">
            Unit Cost
          </label>
          <input
            type="number"
            min={0}
            step={0.01}
            value={line.unit_cost ?? ''}
            onChange={(e) =>
              onUpdate(
                index,
                'unit_cost',
                e.target.value ? Number(e.target.value) : null,
              )
            }
            placeholder="$0.00"
            className="block w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-1.5 text-sm text-gray-900 dark:text-gray-100 tabular-nums placeholder:text-gray-400 dark:placeholder:text-gray-500 focus:outline-none focus:ring-2 focus:ring-primary-300 transition-colors"
          />
        </div>
      </div>

      {/* Line notes */}
      <input
        type="text"
        value={line.notes}
        onChange={(e) => onUpdate(index, 'notes', e.target.value)}
        placeholder="Line notes (optional)…"
        className="block w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-1.5 text-xs text-gray-900 dark:text-gray-100 placeholder:text-gray-400 dark:placeholder:text-gray-500 focus:outline-none focus:ring-2 focus:ring-primary-300 transition-colors"
      />
    </div>
  );
}
