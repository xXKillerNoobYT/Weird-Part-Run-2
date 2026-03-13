/**
 * ContractorsPage — paginated general contractor list with search, filters, and create modal.
 *
 * Shows GC rows with company name, gc_code, trade type badge, phone, email, job count,
 * and active status. Supports search, trade_type filter, active/inactive toggle.
 * Create modal includes gc_code (short code for PO naming), license number, and trade type.
 * Row click navigates to ContractorDetailPage.
 */

import { useState, useEffect, useCallback } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  Plus, Search, ChevronLeft, ChevronRight,
  HardHat, X, Filter, Briefcase, Phone, Mail, Tag, Upload,
} from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import { PageSpinner } from '../../../components/ui/Spinner';
import { EmptyState } from '../../../components/ui/EmptyState';
import { Button } from '../../../components/ui/Button';
import { Input } from '../../../components/ui/Input';
import { Modal } from '../../../components/ui/Modal';
import { Badge } from '../../../components/ui/Badge';
import { Card } from '../../../components/ui/Card';
import { CSVImportModal } from '../../../components/ui/CSVImportModal';
import { useAuthStore } from '../../../stores/auth-store';
import { PERMISSIONS } from '../../../lib/constants';
import { getGCs, createGC, importContractorsCSV } from '../../../api/contacts';
import { toast } from '../../../lib/toast';
import type { GCListItem, GCCreate, GCTradeType } from '../../../lib/types';


// ── Helpers ───────────────────────────────────────────────────────

const TRADE_TYPE_LABELS: Record<GCTradeType, string> = {
  general: 'General',
  electrical: 'Electrical',
  plumbing: 'Plumbing',
  hvac: 'HVAC',
  mechanical: 'Mechanical',
  fire_protection: 'Fire Protection',
  low_voltage: 'Low Voltage',
  other: 'Other',
};

const TRADE_TYPE_BADGE: Record<GCTradeType, 'default' | 'primary' | 'success' | 'warning' | 'info' | 'danger'> = {
  general: 'default',
  electrical: 'primary',
  plumbing: 'info',
  hvac: 'warning',
  mechanical: 'success',
  fire_protection: 'danger',
  low_voltage: 'info',
  other: 'default',
};

const PAGE_SIZES = [25, 50, 100];


// ═════════════════════════════════════════════════════════════════
// MAIN PAGE
// ═════════════════════════════════════════════════════════════════

