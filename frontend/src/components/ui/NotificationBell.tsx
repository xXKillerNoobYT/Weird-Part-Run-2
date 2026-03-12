/**
 * NotificationBell — bell icon with unread count badge + dropdown.
 *
 * Polls the notification badge endpoint for the unread count.
 * Clicking opens a dropdown with recent notifications. Each
 * notification links to the relevant entity (JPO, PO, part, etc.).
 *
 * Auto-refreshes every 60 seconds to keep the count current.
 *
 * Phase 7E: Added sound alert support. When new unread notifications
 * arrive and the user has sound enabled for any notification type,
 * plays a chime. Respects browser audio policies (requires prior
 * user interaction before audio can play).
 */

import { useState, useRef, useEffect, useCallback } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Link } from 'react-router-dom';
import { Bell, Check, Volume2, VolumeX } from 'lucide-react';
import {
  getNotificationBadge,
  listNotifications,
  markNotificationsRead,
  getNotificationSoundSettings,
} from '../../api/notifications';
import type { NotificationResponse } from '../../lib/types';

import { playChime as playChimeSound } from '../../lib/chime';

export function NotificationBell() {
  const [open, setOpen] = useState(false);
  const dropdownRef = useRef<HTMLDivElement>(null);
  const queryClient = useQueryClient();

  // Track previous unread count to detect new notifications
  const prevCountRef = useRef<number | null>(null);
  // Track if user has interacted (required for audio autoplay policy)
  const [userInteracted, setUserInteracted] = useState(false);

  // Register user interaction on first click anywhere
  useEffect(() => {
    function handleInteraction() {
      setUserInteracted(true);
      document.removeEventListener('click', handleInteraction);
      document.removeEventListener('keydown', handleInteraction);
    }
    document.addEventListener('click', handleInteraction);
    document.addEventListener('keydown', handleInteraction);
    return () => {
      document.removeEventListener('click', handleInteraction);
      document.removeEventListener('keydown', handleInteraction);
    };
  }, []);

  // Badge count — polls every 60s
  const { data: badge } = useQuery({
    queryKey: ['notifications', 'badge'],
    queryFn: getNotificationBadge,
    refetchInterval: 60_000,
  });

  // Sound settings — cached, refetch rarely
  const { data: soundSettings } = useQuery({
    queryKey: ['notifications', 'sound-settings'],
    queryFn: getNotificationSoundSettings,
    staleTime: 5 * 60_000, // 5 min cache
  });

  // Check if ANY sound is enabled
  const anySoundEnabled = soundSettings?.settings?.some(s => s.sound_enabled) ?? false;

  // Play chime when new notifications arrive
  const playChime = useCallback(() => {
    if (!userInteracted || !anySoundEnabled) return;
    playChimeSound(0.5).catch(() => {
      // Browser blocked autoplay — silently ignore
    });
  }, [userInteracted, anySoundEnabled]);

  // Detect unread count increase → play sound
  useEffect(() => {
    const currentCount = badge?.unread_count ?? 0;
    if (prevCountRef.current !== null && currentCount > prevCountRef.current) {
      playChime();
    }
    prevCountRef.current = currentCount;
  }, [badge?.unread_count, playChime]);

  // Recent notifications (only fetched when dropdown opens)
  const { data: notifData } = useQuery({
    queryKey: ['notifications', 'list'],
    queryFn: () => listNotifications({ limit: 10, unread_only: true }),
    enabled: open,
  });

  const markReadMutation = useMutation({
    mutationFn: (ids: number[]) => markNotificationsRead({ notification_ids: ids }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['notifications'] });
    },
  });

  // Close dropdown on outside click
  useEffect(() => {
    function handleClick(e: PointerEvent | MouseEvent) {
      if (dropdownRef.current && !dropdownRef.current.contains(e.target as Node)) {
        setOpen(false);
      }
    }
    if (open) {
      document.addEventListener('pointerdown', handleClick);
      return () => document.removeEventListener('pointerdown', handleClick);
    }
  }, [open]);

  const unreadCount = badge?.unread_count ?? 0;
  const notifications: NotificationResponse[] = notifData?.items ?? [];

  const handleMarkAllRead = () => {
    const ids = notifications.filter((n) => !n.is_read).map((n) => n.id);
    if (ids.length > 0) {
      markReadMutation.mutate(ids);
    }
  };

  return (
    <div className="relative" ref={dropdownRef}>
      {/* Bell button */}
      <button
        onClick={() => setOpen(!open)}
        className="p-2 rounded-lg text-gray-500 hover:bg-gray-100 dark:text-gray-400 dark:hover:bg-gray-700 transition-colors relative min-h-[44px] min-w-[44px] flex items-center justify-center"
        title="Notifications"
      >
        <Bell className="h-5 w-5" />
        {unreadCount > 0 && (
          <span className="absolute -top-0.5 -right-0.5 flex h-4 min-w-[16px] items-center justify-center rounded-full bg-red-500 px-1 text-[10px] font-bold text-white">
            {unreadCount > 99 ? '99+' : unreadCount}
          </span>
        )}
      </button>

      {/* Dropdown */}
      {open && (
        <div className="absolute right-0 top-full mt-2 w-80 rounded-lg border border-border bg-surface shadow-lg z-50">
          {/* Header */}
          <div className="flex items-center justify-between border-b border-border px-4 py-3">
            <div className="flex items-center gap-2">
              <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100">
                Notifications
              </h3>
              {/* Sound indicator */}
              {anySoundEnabled ? (
                <Volume2 className="h-3.5 w-3.5 text-green-500" />
              ) : (
                <VolumeX className="h-3.5 w-3.5 text-gray-400 dark:text-gray-500" />
              )}
            </div>
            {notifications.length > 0 && (
              <button
                onClick={handleMarkAllRead}
                className="text-xs text-primary hover:underline"
              >
                Mark all read
              </button>
            )}
          </div>

          {/* List */}
          <div className="max-h-80 overflow-y-auto">
            {notifications.length === 0 ? (
              <div className="p-6 text-center text-sm text-gray-500 dark:text-gray-400">
                <Bell className="h-8 w-8 mx-auto mb-2 text-gray-300 dark:text-gray-600" />
                No unread notifications
              </div>
            ) : (
              <ul className="divide-y divide-border">
                {notifications.map((notif) => (
                  <li key={notif.id}>
                    <NotificationItem
                      notification={notif}
                      onMarkRead={() => markReadMutation.mutate([notif.id])}
                      onClose={() => setOpen(false)}
                    />
                  </li>
                ))}
              </ul>
            )}
          </div>

          {/* Footer */}
          <div className="border-t border-border p-2">
            <Link
              to="/settings/notifications"
              onClick={() => setOpen(false)}
              className="block w-full rounded-md py-2 text-center text-xs font-medium text-gray-500 dark:text-gray-400 hover:bg-surface-secondary transition-colors"
            >
              Notification Settings
            </Link>
          </div>
        </div>
      )}
    </div>
  );
}


