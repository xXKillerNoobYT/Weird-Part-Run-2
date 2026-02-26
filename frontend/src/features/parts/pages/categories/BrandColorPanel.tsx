/**
 * BrandColorPanel — right-panel for managing parts under a Brand/General node.
 *
 * Two sections:
 *   1. Available Colors — link/unlink colors to the parent type.
 *      Shows linked colors as pills with ✕ remove, and unlinked colors as
 *      dashed "+ Add" buttons.
 *   2. Device Grid — for each linked color, shows whether a part exists.
 *      Click to quick-create a new part, or click an existing part to edit.
 *
 * Color selection was moved here from EditTypePanel so that color linking
 * and part creation happen in the same place — one-stop per brand.
 */

import { useMemo } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  Tag, Package, Plus, Check, AlertTriangle, X, Palette,
} from 'lucide-react';
import { Badge } from '../../../../components/ui/Badge';
import { Spinner } from '../../../../components/ui/Spinner';
import {
  listTypeColors, linkColorsToType, unlinkColorFromType,
  listPartsForTypeBrand, quickCreatePart, listColors,
} from '../../../../api/parts';
import type { SelectedCategoryNode, PartListItem } from '../../../../lib/types';


export interface BrandColorPanelProps {
  typeId: number;
  brandId: number | null;   // null = General
  brandName: string;
  categoryId: number;
  styleId: number;
  canEdit: boolean;
  onSelectPart: (node: SelectedCategoryNode) => void;
}

