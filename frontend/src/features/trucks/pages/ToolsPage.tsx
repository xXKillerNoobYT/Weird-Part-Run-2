/**
 * TruckToolsPage — per-truck tool management.
 *
 * Operational view: select a truck, see what tools are on it,
 * checkout available tools from the warehouse, and return tools.
 */

import { useState, useEffect, useMemo } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  Wrench, Search, X, ChevronRight, Truck, Warehouse,
  AlertTriangle, Star, Shield, ArrowDownToLine, ArrowUpFromLine,
  CheckCircle, Clock, QrCode, Printer, Briefcase,
} from 'lucide-react';
import QRCode from 'qrcode';
import { PageSpinner } from '../../../components/ui/Spinner';
import { EmptyState } from '../../../components/ui/EmptyState';
import { Button } from '../../../components/ui/Button';
import { Input } from '../../../components/ui/Input';
import { Modal } from '../../../components/ui/Modal';
import { Badge } from '../../../components/ui/Badge';
import { Card } from '../../../components/ui/Card';
import { useAuthStore } from '../../../stores/auth-store';
import { PERMISSIONS } from '../../../lib/constants';
import {
  getToolsAtLocation, getTools, checkoutTool, returnTool,
  getRecentMovements,
} from '../../../api/tools';
import { listVehicles } from '../../../api/vehicles';
import type {
  Tool, ToolStatus, ToolCategory, ToolMovement, ToolCheckoutRequest,
} from '../../../lib/types';
import type { VehicleListItem } from '../../../lib/types';
import type { ToolListParams } from '../../../api/tools';


// ── Constants ─────────────────────────────────────────────────────

const CATEGORIES: { value: ToolCategory; label: string }[] = [
  { value: 'power_tool', label: 'Power Tool' },
  { value: 'hand_tool', label: 'Hand Tool' },
  { value: 'meter', label: 'Meter' },
  { value: 'safety', label: 'Safety' },
  { value: 'conduit', label: 'Conduit' },
  { value: 'cable', label: 'Cable' },
  { value: 'lighting', label: 'Lighting' },
  { value: 'general', label: 'General' },
];

const STATUS_BADGE: Record<ToolStatus, 'success' | 'warning' | 'danger' | 'default' | 'primary'> = {
  available: 'success',
  checked_out: 'primary',
  in_maintenance: 'warning',
  damaged: 'danger',
  lost: 'danger',
  retired: 'default',
};

function categoryLabel(cat: string): string {
  return CATEGORIES.find((c) => c.value === cat)?.label ?? cat;
}

function locationIcon(type: string | null) {
  if (type === 'truck') return <Truck size={14} className="text-blue-500" />;
  if (type === 'job') return <Briefcase size={14} className="text-amber-500" />;
  return <Warehouse size={14} className="text-gray-400 dark:text-gray-500" />;
}

/** Open a print window with QR label using safe DOM manipulation. */
function printQrLabel(qrDataUrl: string, tool: Tool) {
  const win = window.open('', '_blank', 'width=400,height=500');
  if (!win) return;

  const doc = win.document;
  doc.title = `Tool Label — ${tool.tool_number}`;

  const body = doc.body;
  body.style.fontFamily = 'sans-serif';
  body.style.textAlign = 'center';
  body.style.padding = '24px';

  const img = doc.createElement('img');
  img.src = qrDataUrl;
  img.width = 200;
  img.height = 200;
  body.appendChild(img);

  const h2 = doc.createElement('h2');
  h2.style.margin = '8px 0 4px';
  h2.textContent = tool.tool_number;
  body.appendChild(h2);

  const pName = doc.createElement('p');
  pName.style.cssText = 'margin:0;font-size:14px;color:#666;';
  pName.textContent = tool.name;
  body.appendChild(pName);

  const pCat = doc.createElement('p');
  pCat.style.cssText = 'margin:4px 0;font-size:12px;color:#999;';
  pCat.textContent = categoryLabel(tool.category);
  body.appendChild(pCat);

  win.print();
}


