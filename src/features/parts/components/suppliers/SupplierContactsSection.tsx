/**
 * SupplierContactsSection — dynamic entity_contacts with
 * backward-compatible fallback to hardcoded fields.
 *
 * Also includes the FallbackContactsDisplay and ContactInlineForm
 * sub-components used only within this section.
 */

import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  User, UserCheck, UserPlus, Phone, Mail, Globe, MapPin, Truck,
  Edit2, Trash2,
} from 'lucide-react';
import { Badge } from '../../../../components/ui/Badge';
import { Spinner } from '../../../../components/ui/Spinner';
import {
  getSupplierContacts, addSupplierContact,
  updateEntityContact, deleteEntityContact,
} from '../../../../api/contacts';
import type {
  EntityContactResponse, EntityContactCreate, EntityContactUpdate,
} from '../../../../lib/types';


// ── Public types ──────────────────────────────────────────────

export interface SupplierContactsFallback {
  contact_name?: string | null;
  phone?: string | null;
  email?: string | null;
  website?: string | null;
  address?: string | null;
  rep_name?: string | null;
  rep_phone?: string | null;
  rep_email?: string | null;
  driver_name?: string | null;
  driver_phone?: string | null;
  driver_email?: string | null;
}


// ── Main section ──────────────────────────────────────────────

export function SupplierContactsSection({
  supplierId,
  canEdit,
  fallback,
}: {
  supplierId: number;
  canEdit: boolean;
  fallback: SupplierContactsFallback;
}) {
  const queryClient = useQueryClient();
  const [showAddForm, setShowAddForm] = useState(false);
  const [editingContact, setEditingContact] = useState<EntityContactResponse | null>(null);

  const { data: contacts, isLoading } = useQuery({
    queryKey: ['supplier-contacts', supplierId],
    queryFn: () => getSupplierContacts(supplierId),
  });

  const addMutation = useMutation({
    mutationFn: (data: EntityContactCreate) => addSupplierContact(supplierId, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['supplier-contacts', supplierId] });
      setShowAddForm(false);
    },
  });

  const updateMutation = useMutation({
    mutationFn: ({ id, data }: { id: number; data: EntityContactUpdate }) =>
      updateEntityContact(id, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['supplier-contacts', supplierId] });
      setEditingContact(null);
    },
  });

  const deleteMutation = useMutation({
    mutationFn: deleteEntityContact,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['supplier-contacts', supplierId] });
    },
  });

  // Use entity_contacts if available; fall back to hardcoded columns if empty
  const hasEntityContacts = (contacts ?? []).length > 0;

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between">
        <h4 className="text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400 flex items-center gap-1.5">
          <User className="h-3.5 w-3.5" />
          Contacts
        </h4>
        {canEdit && !showAddForm && (
          <button
            onClick={() => setShowAddForm(true)}
            className="flex items-center gap-1 text-xs text-primary-500 hover:text-primary-600 font-medium"
          >
            <UserPlus className="h-3.5 w-3.5" />
            Add Contact
          </button>
        )}
      </div>

      {/* Add contact inline form */}
      {showAddForm && (
        <ContactInlineForm
          onSubmit={(data) => addMutation.mutate(data as EntityContactCreate)}
          onCancel={() => setShowAddForm(false)}
          isLoading={addMutation.isPending}
        />
      )}

      {isLoading ? (
        <div className="flex items-center gap-2 text-sm text-gray-500">
          <Spinner size="sm" /> Loading contacts...
        </div>
      ) : hasEntityContacts ? (
        /* ── Dynamic entity_contacts list ──────── */
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
          {(contacts ?? []).map((contact) => (
            <div
              key={contact.id}
              className="p-3 rounded-lg border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800/50 space-y-1.5"
            >
              {editingContact?.id === contact.id ? (
                <ContactInlineForm
                  initial={contact}
                  onSubmit={(data) =>
                    updateMutation.mutate({ id: contact.id, data })
                  }
                  onCancel={() => setEditingContact(null)}
                  isLoading={updateMutation.isPending}
                />
              ) : (
                <>
                  <div className="flex items-center justify-between">
                    <div className="flex items-center gap-2 min-w-0">
                      <span className="font-medium text-sm text-gray-900 dark:text-gray-100 truncate">
                        {contact.first_name} {contact.last_name}
                      </span>
                      <Badge variant="info" className="text-[10px] flex-shrink-0">
                        {contact.role}
                      </Badge>
                      {contact.is_primary && (
                        <Badge variant="success" className="text-[10px] flex-shrink-0">
                          Primary
                        </Badge>
                      )}
                    </div>
                    {canEdit && (
                      <div className="flex items-center gap-0.5 ml-1 flex-shrink-0">
                        <button
                          onClick={() => setEditingContact(contact)}
                          className="p-1 rounded hover:bg-gray-100 dark:hover:bg-gray-700"
                          title="Edit"
                        >
                          <Edit2 className="h-3 w-3 text-gray-400" />
                        </button>
                        <button
                          onClick={() => deleteMutation.mutate(contact.id)}
                          className="p-1 rounded hover:bg-red-100 dark:hover:bg-red-900/30"
                          title="Remove"
                        >
                          <Trash2 className="h-3 w-3 text-red-400" />
                        </button>
                      </div>
                    )}
                  </div>
                  <div className="space-y-0.5 text-sm">
                    {contact.phone && (
                      <a
                        href={`tel:${contact.phone}`}
                        className="flex items-center gap-1.5 text-primary-500 hover:text-primary-600 hover:underline"
                      >
                        <Phone className="h-3 w-3" />
                        {contact.phone}
                      </a>
                    )}
                    {contact.email && (
                      <a
                        href={`mailto:${contact.email}`}
                        className="flex items-center gap-1.5 text-primary-500 hover:text-primary-600 hover:underline"
                      >
                        <Mail className="h-3 w-3" />
                        {contact.email}
                      </a>
                    )}
                  </div>
                </>
              )}
            </div>
          ))}
        </div>
      ) : (
        /* ── Fallback: hardcoded columns (pre-migration data) ── */
        <FallbackContactsDisplay fallback={fallback} />
      )}
    </div>
  );
}


