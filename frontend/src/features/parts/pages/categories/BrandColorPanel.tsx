/**
 * BrandColorPanel — right-panel for managing parts under a Brand/General node.
 *
 * Shows all available colors (from type_color_links) for this type.
 * Each color is a toggle:
 *   - Checked (part exists) → shows part info, click to view/edit
 *   - Unchecked (no part) → click to quick-create the Part
 *
 * For branded parts: shows MPN input inline per existing color.
 */

import { useMemo } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  Tag, Package, Plus, Check, AlertTriangle,
} from 'lucide-react';
import { Badge } from '../../../../components/ui/Badge';
import { Spinner } from '../../../../components/ui/Spinner';
import {
  listTypeColors, listPartsForTypeBrand, quickCreatePart,
} from '../../../../api/parts';
import type { SelectedCategoryNode, PartListItem, TypeColorLink } from '../../../../lib/types';


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

  // Available colors for this type (from type_color_links)
  const { data: colorLinks, isLoading: colorsLoading } = useQuery({
    queryKey: ['type-colors', typeId],
    queryFn: () => listTypeColors(typeId),
  });

  // Existing parts under this type+brand combo
  const { data: existingParts, isLoading: partsLoading } = useQuery({
    queryKey: ['type-brand-parts', typeId, brandId ?? 0],
    queryFn: () => listPartsForTypeBrand(typeId, brandId),
  });

  // Quick-create mutation
  const createMutation = useMutation({
    mutationFn: (colorId: number) => quickCreatePart(typeId, brandId, colorId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['type-brand-parts', typeId, brandId ?? 0] });
      queryClient.invalidateQueries({ queryKey: ['type-brands', typeId] });
      queryClient.invalidateQueries({ queryKey: ['types'] });
    },
  });

  // Map color_id → existing part for quick lookup
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
      {/* Header */}
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

      {/* Color grid */}
      <div className="flex-1 overflow-y-auto p-6">
        {isLoading ? (
          <div className="flex items-center justify-center py-8">
            <Spinner size="lg" />
          </div>
        ) : !colorLinks || colorLinks.length === 0 ? (
          <div className="text-center py-8">
            <p className="text-gray-500 dark:text-gray-400 text-sm">
              No colors available for this type.
            </p>
            <p className="text-gray-400 dark:text-gray-500 text-xs mt-1">
              Link colors to this type first (select the type node above).
            </p>
          </div>
        ) : (
          <>
            <p className="text-xs text-gray-500 dark:text-gray-400 mb-3">
              Click a color to create a part, or click an existing part to edit it.
            </p>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
              {colorLinks.map((link) => {
                const existingPart = partsByColorId.get(link.color_id);
                const haspart = !!existingPart;

                return (
                  <button
                    key={link.color_id}
                    className={`flex items-center gap-3 px-3 py-2.5 rounded-lg border text-left transition-all ${
                      haspart
                        ? 'border-green-200 bg-green-50 dark:border-green-800 dark:bg-green-900/20 hover:bg-green-100 dark:hover:bg-green-900/30'
                        : 'border-dashed border-gray-300 dark:border-gray-600 hover:border-primary-400 hover:bg-primary-50 dark:hover:bg-primary-900/20'
                    }`}
                    onClick={() => {
                      if (haspart) {
                        // Navigate to part detail
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
                        // Quick-create
                        createMutation.mutate(link.color_id);
                      }
                    }}
                    disabled={!haspart && !canEdit}
                  >
                    {/* Color swatch */}
                    <span
                      className="w-6 h-6 rounded-full border-2 flex-shrink-0"
                      style={{
                        backgroundColor: link.hex_code ?? '#ccc',
                        borderColor: haspart ? '#22c55e' : '#d1d5db',
                      }}
                    >
                      {haspart && (
                        <Check className="h-4 w-4 text-white m-0.5" style={{ filter: 'drop-shadow(0 0 1px rgba(0,0,0,0.5))' }} />
                      )}
                    </span>

                    {/* Color info */}
                    <div className="flex-1 min-w-0">
                      <div className="text-sm font-medium truncate">
                        {link.color_name ?? 'Unknown'}
                      </div>
                      {haspart ? (
                        <div className="text-xs text-gray-500 dark:text-gray-400 truncate">
                          {existingPart.manufacturer_part_number
                            ? `MPN: ${existingPart.manufacturer_part_number}`
                            : (!isGeneral ? 'MPN needed' : 'Created')
                          }
                        </div>
                      ) : (
                        <div className="text-xs text-gray-400 dark:text-gray-500">
                          Click to create
                        </div>
                      )}
                    </div>

                    {/* Status indicator */}
                    {haspart ? (
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
    </div>
  );
}
