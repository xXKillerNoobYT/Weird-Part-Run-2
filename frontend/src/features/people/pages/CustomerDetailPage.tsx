/**
 * CustomerDetailPage — full customer profile with sub-tabs for
 * overview (edit form), contacts (entity_contacts CRUD), and linked jobs.
 *
 * Follows the EmployeeDetailPage pattern: back button, header with status badge,
 * sub-tab bar, and tab content panels.
 */

import { useState } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  ArrowLeft, Mail, Phone, Building2, Edit2, UserCheck, UserX,
  Plus, Trash2, X, Users, Briefcase, MapPin, Save,
} from 'lucide-react';
import { PageSpinner } from '../../../components/ui/Spinner';
import { Button } from '../../../components/ui/Button';
import { Badge } from '../../../components/ui/Badge';
import { Card, CardHeader } from '../../../components/ui/Card';
import { Modal } from '../../../components/ui/Modal';
import { Input } from '../../../components/ui/Input';
import { EmptyState } from '../../../components/ui/EmptyState';
import { useAuthStore } from '../../../stores/auth-store';
import { PERMISSIONS } from '../../../lib/constants';
import {
  getCustomer, updateCustomer, toggleCustomerActive,
  getCustomerContacts, addCustomerContact,
  updateEntityContact, deleteEntityContact,
} from '../../../api/contacts';
import { getJobCustomers } from '../../../api/contacts';
import type {
  CustomerDetail, CustomerUpdate, CustomerType,
  EntityContactResponse, EntityContactCreate, EntityContactUpdate,
  JobCustomerResponse,
} from '../../../lib/types';


// ── Sub-tab IDs ───────────────────────────────────────────────────

const TABS = [
  { id: 'overview', label: 'Overview', icon: Building2 },
  { id: 'contacts', label: 'Contacts', icon: Users },
  { id: 'jobs', label: 'Jobs', icon: Briefcase },
] as const;

type TabId = typeof TABS[number]['id'];

const CUSTOMER_TYPE_LABELS: Record<CustomerType, string> = {
  residential: 'Residential',
  commercial: 'Commercial',
  government: 'Government',
  other: 'Other',
};


// ═════════════════════════════════════════════════════════════════
// MAIN PAGE
// ═════════════════════════════════════════════════════════════════

export function CustomerDetailPage() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const { hasPermission } = useAuthStore();
  const canManage = hasPermission(PERMISSIONS.MANAGE_CUSTOMERS);

  const [activeTab, setActiveTab] = useState<TabId>('overview');

  const customerId = Number(id);

  const { data: customer, isLoading, error } = useQuery({
    queryKey: ['customer-detail', customerId],
    queryFn: () => getCustomer(customerId),
    enabled: !!id && !isNaN(customerId),
    staleTime: 10_000,
  });

  const toggleMutation = useMutation({
    mutationFn: (isActive: boolean) => toggleCustomerActive(customerId, isActive),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['customer-detail', customerId] }),
  });

  if (isLoading) return <PageSpinner label="Loading customer..." />;
  if (error || !customer) {
    return (
      <div className="text-center py-16">
        <p className="text-red-500">Customer not found.</p>
        <Button variant="ghost" className="mt-4" onClick={() => navigate('/people/customers')}>
          Back to Customers
        </Button>
      </div>
    );
  }

  return (
    <div className="space-y-4">
      {/* ── Header ─────────────────────────────────────────── */}
      <div className="flex items-start gap-3 flex-wrap">
        <button
          onClick={() => navigate('/people/customers')}
          className="p-2 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors mt-0.5"
        >
          <ArrowLeft size={20} className="text-gray-500 dark:text-gray-400" />
        </button>

        {/* Avatar */}
        <div className="flex-shrink-0 w-12 h-12 rounded-full bg-blue-100 dark:bg-blue-900/30 flex items-center justify-center text-blue-700 dark:text-blue-300 font-bold text-lg">
          {customer.company_name ? (
            <Building2 size={20} />
          ) : (
            customer.first_name.charAt(0).toUpperCase()
          )}
        </div>

        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 flex-wrap">
            <h1 className="text-xl font-semibold text-gray-900 dark:text-gray-100">
              {customer.display_name}
            </h1>
            {customer.is_active ? (
              <Badge variant="success">Active</Badge>
            ) : (
              <Badge variant="danger">Inactive</Badge>
            )}
            <Badge variant="primary">
              {CUSTOMER_TYPE_LABELS[customer.customer_type]}
            </Badge>
          </div>
          {customer.company_name && (
            <p className="text-sm text-gray-500 dark:text-gray-400">
              {customer.first_name} {customer.last_name}
            </p>
          )}
        </div>

        {/* Actions */}
        {canManage && (
          <div className="flex items-center gap-2">
            <Button
              variant={customer.is_active ? 'ghost' : 'primary'}
              size="sm"
              icon={customer.is_active ? <UserX size={16} /> : <UserCheck size={16} />}
              isLoading={toggleMutation.isPending}
              onClick={() => toggleMutation.mutate(!customer.is_active)}
            >
              <span className="hidden sm:inline">{customer.is_active ? 'Deactivate' : 'Activate'}</span>
            </Button>
          </div>
        )}
      </div>

      {/* ── Sub-tab bar ────────────────────────────────────── */}
      <div className="overflow-x-auto -mx-4 px-4 sm:mx-0 sm:px-0">
        <div className="flex gap-1 border-b border-gray-200 dark:border-gray-700 whitespace-nowrap">
          {TABS.map((tab) => {
            const Icon = tab.icon;
            const isActive = activeTab === tab.id;
            return (
              <button
                key={tab.id}
                onClick={() => setActiveTab(tab.id)}
                className={`flex items-center gap-1.5 px-3 py-2.5 text-sm font-medium border-b-2 transition-colors ${
                  isActive
                    ? 'border-primary-500 text-primary-600 dark:text-primary-400'
                    : 'border-transparent text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-300'
                }`}
              >
                <Icon size={14} />
                <span className="hidden sm:inline">{tab.label}</span>
              </button>
            );
          })}
        </div>
      </div>

      {/* ── Tab Content ────────────────────────────────────── */}
      {activeTab === 'overview' && <OverviewTab customer={customer} canManage={canManage} />}
      {activeTab === 'contacts' && <ContactsTab customerId={customerId} canManage={canManage} />}
      {activeTab === 'jobs' && <JobsTab customerId={customerId} />}
    </div>
  );
}


