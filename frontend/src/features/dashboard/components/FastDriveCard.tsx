/**
 * FastDriveCard — Quick-start driving widget on the dashboard.
 *
 * Shows the user's assigned vehicle, top 3 destinations by recent trip
 * frequency, and an expandable full destination list.  Each destination
 * has two actions:
 *   • GPS & Log  → logs the trip leg AND opens Google Maps / Apple Maps
 *   • Just Log   → logs the trip leg only
 */

import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  Truck,
  Navigation,
  ClipboardCheck,
  ChevronDown,
  ChevronUp,
  Home,
  Building2,
  MapPin,
  Info,
  Loader2,
  CheckCircle2,
} from 'lucide-react';

import { Card, CardHeader } from '../../../components/ui/Card';
import { getFastDriveContext, startDrive } from '../../../api/dashboard';
import type { FastDriveDestination, FastDriveStartRequest } from '../../../lib/types';


// ── Helpers ───────────────────────────────────────────────────

/** Open GPS navigation to a lat/lng coordinate. */
function openGps(lat: number, lng: number, label: string) {
  const isIos = /iPad|iPhone|iPod/.test(navigator.userAgent);
  const url = isIos
    ? `maps://maps.apple.com/?daddr=${lat},${lng}&q=${encodeURIComponent(label)}`
    : `https://www.google.com/maps/dir/?api=1&destination=${lat},${lng}`;
  window.open(url, '_blank');
}

/** Determine the trip leg type based on destination type. */
function inferLegType(dest: FastDriveDestination): string {
  switch (dest.type) {
    case 'shop':  return 'home_to_shop';
    case 'job':   return 'shop_to_job';
    case 'home':  return 'shop_to_home';
    default:      return 'other';
  }
}

/** Determine the "from" label based on destination type. */
function inferFromLabel(dest: FastDriveDestination): string {
  switch (dest.type) {
    case 'shop':  return 'Home';
    case 'job':   return 'Shop';
    case 'home':  return 'Shop';
    default:      return 'Unknown';
  }
}

/** Icon for destination type. */
function DestIcon({ type }: { type: string }) {
  switch (type) {
    case 'home':  return <Home className="h-5 w-5 text-blue-500" />;
    case 'shop':  return <Building2 className="h-5 w-5 text-amber-500" />;
    case 'job':   return <MapPin className="h-5 w-5 text-green-500" />;
    default:      return <MapPin className="h-5 w-5 text-gray-400" />;
  }
}


// ── Destination Row ──────────────────────────────────────────

interface DestRowProps {
  dest: FastDriveDestination;
  onGpsAndLog: (dest: FastDriveDestination) => void;
  onJustLog: (dest: FastDriveDestination) => void;
  isLogging: boolean;
  loggedId: number | null;  // trip_leg_id if just logged this one
}

function DestinationRow({ dest, onGpsAndLog, onJustLog, isLogging, loggedId }: DestRowProps) {
  const hasGps = dest.gps_lat != null && dest.gps_lng != null;

  return (
    <div className="flex flex-col gap-2 rounded-lg border border-gray-100 dark:border-gray-700 p-3">
      {/* Label row */}
      <div className="flex items-center gap-2 min-w-0">
        <DestIcon type={dest.type} />
        <div className="flex-1 min-w-0">
          <p className="text-sm font-medium text-gray-900 dark:text-gray-100 truncate">
            {dest.label}
          </p>
          {dest.miles_estimate != null && dest.miles_estimate > 0 && (
            <p className="text-xs text-gray-500 dark:text-gray-400">
              ~{dest.miles_estimate} mi
            </p>
          )}
        </div>

        {/* Success indicator */}
        {loggedId && (
          <CheckCircle2 className="h-5 w-5 text-green-500 flex-shrink-0" />
        )}
      </div>

      {/* Action buttons */}
      <div className="flex gap-2">
        <button
          onClick={() => onGpsAndLog(dest)}
          disabled={!hasGps || isLogging}
          className="flex-1 flex items-center justify-center gap-1.5 rounded-lg bg-primary-600 px-3 py-2 text-xs font-medium text-white transition-colors hover:bg-primary-700 disabled:opacity-50 disabled:cursor-not-allowed"
          title={hasGps ? 'Open GPS navigation & log trip' : 'No GPS coordinates available'}
        >
          {isLogging ? (
            <Loader2 className="h-3.5 w-3.5 animate-spin" />
          ) : (
            <Navigation className="h-3.5 w-3.5" />
          )}
          <span>GPS & Log</span>
        </button>

        <button
          onClick={() => onJustLog(dest)}
          disabled={isLogging}
          className="flex-1 flex items-center justify-center gap-1.5 rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-700 px-3 py-2 text-xs font-medium text-gray-700 dark:text-gray-200 transition-colors hover:bg-gray-50 dark:hover:bg-gray-600 disabled:opacity-50"
        >
          {isLogging ? (
            <Loader2 className="h-3.5 w-3.5 animate-spin" />
          ) : (
            <ClipboardCheck className="h-3.5 w-3.5" />
          )}
          <span>Just Log</span>
        </button>
      </div>
    </div>
  );
}


// ── Main Component ───────────────────────────────────────────