export function BrandColorPanel({
  typeId, brandId, brandName, categoryId, styleId, canEdit, onSelectPart,
}: BrandColorPanelProps) {
  const queryClient = useQueryClient();
  const isGeneral = brandId === null;

  // ── All global colors (for linking UI) ──────────
  const { data: allColors } = useQuery({
    queryKey: ['colors'],
    queryFn: () => listColors(),
  });

  // ── Colors linked to this type ──────────────────
  const { data: colorLinks, isLoading: colorsLoading } = useQuery({
    queryKey: ['type-colors', typeId],
    queryFn: () => listTypeColors(typeId),
  });

  // ── Existing parts under this type+brand combo ──
  const { data: existingParts, isLoading: partsLoading } = useQuery({
    queryKey: ['type-brand-parts', typeId, brandId ?? 0],
    queryFn: () => listPartsForTypeBrand(typeId, brandId),
  });

  // ── Color link/unlink mutations ─────────────────
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

  // ── Quick-create part mutation ──────────────────
  const createMutation = useMutation({
    mutationFn: (colorId: number) => quickCreatePart(typeId, brandId, colorId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['type-brand-parts', typeId, brandId ?? 0] });
      queryClient.invalidateQueries({ queryKey: ['type-brands', typeId] });
      queryClient.invalidateQueries({ queryKey: ['types'] });
    },
  });

  // ── Derived data ────────────────────────────────
  const linkedColorIds = useMemo(
    () => new Set((colorLinks ?? []).map((l) => l.color_id)),
    [colorLinks],
  );

  const unlinkedColors = (allColors ?? []).filter(
    (c) => !linkedColorIds.has(c.id) && c.is_active,
  );

  const partsByColorId = useMemo(() => {
    const map = new Map<number, PartListItem>();
    (existingParts ?? []).forEach((p) => {
      if (p.color_id != null) map.set(p.color_id, p);
    });
    return map;
  }, [existingParts]);

  const isLoading = colorsLoading || partsLoading;

  return (
    <div className="flex flex-col h-full">
      {/* ── Header ──────────────────────────────── */}
      <div className="px-6 py-4 border-b border-gray-200 dark:border-gray-700 bg-gray-50 dark:bg-gray-800/80">
        <div className="flex items-center gap-2">
          {isGeneral ? (
            <Package className="h-5 w-5 text-gray-500" />
          ) : (
            <Tag className="h-5 w-5 text-amber-500" />
          )}
          <h3 className="text-lg font-semibold text-gray-900 dark:text-gray-100">
            {brandName}
          </h3>
          <Badge variant={isGeneral ? 'default' : 'warning'}>
            {isGeneral ? 'General' : 'Branded'}
          </Badge>
        </div>
        <p className="text-sm text-gray-500 dark:text-gray-400 mt-0.5">
          {isGeneral ? 'Unbranded commodity parts' : `Parts manufactured by ${brandName}`}
          {' '}&middot; {existingParts?.length ?? 0} parts created
        </p>
        {!isGeneral && (
          <p className="text-xs text-amber-600 dark:text-amber-400 mt-1 flex items-center gap-1">
            <AlertTriangle className="h-3 w-3" />
            Branded parts need a Manufacturer Part Number (MPN)
          </p>
        )}
      </div>

      {/* ── Scrollable content ──────────────────── */}
      <div className="flex-1 overflow-y-auto">
        {isLoading ? (
          <div className="flex items-center justify-center py-8">
            <Spinner size="lg" />
          </div>
        ) : (
          <>
            {/* ── Section 1: Color Selection ────── */}
            <div className="p-6 border-b border-gray-200 dark:border-gray-700">
              <h4 className="text-sm font-semibold text-gray-700 dark:text-gray-300 flex items-center gap-2 mb-3">
                <Palette className="h-4 w-4 text-primary-500" />
                Available Colors ({colorLinks?.length ?? 0})
              </h4>
              <p className="text-xs text-gray-500 dark:text-gray-400 mb-3">
                Select which colors are available for this type. Each linked color becomes a device you can create below.
              </p>

              {/* Linked colors as removable pills */}
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
                  <p className="text-sm text-gray-400 italic">No colors linked yet — add colors below to start creating parts.</p>
                )}
              </div>

              {/* Unlinked colors as add buttons */}
              {canEdit && unlinkedColors.length > 0 && (
                <div>
                  <p className="text-xs text-gray-500 dark:text-gray-400 mb-2">
                    Click to add a color:
                  </p>
                  <div className="flex flex-wrap gap-1.5">
                    {unlinkedColors.map((color) => (
                      <button
                        key={color.id}
                        className="inline-flex items-center gap-1 text-xs px-2 py-1 rounded-full border border-dashed border-gray-300 dark:border-gray-600 hover:border-primary-400 hover:bg-primary-50 dark:hover:bg-primary-900/20 transition-colors"
                        onClick={() => linkColorMutation.mutate([color.id])}
                        title={`Add ${color.name}`}
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

              {(linkColorMutation.isError || unlinkColorMutation.isError) && (
                <p className="text-red-500 text-xs mt-2">
                  Failed to update colors. A color may have parts linked to it.
                </p>
              )}
            </div>

            {/* ── Section 2: Device Grid ────────── */}
            <div className="p-6">
              <h4 className="text-sm font-semibold text-gray-700 dark:text-gray-300 flex items-center gap-2 mb-3">
                <Package className="h-4 w-4 text-teal-500" />
                Devices ({existingParts?.length ?? 0})
              </h4>

              {!colorLinks || colorLinks.length === 0 ? (
                <p className="text-sm text-gray-400 italic py-2">
                  Add colors above first, then create devices for each color.
                </p>
              ) : (
                <>
                  <p className="text-xs text-gray-500 dark:text-gray-400 mb-3">
                    Click a color to create a part, or click an existing part to edit it.
                  </p>
                  <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
                    {colorLinks.map((link) => {
                      const existingPart = partsByColorId.get(link.color_id);
                      const hasPart = !!existingPart;

                      return (
                        <button
                          key={link.color_id}
                          className={`flex items-center gap-3 px-3 py-2.5 rounded-lg border text-left transition-all ${
                            hasPart
                              ? 'border-green-200 bg-green-50 dark:border-green-800 dark:bg-green-900/20 hover:bg-green-100 dark:hover:bg-green-900/30'
                              : 'border-dashed border-gray-300 dark:border-gray-600 hover:border-primary-400 hover:bg-primary-50 dark:hover:bg-primary-900/20'
                          }`}
                          onClick={() => {
                            if (hasPart) {
                              onSelectPart({
                                type: 'part',
                                id: existingPart.id,
                                partId: existingPart.id,
                                typeId,
                                styleId,
                                categoryId,
                                brandId,
                                colorId: link.color_id,
                              });
                            } else if (canEdit) {
                              createMutation.mutate(link.color_id);
                            }
                          }}
                          disabled={!hasPart && !canEdit}
                        >
                          {/* Color swatch */}
                          <span
                            className="w-6 h-6 rounded-full border-2 flex-shrink-0"
                            style={{
                              backgroundColor: link.hex_code ?? '#ccc',
                              borderColor: hasPart ? '#22c55e' : '#d1d5db',
                            }}
                          >
                            {hasPart && (
                              <Check className="h-4 w-4 text-white m-0.5" style={{ filter: 'drop-shadow(0 0 1px rgba(0,0,0,0.5))' }} />
                            )}
                          </span>

                          {/* Color info */}
                          <div className="flex-1 min-w-0">
                            <div className="text-sm font-medium truncate">
                              {link.color_name ?? 'Unknown'}
                            </div>
                            {hasPart ? (
                              <div className="text-xs text-gray-500 dark:text-gray-400 truncate">
                                {existingPart.manufacturer_part_number
                                  ? `MPN: ${existingPart.manufacturer_part_number}`
                                  : (!isGeneral ? 'MPN needed' : 'Created')
                                }
                              </div>
                            ) : (
                              <div className="text-xs text-gray-500 dark:text-gray-400">
                                Click to create
                              </div>
                            )}
                          </div>

                          {/* Status indicator */}
                          {hasPart ? (
                            existingPart.is_deprecated ? (
                              <Badge variant="danger" className="text-[10px]">DEP</Badge>
                            ) : !isGeneral && !existingPart.manufacturer_part_number ? (
                              <AlertTriangle className="h-4 w-4 text-amber-400 flex-shrink-0" />
                            ) : null
                          ) : (
                            <Plus className="h-4 w-4 text-gray-400 flex-shrink-0" />
                          )}
                        </button>
                      );
                    })}
                  </div>

                  {createMutation.isError && (
                    <p className="text-red-500 text-sm mt-3">
                      {(createMutation.error as any)?.response?.data?.detail ?? 'Failed to create part.'}
                    </p>
                  )}
                </>
              )}
            </div>
          </>
        )}
      </div>
    </div>
  );
}