// ═════════════════════════════════════════════════════════════════
// Overview Tab — Edit form
// ═════════════════════════════════════════════════════════════════

function OverviewTab({ customer, canManage }: { customer: CustomerDetail; canManage: boolean }) {
  const queryClient = useQueryClient();
  const [editing, setEditing] = useState(false);

  // Form state
  const [firstName, setFirstName] = useState(customer.first_name);
  const [lastName, setLastName] = useState(customer.last_name);
  const [companyName, setCompanyName] = useState(customer.company_name ?? '');
  const [phone, setPhone] = useState(customer.phone ?? '');
  const [email, setEmail] = useState(customer.email ?? '');
  const [customerType, setCustomerType] = useState<CustomerType>(customer.customer_type);
  const [addressLine1, setAddressLine1] = useState(customer.address_line1 ?? '');
  const [city, setCity] = useState(customer.city ?? '');
  const [state, setState] = useState(customer.state ?? '');
  const [zip, setZip] = useState(customer.zip ?? '');
  const [notes, setNotes] = useState(customer.notes ?? '');

  const saveMutation = useMutation({
    mutationFn: (data: CustomerUpdate) => updateCustomer(customer.id, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['customer-detail', customer.id] });
      setEditing(false);
    },
  });

  const handleSave = () => {
    saveMutation.mutate({
      first_name: firstName.trim(),
      last_name: lastName.trim(),
      company_name: companyName.trim() || null,
      phone: phone.trim() || null,
      email: email.trim() || null,
      customer_type: customerType,
      address_line1: addressLine1.trim() || null,
      city: city.trim() || null,
      state: state.trim() || null,
      zip: zip.trim() || null,
      notes: notes.trim() || null,
    });
  };

  const handleCancel = () => {
    setFirstName(customer.first_name);
    setLastName(customer.last_name);
    setCompanyName(customer.company_name ?? '');
    setPhone(customer.phone ?? '');
    setEmail(customer.email ?? '');
    setCustomerType(customer.customer_type);
    setAddressLine1(customer.address_line1 ?? '');
    setCity(customer.city ?? '');
    setState(customer.state ?? '');
    setZip(customer.zip ?? '');
    setNotes(customer.notes ?? '');
    setEditing(false);
  };

  return (
    <Card>
      <div className="flex items-center justify-between mb-4">
        <CardHeader title="Customer Information" />
        {canManage && !editing && (
          <Button variant="ghost" size="sm" icon={<Edit2 size={14} />} onClick={() => setEditing(true)}>
            <span className="hidden sm:inline">Edit</span>
          </Button>
        )}
        {editing && (
          <div className="flex gap-2">
            <Button variant="ghost" size="sm" onClick={handleCancel}>Cancel</Button>
            <Button size="sm" icon={<Save size={14} />} isLoading={saveMutation.isPending} onClick={handleSave}>
              Save
            </Button>
          </div>
        )}
      </div>

      {editing ? (
        <div className="space-y-4">
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <Input label="First Name" value={firstName} onChange={(e) => setFirstName(e.target.value)} />
            <Input label="Last Name" value={lastName} onChange={(e) => setLastName(e.target.value)} />
          </div>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <Input label="Company Name" value={companyName} onChange={(e) => setCompanyName(e.target.value)} />
            <div>
              <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">Type</label>
              <select
                value={customerType}
                onChange={(e) => setCustomerType(e.target.value as CustomerType)}
                className="w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 px-3 py-2 text-sm"
              >
                {(Object.entries(CUSTOMER_TYPE_LABELS) as [CustomerType, string][]).map(([val, label]) => (
                  <option key={val} value={val}>{label}</option>
                ))}
              </select>
            </div>
          </div>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <Input label="Phone" value={phone} onChange={(e) => setPhone(e.target.value)} />
            <Input label="Email" value={email} onChange={(e) => setEmail(e.target.value)} />
          </div>
          <Input label="Address" value={addressLine1} onChange={(e) => setAddressLine1(e.target.value)} />
          <div className="grid grid-cols-2 sm:grid-cols-3 gap-3">
            <Input label="City" value={city} onChange={(e) => setCity(e.target.value)} />
            <Input label="State" value={state} onChange={(e) => setState(e.target.value)} />
            <Input label="ZIP" value={zip} onChange={(e) => setZip(e.target.value)} />
          </div>
          <div>
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">Notes</label>
            <textarea
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
              rows={3}
              className="w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 px-3 py-2 text-sm resize-none"
            />
          </div>
        </div>
      ) : (
        <div className="space-y-3">
          {/* Contact details */}
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            {customer.phone && (
              <div className="flex items-center gap-2">
                <Phone size={16} className="text-gray-400 dark:text-gray-500 flex-shrink-0" />
                <a href={`tel:${customer.phone}`} className="text-sm text-primary-600 dark:text-primary-400 hover:underline">
                  {customer.phone}
                </a>
              </div>
            )}
            {customer.email && (
              <div className="flex items-center gap-2">
                <Mail size={16} className="text-gray-400 dark:text-gray-500 flex-shrink-0" />
                <a href={`mailto:${customer.email}`} className="text-sm text-primary-600 dark:text-primary-400 hover:underline truncate">
                  {customer.email}
                </a>
              </div>
            )}
          </div>

          {/* Address */}
          {customer.address_line1 && (
            <div className="flex items-start gap-2">
              <MapPin size={16} className="text-gray-400 dark:text-gray-500 flex-shrink-0 mt-0.5" />
              <div className="text-sm text-gray-700 dark:text-gray-300">
                <p>{customer.address_line1}</p>
                {(customer.city || customer.state || customer.zip) && (
                  <p>{[customer.city, customer.state, customer.zip].filter(Boolean).join(', ')}</p>
                )}
              </div>
            </div>
          )}

          {/* Notes */}
          {customer.notes && (
            <div className="mt-4 p-3 rounded-lg bg-gray-50 dark:bg-gray-800/50">
              <p className="text-xs font-medium text-gray-500 dark:text-gray-400 mb-1">Notes</p>
              <p className="text-sm text-gray-700 dark:text-gray-300 whitespace-pre-wrap">{customer.notes}</p>
            </div>
          )}

          {/* Metadata */}
          <div className="flex items-center gap-4 text-xs text-gray-400 dark:text-gray-500 pt-2 border-t border-gray-100 dark:border-gray-700/50">
            {customer.created_at && <span>Created: {new Date(customer.created_at).toLocaleDateString()}</span>}
            {customer.updated_at && <span>Updated: {new Date(customer.updated_at).toLocaleDateString()}</span>}
          </div>
        </div>
      )}
    </Card>
  );
}


