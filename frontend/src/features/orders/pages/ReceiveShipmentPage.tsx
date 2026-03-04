/**
 * ReceiveShipmentPage — three-step receiving wizard for incoming deliveries.
 *
 * Step 1: Select PO — choose from POs that have receivable items
 * Step 2: Receive Items — enter quantities for each line, select staging zone
 * Step 3: Review & Confirm — summary of what will be received
 *
 * The wizard tracks per-line receiving quantities and supports partial
 * deliveries (receiving fewer items than ordered). After confirmation,
 * calls receiveByPO() which updates inventory and PO status.
 */

import { useState, useMemo } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  ArrowLeft,
  Truck,
  Package,
  CheckCircle2,
  ChevronRight,
  ChevronLeft,
  Loader2,
  AlertCircle,
  Search,
  MapPin,
} from 'lucide-react';
import { Input } from '../../../components/ui/Input';
import { EmptyState } from '../../../components/ui/EmptyState';
import { listPOs, getPO, receiveByPO, listStagingZones } from '../../../api/orders';
import type {
  POListItem,
  POResponse,
  POLineResponse,
  StagingZoneResponse,
  ReceiveByPO,
} from '../../../lib/types';


// ── Per-line receiving state ──────────────────────────────────────
interface ReceivingLine {
  po_line_id: number;
  part_number: string | null;
  part_description: string | null;
  qty_ordered: number;
  qty_previously_received: number;
  qty_remaining: number;
  qty_receiving_now: number;
  actual_cost: number | null;
  notes: string;
}


