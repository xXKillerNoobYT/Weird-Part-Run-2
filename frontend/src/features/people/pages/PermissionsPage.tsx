/**
 * PermissionsPage — full permission matrix: all hats × all permissions.
 *
 * Displays a scrollable grid grouped by domain (Warehouse, Orders, People, etc.).
 * Columns are hats (sorted by level), rows are permissions within each domain.
 * Checkboxes toggle individual permissions — changes auto-save immediately.
 *
 * Read-only for users without manage_people permission.
 * On mobile: horizontal scroll with sticky permission-name column.
 */

import { useState, useCallback } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Shield, Crown, ChevronDown, ChevronRight, Save } from 'lucide-react';
import { Card } from '../../../components/ui/Card';
import { Badge } from '../../../components/ui/Badge';
import { EmptyState } from '../../../components/ui/EmptyState';
import { PageSpinner } from '../../../components/ui/Spinner';
import { useAuthStore } from '../../../stores/auth-store';
import { PERMISSIONS } from '../../../lib/constants';
import { getPermissionMatrix, setHatPermissions, getHats } from '../../../api/people';



// ── Display helpers ──────────────────────────────────────────────

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

const DOMAIN_ORDER = [
  'warehouse', 'orders', 'people', 'jobs',
  'fleet', 'parts', 'reports', 'notebooks', 'settings',
];

/** "view_warehouse" → "View Warehouse" */
function humanize(key: string): string {
  return key.replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase());
}

/** Level badge colors matching HatsPage */
const LEVEL_COLORS: Record<number, string> = {
  0: 'bg-red-100 text-red-700 dark:bg-red-900 dark:text-red-300',
  1: 'bg-orange-100 text-orange-700 dark:bg-orange-900 dark:text-orange-300',
  2: 'bg-amber-100 text-amber-700 dark:bg-amber-900 dark:text-amber-300',
  3: 'bg-yellow-100 text-yellow-700 dark:bg-yellow-900 dark:text-yellow-300',
  4: 'bg-lime-100 text-lime-700 dark:bg-lime-900 dark:text-lime-300',
  5: 'bg-green-100 text-green-700 dark:bg-green-900 dark:text-green-300',
  6: 'bg-teal-100 text-teal-700 dark:bg-teal-900 dark:text-teal-300',
};


// =================================================================
// DOMAIN SECTION (collapsible group of permissions)
// =================================================================

interface DomainSectionProps {
  domain: string;
  rows: Array<{ permission_key: string; hat_values: Record<number, boolean> }>;
  hats: Array<{ id: number; name: string; level: number }>;
  canManage: boolean;
  onToggle: (hatId: number, permKey: string, enabled: boolean) => void;
  savingKey: string | null;
}

