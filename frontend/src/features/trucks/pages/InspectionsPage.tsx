/**
 * InspectionsPage — vehicle inspection management.
 *
 * Three sub-views:
 *  - Active: pending/in-progress inspections + fleet review
 *  - Templates: create/manage inspection checklist templates
 *  - History: completed inspections by vehicle
 *
 * Drivers can start pre-trip/post-trip inspections.
 * Managers can create templates and review failed inspections.
 */

import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
    ClipboardCheck,
    Plus,
    AlertTriangle,
    CheckCircle2,
    XCircle,
    Clock,
    List,
    FileText,
    Eye,
} from 'lucide-react';
import { PageSpinner } from '../../../components/ui/Spinner';
import { EmptyState } from '../../../components/ui/EmptyState';
import { Badge } from '../../../components/ui/Badge';
import { Button } from '../../../components/ui/Button';
import { Input } from '../../../components/ui/Input';
import { Modal } from '../../../components/ui/Modal';
import { useAuthStore } from '../../../stores/auth-store';
import { PERMISSIONS } from '../../../lib/constants';
import {
    listVehicles,
    listInspectionTemplates,
    createInspectionTemplate,
    startInspection,
    submitInspectionItem,
    completeInspection,
    getVehicleInspections,
    getPendingInspections,
    getFailedInspections,
} from '../../../api/vehicles';
import type {
    InspectionTemplate,
    InspectionTemplateCreate,
    InspectionTemplateItemCreate,
    InspectionRecord,
    InspectionRecordItem,
    InspectionItemSubmit,
    VehicleListItem,
    InspectionItemSeverity,
} from '../../../lib/types';

type SubView = 'active' | 'templates' | 'history';

