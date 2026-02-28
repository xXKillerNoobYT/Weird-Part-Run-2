/**
 * PermissionGrantModal — select a user to grant delegated edit access.
 *
 * Shows a simple user selector. In the future this could pull
 * from the crew/labor list, but for now takes a userId input.
 */

import { useState } from 'react';
import { X, Shield } from 'lucide-react';

interface PermissionGrantModalProps {
  entryTitle: string;
  onGrant: (userId: number) => void;
  onClose: () => void;
  loading?: boolean;
}

export function PermissionGrantModal({
  entryTitle,
  onGrant,
  onClose,
  loading,
}: PermissionGrantModalProps) {
  const [userId, setUserId] = useState('');

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    const id = parseInt(userId, 10);
    if (isNaN(id) || id <= 0) return;
    onGrant(id);
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
      <div className="bg-surface border border-border rounded-xl shadow-xl w-full max-w-sm mx-4">
        {/* Header */}
        <div className="flex items-center gap-3 px-5 py-4 border-b border-border">
          <div className="p-2 bg-purple-50 dark:bg-purple-900/20 rounded-lg">
            <Shield className="h-4 w-4 text-purple-500" />
          </div>
          <div className="flex-1 min-w-0">
            <h2 className="text-base font-semibold text-gray-900 dark:text-gray-100">
              Grant Edit Access
            </h2>
            <p className="text-xs text-gray-500 dark:text-gray-400 truncate">
              {entryTitle}
            </p>
          </div>
          <button
            onClick={onClose}
            className="p-1 rounded-lg hover:bg-surface-secondary transition-colors"
          >
            <X className="h-4 w-4 text-gray-400" />
          </button>
        </div>

        <form onSubmit={handleSubmit} className="p-5 space-y-4">
          <div>
            <label className="block text-xs font-medium text-gray-700 dark:text-gray-300 mb-1">
              User ID
            </label>
            <input
              type="number"
              value={userId}
              onChange={(e) => setUserId(e.target.value)}
              placeholder="Enter user ID..."
              className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
              autoFocus
              min="1"
              required
            />
            <p className="text-[11px] text-gray-400 dark:text-gray-500 mt-1">
              The user will be able to edit this entry
            </p>
          </div>

          <div className="flex justify-end gap-2 pt-2">
            <button
              type="button"
              onClick={onClose}
              className="px-4 py-2 text-sm font-medium text-gray-600 dark:text-gray-400 hover:text-gray-800 dark:hover:text-gray-200 rounded-lg hover:bg-surface-secondary transition-colors"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={!userId || loading}
              className="px-4 py-2 text-sm font-medium text-white bg-purple-500 hover:bg-purple-600 disabled:opacity-50 disabled:cursor-not-allowed rounded-lg transition-colors"
            >
              {loading ? 'Granting...' : 'Grant Access'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
