/**
 * NewPartsRequestPage — create a new Job Parts Order (JPO).
 *
 * Three-area split layout (desktop):
 *   1. Left panel: Catalog Browser — persistent search + category filter
 *   2. Right panel: Order Lines — parts added to this draft
 *   3. Bottom section: Suggested Parts — low-stock quick-add chips
 *
 * On mobile: catalog browser is replaced with a button that opens
 * the PartSearchModal as a full-screen fallback.
 *
 * The backend API (POST /api/orders/jpos) and frontend function (createJPO)
 * already exist — this page is purely the form UI.
 */

import { useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  ArrowLeft,
  Plus,
  Trash2,
  Package,
  Loader2,
  AlertCircle,
} from 'lucide-react';
import { Input } from '../../../components/ui/Input';
import { EmptyState } from '../../../components/ui/EmptyState';
import { CatalogBrowser } from '../components/CatalogBrowser';
import { SuggestedParts } from '../components/SuggestedParts';
import { PartSearchModal } from '../components/PartSearchModal';
import { getActiveJobs } from '../../../api/jobs';
import { createJPO } from '../../../api/orders';
import type { PartListItem, JPOPriority, LinePriority } from '../../../lib/types';

// ── Form-local line item shape ────────────────────────────────────
interface JPOFormLine {
  part_id: number;
  part_code: string | null;
  part_name: string;
  unit_of_measure: string;
  total_stock: number;
  qty_requested: number;
  priority: LinePriority;
  notes: string;
}