// ── Fallback contacts (old-style hardcoded columns) ───────────

function FallbackContactsDisplay({ fallback }: { fallback: SupplierContactsFallback }) {
  const hasBusiness = fallback.contact_name || fallback.phone || fallback.email;
  const hasRep = fallback.rep_name || fallback.rep_phone || fallback.rep_email;
  const hasDriver = fallback.driver_name || fallback.driver_phone || fallback.driver_email;

  if (!hasBusiness && !hasRep && !hasDriver) {
    return (
      <p className="text-sm text-gray-400 dark:text-gray-500 italic">
        No contacts on file. Click "Add Contact" to add one.
      </p>
    );
  }

  return (
    <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
      {hasBusiness && (
        <div className="space-y-1.5 text-sm">
          <div className="flex items-center gap-1 text-xs font-medium text-gray-500 dark:text-gray-400">
            <User className="h-3 w-3" /> Business Contact
          </div>
          {fallback.contact_name && (
            <div className="text-gray-900 dark:text-gray-100 font-medium">{fallback.contact_name}</div>
          )}
          {fallback.phone && (
            <a href={`tel:${fallback.phone}`} className="flex items-center gap-1.5 text-primary-500 hover:underline">
              <Phone className="h-3 w-3" /> {fallback.phone}
            </a>
          )}
          {fallback.email && (
            <a href={`mailto:${fallback.email}`} className="flex items-center gap-1.5 text-primary-500 hover:underline">
              <Mail className="h-3 w-3" /> {fallback.email}
            </a>
          )}
          {fallback.website && (
            <a href={fallback.website} target="_blank" rel="noopener noreferrer" className="flex items-center gap-1.5 text-primary-500 hover:underline">
              <Globe className="h-3 w-3" />
              <span className="truncate">{fallback.website.replace(/^https?:\/\/(www\.)?/, '')}</span>
            </a>
          )}
          {fallback.address && (
            <div className="flex items-start gap-1.5 text-gray-600 dark:text-gray-400">
              <MapPin className="h-3 w-3 mt-0.5 shrink-0" /> {fallback.address}
            </div>
          )}
        </div>
      )}
      {hasRep && (
        <div className="space-y-1.5 text-sm">
          <div className="flex items-center gap-1 text-xs font-medium text-gray-500 dark:text-gray-400">
            <UserCheck className="h-3 w-3" /> Sales Rep
          </div>
          {fallback.rep_name && (
            <div className="text-gray-900 dark:text-gray-100 font-medium">{fallback.rep_name}</div>
          )}
          {fallback.rep_phone && (
            <a href={`tel:${fallback.rep_phone}`} className="flex items-center gap-1.5 text-primary-500 hover:underline">
              <Phone className="h-3 w-3" /> {fallback.rep_phone}
            </a>
          )}
          {fallback.rep_email && (
            <a href={`mailto:${fallback.rep_email}`} className="flex items-center gap-1.5 text-primary-500 hover:underline">
              <Mail className="h-3 w-3" /> {fallback.rep_email}
            </a>
          )}
        </div>
      )}
      {hasDriver && (
        <div className="space-y-1.5 text-sm">
          <div className="flex items-center gap-1 text-xs font-medium text-gray-500 dark:text-gray-400">
            <Truck className="h-3 w-3" /> Delivery Driver
          </div>
          {fallback.driver_name && (
            <div className="text-gray-900 dark:text-gray-100 font-medium">{fallback.driver_name}</div>
          )}
          {fallback.driver_phone && (
            <a href={`tel:${fallback.driver_phone}`} className="flex items-center gap-1.5 text-primary-500 hover:underline">
              <Phone className="h-3 w-3" /> {fallback.driver_phone}
            </a>
          )}
          {fallback.driver_email && (
            <a href={`mailto:${fallback.driver_email}`} className="flex items-center gap-1.5 text-primary-500 hover:underline">
              <Mail className="h-3 w-3" /> {fallback.driver_email}
            </a>
          )}
        </div>
      )}
    </div>
  );
}


