/**
 * InventoryTab — shows parts loaded on the vehicle with search.
 */

import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Package, Search, X } from 'lucide-react';
import { PageSpinner } from '../../../../components/ui/Spinner';
import { EmptyState } from '../../../../components/ui/EmptyState';
import { Input } from '../../../../components/ui/Input';
import { PartIdentity } from '../../../../components/ui/PartIdentity';
import { getVehicleInventory } from '../../../../api/vehicles';


export function InventoryTab({ vehicleId }: { vehicleId: number }) {
  const [search, setSearch] = useState('');

  const { data: inventory, isLoading } = useQuery({
    queryKey: ['vehicle-inventory', vehicleId, search],
    queryFn: () => getVehicleInventory(vehicleId, { search: search || undefined }),
    staleTime: 15_000,
  });

  if (isLoading) return <PageSpinner label="Loading inventory..." />;

  return (
    <div className="space-y-3">
      <div className="flex items-center gap-3 flex-wrap">
        <div className="flex-1 min-w-[200px]">
          <Input
            placeholder="Search parts on vehicle..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            icon={<Search className="h-4 w-4" />}
            iconRight={
              search ? (
                <button onClick={() => setSearch('')} className="text-gray-400 hover:text-gray-600">
                  <X className="h-4 w-4" />
                </button>
              ) : undefined
            }
          />
        </div>
      </div>

      {!inventory || inventory.length === 0 ? (
        <EmptyState
          icon={<Package className="h-12 w-12" />}
          title={search ? 'No parts match' : 'No Parts on Vehicle'}
          description={search ? 'Try a different search term.' : 'Add parts to this vehicle from the warehouse.'}
        />
      ) : (
        <>
          <p className="text-xs text-gray-500 dark:text-gray-400">
            {inventory.length} part{inventory.length !== 1 ? 's' : ''} on vehicle
          </p>
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-border text-left text-xs text-gray-500 dark:text-gray-400">
                  <th className="pb-2 font-medium">Part</th>
                  <th className="pb-2 font-medium">Category</th>
                  <th className="pb-2 font-medium text-right">Qty</th>
                  <th className="pb-2 font-medium">Supplier</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-border">
                {inventory.map((item) => (
                  <tr key={item.id}>
                    <td className="py-2">
                      <PartIdentity
                        compact
                        partName={item.part_description}
                        partNumber={item.part_number}
                        partId={item.part_id}
                        brandName={item.brand}
                        categoryName={item.category}
                      />
                    </td>
                    <td className="py-2 text-gray-500 dark:text-gray-400">{item.category ?? '—'}</td>
                    <td className="py-2 text-right font-mono">{item.qty}</td>
                    <td className="py-2 text-gray-500 dark:text-gray-400">{item.supplier_name ?? '—'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </>
      )}
    </div>
  );
}
