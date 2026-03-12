/**
 * PreferredSuppliersSection — manage explicit preferred suppliers for a job.
 *
 * Displayed on the Job Overview tab. Allows users to set a primary supplier
 * and optional backups BEFORE ordering. These explicit preferences take
 * priority over auto-learned ones from past orders.
 *
 * Phase 17 Gap 5: Explicit Preferred Supplier Per Job
 */

import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Building2, Plus, Trash2, GripVertical, Star, ChevronDown } from 'lucide-react';
import { Card, CardHeader } from '../../../components/ui/Card';
import { Button } from '../../../components/ui/Button';
import { EmptyState } from '../../../components/ui/EmptyState';
import { getJobPreferredSuppliers, setJobPreferredSuppliers } from '../../../api/jobs';
import { listSuppliers } from '../../../api/parts';
import type { Supplier } from '../../../lib/types';


interface Props {
    jobId: number;
    className?: string;
}

export function PreferredSuppliersSection({ jobId, className }: Props) {
    const queryClient = useQueryClient();
    const [isEditing, setIsEditing] = useState(false);
    const [showPicker, setShowPicker] = useState(false);
    const [search, setSearch] = useState('');

    // Fetch current preferred suppliers
    const { data: preferred = [], isLoading } = useQuery({
        queryKey: ['job-preferred-suppliers', jobId],
        queryFn: () => getJobPreferredSuppliers(jobId),
        staleTime: 30_000,
    });

    // Fetch all suppliers for the picker
    const { data: allSuppliers = [] } = useQuery({
        queryKey: ['suppliers-all'],
        queryFn: () => listSuppliers({ is_active: true }),
        staleTime: 60_000,
        enabled: showPicker,
    });

    // Save mutation
    const saveMutation = useMutation({
        mutationFn: (suppliers: { supplier_id: number; category?: string | null }[]) =>
            setJobPreferredSuppliers(jobId, { suppliers }),
        onSuccess: () => {
            queryClient.invalidateQueries({ queryKey: ['job-preferred-suppliers', jobId] });
            queryClient.invalidateQueries({ queryKey: ['job-detail', jobId] });
            setIsEditing(false);
        },
    });

    // Local editing state
    const [editList, setEditList] = useState<{ supplier_id: number; name: string }[]>([]);

    const startEditing = () => {
        setEditList(
            preferred.map((s) => ({ supplier_id: s.supplier_id, name: s.supplier_name }))
        );
        setIsEditing(true);
    };

    const addSupplier = (supplier: Supplier) => {
        if (editList.some((s) => s.supplier_id === supplier.id)) return;
        setEditList([...editList, { supplier_id: supplier.id, name: supplier.name }]);
        setShowPicker(false);
        setSearch('');
    };

    const removeSupplier = (supplierId: number) => {
        setEditList(editList.filter((s) => s.supplier_id !== supplierId));
    };

    const moveUp = (idx: number) => {
        if (idx === 0) return;
        const newList = [...editList];
        [newList[idx - 1], newList[idx]] = [newList[idx], newList[idx - 1]];
        setEditList(newList);
    };

    const moveDown = (idx: number) => {
        if (idx === editList.length - 1) return;
        const newList = [...editList];
        [newList[idx], newList[idx + 1]] = [newList[idx + 1], newList[idx]];
        setEditList(newList);
    };

    const saveChanges = () => {
        saveMutation.mutate(editList.map((s) => ({ supplier_id: s.supplier_id })));
    };

    // Filter suppliers for the picker (exclude already-selected)
    const filteredSuppliers = allSuppliers.filter((s) => {
        if (editList.some((e) => e.supplier_id === s.id)) return false;
        if (search && !s.name.toLowerCase().includes(search.toLowerCase())) return false;
        return true;
    });

    if (isLoading) {
        return (
            <Card className={className}>
                <CardHeader title="Preferred Suppliers" />
                <div className="px-4 pb-4 text-sm text-gray-500">Loading...</div>
            </Card>
        );
    }

    return (
        <Card className={className}>
            <CardHeader
                title="Preferred Suppliers"
                action={
                    !isEditing ? (
                        <Button size="sm" variant="secondary" onClick={startEditing}>
                            {preferred.length > 0 ? 'Edit' : 'Set Suppliers'}
                        </Button>
                    ) : undefined
                }
            />
            <div className="px-4 pb-4">
                {!isEditing ? (
                    // ── Read-only view ──
                    preferred.length === 0 ? (
                        <EmptyState
                            icon={<Building2 className="h-8 w-8" />}
                            title="No preferred suppliers set"
                            description="Set primary and backup suppliers before ordering to auto-fill supplier suggestions."
                        />
                    ) : (
                        <div className="space-y-2">
                            {preferred.map((s, idx) => (
                                <div
                                    key={s.id}
                                    className="flex items-center gap-3 p-2 rounded-lg bg-surface-secondary"
                                >
                                    <div className="flex-shrink-0 w-6 text-center">
                                        {idx === 0 ? (
                                            <Star className="h-4 w-4 text-amber-500 fill-amber-500" />
                                        ) : (
                                            <span className="text-xs text-gray-400 font-medium">#{idx + 1}</span>
                                        )}
                                    </div>
                                    <Building2 className="h-4 w-4 text-gray-400 flex-shrink-0" />
                                    <span className="text-sm font-medium text-gray-900 dark:text-gray-100 flex-1">
                                        {s.supplier_name}
                                    </span>
                                    {idx === 0 && (
                                        <span className="text-xs bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-400 px-2 py-0.5 rounded-full">
                                            Primary
                                        </span>
                                    )}
                                    {idx > 0 && (
                                        <span className="text-xs text-gray-400">Backup</span>
                                    )}
                                </div>
                            ))}
                        </div>
                    )
                ) : (
                    // ── Edit mode ──
                    <div className="space-y-3">
                        {editList.length === 0 && (
                            <p className="text-sm text-gray-500 italic">
                                No suppliers selected. Add at least one to set as primary.
                            </p>
                        )}

                        {editList.map((s, idx) => (
                            <div
                                key={s.supplier_id}
                                className="flex items-center gap-2 p-2 rounded-lg border border-border bg-surface-secondary"
                            >
                                <div className="flex flex-col gap-0.5">
                                    <button
                                        onClick={() => moveUp(idx)}
                                        disabled={idx === 0}
                                        className="p-0.5 text-gray-400 hover:text-gray-600 disabled:opacity-30"
                                        title="Move up"
                                    >
                                        <ChevronDown className="h-3 w-3 rotate-180" />
                                    </button>
                                    <button
                                        onClick={() => moveDown(idx)}
                                        disabled={idx === editList.length - 1}
                                        className="p-0.5 text-gray-400 hover:text-gray-600 disabled:opacity-30"
                                        title="Move down"
                                    >
                                        <ChevronDown className="h-3 w-3" />
                                    </button>
                                </div>
                                <GripVertical className="h-4 w-4 text-gray-300 flex-shrink-0" />
                                <div className="flex-shrink-0 w-6 text-center">
                                    {idx === 0 ? (
                                        <Star className="h-4 w-4 text-amber-500 fill-amber-500" />
                                    ) : (
                                        <span className="text-xs text-gray-400">#{idx + 1}</span>
                                    )}
                                </div>
                                <span className="text-sm font-medium text-gray-900 dark:text-gray-100 flex-1">
                                    {s.name}
                                </span>
                                <button
                                    onClick={() => removeSupplier(s.supplier_id)}
                                    className="p-1 text-red-400 hover:text-red-600"
                                    title="Remove supplier"
                                >
                                    <Trash2 className="h-4 w-4" />
                                </button>
                            </div>
                        ))}

                        {/* Add supplier button + picker */}
                        {!showPicker ? (
                            <Button
                                size="sm"
                                variant="secondary"
                                onClick={() => setShowPicker(true)}
                                className="w-full"
                            >
                                <Plus className="h-4 w-4 mr-1" />
                                Add Supplier
                            </Button>
                        ) : (
                            <div className="border border-border rounded-lg p-2 space-y-2">
                                <input
                                    type="text"
                                    placeholder="Search suppliers..."
                                    value={search}
                                    onChange={(e) => setSearch(e.target.value)}
                                    className="w-full px-3 py-1.5 text-sm rounded-md border border-border bg-background
                             focus:outline-none focus:ring-2 focus:ring-blue-500"
                                    autoFocus
                                />
                                <div className="max-h-40 overflow-y-auto space-y-1">
                                    {filteredSuppliers.length === 0 ? (
                                        <p className="text-xs text-gray-400 text-center py-2">
                                            No suppliers found
                                        </p>
                                    ) : (
                                        filteredSuppliers.slice(0, 20).map((s) => (
                                            <button
                                                key={s.id}
                                                onClick={() => addSupplier(s)}
                                                className="w-full flex items-center gap-2 px-2 py-1.5 text-sm
                                   text-left rounded hover:bg-blue-50 dark:hover:bg-blue-900/20
                                   transition-colors"
                                            >
                                                <Building2 className="h-3.5 w-3.5 text-gray-400" />
                                                {s.name}
                                            </button>
                                        ))
                                    )}
                                </div>
                                <Button
                                    size="sm"
                                    variant="ghost"
                                    onClick={() => { setShowPicker(false); setSearch(''); }}
                                    className="w-full"
                                >
                                    Cancel
                                </Button>
                            </div>
                        )}

                        {/* Save / Cancel */}
                        <div className="flex gap-2 pt-2 border-t border-border">
                            <Button
                                size="sm"
                                variant="secondary"
                                onClick={() => setIsEditing(false)}
                                className="flex-1"
                            >
                                Cancel
                            </Button>
                            <Button
                                size="sm"
                                variant="primary"
                                onClick={saveChanges}
                                disabled={saveMutation.isPending}
                                className="flex-1"
                            >
                                {saveMutation.isPending ? 'Saving...' : 'Save'}
                            </Button>
                        </div>
                    </div>
                )}
            </div>
        </Card>
    );
}