// ═════════════════════════════════════════════════════════════════
// Contacts Tab — Entity contacts CRUD
// ═════════════════════════════════════════════════════════════════

function ContactsTab({ customerId, canManage }: { customerId: number; canManage: boolean }) {
  const queryClient = useQueryClient();
  const [showAdd, setShowAdd] = useState(false);
  const [editingContact, setEditingContact] = useState<EntityContactResponse | null>(null);

  const { data: contacts, isLoading } = useQuery({
    queryKey: ['customer-contacts', customerId],
    queryFn: () => getCustomerContacts(customerId),
    staleTime: 10_000,
  });

  const addMutation = useMutation({
    mutationFn: (data: EntityContactCreate) => addCustomerContact(customerId, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['customer-contacts', customerId] });
      queryClient.invalidateQueries({ queryKey: ['customer-detail', customerId] });
      setShowAdd(false);
    },
  });

  const updateMutation = useMutation({
    mutationFn: ({ id, data }: { id: number; data: EntityContactUpdate }) => updateEntityContact(id, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['customer-contacts', customerId] });
      setEditingContact(null);
    },
  });

  const deleteMutation = useMutation({
    mutationFn: deleteEntityContact,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['customer-contacts', customerId] });
      queryClient.invalidateQueries({ queryKey: ['customer-detail', customerId] });
    },
  });

  if (isLoading) return <PageSpinner label="Loading contacts..." />;

  return (
    <div className="space-y-3">
      {canManage && (
        <div className="flex justify-end">
          <Button size="sm" icon={<Plus size={16} />} onClick={() => setShowAdd(true)}>
            <span className="hidden sm:inline">Add Contact</span>
          </Button>
        </div>
      )}

      {(!contacts || contacts.length === 0) ? (
        <EmptyState
          icon={<Users size={48} />}
          title="No contacts yet"
          description="Add contact persons for this customer."
          action={canManage ? <Button size="sm" onClick={() => setShowAdd(true)}>Add Contact</Button> : undefined}
        />
      ) : (
        contacts.map((c) => (
          <Card key={c.id} noPadding>
            <div className="p-3">
              <div className="flex items-center justify-between flex-wrap gap-2">
                <div>
                  <div className="flex items-center gap-2">
                    <span className="font-medium text-gray-900 dark:text-gray-100">
                      {c.first_name} {c.last_name}
                    </span>
                    {c.is_primary && <Badge variant="primary">Primary</Badge>}
                  </div>
                  <p className="text-sm text-gray-500 dark:text-gray-400">{c.role}</p>
                </div>
                {canManage && (
                  <div className="flex items-center gap-1">
                    <Button variant="ghost" size="sm" icon={<Edit2 size={14} />} onClick={() => setEditingContact(c)} />
                    <Button
                      variant="ghost"
                      size="sm"
                      icon={<Trash2 size={14} className="text-red-500" />}
                      onClick={() => { if (confirm('Delete this contact?')) deleteMutation.mutate(c.id); }}
                    />
                  </div>
                )}
              </div>
              <div className="flex items-center gap-4 mt-2 text-sm text-gray-600 dark:text-gray-400">
                {c.phone && (
                  <a href={`tel:${c.phone}`} className="flex items-center gap-1 hover:text-primary-600 dark:hover:text-primary-400">
                    <Phone size={14} /> {c.phone}
                  </a>
                )}
                {c.email && (
                  <a href={`mailto:${c.email}`} className="flex items-center gap-1 hover:text-primary-600 dark:hover:text-primary-400 truncate">
                    <Mail size={14} /> <span className="truncate">{c.email}</span>
                  </a>
                )}
              </div>
              {c.notes && (
                <p className="text-xs text-gray-500 dark:text-gray-400 mt-1">{c.notes}</p>
              )}
            </div>
          </Card>
        ))
      )}

      {/* Add contact modal */}
      {showAdd && (
        <ContactFormModal
          title="Add Contact"
          isLoading={addMutation.isPending}
          error={addMutation.error?.message ?? null}
          onSubmit={(data) => addMutation.mutate(data)}
          onClose={() => setShowAdd(false)}
        />
      )}

      {/* Edit contact modal */}
      {editingContact && (
        <ContactFormModal
          title="Edit Contact"
          initial={editingContact}
          isLoading={updateMutation.isPending}
          error={updateMutation.error?.message ?? null}
          onSubmit={(data) => updateMutation.mutate({ id: editingContact.id, data })}
          onClose={() => setEditingContact(null)}
        />
      )}
    </div>
  );
}


