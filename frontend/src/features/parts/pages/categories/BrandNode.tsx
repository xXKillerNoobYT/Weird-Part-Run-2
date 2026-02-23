/**
 * BrandNode — fourth-level tree node under a Type.
 *
 * Represents a brand (or "General") enabled for a specific part type.
 * Expand → shows color leaf nodes (= Part records) under this type+brand combo.
 * Click → selects brand for right-panel BrandColorPanel (pick colors / create parts).
 */

import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { ChevronDown, ChevronRight, Tag, Package } from 'lucide-react';
import { Badge } from '../../../../components/ui/Badge';
import { Spinner } from '../../../../components/ui/Spinner';
import { listPartsForTypeBrand } from '../../../../api/parts';
import type { TypeBrandLink, SelectedCategoryNode } from '../../../../lib/types';
import { ColorLeafNode } from './ColorLeafNode';


export interface BrandNodeProps {
  link: TypeBrandLink;
  typeId: number;
  styleId: number;
  categoryId: number;
  selected: SelectedCategoryNode | null;
  onSelect: (node: SelectedCategoryNode) => void;
  canEdit: boolean;
}

export function BrandNode({
  link, typeId, styleId, categoryId, selected, onSelect, canEdit,
}: BrandNodeProps) {
  const [isExpanded, setIsExpanded] = useState(false);
  const isGeneral = link.brand_id === null;
  const displayName = isGeneral ? 'General' : (link.brand_name ?? 'Unknown');

  const isSelected =
    selected?.type === 'brand' &&
    selected.typeId === typeId &&
    selected.brandId === link.brand_id;

  // Fetch parts under this type+brand combo when expanded
  const { data: parts, isLoading: partsLoading } = useQuery({
    queryKey: ['type-brand-parts', typeId, link.brand_id ?? 0],
    queryFn: () => listPartsForTypeBrand(typeId, link.brand_id),
    enabled: isExpanded,
  });

  return (
    <div>
      {/* Brand row */}
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
            setIsExpanded(!isExpanded);
          }}
        >
          {isExpanded ? (
            <ChevronDown className="h-3.5 w-3.5 text-gray-500" />
          ) : (
            <ChevronRight className="h-3.5 w-3.5 text-gray-500" />
          )}
        </button>
        {isGeneral ? (
          <Package className="h-3.5 w-3.5 text-gray-500 flex-shrink-0" />
        ) : (
          <Tag className="h-3.5 w-3.5 text-amber-500 flex-shrink-0" />
        )}
        <button
          className="flex-1 text-left text-sm truncate"
          onClick={() => onSelect({
            type: 'brand',
            id: link.id,
            typeId,
            styleId,
            categoryId,
            brandId: link.brand_id,
          })}
        >
          {displayName}
        </button>
        {link.part_count > 0 && (
          <Badge variant="default" className="text-[10px] px-1.5 py-0">
            {link.part_count}
          </Badge>
        )}
      </div>

      {/* Children: color leaf nodes (= Part records) */}
      {isExpanded && (
        <div className="ml-4 pl-2 border-l border-gray-200 dark:border-gray-700">
          {partsLoading ? (
            <div className="flex items-center gap-2 py-1 pl-2 text-xs text-gray-400">
              <Spinner size="sm" /> Loading parts...
            </div>
          ) : !parts || parts.length === 0 ? (
            <p className="text-xs text-gray-400 italic py-1 pl-2">
              No parts yet — select to add colors
            </p>
          ) : (
            parts.map((part) => (
              <ColorLeafNode
                key={part.id}
                part={part}
                typeId={typeId}
                styleId={styleId}
                categoryId={categoryId}
                brandId={link.brand_id}
                selected={selected}
                onSelect={onSelect}
              />
            ))
          )}
        </div>
      )}
    </div>
  );
}