// ═══════════════════════════════════════════════════════════════════
// MAIN PAGE
// ═══════════════════════════════════════════════════════════════════

export function ToolsPage() {
  const queryClient = useQueryClient();
  const { hasPermission } = useAuthStore();
  const canCheckout = hasPermission(PERMISSIONS.CHECKOUT_TOOLS);

  // ── Vehicle selection ────────────────────────────────────────────
  const [selectedVehicleId, setSelectedVehicleId] = useState<number | null>(null);
  const [showCheckout, setShowCheckout] = useState(false);
  const [showMovements, setShowMovements] = useState(false);
  const [selectedTool, setSelectedTool] = useState<Tool | null>(null);
  const [returningToolId, setReturningToolId] = useState<number | null>(null);

  // ── Queries ──────────────────────────────────────────────────────
  const { data: vehicles, isLoading: vehiclesLoading } = useQuery({
    queryKey: ['vehicles-list'],
    queryFn: () => listVehicles({ status: 'active' }),
    staleTime: 60_000,
  });

  // Auto-select first vehicle
  useEffect(() => {
    if (vehicles && vehicles.length > 0 && selectedVehicleId === null) {
      setSelectedVehicleId(vehicles[0].id);
    }
  }, [vehicles, selectedVehicleId]);

  // Tools on selected truck
  const { data: truckTools, isLoading: toolsLoading, refetch: refetchTools } = useQuery({
    queryKey: ['truck-tools', selectedVehicleId],
    queryFn: () => getToolsAtLocation('truck', selectedVehicleId!),
    enabled: selectedVehicleId !== null,
    staleTime: 15_000,
  });

  // Recent movements for this truck
  const { data: movements } = useQuery({
    queryKey: ['truck-tool-movements', selectedVehicleId],
    queryFn: () => getRecentMovements(20),
    enabled: selectedVehicleId !== null && showMovements,
    staleTime: 30_000,
  });

  // ── Return mutation ──────────────────────────────────────────────
  const returnMutation = useMutation({
    mutationFn: (toolId: number) => returnTool(toolId, {
      to_location_type: 'warehouse',
      to_location_id: 1,
    }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['truck-tools'] });
      queryClient.invalidateQueries({ queryKey: ['tools'] });
      queryClient.invalidateQueries({ queryKey: ['tools-dashboard'] });
      setReturningToolId(null);
    },
  });

  // ── Derived ──────────────────────────────────────────────────────
  const tools = truckTools ?? [];
  const selectedVehicle = vehicles?.find((v) => v.id === selectedVehicleId);

  // Filter movements to this truck
  const truckMovements = useMemo(() => {
    if (!movements || !selectedVehicleId) return [];
    return movements.filter(
      (m) =>
        (m.from_location_type === 'truck' && m.from_location_id === selectedVehicleId) ||
        (m.to_location_type === 'truck' && m.to_location_id === selectedVehicleId)
    );
  }, [movements, selectedVehicleId]);

  // Stats
  const withKit = tools.filter((t) => t.has_kit === 1).length;
  const needsMaintenance = tools.filter((t) => t.overdue_maintenance_count > 0).length;

  if (vehiclesLoading) return <PageSpinner label="Loading vehicles..." />;

  if (!vehicles || vehicles.length === 0) {
    return (
      <EmptyState
        icon={<Truck className="h-12 w-12" />}
        title="No Vehicles"
        description="No active vehicles found. Add vehicles in the Fleet section first."
      />
    );
  }

  return (
    <div className="space-y-4">
      {/* Header + vehicle selector */}
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div className="flex items-center gap-3 min-w-0">
          <div className="min-w-0">
            <h1 className="text-xl font-semibold text-gray-900 dark:text-gray-100">
              Truck Tools
            </h1>
            <p className="text-sm text-gray-500 dark:text-gray-400">
              {tools.length} tool{tools.length !== 1 ? 's' : ''} on this vehicle
            </p>
          </div>
        </div>

        <div className="flex items-center gap-2 flex-wrap">
          {/* Vehicle selector */}
          <select
            value={selectedVehicleId ?? ''}
            onChange={(e) => setSelectedVehicleId(Number(e.target.value))}
            className="text-sm rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 px-3 py-2"
          >
            {vehicles.map((v) => (
              <option key={v.id} value={v.id}>
                {v.vehicle_number} — {v.vehicle_name}
              </option>
            ))}
          </select>

          <Button
            variant="ghost"
            size="sm"
            icon={<Clock size={16} />}
            onClick={() => setShowMovements(!showMovements)}
          >
            <span className="hidden sm:inline">History</span>
          </Button>

          {canCheckout && (
            <Button
              size="sm"
              icon={<ArrowDownToLine size={16} />}
              onClick={() => setShowCheckout(true)}
            >
              <span className="hidden sm:inline">Checkout Tool</span>
            </Button>
          )}
        </div>
      </div>

      {/* Stats bar */}
      <div className="grid grid-cols-3 gap-3">
        <div className="flex items-center gap-3 bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-lg p-3">
          <Wrench size={16} className="text-blue-500 flex-shrink-0" />
          <div className="min-w-0">
            <p className="text-lg font-semibold text-gray-900 dark:text-gray-100">{tools.length}</p>
            <p className="text-xs text-gray-500 dark:text-gray-400 truncate">On Truck</p>
          </div>
        </div>
        <div className="flex items-center gap-3 bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-lg p-3">
          <Shield size={16} className="text-purple-500 flex-shrink-0" />
          <div className="min-w-0">
            <p className="text-lg font-semibold text-gray-900 dark:text-gray-100">{withKit}</p>
            <p className="text-xs text-gray-500 dark:text-gray-400 truncate">With Kit</p>
          </div>
        </div>
        <div className="flex items-center gap-3 bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-lg p-3">
          <AlertTriangle size={16} className={needsMaintenance > 0 ? 'text-red-500' : 'text-gray-400 dark:text-gray-500'} />
          <div className="min-w-0">
            <p className="text-lg font-semibold text-gray-900 dark:text-gray-100">{needsMaintenance}</p>
            <p className="text-xs text-gray-500 dark:text-gray-400 truncate">Needs Service</p>
          </div>
        </div>
      </div>

      {/* Movement history panel */}
      {showMovements && truckMovements.length > 0 && (
        <MovementHistoryPanel movements={truckMovements} />
      )}

      {/* Return error */}
      {returnMutation.isError && (
        <div className="p-3 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-lg text-sm text-red-600 dark:text-red-400">
          Failed to return tool. {returnMutation.error?.message}
        </div>
      )}

      {/* Tool list */}
      {toolsLoading ? (
        <PageSpinner label="Loading tools..." />
      ) : tools.length === 0 ? (
        <EmptyState
          icon={<Wrench size={48} />}
          title="No Tools on This Vehicle"
          description="Checkout tools from the warehouse to load this truck."
          action={canCheckout ? (
            <Button size="sm" icon={<ArrowDownToLine size={16} />} onClick={() => setShowCheckout(true)}>
              Checkout Tool
            </Button>
          ) : undefined}
        />
      ) : (
        <div className="space-y-2">
          {tools.map((tool) => (
            <TruckToolRow
              key={tool.id}
              tool={tool}
              canReturn={canCheckout}
              isReturning={returningToolId === tool.id && returnMutation.isPending}
              onReturn={() => {
                setReturningToolId(tool.id);
                returnMutation.mutate(tool.id);
              }}
              onClick={() => setSelectedTool(tool)}
            />
          ))}
        </div>
      )}

      {/* Checkout modal */}
      {showCheckout && selectedVehicleId && (
        <CheckoutModal
          vehicleId={selectedVehicleId}
          vehicleName={selectedVehicle ? `${selectedVehicle.vehicle_number} — ${selectedVehicle.vehicle_name}` : ''}
          onClose={() => setShowCheckout(false)}
          onComplete={() => {
            refetchTools();
            queryClient.invalidateQueries({ queryKey: ['tools'] });
            queryClient.invalidateQueries({ queryKey: ['tools-dashboard'] });
            setShowCheckout(false);
          }}
        />
      )}

      {/* Tool detail panel */}
      {selectedTool && (
        <ToolDetailPanel
          tool={selectedTool}
          onClose={() => setSelectedTool(null)}
        />
      )}
    </div>
  );
}


