/**
 * PartDetailPanel — right-panel for viewing/editing a single Part record.
 *
 * Shown when a color leaf node (= Part) is selected in the tree.
 * Displays:
 *   - Auto-generated name (editable)
 *   - Code / SKU (optional for general, shown for specific)
 *   - MPN field (only for branded parts — the KEY difference)
 *   - Pricing: cost, markup %, computed sell
 *   - Notes, image URL
 *   - Deprecated toggle
 *   - Delete button (removes the Part record)
 */

import { useState, useEffect } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  Box, Check, Trash2, AlertTriangle, DollarSign,
  ToggleLeft, ToggleRight, Tag, Package,
} from 'lucide-react';
import { Button } from '../../../../components/ui/Button';
import { Input } from '../../../../components/ui/Input';
import { Badge } from '../../../../components/ui/Badge';
import { Spinner } from '../../../../components/ui/Spinner';
import { Modal } from '../../../../components/ui/Modal';
import { getPart, updatePart, deletePart } from '../../../../api/parts';
import type { PartUpdate } from '../../../../lib/types';


export interface PartDetailPanelProps {
  partId: number;
  canEdit: boolean;
  onDeleted: () => void;  // Called when part is deleted so parent can clear selection
}

export function PartDetailPanel({ partId, canEdit, onDeleted }: PartDetailPanelProps) {
  const queryClient = useQueryClient();

  // Fetch full part detail
  const { data: part, isLoading } = useQuery({
    queryKey: ['part-detail', partId],
    queryFn: () => getPart(partId),
  });

  // Form state
  const [name, setName] = useState('');
  const [code, setCode] = useState('');
  const [mpn, setMpn] = useState('');
  const [costPrice, setCostPrice] = useState('');
  const [markupPercent, setMarkupPercent] = useState('');
  const [notes, setNotes] = useState('');
  const [imageUrl, setImageUrl] = useState('');
  const [unitOfMeasure, setUnitOfMeasure] = useState('');
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);

  // Populate form when part loads
  useEffect(() => {
    if (part) {
      setName(part.name);
      setCode(part.code ?? '');
      setMpn(part.manufacturer_part_number ?? '');
      setCostPrice(part.company_cost_price != null ? String(part.company_cost_price) : '');
      setMarkupPercent(part.markup_percent != null ? String(part.markup_percent) : '');
      setNotes(part.notes ?? '');
      setImageUrl(part.image_url ?? '');
      setUnitOfMeasure(part.unit_of_measure ?? 'each');
    }
  }, [part]);

  // Mutations
  const updateMutation = useMutation({
    mutationFn: (data: PartUpdate) => updatePart(partId, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['part-detail', partId] });
      // Also refresh tree parts lists
      queryClient.invalidateQueries({ queryKey: ['type-brand-parts'] });
      queryClient.invalidateQueries({ queryKey: ['types'] });
    },
  });

  const deleteMutation = useMutation({
    mutationFn: () => deletePart(partId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['type-brand-parts'] });
      queryClient.invalidateQueries({ queryKey: ['type-brands'] });
      queryClient.invalidateQueries({ queryKey: ['types'] });
      setShowDeleteConfirm(false);
      onDeleted();
    },
  });

  const deprecateMutation = useMutation({
    mutationFn: (is_deprecated: boolean) => updatePart(partId, { is_deprecated }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['part-detail', partId] });
      queryClient.invalidateQueries({ queryKey: ['type-brand-parts'] });
    },
  });

  if (isLoading || !part) {
    return (
      <div className="flex-1 flex items-center justify-center">
        <Spinner size="lg" />
      </div>
    );
  }

  const isGeneral = part.part_type === 'general';
  const computedSellPrice = costPrice && markupPercent
    ? (parseFloat(costPrice) * (1 + parseFloat(markupPercent) / 100)).toFixed(2)
    : part.company_sell_price?.toFixed(2) ?? '—';

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    updateMutation.mutate({
      name,
      code: code || undefined,
      manufacturer_part_number: mpn || undefined,
      company_cost_price: costPrice ? parseFloat(costPrice) : undefined,
      markup_percent: markupPercent ? parseFloat(markupPercent) : undefined,
      notes: notes || undefined,
      image_url: imageUrl || undefined,
      unit_of_measure: unitOfMeasure || undefined,
    });
  };

  return (
    <div className="flex flex-col h-full">
      {/* Header */}
      <div className="px-6 py-4 border-b border-gray-200 dark:border-gray-700 bg-gray-50 dark:bg-gray-800/80 flex items-center justify-between">
        <div>
          <div className="flex items-center gap-2">
            {/* Color swatch */}
            {part.color_hex && (
              <span
                className="inline-block w-5 h-5 rounded-full border-2 border-gray-300 dark:border-gray-500"
                style={{ backgroundColor: part.color_hex }}
              />
            )}
            <h3 className="text-lg font-semibold text-gray-900 dark:text-gray-100 truncate">
              {part.name}
            </h3>
            <Badge variant={isGeneral ? 'default' : 'warning'}>
              {isGeneral ? 'General' : 'Branded'}
            </Badge>
            {part.is_deprecated && (
              <Badge variant="danger">Deprecated</Badge>
            )}
          </div>
          <p className="text-sm text-gray-500 dark:text-gray-400 mt-0.5">
            {part.category_name} &rarr; {part.style_name} &rarr; {part.type_name}
            {part.brand_name && ` &rarr; ${part.brand_name}`}
            {part.color_name && ` &middot; ${part.color_name}`}
          </p>
        </div>
        {canEdit && (
          <div className="flex items-center gap-2">
            <button
              className="p-2 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors"
              onClick={() => deprecateMutation.mutate(!part.is_deprecated)}
              title={part.is_deprecated ? 'Restore' : 'Deprecate'}
            >
              {part.is_deprecated ? (
                <ToggleLeft className="h-5 w-5 text-gray-400" />
              ) : (
                <ToggleRight className="h-5 w-5 text-green-500" />
              )}
            </button>
            <button
              className="p-2 rounded-lg hover:bg-red-50 dark:hover:bg-red-900/20 transition-colors"
              onClick={() => setShowDeleteConfirm(true)}
              title="Delete Part"
            >
              <Trash2 className="h-4 w-4 text-red-400" />
            </button>
          </div>
        )}
      </div>

      {/* Form */}
      <form onSubmit={handleSubmit} className="flex-1 overflow-y-auto p-6 space-y-5">
        {/* Identity */}
        <div className="space-y-3">
          <h4 className="text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400">
            Identity
          </h4>
          <Input
            label="Part Name"
            value={name}
            onChange={(e) => setName(e.target.value)}
            disabled={!canEdit}
            required
          />
          <Input
            label="Code / SKU"
            value={code}
            onChange={(e) => setCode(e.target.value)}
            disabled={!canEdit}
            placeholder="Optional internal code"
          />
          {!isGeneral && (
            <div>
              <Input
                label="Manufacturer Part Number (MPN)"
                value={mpn}
                onChange={(e) => setMpn(e.target.value)}
                disabled={!canEdit}
                placeholder="e.g. GFNT1-0GW"
              />
              {!mpn && (
                <p className="text-xs text-amber-500 mt-1 flex items-center gap-1">
                  <AlertTriangle className="h-3 w-3" />
                  This branded part needs an MPN
                </p>
              )}
            </div>
          )}
        </div>

        {/* Pricing */}
        <div className="space-y-3 border-t border-gray-200 dark:border-gray-700 pt-4">
          <h4 className="text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400 flex items-center gap-1">
            <DollarSign className="h-3.5 w-3.5" />
            Pricing
          </h4>
          <div className="grid grid-cols-3 gap-3">
            <Input
              label="Cost"
              value={costPrice}
              onChange={(e) => setCostPrice(e.target.value)}
              disabled={!canEdit}
              type="number"
              step="0.01"
              min="0"
              placeholder="0.00"
            />
            <Input
              label="Markup %"
              value={markupPercent}
              onChange={(e) => setMarkupPercent(e.target.value)}
              disabled={!canEdit}
              type="number"
              step="0.1"
              min="0"
              placeholder="0"
            />
            <div className="space-y-1.5">
              <label className="block text-sm font-medium text-gray-700 dark:text-gray-300">Sell</label>
              <div className="px-3 py-2 rounded-lg bg-gray-100 dark:bg-gray-700 text-sm font-medium text-gray-700 dark:text-gray-300">
                ${computedSellPrice}
              </div>
            </div>
          </div>
          <Input
            label="Unit of Measure"
            value={unitOfMeasure}
            onChange={(e) => setUnitOfMeasure(e.target.value)}
            disabled={!canEdit}
            placeholder="each"
          />
        </div>

        {/* Details */}
        <div className="space-y-3 border-t border-gray-200 dark:border-gray-700 pt-4">
          <h4 className="text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400">
            Details
          </h4>
          <Input
            label="Image URL"
            value={imageUrl}
            onChange={(e) => setImageUrl(e.target.value)}
            disabled={!canEdit}
            placeholder="https://..."
            type="url"
          />
          <div className="space-y-1.5">
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300">Notes</label>
            <textarea
              className="w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm min-h-[60px] disabled:opacity-50"
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
              disabled={!canEdit}
              placeholder="Optional notes..."
            />
          </div>
        </div>

        {/* Save feedback */}
        {updateMutation.isSuccess && (
          <p className="text-green-600 text-sm flex items-center gap-1">
            <Check className="h-4 w-4" /> Saved
          </p>
        )}
        {updateMutation.isError && (
          <p className="text-red-500 text-sm">
            {(updateMutation.error as any)?.response?.data?.detail ?? 'Failed to save.'}
          </p>
        )}

        {canEdit && (
          <div className="flex justify-end pt-4 border-t border-gray-200 dark:border-gray-700">
            <Button type="submit" isLoading={updateMutation.isPending}>
              Save Changes
            </Button>
          </div>
        )}
      </form>

      {/* Delete confirmation modal */}
      {showDeleteConfirm && (
        <Modal isOpen onClose={() => setShowDeleteConfirm(false)} title="Delete Part?" size="sm">
          <p className="text-gray-600 dark:text-gray-300 mb-4">
            Are you sure you want to delete <strong>{part.name}</strong>? This cannot be undone.
          </p>
          {deleteMutation.isError && (
            <p className="text-red-500 text-sm mb-4">
              {(deleteMutation.error as any)?.response?.data?.detail ?? 'Failed to delete. Stock may exist for this part.'}
            </p>
          )}
          <div className="flex justify-end gap-2">
            <Button variant="secondary" onClick={() => setShowDeleteConfirm(false)}>Cancel</Button>
            <Button variant="danger" isLoading={deleteMutation.isPending} onClick={() => deleteMutation.mutate()}>
              Delete Part
            </Button>
          </div>
        </Modal>
      )}
    </div>
  );
}
