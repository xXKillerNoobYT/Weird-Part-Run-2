/**
 * Shared helper components used across multiple vehicle-detail tabs.
 */

import {
  Truck,
  Car,
  ChevronDown,
  ChevronUp,
} from 'lucide-react';
import { Badge } from '../../../../components/ui/Badge';
import type { VehicleType, VehicleStatus } from '../../../../lib/types';


// ── Constants ────────────────────────────────────────────────────

export type SubTab = 'overview' | 'assignments' | 'inventory' | 'deliveries' | 'maintenance' | 'mileage';

export const STATUS_OPTIONS: { label: string; value: VehicleStatus }[] = [
  { label: 'Active', value: 'active' },
  { label: 'Inactive', value: 'inactive' },
  { label: 'In Maintenance', value: 'maintenance' },
  { label: 'Retired', value: 'retired' },
];

export const TYPE_OPTIONS: { label: string; value: VehicleType }[] = [
  { label: 'Company Truck', value: 'company_truck' },
  { label: 'Company Van', value: 'company_van' },
  { label: 'Company Car', value: 'company_car' },
  { label: 'Private Vehicle', value: 'private_vehicle' },
];


// ── Helper Components ────────────────────────────────────────────

export function VehicleIcon({ type, className }: { type: VehicleType; className?: string }) {
  switch (type) {
    case 'company_van':
    case 'company_truck':
      return <Truck className={className} />;
    default:
      return <Car className={className} />;
  }
}

export function InfoRow({ label, value, mono }: { label: string; value: string | null | undefined; mono?: boolean }) {
  if (!value) return null;
  return (
    <div className="flex justify-between text-sm py-1">
      <span className="text-gray-500 dark:text-gray-400">{label}</span>
      <span className={`text-gray-900 dark:text-gray-100 font-medium ${mono ? 'font-mono text-xs' : ''}`}>
        {value}
      </span>
    </div>
  );
}

export function CollapsibleSection({
  title,
  count,
  open,
  onToggle,
  children,
}: {
  title: string;
  count?: number;
  open: boolean;
  onToggle: () => void;
  children: React.ReactNode;
}) {
  return (
    <div className="bg-surface border border-border rounded-xl overflow-hidden">
      <button
        onClick={onToggle}
        className="w-full flex items-center justify-between px-4 py-3 hover:bg-gray-50 dark:hover:bg-gray-800/50 transition-colors"
      >
        <div className="flex items-center gap-2">
          <h3 className="text-sm font-medium text-gray-900 dark:text-gray-100">{title}</h3>
          {count != null && count > 0 && <Badge variant="default">{count}</Badge>}
        </div>
        {open ? <ChevronUp className="h-4 w-4 text-gray-400" /> : <ChevronDown className="h-4 w-4 text-gray-400" />}
      </button>
      {open && <div className="px-4 pb-3">{children}</div>}
    </div>
  );
}
