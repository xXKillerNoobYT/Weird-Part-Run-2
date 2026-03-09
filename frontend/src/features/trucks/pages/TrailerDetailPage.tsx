/**
 * TrailerDetailPage — full trailer detail with internal sub-tabs.
 *
 * Sub-tabs: Overview (default), Inventory, Location History, Templates.
 * Accessible via /trucks/trailers/:trailer_id.
 * Follows the VehicleDetailPage tabbed-detail pattern.
 */

import { useState } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  ArrowLeft,
  Container,
  Package,
  MapPin,
  ClipboardList,
  Edit3,
  Save,
  X,
  Plus,
  Trash2,
  AlertTriangle,
  Briefcase,
  Warehouse,
  User,
  Clock,
  Search,
  ArrowUpFromLine,
  RotateCcw,
} from 'lucide-react';
import { PageSpinner } from '../../../components/ui/Spinner';
import { EmptyState } from '../../../components/ui/EmptyState';
import { Button } from '../../../components/ui/Button';
import { Input } from '../../../components/ui/Input';
import { Badge } from '../../../components/ui/Badge';
import { Card } from '../../../components/ui/Card';
import { useAuthStore } from '../../../stores/auth-store';
import { PERMISSIONS } from '../../../lib/constants';
import {
  listTrailers,
  updateTrailer,
  deactivateTrailer,
  getTrailerInventory,
  consumeTrailerToJob,
  returnTrailerInventory,
  listTrailerLocationEvents,
  createTrailerLocationEvent,
  getTrailerRestockGuidance,
  listTrailerTemplates,
} from '../../../api/vehicles';
import { TrailerStatusBadge } from '../components/TrailerStatusBadge';
import { toast } from '../../../lib/toast';
import type {
  JobTrailer,
  JobTrailerUpdate,
  TrailerStatus,
  TrailerInventoryItem,
  TrailerLocationKind,
  TrailerLocationEventType,
  TrailerLocationEventCreate,
} from '../../../lib/types';


// ── Sub-tab Definitions ──────────────────────────────────────────

type SubTab = 'overview' | 'inventory' | 'location' | 'templates';

const TABS: { id: SubTab; label: string; mobileLabel: string; icon: React.ReactNode }[] = [
  { id: 'overview', label: 'Overview', mobileLabel: 'Info', icon: <Container className="h-4 w-4" /> },
  { id: 'inventory', label: 'Inventory', mobileLabel: 'Parts', icon: <Package className="h-4 w-4" /> },
  { id: 'location', label: 'Location History', mobileLabel: 'Location', icon: <MapPin className="h-4 w-4" /> },
  { id: 'templates', label: 'Templates', mobileLabel: 'Templates', icon: <ClipboardList className="h-4 w-4" /> },
];

const STATUS_OPTIONS: { label: string; value: TrailerStatus }[] = [
  { label: 'Active', value: 'active' },
  { label: 'In Transit', value: 'in_transit' },
  { label: 'Maintenance', value: 'maintenance' },
  { label: 'Inactive', value: 'inactive' },
];