// ═════════════════════════════════════════════════════════════════
// Jobs Tab — Linked jobs
// ═════════════════════════════════════════════════════════════════

function JobsTab({ customerId }: { customerId: number }) {
  const navigate = useNavigate();

  const { data: links, isLoading } = useQuery({
    queryKey: ['customer-jobs', customerId],
    queryFn: () => getJobCustomers(customerId),
    staleTime: 15_000,
  });

  if (isLoading) return <PageSpinner label="Loading jobs..." />;

  if (!links || links.length === 0) {
    return (
      <EmptyState
        icon={<Briefcase size={48} />}
        title="No linked jobs"
        description="This customer hasn't been linked to any jobs yet. Link customers from the Job Detail page."
      />
    );
  }

  return (
    <div className="space-y-2">
      {links.map((link) => (
        <Card key={link.id} noPadding>
          <button
            onClick={() => navigate(`/jobs/active/${link.job_id}`)}
            className="w-full flex items-center gap-3 p-3 text-left hover:bg-gray-50 dark:hover:bg-gray-700/50 transition-colors rounded-lg"
          >
            <Briefcase size={16} className="text-gray-400 dark:text-gray-500 flex-shrink-0" />
            <div className="flex-1 min-w-0">
              <span className="font-medium text-gray-900 dark:text-gray-100">{link.customer_name}</span>
              <div className="flex items-center gap-2 mt-0.5">
                <Badge variant="default">{link.contact_role}</Badge>
                {link.is_primary && <Badge variant="primary">Primary</Badge>}
              </div>
            </div>
          </button>
        </Card>
      ))}
    </div>
  );
}