export function InspectionsPage() {
    const queryClient = useQueryClient();
    const { hasPermission } = useAuthStore();
    const canManage = hasPermission(PERMISSIONS.MANAGE_FLEET);

    const [subView, setSubView] = useState<SubView>('active');
    const [showStartModal, setShowStartModal] = useState(false);
    const [showTemplateModal, setShowTemplateModal] = useState(false);
    const [activeRecord, setActiveRecord] = useState<InspectionRecord | null>(null);
    const [historyVehicleId, setHistoryVehicleId] = useState<number | null>(null);

    // ── Queries ──
    const { data: vehicles } = useQuery({
        queryKey: ['vehicles-list-brief'],
        queryFn: () => listVehicles(),
    });

    const { data: templates } = useQuery({
        queryKey: ['inspection-templates'],
        queryFn: () => listInspectionTemplates(),
    });

    const { data: pendingRecords, isLoading: loadingPending } = useQuery({
        queryKey: ['inspections-pending'],
        queryFn: getPendingInspections,
        enabled: subView === 'active',
    });

    const { data: failedRecords, isLoading: loadingFailed } = useQuery({
        queryKey: ['inspections-failed'],
        queryFn: getFailedInspections,
        enabled: subView === 'active',
    });

    const { data: historyRecords } = useQuery({
        queryKey: ['inspections-history', historyVehicleId],
        queryFn: () => getVehicleInspections(historyVehicleId!, { limit: 50 }),
        enabled: subView === 'history' && !!historyVehicleId,
    });

    // ── Mutations ──
    const startMut = useMutation({
        mutationFn: (d: { vehicleId: number; templateId: number; odometer?: number }) =>
            startInspection(d.vehicleId, {
                template_id: d.templateId,
                odometer_reading: d.odometer,
            }),
        onSuccess: (record) => {
            queryClient.invalidateQueries({ queryKey: ['inspections-pending'] });
            setShowStartModal(false);
            setActiveRecord(record);
        },
    });

    const submitItemMut = useMutation({
        mutationFn: (d: { recordId: number; itemId: number; body: InspectionItemSubmit }) =>
            submitInspectionItem(d.recordId, d.itemId, d.body),
        onSuccess: (record) => setActiveRecord(record),
    });

    const completeMut = useMutation({
        mutationFn: (recordId: number) => completeInspection(recordId),
        onSuccess: (record) => {
            setActiveRecord(record);
            queryClient.invalidateQueries({ queryKey: ['inspections-pending'] });
            queryClient.invalidateQueries({ queryKey: ['inspections-failed'] });
        },
    });

    const createTemplateMut = useMutation({
        mutationFn: (body: InspectionTemplateCreate) => createInspectionTemplate(body),
        onSuccess: () => {
            queryClient.invalidateQueries({ queryKey: ['inspection-templates'] });
            setShowTemplateModal(false);
        },
    });

    const vList: VehicleListItem[] = Array.isArray(vehicles) ? vehicles : [];

    const SubTab = ({
        value,
        icon: Icon,
        label,
        count,
    }: {
        value: SubView;
        icon: React.ElementType;
        label: string;
        count?: number;
    }) => (
        <button
            onClick={() => setSubView(value)}
            className={`px-3 py-1.5 text-sm rounded-lg transition-colors min-h-[36px] flex items-center gap-1.5 ${subView === value
                    ? 'bg-blue-100 dark:bg-blue-900/40 text-blue-700 dark:text-blue-300 font-medium'
                    : 'text-gray-600 dark:text-gray-400 hover:bg-gray-100 dark:hover:bg-gray-800'
                }`}
        >
            <Icon className="h-4 w-4" />
            <span className="hidden sm:inline">{label}</span>
            {count != null && count > 0 && (
                <span className="ml-1 px-1.5 py-0.5 text-xs bg-red-100 dark:bg-red-900/40 text-red-700 dark:text-red-300 rounded-full">
                    {count}
                </span>
            )}
        </button>
    );

    const resultBadge = (result: string | null) => {
        if (result === 'pass') return <Badge variant="success">Pass</Badge>;
        if (result === 'fail') return <Badge variant="danger">Fail</Badge>;
        if (result === 'needs_attention') return <Badge variant="warning">Needs Attention</Badge>;
        return <Badge variant="neutral">In Progress</Badge>;
    };

    return (
        <div className="space-y-4">
            {/* Header */}
            <div className="flex items-center justify-between flex-wrap gap-3">
                <div className="flex items-center gap-2">
                    <SubTab value="active" icon={ClipboardCheck} label="Active" count={pendingRecords?.length} />
                    {canManage && <SubTab value="templates" icon={FileText} label="Templates" />}
                    <SubTab value="history" icon={List} label="History" />
                </div>
                <div className="flex items-center gap-2">
                    <Button size="sm" onClick={() => setShowStartModal(true)}>
                        <Plus className="h-4 w-4 mr-1" />
                        <span className="hidden sm:inline">Start Inspection</span>
                    </Button>
                    {canManage && subView === 'templates' && (
                        <Button size="sm" variant="secondary" onClick={() => setShowTemplateModal(true)}>
                            <Plus className="h-4 w-4 mr-1" />
                            <span className="hidden sm:inline">New Template</span>
                        </Button>
                    )}
                </div>
            </div>

            {/* Active View */}
            {subView === 'active' && (
                <div className="space-y-4">
                    {/* Pending */}
                    <Section title="Pending Inspections" icon={Clock} loading={loadingPending}>
                        {pendingRecords && pendingRecords.length > 0 ? (
                            <InspectionTable
                                records={pendingRecords}
                                onView={(r) => setActiveRecord(r)}
                                resultBadge={resultBadge}
                            />
                        ) : (
                            <EmptyState icon={CheckCircle2} title="No pending inspections" />
                        )}
                    </Section>

                    {/* Failed */}
                    {canManage && (
                        <Section title="Failed / Needs Attention" icon={AlertTriangle} loading={loadingFailed}>
                            {failedRecords && failedRecords.length > 0 ? (
                                <InspectionTable
                                    records={failedRecords}
                                    onView={(r) => setActiveRecord(r)}
                                    resultBadge={resultBadge}
                                />
                            ) : (
                                <EmptyState icon={CheckCircle2} title="No failed inspections" />
                            )}
                        </Section>
                    )}
                </div>
            )}

            {/* Templates View */}
            {subView === 'templates' && (
                <div className="rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 overflow-hidden">
                    {!templates || templates.length === 0 ? (
                        <EmptyState
                            icon={FileText}
                            title="No templates yet"
                            description="Create an inspection template to start."
                        />
                    ) : (
                        <div className="overflow-x-auto">
                            <table className="w-full text-sm">
                                <thead className="bg-gray-50 dark:bg-gray-800 border-b border-gray-200 dark:border-gray-700">
                                    <tr>
                                        <th className="text-left p-3 font-medium">Name</th>
                                        <th className="text-left p-3 font-medium">Type</th>
                                        <th className="text-left p-3 font-medium">Vehicle Type</th>
                                        <th className="text-center p-3 font-medium">Status</th>
                                    </tr>
                                </thead>
                                <tbody className="divide-y divide-gray-100 dark:divide-gray-700">
                                    {templates.map((t) => (
                                        <tr key={t.id} className="hover:bg-gray-50 dark:hover:bg-gray-700/40">
                                            <td className="p-3 font-medium">{t.name}</td>
                                            <td className="p-3 capitalize">{t.inspection_type?.replace(/_/g, ' ')}</td>
                                            <td className="p-3 text-gray-600 dark:text-gray-400">
                                                {t.vehicle_type ?? 'All'}
                                            </td>
                                            <td className="p-3 text-center">
                                                <Badge variant={t.is_active ? 'success' : 'neutral'}>
                                                    {t.is_active ? 'Active' : 'Inactive'}
                                                </Badge>
                                            </td>
                                        </tr>
                                    ))}
                                </tbody>
                            </table>
                        </div>
                    )}
                </div>
            )}

            {/* History View */}
            {subView === 'history' && (
                <div className="space-y-3">
                    <div className="flex items-center gap-3 flex-wrap">
                        <label className="text-sm font-medium">Vehicle:</label>
                        <select
                            value={historyVehicleId ?? ''}
                            onChange={(e) =>
                                setHistoryVehicleId(e.target.value ? Number(e.target.value) : null)
                            }
                            className="px-3 py-1.5 rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-sm min-w-[200px]"
                        >
                            <option value="">Select vehicle...</option>
                            {vList.map((v: VehicleListItem) => (
                                <option key={v.id} value={v.id}>
                                    {v.vehicle_number}
                                </option>
                            ))}
                        </select>
                    </div>
                    {historyVehicleId && historyRecords && (
                        <div className="rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 overflow-hidden">
                            {historyRecords.length === 0 ? (
                                <EmptyState icon={ClipboardCheck} title="No inspections for this vehicle" />
                            ) : (
                                <InspectionTable
                                    records={historyRecords}
                                    onView={(r) => setActiveRecord(r)}
                                    resultBadge={resultBadge}
                                />
                            )}
                        </div>
                    )}
                </div>
            )}

            {/* Active Inspection Worksheet */}
            {activeRecord && (
                <InspectionWorksheet
                    record={activeRecord}
                    onSubmitItem={(itemId, body) =>
                        submitItemMut.mutate({ recordId: activeRecord.id, itemId, body })
                    }
                    onComplete={() => completeMut.mutate(activeRecord.id)}
                    onClose={() => {
                        setActiveRecord(null);
                        queryClient.invalidateQueries({ queryKey: ['inspections-pending'] });
                    }}
                    isCompleting={completeMut.isPending}
                    resultBadge={resultBadge}
                />
            )}

            {/* Start Inspection Modal */}
            {showStartModal && (
                <StartInspectionModal
                    vehicles={vList}
                    templates={templates ?? []}
                    onSubmit={(vehicleId, templateId, odometer) =>
                        startMut.mutate({ vehicleId, templateId, odometer })
                    }
                    onClose={() => setShowStartModal(false)}
                    isPending={startMut.isPending}
                />
            )}

            {/* Create Template Modal */}
            {showTemplateModal && (
                <CreateTemplateModal
                    onSubmit={(body) => createTemplateMut.mutate(body)}
                    onClose={() => setShowTemplateModal(false)}
                    isPending={createTemplateMut.isPending}
                />
            )}
        </div>
    );
}


