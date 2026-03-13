/**
 * WarehouseToolsPage — global tools registry.
 *
 * The master view of ALL company tools. Shows dashboard stats,
 * filterable list, tool detail panel, and create/edit modals.
 * Also surfaces maintenance alerts for overdue/upcoming service.
 */

import { useState, useEffect, useCallback, useRef } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  Plus, Search, Wrench, X, Filter, ChevronRight,
  AlertTriangle, Truck, Briefcase, Warehouse,
  Star, CheckCircle, QrCode, Printer, Clock, Shield,
  ChevronLeft, Download, Camera, ArrowRightLeft, DollarSign,
  Calendar, TrendingDown,
} from 'lucide-react';
import QRCode from 'qrcode';
import JsBarcode from 'jsbarcode';
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
  getTools, createTool, getToolsDashboard, getMaintenanceAlerts,
  uploadToolPhoto, transferTool, getToolDepreciation,
  exportToolsCsv,
} from '../../../api/tools';
import type {
  Tool, ToolCreate, ToolCategory, ToolStatus, ToolsDashboardStats,
  ToolMaintenanceAlert, DepreciationMethod,
} from '../../../lib/types';
import type { ToolListParams } from '../../../api/tools';

// ── Constants ─────────────────────────────────────────────────────

const PAGE_SIZES = [25, 50, 100];

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

