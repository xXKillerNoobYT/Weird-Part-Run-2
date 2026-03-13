/**
 * HatsPage — manage roles ("hats") employees can wear.
 *
 * Shows all hats with their permissions, user counts, and built-in status.
 * Each hat card expands to show a domain-grouped permission checklist.
 * Supports create, edit, delete (unless built-in), and permission toggling.
 */

import { useState, useCallback, useEffect } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  Crown, Plus, Pencil, Trash2, ChevronDown, ChevronRight,
  Users, Shield, Lock, Save,
} from 'lucide-react';
import { Button } from '../../../components/ui/Button';
import { Card } from '../../../components/ui/Card';
import { Modal } from '../../../components/ui/Modal';
import { Badge } from '../../../components/ui/Badge';
import { Input } from '../../../components/ui/Input';
import { EmptyState } from '../../../components/ui/EmptyState';
import { PageSpinner } from '../../../components/ui/Spinner';
import { useAuthStore } from '../../../stores/auth-store';
import { PERMISSIONS } from '../../../lib/constants';
import { getHats, createHat, updateHat, deleteHat, setHatPermissions } from '../../../api/people';
import type { HatDetailResponse, HatCreate, HatUpdate } from '../../../lib/types';


// ── Level badge helpers ──────────────────────────────────────────
const LEVEL_CONFIG: Record<number, { label: string; color: string }> = {
  0: { label: 'Admin',     color: 'bg-red-100 text-red-700 dark:bg-red-900 dark:text-red-300' },
  1: { label: 'Level 1',   color: 'bg-orange-100 text-orange-700 dark:bg-orange-900 dark:text-orange-300' },
  2: { label: 'Level 2',   color: 'bg-amber-100 text-amber-700 dark:bg-amber-900 dark:text-amber-300' },
  3: { label: 'Level 3',   color: 'bg-yellow-100 text-yellow-700 dark:bg-yellow-900 dark:text-yellow-300' },
  4: { label: 'Level 4',   color: 'bg-lime-100 text-lime-700 dark:bg-lime-900 dark:text-lime-300' },
  5: { label: 'Level 5',   color: 'bg-green-100 text-green-700 dark:bg-green-900 dark:text-green-300' },
  6: { label: 'Level 6',   color: 'bg-teal-100 text-teal-700 dark:bg-teal-900 dark:text-teal-300' },
};

function LevelBadge({ level }: { level: number }) {
  const cfg = LEVEL_CONFIG[level] ?? LEVEL_CONFIG[6];
  return (
    <span className={`inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium ${cfg.color}`}>
      {cfg.label}
    </span>
  );
}


// ── Permission domain display names ──────────────────────────────
const DOMAIN_LABELS: Record<string, string> = {
  warehouse: 'Warehouse',
  orders:    'Orders',
  people:    'People',
  jobs:      'Jobs',
  fleet:     'Fleet',
  parts:     'Parts & Catalog',
  reports:   'Reports',
  notebooks: 'Notebooks',
  settings:  'Settings',
};

/** Humanize a permission key: "view_warehouse" → "View Warehouse" */
function humanize(key: string): string {
  return key.replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase());
}


// ── Permission Domains (client-side mirror of backend PERMISSION_DOMAINS) ──
// Used when the permission keys endpoint just returns a flat list.
const PERMISSION_DOMAINS: Record<string, string[]> = {
  warehouse: ['view_warehouse', 'manage_warehouse', 'perform_audit', 'manage_stock'],
  orders:    ['view_orders', 'manage_orders', 'approve_orders'],
  people:    ['view_people', 'manage_people'],
  jobs:      ['view_jobs', 'manage_jobs'],
  fleet:     ['view_trucks', 'manage_fleet'],
  parts:     ['view_parts_catalog', 'edit_pricing', 'show_dollar_values'],
  reports:   ['view_reports', 'export_reports'],
  notebooks: ['manage_notebooks'],
  settings:  ['manage_settings', 'manage_devices'],
};


// =================================================================
// HAT CARD (expandable with permissions)
// =================================================================

interface HatCardProps {
  hat: HatDetailResponse;
  canManage: boolean;
  onEdit: (hat: HatDetailResponse) => void;
  onDelete: (hat: HatDetailResponse) => void;
  onPermissionToggle: (hatId: number, permKey: string, enabled: boolean, currentPerms: string[]) => void;
  isSavingPerms: boolean;
}

