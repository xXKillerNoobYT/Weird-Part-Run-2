/**
 * NotificationPrefsPage — manage notification preferences.
 *
 * Notifications default to ON — users opt out of categories they don't want.
 * If a user's hat/role doesn't grant the required permission for a notification
 * type, that toggle is locked off and greyed out.
 *
 * Preferences are per-user and stored in the notification_preferences table.
 */

import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Bell, BellOff, Lock, Save, Check } from 'lucide-react';
import { useState, useEffect } from 'react';
import {
  getNotificationPreferences,
  updateNotificationPreferences,
} from '../../../api/notifications';
import type { NotificationPreference } from '../../../lib/types';
import { useAuthStore } from '../../../stores/auth-store';

/**
 * Known notification types with human-friendly labels, descriptions,
 * and the permission required to receive them.
 *
 * If `requiredPermission` is null, every user can receive that notification.
 * If set, the user's hat must grant that permission — otherwise the toggle
 * is locked off.
 */
const NOTIFICATION_TYPES: {
  type: string;
  label: string;
  description: string;
  category: string;
  requiredPermission: string | null;
}[] = [
  // Orders & Procurement
  {
    type: 'jpo_submitted',
    label: 'Parts Request Submitted',
    description: 'When a field worker submits a new parts request for approval.',
    category: 'Orders',
    requiredPermission: 'manage_orders',
  },
  {
    type: 'jpo_approved',
    label: 'Parts Request Approved',
    description: 'When your parts request is approved by a manager.',
    category: 'Orders',
    requiredPermission: null,
  },
  {
    type: 'jpo_rejected',
    label: 'Parts Request Rejected',
    description: 'When your parts request is rejected.',
    category: 'Orders',
    requiredPermission: null,
  },
  {
    type: 'po_submitted',
    label: 'Purchase Order Submitted',
    description: 'When a PO is submitted to a supplier.',
    category: 'Orders',
    requiredPermission: 'manage_orders',
  },
  {
    type: 'po_acknowledged',
    label: 'PO Acknowledged by Supplier',
    description: 'When a supplier acknowledges receipt of a PO.',
    category: 'Orders',
    requiredPermission: 'manage_orders',
  },
  {
    type: 'po_shipped',
    label: 'Shipment Notification',
    description: 'When a supplier marks items as shipped.',
    category: 'Orders',
    requiredPermission: 'manage_orders',
  },
  {
    type: 'po_received',
    label: 'Items Received',
    description: 'When ordered items are received at the warehouse.',
    category: 'Orders',
    requiredPermission: 'manage_warehouse',
  },

  // Inventory
  {
    type: 'low_stock',
    label: 'Low Stock Alert',
    description: 'When a part drops below its reorder point.',
    category: 'Inventory',
    requiredPermission: 'manage_warehouse',
  },
  {
    type: 'reorder_suggestion',
    label: 'Reorder Suggestions',
    description: 'Weekly summary of parts that need reordering.',
    category: 'Inventory',
    requiredPermission: 'manage_warehouse',
  },

  // Returns
  {
    type: 'return_submitted',
    label: 'Return Submitted',
    description: 'When a return is submitted for approval.',
    category: 'Returns',
    requiredPermission: 'manage_orders',
  },
  {
    type: 'return_approved',
    label: 'Return Approved',
    description: 'When your return is approved.',
    category: 'Returns',
    requiredPermission: null,
  },

  // Jobs
  {
    type: 'job_status_change',
    label: 'Job Status Changes',
    description: "When a job you're assigned to changes status.",
    category: 'Jobs',
    requiredPermission: null,
  },
];

