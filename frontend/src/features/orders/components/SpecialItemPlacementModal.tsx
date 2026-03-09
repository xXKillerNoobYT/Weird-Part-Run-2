/**
 * SpecialItemPlacementModal — wizard for placing a special item into the parts catalog.
 *
 * Walk through Category → Style → Type → Brand → Color with cascading
 * selectors, then confirm to create a new catalog part and resolve the
 * special item in one operation.
 *
 * Used by the office Approvals tab when a flagged special item needs to
 * be promoted to a catalog entry.
 */

import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  X, FolderTree, ChevronRight, Tag, Package, Palette, Check, AlertTriangle,
} from 'lucide-react';
import { Button } from '../../../components/ui/Button';
import { Spinner } from '../../../components/ui/Spinner';
import {
  listCategories, listStylesByCategory, listTypesByStyle,
  listTypeBrands, listTypeColors,
} from '../../../api/parts';
import { placeSpecialItemInCatalog } from '../../../api/orders';
import { toast } from '../../../lib/toast';
import type { SpecialItemResponse } from '../../../lib/types';


interface SpecialItemPlacementModalProps {
  item: SpecialItemResponse;
  onClose: () => void;
}


export function SpecialItemPlacementModal({ item, onClose }: SpecialItemPlacementModalProps) {
  const queryClient = useQueryClient();

  // ── Selection state ─────────────────────────────────────
  const [selectedCategoryId, setSelectedCategoryId] = useState<number | null>(null);
  const [selectedStyleId, setSelectedStyleId] = useState<number | null>(null);
  const [selectedTypeId, setSelectedTypeId] = useState<number | null>(null);
  const [selectedBrandId, setSelectedBrandId] = useState<number | null | undefined>(undefined); // undefined = not chosen
  const [selectedColorId, setSelectedColorId] = useState<number | null>(null);
  const [mpn, setMpn] = useState(item.part_number ?? '');

  // ── Hierarchy data ──────────────────────────────────────
  const { data: categories, isLoading: catLoading } = useQuery({
    queryKey: ['categories'],
    queryFn: () => listCategories(),
  });

  const { data: styles, isLoading: stylesLoading } = useQuery({
    queryKey: ['styles', selectedCategoryId],
    queryFn: () => listStylesByCategory(selectedCategoryId!),
    enabled: selectedCategoryId != null,
  });

  const { data: types, isLoading: typesLoading } = useQuery({
    queryKey: ['types', selectedStyleId],
    queryFn: () => listTypesByStyle(selectedStyleId!),
    enabled: selectedStyleId != null,
  });

  const { data: brandLinks, isLoading: brandsLoading } = useQuery({
    queryKey: ['type-brands', selectedTypeId],
    queryFn: () => listTypeBrands(selectedTypeId!),
    enabled: selectedTypeId != null,
  });

  const { data: colorLinks, isLoading: colorsLoading } = useQuery({
    queryKey: ['type-colors', selectedTypeId],
    queryFn: () => listTypeColors(selectedTypeId!),
    enabled: selectedTypeId != null,
  });

  // ── Mutation ────────────────────────────────────────────
  const mutation = useMutation({
    mutationFn: () => placeSpecialItemInCatalog(item.id, {
      type_id: selectedTypeId!,
      brand_id: selectedBrandId ?? null,
      color_id: selectedColorId!,
      manufacturer_part_number: mpn.trim() || undefined,
    }),
    onSuccess: (result) => {
      queryClient.invalidateQueries({ queryKey: ['flagged-special-items'] });
      queryClient.invalidateQueries({ queryKey: ['type-brand-parts', selectedTypeId] });
      queryClient.invalidateQueries({ queryKey: ['type-brands', selectedTypeId] });
      queryClient.invalidateQueries({ queryKey: ['categories'] });
      toast.success(`Added to catalog as "${result.part_name}"`);
      onClose();
    },
    onError: (err: any) => {
      toast.error(err?.response?.data?.detail ?? 'Failed to place item in catalog');
    },
  });

  // ── Reset dependent selections on change ───────────────
  const handleCategoryChange = (id: number) => {
    setSelectedCategoryId(id);
    setSelectedStyleId(null);
    setSelectedTypeId(null);
    setSelectedBrandId(undefined);
    setSelectedColorId(null);
  };

  const handleStyleChange = (id: number) => {
    setSelectedStyleId(id);
    setSelectedTypeId(null);
    setSelectedBrandId(undefined);
    setSelectedColorId(null);
  };

  const handleTypeChange = (id: number) => {
    setSelectedTypeId(id);
    setSelectedBrandId(undefined);
    setSelectedColorId(null);
  };

  const handleBrandChange = (brandId: number | null) => {
    setSelectedBrandId(brandId);
    setSelectedColorId(null);
  };

  // ── Can submit ─────────────────────────────────────────
  const canSubmit =
    selectedTypeId != null &&
    selectedBrandId !== undefined &&
    selectedColorId != null;

  // ── Preview name ───────────────────────────────────────
  const previewParts: string[] = [];
  if (selectedCategoryId && categories) {
    const cat = categories.find((c) => c.id === selectedCategoryId);
    if (cat) previewParts.push(cat.name);
  }
  if (selectedStyleId && styles) {
    const sty = styles.find((s) => s.id === selectedStyleId);
    if (sty) previewParts.push(sty.name);
  }
  if (selectedTypeId && types) {
    const typ = types.find((t) => t.id === selectedTypeId);
    if (typ) previewParts.push(typ.name);
  }
  if (selectedBrandId && brandLinks) {
    const bl = brandLinks.find((b) => b.brand_id === selectedBrandId);
    if (bl?.brand_name) previewParts.push(bl.brand_name);
  }
  if (selectedColorId && colorLinks) {
    const cl = colorLinks.find((c) => c.color_id === selectedColorId);
    if (cl?.color_name) previewParts.push(cl.color_name);
  }
  const previewName = previewParts.join(' ');

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-sm">
      <div className="bg-white dark:bg-gray-900 rounded-xl shadow-2xl w-full max-w-lg max-h-[90vh] flex flex-col border border-gray-200 dark:border-gray-700">

        {/* Header */}
        <div className="flex items-center justify-between px-6 py-4 border-b border-gray-200 dark:border-gray-700">
          <div className="flex items-center gap-2">
            <FolderTree className="h-5 w-5 text-primary-500" />
            <h2 className="text-base font-semibold text-gray-900 dark:text-gray-100">
              Place in Catalog
            </h2>
          </div>
          <button
            onClick={onClose}
            className="p-2 rounded-lg text-gray-400 hover:text-gray-600 dark:hover:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-800 transition-colors"
          >
            <X className="h-4 w-4" />
          </button>
        </div>

        <div className="flex-1 overflow-y-auto px-6 py-4 space-y-5">
          {/* Special item summary */}
          <div className="p-3 rounded-lg border border-amber-200 dark:border-amber-800 bg-amber-50 dark:bg-amber-900/20">
            <div className="flex items-start gap-2">
              <AlertTriangle className="h-4 w-4 text-amber-500 flex-shrink-0 mt-0.5" />
              <div className="min-w-0">
                <p className="text-sm font-medium text-gray-900 dark:text-gray-100">
                  {item.description}
                </p>
                <p className="text-xs text-gray-500 dark:text-gray-400 mt-0.5">
                  Qty: {item.quantity} {item.unit ?? 'each'}
                  {item.part_number && ` · P/N: ${item.part_number}`}
                  {item.estimated_cost != null && ` · ~$${item.estimated_cost.toFixed(2)}`}
                </p>
              </div>
            </div>
          </div>

          {/* Hierarchy selectors */}
          <div className="space-y-3">
            <p className="text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wide">
              Select catalog position
            </p>

            {/* Category */}
            <SelectRow
              label="Category"
              icon={<FolderTree className="h-3.5 w-3.5 text-primary-500" />}
              isLoading={catLoading}
              disabled={false}
              value={selectedCategoryId}
              onChange={handleCategoryChange}
              options={(categories ?? []).map((c) => ({ id: c.id, label: c.name }))}
              placeholder="Pick a category..."
            />

            {/* Style */}
            {selectedCategoryId != null && (
              <SelectRow
                label="Style"
                icon={<ChevronRight className="h-3.5 w-3.5 text-indigo-500" />}
                isLoading={stylesLoading}
                disabled={!selectedCategoryId}
                value={selectedStyleId}
                onChange={handleStyleChange}
                options={(styles ?? []).map((s) => ({ id: s.id, label: s.name }))}
                placeholder="Pick a style..."
              />
            )}

            {/* Type */}
            {selectedStyleId != null && (
              <SelectRow
                label="Type"
                icon={<ChevronRight className="h-3.5 w-3.5 text-teal-500" />}
                isLoading={typesLoading}
                disabled={!selectedStyleId}
                value={selectedTypeId}
                onChange={handleTypeChange}
                options={(types ?? []).map((t) => ({ id: t.id, label: t.name }))}
                placeholder="Pick a type..."
              />
            )}

            {/* Brand */}
            {selectedTypeId != null && (
              <div className="space-y-1.5">
                <label className="text-xs font-medium text-gray-600 dark:text-gray-400 flex items-center gap-1.5">
                  <Tag className="h-3.5 w-3.5 text-amber-500" />
                  Brand
                </label>
                {brandsLoading ? (
                  <div className="flex items-center gap-2 py-2 text-xs text-gray-400">
                    <Spinner size="sm" /> Loading brands...
                  </div>
                ) : !brandLinks || brandLinks.length === 0 ? (
                  <p className="text-xs text-gray-400 italic">
                    No brands enabled for this type. Go to the hierarchy editor to add brands.
                  </p>
                ) : (
                  <div className="flex flex-wrap gap-1.5">
                    {brandLinks.map((bl) => {
                      const id = bl.brand_id;
                      const label = bl.brand_id === null ? 'General' : (bl.brand_name ?? 'Unknown');
                      const isSelected = selectedBrandId === id;
                      return (
                        <button
                          key={bl.id}
                          type="button"
                          onClick={() => handleBrandChange(id)}
                          className={`inline-flex items-center gap-1 px-3 py-1.5 rounded-full border text-xs font-medium transition-colors ${
                            isSelected
                              ? 'border-amber-400 bg-amber-100 dark:bg-amber-900/30 text-amber-700 dark:text-amber-300'
                              : 'border-gray-200 dark:border-gray-700 hover:border-amber-300 hover:bg-amber-50 dark:hover:bg-amber-900/20 text-gray-700 dark:text-gray-300'
                          }`}
                        >
                          {id === null ? (
                            <Package className="h-3 w-3" />
                          ) : (
                            <Tag className="h-3 w-3" />
                          )}
                          {label}
                          {isSelected && <Check className="h-3 w-3 ml-0.5" />}
                        </button>
                      );
                    })}
                  </div>
                )}
              </div>
            )}

            {/* Color */}
            {selectedBrandId !== undefined && selectedTypeId != null && (
              <div className="space-y-1.5">
                <label className="text-xs font-medium text-gray-600 dark:text-gray-400 flex items-center gap-1.5">
                  <Palette className="h-3.5 w-3.5 text-primary-500" />
                  Color
                </label>
                {colorsLoading ? (
                  <div className="flex items-center gap-2 py-2 text-xs text-gray-400">
                    <Spinner size="sm" /> Loading colors...
                  </div>
                ) : !colorLinks || colorLinks.length === 0 ? (
                  <p className="text-xs text-gray-400 italic">
                    No colors linked to this type. Go to the hierarchy editor to add colors.
                  </p>
                ) : (
                  <div className="flex flex-wrap gap-1.5">
                    {colorLinks.map((cl) => {
                      const isSelected = selectedColorId === cl.color_id;
                      return (
                        <button
                          key={cl.color_id}
                          type="button"
                          onClick={() => setSelectedColorId(cl.color_id)}
                          className={`inline-flex items-center gap-1.5 px-3 py-1.5 rounded-full border text-xs font-medium transition-colors ${
                            isSelected
                              ? 'border-primary-400 bg-primary-50 dark:bg-primary-900/30 text-primary-700 dark:text-primary-300'
                              : 'border-gray-200 dark:border-gray-700 hover:border-primary-300 hover:bg-primary-50/50 dark:hover:bg-primary-900/20 text-gray-700 dark:text-gray-300'
                          }`}
                        >
                          {cl.hex_code && (
                            <span
                              className="w-3 h-3 rounded-full border border-gray-300 dark:border-gray-500 flex-shrink-0"
                              style={{ backgroundColor: cl.hex_code }}
                            />
                          )}
                          {cl.color_name ?? 'Unknown'}
                          {isSelected && <Check className="h-3 w-3" />}
                        </button>
                      );
                    })}
                  </div>
                )}
              </div>
            )}
          </div>

          {/* MPN field */}
          {selectedColorId != null && (
            <div className="space-y-1.5">
              <label className="block text-xs font-medium text-gray-600 dark:text-gray-400">
                Manufacturer Part Number (optional)
              </label>
              <input
                type="text"
                value={mpn}
                onChange={(e) => setMpn(e.target.value)}
                placeholder="e.g. 5225-2W"
                className="w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm text-gray-900 dark:text-gray-100 placeholder:text-gray-400 focus:ring-2 focus:ring-primary-300 min-h-[44px]"
              />
            </div>
          )}

          {/* Preview name */}
          {previewName && (
            <div className="p-3 rounded-lg bg-gray-50 dark:bg-gray-800 border border-gray-200 dark:border-gray-700">
              <p className="text-[10px] text-gray-400 dark:text-gray-500 uppercase tracking-wide mb-1">
                New part name
              </p>
              <p className="text-sm font-medium text-gray-900 dark:text-gray-100">
                {previewName}
              </p>
            </div>
          )}
        </div>

        {/* Footer */}
        <div className="flex justify-end gap-2 px-6 py-4 border-t border-gray-200 dark:border-gray-700">
          <Button variant="secondary" onClick={onClose} disabled={mutation.isPending}>
            Cancel
          </Button>
          <Button
            variant="primary"
            onClick={() => mutation.mutate()}
            isLoading={mutation.isPending}
            disabled={!canSubmit}
          >
            Place in Catalog
          </Button>
        </div>
      </div>
    </div>
  );
}