export function ContractorsPage() {
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const { hasPermission } = useAuthStore();
  const canManage = hasPermission(PERMISSIONS.MANAGE_CONTRACTORS);

  // ── State ──────────────────────────────────────────────────────
  const [search, setSearch] = useState('');
  const [debouncedSearch, setDebouncedSearch] = useState('');
  const [isActiveFilter, setIsActiveFilter] = useState<boolean | undefined>(true);
  const [tradeFilter, setTradeFilter] = useState<string | undefined>(undefined);
  const [page, setPage] = useState(1);
  const [pageSize, setPageSize] = useState(50);
  const [showFilters, setShowFilters] = useState(false);
  const [showCreate, setShowCreate] = useState(false);
  const [showImport, setShowImport] = useState(false);

  // Debounce search
  useEffect(() => {
    const timer = setTimeout(() => {
      setDebouncedSearch(search);
      setPage(1);
    }, 300);
    return () => clearTimeout(timer);
  }, [search]);

  // Reset page on filter change
  useEffect(() => { setPage(1); }, [isActiveFilter, tradeFilter, pageSize]);

  // ── Queries ────────────────────────────────────────────────────
  const { data, isLoading, error } = useQuery({
    queryKey: ['general-contractors', debouncedSearch, isActiveFilter, tradeFilter, page, pageSize],
    queryFn: () => getGCs({
      search: debouncedSearch || undefined,
      is_active: isActiveFilter,
      trade_type: tradeFilter,
      page,
      page_size: pageSize,
    }),
    staleTime: 15_000,
  });

  // ── Create mutation ────────────────────────────────────────────
  const createMutation = useMutation({
    mutationFn: createGC,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['general-contractors'] });
      setShowCreate(false);
      toast.success('Contractor created');
    },
    onError: (err: unknown) => {
      const msg = (err as { response?: { data?: { detail?: string } } })?.response?.data?.detail
        ?? 'Failed to create contractor';
      toast.error(msg);
    },
  });

  const hasActiveFilters = isActiveFilter !== true || tradeFilter !== undefined;

  const clearFilters = useCallback(() => {
    setIsActiveFilter(true);
    setTradeFilter(undefined);
  }, []);

  if (isLoading) return <PageSpinner label="Loading contractors..." />;

  if (error) {
    return (
      <div className="text-center py-16">
        <p className="text-red-500">Failed to load contractors. Please try again.</p>
      </div>
    );
  }

  const gcs = data?.items ?? [];
  const totalPages = data?.total_pages ?? 1;
  const total = data?.total ?? 0;

  return (
    <div className="space-y-4">
      {/* Header */}
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div>
          <h1 className="text-xl font-semibold text-gray-900 dark:text-gray-100">
            General Contractors
          </h1>
          <p className="text-sm text-gray-500 dark:text-gray-400">
            {total} {isActiveFilter === true ? 'active' : isActiveFilter === false ? 'inactive' : 'total'} contractors
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
              variant="ghost"
              size="sm"
              icon={<Upload size={16} />}
              onClick={() => setShowImport(true)}
            >
              <span className="hidden sm:inline">Import</span>
            </Button>
          )}

          {canManage && (
            <Button
              size="sm"
              icon={<Plus size={16} />}
              onClick={() => setShowCreate(true)}
            >
              <span className="hidden sm:inline">Add Contractor</span>
            </Button>
          )}
        </div>
      </div>

      {/* Search */}
      <Input
        placeholder="Search by company name, code, or contact info..."
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
                  className={`px-2.5 py-1 text-xs rounded-full transition-colors ${isActiveFilter === opt.value
                      ? 'bg-primary-100 dark:bg-primary-900/30 text-primary-700 dark:text-primary-300 font-medium'
                      : 'text-gray-600 dark:text-gray-400 hover:bg-gray-100 dark:hover:bg-gray-700'
                    }`}
                >
                  {opt.label}
                </button>
              ))}
            </div>

            <div className="flex items-center gap-1.5">
              <span className="text-xs text-gray-500 dark:text-gray-400 mr-1">Trade:</span>
              <select
                value={tradeFilter ?? ''}
                onChange={(e) => setTradeFilter(e.target.value || undefined)}
                className="text-xs rounded-md border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 px-2 py-1"
              >
                <option value="">All Trades</option>
                {(Object.entries(TRADE_TYPE_LABELS) as [GCTradeType, string][]).map(([val, label]) => (
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

      {/* GC list */}
      {gcs.length === 0 ? (
        <EmptyState
          icon={<HardHat size={48} />}
          title="No contractors found"
          description={search ? `No results for "${search}"` : 'No contractors match the current filters.'}
          action={canManage ? <Button size="sm" onClick={() => setShowCreate(true)}>Add Contractor</Button> : undefined}
        />
      ) : (
        <div className="space-y-2">
          {gcs.map((gc) => (
            <GCRow
              key={gc.id}
              gc={gc}
              onClick={() => navigate(`/people/contractors/${gc.id}`)}
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
        <CreateGCModal
          isLoading={createMutation.isPending}
          error={(createMutation.error as Error | null)?.message ?? null}
          onSubmit={(data) => createMutation.mutate(data)}
          onClose={() => setShowCreate(false)}
        />
      )}

      {/* CSV Import modal */}
      <CSVImportModal
        isOpen={showImport}
        onClose={() => setShowImport(false)}
        title="Import Contractors"
        description="Upload a CSV file to bulk-create general contractors. Existing contractors (matched by name) are skipped."
        expectedColumns="name, code, contact_name, email, phone, specialty, license_number, notes"
        importFn={importContractorsCSV}
        onSuccess={() => queryClient.invalidateQueries({ queryKey: ['general-contractors'] })}
      />
    </div>
  );
}


// ═════════════════════════════════════════════════════════════════
// GC Row
// ═════════════════════════════════════════════════════════════════

function GCRow({ gc, onClick }: { gc: GCListItem; onClick: () => void }) {
  return (
    <Card noPadding>
      <button
        onClick={onClick}
        className="w-full flex items-center gap-3 p-3 text-left hover:bg-gray-50 dark:hover:bg-gray-700/50 transition-colors rounded-lg"
      >
        {/* Icon */}
        <div className="flex-shrink-0 w-10 h-10 rounded-full bg-amber-100 dark:bg-amber-900/30 flex items-center justify-center text-amber-700 dark:text-amber-300">
          <HardHat size={18} />
        </div>

        {/* Name and details */}
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 flex-wrap">
            <span className="font-medium text-gray-900 dark:text-gray-100 truncate">
              {gc.company_name}
            </span>
            <Badge variant={TRADE_TYPE_BADGE[gc.trade_type]}>
              {TRADE_TYPE_LABELS[gc.trade_type]}
            </Badge>
            {!gc.is_active && <Badge variant="danger">Inactive</Badge>}
          </div>
          <div className="flex items-center gap-2 mt-0.5">
            <span className="flex items-center gap-1 text-xs text-gray-500 dark:text-gray-400">
              <Tag size={12} />
              {gc.gc_code}
            </span>
          </div>
        </div>

        {/* Contact info — hidden on mobile */}
        <div className="hidden md:flex items-center gap-4 text-sm text-gray-500 dark:text-gray-400 flex-shrink-0">
          {gc.phone && (
            <span className="flex items-center gap-1">
              <Phone size={14} />
              <span className="truncate max-w-[120px]">{gc.phone}</span>
            </span>
          )}
          {gc.email && (
            <span className="flex items-center gap-1">
              <Mail size={14} />
              <span className="truncate max-w-[160px]">{gc.email}</span>
            </span>
          )}
        </div>

        {/* Job count */}
        <div className="flex items-center gap-1 text-sm text-gray-500 dark:text-gray-400 flex-shrink-0">
          <Briefcase size={14} />
          <span>{gc.job_count}</span>
        </div>
      </button>
    </Card>
  );
}


// ═════════════════════════════════════════════════════════════════
// Create GC Modal
// ═════════════════════════════════════════════════════════════════

function CreateGCModal({
  isLoading,
  error,
  onSubmit,
  onClose,
}: {
  isLoading: boolean;
  error: string | null;
  onSubmit: (data: GCCreate) => void;
  onClose: () => void;
}) {
  const [companyName, setCompanyName] = useState('');
  const [gcCode, setGcCode] = useState('');
  const [tradeType, setTradeType] = useState<GCTradeType>('general');
  const [licenseNumber, setLicenseNumber] = useState('');
  const [phone, setPhone] = useState('');
  const [email, setEmail] = useState('');
  const [website, setWebsite] = useState('');
  const [addressLine1, setAddressLine1] = useState('');
  const [city, setCity] = useState('');
  const [state, setState] = useState('');
  const [zip, setZip] = useState('');
  const [notes, setNotes] = useState('');

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!companyName.trim() || !gcCode.trim()) return;
    onSubmit({
      company_name: companyName.trim(),
      gc_code: gcCode.trim().toUpperCase(),
      trade_type: tradeType,
      license_number: licenseNumber.trim() || null,
      phone: phone.trim() || null,
      email: email.trim() || null,
      website: website.trim() || null,
      address_line1: addressLine1.trim() || null,
      city: city.trim() || null,
      state: state.trim() || null,
      zip: zip.trim() || null,
      notes: notes.trim() || null,
    });
  };

  return (
    <Modal isOpen title="New General Contractor" onClose={onClose} size="lg">
      <form onSubmit={handleSubmit} className="space-y-4">
        {error && (
          <div className="p-3 rounded-lg bg-red-50 dark:bg-red-900/20 text-red-600 dark:text-red-400 text-sm">
            {error}
          </div>
        )}

        {/* Company + code row */}
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
          <div className="sm:col-span-2">
            <Input
              label="Company Name *"
              value={companyName}
              onChange={(e) => setCompanyName(e.target.value)}
              required
              autoFocus
            />
          </div>
          <Input
            label="GC Code *"
            value={gcCode}
            onChange={(e) => setGcCode(e.target.value.toUpperCase())}
            placeholder="e.g. SMITH"
            required
          />
        </div>

        <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
          <div>
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
              Trade Type
            </label>
            <select
              value={tradeType}
              onChange={(e) => setTradeType(e.target.value as GCTradeType)}
              className="w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 px-3 py-2 text-sm"
            >
              {(Object.entries(TRADE_TYPE_LABELS) as [GCTradeType, string][]).map(([val, label]) => (
                <option key={val} value={val}>{label}</option>
              ))}
            </select>
          </div>
          <Input
            label="License Number"
            value={licenseNumber}
            onChange={(e) => setLicenseNumber(e.target.value)}
          />
        </div>

        {/* Contact */}
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
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
          <Input
            label="Website"
            value={website}
            onChange={(e) => setWebsite(e.target.value)}
            placeholder="https://..."
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
          <Input label="City" value={city} onChange={(e) => setCity(e.target.value)} />
          <Input label="State" value={state} onChange={(e) => setState(e.target.value)} />
          <Input label="ZIP" value={zip} onChange={(e) => setZip(e.target.value)} />
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
          <Button type="submit" isLoading={isLoading} disabled={!companyName.trim() || !gcCode.trim()}>
            Create Contractor
          </Button>
        </div>
      </form>
    </Modal>
  );
}