export function TrailerDetailPage() {
  const { trailer_id } = useParams<{ trailer_id: string }>();
  const navigate = useNavigate();

  const { hasPermission } = useAuthStore();
  const canManage = hasPermission(PERMISSIONS.MANAGE_FLEET);
  const canMove = hasPermission(PERMISSIONS.MOVE_STOCK_WAREHOUSE);

  const [activeTab, setActiveTab] = useState<SubTab>('overview');

  // ── Fetch trailer from list (or could add a GET /trailers/:id endpoint) ──
  const { data: trailers, isLoading, error } = useQuery({
    queryKey: ['trailers'],
    queryFn: () => listTrailers(),
    staleTime: 15_000,
  });

  const trailer = trailers?.find((t) => t.id === Number(trailer_id));

  if (isLoading) return <PageSpinner label="Loading trailer..." />;
  if (error || !trailer) {
    return (
      <div className="text-center py-16">
        <Button variant="secondary" icon={<ArrowLeft className="h-4 w-4" />} onClick={() => navigate('/trucks/trailers')}>
          Back to Trailers
        </Button>
        <p className="text-red-500 mt-4">Trailer not found.</p>
      </div>
    );
  }

  return (
    <div className="space-y-4">
      {/* Back + Header */}
      <div className="flex items-center gap-3 flex-wrap">
        <Button
          variant="ghost"
          size="sm"
          icon={<ArrowLeft className="h-4 w-4" />}
          onClick={() => navigate('/trucks/trailers')}
        >
          <span className="hidden sm:inline">Back</span>
        </Button>

        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 flex-wrap">
            <Container className="h-5 w-5 text-gray-400 shrink-0" />
            <span className="text-sm font-mono text-gray-500">{trailer.trailer_code}</span>
            <TrailerStatusBadge status={trailer.status} />
          </div>
          <h1 className="text-lg font-bold text-gray-900 dark:text-gray-100 truncate">
            {trailer.name}
          </h1>
        </div>
      </div>

      {/* Quick stats */}
      <div className="flex items-center gap-4 text-xs text-gray-500 dark:text-gray-400 flex-wrap">
        {trailer.current_job_name && (
          <div className="flex items-center gap-1">
            <Briefcase className="h-3.5 w-3.5" />
            <span>{trailer.current_job_name}</span>
          </div>
        )}
        {trailer.home_warehouse_name && (
          <div className="flex items-center gap-1">
            <Warehouse className="h-3.5 w-3.5" />
            <span>{trailer.home_warehouse_name}</span>
          </div>
        )}
        {trailer.assigned_driver_name && (
          <div className="flex items-center gap-1">
            <User className="h-3.5 w-3.5" />
            <span>{trailer.assigned_driver_name}</span>
          </div>
        )}
      </div>

      {/* Tab bar */}
      <div className="overflow-x-auto border-b border-border">
        <div className="flex gap-1 min-w-max">
          {TABS.map((tab) => (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id)}
              className={`flex items-center gap-1.5 px-3 py-2 text-sm font-medium border-b-2 transition-colors whitespace-nowrap ${
                activeTab === tab.id
                  ? 'border-primary-500 text-primary-600 dark:text-primary-400'
                  : 'border-transparent text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-300'
              }`}
            >
              {tab.icon}
              <span className="hidden sm:inline">{tab.label}</span>
              <span className="sm:hidden">{tab.mobileLabel}</span>
            </button>
          ))}
        </div>
      </div>

      {/* Tab content */}
      {activeTab === 'overview' && <OverviewTab trailer={trailer} canManage={canManage} />}
      {activeTab === 'inventory' && <InventoryTab trailer={trailer} canMove={canMove} />}
      {activeTab === 'location' && <LocationTab trailer={trailer} canManage={canManage} />}
      {activeTab === 'templates' && <TemplatesTab trailer={trailer} />}
    </div>
  );
}


// ═══════════════════════════════════════════════════════════════════
// OVERVIEW TAB
// ═══════════════════════════════════════════════════════════════════