// ── Sub-Components ────────────────────────────────────────────────

function Section({
    title,
    icon: Icon,
    loading,
    children,
}: {
    title: string;
    icon: React.ElementType;
    loading: boolean;
    children: React.ReactNode;
}) {
    return (
        <div className="rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 overflow-hidden">
            <div className="px-4 py-3 border-b border-gray-200 dark:border-gray-700 flex items-center gap-2">
                <Icon className="h-4 w-4 text-gray-500" />
                <h3 className="text-sm font-semibold">{title}</h3>
            </div>
            <div className="p-2">{loading ? <PageSpinner /> : children}</div>
        </div>
    );
}

function InspectionTable({
    records,
    onView,
    resultBadge,
}: {
    records: InspectionRecord[];
    onView: (r: InspectionRecord) => void;
    resultBadge: (r: string | null) => React.ReactNode;
}) {
    return (
        <div className="overflow-x-auto">
            <table className="w-full text-sm">
                <thead className="bg-gray-50 dark:bg-gray-800 border-b border-gray-200 dark:border-gray-700">
                    <tr>
                        <th className="text-left p-3 font-medium">Vehicle</th>
                        <th className="text-left p-3 font-medium">Type</th>
                        <th className="text-left p-3 font-medium">Date</th>
                        <th className="text-center p-3 font-medium">Result</th>
                        <th className="p-3 w-10" />
                    </tr>
                </thead>
                <tbody className="divide-y divide-gray-100 dark:divide-gray-700">
                    {records.map((r) => (
                        <tr key={r.id} className="hover:bg-gray-50 dark:hover:bg-gray-700/40">
                            <td className="p-3 font-medium">{r.vehicle_number ?? `#${r.vehicle_id}`}</td>
                            <td className="p-3 capitalize">{r.inspection_type?.replace(/_/g, ' ')}</td>
                            <td className="p-3 text-gray-600 dark:text-gray-400">{r.inspection_date}</td>
                            <td className="p-3 text-center">{resultBadge(r.overall_result)}</td>
                            <td className="p-3">
                                <button
                                    onClick={() => onView(r)}
                                    className="p-1 hover:bg-gray-200 dark:hover:bg-gray-600 rounded"
                                    title="View"
                                >
                                    <Eye className="h-3.5 w-3.5" />
                                </button>
                            </td>
                        </tr>
                    ))}
                </tbody>
            </table>
        </div>
    );
}

