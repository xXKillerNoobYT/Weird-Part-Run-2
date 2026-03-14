/**
 * SupplierBrandsSection — displays linked brands in the expanded supplier detail.
 */

import { useQuery } from '@tanstack/react-query';
import { Tag } from 'lucide-react';
import { Spinner } from '../../../../components/ui/Spinner';
import { getSupplierBrands } from '../../../../api/parts';


export function SupplierBrandsSection({
  supplierId,
  supplierName: _supplierName,
}: {
  supplierId: number;
  supplierName: string;
}) {
  const { data: links, isLoading } = useQuery({
    queryKey: ['supplier-brands', supplierId],
    queryFn: () => getSupplierBrands(supplierId),
  });

  return (
    <div className="mt-3 pt-3 border-t border-gray-100 dark:border-gray-700/50">
      <h4 className="text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400 flex items-center gap-1.5 mb-2">
        <Tag className="h-3.5 w-3.5" />
        Brands Carried
      </h4>

      {isLoading ? (
        <div className="flex items-center gap-2 text-sm text-gray-500">
          <Spinner size="sm" /> Loading...
        </div>
      ) : (links ?? []).length === 0 ? (
        <p className="text-sm text-gray-400 italic">
          No brands linked. Link brands from the Brands tab.
        </p>
      ) : (
        <div className="flex flex-wrap gap-2">
          {(links ?? []).map((link) => (
            <div
              key={link.id}
              className="inline-flex items-center gap-1.5 px-3 py-1.5 bg-white dark:bg-gray-800 rounded-lg border border-gray-200 dark:border-gray-700 text-sm"
            >
              <Tag className="h-3.5 w-3.5 text-primary-500" />
              <span className="font-medium text-gray-900 dark:text-gray-100">
                {link.brand_name}
              </span>
              {link.account_number && (
                <span className="text-xs text-gray-500 dark:text-gray-400">
                  ({link.account_number})
                </span>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
