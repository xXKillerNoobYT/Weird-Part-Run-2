/**
 * TrailerCard — card component for a trailer in the fleet list.
 *
 * Shows trailer code, name, status, current job/location, driver,
 * and warehouse assignment. Clicking navigates to detail page.
 */

import {
  Container,
  MapPin,
  User,
  Warehouse,
  ChevronRight,
  Briefcase,
} from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import { TrailerStatusBadge } from './TrailerStatusBadge';
import type { JobTrailer } from '../../../lib/types';

interface TrailerCardProps {
  trailer: JobTrailer;
}

export function TrailerCard({ trailer }: TrailerCardProps) {
  const navigate = useNavigate();

  return (
    <div
      className="group bg-surface border border-border rounded-xl p-4 hover:border-blue-300 dark:hover:border-blue-600 transition-colors cursor-pointer"
      onClick={() => navigate(`/trucks/trailers/${trailer.id}`)}
    >
      {/* Header — code + status */}
      <div className="flex items-start justify-between mb-2">
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 mb-1 flex-wrap">
            <Container className="h-4 w-4 text-gray-400 dark:text-gray-500 shrink-0" />
            <span className="text-xs font-mono text-gray-500 dark:text-gray-400">
              {trailer.trailer_code}
            </span>
            <TrailerStatusBadge status={trailer.status} />
          </div>
          <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100 truncate">
            {trailer.name}
          </h3>
        </div>
        <ChevronRight className="h-4 w-4 text-gray-300 dark:text-gray-600 mt-1 shrink-0" />
      </div>

      {/* Stats row */}
      <div className="flex items-center gap-4 text-xs text-gray-500 dark:text-gray-400 flex-wrap">
        {/* Current job */}
        {trailer.current_job_name && (
          <div className="flex items-center gap-1">
            <Briefcase className="h-3.5 w-3.5 shrink-0" />
            <span className="truncate max-w-[140px]">{trailer.current_job_name}</span>
          </div>
        )}

        {/* Home warehouse */}
        {trailer.home_warehouse_name && (
          <div className="flex items-center gap-1">
            <Warehouse className="h-3.5 w-3.5 shrink-0" />
            <span className="truncate max-w-[120px]">{trailer.home_warehouse_name}</span>
          </div>
        )}

        {/* Driver */}
        {trailer.assigned_driver_name && (
          <div className="flex items-center gap-1">
            <User className="h-3.5 w-3.5 shrink-0" />
            <span className="truncate max-w-[120px]">{trailer.assigned_driver_name}</span>
          </div>
        )}

        {/* Fallback location */}
        {!trailer.current_job_name && !trailer.home_warehouse_name && (
          <div className="flex items-center gap-1">
            <MapPin className="h-3.5 w-3.5 shrink-0" />
            <span>No location assigned</span>
          </div>
        )}
      </div>
    </div>
  );
}