export function FastDriveCard() {
  const queryClient = useQueryClient();
  const [showAll, setShowAll] = useState(false);
  const [loggingDest, setLoggingDest] = useState<string | null>(null);
  const [lastLoggedId, setLastLoggedId] = useState<{ label: string; id: number } | null>(null);

  const { data: ctx, isLoading, error } = useQuery({
    queryKey: ['fast-drive'],
    queryFn: getFastDriveContext,
    staleTime: 60_000,
  });

  const logMutation = useMutation({
    mutationFn: startDrive,
    onSuccess: (result, vars) => {
      setLastLoggedId({ label: vars.to_label, id: result.trip_leg_id });
      setLoggingDest(null);
      // Auto-clear success badge after 5 seconds
      setTimeout(() => setLastLoggedId(null), 5_000);
      // Refetch to update trip counts
      queryClient.invalidateQueries({ queryKey: ['fast-drive'] });
    },
    onError: () => {
      setLoggingDest(null);
    },
  });

  // ── Handlers ─────────────────────────────────────────────

  function buildRequest(dest: FastDriveDestination): FastDriveStartRequest {
    return {
      leg_type: inferLegType(dest),
      from_label: inferFromLabel(dest),
      to_label: dest.label,
      estimated_miles: dest.miles_estimate ?? undefined,
      to_job_id: dest.type === 'job' ? dest.job_id : undefined,
    };
  }

  function handleGpsAndLog(dest: FastDriveDestination) {
    setLoggingDest(dest.label);
    logMutation.mutate(buildRequest(dest), {
      onSuccess: () => {
        // Open GPS after successful log
        if (dest.gps_lat != null && dest.gps_lng != null) {
          openGps(dest.gps_lat, dest.gps_lng, dest.label);
        }
      },
    });
  }

  function handleJustLog(dest: FastDriveDestination) {
    setLoggingDest(dest.label);
    logMutation.mutate(buildRequest(dest));
  }

  // ── Render states ────────────────────────────────────────

  if (isLoading) {
    return (
      <Card>
        <div className="flex items-center gap-3 text-gray-400">
          <Loader2 className="h-5 w-5 animate-spin" />
          <span className="text-sm">Loading drive options...</span>
        </div>
      </Card>
    );
  }

  if (error || !ctx) return null;

  // No vehicle assigned
  if (!ctx.has_vehicle) {
    return (
      <Card>
        <div className="flex items-center gap-3 text-gray-500 dark:text-gray-400">
          <Info className="h-5 w-5 flex-shrink-0" />
          <p className="text-sm">
            No vehicle assigned. Contact your manager to get started with Fast Drive.
          </p>
        </div>
      </Card>
    );
  }

  const suggested = ctx.suggested ?? [];
  const allDest = ctx.all_destinations ?? [];

  // Destinations to show: suggested (top 3) unless "All" is expanded
  const visibleDests = showAll ? allDest : suggested;

  // Filter "All" to exclude those already in suggested (to avoid duplicates when expanded)
  const extraDests = showAll
    ? allDest.filter(d => !suggested.some(s => s.label === d.label && s.type === d.type))
    : [];

  return (
    <Card>
      <CardHeader
        title="Fast Drive"
        subtitle={`${ctx.vehicle_name} (${ctx.vehicle_number})`}
        action={
          <Truck className="h-5 w-5 text-gray-400 dark:text-gray-500" />
        }
      />

      {/* Error banner */}
      {logMutation.isError && (
        <div className="mb-3 rounded-lg bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 px-3 py-2 text-sm text-red-700 dark:text-red-300">
          Failed to log trip. Please try again.
        </div>
      )}

      {/* Destination list */}
      <div className="space-y-2">
        {/* Always show suggested destinations */}
        {suggested.map((dest) => (
          <DestinationRow
            key={`${dest.type}-${dest.label}`}
            dest={dest}
            onGpsAndLog={handleGpsAndLog}
            onJustLog={handleJustLog}
            isLogging={loggingDest === dest.label}
            loggedId={lastLoggedId?.label === dest.label ? lastLoggedId.id : null}
          />
        ))}

        {/* Extra destinations when expanded */}
        {showAll && extraDests.map((dest) => (
          <DestinationRow
            key={`${dest.type}-${dest.label}`}
            dest={dest}
            onGpsAndLog={handleGpsAndLog}
            onJustLog={handleJustLog}
            isLogging={loggingDest === dest.label}
            loggedId={lastLoggedId?.label === dest.label ? lastLoggedId.id : null}
          />
        ))}
      </div>

      {/* "All Destinations" toggle — only show if there are more than suggested */}
      {allDest.length > suggested.length && (
        <button
          onClick={() => setShowAll(!showAll)}
          className="mt-3 flex w-full items-center justify-center gap-1.5 rounded-lg border border-gray-200 dark:border-gray-700 bg-gray-50 dark:bg-gray-800 px-3 py-2 text-sm font-medium text-gray-600 dark:text-gray-300 transition-colors hover:bg-gray-100 dark:hover:bg-gray-700"
        >
          {showAll ? (
            <>
              <ChevronUp className="h-4 w-4" />
              Show Less
            </>
          ) : (
            <>
              <ChevronDown className="h-4 w-4" />
              All Destinations ({allDest.length})
            </>
          )}
        </button>
      )}
    </Card>
  );
}
