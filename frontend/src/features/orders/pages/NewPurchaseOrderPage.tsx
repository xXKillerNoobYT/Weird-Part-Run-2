/**
 * NewPurchaseOrderPage — create a standalone Warehouse Purchase Order (PO).
 *
 * This form creates a PO directly (not from a JPO). Used for:
 *   - Warehouse restocking
 *   - Bulk orders
 *   - Special orders
 *
 * Layout: supplier selector, delivery/notes, line items with prices,
 * running subtotal, save as draft.
 */

import { useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  ArrowLeft,
  Plus,
  Trash2,
  ShoppingCart,
  Loader2,
  AlertCircle,
} from 'lucide-react';
import { Input } from '../../../components/ui/Input';
import { EmptyState } from '../../../components/ui/EmptyState';
import { PartSearchModal } from '../components/PartSearchModal';
import { listSuppliers } from '../../../api/parts';
import { createPO } from '../../../api/orders';
import type { PartListItem, Supplier } from '../../../lib/types';

// ── Local line item shape ─────────────────────────────────────────
interface POFormLine {
  part_id: number;
  part_code: string | null;
  part_name: string;
  unit_of_measure: string;
  qty_ordered: number;
  unit_cost: number;
  notes: string;
}

export function NewPurchaseOrderPage() {
  const navigate = useNavigate();
  const queryClient = useQueryClient();

  // ── Form state ──────────────────────────────────────────────────
  const [supplierId, setSupplierId] = useState<number | ''>('');
  const [expectedDelivery, setExpectedDelivery] = useState('');
  const [shippingMethod, setShippingMethod] = useState('');
  const [notes, setNotes] = useState('');
  const [lines, setLines] = useState<POFormLine[]>([]);
  const [showPartSearch, setShowPartSearch] = useState(false);
  const [validationError, setValidationError] = useState('');

  // ── Fetch suppliers ─────────────────────────────────────────────
  const { data: suppliers = [], isLoading: suppliersLoading } = useQuery({
    queryKey: ['suppliers-active'],
    queryFn: () => listSuppliers({ is_active: true }),
  });

  // ── Create PO mutation ──────────────────────────────────────────
  const createMutation = useMutation({
    mutationFn: createPO,
    onSuccess: (po) => {
      queryClient.invalidateQueries({ queryKey: ['pos'] });
      navigate(`/orders/pos/${po.id}`);
    },
    onError: (err: Error) => {
      setValidationError(err.message || 'Failed to create purchase order');
    },
  });

  // ── Add a part ──────────────────────────────────────────────────
  const handleAddPart = (part: PartListItem) => {
    if (lines.some((l) => l.part_id === part.id)) return;
    setLines((prev) => [
      ...prev,
      {
        part_id: part.id,
        part_code: part.code,
        part_name: part.name,
        unit_of_measure: part.unit_of_measure,
        qty_ordered: 1,
        unit_cost: part.company_cost_price ?? 0,
        notes: '',
      },
    ]);
  };

  // ── Update a line field ─────────────────────────────────────────
  const updateLine = <K extends keyof POFormLine>(
    index: number,
    field: K,
    value: POFormLine[K],
  ) => {
    setLines((prev) =>
      prev.map((line, i) => (i === index ? { ...line, [field]: value } : line)),
    );
  };

  // ── Remove a line ───────────────────────────────────────────────
  const removeLine = (index: number) => {
    setLines((prev) => prev.filter((_, i) => i !== index));
  };

  // ── Compute subtotal ────────────────────────────────────────────
  const subtotal = lines.reduce(
    (sum, l) => sum + l.qty_ordered * l.unit_cost,
    0,
  );

  // ── Validate & submit ───────────────────────────────────────────
  const handleSubmit = () => {
    if (!supplierId) {
      setValidationError('Please select a supplier.');
      return;
    }
    if (lines.length === 0) {
      setValidationError('Please add at least one part.');
      return;
    }
    const badQty = lines.find((l) => l.qty_ordered < 1);
    if (badQty) {
      setValidationError(`Quantity must be at least 1 for "${badQty.part_name}".`);
      return;
    }

    setValidationError('');

    createMutation.mutate({
      supplier_id: supplierId as number,
      expected_delivery: expectedDelivery || undefined,
      shipping_method: shippingMethod.trim() || undefined,
      notes: notes.trim() || undefined,
      lines: lines.map((l) => ({
        part_id: l.part_id,
        qty_ordered: l.qty_ordered,
        unit_cost: l.unit_cost || undefined,
        notes: l.notes.trim() || undefined,
      })),
    });
  };

  const excludePartIds = lines.map((l) => l.part_id);

  return (
    <div className="space-y-4">
      {/* ── Back link ──────────────────────────────────────────── */}
      <Link
        to="/orders/purchase-orders"
        className="inline-flex items-center gap-1.5 text-sm text-gray-500 dark:text-gray-400 hover:text-primary transition-colors min-h-[44px]"
      >
        <ArrowLeft className="h-4 w-4" />
        Back to Warehouse Purchase Orders
      </Link>

      {/* ── Header ─────────────────────────────────────────────── */}
      <h1 className="text-xl font-semibold text-gray-900 dark:text-gray-100">
        New Warehouse Purchase Order
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

      {/* ── Form card ──────────────────────────────────────────── */}
      <div className="rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 shadow-sm">
        <div className="p-6 space-y-6">
          {/* ── Row 1: Supplier + Expected Delivery ──────────── */}
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div className="space-y-1.5">
              <label
                htmlFor="po-supplier"
                className="block text-sm font-medium text-gray-700 dark:text-gray-300"
              >
                Supplier <span className="text-red-500">*</span>
              </label>
              <select
                id="po-supplier"
                value={supplierId}
                onChange={(e) => {
                  setSupplierId(e.target.value ? Number(e.target.value) : '');
                  setValidationError('');
                }}
                className="block w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm text-gray-900 dark:text-gray-100 focus:outline-none focus:ring-2 focus:ring-primary-300 focus:border-primary-500 transition-colors min-h-[44px]"
              >
                <option value="">
                  {suppliersLoading ? 'Loading suppliers…' : 'Select a supplier'}
                </option>
                {suppliers.map((s: Supplier) => (
                  <option key={s.id} value={s.id}>
                    {s.name}
                  </option>
                ))}
              </select>
            </div>

            <Input
              label="Expected Delivery"
              type="date"
              value={expectedDelivery}
              onChange={(e) => setExpectedDelivery(e.target.value)}
            />
          </div>

          {/* ── Row 2: Shipping method + Notes ──────────────── */}
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <Input
              label="Shipping Method"
              value={shippingMethod}
              onChange={(e) => setShippingMethod(e.target.value)}
              placeholder="e.g. Ground, Express, Will Call"
            />
            <div className="space-y-1.5">
              <label
                htmlFor="po-notes"
                className="block text-sm font-medium text-gray-700 dark:text-gray-300"
              >
                Notes
              </label>
              <textarea
                id="po-notes"
                value={notes}
                onChange={(e) => setNotes(e.target.value)}
                rows={2}
                placeholder="Optional notes for this PO…"
                className="block w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm text-gray-900 dark:text-gray-100 placeholder:text-gray-400 dark:placeholder:text-gray-500 focus:outline-none focus:ring-2 focus:ring-primary-300 focus:border-primary-500 transition-colors resize-y"
              />
            </div>
          </div>

          {/* ── Line Items ─────────────────────────────────── */}
          <div>
            <div className="flex items-center justify-between mb-3">
              <h2 className="text-sm font-semibold text-gray-900 dark:text-gray-100">
                Line Items ({lines.length})
              </h2>
              <button
                type="button"
                onClick={() => setShowPartSearch(true)}
                className="inline-flex items-center gap-1.5 rounded-lg bg-primary px-3 py-1.5 text-sm font-medium text-white shadow-sm hover:bg-primary/90 transition-colors min-h-[36px]"
              >
                <Plus className="h-4 w-4" />
                Add Part
              </button>
            </div>

            {lines.length === 0 && (
              <EmptyState
                icon={<ShoppingCart className="h-10 w-10" />}
                title="No line items"
                description="Click 'Add Part' to add parts to this purchase order."
                className="py-8 border border-dashed border-gray-300 dark:border-gray-600 rounded-lg"
              />
            )}

            <div className="space-y-3">
              {lines.map((line, idx) => (
                <POLineCard
                  key={line.part_id}
                  line={line}
                  index={idx}
                  onUpdate={updateLine}
                  onRemove={removeLine}
                />
              ))}
            </div>

            {/* Subtotal */}
            {lines.length > 0 && (
              <div className="mt-4 flex justify-end">
                <div className="text-right">
                  <span className="text-sm text-gray-500 dark:text-gray-400">
                    Subtotal:{' '}
                  </span>
                  <span className="text-lg font-semibold text-gray-900 dark:text-gray-100 tabular-nums">
                    ${subtotal.toLocaleString(undefined, {
                      minimumFractionDigits: 2,
                      maximumFractionDigits: 2,
                    })}
                  </span>
                </div>
              </div>
            )}
          </div>
        </div>

        {/* ── Footer actions ───────────────────────────────────── */}
        <div className="px-6 py-4 border-t border-gray-200 dark:border-gray-700 flex items-center justify-end gap-3">
          <Link
            to="/orders/purchase-orders"
            className="rounded-lg border border-gray-300 dark:border-gray-600 px-4 py-2 text-sm font-medium text-gray-700 dark:text-gray-300 hover:bg-gray-50 dark:hover:bg-gray-700 transition-colors min-h-[44px] flex items-center"
          >
            Cancel
          </Link>
          <button
            type="button"
            onClick={handleSubmit}
            disabled={createMutation.isPending}
            className="inline-flex items-center gap-2 rounded-lg bg-primary px-5 py-2 text-sm font-medium text-white shadow-sm hover:bg-primary/90 disabled:opacity-50 transition-colors min-h-[44px]"
          >
            {createMutation.isPending && (
              <Loader2 className="h-4 w-4 animate-spin" />
            )}
            Save as Draft
          </button>
        </div>
      </div>

      {/* ── Part Search Modal ──────────────────────────────────── */}
      <PartSearchModal
        isOpen={showPartSearch}
        onClose={() => setShowPartSearch(false)}
        onSelect={handleAddPart}
        excludePartIds={excludePartIds}
      />
    </div>
  );
}


