/**
 * EditTypePanel — right-panel for editing a Type node.
 *
 * REWRITTEN for Phase 2.6: now includes brand/general checkboxes.
 * - Top section: type name, description, image fields
 * - Middle: "Available Colors" — type ↔ color link management
 * - Bottom: "Brands & General" — checkboxes to enable brands for this type
 *
 * Checking a brand creates a type_brand_link; unchecking removes it.
 * The tree then shows enabled brands/General as expandable BrandNodes.
 */

import { useState, useMemo } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  Box, Check, ToggleLeft, ToggleRight, Trash2,
  Palette, Tag, Package, Plus, X,
} from 'lucide-react';
import { Button } from '../../../../components/ui/Button';
import { Input } from '../../../../components/ui/Input';
import { Badge } from '../../../../components/ui/Badge';
import { Spinner } from '../../../../components/ui/Spinner';
import {
  listCategories, listStylesByCategory, listTypesByStyle,
  updateType, listTypeColors, linkColorsToType, unlinkColorFromType,
  listTypeBrands, linkBrandToType, unlinkBrandFromType,
  listBrands,
} from '../../../../api/parts';
import type {
  PartType, PartTypeUpdate, PartColor, TypeColorLink, Brand,
} from '../../../../lib/types';


export interface EditTypePanelProps {
  typeId: number;
  allColors: PartColor[];
  canEdit: boolean;
  onDelete: () => void;
}

