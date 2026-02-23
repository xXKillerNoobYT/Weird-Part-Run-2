/**
 * SuppliersPage — manage supplier / parts house directory.
 *
 * This is the go-to reference for anyone who needs to contact a supplier,
 * whether from the office or in the field. Every supplier shows:
 *
 *  1. Business contact — main office phone, email (for returns, billing, general)
 *  2. Sales rep contact — the person you call for orders and quotes
 *  3. Delivery driver — the driver who physically brings the parts (for scheduled suppliers)
 *  4. Delivery method — how they get parts to you (shipping, scheduled, pickup)
 *  5. Delivery schedule — which days they deliver (for scheduled suppliers)
 *  6. Special order info — lead days for items not in local warehouse
 *  7. Reliability metrics — on-time rate, quality score, avg lead days
 *
 * Features:
 *  - Searchable table with expandable detail rows
 *  - Add / Edit / Delete with multi-section form modal
 *  - Inline active/inactive toggle
 *  - Delivery method badges with color coding
 *  - Click-to-call phone links and mailto email links
 */

import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  Building2, Plus, Search, Edit2, Trash2, Globe, Phone, Mail,
  AlertTriangle, ToggleLeft, ToggleRight, Truck, MapPin, Clock,
  ChevronDown, ChevronRight, User, UserCheck, Calendar,
} from 'lucide-react';
import { Button } from '../../../components/ui/Button';
import { Input } from '../../../components/ui/Input';
import { Badge } from '../../../components/ui/Badge';
import { Modal } from '../../../components/ui/Modal';
import { Spinner } from '../../../components/ui/Spinner';
import { EmptyState } from '../../../components/ui/EmptyState';
import { useAuthStore } from '../../../stores/auth-store';
import { PERMISSIONS } from '../../../lib/constants';
import {
  listSuppliers, createSupplier, updateSupplier, deleteSupplier,
} from '../../../api/parts';
import type { Supplier, SupplierCreate, SupplierUpdate, DeliveryMethod } from '../../../lib/types';


// ── Delivery method display helpers ─────────────────────────────

const DELIVERY_LABELS: Record<DeliveryMethod, string> = {
  standard_shipping: 'Standard Shipping',
  scheduled_delivery: 'Scheduled Delivery',
  in_store_pickup: 'In-Store Pickup',
};

const DELIVERY_BADGE_VARIANT: Record<DeliveryMethod, 'info' | 'success' | 'warning'> = {
  standard_shipping: 'info',
  scheduled_delivery: 'success',
  in_store_pickup: 'warning',
};

const DELIVERY_ICONS: Record<DeliveryMethod, typeof Truck> = {
  standard_shipping: Truck,
  scheduled_delivery: Calendar,
  in_store_pickup: MapPin,
};

const WEEKDAY_LABELS: Record<string, string> = {
  monday: 'Mon', tuesday: 'Tue', wednesday: 'Wed',
  thursday: 'Thu', friday: 'Fri', saturday: 'Sat', sunday: 'Sun',
};