export function ReceiveShipmentPage() {
  const navigate = useNavigate();
  const queryClient = useQueryClient();

  // ── Wizard step (1, 2, or 3) ──────────────────────────────────
  const [step, setStep] = useState<1 | 2 | 3>(1);

  // ── Step 1 state ──────────────────────────────────────────────
  const [selectedPOId, setSelectedPOId] = useState<number | null>(null);
  const [poSearch, setPOSearch] = useState('');

  // ── Step 2 state ──────────────────────────────────────────────
  const [receivingLines, setReceivingLines] = useState<ReceivingLine[]>([]);
  const [stagingZoneId, setStagingZoneId] = useState<number | ''>('');
  const [receiveNotes, setReceiveNotes] = useState('');

  // ── Error state ───────────────────────────────────────────────
  const [validationError, setValidationError] = useState('');

  // ── Fetch receivable POs (submitted, acknowledged, partially_received)
  const { data: poList = [], isLoading: posLoading } = useQuery({
    queryKey: ['pos-receivable'],
    queryFn: () => listPOs({ status: 'submitted,acknowledged,partially_received' }),
  });

  // ── Fetch selected PO details (with lines) ───────────────────
  const { data: selectedPO, isLoading: poDetailLoading } = useQuery({
    queryKey: ['po-detail', selectedPOId],
    queryFn: () => getPO(selectedPOId!),
    enabled: selectedPOId !== null,
  });

  // ── Fetch staging zones ───────────────────────────────────────
  const { data: stagingZones = [] } = useQuery({
    queryKey: ['staging-zones'],
    queryFn: listStagingZones,
  });

  // ── Receive mutation ──────────────────────────────────────────
  const receiveMutation = useMutation({
    mutationFn: receiveByPO,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['pos'] });
      queryClient.invalidateQueries({ queryKey: ['pos-receivable'] });
      queryClient.invalidateQueries({ queryKey: ['po-detail'] });
      navigate(`/orders/pos/${selectedPOId}`);
    },
    onError: (err: Error) => {
      setValidationError(err.message || 'Failed to receive shipment');
    },
  });

  // ── Filter PO list by search ──────────────────────────────────
  const filteredPOs = useMemo(() => {
    if (!poSearch.trim()) return poList;
    const q = poSearch.toLowerCase();
    return poList.filter(
      (po: POListItem) =>
        po.po_number.toLowerCase().includes(q) ||
        (po.supplier_name ?? '').toLowerCase().includes(q),
    );
  }, [poList, poSearch]);

  // ── Build receiving lines from PO detail ──────────────────────
  const initializeReceivingLines = (po: POResponse) => {
    const lines = (po.lines ?? [])
      .filter((l: POLineResponse) => l.status !== 'cancelled' && l.status !== 'received')
      .map((l: POLineResponse) => {
        const remaining = Math.max(0, l.qty_ordered - l.qty_received);
        return {
          po_line_id: l.id,
          part_number: l.part_number,
          part_description: l.part_description,
          qty_ordered: l.qty_ordered,
          qty_previously_received: l.qty_received,
          qty_remaining: remaining,
          qty_receiving_now: remaining, // Default: receive all remaining
          actual_cost: l.unit_cost,
          notes: '',
        };
      });
    setReceivingLines(lines);
  };

  // ── Step navigation ───────────────────────────────────────────
  const goToStep2 = () => {
    if (!selectedPO) return;
    initializeReceivingLines(selectedPO);
    setValidationError('');
    setStep(2);
  };

  const goToStep3 = () => {
    const hasQty = receivingLines.some((l) => l.qty_receiving_now > 0);
    if (!hasQty) {
      setValidationError('Please enter a quantity for at least one item.');
      return;
    }
    const badQty = receivingLines.find(
      (l) => l.qty_receiving_now < 0,
    );
    if (badQty) {
      setValidationError(
        `Quantity cannot be negative for "${badQty.part_description ?? badQty.part_number}".`,
      );
      return;
    }
    setValidationError('');
    setStep(3);
  };

  const handleConfirm = () => {
    // Build the payload — only include lines with qty > 0
    const items = receivingLines
      .filter((l) => l.qty_receiving_now > 0)
      .map((l) => ({
        po_line_id: l.po_line_id,
        qty_received: l.qty_receiving_now,
        actual_cost: l.actual_cost ?? undefined,
        staging_zone_id: stagingZoneId ? (stagingZoneId as number) : undefined,
        notes: l.notes.trim() || undefined,
      }));

    const payload: ReceiveByPO = {
      po_id: selectedPOId!,
      items,
    };

    receiveMutation.mutate(payload);
  };

  // ── Helpers ───────────────────────────────────────────────────
  const updateReceivingLine = (index: number, field: keyof ReceivingLine, value: unknown) => {
    setReceivingLines((prev) =>
      prev.map((line, i) => (i === index ? { ...line, [field]: value } : line)),
    );
  };

  const totalItemsReceiving = receivingLines.reduce(
    (sum, l) => sum + l.qty_receiving_now,
    0,
  );

  const linesWithQty = receivingLines.filter((l) => l.qty_receiving_now > 0);

  // ── Step indicator ────────────────────────────────────────────
  const steps = [
    { num: 1, label: 'Select PO' },
    { num: 2, label: 'Receive Items' },
    { num: 3, label: 'Review & Confirm' },
  ];

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
        Receive Shipment
      </h1>

      {/* ── Step Indicator ─────────────────────────────────────── */}
      <div className="flex items-center gap-2">
        {steps.map((s, idx) => (
          <div key={s.num} className="flex items-center gap-2">
            <div
              className={`flex items-center gap-2 px-3 py-1.5 rounded-full text-xs font-medium transition-colors ${
                step === s.num
                  ? 'bg-primary text-white'
                  : step > s.num
                    ? 'bg-green-100 dark:bg-green-900/30 text-green-700 dark:text-green-400'
                    : 'bg-gray-100 dark:bg-gray-700 text-gray-500 dark:text-gray-400'
              }`}
            >
              {step > s.num ? (
                <CheckCircle2 className="h-3.5 w-3.5" />
              ) : (
                <span>{s.num}</span>
              )}
              {s.label}
            </div>
            {idx < steps.length - 1 && (
              <ChevronRight className="h-4 w-4 text-gray-300 dark:text-gray-600" />
            )}
          </div>
        ))}
      </div>

      {/* ── Error banner ───────────────────────────────────────── */}
      {(validationError || receiveMutation.isError) && (
        <div className="flex items-start gap-3 p-3 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-lg">
          <AlertCircle className="h-5 w-5 text-red-500 flex-shrink-0 mt-0.5" />
          <p className="text-sm text-red-600 dark:text-red-400">
            {validationError || receiveMutation.error?.message}
          </p>
        </div>
      )}

      {/* ── Step Content ───────────────────────────────────────── */}
      <div className="rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 shadow-sm">
        {/* ═══════════════ STEP 1: Select PO ═══════════════ */}
        {step === 1 && (
          <div className="p-6 space-y-4">
            <h2 className="text-sm font-semibold text-gray-900 dark:text-gray-100">
              Select a Purchase Order to receive
            </h2>

            {/* Search */}
            <div className="relative">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-gray-400" />
              <input
                type="text"
                value={poSearch}
                onChange={(e) => setPOSearch(e.target.value)}
                placeholder="Search by PO number or supplier…"
                className="w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 pl-10 pr-4 py-2.5 text-sm text-gray-900 dark:text-gray-100 placeholder:text-gray-400 dark:placeholder:text-gray-500 focus:outline-none focus:ring-2 focus:ring-primary-300 focus:border-primary-500 transition-colors"
              />
            </div>

            {/* PO List */}
            {posLoading ? (
              <div className="flex items-center justify-center py-12">
                <Loader2 className="h-6 w-6 text-primary animate-spin" />
              </div>
            ) : filteredPOs.length === 0 ? (
              <EmptyState
                icon={<Truck className="h-10 w-10" />}
                title="No receivable POs"
                description={
                  poSearch
                    ? `No POs matching "${poSearch}" with items to receive.`
                    : 'No purchase orders are currently awaiting receipt. Submit a PO first.'
                }
                className="py-8"
              />
            ) : (
              <div className="space-y-2 max-h-[400px] overflow-y-auto">
                {filteredPOs.map((po: POListItem) => (
                  <button
                    key={po.id}
                    type="button"
                    onClick={() => {
                      setSelectedPOId(po.id);
                      setValidationError('');
                    }}
                    className={`w-full text-left px-4 py-3 rounded-lg border transition-colors ${
                      selectedPOId === po.id
                        ? 'border-primary bg-primary/5 dark:bg-primary/10 ring-2 ring-primary/30'
                        : 'border-gray-200 dark:border-gray-700 hover:bg-gray-50 dark:hover:bg-gray-700/50'
                    }`}
                  >
                    <div className="flex items-center justify-between gap-3">
                      <div className="flex-1 min-w-0">
                        <div className="flex items-center gap-2 flex-wrap">
                          <span className="text-sm font-semibold text-gray-900 dark:text-gray-100">
                            {po.po_number}
                          </span>
                          <StatusChip status={po.status} />
                        </div>
                        <p className="text-xs text-gray-500 dark:text-gray-400 mt-0.5">
                          {po.supplier_name ?? 'Unknown Supplier'}
                          {po.expected_delivery && (
                            <> &middot; Expected: {new Date(po.expected_delivery).toLocaleDateString()}</>
                          )}
                        </p>
                      </div>
                      <div className="text-right flex-shrink-0">
                        <p className="text-sm font-medium text-gray-900 dark:text-gray-100 tabular-nums">
                          {po.line_count} line{po.line_count !== 1 ? 's' : ''}
                        </p>
                        {po.total_cost > 0 && (
                          <p className="text-xs text-gray-500 dark:text-gray-400 tabular-nums">
                            ${po.total_cost.toLocaleString(undefined, {
                              minimumFractionDigits: 2,
                              maximumFractionDigits: 2,
                            })}
                          </p>
                        )}
                      </div>
                    </div>
                  </button>
                ))}
              </div>
            )}

            {/* Step 1 → 2 button */}
            <div className="flex justify-end pt-2">
              <button
                type="button"
                disabled={!selectedPOId || poDetailLoading}
                onClick={goToStep2}
                className="inline-flex items-center gap-2 rounded-lg bg-primary px-5 py-2 text-sm font-medium text-white shadow-sm hover:bg-primary/90 disabled:opacity-50 transition-colors min-h-[44px]"
              >
                {poDetailLoading && <Loader2 className="h-4 w-4 animate-spin" />}
                Continue
                <ChevronRight className="h-4 w-4" />
              </button>
            </div>
          </div>
        )}

        {/* ═══════════════ STEP 2: Receive Items ═══════════════ */}
        {step === 2 && selectedPO && (
          <div className="p-6 space-y-4">
            {/* PO summary bar */}
            <div className="flex items-center justify-between flex-wrap gap-2 pb-3 border-b border-gray-200 dark:border-gray-700">
              <div>
                <h2 className="text-sm font-semibold text-gray-900 dark:text-gray-100">
                  {selectedPO.po_number} — {selectedPO.supplier_name}
                </h2>
                {selectedPO.expected_delivery && (
                  <p className="text-xs text-gray-500 dark:text-gray-400">
                    Expected: {new Date(selectedPO.expected_delivery).toLocaleDateString()}
                  </p>
                )}
              </div>
              <div className="text-right">
                <p className="text-sm font-medium text-primary tabular-nums">
                  Receiving {totalItemsReceiving} item{totalItemsReceiving !== 1 ? 's' : ''}
                </p>
              </div>
            </div>

            {/* Staging zone selector */}
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <div className="space-y-1.5">
                <label
                  htmlFor="staging-zone"
                  className="block text-sm font-medium text-gray-700 dark:text-gray-300"
                >
                  <MapPin className="inline h-3.5 w-3.5 mr-1" />
                  Staging Zone
                </label>
                <select
                  id="staging-zone"
                  value={stagingZoneId}
                  onChange={(e) =>
                    setStagingZoneId(e.target.value ? Number(e.target.value) : '')
                  }
                  className="block w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm text-gray-900 dark:text-gray-100 focus:outline-none focus:ring-2 focus:ring-primary-300 focus:border-primary-500 transition-colors min-h-[44px]"
                >
                  <option value="">No staging zone (direct to warehouse)</option>
                  {stagingZones
                    .filter((z: StagingZoneResponse) => z.is_active)
                    .map((z: StagingZoneResponse) => (
                      <option key={z.id} value={z.id}>
                        {z.label}
                        {z.job_name ? ` (${z.job_name})` : ''}
                        {z.zone_type !== 'general' ? ` — ${z.zone_type}` : ''}
                      </option>
                    ))}
                </select>
              </div>

              <div className="space-y-1.5">
                <label
                  htmlFor="receive-notes"
                  className="block text-sm font-medium text-gray-700 dark:text-gray-300"
                >
                  Notes
                </label>
                <input
                  id="receive-notes"
                  type="text"
                  value={receiveNotes}
                  onChange={(e) => setReceiveNotes(e.target.value)}
                  placeholder="Optional delivery notes…"
                  className="block w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm text-gray-900 dark:text-gray-100 placeholder:text-gray-400 dark:placeholder:text-gray-500 focus:outline-none focus:ring-2 focus:ring-primary-300 focus:border-primary-500 transition-colors min-h-[44px]"
                />
              </div>
            </div>

            {/* Receiving lines */}
            {receivingLines.length === 0 ? (
              <EmptyState
                icon={<Package className="h-10 w-10" />}
                title="All items received"
                description="Every line on this PO has been fully received."
                className="py-8"
              />
            ) : (
              <div className="space-y-3">
                {/* Table header (desktop) */}
                <div className="hidden sm:grid sm:grid-cols-12 gap-3 px-4 text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider">
                  <div className="col-span-4">Part</div>
                  <div className="col-span-2 text-center">Ordered</div>
                  <div className="col-span-2 text-center">Prev. Received</div>
                  <div className="col-span-2 text-center">Receiving Now</div>
                  <div className="col-span-2">Notes</div>
                </div>

                {receivingLines.map((line, idx) => (
                  <ReceiveLineRow
                    key={line.po_line_id}
                    line={line}
                    index={idx}
                    onUpdate={updateReceivingLine}
                  />
                ))}
              </div>
            )}

            {/* Step 2 nav */}
            <div className="flex items-center justify-between pt-2">
              <button
                type="button"
                onClick={() => { setStep(1); setValidationError(''); }}
                className="inline-flex items-center gap-1.5 rounded-lg border border-gray-300 dark:border-gray-600 px-4 py-2 text-sm font-medium text-gray-700 dark:text-gray-300 hover:bg-gray-50 dark:hover:bg-gray-700 transition-colors min-h-[44px]"
              >
                <ChevronLeft className="h-4 w-4" />
                Back
              </button>
              <button
                type="button"
                onClick={goToStep3}
                disabled={totalItemsReceiving === 0}
                className="inline-flex items-center gap-2 rounded-lg bg-primary px-5 py-2 text-sm font-medium text-white shadow-sm hover:bg-primary/90 disabled:opacity-50 transition-colors min-h-[44px]"
              >
                Review
                <ChevronRight className="h-4 w-4" />
              </button>
            </div>
          </div>
        )}

        {/* ═══════════════ STEP 3: Review & Confirm ═══════════════ */}
        {step === 3 && selectedPO && (
          <div className="p-6 space-y-4">
            <h2 className="text-sm font-semibold text-gray-900 dark:text-gray-100">
              Review Receipt
            </h2>

            {/* Summary card */}
            <div className="rounded-lg border border-gray-200 dark:border-gray-700 bg-gray-50 dark:bg-gray-800/50 p-4 space-y-3">
              <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 text-sm">
                <div>
                  <p className="text-xs text-gray-500 dark:text-gray-400">PO Number</p>
                  <p className="font-medium text-gray-900 dark:text-gray-100">
                    {selectedPO.po_number}
                  </p>
                </div>
                <div>
                  <p className="text-xs text-gray-500 dark:text-gray-400">Supplier</p>
                  <p className="font-medium text-gray-900 dark:text-gray-100">
                    {selectedPO.supplier_name}
                  </p>
                </div>
                <div>
                  <p className="text-xs text-gray-500 dark:text-gray-400">Items Receiving</p>
                  <p className="font-medium text-gray-900 dark:text-gray-100 tabular-nums">
                    {linesWithQty.length} line{linesWithQty.length !== 1 ? 's' : ''},{' '}
                    {totalItemsReceiving} unit{totalItemsReceiving !== 1 ? 's' : ''}
                  </p>
                </div>
                <div>
                  <p className="text-xs text-gray-500 dark:text-gray-400">Staging Zone</p>
                  <p className="font-medium text-gray-900 dark:text-gray-100">
                    {stagingZoneId
                      ? stagingZones.find((z: StagingZoneResponse) => z.id === stagingZoneId)?.label ?? 'Unknown'
                      : 'Direct to warehouse'}
                  </p>
                </div>
              </div>
            </div>

            {/* Items being received */}
            <div className="space-y-2">
              <h3 className="text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider">
                Items Being Received
              </h3>
              <div className="rounded-lg border border-gray-200 dark:border-gray-700 divide-y divide-gray-200 dark:divide-gray-700">
                {linesWithQty.map((line) => (
                  <div
                    key={line.po_line_id}
                    className="flex items-center justify-between gap-3 px-4 py-3"
                  >
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2 flex-wrap">
                        {line.part_number && (
                          <span className="text-xs font-mono bg-gray-200 dark:bg-gray-700 text-gray-600 dark:text-gray-300 px-1.5 py-0.5 rounded">
                            {line.part_number}
                          </span>
                        )}
                        <span className="text-sm text-gray-900 dark:text-gray-100">
                          {line.part_description ?? `Line #${line.po_line_id}`}
                        </span>
                      </div>
                      {line.notes && (
                        <p className="text-xs text-gray-500 dark:text-gray-400 mt-0.5">
                          {line.notes}
                        </p>
                      )}
                    </div>
                    <div className="flex-shrink-0 text-right">
                      <span className="text-sm font-semibold text-primary tabular-nums">
                        +{line.qty_receiving_now}
                      </span>
                      <span className="text-xs text-gray-500 dark:text-gray-400 ml-1">
                        of {line.qty_ordered}
                      </span>
                    </div>
                  </div>
                ))}
              </div>
            </div>

            {/* Skipped items (qty = 0) */}
            {receivingLines.filter((l) => l.qty_receiving_now === 0).length > 0 && (
              <div className="space-y-2">
                <h3 className="text-xs font-medium text-amber-600 dark:text-amber-400 uppercase tracking-wider">
                  Not Receiving ({receivingLines.filter((l) => l.qty_receiving_now === 0).length} items)
                </h3>
                <div className="rounded-lg border border-amber-200 dark:border-amber-800 bg-amber-50 dark:bg-amber-900/10 px-4 py-2">
                  <ul className="text-xs text-amber-700 dark:text-amber-400 space-y-1">
                    {receivingLines
                      .filter((l) => l.qty_receiving_now === 0)
                      .map((line) => (
                        <li key={line.po_line_id}>
                          {line.part_number ?? line.part_description ?? `Line #${line.po_line_id}`}
                          {' '}&mdash; {line.qty_remaining} remaining
                        </li>
                      ))}
                  </ul>
                </div>
              </div>
            )}

            {/* Step 3 nav */}
            <div className="flex items-center justify-between pt-2">
              <button
                type="button"
                onClick={() => { setStep(2); setValidationError(''); }}
                className="inline-flex items-center gap-1.5 rounded-lg border border-gray-300 dark:border-gray-600 px-4 py-2 text-sm font-medium text-gray-700 dark:text-gray-300 hover:bg-gray-50 dark:hover:bg-gray-700 transition-colors min-h-[44px]"
              >
                <ChevronLeft className="h-4 w-4" />
                Back
              </button>
              <button
                type="button"
                onClick={handleConfirm}
                disabled={receiveMutation.isPending}
                className="inline-flex items-center gap-2 rounded-lg bg-green-600 px-5 py-2 text-sm font-medium text-white shadow-sm hover:bg-green-700 disabled:opacity-50 transition-colors min-h-[44px]"
              >
                {receiveMutation.isPending ? (
                  <Loader2 className="h-4 w-4 animate-spin" />
                ) : (
                  <CheckCircle2 className="h-4 w-4" />
                )}
                Confirm Receipt
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}


// ═══════════════════════════════════════════════════════════════════
// INTERNAL: ReceiveLineRow
// ═══════════════════════════════════════════════════════════════════

interface ReceiveLineRowProps {
  line: ReceivingLine;
  index: number;
  onUpdate: (index: number, field: keyof ReceivingLine, value: unknown) => void;
}

function ReceiveLineRow({ line, index, onUpdate }: ReceiveLineRowProps) {
  return (
    <div className="rounded-lg border border-gray-200 dark:border-gray-700 bg-gray-50 dark:bg-gray-800/50 p-4">
      {/* Desktop: grid layout */}
      <div className="hidden sm:grid sm:grid-cols-12 gap-3 items-center">
        {/* Part info */}
        <div className="col-span-4 min-w-0">
          <div className="flex items-center gap-2 flex-wrap">
            {line.part_number && (
              <span className="text-xs font-mono bg-gray-200 dark:bg-gray-700 text-gray-600 dark:text-gray-300 px-1.5 py-0.5 rounded">
                {line.part_number}
              </span>
            )}
            <span className="text-sm font-medium text-gray-900 dark:text-gray-100 truncate">
              {line.part_description ?? `Line #${line.po_line_id}`}
            </span>
          </div>
        </div>

        {/* Ordered */}
        <div className="col-span-2 text-center">
          <span className="text-sm text-gray-900 dark:text-gray-100 tabular-nums">
            {line.qty_ordered}
          </span>
        </div>

        {/* Previously received */}
        <div className="col-span-2 text-center">
          <span className="text-sm text-gray-500 dark:text-gray-400 tabular-nums">
            {line.qty_previously_received}
          </span>
        </div>

        {/* Receiving now */}
        <div className="col-span-2">
          <input
            type="number"
            min={0}
            max={line.qty_remaining + 50} // Allow slight overage
            value={line.qty_receiving_now}
            onChange={(e) =>
              onUpdate(index, 'qty_receiving_now', Math.max(0, Number(e.target.value) || 0))
            }
            className={`w-full rounded-lg border px-3 py-1.5 text-sm text-center tabular-nums focus:outline-none focus:ring-2 focus:ring-primary-300 transition-colors ${
              line.qty_receiving_now > line.qty_remaining
                ? 'border-amber-400 dark:border-amber-600 bg-amber-50 dark:bg-amber-900/20'
                : line.qty_receiving_now > 0
                  ? 'border-green-300 dark:border-green-700 bg-green-50 dark:bg-green-900/20'
                  : 'border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800'
            }`}
          />
          {line.qty_receiving_now > line.qty_remaining && (
            <p className="text-xs text-amber-600 dark:text-amber-400 mt-0.5 text-center">
              Over by {line.qty_receiving_now - line.qty_remaining}
            </p>
          )}
        </div>

        {/* Notes */}
        <div className="col-span-2">
          <input
            type="text"
            value={line.notes}
            onChange={(e) => onUpdate(index, 'notes', e.target.value)}
            placeholder="Notes…"
            className="w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-2 py-1.5 text-xs text-gray-900 dark:text-gray-100 placeholder:text-gray-400 dark:placeholder:text-gray-500 focus:outline-none focus:ring-2 focus:ring-primary-300 transition-colors"
          />
        </div>
      </div>

      {/* Mobile: stacked layout */}
      <div className="sm:hidden space-y-3">
        <div className="flex items-center gap-2 flex-wrap">
          {line.part_number && (
            <span className="text-xs font-mono bg-gray-200 dark:bg-gray-700 text-gray-600 dark:text-gray-300 px-1.5 py-0.5 rounded">
              {line.part_number}
            </span>
          )}
          <span className="text-sm font-medium text-gray-900 dark:text-gray-100">
            {line.part_description ?? `Line #${line.po_line_id}`}
          </span>
        </div>

        <div className="grid grid-cols-3 gap-2 text-center">
          <div>
            <p className="text-xs text-gray-500 dark:text-gray-400">Ordered</p>
            <p className="text-sm font-medium text-gray-900 dark:text-gray-100 tabular-nums">
              {line.qty_ordered}
            </p>
          </div>
          <div>
            <p className="text-xs text-gray-500 dark:text-gray-400">Received</p>
            <p className="text-sm text-gray-500 dark:text-gray-400 tabular-nums">
              {line.qty_previously_received}
            </p>
          </div>
          <div>
            <p className="text-xs text-gray-500 dark:text-gray-400">Remaining</p>
            <p className="text-sm text-gray-900 dark:text-gray-100 tabular-nums">
              {line.qty_remaining}
            </p>
          </div>
        </div>

        <div className="grid grid-cols-2 gap-3">
          <Input
            label="Receiving Now"
            type="number"
            min={0}
            value={line.qty_receiving_now}
            onChange={(e) =>
              onUpdate(index, 'qty_receiving_now', Math.max(0, Number(e.target.value) || 0))
            }
          />
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


// ═══════════════════════════════════════════════════════════════════
// INTERNAL: StatusChip — small PO status badge
// ═══════════════════════════════════════════════════════════════════

function StatusChip({ status }: { status: string }) {
  const colors: Record<string, string> = {
    submitted: 'bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-400',
    acknowledged: 'bg-indigo-100 text-indigo-700 dark:bg-indigo-900/30 dark:text-indigo-400',
    partially_received: 'bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-400',
  };

  return (
    <span
      className={`inline-block rounded-full px-2 py-0.5 text-xs font-medium ${
        colors[status] ?? 'bg-gray-100 text-gray-600 dark:bg-gray-700 dark:text-gray-400'
      }`}
    >
      {status.replace(/_/g, ' ')}
    </span>
  );
}