function InspectionWorksheet({
    record,
    onSubmitItem,
    onComplete,
    onClose,
    isCompleting,
    resultBadge,
}: {
    record: InspectionRecord;
    onSubmitItem: (itemId: number, body: InspectionItemSubmit) => void;
    onComplete: () => void;
    onClose: () => void;
    isCompleting: boolean;
    resultBadge: (r: string | null) => React.ReactNode;
}) {
    const items = record.items ?? [];
    const pendingCount = items.filter((i) => i.status === 'pending').length;
    const isComplete = !!record.completed_at;

    return (
        <Modal isOpen={true} onClose={onClose} title={`Inspection #${record.id}`} size="lg">
            <div className="space-y-4">
                {/* Summary */}
                <div className="flex items-center justify-between flex-wrap gap-2">
                    <div className="text-sm text-gray-600 dark:text-gray-400">
                        <span className="font-medium">{record.vehicle_number}</span> ·{' '}
                        {record.inspection_type?.replace(/_/g, ' ')} · {record.inspection_date}
                    </div>
                    {resultBadge(record.overall_result)}
                </div>

                {/* Item List */}
                <div className="max-h-[60vh] overflow-y-auto divide-y divide-gray-200 dark:divide-gray-700">
                    {items.map((item) => (
                        <InspectionItemRow
                            key={item.id}
                            item={item}
                            disabled={isComplete}
                            onSubmit={(body) => onSubmitItem(item.id, body)}
                        />
                    ))}
                </div>

                {/* Actions */}
                <div className="flex items-center justify-between pt-2 border-t border-gray-200 dark:border-gray-700">
                    <span className="text-xs text-gray-500">
                        {pendingCount > 0
                            ? `${pendingCount} items remaining`
                            : isComplete
                                ? 'Inspection complete'
                                : 'All items submitted — ready to finalize'}
                    </span>
                    <div className="flex gap-2">
                        <Button variant="ghost" onClick={onClose}>
                            Close
                        </Button>
                        {!isComplete && (
                            <Button
                                onClick={onComplete}
                                disabled={pendingCount > 0 || isCompleting}
                                variant={pendingCount > 0 ? 'secondary' : 'primary'}
                            >
                                {isCompleting ? 'Finalizing...' : 'Complete Inspection'}
                            </Button>
                        )}
                    </div>
                </div>
            </div>
        </Modal>
    );
}

