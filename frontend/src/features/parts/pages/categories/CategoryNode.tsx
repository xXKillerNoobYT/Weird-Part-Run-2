/**
 * CategoryNode — top-level tree node in the part hierarchy.
 *
 * Expand → fetches child styles via listStylesByCategory.
 * Click → selects category for right-panel editing.
 * "+" → triggers style creation.
 */

import { useQuery } from '@tanstack/react-query';
import { ChevronDown, ChevronRight, Layers, Plus } from 'lucide-react';
import { Badge } from '../../../../components/ui/Badge';
import { Spinner } from '../../../../components/ui/Spinner';
import { listStylesByCategory } from '../../../../api/parts';
import type { PartCategory, SelectedCategoryNode } from '../../../../lib/types';
import { StyleNode } from './StyleNode';


export interface CategoryNodeProps {
  category: PartCategory;
  isExpanded: boolean;
  onToggle: () => void;
  selected: SelectedCategoryNode | null;
  onSelect: (node: SelectedCategoryNode) => void;
  canEdit: boolean;
  onCreateChild: (categoryId: number) => void;
  expandedStyles: Set<number>;
  onToggleStyle: (id: number) => void;
  expandedTypes: Set<number>;
  onToggleType: (id: number) => void;
  onCreateType: (styleId: number, categoryId: number) => void;
}

export function CategoryNode({
  category, isExpanded, onToggle,
  selected, onSelect, canEdit, onCreateChild,
  expandedStyles, onToggleStyle, expandedTypes, onToggleType, onCreateType,
}: CategoryNodeProps) {
  const isSelected = selected?.type === 'category' && selected.id === category.id;

  const { data: styles, isLoading: stylesLoading } = useQuery({
    queryKey: ['styles', category.id],
    queryFn: () => listStylesByCategory(category.id),
    enabled: isExpanded,
  });

  return (
    <div>
      {/* Category row */}
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
        <Layers className="h-4 w-4 text-primary-500 flex-shrink-0" />
        <button
          className="flex-1 text-left text-sm font-medium truncate"
          onClick={() => onSelect({ type: 'category', id: category.id })}
        >
          {category.name}
        </button>
        {!category.is_active && (
          <Badge variant="default" className="text-[10px] px-1.5 py-0">Off</Badge>
        )}
        <span className="text-[10px] text-gray-400 mr-1">
          {category.style_count}s / {category.part_count}p
        </span>
        {canEdit && (
          <button
            className="p-0.5 rounded hover:bg-gray-200 dark:hover:bg-gray-600 opacity-0 group-hover:opacity-100 transition-opacity"
            onClick={(e) => {
              e.stopPropagation();
              onCreateChild(category.id);
            }}
            title="Add Style"
          >
            <Plus className="h-3 w-3 text-gray-500" />
          </button>
        )}
      </div>

      {/* Children (styles) */}
      {isExpanded && (
        <div className="ml-4 pl-2 border-l border-gray-200 dark:border-gray-700">
          {stylesLoading ? (
            <div className="flex items-center gap-2 py-2 pl-2 text-xs text-gray-400">
              <Spinner size="sm" /> Loading styles...
            </div>
          ) : !styles || styles.length === 0 ? (
            <p className="text-xs text-gray-400 italic py-1.5 pl-2">
              No styles yet
            </p>
          ) : (
            styles.map((style) => (
              <StyleNode
                key={style.id}
                style={style}
                categoryId={category.id}
                isExpanded={expandedStyles.has(style.id)}
                onToggle={() => onToggleStyle(style.id)}
                selected={selected}
                onSelect={onSelect}
                canEdit={canEdit}
                expandedTypes={expandedTypes}
                onToggleType={onToggleType}
                onCreateType={(styleId) => onCreateType(styleId, category.id)}
              />
            ))
          )}
        </div>
      )}
    </div>
  );
}
