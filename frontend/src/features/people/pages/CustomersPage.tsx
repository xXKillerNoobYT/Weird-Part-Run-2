/**
 * CustomersPage — paginated customer list with search, filters, and create modal.
 *
 * Shows customer cards with name, company, type badge, phone, email, job count,
 * and active status. Supports search, customer_type filter, active/inactive toggle.
 * Create modal allows adding new customers with address and contact fields.
 * Row click navigates to CustomerDetailPage.
 */

import { useState, useEffect, useCallback } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  Plus, Search, Users, Phone, Mail, ChevronLeft, ChevronRight,
  Building2, X, Filter, Briefcase,
} from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import { PageSpinner } from '../../../components/ui/Spinner';
import { EmptyState } from '../../../components/ui/EmptyState';
import { Button } from '../../../components/ui/Button';
import { Input } from '../../../components/ui/Input';
import { Modal } from '../../../components/ui/Modal';
import { Badge } from '../../../components/ui/Badge';
import { Card } from '../../../components/ui/Card';
import { useAuthStore } from '../../../stores/auth-store';
import { PERMISSIONS } from '../../../lib/constants';
import { getCustomers, createCustomer } from '../../../api/contacts';
import { toast } from '../../../lib/toast';
import type { CustomerListItem, CustomerCreate, CustomerType } from '../../../lib/types';


// ── Helpers ───────────────────────────────────────────────────────

const CUSTOMER_TYPE_LABELS: Record<CustomerType, string> = {
  residential: 'Residential',
  commercial: 'Commercial',
  government: 'Government',
  other: 'Other',
};

const CUSTOMER_TYPE_BADGE: Record<CustomerType, 'default' | 'primary' | 'success' | 'warning'> = {
  residential: 'default',
  commercial: 'primary',
  government: 'success',
  other: 'warning',
};

const PAGE_SIZES = [25, 50, 100];


// ═════════════════════════════════════════════════════════════════
// MAIN PAGE
// ═════════════════════════════════════════════════════════════════

