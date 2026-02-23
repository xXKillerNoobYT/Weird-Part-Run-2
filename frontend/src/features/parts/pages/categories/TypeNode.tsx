/**
 * TypeNode — third-level tree node (per-style functional variety).
 *
 * When expanded, shows:
 *   1. Brand/General nodes (from type_brand_links) as expandable BrandNodes
 *   2. Each BrandNode shows color leaves (= Part records)
 *
 * Click → selects type for right-panel editing (with brand checkboxes).
 */

import { useQuery } from '@tanstack/react-query';
import {
  ChevronDown, ChevronRight, Box, Package, Tag,
} from 'lucide-react';
import { Badge } from '../../../../components/ui/Badge';
import { Spinner } from '../../../../components/ui/Spinner';
import { listTypeBrands } from '../../../../api/parts';
import type { PartType, SelectedCategoryNode } from '../../../../lib/types';
import { BrandNode } from './BrandNode';


export interface TypeNodeProps {
  type: PartType;
  styleId: number;
  categoryId: number;
  isExpanded: boolean;
  onToggle: () => void;
  selected: SelectedCategoryNode | null;
  onSelect: (node: SelectedCategoryNode) => void;
  canEdit: boolean;
}

export function TypeNode({
  type, styleId, categoryId, isExpanded, onToggle, selected, onSelect, canEdit,
}: TypeNodeProps) {
  const isSelected = selected?.type === 'type' && selected.id === type.id;

  // Fetch brand links when expanded
  const { data: brandLinks, isLoading: brandsLoading } = useQuery({
    queryKey: ['type-brands', type.id],
    queryFn: () => listTypeBrands(type.id),
    enabled: isExpanded,
  });

  return (
    <div>
      {/* Type row */}
      <div
        className={`flex items-center gap-1 px-2 py-1.5 rounded-lg cursor-pointer transition-colors group ${
          isSelected
            ? 'bg-primary-50 dark:bg-primary-900/30 text-primary-700 dark:text-primary-300'
            : 'hover:bg-gray-100 dark:hover:bg-gray-700/50'
        }`}
      >
        <button
          className="p-0.5 rounded hover:bg-gray-200 dark:hover:bg-gray-600 flex-shrink-0"
          onClick={(e) => {
            e.stopPropagation();
            onToggle();
          }}
        >
          {isExpanded ? (
            <ChevronDown className="h-3.5 w-3.5 text-gray-500" />
          ) : (
            <ChevronRight className="h-3.5 w-3.5 text-gray-500" />
          )}
        </button>
        <Box className="h-3 w-3 text-teal-500 flex-shrink-0" />
        <button
          className="flex-1 text-left text-sm truncate"
          onClick={() => onSelect({
            type: 'type',
            id: type.id,
            styleId,
            categoryId,
          })}
        >
          {type.name}
        </button>
        {!type.is_active && (
          <Badge variant="default" className="text-[10px] px-1.5 py-0">Off</Badge>
        )}
        {type.part_count > 0 && (
          <span className="text-[10px] text-gray-400 mr-1">{type.part_count}p</span>
        )}
      </div>

      {/* Children: brand/general nodes */}
      {isExpanded && (
        <div className="ml-4 pl-2 border-l border-gray-200 dark:border-gray-700">
          {brandsLoading ? (
            <div className="flex items-center gap-2 py-2 pl-2 text-xs text-gray-400">
              <Spinner size="sm" /> Loading brands...
            </div>
          ) : !brandLinks || brandLinks.length === 0 ? (
            <p className="text-xs text-gray-400 italic py-1.5 pl-2">
              No brands enabled — select this type to configure
            </p>
          ) : (
            brandLinks.map((link) => (
              <BrandNode
                key={link.id}
                link={link}
                typeId={type.id}
                styleId={styleId}
                categoryId={categoryId}
                selected={selected}
                onSelect={onSelect}
                canEdit={canEdit}
              />
            ))
          )}
        </div>
      )}
    </div>
  );
}