function parseDeliveryDays(json: string | null): string[] {
  if (!json) return [];
  try {
    const parsed = JSON.parse(json);
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}


export function SuppliersPage() {
  const queryClient = useQueryClient();
  const { hasPermission } = useAuthStore();
  const canEdit = hasPermission(PERMISSIONS.EDIT_PARTS_CATALOG);

  // ── State ─────────────────────────────────────────
  const [searchText, setSearchText] = useState('');
  const [expandedId, setExpandedId] = useState<number | null>(null);
  const [isCreateOpen, setIsCreateOpen] = useState(false);
  const [editingSupplier, setEditingSupplier] = useState<Supplier | null>(null);
  const [deleteConfirm, setDeleteConfirm] = useState<Supplier | null>(null);

  // ── Query ─────────────────────────────────────────
  const { data: suppliers, isLoading, error } = useQuery({
    queryKey: ['suppliers', { search: searchText || undefined }],
    queryFn: () => listSuppliers({ search: searchText || undefined }),
  });

  // ── Mutations ─────────────────────────────────────
  const createMutation = useMutation({
    mutationFn: createSupplier,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['suppliers'] });
      setIsCreateOpen(false);
    },
  });

  const updateMutation = useMutation({
    mutationFn: ({ id, data }: { id: number; data: SupplierUpdate }) =>
      updateSupplier(id, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['suppliers'] });
      setEditingSupplier(null);
    },
  });

  const deleteMutation = useMutation({
    mutationFn: deleteSupplier,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['suppliers'] });
      setDeleteConfirm(null);
    },
  });

  const toggleActiveMutation = useMutation({
    mutationFn: ({ id, is_active }: { id: number; is_active: boolean }) =>
      updateSupplier(id, { is_active }),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['suppliers'] }),
  });

  const items = suppliers ?? [];

  return (
    <div className="space-y-4">
      {/* ── Header ───────────────────────────────── */}
      <div className="flex flex-col sm:flex-row gap-3 items-start sm:items-center justify-between">
        <div className="flex-1 w-full sm:max-w-md">
          <Input
            placeholder="Search suppliers, contacts, reps..."
            icon={<Search className="h-4 w-4" />}
            value={searchText}
            onChange={(e) => setSearchText(e.target.value)}
          />
        </div>
        {canEdit && (
          <Button
            size="sm"
            icon={<Plus className="h-4 w-4" />}
            onClick={() => setIsCreateOpen(true)}
          >
            Add Supplier
          </Button>
        )}
      </div>

      {/* ── Results summary ──────────────────────── */}
      <div className="text-sm text-gray-500 dark:text-gray-400">
        {isLoading ? 'Loading...' : `${items.length} supplier${items.length !== 1 ? 's' : ''}`}
      </div>

      {/* ── Supplier Cards ────────────────────────── */}
      {isLoading ? (
        <div className="flex justify-center py-12">
          <Spinner size="lg" />
        </div>
      ) : error ? (
        <EmptyState
          icon={<AlertTriangle className="h-12 w-12 text-red-400" />}
          title="Error loading suppliers"
          description={String(error)}
        />
      ) : items.length === 0 ? (
        <EmptyState
          icon={<Building2 className="h-12 w-12" />}
          title="No suppliers found"
          description={searchText ? 'Try a different search term.' : 'Add your first supplier to get started.'}
        />
      ) : (
        <div className="space-y-3">
          {items.map((supplier) => (
            <SupplierCard
              key={supplier.id}
              supplier={supplier}
              isExpanded={expandedId === supplier.id}
              onToggleExpand={() =>
                setExpandedId(expandedId === supplier.id ? null : supplier.id)
              }
              canEdit={canEdit}
              onEdit={() => setEditingSupplier(supplier)}
              onDelete={() => setDeleteConfirm(supplier)}
              onToggleActive={() =>
                toggleActiveMutation.mutate({
                  id: supplier.id,
                  is_active: !supplier.is_active,
                })
              }
            />
          ))}
        </div>
      )}

      {/* ── Create Modal ─────────────────────────── */}
      <SupplierFormModal
        isOpen={isCreateOpen}
        onClose={() => setIsCreateOpen(false)}
        onSubmit={(data) => createMutation.mutate(data as SupplierCreate)}
        isLoading={createMutation.isPending}
        title="Add Supplier"
      />

      {/* ── Edit Modal ───────────────────────────── */}
      {editingSupplier && (
        <SupplierFormModal
          isOpen={true}
          onClose={() => setEditingSupplier(null)}
          onSubmit={(data) =>
            updateMutation.mutate({ id: editingSupplier.id, data: data as SupplierUpdate })
          }
          isLoading={updateMutation.isPending}
          title={`Edit: ${editingSupplier.name}`}
          initial={editingSupplier}
        />
      )}

      {/* ── Delete Confirmation ──────────────────── */}
      {deleteConfirm && (
        <Modal isOpen={true} onClose={() => setDeleteConfirm(null)} title="Delete Supplier?" size="sm">
          <p className="text-gray-600 dark:text-gray-300 mb-4">
            Are you sure you want to delete <strong>{deleteConfirm.name}</strong>?
            This will also remove all part-supplier links for this supplier.
          </p>
          {deleteMutation.isError && (
            <p className="text-red-500 text-sm mb-4">
              {(deleteMutation.error as any)?.response?.data?.detail ?? 'Failed to delete supplier.'}
            </p>
          )}
          <div className="flex justify-end gap-2">
            <Button variant="secondary" onClick={() => setDeleteConfirm(null)}>Cancel</Button>
            <Button
              variant="danger"
              isLoading={deleteMutation.isPending}
              onClick={() => deleteMutation.mutate(deleteConfirm.id)}
            >
              Delete
            </Button>
          </div>
        </Modal>
      )}
    </div>
  );
}


// ═══════════════════════════════════════════════════════════════
// Supplier Card — expandable row showing contacts + delivery info
// ═══════════════════════════════════════════════════════════════

interface SupplierCardProps {
  supplier: Supplier;
  isExpanded: boolean;
  onToggleExpand: () => void;
  canEdit: boolean;
  onEdit: () => void;
  onDelete: () => void;
  onToggleActive: () => void;
}