function HatCard({ hat, canManage, onEdit, onDelete, onPermissionToggle, isSavingPerms }: HatCardProps) {
  const [expanded, setExpanded] = useState(false);
  const permSet = new Set(hat.permissions);

  return (
    <Card noPadding className="overflow-hidden">
      {/* Hat header row */}
      <div
        className="flex items-center gap-3 p-4 cursor-pointer hover:bg-gray-50 dark:hover:bg-gray-750 transition-colors"
        onClick={() => setExpanded(prev => !prev)}
      >
        {/* Expand chevron */}
        <div className="flex-shrink-0 text-gray-400 dark:text-gray-500">
          {expanded ? <ChevronDown className="h-5 w-5" /> : <ChevronRight className="h-5 w-5" />}
        </div>

        {/* Hat icon */}
        <div className="flex-shrink-0 h-10 w-10 rounded-lg bg-primary-100 dark:bg-primary-900 flex items-center justify-center">
          <Crown className="h-5 w-5 text-primary-600 dark:text-primary-400" />
        </div>

        {/* Name + description */}
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 flex-wrap">
            <h3 className="font-semibold text-gray-900 dark:text-gray-100 truncate">
              {hat.name}
            </h3>
            <LevelBadge level={hat.level} />
            {hat.is_builtin && (
              <Badge variant="default">
                <Lock className="h-3 w-3 mr-1" />
                Built-in
              </Badge>
            )}
          </div>
          {hat.description && (
            <p className="text-sm text-gray-500 dark:text-gray-400 truncate mt-0.5">
              {hat.description}
            </p>
          )}
        </div>

        {/* Stats */}
        <div className="hidden sm:flex items-center gap-4 flex-shrink-0 text-sm text-gray-500 dark:text-gray-400">
          <span className="flex items-center gap-1" title="Users with this hat">
            <Users className="h-4 w-4" />
            {hat.user_count}
          </span>
          <span className="flex items-center gap-1" title="Permissions assigned">
            <Shield className="h-4 w-4" />
            {hat.permissions.length}
          </span>
        </div>

        {/* Actions */}
        {canManage && (
          <div className="flex items-center gap-1 flex-shrink-0" onClick={e => e.stopPropagation()}>
            <button
              onClick={() => onEdit(hat)}
              className="p-2 rounded-lg text-gray-400 hover:text-primary-600 hover:bg-primary-50 dark:hover:bg-primary-900/30 transition-colors min-h-[44px] min-w-[44px] flex items-center justify-center"
              title="Edit hat"
            >
              <Pencil className="h-4 w-4" />
            </button>
            {!hat.is_builtin && (
              <button
                onClick={() => onDelete(hat)}
                className="p-2 rounded-lg text-gray-400 hover:text-red-600 hover:bg-red-50 dark:hover:bg-red-900/30 transition-colors min-h-[44px] min-w-[44px] flex items-center justify-center"
                title="Delete hat"
              >
                <Trash2 className="h-4 w-4" />
              </button>
            )}
          </div>
        )}
      </div>

      {/* Mobile stats (shown below header on small screens) */}
      <div className="sm:hidden flex items-center gap-4 px-4 pb-2 text-sm text-gray-500 dark:text-gray-400">
        <span className="flex items-center gap-1">
          <Users className="h-4 w-4" /> {hat.user_count} users
        </span>
        <span className="flex items-center gap-1">
          <Shield className="h-4 w-4" /> {hat.permissions.length} perms
        </span>
      </div>

      {/* Expanded permissions checklist */}
      {expanded && (
        <div className="border-t border-gray-200 dark:border-gray-700 bg-gray-50 dark:bg-gray-850 p-4">
          <div className="flex items-center justify-between mb-3">
            <h4 className="text-sm font-medium text-gray-700 dark:text-gray-300">
              Permissions
            </h4>
            {isSavingPerms && (
              <span className="text-xs text-primary-600 dark:text-primary-400 flex items-center gap-1">
                <Save className="h-3 w-3 animate-pulse" /> Saving...
              </span>
            )}
          </div>

          <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
            {Object.entries(PERMISSION_DOMAINS).map(([domain, keys]) => (
              <div key={domain} className="space-y-1">
                <h5 className="text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400 mb-2">
                  {DOMAIN_LABELS[domain] ?? humanize(domain)}
                </h5>
                {keys.map(key => (
                  <label
                    key={key}
                    className={`flex items-center gap-2 py-1 px-2 rounded text-sm transition-colors
                      ${canManage ? 'cursor-pointer hover:bg-white dark:hover:bg-gray-800' : 'cursor-default'}`}
                  >
                    <input
                      type="checkbox"
                      checked={permSet.has(key)}
                      disabled={!canManage || isSavingPerms}
                      onChange={e => onPermissionToggle(hat.id, key, e.target.checked, hat.permissions)}
                      className="rounded border-gray-300 dark:border-gray-600 text-primary-600 focus:ring-primary-500 h-4 w-4"
                    />
                    <span className={permSet.has(key)
                      ? 'text-gray-900 dark:text-gray-100'
                      : 'text-gray-500 dark:text-gray-400'
                    }>
                      {humanize(key)}
                    </span>
                  </label>
                ))}
              </div>
            ))}
          </div>
        </div>
      )}
    </Card>
  );
}