export function EditTypePanel({ typeId, allColors, canEdit, onDelete }: EditTypePanelProps) {
  const queryClient = useQueryClient();

  // ── Lookup this type (iterate through hierarchy) ──────────
  const { data: categories } = useQuery({ queryKey: ['categories'], queryFn: () => listCategories() });

  const [type, setType] = useState<PartType | null>(null);
  const [name, setName] = useState('');
  const [description, setDescription] = useState('');
  const [imageUrl, setImageUrl] = useState('');
  const [initialized, setInitialized] = useState(false);
  const [prevId, setPrevId] = useState(typeId);

  const typeLookup = useQuery({
    queryKey: ['type-lookup', typeId],
    queryFn: async () => {
      if (!categories) return null;
      for (const cat of categories) {
        const styles = await listStylesByCategory(cat.id);
        for (const style of styles) {
          const types = await listTypesByStyle(style.id);
          const found = types.find((t) => t.id === typeId);
          if (found) return found;
        }
      }
      return null;
    },
    enabled: !!categories && categories.length > 0,
  });

  if (typeLookup.data && (!initialized || typeId !== prevId)) {
    setType(typeLookup.data);
    setName(typeLookup.data.name);
    setDescription(typeLookup.data.description ?? '');
    setImageUrl(typeLookup.data.image_url ?? '');
    setInitialized(true);
    setPrevId(typeId);
  }

  // ── Type ↔ Color links ────────────────────────────────────
  const { data: colorLinks, isLoading: colorLinksLoading } = useQuery({
    queryKey: ['type-colors', typeId],
    queryFn: () => listTypeColors(typeId),
  });

  const linkColorMutation = useMutation({
    mutationFn: (colorIds: number[]) => linkColorsToType(typeId, colorIds),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['type-colors', typeId] });
      queryClient.invalidateQueries({ queryKey: ['types'] });
      queryClient.invalidateQueries({ queryKey: ['type-lookup', typeId] });
    },
  });

  const unlinkColorMutation = useMutation({
    mutationFn: (colorId: number) => unlinkColorFromType(typeId, colorId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['type-colors', typeId] });
      queryClient.invalidateQueries({ queryKey: ['types'] });
      queryClient.invalidateQueries({ queryKey: ['type-lookup', typeId] });
    },
  });

  // ── Type ↔ Brand links ────────────────────────────────────
  const { data: brandLinks, isLoading: brandLinksLoading } = useQuery({
    queryKey: ['type-brands', typeId],
    queryFn: () => listTypeBrands(typeId),
  });

  const { data: allBrands } = useQuery({
    queryKey: ['brands'],
    queryFn: () => listBrands(),
  });

  const linkBrandMutation = useMutation({
    mutationFn: (brandId: number | null) => linkBrandToType(typeId, brandId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['type-brands', typeId] });
      queryClient.invalidateQueries({ queryKey: ['types'] });
    },
  });

  const unlinkBrandMutation = useMutation({
    mutationFn: (brandId: number | null) => unlinkBrandFromType(typeId, brandId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['type-brands', typeId] });
      queryClient.invalidateQueries({ queryKey: ['types'] });
    },
  });

  // ── Update mutations ──────────────────────────────────────
  const updateMutation = useMutation({
    mutationFn: (data: PartTypeUpdate) => updateType(typeId, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['types'] });
      queryClient.invalidateQueries({ queryKey: ['type-lookup', typeId] });
    },
  });

  const toggleMutation = useMutation({
    mutationFn: (is_active: boolean) => updateType(typeId, { is_active }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['types'] });
      queryClient.invalidateQueries({ queryKey: ['type-lookup', typeId] });
    },
  });

  // ── Derived data ──────────────────────────────────────────
  const linkedColorIds = useMemo(
    () => new Set((colorLinks ?? []).map((l) => l.color_id)),
    [colorLinks],
  );
  const unlinkedColors = allColors.filter((c) => !linkedColorIds.has(c.id) && c.is_active);

  // Which brands are linked? (Set of brand_id, with null mapped to "general")
  const linkedBrandIds = useMemo(() => {
    const set = new Set<number | null>();
    (brandLinks ?? []).forEach((l) => set.add(l.brand_id));
    return set;
  }, [brandLinks]);

  const isGeneralEnabled = linkedBrandIds.has(null);

  // ── Loading state ─────────────────────────────────────────
  if (!type) {
    return (
      <div className="flex-1 flex items-center justify-center">
        <Spinner size="lg" />
      </div>
    );
  }

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    updateMutation.mutate({
      name,
      description: description || undefined,
      image_url: imageUrl || undefined,
    });
  };

  const handleBrandToggle = (brandId: number | null, isCurrentlyLinked: boolean) => {
    if (isCurrentlyLinked) {
      unlinkBrandMutation.mutate(brandId);
    } else {
      linkBrandMutation.mutate(brandId);
    }
  };

  return (
    <div className="flex flex-col h-full">
      {/* Header */}
      <div className="px-6 py-4 border-b border-gray-200 dark:border-gray-700 bg-gray-50 dark:bg-gray-800/80 flex items-center justify-between">
        <div>
          <div className="flex items-center gap-2">
            <Box className="h-5 w-5 text-teal-500" />
            <h3 className="text-lg font-semibold text-gray-900 dark:text-gray-100">
              {type.name}
            </h3>
            <Badge variant={type.is_active ? 'success' : 'default'}>
              {type.is_active ? 'Active' : 'Inactive'}
            </Badge>
          </div>
          <p className="text-sm text-gray-500 dark:text-gray-400 mt-0.5">
            Type in {type.category_name} &rarr; {type.style_name} &middot; {type.color_count} colors &middot; {type.part_count} parts
          </p>
        </div>
        {canEdit && (
          <div className="flex items-center gap-2">
            <button
              className="p-2 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors"
              onClick={() => toggleMutation.mutate(!type.is_active)}
            >
              {type.is_active ? (
                <ToggleRight className="h-5 w-5 text-green-500" />
              ) : (
                <ToggleLeft className="h-5 w-5 text-gray-400" />
              )}
            </button>
            <button
              className="p-2 rounded-lg hover:bg-red-50 dark:hover:bg-red-900/20 transition-colors"
              onClick={onDelete}
            >
              <Trash2 className="h-4 w-4 text-red-400" />
            </button>
          </div>
        )}
      </div>

      <div className="flex-1 overflow-y-auto p-6 space-y-6">
        {/* ── Details form ──────────────────────── */}
        <form onSubmit={handleSubmit} className="space-y-4">
          <Input label="Name" value={name} onChange={(e) => setName(e.target.value)} disabled={!canEdit} required />

          <div className="space-y-1.5">
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300">Description</label>
            <textarea
              className="w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm min-h-[60px] disabled:opacity-50"
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              disabled={!canEdit}
            />
          </div>

          <Input label="Image URL" value={imageUrl} onChange={(e) => setImageUrl(e.target.value)} disabled={!canEdit} type="url" />

          {updateMutation.isSuccess && (
            <p className="text-green-600 text-sm flex items-center gap-1"><Check className="h-4 w-4" /> Saved</p>
          )}
          {updateMutation.isError && (
            <p className="text-red-500 text-sm">{(updateMutation.error as any)?.response?.data?.detail ?? 'Failed to save.'}</p>
          )}

          {canEdit && (
            <div className="flex justify-end">
              <Button type="submit" isLoading={updateMutation.isPending}>Save Changes</Button>
            </div>
          )}
        </form>

        {/* ── Brands & General ─────────────────── */}
        <div className="border-t border-gray-200 dark:border-gray-700 pt-4">
          <h4 className="text-sm font-semibold text-gray-700 dark:text-gray-300 flex items-center gap-2 mb-3">
            <Tag className="h-4 w-4 text-amber-500" />
            Brands &amp; General
          </h4>
          <p className="text-xs text-gray-500 dark:text-gray-400 mb-3">
            Enable brands that manufacture this type of part. "General" is for unbranded commodity items.
          </p>

          {brandLinksLoading ? (
            <div className="flex items-center gap-2 py-2 text-sm text-gray-500">
              <Spinner size="sm" /> Loading brands...
            </div>
          ) : (
            <div className="space-y-1.5">
              {/* General checkbox */}
              <label
                className={`flex items-center gap-3 px-3 py-2 rounded-lg border transition-colors cursor-pointer ${
                  isGeneralEnabled
                    ? 'border-primary-300 bg-primary-50 dark:border-primary-700 dark:bg-primary-900/20'
                    : 'border-gray-200 dark:border-gray-600 hover:bg-gray-50 dark:hover:bg-gray-700/50'
                }`}
              >
                <input
                  type="checkbox"
                  checked={isGeneralEnabled}
                  onChange={() => handleBrandToggle(null, isGeneralEnabled)}
                  disabled={!canEdit || linkBrandMutation.isPending || unlinkBrandMutation.isPending}
                  className="w-4 h-4 rounded border-gray-300 text-primary-600 focus:ring-primary-500"
                />
                <Package className="h-4 w-4 text-gray-500 flex-shrink-0" />
                <span className="text-sm font-medium flex-1">General</span>
                <span className="text-xs text-gray-400">Unbranded / commodity</span>
              </label>

              {/* Brand checkboxes */}
              {(allBrands ?? []).filter((b) => b.is_active).map((brand) => {
                const isLinked = linkedBrandIds.has(brand.id);
                return (
                  <label
                    key={brand.id}
                    className={`flex items-center gap-3 px-3 py-2 rounded-lg border transition-colors cursor-pointer ${
                      isLinked
                        ? 'border-amber-300 bg-amber-50 dark:border-amber-700 dark:bg-amber-900/20'
                        : 'border-gray-200 dark:border-gray-600 hover:bg-gray-50 dark:hover:bg-gray-700/50'
                    }`}
                  >
                    <input
                      type="checkbox"
                      checked={isLinked}
                      onChange={() => handleBrandToggle(brand.id, isLinked)}
                      disabled={!canEdit || linkBrandMutation.isPending || unlinkBrandMutation.isPending}
                      className="w-4 h-4 rounded border-gray-300 text-amber-600 focus:ring-amber-500"
                    />
                    <Tag className="h-4 w-4 text-amber-500 flex-shrink-0" />
                    <span className="text-sm flex-1">{brand.name}</span>
                    {isLinked && (
                      <span className="text-xs text-gray-400">
                        {brandLinks?.find((l) => l.brand_id === brand.id)?.part_count ?? 0} parts
                      </span>
                    )}
                  </label>
                );
              })}

              {/* Unlink error message */}
              {unlinkBrandMutation.isError && (
                <p className="text-red-500 text-sm mt-2">
                  {(unlinkBrandMutation.error as any)?.response?.data?.detail ?? 'Cannot unlink — parts may exist under this brand.'}
                </p>
              )}
            </div>
          )}
        </div>

        {/* ── Type ↔ Color Links ───────────────── */}
        <div className="border-t border-gray-200 dark:border-gray-700 pt-4">
          <h4 className="text-sm font-semibold text-gray-700 dark:text-gray-300 flex items-center gap-2 mb-3">
            <Palette className="h-4 w-4 text-primary-500" />
            Available Colors ({colorLinks?.length ?? 0})
          </h4>
          <p className="text-xs text-gray-500 dark:text-gray-400 mb-3">
            Colors available for parts of this type. Link colors here, then create parts under each brand.
          </p>

          {colorLinksLoading ? (
            <div className="flex items-center gap-2 py-2 text-sm text-gray-500">
              <Spinner size="sm" /> Loading colors...
            </div>
          ) : (
            <>
              {/* Linked colors */}
              <div className="flex flex-wrap gap-2 mb-3">
                {(colorLinks ?? []).map((link) => (
                  <span
                    key={link.id}
                    className="inline-flex items-center gap-1.5 text-sm px-2.5 py-1 rounded-full border border-gray-200 dark:border-gray-600 bg-gray-50 dark:bg-gray-700"
                  >
                    {link.hex_code && (
                      <span
                        className="inline-block w-3 h-3 rounded-full border border-gray-300 dark:border-gray-500"
                        style={{ backgroundColor: link.hex_code }}
                      />
                    )}
                    {link.color_name}
                    {canEdit && (
                      <button
                        className="ml-1 p-0.5 rounded-full hover:bg-red-100 dark:hover:bg-red-900/30 transition-colors"
                        onClick={() => unlinkColorMutation.mutate(link.color_id)}
                        title={`Remove ${link.color_name}`}
                      >
                        <X className="h-3 w-3 text-red-400" />
                      </button>
                    )}
                  </span>
                ))}
                {(colorLinks ?? []).length === 0 && (
                  <p className="text-sm text-gray-400 italic">No colors linked yet</p>
                )}
              </div>

              {/* Add color buttons */}
              {canEdit && unlinkedColors.length > 0 && (
                <div>
                  <p className="text-xs text-gray-500 dark:text-gray-400 mb-2">
                    Click to link a color:
                  </p>
                  <div className="flex flex-wrap gap-1.5">
                    {unlinkedColors.map((color) => (
                      <button
                        key={color.id}
                        className="inline-flex items-center gap-1 text-xs px-2 py-1 rounded-full border border-dashed border-gray-300 dark:border-gray-600 hover:border-primary-400 hover:bg-primary-50 dark:hover:bg-primary-900/20 transition-colors"
                        onClick={() => linkColorMutation.mutate([color.id])}
                        title={`Link ${color.name}`}
                      >
                        {color.hex_code && (
                          <span
                            className="inline-block w-2.5 h-2.5 rounded-full border border-gray-300 dark:border-gray-500"
                            style={{ backgroundColor: color.hex_code }}
                          />
                        )}
                        <Plus className="h-2.5 w-2.5" />
                        {color.name}
                      </button>
                    ))}
                  </div>
                </div>
              )}
            </>
          )}
        </div>
      </div>
    </div>
  );
}
