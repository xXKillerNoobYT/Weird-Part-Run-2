/**
 * ManageBillRateTypesModal — boss-customizable list of billing categories.
 *
 * CRUD modal for bill rate types (e.g. "Construction", "Bid", "Emergency").
 * Accessible from the Manage Jobs page header.
 */

import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Plus, Pencil, Trash2, X, Check } from 'lucide-react';
import { Modal } from '../../../components/ui/Modal';
import { Button } from '../../../components/ui/Button';
import { Input } from '../../../components/ui/Input';
import { Badge } from '../../../components/ui/Badge';
import {
  getBillRateTypes, createBillRateType,
  updateBillRateType, deleteBillRateType,
} from '../../../api/jobs';

interface ManageBillRateTypesModalProps {
  isOpen: boolean;
  onClose: () => void;
}

export function ManageBillRateTypesModal({ isOpen, onClose }: ManageBillRateTypesModalProps) {
  const queryClient = useQueryClient();

  const { data: types, isLoading } = useQuery({
    queryKey: ['bill-rate-types', false],
    queryFn: () => getBillRateTypes(false),
    enabled: isOpen,
  });

  // Add form
  const [showAdd, setShowAdd] = useState(false);
  const [newName, setNewName] = useState('');
  const [newDesc, setNewDesc] = useState('');

  // Edit state
  const [editingId, setEditingId] = useState<number | null>(null);
  const [editName, setEditName] = useState('');
  const [editDesc, setEditDesc] = useState('');

  const [errorMsg, setErrorMsg] = useState('');

  const invalidate = () => {
    queryClient.invalidateQueries({ queryKey: ['bill-rate-types'] });
  };

  const createMutation = useMutation({
    mutationFn: () => createBillRateType({ name: newName.trim(), description: newDesc.trim() || undefined }),
    onSuccess: () => {
      invalidate();
      setNewName('');
      setNewDesc('');
      setShowAdd(false);
      setErrorMsg('');
    },
    onError: (err: Error) => setErrorMsg(err.message || 'Failed to create'),
  });

  const updateMutation = useMutation({
    mutationFn: ({ id, data }: { id: number; data: Parameters<typeof updateBillRateType>[1] }) =>
      updateBillRateType(id, data),
    onSuccess: () => {
      invalidate();
      setEditingId(null);
      setErrorMsg('');
    },
    onError: (err: Error) => setErrorMsg(err.message || 'Failed to update'),
  });

  const deleteMutation = useMutation({
    mutationFn: (id: number) => deleteBillRateType(id),
    onSuccess: () => {
      invalidate();
      setErrorMsg('');
    },
    onError: (err: Error) => setErrorMsg(err.message || 'Failed to delete'),
  });

  const startEdit = (type: { id: number; name: string; description?: string | null }) => {
    setEditingId(type.id);
    setEditName(type.name);
    setEditDesc(type.description ?? '');
  };

  const saveEdit = () => {
    if (!editName.trim() || editingId === null) return;
    updateMutation.mutate({
      id: editingId,
      data: { name: editName.trim(), description: editDesc.trim() || undefined },
    });
  };

  return (
    <Modal isOpen={isOpen} onClose={onClose} title="Bill Rate Types" size="md">
      <p className="text-sm text-gray-500 dark:text-gray-400 mb-4">
        Manage the billing categories available when creating or editing jobs.
      </p>

      {errorMsg && (
        <div className="mb-3 p-2 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded text-sm text-red-600 dark:text-red-400">
          {errorMsg}
        </div>
      )}

      {/* Existing types list */}
      <div className="space-y-2 mb-4">
        {isLoading ? (
          <p className="text-sm text-gray-500 py-4 text-center">Loading...</p>
        ) : !types?.length ? (
          <p className="text-sm text-gray-500 py-4 text-center">No bill rate types yet.</p>
        ) : (
          types.map((t) => (
            <div
              key={t.id}
              className="flex items-center gap-2 p-2.5 bg-surface border border-border rounded-lg group"
            >
              {editingId === t.id ? (
                /* Edit mode */
                <div className="flex-1 flex items-center gap-2">
                  <Input
                    value={editName}
                    onChange={(e) => setEditName(e.target.value)}
                    placeholder="Type name"
                    className="flex-1"
                  />
                  <button
                    onClick={saveEdit}
                    className="p-1.5 rounded text-green-500 hover:bg-green-50 dark:hover:bg-green-900/30"
                    title="Save"
                  >
                    <Check className="h-4 w-4" />
                  </button>
                  <button
                    onClick={() => setEditingId(null)}
                    className="p-1.5 rounded text-gray-400 hover:bg-gray-100 dark:hover:bg-gray-800"
                    title="Cancel"
                  >
                    <X className="h-4 w-4" />
                  </button>
                </div>
              ) : (
                /* Display mode */
                <>
                  <span className={`flex-1 text-sm font-medium ${
                    t.is_active
                      ? 'text-gray-900 dark:text-gray-100'
                      : 'text-gray-400 dark:text-gray-500 line-through'
                  }`}>
                    {t.name}
                  </span>
                  {t.description && (
                    <span className="text-xs text-gray-400 dark:text-gray-500 truncate max-w-[120px]">
                      {t.description}
                    </span>
                  )}
                  {!t.is_active && (
                    <Badge variant="default">Inactive</Badge>
                  )}
                  <div className="flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
                    <button
                      onClick={() => startEdit(t)}
                      className="p-1 rounded text-gray-400 hover:text-blue-500 hover:bg-blue-50 dark:hover:bg-blue-900/30"
                      title="Edit"
                    >
                      <Pencil className="h-3.5 w-3.5" />
                    </button>
                    {t.is_active ? (
                      <button
                        onClick={() => deleteMutation.mutate(t.id)}
                        className="p-1 rounded text-gray-400 hover:text-red-500 hover:bg-red-50 dark:hover:bg-red-900/30"
                        title="Deactivate"
                      >
                        <Trash2 className="h-3.5 w-3.5" />
                      </button>
                    ) : (
                      <button
                        onClick={() => updateMutation.mutate({ id: t.id, data: { is_active: true } })}
                        className="p-1 rounded text-gray-400 hover:text-green-500 hover:bg-green-50 dark:hover:bg-green-900/30"
                        title="Reactivate"
                      >
                        <Check className="h-3.5 w-3.5" />
                      </button>
                    )}
                  </div>
                </>
              )}
            </div>
          ))
        )}
      </div>

      {/* Add new type */}
      {showAdd ? (
        <div className="p-3 bg-surface-secondary rounded-lg border border-border space-y-2">
          <Input
            label="Type Name"
            value={newName}
            onChange={(e) => setNewName(e.target.value)}
            placeholder="e.g. Time & Material"
            autoFocus
          />
          <Input
            label="Description (optional)"
            value={newDesc}
            onChange={(e) => setNewDesc(e.target.value)}
            placeholder="Brief description..."
          />
          <div className="flex justify-end gap-2">
            <Button variant="secondary" size="sm" onClick={() => { setShowAdd(false); setNewName(''); setNewDesc(''); }}>
              Cancel
            </Button>
            <Button
              size="sm"
              onClick={() => newName.trim() && createMutation.mutate()}
              isLoading={createMutation.isPending}
            >
              Add Type
            </Button>
          </div>
        </div>
      ) : (
        <Button
          variant="secondary"
          size="sm"
          icon={<Plus className="h-4 w-4" />}
          onClick={() => setShowAdd(true)}
          className="w-full"
        >
          Add Bill Rate Type
        </Button>
      )}
    </Modal>
  );
}