// =================================================================
// CREATE / EDIT MODAL
// =================================================================

interface HatModalProps {
  isOpen: boolean;
  onClose: () => void;
  hat?: HatDetailResponse | null;
  onSubmit: (data: HatCreate | HatUpdate) => void;
  isLoading: boolean;
}

function HatModal({ isOpen, onClose, hat, onSubmit, isLoading }: HatModalProps) {
  const [name, setName] = useState('');
  const [description, setDescription] = useState('');
  const [level, setLevel] = useState(5);
  const isEdit = !!hat;

  // Sync form state when modal opens or hat changes
  useEffect(() => {
    if (isOpen) {
      setName(hat?.name ?? '');
      setDescription(hat?.description ?? '');
      setLevel(hat?.level ?? 5);
    }
  }, [isOpen, hat]);

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!name.trim()) return;

    onSubmit({
      name: name.trim(),
      description: description.trim() || null,
      level,
    });
  }

  return (
    <Modal isOpen={isOpen} onClose={onClose} title={isEdit ? 'Edit Hat' : 'Create Hat'} size="md">
      <form onSubmit={handleSubmit} className="space-y-4">
        <Input
          label="Hat Name"
          value={name}
          onChange={e => setName(e.target.value)}
          placeholder="e.g. Warehouse Lead"
          required
          autoFocus
        />

        <Input
          label="Description"
          value={description}
          onChange={e => setDescription(e.target.value)}
          placeholder="What does this role do?"
        />

        <div>
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
            Access Level
          </label>
          <select
            value={level}
            onChange={e => setLevel(Number(e.target.value))}
            className="w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 px-3 py-2 text-sm focus:ring-2 focus:ring-primary-500 focus:border-primary-500"
          >
            <option value={0}>Level 0 — Admin (highest)</option>
            <option value={1}>Level 1 — Director</option>
            <option value={2}>Level 2 — Manager</option>
            <option value={3}>Level 3 — Supervisor</option>
            <option value={4}>Level 4 — Senior</option>
            <option value={5}>Level 5 — Standard</option>
            <option value={6}>Level 6 — Entry</option>
          </select>
          <p className="text-xs text-gray-500 dark:text-gray-400 mt-1">
            Lower numbers = more authority. Level 0 is the highest access tier.
          </p>
        </div>

        <div className="flex justify-end gap-3 pt-2">
          <Button type="button" variant="secondary" onClick={onClose}>
            Cancel
          </Button>
          <Button type="submit" isLoading={isLoading} disabled={!name.trim()}>
            {isEdit ? 'Save Changes' : 'Create Hat'}
          </Button>
        </div>
      </form>
    </Modal>
  );
}


// =================================================================
// MAIN PAGE
// =================================================================

