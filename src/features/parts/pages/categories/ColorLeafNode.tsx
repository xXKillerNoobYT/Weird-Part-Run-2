/**
 * ColorLeafNode — leaf node in the hierarchy tree.
 *
 * Each leaf represents an actual Part record, displayed as a color chip.
 * Click → selects the part for right-panel PartDetailPanel.
 */

import type { PartListItem, SelectedCategoryNode } from '../../../../lib/types';


export interface ColorLeafNodeProps {
  part: PartListItem;
  typeId: number;
  styleId: number;
  categoryId: number;
  brandId: number | null;
  selected: SelectedCategoryNode | null;
  onSelect: (node: SelectedCategoryNode) => void;
}

export function ColorLeafNode({
  part, typeId, styleId, categoryId, brandId, selected, onSelect,
}: ColorLeafNodeProps) {
  const isSelected = selected?.type === 'part' && selected.partId === part.id;

  return (
    <button
      className={`flex items-center gap-1.5 w-full px-2 py-1 rounded-lg text-left transition-colors ${
        isSelected
          ? 'bg-primary-50 dark:bg-primary-900/30 text-primary-700 dark:text-primary-300'
          : 'hover:bg-gray-100 dark:hover:bg-gray-700/50'
      }`}
      onClick={() => onSelect({
        type: 'part',
        id: part.id,
        partId: part.id,
        typeId,
        styleId,
        categoryId,
        brandId,
        colorId: part.color_id ?? undefined,
      })}
    >
      {/* Color swatch */}
      <span
        className="inline-block w-3 h-3 rounded-full border border-gray-300 dark:border-gray-500 flex-shrink-0"
        style={{ backgroundColor: part.color_hex ?? '#ccc' }}
      />
      {/* Color name / part name */}
      <span className="text-xs truncate flex-1">
        {part.color_name ?? part.name}
      </span>
      {/* Deprecated indicator */}
      {part.is_deprecated && (
        <span className="text-[9px] text-red-400 font-medium">DEP</span>
      )}
      {/* Missing MPN indicator for branded parts */}
      {part.brand_id !== null && !part.manufacturer_part_number && (
        <span className="text-[9px] text-amber-500 font-medium" title="MPN needed">!</span>
      )}
    </button>
  );
}
