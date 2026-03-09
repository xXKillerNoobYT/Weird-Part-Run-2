/**
 * WarehouseNetworkPage — multi-warehouse overview with stock summary.
 *
 * Shows all warehouse locations as cards, each with key metrics like
 * total SKUs, total stock, and trailer count. Acts as the central
 * hub for seeing fleet-wide warehouse status.
 *
 * Route: /warehouse/network
 */

import { useQuery } from '@tanstack/react-query';
import { Link } from 'react-router-dom';
import {
  Warehouse,
  Container,
  MapPin,
  Phone,
  Star,
  ArrowRight,
  ChevronRight,
} from 'lucide-react';
import { PageSpinner } from '../../../components/ui/Spinner';
import { EmptyState } from '../../../components/ui/EmptyState';
import { Card } from '../../../components/ui/Card';
import { Badge } from '../../../components/ui/Badge';
import { Button } from '../../../components/ui/Button';
import { listWarehouseLocations, listTrailers } from '../../../api/vehicles';
import type { WarehouseLocation, JobTrailer } from '../../../lib/types';


export function WarehouseNetworkPage() {
  const { data: warehouses, isLoading: loadingWarehouses } = useQuery({
    queryKey: ['warehouse-locations'],
    queryFn: () => listWarehouseLocations({ include_inactive: false }),
    staleTime: 30_000,
  });

  const { data: trailers } = useQuery({
    queryKey: ['trailers'],
    queryFn: () => listTrailers(),
    staleTime: 30_000,
  });

  if (loadingWarehouses) return <PageSpinner label="Loading warehouse network..." />;

  const activeWarehouses = warehouses?.filter(w => w.is_active) ?? [];
  const activeTrailers = trailers?.filter(t => t.is_active) ?? [];

  return (
    <div className="space-y-6">
      {/* Summary strip */}
      <div className="flex items-center gap-4 flex-wrap">
        <div className="flex items-center gap-2 text-sm">
          <Warehouse className="h-4 w-4 text-primary-500" />
          <span className="font-semibold">{activeWarehouses.length}</span>
          <span className="text-gray-500 dark:text-gray-400">Warehouse{activeWarehouses.length !== 1 ? 's' : ''}</span>
        </div>
        <div className="flex items-center gap-2 text-sm">
          <Container className="h-4 w-4 text-primary-500" />
          <span className="font-semibold">{activeTrailers.length}</span>
          <span className="text-gray-500 dark:text-gray-400">Active Trailer{activeTrailers.length !== 1 ? 's' : ''}</span>
        </div>
        <div className="ml-auto">
          <Link to="/office/warehouse-locations">
            <Button variant="secondary" size="sm">
              Manage Locations
            </Button>
          </Link>
        </div>
      </div>

      {activeWarehouses.length === 0 ? (
        <EmptyState
          icon={<Warehouse className="h-12 w-12" />}
          title="No warehouses configured"
          description="Add warehouse locations in Office → Warehouse Locations to see the network view."
        />
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
          {activeWarehouses.map((wh) => (
            <WarehouseCard
              key={wh.id}
              warehouse={wh}
              trailers={activeTrailers.filter(t => t.home_warehouse_id === wh.id)}
            />
          ))}
        </div>
      )}

      {/* Unassigned trailers — trailers with no home warehouse */}
      {activeTrailers.filter(t => !t.home_warehouse_id).length > 0 && (
        <div className="space-y-3">
          <h3 className="text-sm font-semibold text-gray-700 dark:text-gray-300">
            Unassigned Trailers
          </h3>
          <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-3">
            {activeTrailers.filter(t => !t.home_warehouse_id).map((trailer) => (
              <Link key={trailer.id} to={`/trucks/trailers/${trailer.id}`}>
                <Card className="hover:shadow-md transition-shadow">
                  <div className="p-3 flex items-center gap-3">
                    <Container className="h-5 w-5 text-gray-400" />
                    <div className="flex-1 min-w-0">
                      <h4 className="text-sm font-medium truncate">{trailer.name}</h4>
                      <span className="text-xs font-mono text-gray-500">{trailer.trailer_code}</span>
                    </div>
                    <Badge variant="warning">No Home</Badge>
                    <ChevronRight className="h-4 w-4 text-gray-400" />
                  </div>
                </Card>
              </Link>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}


/** Individual warehouse location card with its trailers. */
function WarehouseCard({
  warehouse,
  trailers,
}: {
  warehouse: WarehouseLocation;
  trailers: JobTrailer[];
}) {
  const address = [warehouse.address_street, warehouse.address_city, warehouse.address_state]
    .filter(Boolean)
    .join(', ');

  return (
    <Card className="h-full">
      <div className="p-4 space-y-3">
        {/* Header */}
        <div className="flex items-start justify-between gap-2">
          <div className="min-w-0 flex-1">
            <div className="flex items-center gap-2">
              <Warehouse className="h-5 w-5 text-primary-500 shrink-0" />
              <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100 truncate">
                {warehouse.name}
              </h3>
            </div>
            {warehouse.is_primary && (
              <div className="flex items-center gap-1 mt-0.5">
                <Star className="h-3 w-3 text-amber-400" />
                <span className="text-[10px] text-amber-600 dark:text-amber-400 font-medium">Primary</span>
              </div>
            )}
          </div>
          <Badge variant="success">{trailers.length} trailer{trailers.length !== 1 ? 's' : ''}</Badge>
        </div>

        {/* Address + contact */}
        {address && (
          <div className="flex items-start gap-1.5 text-xs text-gray-500 dark:text-gray-400">
            <MapPin className="h-3.5 w-3.5 shrink-0 mt-0.5" />
            <span>{address}</span>
          </div>
        )}
        {warehouse.phone && (
          <div className="flex items-center gap-1.5 text-xs text-gray-500 dark:text-gray-400">
            <Phone className="h-3.5 w-3.5 shrink-0" />
            <span>{warehouse.phone}</span>
          </div>
        )}

        {/* GPS coordinates */}
        {warehouse.gps_lat != null && warehouse.gps_lng != null && (
          <div className="text-[10px] text-gray-400 font-mono">
            GPS: {warehouse.gps_lat.toFixed(4)}, {warehouse.gps_lng.toFixed(4)}
          </div>
        )}

        {/* Trailers at this warehouse */}
        {trailers.length > 0 && (
          <div className="pt-2 border-t border-border space-y-1.5">
            <span className="text-[10px] font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wide">
              Home Trailers
            </span>
            {trailers.slice(0, 5).map((t) => (
              <Link
                key={t.id}
                to={`/trucks/trailers/${t.id}`}
                className="flex items-center gap-2 text-xs hover:bg-surface-secondary rounded px-1.5 py-1 transition-colors"
              >
                <Container className="h-3 w-3 text-gray-400" />
                <span className="font-mono text-gray-500">{t.trailer_code}</span>
                <span className="flex-1 truncate text-gray-700 dark:text-gray-300">{t.name}</span>
                <ArrowRight className="h-3 w-3 text-gray-400" />
              </Link>
            ))}
            {trailers.length > 5 && (
              <p className="text-[10px] text-gray-400">+{trailers.length - 5} more</p>
            )}
          </div>
        )}

        {/* Notes */}
        {warehouse.notes && (
          <div className="pt-2 border-t border-border">
            <p className="text-xs text-gray-500 dark:text-gray-400 line-clamp-2">{warehouse.notes}</p>
          </div>
        )}
      </div>
    </Card>
  );
}