const STATUSES: { value: ToolStatus; label: string }[] = [
  { value: 'available', label: 'Available' },
  { value: 'checked_out', label: 'Checked Out' },
  { value: 'in_maintenance', label: 'In Maintenance' },
  { value: 'damaged', label: 'Damaged' },
  { value: 'lost', label: 'Lost' },
  { value: 'retired', label: 'Retired' },
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

/** Generate Code128 barcode as data URL for a given text. */
function generateBarcodeDataUrl(text: string): string | null {
  try {
    const canvas = document.createElement('canvas');
    JsBarcode(canvas, text, {
      format: 'CODE128',
      width: 2,
      height: 50,
      displayValue: false,
      margin: 4,
    });
    return canvas.toDataURL('image/png');
  } catch {
    return null;
  }
}

/** Open a print window with QR label + Code128 barcode using safe DOM manipulation. */
function printQrLabel(qrDataUrl: string, tool: Tool) {
  const win = window.open('', '_blank', 'width=400,height=600');
  if (!win) return;

  const doc = win.document;
  doc.title = `Tool Label — ${tool.tool_number}`;

  const body = doc.body;
  body.style.fontFamily = 'sans-serif';
  body.style.textAlign = 'center';
  body.style.padding = '24px';

  // QR Code
  const qrImg = doc.createElement('img');
  qrImg.src = qrDataUrl;
  qrImg.width = 180;
  qrImg.height = 180;
  body.appendChild(qrImg);

  // Tool number heading
  const h2 = doc.createElement('h2');
  h2.style.margin = '8px 0 4px';
  h2.textContent = tool.tool_number;
  body.appendChild(h2);

  const pName = doc.createElement('p');
  pName.style.cssText = 'margin:0;font-size:14px;color:#666;';
  pName.textContent = tool.name;
  body.appendChild(pName);

  const pCat = doc.createElement('p');
  pCat.style.cssText = 'margin:4px 0 12px;font-size:12px;color:#999;';
  pCat.textContent = categoryLabel(tool.category);
  body.appendChild(pCat);

  // Code128 Barcode
  const barcodeUrl = generateBarcodeDataUrl(tool.tool_number);
  if (barcodeUrl) {
    const hr = doc.createElement('hr');
    hr.style.cssText = 'border:none;border-top:1px solid #ddd;margin:8px 0;';
    body.appendChild(hr);

    const barcodeImg = doc.createElement('img');
    barcodeImg.src = barcodeUrl;
    barcodeImg.style.cssText = 'max-width:280px;height:60px;';
    body.appendChild(barcodeImg);

    const pBarcode = doc.createElement('p');
    pBarcode.style.cssText = 'margin:2px 0 0;font-size:11px;color:#999;font-family:monospace;';
    pBarcode.textContent = tool.tool_number;
    body.appendChild(pBarcode);
  }

  win.print();
}


// ═══════════════════════════════════════════════════════════════════
// MAIN PAGE
// ═══════════════════════════════════════════════════════════════════

export function WarehouseToolsPage() {
  const queryClient = useQueryClient();
  const { hasPermission } = useAuthStore();
  const canManage = hasPermission(PERMISSIONS.MANAGE_TOOLS);

  // ── State ────────────────────────────────────────────────────────
  const [search, setSearch] = useState('');
  const [debouncedSearch, setDebouncedSearch] = useState('');
  const [categoryFilter, setCategoryFilter] = useState<string>('');
  const [statusFilter, setStatusFilter] = useState<string>('');
  const [locationFilter, setLocationFilter] = useState<string>('');
  const [page, setPage] = useState(1);
  const [pageSize, setPageSize] = useState(50);
  const [showFilters, setShowFilters] = useState(false);
  const [showCreate, setShowCreate] = useState(false);
  const [showAlerts, setShowAlerts] = useState(false);
  const [selectedTool, setSelectedTool] = useState<Tool | null>(null);

  // Debounce search
  useEffect(() => {
    const timer = setTimeout(() => {
      setDebouncedSearch(search);
      setPage(1);
    }, 300);
    return () => clearTimeout(timer);
  }, [search]);

  // Reset page on filter change
  useEffect(() => { setPage(1); }, [categoryFilter, statusFilter, locationFilter, pageSize]);

  // ── Queries ──────────────────────────────────────────────────────
  const { data, isLoading, error } = useQuery({
    queryKey: ['tools', debouncedSearch, categoryFilter, statusFilter, locationFilter, page, pageSize],
    queryFn: () => {
      const params: ToolListParams = {
        search: debouncedSearch || undefined,
        category: categoryFilter || undefined,
        status: statusFilter || undefined,
        location_type: locationFilter || undefined,
        page,
        page_size: pageSize,
      };
      return getTools(params);
    },
    staleTime: 15_000,
  });

  const { data: dashboard } = useQuery({
    queryKey: ['tools-dashboard'],
    queryFn: getToolsDashboard,
    staleTime: 30_000,
  });

  const { data: alerts } = useQuery({
    queryKey: ['tools-maintenance-alerts'],
    queryFn: () => getMaintenanceAlerts(14),
    staleTime: 60_000,
  });

  // ── Create mutation ──────────────────────────────────────────────
  const createMutation = useMutation({
    mutationFn: createTool,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['tools'] });
      queryClient.invalidateQueries({ queryKey: ['tools-dashboard'] });
      setShowCreate(false);
    },
  });

  // ── Export CSV handler ────────────────────────────────────────────
  const [exporting, setExporting] = useState(false);
  const handleExportCsv = async () => {
    try {
      setExporting(true);
      const blob = await exportToolsCsv({
        category: categoryFilter || undefined,
        status: statusFilter || undefined,
        location_type: locationFilter || undefined,
      });
      const { exportFile } = await import('../../../local/services/file-export-service');
      await exportFile(blob, `tools-export-${new Date().toISOString().slice(0, 10)}.csv`);
    } catch {
      // silent fail — user sees no file download
    } finally {
      setExporting(false);
    }
  };

  const hasActiveFilters = categoryFilter !== '' || statusFilter !== '' || locationFilter !== '';

  const clearFilters = useCallback(() => {
    setCategoryFilter('');
    setStatusFilter('');
    setLocationFilter('');
  }, []);

  if (isLoading) return <PageSpinner label="Loading tools..." />;

  if (error) {
    return (
      <div className="text-center py-16">
        <p className="text-red-500">Failed to load tools. Please try again.</p>
      </div>
    );
  }

  const tools = data?.items ?? [];
  const total = data?.total ?? 0;
  const totalPages = Math.max(1, Math.ceil(total / pageSize));
  const overdueCount = alerts?.overdue?.length ?? 0;
  const upcomingCount = alerts?.upcoming?.length ?? 0;

  return (
    <div className="space-y-4">
      {/* Dashboard Stats */}
      {dashboard && <StatsBar stats={dashboard} />}

      {/* Header */}
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div>
          <h1 className="text-xl font-semibold text-gray-900 dark:text-gray-100">
            Tools Registry
          </h1>
          <p className="text-sm text-gray-500 dark:text-gray-400">
            {total} tool{total !== 1 ? 's' : ''}
          </p>
        </div>

        <div className="flex items-center gap-2">
          {(overdueCount > 0 || upcomingCount > 0) && (
            <Button
              variant="ghost"
              size="sm"
              icon={<AlertTriangle size={16} className={overdueCount > 0 ? 'text-red-500' : 'text-amber-500'} />}
              onClick={() => setShowAlerts(!showAlerts)}
            >
              <span className="hidden sm:inline">
                {overdueCount > 0 ? `${overdueCount} Overdue` : `${upcomingCount} Upcoming`}
              </span>
            </Button>
          )}

          <Button
            variant="ghost"
            size="sm"
            icon={<Filter size={16} />}
            onClick={() => setShowFilters(!showFilters)}
          >
            <span className="hidden sm:inline">Filters</span>
          </Button>

          <Button
            variant="ghost"
            size="sm"
            icon={<Download size={16} />}
            onClick={handleExportCsv}
            disabled={exporting}
          >
            <span className="hidden sm:inline">{exporting ? 'Exporting…' : 'Export CSV'}</span>
          </Button>

          {canManage && (
            <Button
              size="sm"
              icon={<Plus size={16} />}
              onClick={() => setShowCreate(true)}
            >
              <span className="hidden sm:inline">Register Tool</span>
            </Button>
          )}
        </div>
      </div>

      {/* Search */}
      <Input
        placeholder="Search by name, number, brand, or serial..."
        value={search}
        onChange={(e) => setSearch(e.target.value)}
        icon={<Search size={16} />}
        iconRight={search ? (
          <button onClick={() => setSearch('')} className="p-1 hover:bg-gray-100 dark:hover:bg-gray-700 rounded">
            <X size={14} />
          </button>
        ) : undefined}
      />

      {/* Filter bar */}
      {showFilters && (
        <Card noPadding>
          <div className="p-3 flex items-center flex-wrap gap-3">
            <div className="flex items-center gap-1.5">
              <span className="text-xs text-gray-500 dark:text-gray-400 mr-1">Category:</span>
              <select
                value={categoryFilter}
                onChange={(e) => setCategoryFilter(e.target.value)}
                className="text-xs rounded-md border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 px-2 py-1"
              >
                <option value="">All</option>
                {CATEGORIES.map((c) => (
                  <option key={c.value} value={c.value}>{c.label}</option>
                ))}
              </select>
            </div>

            <div className="flex items-center gap-1.5">
              <span className="text-xs text-gray-500 dark:text-gray-400 mr-1">Status:</span>
              <select
                value={statusFilter}
                onChange={(e) => setStatusFilter(e.target.value)}
                className="text-xs rounded-md border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 px-2 py-1"
              >
                <option value="">All</option>
                {STATUSES.map((s) => (
                  <option key={s.value} value={s.value}>{s.label}</option>
                ))}
              </select>
            </div>

            <div className="flex items-center gap-1.5">
              <span className="text-xs text-gray-500 dark:text-gray-400 mr-1">Location:</span>
              <select
                value={locationFilter}
                onChange={(e) => setLocationFilter(e.target.value)}
                className="text-xs rounded-md border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 px-2 py-1"
              >
                <option value="">All</option>
                <option value="warehouse">Warehouse</option>
                <option value="truck">Truck</option>
                <option value="job">Job</option>
              </select>
            </div>

            {hasActiveFilters && (
              <button
                onClick={clearFilters}
                className="text-xs text-primary-600 dark:text-primary-400 hover:underline ml-auto"
              >
                Clear filters
              </button>
            )}
          </div>
        </Card>
      )}

      {/* Maintenance Alerts */}
      {showAlerts && alerts && (overdueCount > 0 || upcomingCount > 0) && (
        <MaintenanceAlertsPanel alerts={alerts} />
      )}

      {/* Tool list */}
      {tools.length === 0 ? (
        <EmptyState
          icon={<Wrench size={48} />}
          title="No tools found"
          description={search ? `No results for "${search}"` : 'No tools match the current filters.'}
          action={canManage ? <Button size="sm" onClick={() => setShowCreate(true)}>Register Tool</Button> : undefined}
        />
      ) : (
        <div className="space-y-2">
          {tools.map((tool) => (
            <ToolRow
              key={tool.id}
              tool={tool}
              onClick={() => setSelectedTool(tool)}
            />
          ))}
        </div>
      )}

      {/* Pagination */}
      {totalPages > 1 && (
        <div className="flex items-center justify-between flex-wrap gap-3 pt-2">
          <div className="flex items-center gap-2 text-sm text-gray-500 dark:text-gray-400">
            <span>Show:</span>
            <select
              value={pageSize}
              onChange={(e) => setPageSize(Number(e.target.value))}
              className="text-xs rounded border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 px-1 py-0.5"
            >
              {PAGE_SIZES.map((s) => <option key={s} value={s}>{s}</option>)}
            </select>
          </div>
          <div className="flex items-center gap-1">
            <Button variant="ghost" size="sm" disabled={page <= 1} onClick={() => setPage(page - 1)} icon={<ChevronLeft size={16} />} />
            <span className="text-sm text-gray-600 dark:text-gray-400 px-2">Page {page} of {totalPages}</span>
            <Button variant="ghost" size="sm" disabled={page >= totalPages} onClick={() => setPage(page + 1)} icon={<ChevronRight size={16} />} />
          </div>
        </div>
      )}

      {/* Create modal */}
      {showCreate && (
        <CreateToolModal
          isLoading={createMutation.isPending}
          error={createMutation.error?.message ?? null}
          onSubmit={(data) => createMutation.mutate(data)}
          onClose={() => setShowCreate(false)}
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
// Stats Bar
// ═══════════════════════════════════════════════════════════════════

function StatsBar({ stats }: { stats: ToolsDashboardStats }) {
  const items = [
    { label: 'Total', value: stats.total_tools ?? 0, icon: <Wrench size={16} />, color: 'text-gray-500 dark:text-gray-400' },
    { label: 'Available', value: stats.available ?? 0, icon: <CheckCircle size={16} />, color: 'text-green-500' },
    { label: 'Checked Out', value: stats.checked_out ?? 0, icon: <Truck size={16} />, color: 'text-blue-500' },
    { label: 'Maintenance', value: stats.in_maintenance ?? 0, icon: <Clock size={16} />, color: 'text-amber-500' },
    { label: 'Lost/Damaged', value: stats.lost_or_damaged ?? 0, icon: <AlertTriangle size={16} />, color: 'text-red-500' },
  ];

  return (
    <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-3">
      {items.map((item) => (
        <div
          key={item.label}
          className="flex items-center gap-3 bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-lg p-3"
        >
          <div className={`flex-shrink-0 ${item.color}`}>{item.icon}</div>
          <div className="min-w-0">
            <p className="text-lg font-semibold text-gray-900 dark:text-gray-100 truncate">{item.value}</p>
            <p className="text-xs text-gray-500 dark:text-gray-400 truncate">{item.label}</p>
          </div>
        </div>
      ))}
    </div>
  );
}


// ═══════════════════════════════════════════════════════════════════
// Maintenance Alerts Panel
// ═══════════════════════════════════════════════════════════════════

function MaintenanceAlertsPanel({ alerts }: { alerts: { overdue: ToolMaintenanceAlert[]; upcoming: ToolMaintenanceAlert[] } }) {
  return (
    <Card noPadding>
      <div className="p-4 space-y-3">
        {alerts.overdue.length > 0 && (
          <div>
            <h4 className="text-sm font-medium text-red-600 dark:text-red-400 flex items-center gap-1.5 mb-2">
              <AlertTriangle size={14} /> Overdue ({alerts.overdue.length})
            </h4>
            <div className="space-y-1.5">
              {alerts.overdue.map((a) => (
                <div key={`${a.tool_id}-${a.maintenance_type_id}`} className="flex items-center justify-between text-xs bg-red-50 dark:bg-red-900/20 rounded-md px-3 py-2">
                  <span className="text-gray-900 dark:text-gray-100 font-medium">{a.tool_name}</span>
                  <span className="text-red-600 dark:text-red-400">{a.maintenance_type_name} — {a.days_until_due != null ? `${Math.abs(a.days_until_due)}d overdue` : 'overdue'}</span>
                </div>
              ))}
            </div>
          </div>
        )}
        {alerts.upcoming.length > 0 && (
          <div>
            <h4 className="text-sm font-medium text-amber-600 dark:text-amber-400 flex items-center gap-1.5 mb-2">
              <Clock size={14} /> Upcoming ({alerts.upcoming.length})
            </h4>
            <div className="space-y-1.5">
              {alerts.upcoming.map((a) => (
                <div key={`${a.tool_id}-${a.maintenance_type_id}`} className="flex items-center justify-between text-xs bg-amber-50 dark:bg-amber-900/20 rounded-md px-3 py-2">
                  <span className="text-gray-900 dark:text-gray-100 font-medium">{a.tool_name}</span>
                  <span className="text-amber-600 dark:text-amber-400">{a.maintenance_type_name} — due {a.next_due_date}</span>
                </div>
              ))}
            </div>
          </div>
        )}
      </div>
    </Card>
  );
}


// ═══════════════════════════════════════════════════════════════════
// Tool Row
// ═══════════════════════════════════════════════════════════════════

function ToolRow({ tool, onClick }: { tool: Tool; onClick: () => void }) {
  return (
    <button
      onClick={onClick}
      className="w-full text-left bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-lg p-3 sm:p-4 hover:border-primary-300 dark:hover:border-primary-600 hover:shadow-sm transition-all group"
    >
      <div className="flex items-start gap-3">
        {/* Icon */}
        <div className="flex-shrink-0 w-10 h-10 rounded-full bg-primary-100 dark:bg-primary-900/30 flex items-center justify-center text-primary-700 dark:text-primary-300">
          <Wrench size={18} />
        </div>

        {/* Info */}
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 flex-wrap">
            <span className="font-medium text-gray-900 dark:text-gray-100 truncate">
              {tool.name}
            </span>
            <Badge variant={STATUS_BADGE[tool.status as ToolStatus] ?? 'default'}>
              {tool.status.replace('_', ' ')}
            </Badge>
            {tool.has_kit && (
              <span className="hidden sm:inline-flex items-center gap-1 text-xs text-purple-600 dark:text-purple-400">
                <Shield size={12} /> Kit
              </span>
            )}
          </div>

          {/* Details row */}
          <div className="flex items-center gap-3 mt-1 text-xs text-gray-500 dark:text-gray-400 flex-wrap">
            <span className="font-mono">{tool.tool_number}</span>
            <span>{categoryLabel(tool.category)}</span>
            {tool.brand && <span className="hidden sm:inline">{tool.brand}</span>}
            <span className="flex items-center gap-1">
              {locationIcon(tool.location_type)}
              {tool.location_name ?? tool.location_type}
            </span>
            {tool.assigned_to_name && (
              <span className="hidden sm:inline">→ {tool.assigned_to_name}</span>
            )}
          </div>

          {/* Condition stars + maintenance indicator */}
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
        </div>

        <ChevronRight size={18} className="text-gray-300 dark:text-gray-600 group-hover:text-primary-400 transition-colors flex-shrink-0 mt-2" />
      </div>
    </button>
  );
}


// ═══════════════════════════════════════════════════════════════════
// Tool Detail Panel (modal)
// ═══════════════════════════════════════════════════════════════════

function ToolDetailPanel({ tool, onClose }: {
  tool: Tool;
  onClose: () => void;
}) {
  const queryClient = useQueryClient();
  const { hasPermission } = useAuthStore();
  const canManage = hasPermission(PERMISSIONS.MANAGE_TOOLS);
  const [qrDataUrl, setQrDataUrl] = useState<string | null>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [uploading, setUploading] = useState(false);
  const [photoUrl, setPhotoUrl] = useState<string | null>(tool.photo_path ?? null);
  const [showTransfer, setShowTransfer] = useState(false);
  const [showDepreciation, setShowDepreciation] = useState(false);

  // Generate QR code on mount
  useEffect(() => {
    const url = `${window.location.origin}/tools/scan/${tool.tool_number}`;
    QRCode.toDataURL(url, { width: 200, margin: 2, color: { dark: '#000000', light: '#FFFFFF' } })
      .then(setQrDataUrl)
      .catch(() => setQrDataUrl(null));
  }, [tool.tool_number]);

  // Photo upload handler
  const handlePhotoUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    try {
      setUploading(true);
      const result = await uploadToolPhoto(tool.id, file);
      setPhotoUrl(result.photo_path);
      queryClient.invalidateQueries({ queryKey: ['tools'] });
    } catch {
      // silent — user can try again
    } finally {
      setUploading(false);
      if (fileInputRef.current) fileInputRef.current.value = '';
    }
  };

  // Depreciation query (only fetch when panel expanded)
  const { data: depreciation } = useQuery({
    queryKey: ['tool-depreciation', tool.id],
    queryFn: () => getToolDepreciation(tool.id),
    enabled: showDepreciation && !!tool.depreciation_method,
    staleTime: 30_000,
  });

  return (
    <Modal isOpen onClose={onClose} title="Tool Details" size="lg">
      <div className="space-y-5">
        {/* Header info */}
        <div className="flex items-start gap-4">
          {/* Photo / QR Code */}
          <div className="flex-shrink-0 w-24 h-24 bg-white dark:bg-gray-900 border border-gray-200 dark:border-gray-700 rounded-lg flex items-center justify-center relative overflow-hidden group">
            {photoUrl ? (
              <img src={photoUrl} alt={tool.name} className="w-full h-full object-cover rounded-lg" />
            ) : qrDataUrl ? (
              <img src={qrDataUrl} alt="QR Code" className="w-20 h-20" />
            ) : (
              <QrCode size={40} className="text-gray-300 dark:text-gray-600" />
            )}
            {/* Photo upload overlay */}
            {canManage && (
              <button
                onClick={() => fileInputRef.current?.click()}
                className="absolute inset-0 flex items-center justify-center bg-black/50 opacity-0 group-hover:opacity-100 transition-opacity rounded-lg"
                title={photoUrl ? 'Change photo' : 'Upload photo'}
              >
                {uploading ? (
                  <div className="w-5 h-5 border-2 border-white/50 border-t-white rounded-full animate-spin" />
                ) : (
                  <Camera size={20} className="text-white" />
                )}
              </button>
            )}
            <input
              ref={fileInputRef}
              type="file"
              accept="image/*"
              className="hidden"
              onChange={handlePhotoUpload}
            />
          </div>

          <div className="flex-1 min-w-0">
            <h3 className="text-lg font-semibold text-gray-900 dark:text-gray-100">{tool.name}</h3>
            <p className="text-sm text-gray-500 dark:text-gray-400 font-mono">{tool.tool_number}</p>
            <div className="flex items-center gap-2 mt-1 flex-wrap">
              <Badge variant={STATUS_BADGE[tool.status as ToolStatus] ?? 'default'}>
                {tool.status.replace('_', ' ')}
              </Badge>
              <Badge>{categoryLabel(tool.category)}</Badge>
              {tool.has_kit && <Badge variant="primary">Has Kit</Badge>}
            </div>
          </div>

          {/* Action buttons */}
          <div className="flex flex-col gap-1 flex-shrink-0">
            {qrDataUrl && (
              <Button variant="ghost" size="sm" icon={<Printer size={16} />} onClick={() => printQrLabel(qrDataUrl, tool)}>
                <span className="hidden sm:inline">Print</span>
              </Button>
            )}
            {canManage && (
              <Button variant="ghost" size="sm" icon={<ArrowRightLeft size={16} />} onClick={() => setShowTransfer(true)}>
                <span className="hidden sm:inline">Transfer</span>
              </Button>
            )}
          </div>
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
          {tool.current_book_value != null && (
            <DetailField label="Book Value" value={
              <span className="flex items-center gap-1 text-green-600 dark:text-green-400">
                <DollarSign size={14} />
                {tool.current_book_value.toFixed(2)}
              </span>
            } />
          )}
          {tool.calibration_due_date && (
            <DetailField label="Calibration Due" value={
              <span className={`flex items-center gap-1 ${new Date(tool.calibration_due_date) < new Date() ? 'text-red-500' : 'text-gray-900 dark:text-gray-100'}`}>
                <Calendar size={14} />
                {tool.calibration_due_date}
              </span>
            } />
          )}
        </div>

        {/* Depreciation section */}
        {tool.depreciation_method && (
          <div className="border border-gray-200 dark:border-gray-700 rounded-lg overflow-hidden">
            <button
              onClick={() => setShowDepreciation(!showDepreciation)}
              className="w-full flex items-center justify-between px-4 py-3 bg-gray-50 dark:bg-gray-800/50 hover:bg-gray-100 dark:hover:bg-gray-800 transition-colors"
            >
              <span className="flex items-center gap-2 text-sm font-medium text-gray-700 dark:text-gray-300">
                <TrendingDown size={16} className="text-blue-500" />
                Depreciation — {tool.depreciation_method.replace('_', ' ')}
              </span>
              <ChevronRight size={16} className={`text-gray-400 transition-transform ${showDepreciation ? 'rotate-90' : ''}`} />
            </button>

            {showDepreciation && depreciation && (
              <div className="p-4 space-y-3">
                <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 text-center">
                  <div>
                    <p className="text-xs text-gray-500 dark:text-gray-400">Original Cost</p>
                    <p className="text-sm font-semibold text-gray-900 dark:text-gray-100">
                      ${(depreciation.purchase_cost ?? 0).toFixed(2)}
                    </p>
                  </div>
                  <div>
                    <p className="text-xs text-gray-500 dark:text-gray-400">Book Value</p>
                    <p className="text-sm font-semibold text-green-600 dark:text-green-400">
                      ${(depreciation.current_book_value ?? 0).toFixed(2)}
                    </p>
                  </div>
                  <div>
                    <p className="text-xs text-gray-500 dark:text-gray-400">Depreciated</p>
                    <p className="text-sm font-semibold text-gray-900 dark:text-gray-100">
                      ${depreciation.total_depreciated.toFixed(2)}
                    </p>
                  </div>
                  <div>
                    <p className="text-xs text-gray-500 dark:text-gray-400">Years Left</p>
                    <p className="text-sm font-semibold text-gray-900 dark:text-gray-100">
                      {depreciation.years_remaining ?? '—'}
                    </p>
                  </div>
                </div>

                {/* Schedule table */}
                {depreciation.schedule.length > 0 && (
                  <div className="overflow-x-auto">
                    <table className="w-full text-xs">
                      <thead>
                        <tr className="text-left text-gray-500 dark:text-gray-400 border-b border-gray-200 dark:border-gray-700">
                          <th className="py-1.5 pr-3">Year</th>
                          <th className="py-1.5 pr-3 text-right">Begin</th>
                          <th className="py-1.5 pr-3 text-right">Deprec.</th>
                          <th className="py-1.5 text-right">End</th>
                        </tr>
                      </thead>
                      <tbody>
                        {depreciation.schedule.map((entry) => (
                          <tr key={entry.year_number} className="border-b border-gray-100 dark:border-gray-800">
                            <td className="py-1.5 pr-3 text-gray-600 dark:text-gray-400">{entry.fiscal_year}</td>
                            <td className="py-1.5 pr-3 text-right">${entry.beginning_value.toFixed(2)}</td>
                            <td className="py-1.5 pr-3 text-right text-red-500">${entry.depreciation_amount.toFixed(2)}</td>
                            <td className="py-1.5 text-right font-medium">${entry.ending_value.toFixed(2)}</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                )}
              </div>
            )}
          </div>
        )}

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

        {/* Notes */}
        {tool.notes && (
          <div>
            <p className="text-xs font-medium text-gray-500 dark:text-gray-400 mb-1">Notes</p>
            <p className="text-sm text-gray-700 dark:text-gray-300 whitespace-pre-wrap">{tool.notes}</p>
          </div>
        )}
      </div>

      {/* Transfer modal */}
      {showTransfer && (
        <ToolTransferModal
          tool={tool}
          onClose={() => setShowTransfer(false)}
          onSuccess={() => {
            setShowTransfer(false);
            queryClient.invalidateQueries({ queryKey: ['tools'] });
            queryClient.invalidateQueries({ queryKey: ['tools-dashboard'] });
            onClose();
          }}
        />
      )}
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


// ═══════════════════════════════════════════════════════════════════
// Create Tool Modal
// ═══════════════════════════════════════════════════════════════════

interface CreateModalProps {
  isLoading: boolean;
  error: string | null;
  onSubmit: (data: ToolCreate) => void;
  onClose: () => void;
}

function CreateToolModal({ isLoading, error, onSubmit, onClose }: CreateModalProps) {
  const [form, setForm] = useState<ToolCreate>({
    tool_number: '',
    name: '',
    category: 'power_tool',
  });

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    onSubmit(form);
  };

  return (
    <Modal isOpen onClose={onClose} title="Register New Tool" size="lg">
      <form onSubmit={handleSubmit} className="space-y-4">
        {error && (
          <div className="p-3 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-lg text-sm text-red-600 dark:text-red-400">
            {error}
          </div>
        )}

        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <Input
            label="Tool Name *"
            value={form.name}
            onChange={(e) => setForm({ ...form, name: e.target.value })}
            required
            placeholder="Milwaukee M18 Impact Driver"
          />
          <div className="space-y-1.5">
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300">Category *</label>
            <select
              value={form.category}
              onChange={(e) => setForm({ ...form, category: e.target.value as ToolCategory })}
              className="block w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 px-3 py-2 text-sm"
            >
              {CATEGORIES.map((c) => (
                <option key={c.value} value={c.value}>{c.label}</option>
              ))}
            </select>
          </div>
        </div>

        <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
          <Input
            label="Brand"
            value={form.brand ?? ''}
            onChange={(e) => setForm({ ...form, brand: e.target.value || undefined })}
            placeholder="Milwaukee"
          />
          <Input
            label="Model Number"
            value={form.model_number ?? ''}
            onChange={(e) => setForm({ ...form, model_number: e.target.value || undefined })}
            placeholder="2853-20"
          />
          <Input
            label="Serial Number"
            value={form.serial_number ?? ''}
            onChange={(e) => setForm({ ...form, serial_number: e.target.value || undefined })}
            placeholder="SN12345"
          />
        </div>

        <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
          <Input
            label="Purchase Date"
            type="date"
            value={form.purchase_date ?? ''}
            onChange={(e) => setForm({ ...form, purchase_date: e.target.value || undefined })}
          />
          <Input
            label="Purchase Cost"
            type="number"
            step="0.01"
            min="0"
            value={form.purchase_cost ?? ''}
            onChange={(e) => setForm({ ...form, purchase_cost: e.target.value ? Number(e.target.value) : undefined })}
            placeholder="0.00"
          />
          <Input
            label="Warranty Expiry"
            type="date"
            value={form.warranty_expiry ?? ''}
            onChange={(e) => setForm({ ...form, warranty_expiry: e.target.value || undefined })}
          />
        </div>

        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div className="space-y-1.5">
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300">Condition</label>
            <select
              value={form.condition_rating ?? ''}
              onChange={(e) => setForm({ ...form, condition_rating: e.target.value ? Number(e.target.value) : undefined })}
              className="block w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 px-3 py-2 text-sm"
            >
              <option value="">Not rated</option>
              <option value="5">5 — Excellent</option>
              <option value="4">4 — Good</option>
              <option value="3">3 — Fair</option>
              <option value="2">2 — Poor</option>
              <option value="1">1 — Critical</option>
            </select>
          </div>
          <Input
            label="Notes"
            value={form.notes ?? ''}
            onChange={(e) => setForm({ ...form, notes: e.target.value || undefined })}
            placeholder="Optional notes..."
          />
        </div>

        {/* Depreciation settings (optional) */}
        <div className="border-t border-gray-200 dark:border-gray-700 pt-4">
          <p className="text-xs font-medium text-gray-500 dark:text-gray-400 mb-3 flex items-center gap-1.5">
            <TrendingDown size={14} /> Depreciation (optional)
          </p>
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
            <div className="space-y-1.5">
              <label className="block text-sm font-medium text-gray-700 dark:text-gray-300">Method</label>
              <select
                value={form.depreciation_method ?? ''}
                onChange={(e) => setForm({ ...form, depreciation_method: (e.target.value || undefined) as DepreciationMethod | undefined })}
                className="block w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 px-3 py-2 text-sm"
              >
                <option value="">None</option>
                <option value="straight_line">Straight Line</option>
                <option value="declining_balance">Declining Balance</option>
                <option value="sum_of_years">Sum of Years' Digits</option>
              </select>
            </div>
            <Input
              label="Salvage Value"
              type="number"
              step="0.01"
              min="0"
              value={form.salvage_value ?? ''}
              onChange={(e) => setForm({ ...form, salvage_value: e.target.value ? Number(e.target.value) : undefined })}
              placeholder="0.00"
            />
            <Input
              label="Useful Life (years)"
              type="number"
              min="1"
              max="50"
              value={form.useful_life_years ?? ''}
              onChange={(e) => setForm({ ...form, useful_life_years: e.target.value ? Number(e.target.value) : undefined })}
              placeholder="5"
            />
          </div>
        </div>

        <div className="flex items-center justify-end gap-3 pt-2 border-t border-gray-200 dark:border-gray-700">
          <Button variant="ghost" type="button" onClick={onClose}>Cancel</Button>
          <Button type="submit" isLoading={isLoading} disabled={!form.name}>
            Register Tool
          </Button>
        </div>
      </form>
    </Modal>
  );
}


// ═══════════════════════════════════════════════════════════════════
// Tool Transfer Modal
// ═══════════════════════════════════════════════════════════════════

const LOCATION_TYPES = [
  { value: 'warehouse', label: 'Warehouse' },
  { value: 'truck', label: 'Truck' },
  { value: 'job', label: 'Job' },
];

function ToolTransferModal({ tool, onClose, onSuccess }: {
  tool: Tool;
  onClose: () => void;
  onSuccess: () => void;
}) {
  const [locationType, setLocationType] = useState<string>('warehouse');
  const [locationId, setLocationId] = useState<string>('');
  const [reason, setReason] = useState('');
  const [condition, setCondition] = useState<string>(String(tool.condition_rating ?? ''));
  const [error, setError] = useState<string | null>(null);

  const mutation = useMutation({
    mutationFn: () => transferTool(tool.id, {
      to_location_type: locationType as 'warehouse' | 'truck' | 'job',
      to_location_id: locationId ? Number(locationId) : 0,
      condition_at_move: condition ? Number(condition) : undefined,
      reason: reason || undefined,
    }),
    onSuccess,
    onError: (err: Error) => setError(err.message),
  });

  return (
    <Modal isOpen onClose={onClose} title={`Transfer: ${tool.tool_number}`} size="md">
      <div className="space-y-4">
        {error && (
          <div className="p-3 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-lg text-sm text-red-600 dark:text-red-400">
            {error}
          </div>
        )}

        <p className="text-sm text-gray-600 dark:text-gray-400">
          Currently at: <span className="font-medium">{tool.location_name ?? tool.location_type}</span>
        </p>

        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div className="space-y-1.5">
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300">Destination Type *</label>
            <select
              value={locationType}
              onChange={(e) => { setLocationType(e.target.value); setLocationId(''); }}
              className="block w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 px-3 py-2 text-sm"
            >
              {LOCATION_TYPES.map((t) => (
                <option key={t.value} value={t.value}>{t.label}</option>
              ))}
            </select>
          </div>

          {locationType !== 'warehouse' && (
            <Input
              label={`${locationType === 'truck' ? 'Truck' : 'Job'} ID *`}
              type="number"
              min="1"
              value={locationId}
              onChange={(e) => setLocationId(e.target.value)}
              placeholder={`Enter ${locationType} ID`}
              required
            />
          )}
        </div>

        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div className="space-y-1.5">
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300">Condition at Move</label>
            <select
              value={condition}
              onChange={(e) => setCondition(e.target.value)}
              className="block w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 px-3 py-2 text-sm"
            >
              <option value="">No change</option>
              <option value="5">5 — Excellent</option>
              <option value="4">4 — Good</option>
              <option value="3">3 — Fair</option>
              <option value="2">2 — Poor</option>
              <option value="1">1 — Critical</option>
            </select>
          </div>
          <Input
            label="Reason"
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            placeholder="Optional reason for transfer"
          />
        </div>

        <div className="flex items-center justify-end gap-3 pt-2 border-t border-gray-200 dark:border-gray-700">
          <Button variant="ghost" type="button" onClick={onClose}>Cancel</Button>
          <Button
            onClick={() => mutation.mutate()}
            isLoading={mutation.isPending}
            icon={<ArrowRightLeft size={16} />}
          >
            Transfer Tool
          </Button>
        </div>
      </div>
    </Modal>
  );
}
