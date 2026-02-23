/**
 * InventoryGridPage — visual grid of warehouse bin locations.
 *
 * Stub page. Will display a spatial map of bins with stock levels.
 */

import { Grid3x3 } from 'lucide-react';
import { EmptyState } from '../../../components/ui/EmptyState';

export function InventoryGridPage() {
  return (
    <EmptyState
      icon={<Grid3x3 className="h-12 w-12" />}
      title="Inventory Grid"
      description="Visual warehouse grid showing bin locations and stock levels. Coming soon."
    />
  );
}
