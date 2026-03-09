/**
 * UnifiedOrderPage — single order creation form for both job orders
 * and warehouse restocking.
 *
 * Replaces NewPartsRequestPage (JPO creation) and the standalone PO flow.
 *
 * Desktop layout (3-panel):
 *   TOP BAR  — Order type toggle, job selector, priority, notes (compact)
 *   LEFT     — Parts Catalog (full catalog filtered by search)
 *   CENTER   — Parts Being Ordered (line items cart)
 *   RIGHT    — Suggestions & Special Items
 *
 * Tablet:  2-column — catalog | cart, suggestions below
 * Mobile:  single column stacked (catalog → cart → suggestions)
 *
 * The form submits via the existing createJPO API, which now accepts
 * an optional order_type ('job' | 'warehouse') and special_items array.
 */

import { useState, useCallback, useMemo } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  ArrowLeft,
  Trash2,
  Package,
  Loader2,
  AlertCircle,
  Zap,
  Building2,
  Briefcase,
  ShoppingCart,
  Lightbulb,
  ChevronDown,
  ChevronUp,
  Sparkles,
} from 'lucide-react';
import { Input } from '../../../components/ui/Input';
import { EmptyState } from '../../../components/ui/EmptyState';
import { UnifiedPartSearch } from '../components/UnifiedPartSearch';
import { SpecialItemForm } from '../components/SpecialItemForm';
import { CompanionSuggestionCard } from '../components/CompanionSuggestionCard';
import { getActiveJobs, getJobSuggestions } from '../../../api/jobs';
import { createJPO } from '../../../api/orders';
import { generateCompanionSuggestions } from '../../../api/parts';
import type {
  PartListItem,
  JPOPriority,
  LinePriority,
  SpecialItemCreate,
  JobPreferenceResponse,
  ManualTriggerItem,
} from '../../../lib/types';


// ── Form-local line item shape ────────────────────────────────────
interface OrderFormLine {
  part_id: number;
  part_code: string | null;
  part_name: string;
  brand: string | null;
  color_name: string | null;
  unit_of_measure: string;
  total_stock: number;
  qty_requested: number;
  priority: LinePriority;
  notes: string;
  // Hierarchy IDs — needed to feed the companion suggestion engine
  category_id: number | null;
  style_id: number | null;
}


