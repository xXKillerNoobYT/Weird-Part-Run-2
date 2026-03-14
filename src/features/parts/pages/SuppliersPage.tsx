/**
 * SuppliersPage — manage supplier / parts house directory.
 *
 * This is the go-to reference for anyone who needs to contact a supplier,
 * whether from the office or in the field. Every supplier shows:
 *
 *  1. Business contact — main office phone, email (for returns, billing, general)
 *  2. Sales rep contact — the person you call for orders and quotes
 *  3. Delivery driver — the driver who physically brings the parts (for scheduled suppliers)
 *  4. Delivery method — how they get parts to you (shipping, scheduled, pickup)
 *  5. Delivery schedule — which days they deliver (for scheduled suppliers)
 *  6. Special order info — lead days for items not in local warehouse
 *  7. Reliability metrics — on-time rate, quality score, avg lead days
 *
 * Features:
 *  - Searchable table with expandable detail rows
 *  - Add / Edit / Delete with multi-section form modal
 *  - Inline active/inactive toggle
 *  - Delivery method badges with color coding
 *  - Click-to-call phone links and mailto email links
 */

import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Building2, Plus, Search, AlertTriangle } from 'lucide-react';
import { Button } from '../../../components/ui/Button';
import { Input } from '../../../components/ui/Input';
import { Modal } from '../../../components/ui/Modal';
import { Spinner } from '../../../components/ui/Spinner';
import { EmptyState } from '../../../components/ui/EmptyState';
import { useAuthStore } from '../../../stores/auth-store';
import { PERMISSIONS } from '../../../lib/constants';
import {
  listSuppliers, createSupplier, updateSupplier, deleteSupplier,
} from '../../../api/parts';
import type { Supplier, SupplierCreate, SupplierUpdate } from '../../../lib/types';

import { SupplierCard } from '../components/suppliers/SupplierCard';
import { SupplierFormModal } from '../components/suppliers/SupplierFormModal';


export function SuppliersPage() {
  const queryClient = useQueryClient();
  const { hasPermission } = useAuthStore();
  const canEdit = hasPermission(PERMISSIONS.EDIT_PARTS_CATALOG);

  // ── State ─────────────────────────────────────────
  const [searchText, setSearchText] = useState('');
  const [expandedId, setExpandedId] = useState<number | null>(null);
  const [isCreateOpen, setIsCreateOpen] = useState(false);
  const [editingSupplier, setEditingSupplier] = useState<Supplier | null>(null);
  const [deleteConfirm, setDeleteConfirm] = useState<Supplier | null>(null);

  // ── Query ─────────────────────────────────────────
  const { data: suppliers, isLoading, error } = useQuery({
    queryKey: ['suppliers', { search: searchText || undefined }],
    queryFn: () => listSuppliers({ search: searchText || undefined }),
  });

  // ── Mutations ─────────────────────────────────────
  const createMutation = useMutation({
    mutationFn: createSupplier,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['suppliers'] });
      setIsCreateOpen(false);
    },
  });

  const updateMutation = useMutation({
    mutationFn: ({ id, data }: { id: number; data: SupplierUpdate }) =>
      updateSupplier(id, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['suppliers'] });
      setEditingSupplier(null);
    },
  });

  const deleteMutation = useMutation({
    mutationFn: deleteSupplier,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['suppliers'] });
      setDeleteConfirm(null);
    },
  });

  const toggleActiveMutation = useMutation({
    mutationFn: ({ id, is_active }: { id: number; is_active: boolean }) =>
      updateSupplier(id, { is_active }),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['suppliers'] }),
  });

  const items = suppliers ?? [];

  return (
    <div className="space-y-4">
      {/* ── Header ───────────────────────────────── */}
      <div className="flex flex-col sm:flex-row gap-3 items-start sm:items-center justify-between">
        <div className="flex-1 w-full sm:max-w-md">
          <Input
            placeholder="Search suppliers, contacts, reps..."
            icon={<Search className="h-4 w-4" />}
            value={searchText}
            onChange={(e) => setSearchText(e.target.value)}
          />
        </div>
        {canEdit && (
          <Button
            size="sm"
            icon={<Plus className="h-4 w-4" />}
            onClick={() => setIsCreateOpen(true)}
          >
            Add Supplier
          </Button>
        )}
      </div>

      {/* ── Results summary ──────────────────────── */}
      <div className="text-sm text-gray-500 dark:text-gray-400">
        {isLoading ? 'Loading...' : `${items.length} supplier${items.length !== 1 ? 's' : ''}`}
      </div>

      {/* ── Supplier Cards ────────────────────────── */}
      {isLoading ? (
        <div className="flex justify-center py-12">
          <Spinner size="lg" />
        </div>
      ) : error ? (
        <EmptyState
          icon={<AlertTriangle className="h-12 w-12 text-red-400" />}
          title="Error loading suppliers"
          description={String(error)}
        />
      ) : items.length === 0 ? (
        <EmptyState
          icon={<Building2 className="h-12 w-12" />}
          title="No suppliers found"
          description={searchText ? 'Try a different search term.' : 'Add your first supplier to get started.'}
        />
      ) : (
        <div className="space-y-3">
          {items.map((supplier) => (
            <SupplierCard
              key={supplier.id}
              supplier={supplier}
              isExpanded={expandedId === supplier.id}
              onToggleExpand={() =>
                setExpandedId(expandedId === supplier.id ? null : supplier.id)
              }
              canEdit={canEdit}
              onEdit={() => setEditingSupplier(supplier)}
              onDelete={() => setDeleteConfirm(supplier)}
              onToggleActive={() =>
                toggleActiveMutation.mutate({
                  id: supplier.id,
                  is_active: !supplier.is_active,
                })
              }
            />
          ))}
        </div>
      )}

      {/* ── Create Modal ─────────────────────────── */}
      <SupplierFormModal
        isOpen={isCreateOpen}
        onClose={() => setIsCreateOpen(false)}
        onSubmit={(data) => createMutation.mutate(data as SupplierCreate)}
        isLoading={createMutation.isPending}
        title="Add Supplier"
      />

      {/* ── Edit Modal ───────────────────────────── */}
      {editingSupplier && (
        <SupplierFormModal
          isOpen={true}
          onClose={() => setEditingSupplier(null)}
          onSubmit={(data) =>
            updateMutation.mutate({ id: editingSupplier.id, data: data as SupplierUpdate })
          }
          isLoading={updateMutation.isPending}
          title={`Edit: ${editingSupplier.name}`}
          initial={editingSupplier}
        />
      )}

      {/* ── Delete Confirmation ──────────────────── */}
      {deleteConfirm && (
        <Modal isOpen={true} onClose={() => setDeleteConfirm(null)} title="Delete Supplier?" size="sm">
          <p className="text-gray-600 dark:text-gray-300 mb-4">
            Are you sure you want to delete <strong>{deleteConfirm.name}</strong>?
            This will also remove all part-supplier links for this supplier.
          </p>
          {deleteMutation.isError && (
            <p className="text-red-500 text-sm mb-4">
              {(deleteMutation.error as any)?.response?.data?.detail ?? 'Failed to delete supplier.'}
            </p>
          )}
          <div className="flex justify-end gap-2">
            <Button variant="secondary" onClick={() => setDeleteConfirm(null)}>Cancel</Button>
            <Button
              variant="danger"
              isLoading={deleteMutation.isPending}
              onClick={() => deleteMutation.mutate(deleteConfirm.id)}
            >
              Delete
            </Button>
          </div>
        </Modal>
      )}
    </div>
  );
}
