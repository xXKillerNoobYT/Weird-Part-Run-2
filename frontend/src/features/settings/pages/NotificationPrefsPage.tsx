/**
 * NotificationPrefsPage — manage notification preferences.
 *
 * Users opt into notification types they want to receive.
 * Defaults are OFF — users must explicitly enable categories.
 * Preferences are per-user and stored in the notification_preferences table.
 */

import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Bell, BellOff, Save, Check } from 'lucide-react';
import { useState, useEffect } from 'react';
import {
  getNotificationPreferences,
  updateNotificationPreferences,
} from '../../../api/notifications';
import type { NotificationPreference } from '../../../lib/types';

/** Known notification types with human-friendly labels and descriptions */
const NOTIFICATION_TYPES: {
  type: string;
  label: string;
  description: string;
  category: string;
}[] = [
  // Orders & Procurement
  {
    type: 'jpo_submitted',
    label: 'Parts Request Submitted',
    description: 'When a field worker submits a new parts request for approval.',
    category: 'Orders',
  },
  {
    type: 'jpo_approved',
    label: 'Parts Request Approved',
    description: 'When your parts request is approved by a manager.',
    category: 'Orders',
  },
  {
    type: 'jpo_rejected',
    label: 'Parts Request Rejected',
    description: 'When your parts request is rejected.',
    category: 'Orders',
  },
  {
    type: 'po_submitted',
    label: 'Purchase Order Submitted',
    description: 'When a PO is submitted to a supplier.',
    category: 'Orders',
  },
  {
    type: 'po_acknowledged',
    label: 'PO Acknowledged by Supplier',
    description: 'When a supplier acknowledges receipt of a PO.',
    category: 'Orders',
  },
  {
    type: 'po_shipped',
    label: 'Shipment Notification',
    description: 'When a supplier marks items as shipped.',
    category: 'Orders',
  },
  {
    type: 'po_received',
    label: 'Items Received',
    description: 'When ordered items are received at the warehouse.',
    category: 'Orders',
  },

  // Inventory
  {
    type: 'low_stock',
    label: 'Low Stock Alert',
    description: 'When a part drops below its reorder point.',
    category: 'Inventory',
  },
  {
    type: 'reorder_suggestion',
    label: 'Reorder Suggestions',
    description: 'Weekly summary of parts that need reordering.',
    category: 'Inventory',
  },

  // Returns
  {
    type: 'return_submitted',
    label: 'Return Submitted',
    description: 'When a return is submitted for approval.',
    category: 'Returns',
  },
  {
    type: 'return_approved',
    label: 'Return Approved',
    description: 'When your return is approved.',
    category: 'Returns',
  },

  // Jobs
  {
    type: 'job_status_change',
    label: 'Job Status Changes',
    description: 'When a job you\'re assigned to changes status.',
    category: 'Jobs',
  },
];

export function NotificationPrefsPage() {
  const queryClient = useQueryClient();
  const [saved, setSaved] = useState(false);

  // Fetch current preferences
  const { data: prefData, isLoading } = useQuery({
    queryKey: ['notification-preferences'],
    queryFn: getNotificationPreferences,
  });

  // Build local state from fetched preferences
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
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold text-gray-900 dark:text-gray-100">
            Notification Preferences
          </h1>
          <p className="text-sm text-gray-500 dark:text-gray-400 mt-1">
            Choose which notifications you want to receive. All notifications are off by default.
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
              Saved!
            </>
          ) : (
            <>
              <Save className="h-4 w-4" />
              Save Preferences
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
                const isEnabled = localPrefs[notifType.type] ?? false;

                return (
                  <label
                    key={notifType.type}
                    className="flex items-center justify-between px-4 py-3 hover:bg-surface-secondary/50 transition-colors cursor-pointer"
                  >
                    <div className="flex items-center gap-3">
                      {isEnabled ? (
                        <Bell className="h-4 w-4 text-primary flex-shrink-0" />
                      ) : (
                        <BellOff className="h-4 w-4 text-gray-300 dark:text-gray-600 flex-shrink-0" />
                      )}
                      <div>
                        <p className="text-sm font-medium text-gray-900 dark:text-gray-100">
                          {notifType.label}
                        </p>
                        <p className="text-xs text-gray-500 dark:text-gray-400">
                          {notifType.description}
                        </p>
                      </div>
                    </div>

                    {/* Toggle switch */}
                    <button
                      type="button"
                      role="switch"
                      aria-checked={isEnabled}
                      onClick={() => toggle(notifType.type)}
                      className={`relative inline-flex h-6 w-11 flex-shrink-0 rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none focus:ring-2 focus:ring-primary focus:ring-offset-2 ${
                        isEnabled
                          ? 'bg-primary'
                          : 'bg-gray-200 dark:bg-gray-700'
                      }`}
                    >
                      <span
                        className={`pointer-events-none inline-block h-5 w-5 rounded-full bg-white shadow ring-0 transition-transform duration-200 ease-in-out ${
                          isEnabled ? 'translate-x-5' : 'translate-x-0'
                        }`}
                      />
                    </button>
                  </label>
                );
              }
            )}
          </div>
        </div>
      ))}
    </div>
  );
}
