/**
 * TrailerLocationsPage — real-time overview of all trailer locations.
 *
 * Shows every trailer with its latest location event, current status,
 * home warehouse, and assigned job. Helps dispatchers see at a glance
 * which trailers are where.
 *
 * Route: /trucks/trailer-locations
 */

import { useState, useEffect } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Link } from 'react-router-dom';
import {
  MapPin,
  Container,
  Search,
  Warehouse,
  Briefcase,
  Truck,
  User,
  Clock,
  HelpCircle,
} from 'lucide-react';
import { PageSpinner } from '../../../components/ui/Spinner';
import { EmptyState } from '../../../components/ui/EmptyState';
import { Input } from '../../../components/ui/Input';
import { Card } from '../../../components/ui/Card';
import { listTrailers, getTrailerLocation } from '../../../api/vehicles';
import { TrailerStatusBadge } from '../components/TrailerStatusBadge';
import type { JobTrailer } from '../../../lib/types';


const LOCATION_KIND_ICONS: Record<string, React.ReactNode> = {
  warehouse: <Warehouse className="h-4 w-4 text-blue-500" />,
  job: <Briefcase className="h-4 w-4 text-green-500" />,
  road: <Truck className="h-4 w-4 text-amber-500" />,
  other: <HelpCircle className="h-4 w-4 text-gray-400" />,
};

const LOCATION_KIND_LABELS: Record<string, string> = {
  warehouse: 'At Warehouse',
  job: 'At Job Site',
  road: 'On the Road',
  other: 'Other',
};


export function TrailerLocationsPage() {
  const [search, setSearch] = useState('');
  const [debouncedSearch, setDebouncedSearch] = useState('');

  // Debounce search
  useEffect(() => {
    const timer = setTimeout(() => setDebouncedSearch(search), 300);
    return () => clearTimeout(timer);
  }, [search]);

  // Fetch all trailers
  const { data: trailers, isLoading: loadingTrailers } = useQuery({
    queryKey: ['trailers', debouncedSearch],
    queryFn: () => listTrailers({ search: debouncedSearch || undefined }),
    staleTime: 15_000,
  });

  // Fetch latest location for each trailer
  const activeTrailers = trailers?.filter(t => t.is_active) ?? [];

  return (
    <div className="space-y-4">
      {/* Header */}
      <div className="flex items-center gap-3 flex-wrap">
        <div className="flex-1 min-w-[220px]">
          <Input
            placeholder="Search trailers..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            icon={<Search className="h-4 w-4" />}
          />
        </div>
        <div className="text-xs text-gray-500 dark:text-gray-400">
          {activeTrailers.length} active trailer{activeTrailers.length !== 1 ? 's' : ''}
        </div>
      </div>

      {loadingTrailers ? (
        <PageSpinner label="Loading trailer locations..." />
      ) : activeTrailers.length === 0 ? (
        <EmptyState
          icon={<MapPin className="h-12 w-12" />}
          title="No trailers found"
          description={search ? 'Try a different search term.' : 'No active trailers in the system.'}
        />
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-3">
          {activeTrailers.map((trailer) => (
            <TrailerLocationCard key={trailer.id} trailer={trailer} />
          ))}
        </div>
      )}
    </div>
  );
}


/** Individual trailer location card — fetches its own latest location. */
function TrailerLocationCard({ trailer }: { trailer: JobTrailer }) {
  const { data: location, isLoading } = useQuery({
    queryKey: ['trailer-location', trailer.id],
    queryFn: () => getTrailerLocation(trailer.id),
    staleTime: 30_000,
  });

  const kindIcon = location?.location_kind
    ? LOCATION_KIND_ICONS[location.location_kind] || LOCATION_KIND_ICONS.other
    : null;

  const kindLabel = location?.location_kind
    ? LOCATION_KIND_LABELS[location.location_kind] || location.location_kind
    : null;

  const timeAgo = location?.recorded_at ? formatTimeAgo(location.recorded_at) : null;

  return (
    <Link to={`/trucks/trailers/${trailer.id}`} className="block">
      <Card className="hover:shadow-md transition-shadow h-full">
        <div className="p-4 space-y-3">
          {/* Header: code, name, status */}
          <div className="flex items-start justify-between gap-2">
            <div className="min-w-0">
              <div className="flex items-center gap-2">
                <Container className="h-4 w-4 text-gray-400 shrink-0" />
                <span className="text-xs font-mono text-gray-500">{trailer.trailer_code}</span>
              </div>
              <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100 truncate">
                {trailer.name}
              </h3>
            </div>
            <TrailerStatusBadge status={trailer.status} />
          </div>

          {/* Location info */}
          {isLoading ? (
            <div className="flex items-center gap-2 text-xs text-gray-400">
              <div className="h-3 w-3 animate-pulse bg-gray-300 rounded-full" />
              <span>Loading location...</span>
            </div>
          ) : location ? (
            <div className="space-y-1.5">
              <div className="flex items-center gap-2">
                {kindIcon}
                <span className="text-sm font-medium">{kindLabel}</span>
              </div>
              {location.warehouse_name && (
                <div className="flex items-center gap-1.5 text-xs text-gray-500">
                  <Warehouse className="h-3 w-3" />
                  <span>{location.warehouse_name}</span>
                </div>
              )}
              {location.job_name && (
                <div className="flex items-center gap-1.5 text-xs text-gray-500">
                  <Briefcase className="h-3 w-3" />
                  <span>{location.job_name}</span>
                </div>
              )}
              <div className="flex items-center gap-1.5 text-xs text-gray-400">
                <Clock className="h-3 w-3" />
                <span>{timeAgo}</span>
                {location.recorded_by_name && (
                  <>
                    <span>·</span>
                    <User className="h-3 w-3" />
                    <span>{location.recorded_by_name}</span>
                  </>
                )}
              </div>
              {location.lat != null && location.lng != null && (
                <div className="text-[10px] text-gray-400 font-mono">
                  GPS: {location.lat.toFixed(4)}, {location.lng.toFixed(4)}
                </div>
              )}
            </div>
          ) : (
            <div className="flex items-center gap-2 text-xs text-gray-400">
              <MapPin className="h-3.5 w-3.5" />
              <span>No location recorded yet</span>
            </div>
          )}

          {/* Footer: home warehouse + driver */}
          <div className="flex items-center gap-3 text-[11px] text-gray-400 pt-1 border-t border-border">
            {trailer.home_warehouse_name && (
              <span className="flex items-center gap-1">
                <Warehouse className="h-3 w-3" />
                Home: {trailer.home_warehouse_name}
              </span>
            )}
            {trailer.assigned_driver_name && (
              <span className="flex items-center gap-1">
                <User className="h-3 w-3" />
                {trailer.assigned_driver_name}
              </span>
            )}
          </div>
        </div>
      </Card>
    </Link>
  );
}


/** Simple "time ago" formatter for recent timestamps. */
function formatTimeAgo(isoDate: string): string {
  const now = Date.now();
  const then = new Date(isoDate).getTime();
  const diffMs = now - then;
  const diffMins = Math.floor(diffMs / 60_000);

  if (diffMins < 1) return 'Just now';
  if (diffMins < 60) return `${diffMins}m ago`;
  const diffHrs = Math.floor(diffMins / 60);
  if (diffHrs < 24) return `${diffHrs}h ago`;
  const diffDays = Math.floor(diffHrs / 24);
  if (diffDays < 7) return `${diffDays}d ago`;
  return new Date(isoDate).toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
}
