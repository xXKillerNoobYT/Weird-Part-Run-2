/**
 * OrderStatusBadge — color-coded status chip for JPOs, POs, and Returns.
 *
 * Maps status values to semantic colors. The `type` prop determines
 * which label map to use (JPO, PO, or Return statuses overlap in
 * some values like "draft" but have different meanings).
 */

import {
  JPO_STATUS_LABELS,
  PO_STATUS_LABELS,
  RETURN_STATUS_LABELS,
} from '../../../lib/types';

interface OrderStatusBadgeProps {
  status: string;
  type: 'jpo' | 'po' | 'return';
}

/** Map status → Tailwind color classes */
const STATUS_COLORS: Record<string, string> = {
  // Shared
  draft: 'bg-gray-100 text-gray-700 dark:bg-gray-700 dark:text-gray-300',
  closed: 'bg-gray-100 text-gray-600 dark:bg-gray-700 dark:text-gray-400',
  cancelled: 'bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-400',

  // JPO
  pending_approval: 'bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-400',
  approved: 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400',
  ordering: 'bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-400',
  partially_ordered: 'bg-blue-100 text-blue-600 dark:bg-blue-900/30 dark:text-blue-300',
  ordered: 'bg-indigo-100 text-indigo-700 dark:bg-indigo-900/30 dark:text-indigo-400',

  // PO
  submitted: 'bg-sky-100 text-sky-700 dark:bg-sky-900/30 dark:text-sky-400',
  acknowledged: 'bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-400',
  confirmed: 'bg-indigo-100 text-indigo-700 dark:bg-indigo-900/30 dark:text-indigo-400',

  // Shared receiving
  partially_received: 'bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-400',
  received: 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400',

  // Return-specific
  shipped: 'bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-400',
  received_by_supplier: 'bg-teal-100 text-teal-700 dark:bg-teal-900/30 dark:text-teal-400',
  credited: 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400',
};

const DEFAULT_COLOR = 'bg-gray-100 text-gray-600 dark:bg-gray-700 dark:text-gray-400';

function getLabel(status: string, type: 'jpo' | 'po' | 'return'): string {
  switch (type) {
    case 'jpo':
      return (JPO_STATUS_LABELS as Record<string, string>)[status] ?? status;
    case 'po':
      return (PO_STATUS_LABELS as Record<string, string>)[status] ?? status;
    case 'return':
      return (RETURN_STATUS_LABELS as Record<string, string>)[status] ?? status;
    default:
      return status;
  }
}

export function OrderStatusBadge({ status, type }: OrderStatusBadgeProps) {
  const colorClasses = STATUS_COLORS[status] ?? DEFAULT_COLOR;
  const label = getLabel(status, type);

  return (
    <span
      className={`inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium ${colorClasses}`}
    >
      {label}
    </span>
  );
}