// ═══════════════════════════════════════════════════════════════════
// Truck Tool Row (with return button)
// ═══════════════════════════════════════════════════════════════════

function TruckToolRow({ tool, canReturn, isReturning, onReturn, onClick }: {
  tool: Tool;
  canReturn: boolean;
  isReturning: boolean;
  onReturn: () => void;
  onClick: () => void;
}) {
  return (
    <div className="bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-lg p-3 sm:p-4 hover:border-primary-300 dark:hover:border-primary-600 transition-all">
      <div className="flex items-start gap-3">
        {/* Icon */}
        <button
          onClick={onClick}
          className="flex-shrink-0 w-10 h-10 rounded-full bg-primary-100 dark:bg-primary-900/30 flex items-center justify-center text-primary-700 dark:text-primary-300 hover:ring-2 ring-primary-400 transition-all"
        >
          <Wrench size={18} />
        </button>

        {/* Info — clickable for detail */}
        <button onClick={onClick} className="flex-1 min-w-0 text-left">
          <div className="flex items-center gap-2 flex-wrap">
            <span className="font-medium text-gray-900 dark:text-gray-100 truncate">
              {tool.name}
            </span>
            <Badge variant={STATUS_BADGE[tool.status as ToolStatus] ?? 'default'}>
              {tool.status.replace('_', ' ')}
            </Badge>
            {tool.has_kit === 1 && (
              <span className="hidden sm:inline-flex items-center gap-1 text-xs text-purple-600 dark:text-purple-400">
                <Shield size={12} /> Kit
              </span>
            )}
          </div>

          <div className="flex items-center gap-3 mt-1 text-xs text-gray-500 dark:text-gray-400 flex-wrap">
            <span className="font-mono">{tool.tool_number}</span>
            <span>{categoryLabel(tool.category)}</span>
            {tool.brand && <span className="hidden sm:inline">{tool.brand}</span>}
            {tool.assigned_to_name && (
              <span className="hidden sm:inline">→ {tool.assigned_to_name}</span>
            )}
          </div>

          {/* Condition + maintenance */}
          <div className="flex items-center gap-3 mt-1">
            {tool.condition_rating && (
              <span className="flex items-center gap-0.5">
                {[1, 2, 3, 4, 5].map((n) => (
                  <Star
                    key={n}
                    size={12}
                    className={n <= tool.condition_rating! ? 'text-amber-400 fill-amber-400' : 'text-gray-300 dark:text-gray-600'}
                  />
                ))}
              </span>
            )}
            {tool.overdue_maintenance_count > 0 && (
              <span className="flex items-center gap-1 text-xs text-red-500">
                <AlertTriangle size={12} /> {tool.overdue_maintenance_count} overdue
              </span>
            )}
          </div>
        </button>

        {/* Return button */}
        <div className="flex items-center gap-2 flex-shrink-0">
          {canReturn && (
            <Button
              variant="ghost"
              size="sm"
              icon={<ArrowUpFromLine size={14} />}
              onClick={(e) => {
                e.stopPropagation();
                onReturn();
              }}
              isLoading={isReturning}
              disabled={isReturning}
            >
              <span className="hidden sm:inline">Return</span>
            </Button>
          )}
          <button onClick={onClick} className="text-gray-300 dark:text-gray-600 hover:text-primary-400 transition-colors">
            <ChevronRight size={18} />
          </button>
        </div>
      </div>
    </div>
  );
}


