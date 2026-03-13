/**
 * EmployeeListPage — paginated employee list with search, filters, and create modal.
 *
 * Shows employee cards with avatar, name, hat badges, certification level, hire date,
 * and status indicator. Supports search, active/inactive filter, and hat filter.
 * Create modal allows adding new employees with PIN, hats, and pay rate.
 */

import { useState, useEffect, useCallback } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  Plus, Search, Users, Phone, Mail, ChevronLeft, ChevronRight,
  Award, X, Filter, Upload,
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
import { getEmployees, createEmployee, getHats, importEmployeesCSV } from '../../../api/people';
import type {
  EmployeeCreate, EmployeeListItem, HatDetailResponse,
} from '../../../lib/types';

// ── Helpers ───────────────────────────────────────────────────────

function certLabel(cert: string | null): string {
  if (!cert) return '';
  return cert.charAt(0).toUpperCase() + cert.slice(1);
}

const PAGE_SIZES = [25, 50, 100];

// ═════════════════════════════════════════════════════════════════
// MAIN PAGE
// ═════════════════════════════════════════════════════════════════

export function EmployeeListPage() {
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const { hasPermission } = useAuthStore();
  const canManage = hasPermission(PERMISSIONS.MANAGE_PEOPLE);

  // ── State ──────────────────────────────────────────────────────
  const [search, setSearch] = useState('');
  const [debouncedSearch, setDebouncedSearch] = useState('');
  const [isActiveFilter, setIsActiveFilter] = useState<boolean | undefined>(true);
  const [hatFilter, setHatFilter] = useState<number | undefined>(undefined);
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
  useEffect(() => { setPage(1); }, [isActiveFilter, hatFilter, pageSize]);

  // ── Queries ────────────────────────────────────────────────────
  const { data, isLoading, error } = useQuery({
    queryKey: ['employees', debouncedSearch, isActiveFilter, hatFilter, page, pageSize],
    queryFn: () => getEmployees({
      search: debouncedSearch || undefined,
      is_active: isActiveFilter,
      hat_id: hatFilter,
      page,
      page_size: pageSize,
    }),
    staleTime: 15_000,
  });

  const { data: hats } = useQuery({
    queryKey: ['people-hats'],
    queryFn: getHats,
    staleTime: 60_000,
  });

  // ── Create mutation ────────────────────────────────────────────
  const createMutation = useMutation({
    mutationFn: createEmployee,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['employees'] });
      setShowCreate(false);
    },
  });

  const hasActiveFilters = isActiveFilter !== true || hatFilter !== undefined;

  const clearFilters = useCallback(() => {
    setIsActiveFilter(true);
    setHatFilter(undefined);
  }, []);

  if (isLoading) return <PageSpinner label="Loading employees..." />;

  if (error) {
    return (
      <div className="text-center py-16">
        <p className="text-red-500">Failed to load employees. Please try again.</p>
      </div>
    );
  }

  const employees = data?.items ?? [];
  const totalPages = data?.total_pages ?? 1;
  const total = data?.total ?? 0;

  return (
    <div className="space-y-4">
      {/* Header */}
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div>
          <h1 className="text-xl font-semibold text-gray-900 dark:text-gray-100">
            Employees
          </h1>
          <p className="text-sm text-gray-500 dark:text-gray-400">
            {total} {isActiveFilter === true ? 'active' : isActiveFilter === false ? 'inactive' : 'total'} employees
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
              <span className="hidden sm:inline">Add Employee</span>
            </Button>
          )}
        </div>
      </div>

      {/* Search */}
      <Input
        placeholder="Search by name, email, or phone..."
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

            {hats && hats.length > 0 && (
              <div className="flex items-center gap-1.5">
                <span className="text-xs text-gray-500 dark:text-gray-400 mr-1">Role:</span>
                <select
                  value={hatFilter ?? ''}
                  onChange={(e) => setHatFilter(e.target.value ? Number(e.target.value) : undefined)}
                  className="text-xs rounded-md border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 px-2 py-1"
                >
                  <option value="">All Roles</option>
                  {hats.map((h) => (
                    <option key={h.id} value={h.id}>{h.name}</option>
                  ))}
                </select>
              </div>
            )}

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

      {/* Employee list */}
      {employees.length === 0 ? (
        <EmptyState
          icon={<Users size={48} />}
          title="No employees found"
          description={search ? `No results for "${search}"` : 'No employees match the current filters.'}
          action={canManage ? <Button size="sm" onClick={() => setShowCreate(true)}>Add Employee</Button> : undefined}
        />
      ) : (
        <div className="space-y-2">
          {employees.map((emp) => (
            <EmployeeRow
              key={emp.id}
              employee={emp}
              onClick={() => navigate(`/people/employees/${emp.id}`)}
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
        <CreateEmployeeModal
          hats={hats ?? []}
          isLoading={createMutation.isPending}
          error={createMutation.error?.message ?? null}
          onSubmit={(data) => createMutation.mutate(data)}
          onClose={() => setShowCreate(false)}
        />
      )}

      {/* CSV Import modal */}
      <CSVImportModal
        isOpen={showImport}
        onClose={() => setShowImport(false)}
        title="Import Employees"
        description="Upload a CSV file to bulk-create employees. Existing employees (matched by name) are skipped."
        expectedColumns="display_name, email, phone, pin, certification, hire_date, pay_rate, emergency_contact_name, emergency_contact_phone"
        importFn={importEmployeesCSV}
        onSuccess={() => queryClient.invalidateQueries({ queryKey: ['employees'] })}
      />
    </div>
  );
}


// ═════════════════════════════════════════════════════════════════
// Employee Row
// ═════════════════════════════════════════════════════════════════

function EmployeeRow({ employee, onClick }: { employee: EmployeeListItem; onClick: () => void }) {
  return (
    <button
      onClick={onClick}
      className="w-full text-left bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-lg p-3 sm:p-4 hover:border-primary-300 dark:hover:border-primary-600 hover:shadow-sm transition-all group"
    >
      <div className="flex items-start gap-3">
        {/* Avatar */}
        <div className="flex-shrink-0 w-10 h-10 rounded-full bg-primary-100 dark:bg-primary-900/30 flex items-center justify-center text-primary-700 dark:text-primary-300 font-semibold text-sm">
          {employee.avatar_url ? (
            <img src={employee.avatar_url} alt="" className="w-10 h-10 rounded-full object-cover" />
          ) : (
            employee.display_name.charAt(0).toUpperCase()
          )}
        </div>

        {/* Info */}
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 flex-wrap">
            <span className="font-medium text-gray-900 dark:text-gray-100 truncate">
              {employee.display_name}
            </span>
            {!employee.is_active && <Badge variant="danger">Inactive</Badge>}
            {employee.certification && <Badge variant="primary">{certLabel(employee.certification)}</Badge>}
            {employee.active_cert_count > 0 && (
              <span className="hidden sm:inline-flex items-center gap-1 text-xs text-amber-600 dark:text-amber-400">
                <Award size={12} /> {employee.active_cert_count}
              </span>
            )}
          </div>

          {/* Hat badges */}
          {employee.hat_names.length > 0 && (
            <div className="flex items-center gap-1 mt-1 flex-wrap">
              {employee.hat_names.map((name) => (
                <span key={name} className="text-xs px-1.5 py-0.5 rounded bg-gray-100 dark:bg-gray-700 text-gray-600 dark:text-gray-400">
                  {name}
                </span>
              ))}
            </div>
          )}

          {/* Contact info (desktop) */}
          <div className="hidden sm:flex items-center gap-4 mt-1.5 text-xs text-gray-500 dark:text-gray-400">
            {employee.email && <span className="flex items-center gap-1 truncate"><Mail size={12} /> {employee.email}</span>}
            {employee.phone && <span className="flex items-center gap-1"><Phone size={12} /> {employee.phone}</span>}
            {employee.hire_date && <span>Hired: {employee.hire_date}</span>}
          </div>
        </div>

        <ChevronRight size={18} className="text-gray-300 dark:text-gray-600 group-hover:text-primary-400 transition-colors flex-shrink-0 mt-2" />
      </div>
    </button>
  );
}


// ═════════════════════════════════════════════════════════════════
// Create Employee Modal
// ═════════════════════════════════════════════════════════════════

interface CreateModalProps {
  hats: HatDetailResponse[];
  isLoading: boolean;
  error: string | null;
  onSubmit: (data: EmployeeCreate) => void;
  onClose: () => void;
}

function CreateEmployeeModal({ hats, isLoading, error, onSubmit, onClose }: CreateModalProps) {
  const [form, setForm] = useState<EmployeeCreate>({ display_name: '', pin: '' });
  const [selectedHatIds, setSelectedHatIds] = useState<number[]>([]);

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    onSubmit({ ...form, hat_ids: selectedHatIds.length > 0 ? selectedHatIds : undefined });
  };

  const toggleHat = (hatId: number) => {
    setSelectedHatIds((prev) =>
      prev.includes(hatId) ? prev.filter((id) => id !== hatId) : [...prev, hatId]
    );
  };

  return (
    <Modal isOpen onClose={onClose} title="New Employee" size="lg">
      <form onSubmit={handleSubmit} className="space-y-4">
        {error && (
          <div className="p-3 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-lg text-sm text-red-600 dark:text-red-400">
            {error}
          </div>
        )}

        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <Input label="Full Name *" value={form.display_name} onChange={(e) => setForm({ ...form, display_name: e.target.value })} required placeholder="John Smith" />
          <Input label="PIN (4-6 digits) *" value={form.pin} onChange={(e) => setForm({ ...form, pin: e.target.value.replace(/\D/g, '').slice(0, 6) })} required placeholder="1234" inputMode="numeric" pattern="\d{4,6}" maxLength={6} />
        </div>

        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <Input label="Email" type="email" value={form.email ?? ''} onChange={(e) => setForm({ ...form, email: e.target.value || null })} placeholder="john@example.com" />
          <Input label="Phone" type="tel" value={form.phone ?? ''} onChange={(e) => setForm({ ...form, phone: e.target.value || null })} placeholder="(555) 123-4567" />
        </div>

        <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
          <div className="space-y-1.5">
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300">Certification Level</label>
            <select
              value={form.certification ?? ''}
              onChange={(e) => setForm({ ...form, certification: (e.target.value || null) as any })}
              className="block w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 px-3 py-2 text-sm"
            >
              <option value="">None</option>
              <option value="apprentice">Apprentice</option>
              <option value="journeyman">Journeyman</option>
              <option value="master">Master</option>
            </select>
          </div>
          <Input label="Hire Date" type="date" value={form.hire_date ?? ''} onChange={(e) => setForm({ ...form, hire_date: e.target.value || null })} />
          <Input label="Pay Rate" type="number" step="0.01" min="0" value={form.pay_rate ?? ''} onChange={(e) => setForm({ ...form, pay_rate: e.target.value ? Number(e.target.value) : null })} placeholder="0.00" />
        </div>

        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <Input label="Emergency Contact" value={form.emergency_contact_name ?? ''} onChange={(e) => setForm({ ...form, emergency_contact_name: e.target.value || null })} placeholder="Jane Smith" />
          <Input label="Emergency Phone" type="tel" value={form.emergency_contact_phone ?? ''} onChange={(e) => setForm({ ...form, emergency_contact_phone: e.target.value || null })} placeholder="(555) 987-6543" />
        </div>

        {hats.length > 0 && (
          <div className="space-y-1.5">
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300">Assign Roles (Hats)</label>
            <div className="flex flex-wrap gap-2">
              {hats.map((h) => (
                <button
                  key={h.id}
                  type="button"
                  onClick={() => toggleHat(h.id)}
                  className={`px-3 py-1.5 text-sm rounded-lg border transition-colors ${selectedHatIds.includes(h.id)
                      ? 'bg-primary-50 dark:bg-primary-900/30 border-primary-300 dark:border-primary-700 text-primary-700 dark:text-primary-300'
                      : 'bg-white dark:bg-gray-800 border-gray-300 dark:border-gray-600 text-gray-600 dark:text-gray-400 hover:border-gray-400'
                    }`}
                >
                  {h.name}
                </button>
              ))}
            </div>
          </div>
        )}

        <div className="flex items-center justify-end gap-3 pt-2 border-t border-gray-200 dark:border-gray-700">
          <Button variant="ghost" type="button" onClick={onClose}>Cancel</Button>
          <Button type="submit" isLoading={isLoading} disabled={!form.display_name || form.pin.length < 4}>
            Create Employee
          </Button>
        </div>
      </form>
    </Modal>
  );
}