// ── Inline add/edit form for entity contacts ──────────────────

function ContactInlineForm({
  initial,
  onSubmit,
  onCancel,
  isLoading,
}: {
  initial?: EntityContactResponse;
  onSubmit: (data: EntityContactCreate | EntityContactUpdate) => void;
  onCancel: () => void;
  isLoading: boolean;
}) {
  const [form, setForm] = useState({
    first_name: initial?.first_name ?? '',
    last_name: initial?.last_name ?? '',
    role: initial?.role ?? '',
    phone: initial?.phone ?? '',
    email: initial?.email ?? '',
    is_primary: initial?.is_primary ?? false,
  });

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    onSubmit({
      first_name: form.first_name,
      last_name: form.last_name,
      role: form.role,
      phone: form.phone,
      email: form.email || undefined,
      is_primary: !!form.is_primary,
    });
  };

  return (
    <form onSubmit={handleSubmit} className="p-3 rounded-lg border border-primary-200 dark:border-primary-800 bg-primary-50/50 dark:bg-primary-900/10 space-y-2">
      <div className="grid grid-cols-2 gap-2">
        <input
          className="rounded border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-2 py-1.5 text-sm"
          placeholder="First name *"
          value={form.first_name}
          onChange={(e) => setForm(f => ({ ...f, first_name: e.target.value }))}
          required
        />
        <input
          className="rounded border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-2 py-1.5 text-sm"
          placeholder="Last name *"
          value={form.last_name}
          onChange={(e) => setForm(f => ({ ...f, last_name: e.target.value }))}
          required
        />
      </div>
      <div className="grid grid-cols-2 gap-2">
        <input
          className="rounded border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-2 py-1.5 text-sm"
          placeholder="Role * (e.g. Sales Rep)"
          value={form.role}
          onChange={(e) => setForm(f => ({ ...f, role: e.target.value }))}
          required
        />
        <input
          className="rounded border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-2 py-1.5 text-sm"
          placeholder="Phone *"
          value={form.phone}
          onChange={(e) => setForm(f => ({ ...f, phone: e.target.value }))}
          required
          type="tel"
        />
      </div>
      <div className="grid grid-cols-2 gap-2">
        <input
          className="rounded border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-2 py-1.5 text-sm"
          placeholder="Email"
          value={form.email}
          onChange={(e) => setForm(f => ({ ...f, email: e.target.value }))}
          type="email"
        />
        <label className="flex items-center gap-2 text-sm text-gray-600 dark:text-gray-400 cursor-pointer">
          <input
            type="checkbox"
            className="rounded"
            checked={!!form.is_primary}
            onChange={(e) => setForm(f => ({ ...f, is_primary: e.target.checked }))}
          />
          Primary contact
        </label>
      </div>
      <div className="flex items-center gap-2 pt-1">
        <button
          type="submit"
          disabled={isLoading}
          className="px-3 py-1 rounded bg-primary-500 text-white text-xs font-medium hover:bg-primary-600 disabled:opacity-50"
        >
          {isLoading ? 'Saving...' : initial ? 'Update' : 'Add'}
        </button>
        <button
          type="button"
          onClick={onCancel}
          className="px-3 py-1 rounded border border-gray-300 dark:border-gray-600 text-xs font-medium text-gray-600 dark:text-gray-400 hover:bg-gray-100 dark:hover:bg-gray-800"
        >
          Cancel
        </button>
      </div>
    </form>
  );
}
