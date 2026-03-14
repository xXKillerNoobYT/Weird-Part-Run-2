/**
 * SupplierCard — expandable row showing contacts, delivery info,
 * reliability metrics, brands, and notes for a single supplier.
 */

import {
  Edit2, Trash2, Phone, Truck, Clock,
  ChevronDown, ChevronRight, UserCheck, Calendar, Tag, Star,
  ToggleLeft, ToggleRight,
} from 'lucide-react';
import { Badge } from '../../../../components/ui/Badge';
import type { Supplier } from '../../../../lib/types';
import {
  DELIVERY_LABELS, DELIVERY_BADGE_VARIANT, DELIVERY_ICONS,
  WEEKDAY_LABELS, parseDeliveryDays,
} from './supplier-helpers';
import { ReliabilityBadge } from './ReliabilityBadge';
import { SupplierBrandsSection } from './SupplierBrandsSection';
import { SupplierContactsSection } from './SupplierContactsSection';


export interface SupplierCardProps {
  supplier: Supplier;
  isExpanded: boolean;
  onToggleExpand: () => void;
  canEdit: boolean;
  onEdit: () => void;
  onDelete: () => void;
  onToggleActive: () => void;
}

export function SupplierCard({
  supplier,
  isExpanded,
  onToggleExpand,
  canEdit,
  onEdit,
  onDelete,
  onToggleActive,
}: SupplierCardProps) {
  const _deliveryIcon = DELIVERY_ICONS[supplier.primary_delivery_method] ?? Truck; void _deliveryIcon;
  const hasScheduledDelivery = supplier.delivery_methods?.includes('scheduled_delivery') ?? false;
  const deliveryDays = parseDeliveryDays(supplier.delivery_days);

  return (
    <div className="border border-gray-200 dark:border-gray-700 rounded-xl bg-white dark:bg-gray-800/50 overflow-hidden">
      {/* ── Header Row (always visible) ────────── */}
      <div
        className="flex items-center gap-3 px-4 py-3 cursor-pointer hover:bg-gray-50 dark:hover:bg-gray-800/80 transition-colors"
        onClick={onToggleExpand}
      >
        {/* Expand chevron */}
        <div className="text-gray-400">
          {isExpanded ? (
            <ChevronDown className="h-4 w-4" />
          ) : (
            <ChevronRight className="h-4 w-4" />
          )}
        </div>

        {/* Supplier name */}
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2">
            <span className="font-medium text-gray-900 dark:text-gray-100 truncate">
              {supplier.name}
            </span>
            {!supplier.is_active && (
              <Badge variant="default">Inactive</Badge>
            )}
          </div>
          {/* Quick info line */}
          <div className="flex items-center gap-3 text-xs text-gray-500 dark:text-gray-400 mt-0.5">
            {supplier.phone && (
              <span className="flex items-center gap-1">
                <Phone className="h-3 w-3" />
                {supplier.phone}
              </span>
            )}
            {supplier.rep_name && (
              <span className="flex items-center gap-1">
                <UserCheck className="h-3 w-3" />
                Rep: {supplier.rep_name}
              </span>
            )}
            {hasScheduledDelivery && supplier.driver_name && (
              <span className="flex items-center gap-1">
                <Truck className="h-3 w-3" />
                Driver: {supplier.driver_name}
              </span>
            )}
            {supplier.brand_count > 0 && (
              <span className="flex items-center gap-1">
                <Tag className="h-3 w-3" />
                {supplier.brand_count} brand{supplier.brand_count !== 1 ? 's' : ''}
              </span>
            )}
          </div>
        </div>

        {/* Delivery badges */}
        <div className="flex items-center gap-1">
          {(supplier.delivery_methods ?? (supplier.primary_delivery_method ? [supplier.primary_delivery_method] : [])).map((method) => {
            const Icon = DELIVERY_ICONS[method] ?? Truck;
            const isPrimary = method === supplier.primary_delivery_method;
            return (
              <Badge key={method} variant={DELIVERY_BADGE_VARIANT[method]}>
                <Icon className="h-3 w-3 mr-1 inline" />
                {DELIVERY_LABELS[method]}
                {isPrimary && (supplier.delivery_methods?.length ?? 0) > 1 && (
                  <Star className="h-2.5 w-2.5 ml-0.5 inline fill-current" />
                )}
              </Badge>
            );
          })}
        </div>

        {/* Actions */}
        <div className="flex items-center gap-1" onClick={(e) => e.stopPropagation()}>
          {canEdit && (
            <>
              <button
                className="p-1.5 rounded hover:bg-gray-200 dark:hover:bg-gray-700 transition-colors"
                onClick={onToggleActive}
                title={supplier.is_active ? 'Deactivate' : 'Activate'}
              >
                {supplier.is_active ? (
                  <ToggleRight className="h-4 w-4 text-green-500" />
                ) : (
                  <ToggleLeft className="h-4 w-4 text-gray-400" />
                )}
              </button>
              <button
                className="p-1.5 rounded hover:bg-gray-200 dark:hover:bg-gray-700 transition-colors"
                onClick={onEdit}
                title="Edit"
              >
                <Edit2 className="h-4 w-4 text-gray-500" />
              </button>
              <button
                className="p-1.5 rounded hover:bg-red-100 dark:hover:bg-red-900/30 transition-colors"
                onClick={onDelete}
                title="Delete"
              >
                <Trash2 className="h-4 w-4 text-red-400" />
              </button>
            </>
          )}
        </div>
      </div>

      {/* ── Expanded Detail ────────────────────── */}
      {isExpanded && (
        <div className="border-t border-gray-200 dark:border-gray-700 px-4 py-4">
          {/* ── Dynamic Contacts Section ─────────── */}
          <SupplierContactsSection
            supplierId={supplier.id}
            canEdit={canEdit}
            fallback={{
              contact_name: supplier.contact_name,
              phone: supplier.phone,
              email: supplier.email,
              website: supplier.website,
              address: supplier.address,
              rep_name: supplier.rep_name,
              rep_phone: supplier.rep_phone,
              rep_email: supplier.rep_email,
              driver_name: supplier.driver_name,
              driver_phone: supplier.driver_phone,
              driver_email: supplier.driver_email,
            }}
          />

          <div className="grid grid-cols-1 gap-6 md:grid-cols-2 mt-6">
            {/* Delivery Info */}
            <div className="space-y-2">
              <h4 className="text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400 flex items-center gap-1.5">
                <Calendar className="h-3.5 w-3.5" />
                Delivery Info
              </h4>
              <div className="space-y-1.5 text-sm">
                <div className="flex flex-wrap gap-1">
                  {(supplier.delivery_methods ?? (supplier.primary_delivery_method ? [supplier.primary_delivery_method] : [])).map((method) => {
                    const isPrimary = method === supplier.primary_delivery_method;
                    return (
                      <Badge key={method} variant={DELIVERY_BADGE_VARIANT[method]}>
                        {DELIVERY_LABELS[method]}
                        {isPrimary && (supplier.delivery_methods?.length ?? 0) > 1 && (
                          <span className="ml-1 text-[10px] opacity-75">(primary)</span>
                        )}
                      </Badge>
                    );
                  })}
                </div>

                {/* Delivery days (only for scheduled) */}
                {hasScheduledDelivery && deliveryDays.length > 0 && (
                  <div className="flex items-center gap-1 flex-wrap mt-1">
                    <Calendar className="h-3.5 w-3.5 text-gray-500 shrink-0" />
                    {deliveryDays.map((day) => (
                      <span
                        key={day}
                        className="px-2 py-0.5 text-xs rounded-full bg-green-100 dark:bg-green-900/30 text-green-700 dark:text-green-300"
                      >
                        {WEEKDAY_LABELS[day] ?? day}
                      </span>
                    ))}
                  </div>
                )}

                {/* Special order lead time */}
                {supplier.special_order_lead_days != null && supplier.special_order_lead_days > 0 && (
                  <div className="flex items-center gap-1.5 text-amber-600 dark:text-amber-400">
                    <Clock className="h-3.5 w-3.5" />
                    Special orders: +{supplier.special_order_lead_days} day{supplier.special_order_lead_days !== 1 ? 's' : ''}
                  </div>
                )}

                {/* Delivery notes */}
                {supplier.delivery_notes && (
                  <div className="text-gray-500 dark:text-gray-400 text-xs italic mt-1">
                    {supplier.delivery_notes}
                  </div>
                )}
              </div>
            </div>
          </div>

          {/* ── Reliability Metrics row ─────────── */}
          <div className="mt-4 pt-3 border-t border-gray-100 dark:border-gray-700/50">
            <div className="flex flex-wrap gap-4 text-xs">
              <ReliabilityBadge
                label="On-Time"
                value={supplier.on_time_rate}
                format="percent"
              />
              <ReliabilityBadge
                label="Quality"
                value={supplier.quality_score}
                format="percent"
              />
              <ReliabilityBadge
                label="Avg Lead"
                value={supplier.avg_lead_days}
                format="days"
              />
              <ReliabilityBadge
                label="Reliability"
                value={supplier.reliability_score}
                format="percent"
              />
            </div>
          </div>

          {/* Notes */}
          {supplier.notes && (
            <div className="mt-3 pt-3 border-t border-gray-100 dark:border-gray-700/50 text-sm text-gray-600 dark:text-gray-400">
              <span className="font-medium text-gray-700 dark:text-gray-300">Notes: </span>
              {supplier.notes}
            </div>
          )}

          {/* Brands Carried */}
          <SupplierBrandsSection supplierId={supplier.id} supplierName={supplier.name} />
        </div>
      )}
    </div>
  );
}