function SupplierCard({
  supplier,
  isExpanded,
  onToggleExpand,
  canEdit,
  onEdit,
  onDelete,
  onToggleActive,
}: SupplierCardProps) {
  const DeliveryIcon = DELIVERY_ICONS[supplier.delivery_method] ?? Truck;
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
            {supplier.delivery_method === 'scheduled_delivery' && supplier.driver_name && (
              <span className="flex items-center gap-1">
                <Truck className="h-3 w-3" />
                Driver: {supplier.driver_name}
              </span>
            )}
          </div>
        </div>

        {/* Delivery badge */}
        <Badge variant={DELIVERY_BADGE_VARIANT[supplier.delivery_method]}>
          <DeliveryIcon className="h-3 w-3 mr-1 inline" />
          {DELIVERY_LABELS[supplier.delivery_method]}
        </Badge>

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
          <div className={`grid grid-cols-1 gap-6 ${
            supplier.delivery_method === 'scheduled_delivery'
              ? 'md:grid-cols-4'
              : 'md:grid-cols-3'
          }`}>
            {/* Business Contact */}
            <div className="space-y-2">
              <h4 className="text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400 flex items-center gap-1.5">
                <User className="h-3.5 w-3.5" />
                Business Contact
              </h4>
              <div className="space-y-1.5 text-sm">
                {supplier.contact_name && (
                  <div className="text-gray-900 dark:text-gray-100 font-medium">
                    {supplier.contact_name}
                  </div>
                )}
                {supplier.phone && (
                  <a
                    href={`tel:${supplier.phone}`}
                    className="flex items-center gap-1.5 text-primary-500 hover:text-primary-600 hover:underline"
                  >
                    <Phone className="h-3.5 w-3.5" />
                    {supplier.phone}
                  </a>
                )}
                {supplier.email && (
                  <a
                    href={`mailto:${supplier.email}`}
                    className="flex items-center gap-1.5 text-primary-500 hover:text-primary-600 hover:underline"
                  >
                    <Mail className="h-3.5 w-3.5" />
                    {supplier.email}
                  </a>
                )}
                {supplier.website && (
                  <a
                    href={supplier.website}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="flex items-center gap-1.5 text-primary-500 hover:text-primary-600 hover:underline"
                  >
                    <Globe className="h-3.5 w-3.5" />
                    <span className="truncate">
                      {supplier.website.replace(/^https?:\/\/(www\.)?/, '')}
                    </span>
                  </a>
                )}
                {supplier.address && (
                  <div className="flex items-start gap-1.5 text-gray-600 dark:text-gray-400">
                    <MapPin className="h-3.5 w-3.5 mt-0.5 shrink-0" />
                    {supplier.address}
                  </div>
                )}
                {!supplier.contact_name && !supplier.phone && !supplier.email && (
                  <span className="text-gray-400 italic text-xs">No business contact on file</span>
                )}
              </div>
            </div>

            {/* Sales Rep */}
            <div className="space-y-2">
              <h4 className="text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400 flex items-center gap-1.5">
                <UserCheck className="h-3.5 w-3.5" />
                Sales Rep
              </h4>
              <div className="space-y-1.5 text-sm">
                {supplier.rep_name && (
                  <div className="text-gray-900 dark:text-gray-100 font-medium">
                    {supplier.rep_name}
                  </div>
                )}
                {supplier.rep_phone && (
                  <a
                    href={`tel:${supplier.rep_phone}`}
                    className="flex items-center gap-1.5 text-primary-500 hover:text-primary-600 hover:underline"
                  >
                    <Phone className="h-3.5 w-3.5" />
                    {supplier.rep_phone}
                  </a>
                )}
                {supplier.rep_email && (
                  <a
                    href={`mailto:${supplier.rep_email}`}
                    className="flex items-center gap-1.5 text-primary-500 hover:text-primary-600 hover:underline"
                  >
                    <Mail className="h-3.5 w-3.5" />
                    {supplier.rep_email}
                  </a>
                )}
                {!supplier.rep_name && !supplier.rep_phone && !supplier.rep_email && (
                  <span className="text-gray-400 italic text-xs">No sales rep on file</span>
                )}
              </div>
            </div>

            {/* Delivery Driver (only shown for scheduled delivery suppliers) */}
            {supplier.delivery_method === 'scheduled_delivery' && (
              <div className="space-y-2">
                <h4 className="text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400 flex items-center gap-1.5">
                  <Truck className="h-3.5 w-3.5" />
                  Delivery Driver
                </h4>
                <div className="space-y-1.5 text-sm">
                  {supplier.driver_name && (
                    <div className="text-gray-900 dark:text-gray-100 font-medium">
                      {supplier.driver_name}
                    </div>
                  )}
                  {supplier.driver_phone && (
                    <a
                      href={`tel:${supplier.driver_phone}`}
                      className="flex items-center gap-1.5 text-primary-500 hover:text-primary-600 hover:underline"
                    >
                      <Phone className="h-3.5 w-3.5" />
                      {supplier.driver_phone}
                    </a>
                  )}
                  {supplier.driver_email && (
                    <a
                      href={`mailto:${supplier.driver_email}`}
                      className="flex items-center gap-1.5 text-primary-500 hover:text-primary-600 hover:underline"
                    >
                      <Mail className="h-3.5 w-3.5" />
                      {supplier.driver_email}
                    </a>
                  )}
                  {!supplier.driver_name && !supplier.driver_phone && !supplier.driver_email && (
                    <span className="text-gray-400 italic text-xs">No driver contact on file</span>
                  )}
                </div>
              </div>
            )}

            {/* Delivery Info */}
            <div className="space-y-2">
              <h4 className="text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400 flex items-center gap-1.5">
                <Calendar className="h-3.5 w-3.5" />
                Delivery Info
              </h4>
              <div className="space-y-1.5 text-sm">
                <Badge variant={DELIVERY_BADGE_VARIANT[supplier.delivery_method]}>
                  {DELIVERY_LABELS[supplier.delivery_method]}
                </Badge>

                {/* Delivery days (only for scheduled) */}
                {supplier.delivery_method === 'scheduled_delivery' && deliveryDays.length > 0 && (
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
        </div>
      )}
    </div>
  );
}