// ═══════════════════════════════════════════════════════════════════
// Movement History Panel
// ═══════════════════════════════════════════════════════════════════

function MovementHistoryPanel({ movements }: { movements: ToolMovement[] }) {
  return (
    <Card noPadding>
      <div className="p-4">
        <h3 className="text-sm font-medium text-gray-900 dark:text-gray-100 flex items-center gap-2 mb-3">
          <Clock size={14} /> Recent Movement History
        </h3>
        <div className="space-y-2 max-h-64 overflow-y-auto">
          {movements.map((m) => (
            <div
              key={m.id}
              className="flex items-center justify-between text-xs bg-gray-50 dark:bg-gray-700/50 rounded-md px-3 py-2"
            >
              <div className="flex items-center gap-2 min-w-0">
                <span className={
                  m.movement_type === 'checkout' ? 'text-blue-500' :
                  m.movement_type === 'return' ? 'text-green-500' :
                  'text-gray-400 dark:text-gray-500'
                }>
                  {m.movement_type === 'checkout' ? <ArrowDownToLine size={12} /> :
                   m.movement_type === 'return' ? <ArrowUpFromLine size={12} /> :
                   <ChevronRight size={12} />}
                </span>
                <span className="font-medium text-gray-900 dark:text-gray-100 truncate">
                  {m.tool_name ?? `Tool #${m.tool_id}`}
                </span>
                <span className="text-gray-500 dark:text-gray-400 capitalize">
                  {m.movement_type.replace('_', ' ')}
                </span>
              </div>
              <span className="text-gray-400 dark:text-gray-500 whitespace-nowrap ml-2">
                {new Date(m.created_at).toLocaleDateString()}
              </span>
            </div>
          ))}
          {movements.length === 0 && (
            <p className="text-xs text-gray-400 dark:text-gray-500 text-center py-4">No recent movements</p>
          )}
        </div>
      </div>
    </Card>
  );
}


