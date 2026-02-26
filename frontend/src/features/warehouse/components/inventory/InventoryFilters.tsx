/**
 * InventoryFilters — search bar, category/brand dropdowns,
 * and stock status chip toggles.
 */

import { Search } from 'lucide-react';
import { Input } from '../../../../components/ui/Input';
import { cn } from '../../../../lib/utils';
import type { StockStatus } from '../../../../lib/types';

const STATUS_OPTIONS: { label: string; value: StockStatus }[] = [
  { label: 'All', value: 'all' },
  { label: 'Low Stock', value: 'low_stock' },
  { label: 'Overstock', value: 'overstock' },
  { label: 'In Range', value: 'in_range' },
  { label: 'Winding Down', value: 'winding_down' },
  { label: 'Zero', value: 'zero' },
];

interface InventoryFiltersProps {
  search: string;
  onSearchChange: (value: string) => void;
  stockStatus: StockStatus;
  onStockStatusChange: (status: StockStatus) => void;
}

export function InventoryFilters({
  search,
  onSearchChange,
  stockStatus,
  onStockStatusChange,
}: InventoryFiltersProps) {
  return (
    <div className="space-y-4">
      {/* Search */}
      <div className="max-w-md">
        <Input
          placeholder="Search parts..."
          icon={<Search className="h-4 w-4" />}
          value={search}
          onChange={(e) => onSearchChange(e.target.value)}
        />
      </div>

      {/* Stock status chips */}
      <div className="flex flex-wrap gap-2">
        {STATUS_OPTIONS.map((option) => (
          <button
            key={option.value}
            onClick={() => onStockStatusChange(option.value)}
            className={cn(
              'px-3 py-1.5 rounded-full text-xs font-medium transition-colors',
              stockStatus === option.value
                ? 'bg-primary-500 text-white'
                : 'bg-gray-100 text-gray-600 hover:bg-gray-200 dark:bg-gray-700 dark:text-gray-300 dark:hover:bg-gray-600',
            )}
          >
            {option.label}
          </button>
        ))}
      </div>
    </div>
  );
}
