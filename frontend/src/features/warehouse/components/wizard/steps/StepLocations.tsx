/**
 * Step 1: Location Picker — select From and To locations.
 *
 * Shows the horizontal flow map (Warehouse → Pulled → Truck → Job)
 * with interactive location pickers below.
 */

import { useEffect } from 'react';
import { useQuery } from '@tanstack/react-query';
import {
  Warehouse, Package, Truck, Briefcase,
  ArrowRight, ArrowLeftRight, AlertCircle,
} from 'lucide-react';
import { cn } from '../../../../../lib/utils';
import { getLocations } from '../../../../../api/warehouse';
import { useMovementWizardStore } from '../../../stores/movement-wizard-store';
import type { LocationType } from '../../../../../lib/types';

const FLOW_NODES: {
  type: LocationType;
  label: string;
  icon: React.ElementType;
}[] = [
  { type: 'warehouse', label: 'Warehouse', icon: Warehouse },
  { type: 'pulled', label: 'Staging', icon: Package },
  { type: 'truck', label: 'Truck', icon: Truck },
  { type: 'job', label: 'Job', icon: Briefcase },
];

// Valid movement paths
const VALID_PATHS: [LocationType, LocationType][] = [
  ['warehouse', 'pulled'],
  ['pulled', 'truck'],
  ['warehouse', 'truck'],
  ['truck', 'job'],
  ['job', 'truck'],
  ['truck', 'warehouse'],
  ['pulled', 'warehouse'],
];