export function NewPartsRequestPage() {
  const navigate = useNavigate();
  const queryClient = useQueryClient();

  // ── Form state ──────────────────────────────────────────────────
  const [jobId, setJobId] = useState<number | ''>('');
  const [priority, setPriority] = useState<JPOPriority>('normal');
  const [notes, setNotes] = useState('');
  const [lines, setLines] = useState<JPOFormLine[]>([]);
  const [showPartSearch, setShowPartSearch] = useState(false);
  const [validationError, setValidationError] = useState('');

  // ── Fetch active jobs for the selector ──────────────────────────
  const { data: jobs = [], isLoading: jobsLoading } = useQuery({
    queryKey: ['jobs-active'],
    queryFn: () => getActiveJobs(),
  });

  // ── Create JPO mutation ─────────────────────────────────────────
  const createMutation = useMutation({
    mutationFn: createJPO,
    onSuccess: (jpo) => {
      queryClient.invalidateQueries({ queryKey: ['jpos'] });
      navigate(`/orders/parts-requests/${jpo.id}`);
    },
    onError: (err: Error) => {
      setValidationError(err.message || 'Failed to create parts request');
    },
  });

  // ── Add a part from catalog browser / search modal / suggestions ─
  const handleAddPart = (part: PartListItem) => {
    // Prevent duplicates
    if (lines.some((l) => l.part_id === part.id)) return;

    setLines((prev) => [
      ...prev,
      {
        part_id: part.id,
        part_code: part.code,
        part_name: part.name,
        unit_of_measure: part.unit_of_measure,
        total_stock: part.total_stock,
        qty_requested: 1,
        priority: 'normal',
        notes: '',
      },
    ]);
  };

  // ── Update a field on a specific line ───────────────────────────
  const updateLine = <K extends keyof JPOFormLine>(
    index: number,
    field: K,
    value: JPOFormLine[K],
  ) => {
    setLines((prev) =>
      prev.map((line, i) => (i === index ? { ...line, [field]: value } : line)),
    );
  };

  // ── Remove a line ───────────────────────────────────────────────
  const removeLine = (index: number) => {
    setLines((prev) => prev.filter((_, i) => i !== index));
  };

  // ── Validate & submit ───────────────────────────────────────────
  const handleSubmit = () => {
    if (!jobId) {
      setValidationError('Please select a job.');
      return;
    }
    if (lines.length === 0) {
      setValidationError('Please add at least one part.');
      return;
    }
    const badQty = lines.find((l) => l.qty_requested < 1);
    if (badQty) {
      setValidationError(
        `Quantity must be at least 1 for "${badQty.part_name}".`,
      );
      return;
    }

    setValidationError('');

    createMutation.mutate({
      job_id: jobId as number,
      priority,
      notes: notes.trim() || undefined,
      lines: lines.map((l) => ({
        part_id: l.part_id,
        qty_requested: l.qty_requested,
        priority: l.priority,
        notes: l.notes.trim() || undefined,
      })),
    });
  };

  const excludePartIds = lines.map((l) => l.part_id);

  return (
    <div className="space-y-4">
      {/* ── Back link ──────────────────────────────────────────── */}
      <Link
        to="/orders/parts-requests"
        className="inline-flex items-center gap-1.5 text-sm text-gray-500 dark:text-gray-400 hover:text-primary transition-colors min-h-[44px]"
      >
        <ArrowLeft className="h-4 w-4" />
        Back to Parts Requests
      </Link>

      {/* ── Header ─────────────────────────────────────────────── */}
      <h1 className="text-xl font-semibold text-gray-900 dark:text-gray-100">
        New Parts Request
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
          {/* ── Row 1: Job selector + Priority ───────────────── */}
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div className="space-y-1.5">
              <label
                htmlFor="jpo-job"
                className="block text-sm font-medium text-gray-700 dark:text-gray-300"
              >
                Job <span className="text-red-500">*</span>
              </label>
              <select
                id="jpo-job"
                value={jobId}
                onChange={(e) => {
                  setJobId(e.target.value ? Number(e.target.value) : '');
                  setValidationError('');
                }}
                className="block w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm text-gray-900 dark:text-gray-100 focus:outline-none focus:ring-2 focus:ring-primary-300 focus:border-primary-500 transition-colors min-h-[44px]"
              >
                <option value="">
                  {jobsLoading ? 'Loading jobs…' : 'Select a job'}
                </option>
                {jobs.map((job) => (
                  <option key={job.id} value={job.id}>
                    {job.job_number} — {job.job_name} ({job.customer_name})
                  </option>
                ))}
              </select>
            </div>

            <div className="space-y-1.5">
              <label
                htmlFor="jpo-priority"
                className="block text-sm font-medium text-gray-700 dark:text-gray-300"
              >
                Priority
              </label>
              <select
                id="jpo-priority"
                value={priority}
                onChange={(e) => setPriority(e.target.value as JPOPriority)}
                className="block w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm text-gray-900 dark:text-gray-100 focus:outline-none focus:ring-2 focus:ring-primary-300 focus:border-primary-500 transition-colors min-h-[44px]"
              >
                <option value="normal">Normal</option>
                <option value="urgent">Urgent</option>
              </select>
            </div>
          </div>

          {/* ── Notes ────────────────────────────────────────── */}
          <div className="space-y-1.5">
            <label
              htmlFor="jpo-notes"
              className="block text-sm font-medium text-gray-700 dark:text-gray-300"
            >
              Notes
            </label>
            <textarea
              id="jpo-notes"
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
              rows={2}
              placeholder="Optional notes about this parts request…"
              className="block w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm text-gray-900 dark:text-gray-100 placeholder:text-gray-400 dark:placeholder:text-gray-500 focus:outline-none focus:ring-2 focus:ring-primary-300 focus:border-primary-500 transition-colors resize-y"
            />
          </div>

          {/* ── Three-Area Split: Catalog + Order Lines ──────── */}
          <div>
            <div className="flex items-center justify-between mb-3">
              <h2 className="text-sm font-semibold text-gray-900 dark:text-gray-100">
                Parts ({lines.length})
              </h2>
              {/* Mobile-only "Add Part" button (opens modal) */}
              <button
                type="button"
                onClick={() => setShowPartSearch(true)}
                className="lg:hidden inline-flex items-center gap-1.5 rounded-lg bg-primary px-3 py-1.5 text-sm font-medium text-white shadow-sm hover:bg-primary/90 transition-colors min-h-[36px]"
              >
                <Plus className="h-4 w-4" />
                Add Part
              </button>
            </div>

            {/* Desktop: side-by-side catalog browser + order lines */}
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
              {/* Left: Catalog Browser (hidden on mobile) */}
              <div className="hidden lg:block rounded-lg border border-gray-200 dark:border-gray-700 bg-gray-50 dark:bg-gray-800/50 p-4 h-[320px]">
                <CatalogBrowser
                  onSelect={handleAddPart}
                  excludePartIds={excludePartIds}
                />
              </div>

              {/* Right: Order Lines */}
              <div className="space-y-3 lg:h-[320px] lg:overflow-y-auto">
                {lines.length === 0 && (
                  <EmptyState
                    icon={<Package className="h-10 w-10" />}
                    title="No parts added yet"
                    description="Search the catalog to add parts to this request."
                    className="py-8 border border-dashed border-gray-300 dark:border-gray-600 rounded-lg"
                  />
                )}

                {lines.map((line, idx) => (
                  <LineItemCard
                    key={line.part_id}
                    line={line}
                    index={idx}
                    onUpdate={updateLine}
                    onRemove={removeLine}
                  />
                ))}
              </div>
            </div>
          </div>

          {/* ── Suggested Parts ─────────────────────────────── */}
          <SuggestedParts
            jobId={jobId}
            onSelect={handleAddPart}
            excludePartIds={excludePartIds}
          />
        </div>

        {/* ── Footer actions ───────────────────────────────────── */}
        <div className="px-6 py-4 border-t border-gray-200 dark:border-gray-700 flex items-center justify-end gap-3">
          <Link
            to="/orders/parts-requests"
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

      {/* ── Part Search Modal (mobile fallback) ──────────────── */}
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
// INTERNAL: LineItemCard (sub-component for each line)
// ═══════════════════════════════════════════════════════════════════

interface LineItemCardProps {
  line: JPOFormLine;
  index: number;
  onUpdate: <K extends keyof JPOFormLine>(
    index: number,
    field: K,
    value: JPOFormLine[K],
  ) => void;
  onRemove: (index: number) => void;
}

function LineItemCard({ line, index, onUpdate, onRemove }: LineItemCardProps) {
  return (
    <div className="rounded-lg border border-gray-200 dark:border-gray-700 bg-gray-50 dark:bg-gray-800/50 p-4">
      {/* Part identity row */}
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
          <p className="text-xs text-gray-500 dark:text-gray-400 mt-0.5">
            {line.total_stock} {line.unit_of_measure} in stock
          </p>
        </div>
        <button
          type="button"
          onClick={() => onRemove(index)}
          className="p-2 rounded-lg text-gray-400 hover:text-red-500 hover:bg-red-50 dark:hover:bg-red-900/20 transition-colors min-h-[36px] min-w-[36px] flex items-center justify-center"
          title="Remove part"
        >
          <Trash2 className="h-4 w-4" />
        </button>
      </div>

      {/* Editable fields row */}
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
        <div>
          <Input
            label="Qty"
            type="number"
            min={1}
            value={line.qty_requested}
            onChange={(e) =>
              onUpdate(index, 'qty_requested', Math.max(1, Number(e.target.value) || 1))
            }
          />
        </div>

        <div className="space-y-1.5">
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300">
            Priority
          </label>
          <select
            value={line.priority}
            onChange={(e) =>
              onUpdate(index, 'priority', e.target.value as LinePriority)
            }
            className="block w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm text-gray-900 dark:text-gray-100 focus:outline-none focus:ring-2 focus:ring-primary-300 focus:border-primary-500 transition-colors"
          >
            <option value="normal">Normal</option>
            <option value="urgent">Urgent</option>
            <option value="critical">Critical</option>
          </select>
        </div>

        <div className="col-span-2">
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