export function UnifiedOrderPage() {
  const navigate = useNavigate();
  const queryClient = useQueryClient();

  // ── Order type: 'job' or 'warehouse' ────────────────────────────
  const [orderType, setOrderType] = useState<'job' | 'warehouse'>('job');

  // ── Form state ──────────────────────────────────────────────────
  const [jobId, setJobId] = useState<number | ''>('');
  const [priority, setPriority] = useState<JPOPriority>('normal');
  const [notes, setNotes] = useState('');
  const [lines, setLines] = useState<OrderFormLine[]>([]);
  const [specialItems, setSpecialItems] = useState<SpecialItemCreate[]>([]);
  const [validationError, setValidationError] = useState('');
  const [showNotes, setShowNotes] = useState(false);

  // ── Smart suggestion state ──────────────────────────────────────
  const [suggestionsEnabled, setSuggestionsEnabled] = useState(true);

  // ── Fetch active jobs for the selector ──────────────────────────
  const { data: jobs = [], isLoading: jobsLoading } = useQuery({
    queryKey: ['jobs-active'],
    queryFn: () => getActiveJobs(),
    staleTime: 60_000,
  });

  // ── Fetch job suggestions when a job is selected ────────────────
  const { data: suggestions } = useQuery({
    queryKey: ['job-suggestions', jobId],
    queryFn: () => getJobSuggestions(jobId as number),
    enabled: orderType === 'job' && typeof jobId === 'number' && jobId > 0,
    staleTime: 30_000,
  });

  // Derive brand/color prefs from suggestions for the part search
  const brandPrefs: JobPreferenceResponse[] = useMemo(
    () => (suggestionsEnabled && suggestions?.brands) || [],
    [suggestionsEnabled, suggestions?.brands],
  );
  const colorPrefs: JobPreferenceResponse[] = useMemo(
    () => (suggestionsEnabled && suggestions?.colors) || [],
    [suggestionsEnabled, suggestions?.colors],
  );

  // ── Companion suggestions — build trigger items from cart ──────
  // Deduplicate by category_id and sum quantities so the companion
  // engine gets one entry per category (e.g. 3 outlets + 2 outlets = 5).
  const companionTriggerItems: ManualTriggerItem[] = useMemo(() => {
    const byCat = new Map<number, ManualTriggerItem>();
    for (const line of lines) {
      if (line.category_id == null) continue;
      const existing = byCat.get(line.category_id);
      if (existing) {
        existing.qty += line.qty_requested;
      } else {
        byCat.set(line.category_id, {
          category_id: line.category_id,
          style_id: line.style_id,
          qty: line.qty_requested,
        });
      }
    }
    return Array.from(byCat.values());
  }, [lines]);

  // Stable key string for the trigger items to avoid unnecessary re-fetches
  const triggerKey = useMemo(
    () => JSON.stringify(companionTriggerItems),
    [companionTriggerItems],
  );

  // Query companion suggestions when cart has items with valid categories
  const {
    data: companionSuggestions = [],
    isLoading: companionsLoading,
    isFetching: companionsFetching,
  } = useQuery({
    queryKey: ['companion-suggestions', triggerKey],
    queryFn: () => generateCompanionSuggestions({ items: companionTriggerItems }),
    enabled: suggestionsEnabled && companionTriggerItems.length > 0,
    staleTime: 30_000,
  });

  // ── Create JPO mutation ─────────────────────────────────────────
  const createMutation = useMutation({
    mutationFn: createJPO,
    onSuccess: (jpo) => {
      queryClient.invalidateQueries({ queryKey: ['jpos'] });
      navigate(`/orders/parts-requests/${jpo.id}`);
    },
    onError: (err: Error) => {
      setValidationError(err.message || 'Failed to create order');
    },
  });

  // ── Add a part from UnifiedPartSearch ───────────────────────────
  const handleAddPart = useCallback((part: PartListItem) => {
    setLines((prev) => {
      // Prevent duplicates
      if (prev.some((l) => l.part_id === part.id)) return prev;

      return [
        ...prev,
        {
          part_id: part.id,
          part_code: part.code,
          part_name: part.name,
          brand: part.brand_name ?? null,
          color_name: part.color_name ?? null,
          unit_of_measure: part.unit_of_measure,
          total_stock: part.total_stock,
          qty_requested: 1,
          priority: 'normal',
          notes: '',
          category_id: part.category_id ?? null,
          style_id: part.style_id ?? null,
        },
      ];
    });
  }, []);

  // ── Update a field on a specific line ───────────────────────────
  const updateLine = <K extends keyof OrderFormLine>(
    index: number,
    field: K,
    value: OrderFormLine[K],
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
    if (orderType === 'job' && !jobId) {
      setValidationError('Please select a job.');
      return;
    }
    if (lines.length === 0 && specialItems.length === 0) {
      setValidationError('Please add at least one part or special item.');
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
      job_id: orderType === 'job' ? (jobId as number) : null,
      order_type: orderType,
      priority,
      notes: notes.trim() || undefined,
      smart_suggestions_enabled: orderType === 'job' ? suggestionsEnabled : undefined,
      lines: lines.map((l) => ({
        part_id: l.part_id,
        qty_requested: l.qty_requested,
        priority: l.priority,
        notes: l.notes.trim() || undefined,
      })),
      special_items: specialItems.length > 0 ? specialItems : undefined,
    });
  };

  const excludePartIds = lines.map((l) => l.part_id);
  const isJobOrder = orderType === 'job';
  const hasJob = isJobOrder && typeof jobId === 'number' && jobId > 0;
  const totalItems = lines.length + specialItems.length;

  return (
    <div className="space-y-3">
      {/* ── Header row ───────────────────────────────────────────── */}
      <div className="flex items-center justify-between flex-wrap gap-2">
        <div className="flex items-center gap-3">
          <Link
            to="/orders/my-orders"
            className="inline-flex items-center gap-1 text-sm text-gray-500 dark:text-gray-400 hover:text-primary transition-colors min-h-[44px]"
          >
            <ArrowLeft className="h-4 w-4" />
            <span className="hidden sm:inline">Back</span>
          </Link>
          <h1 className="text-lg font-semibold text-gray-900 dark:text-gray-100">
            New Order
          </h1>
        </div>
        <div className="flex items-center gap-3">
          <Link
            to="/orders/my-orders"
            className="rounded-lg border border-gray-300 dark:border-gray-600 px-3 py-1.5 text-sm font-medium text-gray-700 dark:text-gray-300 hover:bg-gray-50 dark:hover:bg-gray-700 transition-colors min-h-[36px] flex items-center"
          >
            Cancel
          </Link>
          <button
            type="button"
            onClick={handleSubmit}
            disabled={createMutation.isPending}
            className="inline-flex items-center gap-2 rounded-lg bg-primary px-4 py-1.5 text-sm font-medium text-white shadow-sm hover:bg-primary/90 disabled:opacity-50 transition-colors min-h-[36px]"
          >
            {createMutation.isPending && (
              <Loader2 className="h-4 w-4 animate-spin" />
            )}
            Save as Draft
          </button>
        </div>
      </div>

      {/* ── Error banner ─────────────────────────────────────────── */}
      {(validationError || createMutation.isError) && (
        <div className="flex items-start gap-3 p-3 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-lg">
          <AlertCircle className="h-5 w-5 text-red-500 flex-shrink-0 mt-0.5" />
          <p className="text-sm text-red-600 dark:text-red-400">
            {validationError || createMutation.error?.message}
          </p>
        </div>
      )}

      {/* ── Order Setup Bar (compact horizontal strip) ────────────── */}
      <div className="rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 shadow-sm p-3">
        <div className="flex items-end gap-2 xl:gap-3 flex-wrap">
          {/* Order Type Toggle */}
          <div className="space-y-1">
            <label className="block text-xs font-medium text-gray-600 dark:text-gray-400">
              Type
            </label>
            <div className="inline-flex rounded-lg border border-gray-300 dark:border-gray-600 overflow-hidden">
              <button
                type="button"
                onClick={() => { setOrderType('job'); setValidationError(''); }}
                className={`inline-flex items-center gap-1.5 px-2.5 py-1.5 text-sm font-medium transition-colors min-h-[36px] ${
                  isJobOrder
                    ? 'bg-primary text-white'
                    : 'bg-white dark:bg-gray-800 text-gray-700 dark:text-gray-300 hover:bg-gray-50 dark:hover:bg-gray-700'
                }`}
              >
                <Briefcase className="h-3.5 w-3.5" />
                <span className="hidden lg:inline">Job Order</span>
                <span className="lg:hidden">Job</span>
              </button>
              <button
                type="button"
                onClick={() => { setOrderType('warehouse'); setValidationError(''); }}
                className={`inline-flex items-center gap-1.5 px-2.5 py-1.5 text-sm font-medium transition-colors min-h-[36px] ${
                  !isJobOrder
                    ? 'bg-primary text-white'
                    : 'bg-white dark:bg-gray-800 text-gray-700 dark:text-gray-300 hover:bg-gray-50 dark:hover:bg-gray-700'
                }`}
              >
                <Building2 className="h-3.5 w-3.5" />
                <span className="hidden lg:inline">Warehouse</span>
                <span className="lg:hidden">WH</span>
              </button>
            </div>
          </div>

          {/* Job Selector (conditional) */}
          {isJobOrder && (
            <div className="flex-1 min-w-[140px] max-w-xs space-y-1">
              <label htmlFor="order-job" className="block text-xs font-medium text-gray-600 dark:text-gray-400">
                Job <span className="text-red-500">*</span>
              </label>
              <select
                id="order-job"
                value={jobId}
                onChange={(e) => {
                  setJobId(e.target.value ? Number(e.target.value) : '');
                  setValidationError('');
                }}
                className="block w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-2.5 py-1.5 text-sm text-gray-900 dark:text-gray-100 focus:outline-none focus:ring-2 focus:ring-primary-300 focus:border-primary-500 transition-colors min-h-[36px]"
              >
                <option value="">
                  {jobsLoading ? 'Loading...' : 'Select a job'}
                </option>
                {jobs.map((job) => (
                  <option key={job.id} value={job.id}>
                    {job.job_number} — {job.job_name}
                  </option>
                ))}
              </select>
            </div>
          )}

          {/* Priority */}
          <div className="space-y-1">
            <label htmlFor="order-priority" className="block text-xs font-medium text-gray-600 dark:text-gray-400">
              Priority
            </label>
            <select
              id="order-priority"
              value={priority}
              onChange={(e) => setPriority(e.target.value as JPOPriority)}
              className="block rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-2.5 py-1.5 text-sm text-gray-900 dark:text-gray-100 focus:outline-none focus:ring-2 focus:ring-primary-300 focus:border-primary-500 transition-colors min-h-[36px]"
            >
              <option value="normal">Normal</option>
              <option value="urgent">Urgent</option>
            </select>
          </div>

          {/* Notes toggle */}
          <button
            type="button"
            onClick={() => setShowNotes(!showNotes)}
            className="inline-flex items-center gap-1 px-2.5 py-1.5 text-sm text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-200 border border-gray-300 dark:border-gray-600 rounded-lg transition-colors min-h-[44px] min-w-[44px] justify-center"
          >
            {showNotes ? <ChevronUp className="h-3.5 w-3.5" /> : <ChevronDown className="h-3.5 w-3.5" />}
            <span className="hidden sm:inline">Notes</span>
          </button>

          {/* Item count badge — pushed right */}
          <div className="flex items-center gap-1.5 text-sm text-gray-500 dark:text-gray-400 ml-auto min-h-[36px]">
            <ShoppingCart className="h-4 w-4" />
            <span>{totalItems}</span>
            {specialItems.length > 0 && (
              <span className="text-amber-600 dark:text-amber-400 text-xs">
                +{specialItems.length}⚠
              </span>
            )}
          </div>
        </div>

        {/* Expandable notes */}
        {showNotes && (
          <div className="mt-3 pt-3 border-t border-gray-200 dark:border-gray-700">
            <textarea
              id="order-notes"
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
              rows={2}
              placeholder={isJobOrder
                ? 'Optional notes about this parts request...'
                : 'Optional notes about this warehouse restock...'}
              className="block w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm text-gray-900 dark:text-gray-100 placeholder:text-gray-400 dark:placeholder:text-gray-500 focus:outline-none focus:ring-2 focus:ring-primary-300 focus:border-primary-500 transition-colors resize-y"
            />
          </div>
        )}
      </div>

      {/* ══════════════════════════════════════════════════════════════
       *  3-PANEL LAYOUT
       *  Desktop (xl+):  3 columns — Catalog | Order Lines | Suggestions
       *  Tablet  (lg):   2 columns — Catalog | Order Lines (suggestions below)
       *  Mobile:         1 column stacked
       * ════════════════════════════════════════════════════════════ */}
      <div className="grid grid-cols-1 lg:grid-cols-2 xl:grid-cols-[1fr_1fr_260px] gap-3 items-start">

        {/* ═══ PANEL 1: Parts Catalog (left) ═════════════════════ */}
        <div className="min-w-0">
          <UnifiedPartSearch
            onSelect={handleAddPart}
            excludePartIds={excludePartIds}
            brandPrefs={brandPrefs}
            colorPrefs={colorPrefs}
            suggestionsEnabled={suggestionsEnabled && isJobOrder && hasJob}
          />
        </div>

        {/* ═══ PANEL 2: Parts Being Ordered (center) ═════════════ */}
        <div className="min-w-0 rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 shadow-sm overflow-hidden">
          <div className="px-4 py-3 border-b border-gray-200 dark:border-gray-700 flex items-center justify-between">
            <h2 className="text-sm font-semibold text-gray-900 dark:text-gray-100 flex items-center gap-1.5">
              <ShoppingCart className="h-4 w-4 text-gray-400 dark:text-gray-500" />
              Order Lines ({lines.length})
            </h2>
          </div>

          {/* Scrollable line items body */}
          <div className="max-h-[calc(100vh-300px)] overflow-y-auto">
            {lines.length === 0 ? (
              <EmptyState
                icon={<Package className="h-10 w-10" />}
                title="No parts added"
                description="Click parts in the catalog to add them here."
                className="py-10 px-4"
              />
            ) : (
              <div className="p-3 space-y-2">
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
            )}
          </div>
        </div>

        {/* ═══ PANEL 3: Companion Suggestions & Special Items (right) ═ */}
        <div className="min-w-0 space-y-3 lg:col-span-2 xl:col-span-1">
          {/* Companion Suggestions card */}
          <div className="rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 shadow-sm overflow-hidden">
            <div className="px-3 py-2.5 border-b border-gray-200 dark:border-gray-700 flex items-center justify-between gap-2">
              <h2 className="text-sm font-semibold text-gray-900 dark:text-gray-100 flex items-center gap-1.5 truncate">
                <Sparkles className="h-4 w-4 text-violet-500 flex-shrink-0" />
                Companions
              </h2>
              <div className="flex items-center gap-2 flex-shrink-0">
                {companionsFetching && (
                  <Loader2 className="h-3.5 w-3.5 text-gray-400 dark:text-gray-500 animate-spin" />
                )}
                <label className="relative inline-flex items-center cursor-pointer">
                  <input
                    type="checkbox"
                    checked={suggestionsEnabled}
                    onChange={(e) => setSuggestionsEnabled(e.target.checked)}
                    className="sr-only peer"
                  />
                  <div className="w-9 h-5 bg-gray-200 peer-focus:outline-none peer-focus:ring-4 peer-focus:ring-violet-300 dark:peer-focus:ring-violet-800 rounded-full peer dark:bg-gray-600 peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-4 after:w-4 after:transition-all dark:after:border-gray-600 peer-checked:bg-violet-500" />
                </label>
              </div>
            </div>

            <div className="max-h-[calc(100vh-360px)] overflow-y-auto">
              {!suggestionsEnabled ? (
                <p className="text-xs text-gray-500 dark:text-gray-400 text-center py-6 px-3">
                  Companion suggestions are turned off
                </p>
              ) : lines.length === 0 ? (
                <div className="flex flex-col items-center justify-center py-8 px-3 text-center">
                  <Lightbulb className="h-8 w-8 text-gray-300 dark:text-gray-600 mb-2" />
                  <p className="text-xs text-gray-500 dark:text-gray-400">
                    Add parts to your order to see companion suggestions
                  </p>
                  <p className="text-xs text-gray-400 dark:text-gray-500 mt-1">
                    Based on your Link Rules
                  </p>
                </div>
              ) : companionsLoading ? (
                <div className="flex items-center justify-center py-8">
                  <Loader2 className="h-5 w-5 animate-spin text-violet-400" />
                </div>
              ) : companionSuggestions.length === 0 ? (
                <div className="flex flex-col items-center justify-center py-8 px-3 text-center">
                  <Sparkles className="h-8 w-8 text-gray-300 dark:text-gray-600 mb-2" />
                  <p className="text-xs text-gray-500 dark:text-gray-400">
                    No companion suggestions for the current cart
                  </p>
                  <p className="text-xs text-gray-400 dark:text-gray-500 mt-1">
                    Add Link Rules in Parts → Companions to enable suggestions
                  </p>
                </div>
              ) : (
                <div className="p-2 space-y-2">
                  {companionSuggestions.map((suggestion) => (
                    <CompanionSuggestionCard
                      key={suggestion.id}
                      suggestion={suggestion}
                      onAdd={handleAddPart}
                      excludePartIds={excludePartIds}
                    />
                  ))}
                </div>
              )}
            </div>
          </div>

          {/* Brand/Color Preferences chip strip (compact, secondary) */}
          {isJobOrder && hasJob && suggestionsEnabled && (brandPrefs.length > 0 || colorPrefs.length > 0) && (
            <div className="rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 shadow-sm p-3">
              <p className="text-xs font-medium text-gray-500 dark:text-gray-400 mb-2">
                Job Preferences
              </p>
              <div className="flex flex-wrap gap-1.5">
                {brandPrefs.map((pref) => (
                  <span
                    key={pref.id}
                    className="inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs bg-blue-50 dark:bg-blue-900/20 text-blue-600 dark:text-blue-400 border border-blue-200 dark:border-blue-800"
                  >
                    <Zap className="h-2.5 w-2.5" />
                    {pref.text_value}
                  </span>
                ))}
                {colorPrefs.map((pref) => (
                  <span
                    key={pref.id}
                    className="inline-flex items-center rounded-full px-2 py-0.5 text-xs bg-purple-50 dark:bg-purple-900/20 text-purple-600 dark:text-purple-400 border border-purple-200 dark:border-purple-800"
                  >
                    {pref.text_value}
                  </span>
                ))}
              </div>
            </div>
          )}

          {/* Special Items card */}
          <div className="rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 shadow-sm overflow-hidden">
            <div className="p-3">
              <SpecialItemForm
                items={specialItems}
                onChange={setSpecialItems}
              />
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}