export function NotificationPrefsPage() {
  const queryClient = useQueryClient();
  const [saved, setSaved] = useState(false);
  const { hasPermission } = useAuthStore();

  // Fetch current preferences
  const { data: prefData, isLoading } = useQuery({
    queryKey: ['notification-preferences'],
    queryFn: getNotificationPreferences,
  });

  // Build local state from fetched preferences — default is ON (opt-out)
  const [localPrefs, setLocalPrefs] = useState<Record<string, boolean>>({});

  useEffect(() => {
    if (prefData?.preferences) {
      const map: Record<string, boolean> = {};
      for (const p of prefData.preferences) {
        map[p.notification_type] = p.is_enabled;
      }
      setLocalPrefs(map);
    }
  }, [prefData]);

  const toggle = (type: string) => {
    setLocalPrefs((prev) => ({ ...prev, [type]: !prev[type] }));
  };

  const saveMutation = useMutation({
    mutationFn: () => {
      const prefs: NotificationPreference[] = Object.entries(localPrefs).map(
        ([notification_type, is_enabled]) => ({
          notification_type,
          is_enabled,
        })
      );
      return updateNotificationPreferences(prefs);
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['notification-preferences'] });
      setSaved(true);
      setTimeout(() => setSaved(false), 2500);
    },
  });

  // Group by category
  const categories = Array.from(
    new Set(NOTIFICATION_TYPES.map((t) => t.category))
  );

  if (isLoading) {
    return (
      <div className="flex justify-center py-12">
        <div className="h-8 w-8 animate-spin rounded-full border-4 border-primary border-t-transparent" />
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div>
          <h1 className="text-xl font-semibold text-gray-900 dark:text-gray-100">
            Notification Preferences
          </h1>
          <p className="text-sm text-gray-500 dark:text-gray-400 mt-1">
            All notifications are enabled by default. Toggle off any you don't need.
          </p>
        </div>
        <button
          onClick={() => saveMutation.mutate()}
          disabled={saveMutation.isPending}
          className="inline-flex items-center gap-2 rounded-lg bg-primary px-4 py-2 text-sm font-medium text-white shadow-sm hover:bg-primary/90 transition-colors disabled:opacity-50"
        >
          {saved ? (
            <>
              <Check className="h-4 w-4" />
              <span className="hidden sm:inline">Saved!</span>
            </>
          ) : (
            <>
              <Save className="h-4 w-4" />
              <span className="hidden sm:inline">Save Preferences</span>
            </>
          )}
        </button>
      </div>

      {categories.map((category) => (
        <div key={category} className="rounded-lg border border-border bg-surface">
          <div className="border-b border-border bg-surface-secondary px-4 py-3">
            <h2 className="text-sm font-semibold text-gray-900 dark:text-gray-100">
              {category}
            </h2>
          </div>
          <div className="divide-y divide-border">
            {NOTIFICATION_TYPES.filter((t) => t.category === category).map(
              (notifType) => {
                // Check if user's hat qualifies for this notification
                const hasRequiredPerm =
                  notifType.requiredPermission === null ||
                  hasPermission(notifType.requiredPermission);

                // Default ON when no stored preference (opt-out model)
                const isEnabled = hasRequiredPerm
                  ? (localPrefs[notifType.type] ?? true)
                  : false;

                return (
                  <div
                    key={notifType.type}
                    className={`flex items-center justify-between px-4 py-3 transition-colors ${
                      hasRequiredPerm
                        ? 'hover:bg-surface-secondary/50 cursor-pointer'
                        : 'opacity-50 cursor-not-allowed'
                    }`}
                    onClick={hasRequiredPerm ? () => toggle(notifType.type) : undefined}
                  >
                    <div className="flex items-center gap-3">
                      {!hasRequiredPerm ? (
                        <Lock className="h-4 w-4 text-gray-300 dark:text-gray-600 flex-shrink-0" />
                      ) : isEnabled ? (
                        <Bell className="h-4 w-4 text-green-500 dark:text-green-400 flex-shrink-0" />
                      ) : (
                        <BellOff className="h-4 w-4 text-red-400 dark:text-red-500 flex-shrink-0" />
                      )}
                      <div>
                        <p className="text-sm font-medium text-gray-900 dark:text-gray-100">
                          {notifType.label}
                        </p>
                        <p className="text-xs text-gray-500 dark:text-gray-400">
                          {notifType.description}
                        </p>
                        {!hasRequiredPerm && (
                          <p className="text-xs text-amber-600 dark:text-amber-400 mt-0.5">
                            Requires {notifType.requiredPermission?.replace(/_/g, ' ')} permission
                          </p>
                        )}
                      </div>
                    </div>

                    {/* Toggle switch — locked if no permission */}
                    <button
                      type="button"
                      role="switch"
                      aria-checked={isEnabled}
                      disabled={!hasRequiredPerm}
                      onClick={(e) => {
                        e.stopPropagation();
                        if (hasRequiredPerm) toggle(notifType.type);
                      }}
                      className={`relative inline-flex h-6 w-11 flex-shrink-0 rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none focus:ring-2 focus:ring-primary focus:ring-offset-2 ${
                        !hasRequiredPerm
                          ? 'bg-gray-200 dark:bg-gray-700 cursor-not-allowed'
                          : isEnabled
                            ? 'bg-green-500 dark:bg-green-600'
                            : 'bg-red-400 dark:bg-red-500'
                      }`}
                    >
                      <span
                        className={`pointer-events-none inline-block h-5 w-5 rounded-full bg-white shadow ring-0 transition-transform duration-200 ease-in-out ${
                          isEnabled ? 'translate-x-5' : 'translate-x-0'
                        }`}
                      />
                    </button>
                  </div>
                );
              }
            )}
          </div>
        </div>
      ))}
    </div>
  );
}