function InspectionItemRow({
    item,
    disabled,
    onSubmit,
}: {
    item: InspectionRecordItem;
    disabled: boolean;
    onSubmit: (body: InspectionItemSubmit) => void;
}) {
    const [notes, setNotes] = useState('');

    const severityColor =
        item.severity === 'critical'
            ? 'text-red-600 dark:text-red-400'
            : item.severity === 'warning'
                ? 'text-amber-600 dark:text-amber-400'
                : 'text-blue-600 dark:text-blue-400';

    const statusIcon =
        item.status === 'pass' ? (
            <CheckCircle2 className="h-5 w-5 text-emerald-500" />
        ) : item.status === 'fail' ? (
            <XCircle className="h-5 w-5 text-red-500" />
        ) : item.status === 'na' ? (
            <span className="text-xs text-gray-400 font-medium">N/A</span>
        ) : (
            <Clock className="h-5 w-5 text-gray-400" />
        );

    return (
        <div className="flex items-center gap-3 py-3 px-2">
            <div className="flex-shrink-0">{statusIcon}</div>
            <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2">
                    <span className="font-medium text-sm">{item.item_name}</span>
                    <span className={`text-xs ${severityColor}`}>{item.severity}</span>
                </div>
                {item.category && (
                    <span className="text-xs text-gray-500">{item.category}</span>
                )}
                {item.notes && (
                    <p className="text-xs text-gray-500 mt-0.5">{item.notes}</p>
                )}
            </div>
            {!disabled && item.status === 'pending' && (
                <div className="flex items-center gap-1 flex-shrink-0">
                    <input
                        type="text"
                        placeholder="Note"
                        value={notes}
                        onChange={(e) => setNotes(e.target.value)}
                        className="w-20 px-1.5 py-1 text-xs rounded border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800"
                    />
                    <button
                        onClick={() => onSubmit({ status: 'pass', notes: notes || undefined })}
                        className="px-2 py-1 text-xs rounded bg-emerald-100 dark:bg-emerald-900/30 text-emerald-700 dark:text-emerald-300 hover:bg-emerald-200 min-h-[32px]"
                    >
                        Pass
                    </button>
                    <button
                        onClick={() => onSubmit({ status: 'fail', notes: notes || undefined })}
                        className="px-2 py-1 text-xs rounded bg-red-100 dark:bg-red-900/30 text-red-700 dark:text-red-300 hover:bg-red-200 min-h-[32px]"
                    >
                        Fail
                    </button>
                    <button
                        onClick={() => onSubmit({ status: 'na', notes: notes || undefined })}
                        className="px-2 py-1 text-xs rounded bg-gray-100 dark:bg-gray-700 text-gray-600 dark:text-gray-300 hover:bg-gray-200 min-h-[32px]"
                    >
                        N/A
                    </button>
                </div>
            )}
        </div>
    );
}

function StartInspectionModal({
    vehicles,
    templates,
    onSubmit,
    onClose,
    isPending,
}: {
    vehicles: VehicleListItem[];
    templates: InspectionTemplate[];
    onSubmit: (vehicleId: number, templateId: number, odometer?: number) => void;
    onClose: () => void;
    isPending: boolean;
}) {
    const [vehicleId, setVehicleId] = useState(0);
    const [templateId, setTemplateId] = useState(0);
    const [odometer, setOdometer] = useState('');

    return (
        <Modal isOpen={true} onClose={onClose} title="Start Inspection" size="md">
            <div className="space-y-4">
                <div>
                    <label className="block text-sm font-medium mb-1">Vehicle *</label>
                    <select
                        value={vehicleId}
                        onChange={(e) => setVehicleId(Number(e.target.value))}
                        className="w-full px-3 py-2 rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-sm"
                    >
                        <option value={0}>Select vehicle...</option>
                        {vehicles.map((v) => (
                            <option key={v.id} value={v.id}>
                                {v.vehicle_number} — {v.year} {v.make} {v.model}
                            </option>
                        ))}
                    </select>
                </div>
                <div>
                    <label className="block text-sm font-medium mb-1">Template *</label>
                    <select
                        value={templateId}
                        onChange={(e) => setTemplateId(Number(e.target.value))}
                        className="w-full px-3 py-2 rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-sm"
                    >
                        <option value={0}>Select template...</option>
                        {templates
                            .filter((t) => t.is_active)
                            .map((t) => (
                                <option key={t.id} value={t.id}>
                                    {t.name} ({t.inspection_type?.replace(/_/g, ' ')})
                                </option>
                            ))}
                    </select>
                </div>
                <Input
                    label="Odometer Reading"
                    type="number"
                    value={odometer}
                    onChange={(e) => setOdometer(e.target.value)}
                    placeholder="Optional"
                />
                <div className="flex justify-end gap-2 pt-2">
                    <Button variant="ghost" onClick={onClose}>
                        Cancel
                    </Button>
                    <Button
                        onClick={() =>
                            onSubmit(vehicleId, templateId, odometer ? Number(odometer) : undefined)
                        }
                        disabled={isPending || !vehicleId || !templateId}
                    >
                        {isPending ? 'Starting...' : 'Start Inspection'}
                    </Button>
                </div>
            </div>
        </Modal>
    );
}