export function HatsPage() {
  const { hasPermission } = useAuthStore();
  const canManage = hasPermission(PERMISSIONS.MANAGE_PEOPLE);
  const queryClient = useQueryClient();

  // ── State ──────────────────────────────────────────────────────
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [editingHat, setEditingHat] = useState<HatDetailResponse | null>(null);
  const [deletingHat, setDeletingHat] = useState<HatDetailResponse | null>(null);
  const [savingPermHatId, setSavingPermHatId] = useState<number | null>(null);

  // ── Queries ────────────────────────────────────────────────────
  const { data: hats, isLoading, error } = useQuery({
    queryKey: ['people', 'hats'],
    queryFn: getHats,
  });

  // ── Mutations ──────────────────────────────────────────────────
  const createMutation = useMutation({
    mutationFn: (data: HatCreate) => createHat(data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['people', 'hats'] });
      setShowCreateModal(false);
    },
  });

  const updateMutation = useMutation({
    mutationFn: ({ hatId, data }: { hatId: number; data: HatUpdate }) => updateHat(hatId, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['people', 'hats'] });
      setEditingHat(null);
    },
  });

  const deleteMutation = useMutation({
    mutationFn: (hatId: number) => deleteHat(hatId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['people', 'hats'] });
      setDeletingHat(null);
    },
  });

  const permMutation = useMutation({
    mutationFn: ({ hatId, keys }: { hatId: number; keys: string[] }) =>
      setHatPermissions(hatId, keys),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['people', 'hats'] });
      queryClient.invalidateQueries({ queryKey: ['people', 'permissions'] });
      setSavingPermHatId(null);
    },
    onError: () => {
      setSavingPermHatId(null);
    },
  });

  // ── Handlers ───────────────────────────────────────────────────
  const handlePermissionToggle = useCallback(
    (hatId: number, permKey: string, enabled: boolean, currentPerms: string[]) => {
      setSavingPermHatId(hatId);
      const newPerms = enabled
        ? [...currentPerms, permKey]
        : currentPerms.filter(k => k !== permKey);
      permMutation.mutate({ hatId, keys: newPerms });
    },
    [permMutation],
  );

  // ── Loading / Error ────────────────────────────────────────────
  if (isLoading) return <PageSpinner />;

  if (error) {
    return (
      <EmptyState
        icon={<Crown className="h-12 w-12" />}
        title="Failed to Load Hats"
        description="Could not load roles. Please try refreshing the page."
      />
    );
  }

  if (!hats || hats.length === 0) {
    return (
      <div>
        <div className="flex items-center justify-between flex-wrap gap-3 mb-6">
          <h1 className="text-2xl font-bold text-gray-900 dark:text-gray-100">
            Roles & Hats
          </h1>
          {canManage && (
            <Button icon={<Plus className="h-4 w-4" />} onClick={() => setShowCreateModal(true)}>
              <span className="hidden sm:inline">New Hat</span>
            </Button>
          )}
        </div>
        <EmptyState
          icon={<Crown className="h-12 w-12" />}
          title="No Hats Defined"
          description="Create your first role to start organizing employee access levels."
        />
        {showCreateModal && (
          <HatModal
            isOpen={showCreateModal}
            onClose={() => setShowCreateModal(false)}
            onSubmit={data => createMutation.mutate(data as HatCreate)}
            isLoading={createMutation.isPending}
          />
        )}
      </div>
    );
  }

  // Sort hats by level (admins first), then alphabetically
  const sortedHats = [...hats].sort((a, b) => a.level - b.level || a.name.localeCompare(b.name));

  return (
    <div>
      {/* Page header */}
      <div className="flex items-center justify-between flex-wrap gap-3 mb-6">
        <div>
          <h1 className="text-2xl font-bold text-gray-900 dark:text-gray-100">
            Roles & Hats
          </h1>
          <p className="text-sm text-gray-500 dark:text-gray-400 mt-1">
            {hats.length} role{hats.length !== 1 ? 's' : ''} defined — click to expand permissions
          </p>
        </div>
        {canManage && (
          <Button icon={<Plus className="h-4 w-4" />} onClick={() => setShowCreateModal(true)}>
            <span className="hidden sm:inline">New Hat</span>
          </Button>
        )}
      </div>

      {/* Hat cards */}
      <div className="space-y-3">
        {sortedHats.map(hat => (
          <HatCard
            key={hat.id}
            hat={hat}
            canManage={canManage}
            onEdit={setEditingHat}
            onDelete={setDeletingHat}
            onPermissionToggle={handlePermissionToggle}
            isSavingPerms={savingPermHatId === hat.id}
          />
        ))}
      </div>

      {/* Create modal */}
      {showCreateModal && (
        <HatModal
          isOpen={showCreateModal}
          onClose={() => setShowCreateModal(false)}
          onSubmit={data => createMutation.mutate(data as HatCreate)}
          isLoading={createMutation.isPending}
        />
      )}

      {/* Edit modal */}
      {editingHat && (
        <HatModal
          isOpen={!!editingHat}
          onClose={() => setEditingHat(null)}
          hat={editingHat}
          onSubmit={data => updateMutation.mutate({ hatId: editingHat.id, data: data as HatUpdate })}
          isLoading={updateMutation.isPending}
        />
      )}

      {/* Delete confirmation */}
      {deletingHat && (
        <Modal
          isOpen={!!deletingHat}
          onClose={() => setDeletingHat(null)}
          title="Delete Hat"
          size="sm"
        >
          <div className="space-y-4">
            <p className="text-gray-600 dark:text-gray-400">
              Are you sure you want to delete{' '}
              <strong className="text-gray-900 dark:text-gray-100">{deletingHat.name}</strong>?
            </p>
            {deletingHat.user_count > 0 && (
              <div className="p-3 rounded-lg bg-amber-50 dark:bg-amber-900/20 border border-amber-200 dark:border-amber-800">
                <p className="text-sm text-amber-700 dark:text-amber-400">
                  This hat is currently assigned to {deletingHat.user_count} employee
                  {deletingHat.user_count !== 1 ? 's' : ''}. They will lose all permissions
                  associated with this hat.
                </p>
              </div>
            )}
            <div className="flex justify-end gap-3">
              <Button variant="secondary" onClick={() => setDeletingHat(null)}>
                Cancel
              </Button>
              <Button
                variant="danger"
                isLoading={deleteMutation.isPending}
                onClick={() => deleteMutation.mutate(deletingHat.id)}
              >
                Delete Hat
              </Button>
            </div>
          </div>
        </Modal>
      )}
    </div>
  );
}