function NotificationItem({
  notification,
  onMarkRead,
  onClose,
}: {
  notification: NotificationResponse;
  onMarkRead: () => void;
  onClose: () => void;
}) {
  const content = (
    <div className="flex items-start gap-3 px-4 py-3 hover:bg-surface-secondary/50 transition-colors group">
      {/* Unread indicator */}
      <div className="mt-1.5 flex-shrink-0">
        {!notification.is_read ? (
          <div className="h-2 w-2 rounded-full bg-primary" />
        ) : (
          <div className="h-2 w-2 rounded-full bg-transparent" />
        )}
      </div>

      {/* Content */}
      <div className="min-w-0 flex-1">
        <p className="text-sm font-medium text-gray-900 dark:text-gray-100 leading-tight">
          {notification.title}
        </p>
        {notification.message && (
          <p className="text-xs text-gray-500 dark:text-gray-400 mt-0.5 line-clamp-2">
            {notification.message}
          </p>
        )}
        <p className="text-xs text-gray-400 dark:text-gray-500 mt-1">
          {notification.created_at
            ? formatRelativeTime(new Date(notification.created_at))
            : ''}
        </p>
      </div>

      {/* Mark-read button */}
      {!notification.is_read && (
        <button
          onClick={(e) => {
            e.preventDefault();
            e.stopPropagation();
            onMarkRead();
          }}
          className="flex p-2 rounded text-gray-400 hover:text-primary hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors flex-shrink-0"
          title="Mark as read"
        >
          <Check className="h-4 w-4" />
        </button>
      )}
    </div>
  );

  // Wrap in Link if notification has a deep link
  if (notification.link) {
    return (
      <Link to={notification.link} onClick={onClose}>
        {content}
      </Link>
    );
  }

  return content;
}


/** Simple relative time formatter */
function formatRelativeTime(date: Date): string {
  const now = new Date();
  const diffMs = now.getTime() - date.getTime();
  const diffMin = Math.floor(diffMs / 60000);

  if (diffMin < 1) return 'Just now';
  if (diffMin < 60) return `${diffMin}m ago`;

  const diffHours = Math.floor(diffMin / 60);
  if (diffHours < 24) return `${diffHours}h ago`;

  const diffDays = Math.floor(diffHours / 24);
  if (diffDays < 7) return `${diffDays}d ago`;

  return date.toLocaleDateString();
}