// ── Helper component: cascading select row ───────────────────────

interface SelectRowProps {
  label: string;
  icon: React.ReactNode;
  isLoading: boolean;
  disabled: boolean;
  value: number | null;
  onChange: (id: number) => void;
  options: { id: number; label: string }[];
  placeholder: string;
}

function SelectRow({
  label, icon, isLoading, disabled, value, onChange, options, placeholder,
}: SelectRowProps) {
  return (
    <div className="space-y-1">
      <label className="text-xs font-medium text-gray-600 dark:text-gray-400 flex items-center gap-1.5">
        {icon}
        {label}
      </label>
      {isLoading ? (
        <div className="flex items-center gap-2 py-1 text-xs text-gray-400">
          <Spinner size="sm" /> Loading...
        </div>
      ) : (
        <select
          value={value ?? ''}
          onChange={(e) => onChange(Number(e.target.value))}
          disabled={disabled || options.length === 0}
          className="w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm text-gray-900 dark:text-gray-100 disabled:opacity-50 focus:ring-2 focus:ring-primary-300 min-h-[44px]"
        >
          <option value="">{placeholder}</option>
          {options.map((o) => (
            <option key={o.id} value={o.id}>
              {o.label}
            </option>
          ))}
        </select>
      )}
    </div>
  );
}