// ═══════════════════════════════════════════════════════════════════
// INTERNAL: POLineCard
// ═══════════════════════════════════════════════════════════════════

interface POLineCardProps {
  line: POFormLine;
  index: number;
  onUpdate: <K extends keyof POFormLine>(
    index: number,
    field: K,
    value: POFormLine[K],
  ) => void;
  onRemove: (index: number) => void;
}

function POLineCard({ line, index, onUpdate, onRemove }: POLineCardProps) {
  const lineTotal = line.qty_ordered * line.unit_cost;

  return (
    <div className="rounded-lg border border-gray-200 dark:border-gray-700 bg-gray-50 dark:bg-gray-800/50 p-4">
      {/* Part identity + remove */}
      <div className="flex items-start justify-between gap-3 mb-3">
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 flex-wrap">
            {line.part_code && (
              <span className="text-xs font-mono bg-gray-200 dark:bg-gray-700 text-gray-600 dark:text-gray-300 px-1.5 py-0.5 rounded">
                {line.part_code}
              </span>
            )}
            <span className="text-sm font-medium text-gray-900 dark:text-gray-100">
              {line.part_name}
            </span>
          </div>
        </div>
        <button
          type="button"
          onClick={() => onRemove(index)}
          className="p-2 rounded-lg text-gray-400 hover:text-red-500 hover:bg-red-50 dark:hover:bg-red-900/20 transition-colors min-h-[36px] min-w-[36px] flex items-center justify-center"
          title="Remove"
        >
          <Trash2 className="h-4 w-4" />
        </button>
      </div>

      {/* Editable fields */}
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
        <div>
          <Input
            label="Qty"
            type="number"
            min={1}
            value={line.qty_ordered}
            onChange={(e) =>
              onUpdate(index, 'qty_ordered', Math.max(1, Number(e.target.value) || 1))
            }
          />
        </div>

        <div>
          <Input
            label="Unit Cost ($)"
            type="number"
            min={0}
            step={0.01}
            value={line.unit_cost}
            onChange={(e) =>
              onUpdate(index, 'unit_cost', Math.max(0, Number(e.target.value) || 0))
            }
          />
        </div>

        <div className="space-y-1.5">
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300">
            Line Total
          </label>
          <div className="px-3 py-2 text-sm font-medium text-gray-900 dark:text-gray-100 tabular-nums">
            ${lineTotal.toLocaleString(undefined, {
              minimumFractionDigits: 2,
              maximumFractionDigits: 2,
            })}
          </div>
        </div>

        <div>
          <Input
            label="Notes"
            value={line.notes}
            onChange={(e) => onUpdate(index, 'notes', e.target.value)}
            placeholder="Optional"
          />
        </div>
      </div>
    </div>
  );
}
