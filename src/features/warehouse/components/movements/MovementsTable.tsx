/**
 * MovementsTable — chronological table of stock movements.
 *
 * Shows time, user, movement type, part, qty, from→to, reason,
 * and a photo thumbnail that expands on click.
 */

import { Fragment, useState } from 'react';
import {
  ArrowRight, Camera, ChevronDown, ChevronUp, ArrowRightLeft,
} from 'lucide-react';
import { Badge } from '../../../../components/ui/Badge';
import { cn, formatDateTime } from '../../../../lib/utils';
import { useAuthStore } from '../../../../stores/auth-store';
import { PERMISSIONS } from '../../../../lib/constants';
import type { MovementLogEntry } from '../../../../lib/types';

const typeVariant: Record<string, 'default' | 'primary' | 'success' | 'warning' | 'danger'> = {
  transfer: 'primary',
  receive: 'success',
  consume: 'warning',
  return: 'default',
  adjust: 'danger',
  write_off: 'danger',
};

interface MovementsTableProps {
  items: MovementLogEntry[];
}

export function MovementsTable({ items }: MovementsTableProps) {
  const [expandedId, setExpandedId] = useState<number | null>(null);
  const [lightboxSrc, setLightboxSrc] = useState<string | null>(null);
  const { hasPermission } = useAuthStore();
  const showDollars = hasPermission(PERMISSIONS.SHOW_DOLLAR_VALUES);

  if (items.length === 0) {
    return (
      <div className="flex flex-col items-center py-12 gap-3">
        <ArrowRightLeft className="h-8 w-8 text-gray-400 dark:text-gray-500" />
        <p className="text-sm text-gray-500 dark:text-gray-400">
          No movements found matching your filters.
        </p>
      </div>
    );
  }

  return (
    <>
      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-gray-200 dark:border-gray-700">
              <th className="py-2 px-3 text-left text-gray-500 dark:text-gray-400 font-medium">
                Time
              </th>
              <th className="py-2 px-3 text-left text-gray-500 dark:text-gray-400 font-medium">
                User
              </th>
              <th className="py-2 px-3 text-left text-gray-500 dark:text-gray-400 font-medium">
                Type
              </th>
              <th className="py-2 px-3 text-left text-gray-500 dark:text-gray-400 font-medium">
                Part
              </th>
              <th className="py-2 px-3 text-center text-gray-500 dark:text-gray-400 font-medium">
                Qty
              </th>
              <th className="py-2 px-3 text-left text-gray-500 dark:text-gray-400 font-medium">
                From → To
              </th>
              <th className="py-2 px-3 text-left text-gray-500 dark:text-gray-400 font-medium">
                Reason
              </th>
              <th className="py-2 px-3 text-center text-gray-500 dark:text-gray-400 font-medium">
                Photo
              </th>
              <th className="py-2 px-3 w-8" />
            </tr>
          </thead>
          <tbody>
            {items.map((entry) => {
              const isExpanded = expandedId === entry.id;
              return (
                <Fragment key={entry.id}>
                  <tr
                    className={cn(
                      'border-b border-gray-100 dark:border-gray-800 hover:bg-gray-50 dark:hover:bg-gray-700/30 cursor-pointer',
                      isExpanded && 'bg-gray-50 dark:bg-gray-700/30',
                    )}
                    onClick={() => setExpandedId(isExpanded ? null : entry.id)}
                  >
                    <td className="py-2.5 px-3 text-gray-500 dark:text-gray-400 whitespace-nowrap">
                      {formatDateTime(entry.created_at)}
                    </td>
                    <td className="py-2.5 px-3 text-gray-700 dark:text-gray-300">
                      {entry.performer_name ?? '—'}
                    </td>
                    <td className="py-2.5 px-3">
                      <Badge variant={typeVariant[entry.movement_type] ?? 'default'}>
                        {entry.movement_type}
                      </Badge>
                    </td>
                    <td className="py-2.5 px-3">
                      <span className="font-medium text-gray-900 dark:text-gray-100">
                        {entry.part_name}
                      </span>
                    </td>
                    <td className="py-2.5 px-3 text-center font-medium text-gray-900 dark:text-gray-100">
                      {entry.qty}
                    </td>
                    <td className="py-2.5 px-3 text-gray-600 dark:text-gray-400 whitespace-nowrap">
                      {entry.from_location_type ?? '?'}
                      <ArrowRight className="inline h-3 w-3 mx-1 text-gray-400 dark:text-gray-500" />
                      {entry.to_location_type ?? '?'}
                    </td>
                    <td className="py-2.5 px-3 text-gray-600 dark:text-gray-400 text-xs truncate max-w-[120px]">
                      {entry.reason ?? '—'}
                    </td>
                    <td className="py-2.5 px-3 text-center">
                      {entry.photo_path ? (
                        <button
                          onClick={(e) => {
                            e.stopPropagation();
                            setLightboxSrc(`/api/uploads/${entry.photo_path}`);
                          }}
                          className="inline-block"
                        >
                          <div className="w-10 h-10 rounded-lg bg-gray-100 dark:bg-gray-700 flex items-center justify-center overflow-hidden">
                            <Camera className="h-4 w-4 text-gray-400" />
                          </div>
                        </button>
                      ) : (
                        <span className="text-gray-400 dark:text-gray-500">—</span>
                      )}
                    </td>
                    <td className="py-2.5 px-3">
                      {isExpanded
                        ? <ChevronUp className="h-4 w-4 text-gray-400" />
                        : <ChevronDown className="h-4 w-4 text-gray-400" />}
                    </td>
                  </tr>

                  {/* Expanded details row */}
                  {isExpanded && (
                    <tr className="bg-gray-50 dark:bg-gray-700/20">
                      <td colSpan={9} className="px-6 py-4">
                        <div className="grid grid-cols-2 sm:grid-cols-4 gap-4 text-sm">
                          {entry.notes && (
                            <div className="col-span-2">
                              <span className="text-gray-500 dark:text-gray-400 text-xs">Notes</span>
                              <p className="text-gray-700 dark:text-gray-300 mt-0.5">
                                {entry.notes}
                              </p>
                            </div>
                          )}
                          {entry.reference_number && (
                            <div>
                              <span className="text-gray-500 dark:text-gray-400 text-xs">Reference #</span>
                              <p className="text-gray-700 dark:text-gray-300 mt-0.5">
                                {entry.reference_number}
                              </p>
                            </div>
                          )}
                          {showDollars && entry.unit_cost != null && (
                            <div>
                              <span className="text-gray-500 dark:text-gray-400 text-xs">Unit Cost</span>
                              <p className="text-gray-700 dark:text-gray-300 mt-0.5">
                                ${entry.unit_cost.toFixed(2)}
                              </p>
                            </div>
                          )}
                          {entry.part_code && (
                            <div>
                              <span className="text-gray-500 dark:text-gray-400 text-xs">Part Code</span>
                              <p className="text-gray-700 dark:text-gray-300 mt-0.5">
                                {entry.part_code}
                              </p>
                            </div>
                          )}
                          <div>
                            <span className="text-gray-500 dark:text-gray-400 text-xs">Movement ID</span>
                            <p className="text-gray-700 dark:text-gray-300 mt-0.5">
                              #{entry.id}
                            </p>
                          </div>
                        </div>
                      </td>
                    </tr>
                  )}
                </Fragment>
              );
            })}
          </tbody>
        </table>
      </div>

      {/* Photo lightbox */}
      {lightboxSrc && (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/80 backdrop-blur-sm"
          onClick={() => setLightboxSrc(null)}
        >
          <img
            src={lightboxSrc}
            alt="Movement photo"
            className="max-w-[90vw] max-h-[90vh] rounded-xl shadow-2xl object-contain"
          />
        </div>
      )}
    </>
  );
}
