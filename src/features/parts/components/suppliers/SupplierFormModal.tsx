/**
 * SupplierFormModal — multi-section form modal shared by Create and Edit flows.
 */

import { useState } from 'react';
import { User, UserCheck, Truck, Star } from 'lucide-react';
import { Button } from '../../../../components/ui/Button';
import { Input } from '../../../../components/ui/Input';
import { Modal } from '../../../../components/ui/Modal';
import type { Supplier, SupplierCreate, SupplierUpdate, DeliveryMethod } from '../../../../lib/types';
import { DELIVERY_LABELS, DELIVERY_ICONS, parseDeliveryDays } from './supplier-helpers';


const ALL_WEEKDAYS = [
  { value: 'monday', label: 'Mon' },
  { value: 'tuesday', label: 'Tue' },
  { value: 'wednesday', label: 'Wed' },
  { value: 'thursday', label: 'Thu' },
  { value: 'friday', label: 'Fri' },
  { value: 'saturday', label: 'Sat' },
  { value: 'sunday', label: 'Sun' },
];

export interface SupplierFormModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSubmit: (data: SupplierCreate | SupplierUpdate) => void;
  isLoading: boolean;
  title: string;
  initial?: Supplier | null;
}

export function SupplierFormModal({
  isOpen,
  onClose,
  onSubmit,
  isLoading,
  title,
  initial,
}: SupplierFormModalProps) {
  const [form, setForm] = useState({
    name: initial?.name ?? '',
    // Business contact
    contact_name: initial?.contact_name ?? '',
    email: initial?.email ?? '',
    phone: initial?.phone ?? '',
    address: initial?.address ?? '',
    website: initial?.website ?? '',
    // Sales rep
    rep_name: initial?.rep_name ?? '',
    rep_email: initial?.rep_email ?? '',
    rep_phone: initial?.rep_phone ?? '',
    // Delivery — multi-select with primary
    delivery_methods: (initial?.delivery_methods ?? ['standard_shipping']) as DeliveryMethod[],
    primary_delivery_method: (initial?.primary_delivery_method ?? 'standard_shipping') as DeliveryMethod,
    delivery_days: parseDeliveryDays(initial?.delivery_days ?? null),
    special_order_lead_days: initial?.special_order_lead_days?.toString() ?? '',
    delivery_notes: initial?.delivery_notes ?? '',
    // Delivery driver
    driver_name: initial?.driver_name ?? '',
    driver_phone: initial?.driver_phone ?? '',
    driver_email: initial?.driver_email ?? '',
    // Misc
    notes: initial?.notes ?? '',
  });

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    const data: Record<string, unknown> = {
      name: form.name,
      contact_name: form.contact_name || undefined,
      email: form.email || undefined,
      phone: form.phone || undefined,
      address: form.address || undefined,
      website: form.website || undefined,
      rep_name: form.rep_name || undefined,
      rep_email: form.rep_email || undefined,
      rep_phone: form.rep_phone || undefined,
      delivery_methods: form.delivery_methods,
      primary_delivery_method: form.primary_delivery_method,
      delivery_days: form.delivery_methods.includes('scheduled_delivery') && form.delivery_days.length > 0
        ? JSON.stringify(form.delivery_days)
        : undefined,
      special_order_lead_days: form.special_order_lead_days
        ? parseInt(form.special_order_lead_days, 10)
        : undefined,
      delivery_notes: form.delivery_notes || undefined,
      driver_name: form.driver_name || undefined,
      driver_phone: form.driver_phone || undefined,
      driver_email: form.driver_email || undefined,
      notes: form.notes || undefined,
    };
    onSubmit(data as SupplierCreate | SupplierUpdate);
  };

  const update = <K extends keyof typeof form>(field: K, value: (typeof form)[K]) =>
    setForm((prev) => ({ ...prev, [field]: value }));

  const toggleDeliveryMethod = (method: DeliveryMethod) => {
    setForm((prev) => {
      const has = prev.delivery_methods.includes(method);
      let next: DeliveryMethod[];
      if (has) {
        // Don't allow removing the last method
        if (prev.delivery_methods.length <= 1) return prev;
        next = prev.delivery_methods.filter((m) => m !== method);
      } else {
        next = [...prev.delivery_methods, method];
      }
      // If the primary was removed, auto-pick the first remaining
      const primary = next.includes(prev.primary_delivery_method)
        ? prev.primary_delivery_method
        : next[0];
      return { ...prev, delivery_methods: next, primary_delivery_method: primary };
    });
  };

  const toggleDeliveryDay = (day: string) => {
    setForm((prev) => ({
      ...prev,
      delivery_days: prev.delivery_days.includes(day)
        ? prev.delivery_days.filter((d) => d !== day)
        : [...prev.delivery_days, day],
    }));
  };

  return (
    <Modal isOpen={isOpen} onClose={onClose} title={title} size="lg">
      <form onSubmit={handleSubmit} className="space-y-5 max-h-[70vh] overflow-y-auto pr-1">
        {/* ── Supplier Name ──────────────────────── */}
        <Input
          label="Supplier Name *"
          value={form.name}
          onChange={(e) => update('name', e.target.value)}
          placeholder="e.g. CED Irving"
          required
        />

        {/* ── Business Contact ───────────────────── */}
        <fieldset className="space-y-3 border border-gray-200 dark:border-gray-700 rounded-lg p-3">
          <legend className="text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400 px-1 flex items-center gap-1">
            <User className="h-3.5 w-3.5" />
            Business Contact
          </legend>
          <Input
            label="Contact Name"
            value={form.contact_name}
            onChange={(e) => update('contact_name', e.target.value)}
            placeholder="e.g. Front Desk, Customer Service"
          />
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <Input
              label="Phone"
              value={form.phone}
              onChange={(e) => update('phone', e.target.value)}
              placeholder="972-555-0100"
              type="tel"
            />
            <Input
              label="Email"
              value={form.email}
              onChange={(e) => update('email', e.target.value)}
              placeholder="info@supplier.com"
              type="email"
            />
          </div>
          <Input
            label="Address"
            value={form.address}
            onChange={(e) => update('address', e.target.value)}
            placeholder="123 Supply Rd, Irving TX 75061"
          />
          <Input
            label="Website"
            value={form.website}
            onChange={(e) => update('website', e.target.value)}
            placeholder="https://www.supplier.com"
            type="url"
          />
        </fieldset>

        {/* ── Sales Rep Contact ──────────────────── */}
        <fieldset className="space-y-3 border border-gray-200 dark:border-gray-700 rounded-lg p-3">
          <legend className="text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400 px-1 flex items-center gap-1">
            <UserCheck className="h-3.5 w-3.5" />
            Sales Rep
          </legend>
          <Input
            label="Rep Name"
            value={form.rep_name}
            onChange={(e) => update('rep_name', e.target.value)}
            placeholder="e.g. Mike Johnson"
          />
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <Input
              label="Rep Phone"
              value={form.rep_phone}
              onChange={(e) => update('rep_phone', e.target.value)}
              placeholder="972-555-0101"
              type="tel"
            />
            <Input
              label="Rep Email"
              value={form.rep_email}
              onChange={(e) => update('rep_email', e.target.value)}
              placeholder="rep@supplier.com"
              type="email"
            />
          </div>
        </fieldset>

        {/* ── Delivery Settings ──────────────────── */}
        <fieldset className="space-y-3 border border-gray-200 dark:border-gray-700 rounded-lg p-3">
          <legend className="text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400 px-1 flex items-center gap-1">
            <Truck className="h-3.5 w-3.5" />
            Delivery
          </legend>

          {/* Delivery Methods — multi-select */}
          <div className="space-y-1.5">
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300">
              Delivery Methods
            </label>
            <p className="text-xs text-gray-500 dark:text-gray-400">
              Select all that apply
            </p>
            <div className="flex flex-wrap gap-2">
              {(['standard_shipping', 'scheduled_delivery', 'in_store_pickup'] as DeliveryMethod[]).map(
                (method) => {
                  const Icon = DELIVERY_ICONS[method];
                  const isSelected = form.delivery_methods.includes(method);
                  return (
                    <button
                      key={method}
                      type="button"
                      className={`flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-sm border transition-colors ${isSelected
                          ? 'border-primary-500 bg-primary-50 dark:bg-primary-900/20 text-primary-700 dark:text-primary-300'
                          : 'border-gray-200 dark:border-gray-600 hover:border-gray-300 dark:hover:border-gray-500'
                        }`}
                      onClick={() => toggleDeliveryMethod(method)}
                    >
                      <Icon className="h-3.5 w-3.5" />
                      {DELIVERY_LABELS[method]}
                    </button>
                  );
                },
              )}
            </div>
          </div>

          {/* Primary Delivery Method — dropdown (only if 2+ selected) */}
          {form.delivery_methods.length > 1 && (
            <div className="space-y-1.5">
              <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 flex items-center gap-1.5">
                <Star className="h-3.5 w-3.5 text-amber-500" />
                Primary Method
              </label>
              <p className="text-xs text-gray-500 dark:text-gray-400">
                Which method do you use most often?
              </p>
              <select
                className="w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm"
                value={form.primary_delivery_method}
                onChange={(e) => update('primary_delivery_method', e.target.value as DeliveryMethod)}
              >
                {form.delivery_methods.map((method) => (
                  <option key={method} value={method}>
                    {DELIVERY_LABELS[method]}
                  </option>
                ))}
              </select>
            </div>
          )}

          {/* Delivery Driver (only if scheduled delivery is selected) */}
          {form.delivery_methods.includes('scheduled_delivery') && (
            <div className="space-y-3 mt-2 p-2.5 rounded-lg bg-gray-50 dark:bg-gray-900/40">
              <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 flex items-center gap-1.5">
                <Truck className="h-3.5 w-3.5" />
                Delivery Driver
              </label>
              <Input
                label="Driver Name"
                value={form.driver_name}
                onChange={(e) => update('driver_name', e.target.value)}
                placeholder="e.g. Carlos"
              />
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <Input
                  label="Driver Phone"
                  value={form.driver_phone}
                  onChange={(e) => update('driver_phone', e.target.value)}
                  placeholder="972-555-0102"
                  type="tel"
                />
                <Input
                  label="Driver Email"
                  value={form.driver_email}
                  onChange={(e) => update('driver_email', e.target.value)}
                  placeholder="driver@supplier.com"
                  type="email"
                />
              </div>
            </div>
          )}

          {/* Delivery Days (only if scheduled delivery is selected) */}
          {form.delivery_methods.includes('scheduled_delivery') && (
            <div className="space-y-1.5">
              <label className="block text-sm font-medium text-gray-700 dark:text-gray-300">
                Delivery Days
              </label>
              <div className="flex flex-wrap gap-1.5">
                {ALL_WEEKDAYS.map(({ value, label }) => (
                  <button
                    key={value}
                    type="button"
                    className={`px-3 py-1 rounded-full text-xs font-medium border transition-colors ${form.delivery_days.includes(value)
                        ? 'border-green-500 bg-green-100 dark:bg-green-900/30 text-green-700 dark:text-green-300'
                        : 'border-gray-200 dark:border-gray-600 text-gray-500 hover:border-gray-300'
                      }`}
                    onClick={() => toggleDeliveryDay(value)}
                  >
                    {label}
                  </button>
                ))}
              </div>
            </div>
          )}

          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <Input
              label="Special Order Lead Days"
              value={form.special_order_lead_days}
              onChange={(e) => update('special_order_lead_days', e.target.value)}
              placeholder="e.g. 3"
              type="number"
              min="0"
              hint="Extra days for items not in local warehouse"
            />
            <div className="space-y-1.5">
              <label className="block text-sm font-medium text-gray-700 dark:text-gray-300">
                Delivery Notes
              </label>
              <input
                className="block w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm"
                value={form.delivery_notes}
                onChange={(e) => update('delivery_notes', e.target.value)}
                placeholder="e.g. Delivers 7am-noon only"
              />
            </div>
          </div>
        </fieldset>

        {/* ── Notes ──────────────────────────────── */}
        <div className="space-y-1.5">
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300">Notes</label>
          <textarea
            className="w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm min-h-[80px]"
            value={form.notes}
            onChange={(e) => update('notes', e.target.value)}
            placeholder="Any additional notes about this supplier..."
          />
        </div>

        {/* ── Submit ─────────────────────────────── */}
        <div className="flex justify-end gap-2 pt-2 border-t border-gray-200 dark:border-gray-700">
          <Button variant="secondary" type="button" onClick={onClose}>Cancel</Button>
          <Button type="submit" isLoading={isLoading}>
            {initial ? 'Save Changes' : 'Create Supplier'}
          </Button>
        </div>
      </form>
    </Modal>
  );
}