// ═══════════════════════════════════════════════════════════════════
// INTERNAL: LineItemCard (compact card for each order line)
// ═══════════════════════════════════════════════════════════════════

interface LineItemCardProps {
  line: OrderFormLine;
  index: number;
  onUpdate: <K extends keyof OrderFormLine>(
    index: number,
    field: K,
    value: OrderFormLine[K],
  ) => void;
  onRemove: (index: number) => void;
}

function LineItemCard({ line, index, onUpdate, onRemove }: LineItemCardProps) {
  return (
    <div className="rounded-lg border border-gray-200 dark:border-gray-700 bg-gray-50 dark:bg-gray-800/50 p-3">
      {/* Part identity + remove */}
      <div className="flex items-start justify-between gap-2 mb-2">
        <div className="flex-1 min-w-0">
          <p className="text-sm font-medium text-gray-900 dark:text-gray-100 truncate">
            {line.part_name}
          </p>
          <div className="flex items-center gap-1.5 flex-wrap mt-0.5">
            {line.part_code && (
              <span className="text-xs font-mono bg-gray-200 dark:bg-gray-700 text-gray-600 dark:text-gray-300 px-1 py-0.5 rounded">
                {line.part_code}
              </span>
            )}
            {line.brand && (
              <span className="text-xs bg-blue-100 dark:bg-blue-900/30 text-blue-700 dark:text-blue-300 px-1.5 py-0.5 rounded">
                {line.brand}
              </span>
            )}
            {line.color_name && (
              <span className="text-xs bg-purple-100 dark:bg-purple-900/30 text-purple-700 dark:text-purple-300 px-1.5 py-0.5 rounded">
                {line.color_name}
              </span>
            )}
            <span className="text-xs text-gray-500 dark:text-gray-400">
              {line.total_stock} in stock
            </span>
          </div>
        </div>
        <button
          type="button"
          onClick={() => onRemove(index)}
          className="p-2 rounded-lg text-gray-400 dark:text-gray-500 hover:text-red-500 hover:bg-red-50 dark:hover:bg-red-900/20 transition-colors min-h-[44px] min-w-[44px] flex items-center justify-center"
          title="Remove"
        >
          <Trash2 className="h-3.5 w-3.5" />
        </button>
      </div>

      {/* Compact fields row: qty + priority + notes */}
      <div className="grid grid-cols-3 gap-2">
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

        <div className="space-y-1">
          <label className="block text-xs font-medium text-gray-600 dark:text-gray-400">
            Priority
          </label>
          <select
            value={line.priority}
            onChange={(e) =>
              onUpdate(index, 'priority', e.target.value as LinePriority)
            }
            className="block w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-2 py-1.5 text-xs text-gray-900 dark:text-gray-100 focus:outline-none focus:ring-2 focus:ring-primary-300 focus:border-primary-500 transition-colors min-h-[32px]"
          >
            <option value="normal">Normal</option>
            <option value="urgent">Urgent</option>
            <option value="critical">Critical</option>
          </select>
        </div>

        <div>
          <Input
            label="Notes"
            value={line.notes}
            onChange={(e) => onUpdate(index, 'notes', e.target.value)}
            placeholder="..."
          />
        </div>
      </div>
    </div>
  );
}