function OverviewTab({ trailer, canManage }: { trailer: JobTrailer; canManage: boolean }) {
  const queryClient = useQueryClient();
  const navigate = useNavigate();
  const [editing, setEditing] = useState(false);
  const [name, setName] = useState(trailer.name);
  const [status, setStatus] = useState<TrailerStatus>(trailer.status);
  const [notes, setNotes] = useState(trailer.notes || '');

  const updateMutation = useMutation({
    mutationFn: (update: JobTrailerUpdate) => updateTrailer(trailer.id, update),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['trailers'] });
      toast.success('Trailer updated');
      setEditing(false);
    },
    onError: () => toast.error('Failed to update trailer'),
  });

  const deactivateMutation = useMutation({
    mutationFn: () => deactivateTrailer(trailer.id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['trailers'] });
      toast.success('Trailer deactivated');
      navigate('/trucks/trailers');
    },
    onError: () => toast.error('Failed to deactivate trailer'),
  });

  function handleSave() {
    updateMutation.mutate({
      name: name.trim(),
      status,
      notes: notes.trim() || undefined,
    });
  }

  return (
    <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
      {/* Details card */}
      <Card>
        <div className="p-4 space-y-4">
          <div className="flex items-center justify-between">
            <h3 className="text-sm font-semibold">Trailer Details</h3>
            {canManage && !editing && (
              <Button variant="ghost" size="sm" icon={<Edit3 className="h-3.5 w-3.5" />} onClick={() => setEditing(true)}>
                Edit
              </Button>
            )}
          </div>

          {editing ? (
            <div className="space-y-3">
              <Input label="Name" value={name} onChange={(e) => setName(e.target.value)} />
              <div>
                <label className="block text-sm font-medium mb-1">Status</label>
                <select
                  value={status}
                  onChange={(e) => setStatus(e.target.value as TrailerStatus)}
                  className="w-full rounded-md border border-border bg-surface px-3 py-2 text-sm"
                >
                  {STATUS_OPTIONS.map((o) => (
                    <option key={o.value} value={o.value}>{o.label}</option>
                  ))}
                </select>
              </div>
              <div>
                <label className="block text-sm font-medium mb-1">Notes</label>
                <textarea
                  value={notes}
                  onChange={(e) => setNotes(e.target.value)}
                  rows={3}
                  className="w-full rounded-md border border-border bg-surface px-3 py-2 text-sm"
                />
              </div>
              <div className="flex gap-2">
                <Button size="sm" icon={<Save className="h-3.5 w-3.5" />} onClick={handleSave} isLoading={updateMutation.isPending}>
                  Save
                </Button>
                <Button variant="secondary" size="sm" icon={<X className="h-3.5 w-3.5" />} onClick={() => setEditing(false)}>
                  Cancel
                </Button>
              </div>
            </div>
          ) : (
            <div className="space-y-2 text-sm">
              <div className="flex justify-between">
                <span className="text-gray-500">Code</span>
                <span className="font-mono">{trailer.trailer_code}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-gray-500">Name</span>
                <span>{trailer.name}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-gray-500">Status</span>
                <TrailerStatusBadge status={trailer.status} />
              </div>
              <div className="flex justify-between">
                <span className="text-gray-500">Home Warehouse</span>
                <span>{trailer.home_warehouse_name || '—'}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-gray-500">Current Job</span>
                <span>{trailer.current_job_name || '—'}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-gray-500">Driver</span>
                <span>{trailer.assigned_driver_name || '—'}</span>
              </div>
              {trailer.notes && (
                <div className="pt-2 border-t border-border">
                  <span className="text-gray-500 block mb-1">Notes</span>
                  <p className="text-gray-700 dark:text-gray-300 whitespace-pre-wrap">{trailer.notes}</p>
                </div>
              )}
            </div>
          )}
        </div>
      </Card>

      {/* Actions card */}
      <Card>
        <div className="p-4 space-y-4">
          <h3 className="text-sm font-semibold">Quick Actions</h3>

          {/* Restock guidance */}
          <RestockGuidanceCard trailerId={trailer.id} />

          {/* Deactivate */}
          {canManage && trailer.is_active && (
            <div className="pt-4 border-t border-border">
              <Button
                variant="danger"
                size="sm"
                icon={<Trash2 className="h-3.5 w-3.5" />}
                onClick={() => {
                  if (window.confirm('Deactivate this trailer? It can be reactivated later.')) {
                    deactivateMutation.mutate();
                  }
                }}
                isLoading={deactivateMutation.isPending}
              >
                Deactivate Trailer
              </Button>
            </div>
          )}
        </div>
      </Card>
    </div>
  );
}