// ═══════════════════════════════════════════════════════════════════
// Checkout Modal — search warehouse tools, pick one, checkout
// ═══════════════════════════════════════════════════════════════════

function CheckoutModal({ vehicleId, vehicleName, onClose, onComplete }: {
  vehicleId: number;
  vehicleName: string;
  onClose: () => void;
  onComplete: () => void;
}) {
  const [search, setSearch] = useState('');
  const [debouncedSearch, setDebouncedSearch] = useState('');

  // Debounce search
  useEffect(() => {
    const timer = setTimeout(() => setDebouncedSearch(search), 300);
    return () => clearTimeout(timer);
  }, [search]);

  // Query available warehouse tools
  const { data, isLoading } = useQuery({
    queryKey: ['available-warehouse-tools', debouncedSearch],
    queryFn: () => {
      const params: ToolListParams = {
        status: 'available',
        location_type: 'warehouse',
        search: debouncedSearch || undefined,
        page_size: 50,
      };
      return getTools(params);
    },
    staleTime: 10_000,
  });

  // Checkout mutation
  const checkoutMutation = useMutation({
    mutationFn: ({ toolId, body }: { toolId: number; body: ToolCheckoutRequest }) =>
      checkoutTool(toolId, body),
    onSuccess: () => onComplete(),
  });

  const handleCheckout = (tool: Tool) => {
    checkoutMutation.mutate({
      toolId: tool.id,
      body: {
        to_location_type: 'truck',
        to_location_id: vehicleId,
      },
    });
  };

  const availableTools = data?.items ?? [];

  return (
    <Modal isOpen onClose={onClose} title="Checkout Tool to Truck" size="lg">
      <div className="space-y-4">
        {/* Target info */}
        <div className="flex items-center gap-2 bg-blue-50 dark:bg-blue-900/20 border border-blue-200 dark:border-blue-800 rounded-lg px-3 py-2">
          <Truck size={16} className="text-blue-500" />
          <span className="text-sm text-blue-700 dark:text-blue-300">
            Checking out to: <strong>{vehicleName}</strong>
          </span>
        </div>

        {/* Search */}
        <Input
          placeholder="Search available tools..."
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          icon={<Search size={16} />}
          iconRight={search ? (
            <button onClick={() => setSearch('')} className="p-1 hover:bg-gray-100 dark:hover:bg-gray-700 rounded">
              <X size={14} />
            </button>
          ) : undefined}
        />

        {/* Error */}
        {checkoutMutation.isError && (
          <div className="p-3 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-lg text-sm text-red-600 dark:text-red-400">
            Checkout failed. {checkoutMutation.error?.message}
          </div>
        )}

        {/* Available tools list */}
        {isLoading ? (
          <div className="py-8 text-center text-sm text-gray-400">Loading available tools...</div>
        ) : availableTools.length === 0 ? (
          <div className="py-8 text-center">
            <Warehouse size={32} className="mx-auto text-gray-300 dark:text-gray-600 mb-2" />
            <p className="text-sm text-gray-500 dark:text-gray-400">
              {search ? `No available tools matching "${search}"` : 'No tools available at warehouse'}
            </p>
          </div>
        ) : (
          <div className="space-y-2 max-h-96 overflow-y-auto">
            {availableTools.map((tool) => (
              <button
                key={tool.id}
                onClick={() => handleCheckout(tool)}
                disabled={checkoutMutation.isPending}
                className="w-full text-left bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-lg p-3 hover:border-blue-300 dark:hover:border-blue-600 hover:bg-blue-50/50 dark:hover:bg-blue-900/10 transition-all disabled:opacity-50"
              >
                <div className="flex items-center gap-3">
                  <div className="flex-shrink-0 w-8 h-8 rounded-full bg-green-100 dark:bg-green-900/30 flex items-center justify-center text-green-700 dark:text-green-300">
                    <Wrench size={14} />
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2">
                      <span className="font-medium text-gray-900 dark:text-gray-100 truncate text-sm">
                        {tool.name}
                      </span>
                      {tool.has_kit === 1 && (
                        <span className="inline-flex items-center gap-1 text-xs text-purple-600 dark:text-purple-400">
                          <Shield size={10} />
                        </span>
                      )}
                    </div>
                    <div className="flex items-center gap-2 text-xs text-gray-500 dark:text-gray-400">
                      <span className="font-mono">{tool.tool_number}</span>
                      <span>{categoryLabel(tool.category)}</span>
                      {tool.brand && <span className="hidden sm:inline">{tool.brand}</span>}
                    </div>
                  </div>
                  <ArrowDownToLine size={16} className="text-blue-400 flex-shrink-0" />
                </div>
              </button>
            ))}
          </div>
        )}

        <p className="text-xs text-gray-400 dark:text-gray-500 text-center">
          {availableTools.length} available tool{availableTools.length !== 1 ? 's' : ''} at warehouse
        </p>
      </div>
    </Modal>
  );
}