function CreateTemplateModal({
    onSubmit,
    onClose,
    isPending,
}: {
    onSubmit: (body: InspectionTemplateCreate) => void;
    onClose: () => void;
    isPending: boolean;
}) {
    const [name, setName] = useState('');
    const [inspectionType, setInspectionType] = useState('pre_trip');
    const [vehicleType, setVehicleType] = useState('');
    const [items, setItems] = useState<InspectionTemplateItemCreate[]>([
        { item_name: '', category: 'General', severity: 'warning' },
    ]);

    const addItem = () =>
        setItems([...items, { item_name: '', category: 'General', severity: 'warning' }]);

    const updateItem = (idx: number, update: Partial<InspectionTemplateItemCreate>) =>
        setItems(items.map((it, i) => (i === idx ? { ...it, ...update } : it)));

    const removeItem = (idx: number) => setItems(items.filter((_, i) => i !== idx));

    return (
        <Modal isOpen={true} onClose={onClose} title="Create Inspection Template" size="lg">
            <div className="space-y-4 max-h-[70vh] overflow-y-auto">
                <div className="grid grid-cols-2 gap-3">
                    <Input
                        label="Template Name *"
                        value={name}
                        onChange={(e) => setName(e.target.value)}
                        placeholder="e.g. Pre-Trip Van"
                    />
                    <div>
                        <label className="block text-sm font-medium mb-1">Inspection Type</label>
                        <select
                            value={inspectionType}
                            onChange={(e) => setInspectionType(e.target.value)}
                            className="w-full px-3 py-2 rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-sm"
                        >
                            <option value="pre_trip">Pre-Trip</option>
                            <option value="post_trip">Post-Trip</option>
                            <option value="weekly">Weekly</option>
                            <option value="monthly">Monthly</option>
                        </select>
                    </div>
                </div>
                <Input
                    label="Vehicle Type (optional)"
                    value={vehicleType}
                    onChange={(e) => setVehicleType(e.target.value)}
                    placeholder="e.g. van, truck, trailer"
                />

                {/* Items */}
                <div className="space-y-2">
                    <div className="flex items-center justify-between">
                        <h4 className="text-sm font-medium">Checklist Items</h4>
                        <Button size="sm" variant="ghost" onClick={addItem}>
                            <Plus className="h-3.5 w-3.5 mr-1" /> Add Item
                        </Button>
                    </div>
                    {items.map((item, idx) => (
                        <div
                            key={idx}
                            className="flex items-center gap-2 p-2 rounded border border-gray-200 dark:border-gray-700"
                        >
                            <Input
                                value={item.item_name}
                                onChange={(e) => updateItem(idx, { item_name: e.target.value })}
                                placeholder="Item name"
                                className="flex-1"
                            />
                            <select
                                value={item.severity}
                                onChange={(e) =>
                                    updateItem(idx, { severity: e.target.value as InspectionItemSeverity })
                                }
                                className="px-2 py-1.5 rounded border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-xs"
                            >
                                <option value="critical">Critical</option>
                                <option value="warning">Warning</option>
                                <option value="info">Info</option>
                            </select>
                            <Input
                                value={item.category ?? 'General'}
                                onChange={(e) => updateItem(idx, { category: e.target.value })}
                                placeholder="Category"
                                className="w-24"
                            />
                            <button
                                onClick={() => removeItem(idx)}
                                className="p-1 text-red-500 hover:bg-red-100 dark:hover:bg-red-900/30 rounded"
                            >
                                <XCircle className="h-4 w-4" />
                            </button>
                        </div>
                    ))}
                </div>

                <div className="flex justify-end gap-2 pt-2">
                    <Button variant="ghost" onClick={onClose}>
                        Cancel
                    </Button>
                    <Button
                        onClick={() =>
                            onSubmit({
                                name,
                                inspection_type: inspectionType,
                                vehicle_type: vehicleType || undefined,
                                items: items.filter((i) => i.item_name.trim()),
                            })
                        }
                        disabled={isPending || !name || items.every((i) => !i.item_name.trim())}
                    >
                        {isPending ? 'Creating...' : 'Create Template'}
                    </Button>
                </div>
            </div>
        </Modal>
    );
}