/** Shows restock guidance — parts below template targets. */
function RestockGuidanceCard({ trailerId }: { trailerId: number }) {
  const { data: guidance, isLoading } = useQuery({
    queryKey: ['trailer-restock', trailerId],
    queryFn: () => getTrailerRestockGuidance(trailerId),
    staleTime: 30_000,
  });

  if (isLoading) return <p className="text-xs text-gray-400">Checking restock needs...</p>;
  if (!guidance || !guidance.lines || guidance.lines.length === 0) {
    return <p className="text-xs text-gray-400">No restock template configured.</p>;
  }

  const needsRestock = guidance.lines.filter((l) => l.needed > 0);
  if (needsRestock.length === 0) {
    return (
      <div className="flex items-center gap-2 text-green-600 dark:text-green-400 text-sm">
        <Package className="h-4 w-4" />
        <span>All parts at target levels</span>
      </div>
    );
  }

  return (
    <div className="space-y-2">
      <div className="flex items-center gap-2 text-amber-600 dark:text-amber-400 text-sm">
        <AlertTriangle className="h-4 w-4" />
        <span>{needsRestock.length} part{needsRestock.length !== 1 ? 's' : ''} below target</span>
      </div>
      <div className="max-h-40 overflow-y-auto space-y-1">
        {needsRestock.slice(0, 10).map((line) => (
          <div key={line.part_id} className="flex items-center justify-between text-xs border-b border-border py-1">
            <span className="truncate flex-1">{line.part_description || line.part_number || `Part ${line.part_id}`}</span>
            <span className="shrink-0 ml-2">
              <Badge variant={line.status === 'out' ? 'danger' : 'warning'}>
                {line.current_qty}/{line.target_qty}
              </Badge>
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}


// ═══════════════════════════════════════════════════════════════════
// INVENTORY TAB
// ═══════════════════════════════════════════════════════════════════

function InventoryTab({ trailer, canMove }: { trailer: JobTrailer; canMove: boolean }) {
  const queryClient = useQueryClient();
  const [search, setSearch] = useState('');
  const [debouncedSearch, setDebouncedSearch] = useState('');

  // Debounce
  useState(() => {
    const timer = setTimeout(() => setDebouncedSearch(search), 300);
    return () => clearTimeout(timer);
  });

  const { data: inventory, isLoading } = useQuery({
    queryKey: ['trailer-inventory', trailer.id, debouncedSearch],
    queryFn: () => getTrailerInventory(trailer.id, { search: debouncedSearch || undefined }),
    staleTime: 15_000,
  });

  // ── Consume to job ──
  const consumeMutation = useMutation({
    mutationFn: (params: { part_id: number; qty: number; job_id: number }) =>
      consumeTrailerToJob(trailer.id, params),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['trailer-inventory'] });
      queryClient.invalidateQueries({ queryKey: ['trailer-restock'] });
      toast.success('Parts consumed to job');
    },
    onError: () => toast.error('Failed to consume parts'),
  });

  // ── Return to warehouse ──
  const returnMutation = useMutation({
    mutationFn: (params: { part_id: number; qty: number }) =>
      returnTrailerInventory(trailer.id, params),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['trailer-inventory'] });
      queryClient.invalidateQueries({ queryKey: ['trailer-restock'] });
      toast.success('Parts returned to warehouse');
    },
    onError: () => toast.error('Failed to return parts'),
  });

  function handleConsume(item: TrailerInventoryItem) {
    const qty = prompt(`How many "${item.part_description || item.part_number}" to consume to job?`, '1');
    if (!qty) return;
    const jobId = prompt('Enter job ID to bill to:');
    if (!jobId) return;
    consumeMutation.mutate({ part_id: item.part_id, qty: Number(qty), job_id: Number(jobId) });
  }

  function handleReturn(item: TrailerInventoryItem) {
    const qty = prompt(`How many "${item.part_description || item.part_number}" to return to warehouse?`, String(item.qty));
    if (!qty) return;
    returnMutation.mutate({ part_id: item.part_id, qty: Number(qty) });
  }

  return (
    <div className="space-y-4">
      {/* Search */}
      <div className="flex items-center gap-3 flex-wrap">
        <div className="flex-1 min-w-[200px]">
          <Input
            placeholder="Search inventory..."
            value={search}
            onChange={(e) => { setSearch(e.target.value); setDebouncedSearch(e.target.value); }}
            icon={<Search className="h-4 w-4" />}
          />
        </div>
      </div>

      {isLoading ? (
        <PageSpinner label="Loading inventory..." />
      ) : !inventory || inventory.length === 0 ? (
        <EmptyState
          icon={<Package className="h-12 w-12" />}
          title="No inventory on trailer"
          description="Preload parts from the warehouse to get started."
        />
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="text-left text-xs text-gray-500 dark:text-gray-400 border-b border-border">
                <th className="py-2 pr-3">Part</th>
                <th className="py-2 pr-3">Category</th>
                <th className="py-2 pr-3">Brand</th>
                <th className="py-2 pr-3 text-right">Qty</th>
                <th className="py-2 pr-3">Supplier</th>
                {canMove && <th className="py-2 text-right">Actions</th>}
              </tr>
            </thead>
            <tbody>
              {inventory.map((item) => (
                <tr key={item.id} className="border-b border-border hover:bg-surface-secondary">
                  <td className="py-2 pr-3">
                    <div className="font-medium">{item.part_description || '—'}</div>
                    {item.part_number && (
                      <span className="text-xs text-gray-400 font-mono">{item.part_number}</span>
                    )}
                  </td>
                  <td className="py-2 pr-3 text-xs">{item.category || '—'}</td>
                  <td className="py-2 pr-3 text-xs">{item.brand || '—'}</td>
                  <td className="py-2 pr-3 text-right font-mono">{item.qty}</td>
                  <td className="py-2 pr-3 text-xs">{item.supplier_name || '—'}</td>
                  {canMove && (
                    <td className="py-2 text-right">
                      <div className="flex gap-1 justify-end">
                        <button
                          onClick={() => handleConsume(item)}
                          className="p-1.5 rounded text-blue-500 hover:bg-blue-50 dark:hover:bg-blue-900/30"
                          title="Consume to job"
                        >
                          <ArrowUpFromLine className="h-3.5 w-3.5" />
                        </button>
                        <button
                          onClick={() => handleReturn(item)}
                          className="p-1.5 rounded text-gray-500 hover:bg-gray-100 dark:hover:bg-gray-800"
                          title="Return to warehouse"
                        >
                          <RotateCcw className="h-3.5 w-3.5" />
                        </button>
                      </div>
                    </td>
                  )}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}


// ═══════════════════════════════════════════════════════════════════
// LOCATION HISTORY TAB
// ═══════════════════════════════════════════════════════════════════

const LOCATION_KIND_LABELS: Record<string, string> = {
  warehouse: 'At Warehouse',
  job: 'At Job Site',
  road: 'On the Road',
  other: 'Other',
};

const EVENT_TYPE_LABELS: Record<string, string> = {
  check_in: 'Check-In',
  departed: 'Departed',
  arrived_job: 'Arrived at Job',
  arrived_warehouse: 'Arrived at Warehouse',
  manual_update: 'Manual Update',
};

function LocationTab({ trailer, canManage }: { trailer: JobTrailer; canManage: boolean }) {
  const queryClient = useQueryClient();
  const [showForm, setShowForm] = useState(false);
  const [eventType, setEventType] = useState<TrailerLocationEventType>('check_in');
  const [locationKind, setLocationKind] = useState<TrailerLocationKind>('warehouse');
  const [eventNotes, setEventNotes] = useState('');

  const { data: events, isLoading } = useQuery({
    queryKey: ['trailer-location-events', trailer.id],
    queryFn: () => listTrailerLocationEvents(trailer.id, { limit: 100 }),
    staleTime: 15_000,
  });

  const createMutation = useMutation({
    mutationFn: (event: TrailerLocationEventCreate) =>
      createTrailerLocationEvent(trailer.id, event),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['trailer-location-events'] });
      toast.success('Location event created');
      setShowForm(false);
      setEventNotes('');
    },
    onError: () => toast.error('Failed to record location event'),
  });

  function handleCreate() {
    createMutation.mutate({
      event_type: eventType,
      location_kind: locationKind,
      notes: eventNotes.trim() || undefined,
    });
  }

  return (
    <div className="space-y-4">
      {/* New event button */}
      {canManage && (
        <div className="flex justify-end">
          <Button
            size="sm"
            icon={<Plus className="h-4 w-4" />}
            onClick={() => setShowForm(!showForm)}
          >
            <span className="hidden sm:inline">Record Location</span>
          </Button>
        </div>
      )}

      {/* New event form */}
      {showForm && (
        <Card>
          <div className="p-4 space-y-3">
            <h4 className="text-sm font-semibold">Record Location Event</h4>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
              <div>
                <label className="block text-xs font-medium mb-1">Event Type</label>
                <select
                  value={eventType}
                  onChange={(e) => setEventType(e.target.value as TrailerLocationEventType)}
                  className="w-full rounded-md border border-border bg-surface px-3 py-2 text-sm"
                >
                  {Object.entries(EVENT_TYPE_LABELS).map(([k, v]) => (
                    <option key={k} value={k}>{v}</option>
                  ))}
                </select>
              </div>
              <div>
                <label className="block text-xs font-medium mb-1">Location Kind</label>
                <select
                  value={locationKind}
                  onChange={(e) => setLocationKind(e.target.value as TrailerLocationKind)}
                  className="w-full rounded-md border border-border bg-surface px-3 py-2 text-sm"
                >
                  {Object.entries(LOCATION_KIND_LABELS).map(([k, v]) => (
                    <option key={k} value={k}>{v}</option>
                  ))}
                </select>
              </div>
            </div>
            <div>
              <label className="block text-xs font-medium mb-1">Notes</label>
              <textarea
                value={eventNotes}
                onChange={(e) => setEventNotes(e.target.value)}
                rows={2}
                className="w-full rounded-md border border-border bg-surface px-3 py-2 text-sm"
                placeholder="Optional notes..."
              />
            </div>
            <div className="flex gap-2">
              <Button size="sm" onClick={handleCreate} isLoading={createMutation.isPending}>
                Save
              </Button>
              <Button variant="secondary" size="sm" onClick={() => setShowForm(false)}>
                Cancel
              </Button>
            </div>
          </div>
        </Card>
      )}

      {/* Timeline */}
      {isLoading ? (
        <PageSpinner label="Loading location history..." />
      ) : !events || events.length === 0 ? (
        <EmptyState
          icon={<MapPin className="h-12 w-12" />}
          title="No location events"
          description="Record the trailer's location to start tracking its movements."
        />
      ) : (
        <div className="space-y-0">
          {events.map((event, idx) => (
            <div key={event.id} className="flex gap-3">
              {/* Timeline line */}
              <div className="flex flex-col items-center">
                <div className={`w-3 h-3 rounded-full shrink-0 ${
                  idx === 0 ? 'bg-primary-500' : 'bg-gray-300 dark:bg-gray-600'
                }`} />
                {idx < events.length - 1 && (
                  <div className="w-0.5 flex-1 bg-gray-200 dark:bg-gray-700" />
                )}
              </div>

              {/* Event content */}
              <div className="pb-4 flex-1 min-w-0">
                <div className="flex items-center gap-2 flex-wrap">
                  <span className="text-sm font-medium">
                    {EVENT_TYPE_LABELS[event.event_type] || event.event_type}
                  </span>
                  <Badge variant="default">
                    {LOCATION_KIND_LABELS[event.location_kind] || event.location_kind}
                  </Badge>
                </div>
                <div className="flex items-center gap-3 text-xs text-gray-500 dark:text-gray-400 mt-0.5 flex-wrap">
                  {event.recorded_at && (
                    <span className="flex items-center gap-1">
                      <Clock className="h-3 w-3" />
                      {new Date(event.recorded_at).toLocaleString()}
                    </span>
                  )}
                  {event.recorded_by_name && (
                    <span className="flex items-center gap-1">
                      <User className="h-3 w-3" />
                      {event.recorded_by_name}
                    </span>
                  )}
                  {event.warehouse_name && (
                    <span className="flex items-center gap-1">
                      <Warehouse className="h-3 w-3" />
                      {event.warehouse_name}
                    </span>
                  )}
                  {event.job_name && (
                    <span className="flex items-center gap-1">
                      <Briefcase className="h-3 w-3" />
                      {event.job_name}
                    </span>
                  )}
                </div>
                {event.notes && (
                  <p className="text-xs text-gray-600 dark:text-gray-400 mt-1">{event.notes}</p>
                )}
                {event.lat != null && event.lng != null && (
                  <p className="text-xs text-gray-400 mt-0.5 font-mono">
                    GPS: {event.lat.toFixed(5)}, {event.lng.toFixed(5)}
                  </p>
                )}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}


// ═══════════════════════════════════════════════════════════════════
// TEMPLATES TAB
// ═══════════════════════════════════════════════════════════════════

function TemplatesTab({ trailer }: { trailer: JobTrailer }) {
  const { data: templates, isLoading } = useQuery({
    queryKey: ['trailer-templates', trailer.id],
    queryFn: () => listTrailerTemplates({ trailer_id: trailer.id, include_global: true }),
    staleTime: 30_000,
  });

  if (isLoading) return <PageSpinner label="Loading templates..." />;

  return (
    <div className="space-y-4">
      {!templates || templates.length === 0 ? (
        <EmptyState
          icon={<ClipboardList className="h-12 w-12" />}
          title="No stock templates"
          description="Stock templates define target inventory levels for this trailer. Create one to enable restock guidance."
        />
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
          {templates.map((tmpl) => (
            <Card key={tmpl.id}>
              <div className="p-4">
                <div className="flex items-center justify-between mb-2">
                  <h4 className="text-sm font-semibold">{tmpl.name}</h4>
                  <div className="flex gap-1">
                    {tmpl.is_default && <Badge variant="success">Default</Badge>}
                    {!tmpl.trailer_id && <Badge variant="default">Global</Badge>}
                  </div>
                </div>
                {tmpl.notes && (
                  <p className="text-xs text-gray-500 dark:text-gray-400 mb-2">{tmpl.notes}</p>
                )}
                {tmpl.lines && tmpl.lines.length > 0 ? (
                  <div className="space-y-1 max-h-32 overflow-y-auto">
                    {tmpl.lines.map((line) => (
                      <div key={line.id} className="flex justify-between text-xs border-b border-border py-1">
                        <span className="truncate flex-1">{line.part_description || line.part_number || `Part ${line.part_id}`}</span>
                        <span className="shrink-0 ml-2 font-mono">
                          target: {line.target_qty} / min: {line.min_qty}
                        </span>
                      </div>
                    ))}
                  </div>
                ) : (
                  <p className="text-xs text-gray-400">No lines defined</p>
                )}
              </div>
            </Card>
          ))}
        </div>
      )}
    </div>
  );
}
