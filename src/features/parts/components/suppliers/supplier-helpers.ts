/**
 * Shared constants and helpers for supplier components.
 */

import { Truck, Calendar, MapPin } from 'lucide-react';
import type { DeliveryMethod } from '../../../../lib/types';


export const DELIVERY_LABELS: Record<DeliveryMethod, string> = {
  standard_shipping: 'Standard Shipping',
  scheduled_delivery: 'Scheduled Delivery',
  in_store_pickup: 'In-Store Pickup',
};

export const DELIVERY_BADGE_VARIANT: Record<DeliveryMethod, 'info' | 'success' | 'warning'> = {
  standard_shipping: 'info',
  scheduled_delivery: 'success',
  in_store_pickup: 'warning',
};

export const DELIVERY_ICONS: Record<DeliveryMethod, typeof Truck> = {
  standard_shipping: Truck,
  scheduled_delivery: Calendar,
  in_store_pickup: MapPin,
};

export const WEEKDAY_LABELS: Record<string, string> = {
  monday: 'Mon', tuesday: 'Tue', wednesday: 'Wed',
  thursday: 'Thu', friday: 'Fri', saturday: 'Sat', sunday: 'Sun',
};

export function parseDeliveryDays(json: string | null): string[] {
  if (!json) return [];
  try {
    const parsed = JSON.parse(json);
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}
