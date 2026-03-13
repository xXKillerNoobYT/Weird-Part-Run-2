/**
 * ColorList — global color entries in the left pane.
 *
 * Shows all defined colors with swatches. Click to edit in right panel.
 * This is for managing the global color palette, not for part creation.
 */

import { Badge } from '../../../../components/ui/Badge';
import type { PartColor, SelectedCategoryNode } from '../../../../lib/types';


export interface ColorListProps {
  colors: PartColor[];
  selected: SelectedCategoryNode | null;
  onSelect: (node: SelectedCategoryNode) => void;
  canEdit: boolean;
}

export function ColorList({ colors, selected, onSelect }: ColorListProps) {
  return (
    <div className="space-y-0.5">
      {colors.map((color) => {
        const isSelected = selected?.type === 'color' && selected.id === color.id;
        return (
          <button
            key={color.id}
            className={`flex items-center gap-2 w-full px-2 py-1.5 rounded-lg text-left transition-colors ${
              isSelected
                ? 'bg-primary-50 dark:bg-primary-900/30 text-primary-700 dark:text-primary-300'
                : 'hover:bg-gray-100 dark:hover:bg-gray-700/50'
            }`}
            onClick={() => onSelect({ type: 'color', id: color.id })}
          >
            <span
              className="inline-block w-4 h-4 rounded-full border border-gray-300 dark:border-gray-500 flex-shrink-0"
              style={{ backgroundColor: color.hex_code ?? '#ccc' }}
            />
            <span className="text-sm truncate flex-1">{color.name}</span>
            {!color.is_active && (
              <Badge variant="default" className="text-[10px] px-1.5 py-0">Off</Badge>
            )}
            <span className="text-[10px] text-gray-400">{color.part_count}p</span>
          </button>
        );
      })}
    </div>
  );
}