// ═════════════════════════════════════════════════════════════════
// Contact Form Modal (shared between Add/Edit)
// ═════════════════════════════════════════════════════════════════

function ContactFormModal({
  title,
  initial,
  isLoading,
  error,
  onSubmit,
  onClose,
}: {
  title: string;
  initial?: EntityContactResponse;
  isLoading: boolean;
  error: string | null;
  onSubmit: (data: EntityContactCreate | EntityContactUpdate) => void;
  onClose: () => void;
}) {
  const [firstName, setFirstName] = useState(initial?.first_name ?? '');
  const [lastName, setLastName] = useState(initial?.last_name ?? '');
  const [role, setRole] = useState(initial?.role ?? '');
  const [phone, setPhone] = useState(initial?.phone ?? '');
  const [email, setEmail] = useState(initial?.email ?? '');
  const [isPrimary, setIsPrimary] = useState(initial?.is_primary ?? false);
  const [notes, setNotes] = useState(initial?.notes ?? '');

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!firstName.trim() || !lastName.trim() || !phone.trim() || !role.trim()) return;
    onSubmit({
      first_name: firstName.trim(),
      last_name: lastName.trim(),
      role: role.trim(),
      phone: phone.trim(),
      email: email.trim() || null,
      is_primary: isPrimary,
      notes: notes.trim() || null,
    });
  };

  return (
    <Modal title={title} onClose={onClose}>
      <form onSubmit={handleSubmit} className="space-y-4">
        {error && (
          <div className="p-3 rounded-lg bg-red-50 dark:bg-red-900/20 text-red-600 dark:text-red-400 text-sm">
            {error}
          </div>
        )}

        <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
          <Input label="First Name *" value={firstName} onChange={(e) => setFirstName(e.target.value)} required autoFocus />
          <Input label="Last Name *" value={lastName} onChange={(e) => setLastName(e.target.value)} required />
        </div>

        <Input
          label="Role *"
          value={role}
          onChange={(e) => setRole(e.target.value)}
          placeholder="e.g. Owner, Site Contact, Foreman"
          required
        />

        <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
          <Input label="Phone *" type="tel" value={phone} onChange={(e) => setPhone(e.target.value)} required />
          <Input label="Email" type="email" value={email} onChange={(e) => setEmail(e.target.value)} />
        </div>

        <div className="flex items-center gap-2">
          <input
            type="checkbox"
            id="isPrimary"
            checked={isPrimary}
            onChange={(e) => setIsPrimary(e.target.checked)}
            className="rounded border-gray-300 dark:border-gray-600"
          />
          <label htmlFor="isPrimary" className="text-sm text-gray-700 dark:text-gray-300">Primary contact</label>
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">Notes</label>
          <textarea
            value={notes}
            onChange={(e) => setNotes(e.target.value)}
            rows={2}
            className="w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 px-3 py-2 text-sm resize-none"
          />
        </div>

        <div className="flex justify-end gap-2 pt-2">
          <Button variant="ghost" onClick={onClose}>Cancel</Button>
          <Button
            type="submit"
            isLoading={isLoading}
            disabled={!firstName.trim() || !lastName.trim() || !phone.trim() || !role.trim()}
          >
            {initial ? 'Save Changes' : 'Add Contact'}
          </Button>
        </div>
      </form>
    </Modal>
  );
}