// ═══════════════════════════════════════════════════════════════════
// Tool Detail Panel
// ═══════════════════════════════════════════════════════════════════

function ToolDetailPanel({ tool, onClose }: {
  tool: Tool;
  onClose: () => void;
}) {
  const [qrDataUrl, setQrDataUrl] = useState<string | null>(null);

  useEffect(() => {
    const url = `${window.location.origin}/tools/scan/${tool.tool_number}`;
    QRCode.toDataURL(url, { width: 200, margin: 2, color: { dark: '#000000', light: '#FFFFFF' } })
      .then(setQrDataUrl)
      .catch(() => setQrDataUrl(null));
  }, [tool.tool_number]);

  return (
    <Modal isOpen onClose={onClose} title="Tool Details" size="lg">
      <div className="space-y-5">
        {/* Header info */}
        <div className="flex items-start gap-4">
          <div className="flex-shrink-0 w-24 h-24 bg-white border border-gray-200 dark:border-gray-700 rounded-lg flex items-center justify-center">
            {qrDataUrl ? (
              <img src={qrDataUrl} alt="QR Code" className="w-20 h-20" />
            ) : (
              <QrCode size={40} className="text-gray-300 dark:text-gray-600" />
            )}
          </div>

          <div className="flex-1 min-w-0">
            <h3 className="text-lg font-semibold text-gray-900 dark:text-gray-100">{tool.name}</h3>
            <p className="text-sm text-gray-500 dark:text-gray-400 font-mono">{tool.tool_number}</p>
            <div className="flex items-center gap-2 mt-1 flex-wrap">
              <Badge variant={STATUS_BADGE[tool.status as ToolStatus] ?? 'default'}>
                {tool.status.replace('_', ' ')}
              </Badge>
              <Badge>{categoryLabel(tool.category)}</Badge>
              {tool.has_kit === 1 && <Badge variant="primary">Has Kit</Badge>}
            </div>
          </div>

          {qrDataUrl && (
            <Button variant="ghost" size="sm" icon={<Printer size={16} />} onClick={() => printQrLabel(qrDataUrl, tool)}>
              <span className="hidden sm:inline">Print</span>
            </Button>
          )}
        </div>

        {/* Details grid */}
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
          <DetailField label="Location" value={
            <span className="flex items-center gap-1.5">
              {locationIcon(tool.location_type)}
              {tool.location_name ?? tool.location_type}
            </span>
          } />
          <DetailField label="Assigned To" value={tool.assigned_to_name ?? '—'} />
          <DetailField label="Brand" value={tool.brand ?? '—'} />
          <DetailField label="Model" value={tool.model_number ?? '—'} />
          <DetailField label="Serial #" value={tool.serial_number ?? '—'} />
          <DetailField label="Condition" value={
            tool.condition_rating ? (
              <span className="flex items-center gap-0.5">
                {[1, 2, 3, 4, 5].map((n) => (
                  <Star
                    key={n}
                    size={14}
                    className={n <= tool.condition_rating! ? 'text-amber-400 fill-amber-400' : 'text-gray-300 dark:text-gray-600'}
                  />
                ))}
              </span>
            ) : '—'
          } />
          {tool.purchase_date && <DetailField label="Purchase Date" value={tool.purchase_date} />}
          {tool.purchase_cost != null && <DetailField label="Purchase Cost" value={`$${tool.purchase_cost.toFixed(2)}`} />}
          {tool.warranty_expiry && <DetailField label="Warranty Expires" value={tool.warranty_expiry} />}
        </div>

        {/* Maintenance info */}
        {tool.next_maintenance_due && (
          <div className="bg-amber-50 dark:bg-amber-900/20 border border-amber-200 dark:border-amber-800 rounded-lg px-4 py-3">
            <p className="text-sm text-amber-700 dark:text-amber-300 flex items-center gap-2">
              <Clock size={14} />
              Next maintenance due: {tool.next_maintenance_due}
              {tool.overdue_maintenance_count > 0 && (
                <Badge variant="danger">{tool.overdue_maintenance_count} overdue</Badge>
              )}
            </p>
          </div>
        )}

        {tool.notes && (
          <div>
            <p className="text-xs font-medium text-gray-500 dark:text-gray-400 mb-1">Notes</p>
            <p className="text-sm text-gray-700 dark:text-gray-300 whitespace-pre-wrap">{tool.notes}</p>
          </div>
        )}
      </div>
    </Modal>
  );
}

function DetailField({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div>
      <p className="text-xs font-medium text-gray-500 dark:text-gray-400">{label}</p>
      <div className="text-sm text-gray-900 dark:text-gray-100 mt-0.5">{value}</div>
    </div>
  );
}