export function StepLocations() {
  const {
    fromLocationType, fromLocationId,
    toLocationType, toLocationId,
    setFromLocation, setToLocation,
    setDestination,
  } = useMovementWizardStore();

  const { data: locations = [] } = useQuery({
    queryKey: ['warehouse', 'locations'],
    queryFn: getLocations,
    staleTime: 60_000,
  });

  // Filter location options by type
  const getOptionsForType = (type: LocationType) =>
    locations.filter((l) => l.location_type === type);

  // Get valid "to" types for the currently selected "from"
  const validToTypes = fromLocationType
    ? VALID_PATHS.filter(([f]) => f === fromLocationType).map(([, t]) => t)
    : [];

  // Auto-select to if only one valid option
  useEffect(() => {
    if (fromLocationType && validToTypes.length === 1 && !toLocationType) {
      setToLocation(validToTypes[0], 1);
    }
  }, [fromLocationType]);

  const handleFromClick = (type: LocationType) => {
    if (type === fromLocationType) return;
    setFromLocation(type, 1);
    // Clear "to" if it's now invalid
    if (toLocationType && !VALID_PATHS.some(([f, t]) => f === type && t === toLocationType)) {
      setToLocation(null as unknown as LocationType, 1);
    }
  };

  const handleToClick = (type: LocationType) => {
    if (type === toLocationType) return;
    setToLocation(type, 1);
  };

  // ── Flow map visual state ────────────────────────────────
  // Compute which nodes are active and which arrows to animate.
  const fromIdx = fromLocationType
    ? FLOW_NODES.findIndex((n) => n.type === fromLocationType)
    : -1;
  const toIdx = toLocationType
    ? FLOW_NODES.findIndex((n) => n.type === toLocationType)
    : -1;
  const bothSelected = fromIdx >= 0 && toIdx >= 0;
  const pathMin = bothSelected ? Math.min(fromIdx, toIdx) : -1;
  const pathMax = bothSelected ? Math.max(fromIdx, toIdx) : -1;
  const isForward = fromIdx < toIdx;

  /** Node visual state: from/to grow, others shrink when both are picked. */
  const getNodeState = (idx: number) => {
    if (idx === fromIdx) return 'from' as const;
    if (idx === toIdx) return 'to' as const;
    if (!bothSelected) return 'default' as const;
    if (idx > pathMin && idx < pathMax) return 'between' as const;
    return 'inactive' as const;
  };

  /** Arrow state for the gap between node[idx] and node[idx+1]. */
  const getArrowState = (gapIdx: number) => {
    if (!bothSelected) return 'default' as const;
    if (gapIdx >= pathMin && gapIdx < pathMax) return 'active' as const;
    return 'inactive' as const;
  };

  return (
    <div className="space-y-6">
      {/* ── Flow Map ── animated directional path visualization ── */}
      <div className="flex items-center justify-center py-4 overflow-x-auto">
        {FLOW_NODES.map((node, idx) => {
          const Icon = node.icon;
          const state = getNodeState(idx);
          const isLast = idx === FLOW_NODES.length - 1;
          const arrowState = !isLast ? getArrowState(idx) : null;

          return (
            <div key={node.type} className="flex items-center">
              {/* ── Node ── */}
              <div
                className={cn(
                  'flex flex-col items-center gap-1 rounded-xl border-2 transition-all duration-300 ease-out',
                  // FROM — grows, blue glow
                  state === 'from' &&
                    'px-4 py-3 min-w-[88px] border-blue-500 bg-blue-50 dark:bg-blue-900/30 shadow-md shadow-blue-200/60 dark:shadow-blue-900/40',
                  // TO — grows, green glow
                  state === 'to' &&
                    'px-4 py-3 min-w-[88px] border-green-500 bg-green-50 dark:bg-green-900/30 shadow-md shadow-green-200/60 dark:shadow-green-900/40',
                  // Default — normal size, neutral border
                  state === 'default' &&
                    'px-3 py-2 min-w-[80px] border-gray-200 dark:border-gray-700',
                  // Inactive / between — shrink and fade out of the way
                  (state === 'inactive' || state === 'between') &&
                    'px-2 py-1.5 min-w-[52px] border-gray-200/60 dark:border-gray-700/40 opacity-35 scale-[0.85]',
                )}
              >
                <Icon
                  className={cn(
                    'transition-all duration-300',
                    state === 'from' && 'h-7 w-7 text-blue-500',
                    state === 'to' && 'h-7 w-7 text-green-500',
                    state === 'default' && 'h-6 w-6 text-gray-400',
                    (state === 'inactive' || state === 'between') && 'h-5 w-5 text-gray-400',
                  )}
                />
                <span
                  className={cn(
                    'font-medium transition-all duration-300 whitespace-nowrap',
                    state === 'from' && 'text-xs text-blue-700 dark:text-blue-400',
                    state === 'to' && 'text-xs text-green-700 dark:text-green-400',
                    state === 'default' && 'text-xs text-gray-500 dark:text-gray-400',
                    (state === 'inactive' || state === 'between') &&
                      'text-[10px] text-gray-400 dark:text-gray-500',
                  )}
                >
                  {node.label}
                </span>
                {state === 'from' && (
                  <span className="text-[10px] font-bold text-blue-600 dark:text-blue-400 uppercase tracking-wide">
                    From
                  </span>
                )}
                {state === 'to' && (
                  <span className="text-[10px] font-bold text-green-600 dark:text-green-400 uppercase tracking-wide">
                    To
                  </span>
                )}
              </div>

              {/* ── Arrow between nodes ── */}
              {!isLast && (
                <div
                  className={cn(
                    'flex items-center justify-center flex-shrink-0 transition-all duration-300',
                    arrowState === 'active' && 'mx-3',
                    arrowState === 'inactive' && 'mx-1',
                    arrowState === 'default' && 'mx-2',
                  )}
                >
                  {arrowState === 'active' ? (
                    <ArrowRight
                      className={cn(
                        'h-5 w-5 text-primary-500 animate-pulse',
                        !isForward && 'rotate-180',
                      )}
                    />
                  ) : arrowState === 'inactive' ? (
                    <div className="w-4 h-px bg-gray-200 dark:bg-gray-700 rounded-full" />
                  ) : (
                    <ArrowLeftRight className="h-4 w-4 text-gray-300 dark:text-gray-600" />
                  )}
                </div>
              )}
            </div>
          );
        })}
      </div>

      {/* From Location Picker */}
      <div>
        <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
          Move stock FROM:
        </label>
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-2">
          {FLOW_NODES.map((node) => {
            const Icon = node.icon;
            const isSelected = node.type === fromLocationType;
            const options = getOptionsForType(node.type);
            // Any location type can be a "from" if it appears in valid paths
            const canBeFrom = VALID_PATHS.some(([f]) => f === node.type);

            return (
              <button
                key={node.type}
                onClick={() => handleFromClick(node.type)}
                disabled={!canBeFrom}
                className={cn(
                  'flex flex-col items-center gap-1.5 p-3 rounded-xl border-2 transition-all',
                  isSelected
                    ? 'border-blue-500 bg-blue-50 dark:bg-blue-900/30'
                    : canBeFrom
                    ? 'border-gray-200 dark:border-gray-700 hover:border-blue-300 dark:hover:border-blue-700'
                    : 'border-gray-100 dark:border-gray-800 opacity-40 cursor-not-allowed',
                )}
              >
                <Icon className={cn('h-5 w-5', isSelected ? 'text-blue-500' : 'text-gray-400')} />
                <span className={cn('text-sm font-medium', isSelected ? 'text-blue-700 dark:text-blue-400' : 'text-gray-600 dark:text-gray-400')}>
                  {node.label}
                </span>
              </button>
            );
          })}
        </div>

        {/* Sub-picker for specific location (truck #, job #) */}
        {fromLocationType && ['truck', 'job'].includes(fromLocationType) && (
          <div className="mt-2">
            <select
              className="w-full px-3 py-2 rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 text-sm"
              value={fromLocationId}
              onChange={(e) => setFromLocation(fromLocationType, Number(e.target.value))}
            >
              {getOptionsForType(fromLocationType).map((opt) => (
                <option key={opt.location_id} value={opt.location_id}>
                  {opt.label} — {opt.sub_label}
                </option>
              ))}
            </select>
          </div>
        )}
      </div>

      {/* To Location Picker */}
      {fromLocationType && (
        <div>
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
            Move stock TO:
          </label>
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-2">
            {FLOW_NODES.map((node) => {
              const Icon = node.icon;
              const isSelected = node.type === toLocationType;
              const isValid = validToTypes.includes(node.type);

              return (
                <button
                  key={node.type}
                  onClick={() => handleToClick(node.type)}
                  disabled={!isValid}
                  className={cn(
                    'flex flex-col items-center gap-1.5 p-3 rounded-xl border-2 transition-all',
                    isSelected
                      ? 'border-green-500 bg-green-50 dark:bg-green-900/30'
                      : isValid
                      ? 'border-gray-200 dark:border-gray-700 hover:border-green-300 dark:hover:border-green-700'
                      : 'border-gray-100 dark:border-gray-800 opacity-40 cursor-not-allowed',
                  )}
                >
                  <Icon className={cn('h-5 w-5', isSelected ? 'text-green-500' : 'text-gray-400')} />
                  <span className={cn('text-sm font-medium', isSelected ? 'text-green-700 dark:text-green-400' : 'text-gray-600 dark:text-gray-400')}>
                    {node.label}
                  </span>
                </button>
              );
            })}
          </div>

          {/* Sub-picker for specific location */}
          {toLocationType && ['truck', 'job'].includes(toLocationType) && (
            <div className="mt-2">
              <select
                className="w-full px-3 py-2 rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 text-sm"
                value={toLocationId}
                onChange={(e) => setToLocation(toLocationType, Number(e.target.value))}
              >
                {getOptionsForType(toLocationType).map((opt) => (
                  <option key={opt.location_id} value={opt.location_id}>
                    {opt.label} — {opt.sub_label}
                  </option>
                ))}
              </select>
            </div>
          )}
        </div>
      )}

      {/* Movement type indicator */}
      {fromLocationType && toLocationType && (
        <div className="flex items-center gap-2 p-3 rounded-lg bg-gray-50 dark:bg-gray-900/50 border border-gray-200 dark:border-gray-700">
          <AlertCircle className="h-4 w-4 text-gray-400 flex-shrink-0" />
          <span className="text-sm text-gray-600 dark:text-gray-400">
            Movement type:{' '}
            <span className="font-medium text-gray-900 dark:text-gray-200 capitalize">
              {useMovementWizardStore.getState().getMovementType() ?? 'Invalid path'}
            </span>
            {useMovementWizardStore.getState().isPhotoRequired() && (
              <span className="text-amber-600 dark:text-amber-400 ml-2">
                (Photo required)
              </span>
            )}
          </span>
        </div>
      )}
    </div>
  );
}