export function CustomersPage() {
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const { hasPermission } = useAuthStore();
  const canManage = hasPermission(PERMISSIONS.MANAGE_CUSTOMERS);

  // ── State ──────────────────────────────────────────────────────
  const [search, setSearch] = useState('');
  const [debouncedSearch, setDebouncedSearch] = useState('');
  const [isActiveFilter, setIsActiveFilter] = useState<boolean | undefined>(true);
  const [typeFilter, setTypeFilter] = useState<string | undefined>(undefined);
  const [page, setPage] = useState(1);
  const [pageSize, setPageSize] = useState(50);
  const [showFilters, setShowFilters] = useState(false);
  const [showCreate, setShowCreate] = useState(false);

  // Debounce search
  useEffect(() => {
    const timer = setTimeout(() => {
      setDebouncedSearch(search);
      setPage(1);
    }, 300);
    return () => clearTimeout(timer);
  }, [search]);

  // Reset page on filter change
  useEffect(() => { setPage(1); }, [isActiveFilter, typeFilter, pageSize]);

  // ── Queries ────────────────────────────────────────────────────
  const { data, isLoading, error } = useQuery({
    queryKey: ['customers', debouncedSearch, isActiveFilter, typeFilter, page, pageSize],
    queryFn: () => getCustomers({
      search: debouncedSearch || undefined,
      is_active: isActiveFilter,
      customer_type: typeFilter,
      page,
      page_size: pageSize,
    }),
    staleTime: 15_000,
  });

  // ── Create mutation ────────────────────────────────────────────
  const createMutation = useMutation({
    mutationFn: createCustomer,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['customers'] });
      setShowCreate(false);
      toast.success('Customer created');
    },
    onError: (err: unknown) => {
      const msg = (err as { response?: { data?: { detail?: string } } })?.response?.data?.detail
        ?? 'Failed to create customer';
      toast.error(msg);
    },
  });

  const hasActiveFilters = isActiveFilter !== true || typeFilter !== undefined;

  const clearFilters = useCallback(() => {
    setIsActiveFilter(true);
    setTypeFilter(undefined);
  }, []);

  if (isLoading) return <PageSpinner label="Loading customers..." />;

  if (error) {
    return (
      <div className="text-center py-16">
        <p className="text-red-500">Failed to load customers. Please try again.</p>
      </div>
    );
  }

  const customers = data?.items ?? [];
  const totalPages = data?.total_pages ?? 1;
  const total = data?.total ?? 0;

  return (
    <div className="space-y-4">
      {/* Header */}
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div>
          <h1 className="text-xl font-semibold text-gray-900 dark:text-gray-100">
            Customers
          </h1>
          <p className="text-sm text-gray-500 dark:text-gray-400">
            {total} {isActiveFilter === true ? 'active' : isActiveFilter === false ? 'inactive' : 'total'} customers
          </p>
        </div>

        <div className="flex items-center gap-2">
          <Button
            variant="ghost"
            size="sm"
            icon={<Filter size={16} />}
            onClick={() => setShowFilters(!showFilters)}
          >
            <span className="hidden sm:inline">Filters</span>
          </Button>

          {canManage && (
            <Button
              size="sm"
              icon={<Plus size={16} />}
              onClick={() => setShowCreate(true)}
            >
              <span className="hidden sm:inline">Add Customer</span>
            </Button>
          )}
        </div>
      </div>

      {/* Search */}
      <Input
        placeholder="Search by name, company, email, or phone..."
        value={search}
        onChange={(e) => setSearch(e.target.value)}
        icon={<Search size={16} />}
        iconRight={search ? (
          <button onClick={() => setSearch('')} className="p-1 hover:bg-gray-100 dark:hover:bg-gray-700 rounded">
            <X size={14} />
          </button>
        ) : undefined}
      />

      {/* Filter bar */}
      {showFilters && (
        <Card noPadding>
          <div className="p-3 flex items-center flex-wrap gap-3">
            <div className="flex items-center gap-1.5">
              <span className="text-xs text-gray-500 dark:text-gray-400 mr-1">Status:</span>
              {([
                { label: 'Active', value: true },
                { label: 'Inactive', value: false },
                { label: 'All', value: undefined },
              ] as const).map((opt) => (
                <button
                  key={String(opt.value)}
                  onClick={() => setIsActiveFilter(opt.value as boolean | undefined)}
                  className={`px-2.5 py-1 text-xs rounded-full transition-colors ${
                    isActiveFilter === opt.value
                      ? 'bg-primary-100 dark:bg-primary-900/30 text-primary-700 dark:text-primary-300 font-medium'
                      : 'text-gray-600 dark:text-gray-400 hover:bg-gray-100 dark:hover:bg-gray-700'
                  }`}
                >
                  {opt.label}
                </button>
              ))}
            </div>

            <div className="flex items-center gap-1.5">
              <span className="text-xs text-gray-500 dark:text-gray-400 mr-1">Type:</span>
              <select
                value={typeFilter ?? ''}
                onChange={(e) => setTypeFilter(e.target.value || undefined)}
                className="text-xs rounded-md border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 px-2 py-1"
              >
                <option value="">All Types</option>
                {(Object.entries(CUSTOMER_TYPE_LABELS) as [CustomerType, string][]).map(([val, label]) => (
                  <option key={val} value={val}>{label}</option>
                ))}
              </select>
            </div>

            {hasActiveFilters && (
              <button
                onClick={clearFilters}
                className="text-xs text-primary-600 dark:text-primary-400 hover:underline ml-auto"
              >
                Clear filters
              </button>
            )}
          </div>
        </Card>
      )}

      {/* Customer list */}
      {customers.length === 0 ? (
        <EmptyState
          icon={<Users size={48} />}
          title="No customers found"
          description={search ? `No results for "${search}"` : 'No customers match the current filters.'}
          action={canManage ? <Button size="sm" onClick={() => setShowCreate(true)}>Add Customer</Button> : undefined}
        />
      ) : (
        <div className="space-y-2">
          {customers.map((cust) => (
            <CustomerRow
              key={cust.id}
              customer={cust}
              onClick={() => navigate(`/people/customers/${cust.id}`)}
            />
          ))}
        </div>
      )}

      {/* Pagination */}
      {totalPages > 1 && (
        <div className="flex items-center justify-between flex-wrap gap-3 pt-2">
          <div className="flex items-center gap-2 text-sm text-gray-500 dark:text-gray-400">
            <span>Show:</span>
            <select
              value={pageSize}
              onChange={(e) => setPageSize(Number(e.target.value))}
              className="text-xs rounded border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 px-1 py-0.5"
            >
              {PAGE_SIZES.map((s) => <option key={s} value={s}>{s}</option>)}
            </select>
          </div>
          <div className="flex items-center gap-1">
            <Button variant="ghost" size="sm" disabled={page <= 1} onClick={() => setPage(page - 1)} icon={<ChevronLeft size={16} />} />
            <span className="text-sm text-gray-600 dark:text-gray-400 px-2">Page {page} of {totalPages}</span>
            <Button variant="ghost" size="sm" disabled={page >= totalPages} onClick={() => setPage(page + 1)} icon={<ChevronRight size={16} />} />
          </div>
        </div>
      )}

      {/* Create modal */}
      {showCreate && (
        <CreateCustomerModal
          isLoading={createMutation.isPending}
          error={createMutation.error?.message ?? null}
          onSubmit={(data) => createMutation.mutate(data)}
          onClose={() => setShowCreate(false)}
        />
      )}
    </div>
  );
}


// ═════════════════════════════════════════════════════════════════
// Customer Row
// ═════════════════════════════════════════════════════════════════

