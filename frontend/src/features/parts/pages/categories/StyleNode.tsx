/**
 * StyleNode — second-level tree node (per-category visual/form-factor).
 *
 * Expand → fetches child types via listTypesByStyle.
 * Click → selects style for right-panel editing.
 * "+" → triggers type creation.
 */

import { useQuery } from '@tanstack/react-query';
import { ChevronDown, ChevronRight, Box, Plus } from 'lucide-react';
import { Badge } from '../../../../components/ui/Badge';
import { Spinner } from '../../../../components/ui/Spinner';
import { listTypesByStyle } from '../../../../api/parts';
import type { PartStyle, SelectedCategoryNode } from '../../../../lib/types';
import { TypeNode } from './TypeNode';


export interface StyleNodeProps {
  style: PartStyle;
  categoryId: number;
  isExpanded: boolean;
  onToggle: () => void;
  selected: SelectedCategoryNode | null;
  onSelect: (node: SelectedCategoryNode) => void;
  canEdit: boolean;
  expandedTypes: Set<number>;
  onToggleType: (id: number) => void;
  onCreateType: (styleId: number) => void;
}

export function StyleNode({
  style, categoryId, isExpanded, onToggle,
  selected, onSelect, canEdit,
  expandedTypes, onToggleType, onCreateType,
}: StyleNodeProps) {
  const isSelected = selected?.type === 'style' && selected.id === style.id;

  const { data: types, isLoading: typesLoading } = useQuery({
    queryKey: ['types', style.id],
    queryFn: () => listTypesByStyle(style.id),
    enabled: isExpanded,
  });

  return (
    <div>
      {/* Style row */}
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
        <Box className="h-3.5 w-3.5 text-indigo-500 flex-shrink-0" />
        <button
          className="flex-1 text-left text-sm truncate"
          onClick={() => onSelect({ type: 'style', id: style.id, categoryId })}
        >
          {style.name}
        </button>
        {!style.is_active && (
          <Badge variant="default" className="text-[10px] px-1.5 py-0">Off</Badge>
        )}
        <span className="text-[10px] text-gray-400 mr-1">
          {style.type_count}t / {style.part_count}p
        </span>
        {canEdit && (
          <button
            className="p-0.5 rounded hover:bg-gray-200 dark:hover:bg-gray-600 opacity-0 group-hover:opacity-100 transition-opacity"
            onClick={(e) => {
              e.stopPropagation();
              onCreateType(style.id);
            }}
            title="Add Type"
          >
            <Plus className="h-3 w-3 text-gray-500" />
          </button>
        )}
      </div>

      {/* Children (types) */}
      {isExpanded && (
        <div className="ml-4 pl-2 border-l border-gray-200 dark:border-gray-700">
          {typesLoading ? (
            <div className="flex items-center gap-2 py-2 pl-2 text-xs text-gray-400">
              <Spinner size="sm" /> Loading types...
            </div>
          ) : !types || types.length === 0 ? (
            <p className="text-xs text-gray-400 italic py-1.5 pl-2">
              No types yet
            </p>
          ) : (
            types.map((type) => (
              <TypeNode
                key={type.id}
                type={type}
                styleId={style.id}
                categoryId={categoryId}
                isExpanded={expandedTypes.has(type.id)}
                onToggle={() => onToggleType(type.id)}
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