// ── Reliability badge ─────────────────────────────────────────

function ReliabilityBadge({
  label,
  value,
  format,
}: {
  label: string;
  value: number;
  format: 'percent' | 'days';
}) {
  let display: string;
  let color: string;

  if (format === 'percent') {
    const pct = Math.round(value * 100);
    display = `${pct}%`;
    color = pct >= 90 ? 'text-green-600 dark:text-green-400'
          : pct >= 75 ? 'text-amber-600 dark:text-amber-400'
          : 'text-red-600 dark:text-red-400';
  } else {
    display = `${value}d`;
    color = value <= 3 ? 'text-green-600 dark:text-green-400'
          : value <= 7 ? 'text-amber-600 dark:text-amber-400'
          : 'text-red-600 dark:text-red-400';
  }

  return (
    <div className="flex items-center gap-1">
      <span className="text-gray-500 dark:text-gray-400">{label}:</span>
      <span className={`font-semibold ${color}`}>{display}</span>
    </div>
  );
}


// ═══════════════════════════════════════════════════════════════
// Supplier Form Modal (shared by Create + Edit)
// ═══════════════════════════════════════════════════════════════

const ALL_WEEKDAYS = [
  { value: 'monday', label: 'Mon' },
  { value: 'tuesday', label: 'Tue' },
  { value: 'wednesday', label: 'Wed' },
  { value: 'thursday', label: 'Thu' },
  { value: 'friday', label: 'Fri' },
  { value: 'saturday', label: 'Sat' },
  { value: 'sunday', label: 'Sun' },
];

interface SupplierFormModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSubmit: (data: SupplierCreate | SupplierUpdate) => void;
  isLoading: boolean;
  title: string;
  initial?: Supplier | null;
}

function SupplierFormModal({
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
    // Delivery
    delivery_method: (initial?.delivery_method ?? 'standard_shipping') as DeliveryMethod,
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
      delivery_method: form.delivery_method,
      delivery_days: form.delivery_method === 'scheduled_delivery' && form.delivery_days.length > 0
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

          {/* Delivery Method Radio */}
          <div className="space-y-1.5">
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300">
              Delivery Method
            </label>
            <div className="flex flex-wrap gap-2">
              {(['standard_shipping', 'scheduled_delivery', 'in_store_pickup'] as DeliveryMethod[]).map(
                (method) => {
                  const Icon = DELIVERY_ICONS[method];
                  return (
                    <button
                      key={method}
                      type="button"
                      className={`flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-sm border transition-colors ${
                        form.delivery_method === method
                          ? 'border-primary-500 bg-primary-50 dark:bg-primary-900/20 text-primary-700 dark:text-primary-300'
                          : 'border-gray-200 dark:border-gray-600 hover:border-gray-300 dark:hover:border-gray-500'
                      }`}
                      onClick={() => update('delivery_method', method)}
                    >
                      <Icon className="h-3.5 w-3.5" />
                      {DELIVERY_LABELS[method]}
                    </button>
                  );
                },
              )}
            </div>
          </div>

          {/* Delivery Driver (only for scheduled) */}
          {form.delivery_method === 'scheduled_delivery' && (
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

          {/* Delivery Days (only for scheduled) */}
          {form.delivery_method === 'scheduled_delivery' && (
            <div className="space-y-1.5">
              <label className="block text-sm font-medium text-gray-700 dark:text-gray-300">
                Delivery Days
              </label>
              <div className="flex flex-wrap gap-1.5">
                {ALL_WEEKDAYS.map(({ value, label }) => (
                  <button
                    key={value}
                    type="button"
                    className={`px-3 py-1 rounded-full text-xs font-medium border transition-colors ${
                      form.delivery_days.includes(value)
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