function DomainSection({ domain, rows, hats, canManage, onToggle, savingKey }: DomainSectionProps) {
  const [collapsed, setCollapsed] = useState(false);

  // Count how many permissions are enabled across all hats for this domain
  const totalEnabled = rows.reduce(
    (sum, row) => sum + Object.values(row.hat_values).filter(Boolean).length,
    0,
  );
  const totalPossible = rows.length * hats.length;

  return (
    <div className="mb-4">
      {/* Domain header (clickable to collapse) */}
      <button
        onClick={() => setCollapsed(prev => !prev)}
        className="flex items-center gap-2 w-full py-2 px-3 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-750 transition-colors text-left"
      >
        {collapsed
          ? <ChevronRight className="h-4 w-4 text-gray-400 dark:text-gray-500 flex-shrink-0" />
          : <ChevronDown className="h-4 w-4 text-gray-400 dark:text-gray-500 flex-shrink-0" />
        }
        <span className="text-sm font-semibold uppercase tracking-wider text-gray-700 dark:text-gray-300">
          {DOMAIN_LABELS[domain] ?? humanize(domain)}
        </span>
        <Badge variant="default" className="ml-auto">
          {totalEnabled}/{totalPossible}
        </Badge>
      </button>

      {/* Permission rows */}
      {!collapsed && (
        <div className="mt-1">
          {rows.map(row => (
            <div
              key={row.permission_key}
              className="flex items-center border-b border-gray-100 dark:border-gray-750 last:border-0"
            >
              {/* Sticky permission name column */}
              <div className="sticky left-0 z-10 bg-white dark:bg-gray-800 min-w-[180px] sm:min-w-[220px] px-3 py-2 flex items-center gap-2">
                <span className="text-sm text-gray-700 dark:text-gray-300 truncate">
                  {humanize(row.permission_key)}
                </span>
                {savingKey === row.permission_key && (
                  <Save className="h-3 w-3 text-primary-500 animate-pulse flex-shrink-0" />
                )}
              </div>

              {/* Hat checkboxes */}
              {hats.map(hat => (
                <div
                  key={hat.id}
                  className="flex-shrink-0 w-[80px] sm:w-[100px] flex items-center justify-center py-2"
                >
                  <input
                    type="checkbox"
                    checked={!!row.hat_values[hat.id]}
                    disabled={!canManage}
                    onChange={e => onToggle(hat.id, row.permission_key, e.target.checked)}
                    className="rounded border-gray-300 dark:border-gray-600 text-primary-600 focus:ring-primary-500 h-4 w-4 cursor-pointer disabled:cursor-default disabled:opacity-50"
                    title={`${hat.name}: ${row.permission_key}`}
                  />
                </div>
              ))}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}


// =================================================================
// MAIN PAGE
// =================================================================

export function PermissionsPage() {
  const { hasPermission } = useAuthStore();
  const canManage = hasPermission(PERMISSIONS.MANAGE_PEOPLE);
  const queryClient = useQueryClient();

  const [savingKey, setSavingKey] = useState<string | null>(null);

  // ── Queries ────────────────────────────────────────────────────
  const { data: matrix, isLoading: matrixLoading, error: matrixError } = useQuery({
    queryKey: ['people', 'permissions', 'matrix'],
    queryFn: getPermissionMatrix,
  });

  // Also fetch hats so we can build the full permission array for setHatPermissions
  const { data: hats } = useQuery({
    queryKey: ['people', 'hats'],
    queryFn: getHats,
  });

  // ── Permission toggle mutation ─────────────────────────────────
  const permMutation = useMutation({
    mutationFn: ({ hatId, keys }: { hatId: number; keys: string[] }) =>
      setHatPermissions(hatId, keys),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['people', 'permissions'] });
      queryClient.invalidateQueries({ queryKey: ['people', 'hats'] });
      setSavingKey(null);
    },
    onError: () => {
      setSavingKey(null);
    },
  });

  /**
   * Toggle a single permission for a hat.
   *
   * We need to build the full permissions array for the hat (adding or removing
   * the target key) and send it via the "replace all" endpoint.
   */
  const handleToggle = useCallback(
    (hatId: number, permKey: string, enabled: boolean) => {
      // Find the hat's current permissions from the hats query
      const hat = hats?.find(h => h.id === hatId);
      if (!hat) return;

      setSavingKey(permKey);
      const currentPerms = hat.permissions;
      const newPerms = enabled
        ? [...currentPerms, permKey]
        : currentPerms.filter(k => k !== permKey);

      permMutation.mutate({ hatId, keys: newPerms });
    },
    [hats, permMutation],
  );

  // ── Loading / Error ────────────────────────────────────────────
  if (matrixLoading) return <PageSpinner />;

  if (matrixError || !matrix) {
    return (
      <EmptyState
        icon={<Shield className="h-12 w-12" />}
        title="Failed to Load Permissions"
        description="Could not load the permission matrix. Please try refreshing the page."
      />
    );
  }

  // Sort hats by level (lowest = most authority first)
  const sortedHats = [...matrix.hats].sort((a, b) => a.level - b.level || a.name.localeCompare(b.name));

  return (
    <div>
      {/* Page header */}
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-gray-900 dark:text-gray-100">
          Permission Matrix
        </h1>
        <p className="text-sm text-gray-500 dark:text-gray-400 mt-1">
          {canManage
            ? 'Toggle checkboxes to grant or revoke permissions per role.'
            : 'View-only — you need manage_people permission to make changes.'
          }
        </p>
      </div>

      {/* Matrix card with horizontal scroll */}
      <Card noPadding>
        <div className="overflow-x-auto">
          {/* Hat column headers */}
          <div className="flex items-end border-b border-gray-200 dark:border-gray-700 bg-gray-50 dark:bg-gray-850 sticky top-0 z-20">
            {/* Empty cell for permission name column */}
            <div className="sticky left-0 z-30 bg-gray-50 dark:bg-gray-850 min-w-[180px] sm:min-w-[220px] px-3 py-3">
              <span className="text-xs font-medium uppercase tracking-wider text-gray-500 dark:text-gray-400">
                Permission
              </span>
            </div>

            {/* Hat column headers */}
            {sortedHats.map(hat => (
              <div
                key={hat.id}
                className="flex-shrink-0 w-[80px] sm:w-[100px] px-1 py-3 text-center"
              >
                <div className="flex items-center justify-center mb-1">
                  <Crown className="h-3.5 w-3.5 text-primary-500 dark:text-primary-400" />
                </div>
                <p className="text-xs font-medium text-gray-900 dark:text-gray-100 leading-tight truncate px-1">
                  {hat.name}
                </p>
                <span className={`inline-flex items-center px-1.5 py-0.5 rounded-full text-[10px] font-medium mt-1 ${LEVEL_COLORS[hat.level] ?? LEVEL_COLORS[6]}`}>
                  L{hat.level}
                </span>
              </div>
            ))}
          </div>

          {/* Domain sections */}
          <div className="py-2">
            {DOMAIN_ORDER
              .filter(domain => matrix.domains[domain]?.length > 0)
              .map(domain => (
                <DomainSection
                  key={domain}
                  domain={domain}
                  rows={matrix.domains[domain]}
                  hats={sortedHats}
                  canManage={canManage}
                  onToggle={handleToggle}
                  savingKey={savingKey}
                />
              ))
            }

            {/* Any remaining domains not in DOMAIN_ORDER */}
            {Object.entries(matrix.domains)
              .filter(([domain]) => !DOMAIN_ORDER.includes(domain))
              .map(([domain, rows]) => (
                <DomainSection
                  key={domain}
                  domain={domain}
                  rows={rows}
                  hats={sortedHats}
                  canManage={canManage}
                  onToggle={handleToggle}
                  savingKey={savingKey}
                />
              ))
            }
          </div>
        </div>
      </Card>

      {/* Legend */}
      <div className="mt-4 flex flex-wrap gap-3 text-xs text-gray-500 dark:text-gray-400">
        <span className="flex items-center gap-1.5">
          <input type="checkbox" checked readOnly className="rounded border-gray-300 text-primary-600 h-3 w-3" />
          Permission granted
        </span>
        <span className="flex items-center gap-1.5">
          <input type="checkbox" readOnly className="rounded border-gray-300 h-3 w-3" />
          Permission denied
        </span>
        {!canManage && (
          <Badge variant="warning">Read-only mode</Badge>
        )}
      </div>
    </div>
  );
}
