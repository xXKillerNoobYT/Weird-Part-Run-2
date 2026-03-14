/**
 * NewDMDialog — modal for selecting a user to start a direct message conversation.
 *
 * Fetches the employee list, lets the user search/pick a recipient,
 * then calls createDMChannel and hands back the new channel ID.
 */

import { useState, useMemo } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { X, Search, MessageSquare, Loader2 } from 'lucide-react';
import { getEmployees } from '../../../api/people';
import { createDMChannel } from '../../../api/chat';
import { useAuthStore } from '../../../stores/auth-store';

interface NewDMDialogProps {
  open: boolean;
  onClose: () => void;
  onCreated: (channelId: number) => void;
}

export function NewDMDialog({ open, onClose, onCreated }: NewDMDialogProps) {
  const { user } = useAuthStore();
  const queryClient = useQueryClient();
  const [search, setSearch] = useState('');

  // Fetch all active employees
  const { data: employeeData, isLoading } = useQuery({
    queryKey: ['employees', 'dm-picker'],
    queryFn: () => getEmployees({ is_active: true, page_size: 200 }),
    enabled: open,
    staleTime: 60_000,
  });

  const employees = useMemo(() => {
    const all = employeeData?.items ?? [];
    // Exclude current user
    return all.filter((e) => e.id !== user?.id);
  }, [employeeData, user?.id]);

  const filtered = useMemo(() => {
    if (!search.trim()) return employees;
    const q = search.toLowerCase();
    return employees.filter((e) => {
      const name = (e.display_name || '').toLowerCase();
      const hat = (e.hat_names?.join(' ') || '').toLowerCase();
      return name.includes(q) || hat.includes(q);
    });
  }, [employees, search]);

  // Create DM mutation
  const createMutation = useMutation({
    mutationFn: (userId: number) => createDMChannel([userId]),
    onSuccess: (channel) => {
      queryClient.invalidateQueries({ queryKey: ['chat-inbox'] });
      onCreated(channel.id);
      onClose();
      setSearch('');
    },
  });

  if (!open) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center">
      {/* Backdrop */}
      <div
        className="absolute inset-0 bg-black/50"
        onClick={onClose}
      />

      {/* Dialog */}
      <div className="relative bg-white dark:bg-gray-900 rounded-xl shadow-xl w-full max-w-md mx-4 max-h-[80vh] flex flex-col">
        {/* Header */}
        <div className="flex items-center justify-between p-4 border-b border-border">
          <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-100">
            New Message
          </h2>
          <button
            onClick={onClose}
            className="p-1.5 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-800"
          >
            <X className="h-5 w-5 text-gray-400" />
          </button>
        </div>

        {/* Search */}
        <div className="p-4 border-b border-border">
          <div className="relative">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-gray-400" />
            <input
              type="text"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Search people..."
              autoFocus
              className="w-full pl-9 pr-3 py-2.5 text-sm rounded-lg border border-border bg-surface-secondary text-gray-900 dark:text-gray-100 placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-primary-500"
            />
          </div>
        </div>

        {/* User list */}
        <div className="flex-1 overflow-y-auto min-h-0">
          {isLoading ? (
            <div className="flex items-center justify-center py-12">
              <Loader2 className="h-6 w-6 animate-spin text-gray-400" />
            </div>
          ) : filtered.length === 0 ? (
            <div className="text-center py-12 text-sm text-gray-400">
              {search ? 'No matching people' : 'No employees found'}
            </div>
          ) : (
            filtered.map((emp) => (
              <button
                key={emp.id}
                onClick={() => createMutation.mutate(emp.id)}
                disabled={createMutation.isPending}
                className="w-full flex items-center gap-3 px-4 py-3 text-left hover:bg-gray-50 dark:hover:bg-gray-800 transition-colors disabled:opacity-50"
              >
                {/* Avatar */}
                <div className="flex-shrink-0 w-10 h-10 rounded-full bg-primary-100 dark:bg-primary-900/30 flex items-center justify-center">
                  <span className="text-sm font-semibold text-primary-700 dark:text-primary-300">
                    {getInitials(emp.display_name)}
                  </span>
                </div>

                {/* Name + role */}
                <div className="flex-1 min-w-0">
                  <p className="text-sm font-medium text-gray-900 dark:text-gray-100 truncate">
                    {emp.display_name}
                  </p>
                  {emp.hat_names?.length > 0 && (
                    <p className="text-xs text-gray-500 dark:text-gray-400 truncate">
                      {emp.hat_names.join(', ')}
                    </p>
                  )}
                </div>

                {/* Action hint */}
                <MessageSquare className="h-4 w-4 text-gray-300 dark:text-gray-600 flex-shrink-0" />
              </button>
            ))
          )}
        </div>

        {/* Error */}
        {createMutation.isError && (
          <div className="px-4 py-2 bg-red-50 dark:bg-red-950/30 text-xs text-red-600 dark:text-red-400 border-t border-border">
            Failed to create conversation. Please try again.
          </div>
        )}
      </div>
    </div>
  );
}

function getInitials(name: string | undefined): string {
  if (!name) return '?';
  return name
    .split(' ')
    .map((w) => w[0])
    .filter(Boolean)
    .slice(0, 2)
    .join('')
    .toUpperCase();
}