function CustomerRow({ customer, onClick }: { customer: CustomerListItem; onClick: () => void }) {
  return (
    <Card noPadding>
      <button
        onClick={onClick}
        className="w-full flex items-center gap-3 p-3 text-left hover:bg-gray-50 dark:hover:bg-gray-700/50 transition-colors rounded-lg"
      >
        {/* Icon */}
        <div className="flex-shrink-0 w-10 h-10 rounded-full bg-blue-100 dark:bg-blue-900/30 flex items-center justify-center text-blue-700 dark:text-blue-300">
          {customer.company_name ? (
            <Building2 size={18} />
          ) : (
            <span className="font-bold text-sm">{customer.first_name.charAt(0)}</span>
          )}
        </div>

        {/* Name and details */}
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 flex-wrap">
            <span className="font-medium text-gray-900 dark:text-gray-100 truncate">
              {customer.display_name}
            </span>
            <Badge variant={CUSTOMER_TYPE_BADGE[customer.customer_type]}>
              {CUSTOMER_TYPE_LABELS[customer.customer_type]}
            </Badge>
            {!customer.is_active && <Badge variant="danger">Inactive</Badge>}
          </div>
          {customer.company_name && customer.first_name && (
            <p className="text-xs text-gray-500 dark:text-gray-400 truncate">
              {customer.first_name} {customer.last_name}
            </p>
          )}
        </div>

        {/* Contact info — hidden on mobile */}
        <div className="hidden md:flex items-center gap-4 text-sm text-gray-500 dark:text-gray-400 flex-shrink-0">
          {customer.phone && (
            <span className="flex items-center gap-1">
              <Phone size={14} />
              <span className="truncate max-w-[120px]">{customer.phone}</span>
            </span>
          )}
          {customer.email && (
            <span className="flex items-center gap-1">
              <Mail size={14} />
              <span className="truncate max-w-[160px]">{customer.email}</span>
            </span>
          )}
        </div>

        {/* Job count */}
        <div className="flex items-center gap-1 text-sm text-gray-500 dark:text-gray-400 flex-shrink-0">
          <Briefcase size={14} />
          <span>{customer.job_count}</span>
        </div>
      </button>
    </Card>
  );
}


// ═════════════════════════════════════════════════════════════════
// Create Customer Modal
// ═════════════════════════════════════════════════════════════════

function CreateCustomerModal({
  isLoading,
  error,
  onSubmit,
  onClose,
}: {
  isLoading: boolean;
  error: string | null;
  onSubmit: (data: CustomerCreate) => void;
  onClose: () => void;
}) {
  const [firstName, setFirstName] = useState('');
  const [lastName, setLastName] = useState('');
  const [companyName, setCompanyName] = useState('');
  const [phone, setPhone] = useState('');
  const [email, setEmail] = useState('');
  const [customerType, setCustomerType] = useState<CustomerType>('commercial');
  const [addressLine1, setAddressLine1] = useState('');
  const [city, setCity] = useState('');
  const [state, setState] = useState('');
  const [zip, setZip] = useState('');
  const [notes, setNotes] = useState('');

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!firstName.trim() || !lastName.trim()) return;
    onSubmit({
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

  return (
    <Modal title="New Customer" onClose={onClose} size="lg">
      <form onSubmit={handleSubmit} className="space-y-4">
        {error && (
          <div className="p-3 rounded-lg bg-red-50 dark:bg-red-900/20 text-red-600 dark:text-red-400 text-sm">
            {error}
          </div>
        )}

        {/* Name row */}
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
          <Input
            label="First Name *"
            value={firstName}
            onChange={(e) => setFirstName(e.target.value)}
            required
            autoFocus
          />
          <Input
            label="Last Name *"
            value={lastName}
            onChange={(e) => setLastName(e.target.value)}
            required
          />
        </div>

        <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
          <Input
            label="Company Name"
            value={companyName}
            onChange={(e) => setCompanyName(e.target.value)}
            placeholder="Leave blank for residential"
          />
          <div>
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
              Customer Type
            </label>
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

        {/* Contact */}
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
          <Input
            label="Phone"
            type="tel"
            value={phone}
            onChange={(e) => setPhone(e.target.value)}
          />
          <Input
            label="Email"
            type="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
          />
        </div>

        {/* Address */}
        <Input
          label="Address"
          value={addressLine1}
          onChange={(e) => setAddressLine1(e.target.value)}
          placeholder="Street address"
        />
        <div className="grid grid-cols-2 sm:grid-cols-3 gap-3">
          <Input
            label="City"
            value={city}
            onChange={(e) => setCity(e.target.value)}
          />
          <Input
            label="State"
            value={state}
            onChange={(e) => setState(e.target.value)}
          />
          <Input
            label="ZIP"
            value={zip}
            onChange={(e) => setZip(e.target.value)}
          />
        </div>

        {/* Notes */}
        <div>
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
            Notes
          </label>
          <textarea
            value={notes}
            onChange={(e) => setNotes(e.target.value)}
            rows={2}
            className="w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 px-3 py-2 text-sm resize-none"
          />
        </div>

        <div className="flex justify-end gap-2 pt-2">
          <Button variant="ghost" onClick={onClose}>Cancel</Button>
          <Button type="submit" isLoading={isLoading} disabled={!firstName.trim() || !lastName.trim()}>
            Create Customer
          </Button>
        </div>
      </form>
    </Modal>
  );
}
