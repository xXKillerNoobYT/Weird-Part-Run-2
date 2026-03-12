/**
 * CompanyProfilePage — manage company profiles used for PO branding.
 *
 * Companies can have multiple profiles (branches). Each profile provides
 * the name, address, phone, email, and logo URL that appear on PO PDFs.
 * One profile is marked as "primary" and used by default.
 */

import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Building2, Plus, Star, Pencil, Trash2, Check, X } from 'lucide-react';
import {
  listCompanyProfiles,
  createCompanyProfile,
  updateCompanyProfile,
  deleteCompanyProfile,
} from '../../../api/settings';
import { EmptyState } from '../../../components/ui/EmptyState';
import { ErrorFallback } from '../../../components/ui/ErrorFallback';
import type { CompanyProfile, CompanyProfileCreate, CompanyProfileUpdate } from '../../../lib/types';

export function CompanyProfilePage() {
  const queryClient = useQueryClient();
  const [editingId, setEditingId] = useState<number | null>(null);
  const [showAdd, setShowAdd] = useState(false);

  const { data: profiles = [], isLoading, isError, refetch } = useQuery({
    queryKey: ['company-profiles'],
    queryFn: listCompanyProfiles,
  });

  const createMutation = useMutation({
    mutationFn: createCompanyProfile,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['company-profiles'] });
      setShowAdd(false);
    },
  });

  const updateMutation = useMutation({
    mutationFn: ({ id, data }: { id: number; data: CompanyProfileUpdate }) =>
      updateCompanyProfile(id, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['company-profiles'] });
      setEditingId(null);
    },
  });

  const deleteMutation = useMutation({
    mutationFn: deleteCompanyProfile,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['company-profiles'] });
    },
  });

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold text-gray-900 dark:text-gray-100">
            Company Profiles
          </h1>
          <p className="text-sm text-gray-500 dark:text-gray-400 mt-1">
            Manage company info used on Purchase Order PDFs and supplier communications.
          </p>
        </div>
        <button
          onClick={() => setShowAdd(true)}
          className="inline-flex items-center gap-2 rounded-lg bg-primary px-4 py-2 text-sm font-medium text-white shadow-sm hover:bg-primary/90 transition-colors"
        >
          <Plus className="h-4 w-4" />
          Add Profile
        </button>
      </div>

      {/* Add form */}
      {showAdd && (
        <ProfileForm
          onSubmit={(data) => createMutation.mutate(data)}
          onCancel={() => setShowAdd(false)}
          loading={createMutation.isPending}
        />
      )}

      {/* Profiles list */}
      {isError ? (
        <ErrorFallback onRetry={refetch} />
      ) : isLoading ? (
        <div className="flex justify-center py-12">
          <div className="h-8 w-8 animate-spin rounded-full border-4 border-primary border-t-transparent" />
        </div>
      ) : profiles.length === 0 && !showAdd ? (
        <EmptyState
          icon={<Building2 className="h-12 w-12" />}
          title="No company profiles"
          description="Add your company info to display on PO PDFs and supplier communications."
          action={
            <button
              onClick={() => setShowAdd(true)}
              className="text-sm text-primary hover:underline"
            >
              + Add your first profile
            </button>
          }
        />
      ) : (
        <div className="space-y-4">
          {profiles.map((profile: CompanyProfile) => (
            <div key={profile.id}>
              {editingId === profile.id ? (
                <ProfileForm
                  initial={profile}
                  onSubmit={(data) =>
                    updateMutation.mutate({ id: profile.id, data })
                  }
                  onCancel={() => setEditingId(null)}
                  loading={updateMutation.isPending}
                />
              ) : (
                <ProfileCard
                  profile={profile}
                  onEdit={() => setEditingId(profile.id)}
                  onDelete={() => {
                    if (confirm('Delete this company profile? This cannot be undone.')) {
                      deleteMutation.mutate(profile.id);
                    }
                  }}
                />
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}


// ── Sub-components ──────────────────────────────────────────────────

function ProfileCard({
  profile,
  onEdit,
  onDelete,
}: {
  profile: CompanyProfile;
  onEdit: () => void;
  onDelete: () => void;
}) {
  return (
    <div className="rounded-lg border border-border bg-surface p-4">
      <div className="flex items-start justify-between">
        <div className="flex items-center gap-3">
          <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-primary/10 text-primary">
            <Building2 className="h-5 w-5" />
          </div>
          <div>
            <div className="flex items-center gap-2">
              <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100">
                {profile.name}
              </h3>
              {profile.is_primary && (
                <span className="inline-flex items-center gap-1 rounded-full bg-amber-100 px-2 py-0.5 text-xs font-medium text-amber-700 dark:bg-amber-900/30 dark:text-amber-400">
                  <Star className="h-3 w-3" />
                  Primary
                </span>
              )}
            </div>
            <div className="mt-1 text-sm text-gray-500 dark:text-gray-400 space-y-0.5">
              {profile.branch_name && (
                <p className="text-xs font-medium text-gray-400 dark:text-gray-500">{profile.branch_name}</p>
              )}
              {(profile.address_street || profile.address_city) && (
                <p>
                  {[
                    profile.address_street,
                    [profile.address_city, profile.address_state, profile.address_zip]
                      .filter(Boolean).join(', '),
                  ].filter(Boolean).join(', ')}
                </p>
              )}
              <div className="flex gap-4">
                {profile.phone && <span>📞 {profile.phone}</span>}
                {profile.email && <span>✉ {profile.email}</span>}
              </div>
              {profile.website && (
                <p className="text-primary text-xs">{profile.website}</p>
              )}
            </div>
          </div>
        </div>

        <div className="flex items-center gap-1">
          <button
            onClick={onEdit}
            className="p-1.5 rounded text-gray-400 hover:text-primary hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors"
            title="Edit"
          >
            <Pencil className="h-4 w-4" />
          </button>
          <button
            onClick={onDelete}
            className="p-1.5 rounded text-gray-400 hover:text-red-500 hover:bg-red-50 dark:hover:bg-red-900/20 transition-colors"
            title="Delete"
          >
            <Trash2 className="h-4 w-4" />
          </button>
        </div>
      </div>
    </div>
  );
}


function ProfileForm({
  initial,
  onSubmit,
  onCancel,
  loading,
}: {
  initial?: CompanyProfile;
  onSubmit: (data: CompanyProfileCreate) => void;
  onCancel: () => void;
  loading: boolean;
}) {
  const [form, setForm] = useState({
    name: initial?.name ?? '',
    address_street: initial?.address_street ?? '',
    address_city: initial?.address_city ?? '',
    address_state: initial?.address_state ?? '',
    address_zip: initial?.address_zip ?? '',
    phone: initial?.phone ?? '',
    email: initial?.email ?? '',
    website: initial?.website ?? '',
    branch_name: initial?.branch_name ?? '',
    is_primary: initial?.is_primary ?? false,
  });

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!form.name.trim()) return;
    onSubmit({
      name: form.name.trim(),
      address_street: form.address_street.trim() || undefined,
      address_city: form.address_city.trim() || undefined,
      address_state: form.address_state.trim() || undefined,
      address_zip: form.address_zip.trim() || undefined,
      phone: form.phone.trim() || undefined,
      email: form.email.trim() || undefined,
      website: form.website.trim() || undefined,
      branch_name: form.branch_name.trim() || undefined,
      is_primary: form.is_primary,
    });
  };

  return (
    <form
      onSubmit={handleSubmit}
      className="rounded-lg border border-primary/30 bg-surface p-4 space-y-4"
    >
      <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100">
        {initial ? 'Edit Profile' : 'New Company Profile'}
      </h3>

      <div className="grid gap-4 sm:grid-cols-2">
        <div>
          <label className="block text-xs font-medium text-gray-700 dark:text-gray-300 mb-1">
            Company Name *
          </label>
          <input
            type="text"
            value={form.name}
            onChange={(e) => setForm((f) => ({ ...f, name: e.target.value }))}
            required
            className="w-full rounded-lg border border-border bg-surface py-2 px-3 text-sm text-gray-900 dark:text-gray-100"
            placeholder="Acme Electric LLC"
          />
        </div>
        <div>
          <label className="block text-xs font-medium text-gray-700 dark:text-gray-300 mb-1">
            Branch Name
          </label>
          <input
            type="text"
            value={form.branch_name}
            onChange={(e) => setForm((f) => ({ ...f, branch_name: e.target.value }))}
            className="w-full rounded-lg border border-border bg-surface py-2 px-3 text-sm text-gray-900 dark:text-gray-100"
            placeholder="Main Office"
          />
        </div>
        <div>
          <label className="block text-xs font-medium text-gray-700 dark:text-gray-300 mb-1">
            Phone
          </label>
          <input
            type="text"
            value={form.phone}
            onChange={(e) => setForm((f) => ({ ...f, phone: e.target.value }))}
            className="w-full rounded-lg border border-border bg-surface py-2 px-3 text-sm text-gray-900 dark:text-gray-100"
            placeholder="(555) 123-4567"
          />
        </div>
        <div>
          <label className="block text-xs font-medium text-gray-700 dark:text-gray-300 mb-1">
            Email
          </label>
          <input
            type="email"
            value={form.email}
            onChange={(e) => setForm((f) => ({ ...f, email: e.target.value }))}
            className="w-full rounded-lg border border-border bg-surface py-2 px-3 text-sm text-gray-900 dark:text-gray-100"
            placeholder="orders@acmeelectric.com"
          />
        </div>
        <div>
          <label className="block text-xs font-medium text-gray-700 dark:text-gray-300 mb-1">
            Website
          </label>
          <input
            type="text"
            value={form.website}
            onChange={(e) => setForm((f) => ({ ...f, website: e.target.value }))}
            className="w-full rounded-lg border border-border bg-surface py-2 px-3 text-sm text-gray-900 dark:text-gray-100"
            placeholder="https://acmeelectric.com"
          />
        </div>
      </div>

      {/* Address fields */}
      <div>
        <label className="block text-xs font-medium text-gray-700 dark:text-gray-300 mb-1">
          Street Address
        </label>
        <input
          type="text"
          value={form.address_street}
          onChange={(e) => setForm((f) => ({ ...f, address_street: e.target.value }))}
          className="w-full rounded-lg border border-border bg-surface py-2 px-3 text-sm text-gray-900 dark:text-gray-100"
          placeholder="123 Main St, Suite 100"
        />
      </div>
      <div className="grid gap-4 sm:grid-cols-3">
        <div>
          <label className="block text-xs font-medium text-gray-700 dark:text-gray-300 mb-1">
            City
          </label>
          <input
            type="text"
            value={form.address_city}
            onChange={(e) => setForm((f) => ({ ...f, address_city: e.target.value }))}
            className="w-full rounded-lg border border-border bg-surface py-2 px-3 text-sm text-gray-900 dark:text-gray-100"
            placeholder="Austin"
          />
        </div>
        <div>
          <label className="block text-xs font-medium text-gray-700 dark:text-gray-300 mb-1">
            State
          </label>
          <input
            type="text"
            value={form.address_state}
            onChange={(e) => setForm((f) => ({ ...f, address_state: e.target.value }))}
            className="w-full rounded-lg border border-border bg-surface py-2 px-3 text-sm text-gray-900 dark:text-gray-100"
            placeholder="TX"
          />
        </div>
        <div>
          <label className="block text-xs font-medium text-gray-700 dark:text-gray-300 mb-1">
            ZIP Code
          </label>
          <input
            type="text"
            value={form.address_zip}
            onChange={(e) => setForm((f) => ({ ...f, address_zip: e.target.value }))}
            className="w-full rounded-lg border border-border bg-surface py-2 px-3 text-sm text-gray-900 dark:text-gray-100"
            placeholder="78701"
          />
        </div>
      </div>

      <label className="flex items-center gap-2 text-sm cursor-pointer">
        <input
          type="checkbox"
          checked={form.is_primary}
          onChange={(e) => setForm((f) => ({ ...f, is_primary: e.target.checked }))}
          className="rounded border-gray-300 text-primary focus:ring-primary"
        />
        <span className="text-gray-700 dark:text-gray-300">
          Set as primary profile (used by default on PO PDFs)
        </span>
      </label>

      <div className="flex justify-end gap-2">
        <button
          type="button"
          onClick={onCancel}
          className="inline-flex items-center gap-1 rounded-lg border border-border bg-surface px-3 py-2 text-sm font-medium text-gray-700 dark:text-gray-300 hover:bg-surface-secondary transition-colors"
        >
          <X className="h-4 w-4" />
          Cancel
        </button>
        <button
          type="submit"
          disabled={loading || !form.name.trim()}
          className="inline-flex items-center gap-1 rounded-lg bg-primary px-4 py-2 text-sm font-medium text-white shadow-sm hover:bg-primary/90 transition-colors disabled:opacity-50"
        >
          <Check className="h-4 w-4" />
          {initial ? 'Save Changes' : 'Create Profile'}
        </button>
      </div>
    </form>
  );
}
