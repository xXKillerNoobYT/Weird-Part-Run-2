/**
 * ContractorDetailPage — full GC profile with sub-tabs for
 * overview (edit form), contacts (entity_contacts CRUD), and linked jobs.
 *
 * Follows the CustomerDetailPage pattern. Additional GC-specific fields:
 * gc_code, license_number, trade_type, website, insurance_info.
 */

import { useState } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  ArrowLeft, Mail, Phone, HardHat, Edit2, UserCheck, UserX,
  Plus, Trash2, Users, Briefcase, MapPin, Save, Globe, Tag,
  Shield,
} from 'lucide-react';
import { PageSpinner } from '../../../components/ui/Spinner';
import { Button } from '../../../components/ui/Button';
import { Badge } from '../../../components/ui/Badge';
import { Card, CardHeader } from '../../../components/ui/Card';
import { Modal } from '../../../components/ui/Modal';
import { Input } from '../../../components/ui/Input';
import { EmptyState } from '../../../components/ui/EmptyState';
import { toast } from '../../../lib/toast';
import { useAuthStore } from '../../../stores/auth-store';
import { PERMISSIONS } from '../../../lib/constants';
import {
  getGC, updateGC, toggleGCActive,
  getGCContacts, addGCContact,
  updateEntityContact, deleteEntityContact,
  getGCJobs,
} from '../../../api/contacts';
import type {
  GCDetail, GCUpdate, GCTradeType,
  EntityContactResponse, EntityContactCreate, EntityContactUpdate,
} from '../../../lib/types';


// ── Sub-tab IDs ───────────────────────────────────────────────────

const TABS = [
  { id: 'overview', label: 'Overview', icon: HardHat },
  { id: 'contacts', label: 'Contacts', icon: Users },
  { id: 'jobs', label: 'Jobs', icon: Briefcase },
] as const;

type TabId = typeof TABS[number]['id'];

const TRADE_TYPE_LABELS: Record<GCTradeType, string> = {
  general: 'General',
  electrical: 'Electrical',
  plumbing: 'Plumbing',
  hvac: 'HVAC',
  mechanical: 'Mechanical',
  fire_protection: 'Fire Protection',
  low_voltage: 'Low Voltage',
  other: 'Other',
};

const TRADE_TYPE_BADGE: Record<GCTradeType, 'default' | 'primary' | 'success' | 'warning' | 'info' | 'danger'> = {
  general: 'default',
  electrical: 'primary',
  plumbing: 'info',
  hvac: 'warning',
  mechanical: 'success',
  fire_protection: 'danger',
  low_voltage: 'info',
  other: 'default',
};


// ═════════════════════════════════════════════════════════════════
// MAIN PAGE
// ═════════════════════════════════════════════════════════════════

export function ContractorDetailPage() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const { hasPermission } = useAuthStore();
  const canManage = hasPermission(PERMISSIONS.MANAGE_CONTRACTORS);

  const [activeTab, setActiveTab] = useState<TabId>('overview');

  const gcId = Number(id);

  const { data: gc, isLoading, error } = useQuery({
    queryKey: ['gc-detail', gcId],
    queryFn: () => getGC(gcId),
    enabled: !!id && !isNaN(gcId),
    staleTime: 10_000,
  });

  const toggleMutation = useMutation({
    mutationFn: (isActive: boolean) => toggleGCActive(gcId, isActive),
    onSuccess: (_data, isActive) => {
      queryClient.invalidateQueries({ queryKey: ['gc-detail', gcId] });
      toast.success(isActive ? 'Contractor activated' : 'Contractor deactivated');
    },
    onError: () => toast.error('Failed to update contractor status'),
  });

  if (isLoading) return <PageSpinner label="Loading contractor..." />;
  if (error || !gc) {
    return (
      <div className="text-center py-16">
        <p className="text-red-500">Contractor not found.</p>
        <Button variant="ghost" className="mt-4" onClick={() => navigate('/people/contractors')}>
          Back to Contractors
        </Button>
      </div>
    );
  }

  return (
    <div className="space-y-4">
      {/* ── Header ─────────────────────────────────────────── */}
      <div className="flex items-start gap-3 flex-wrap">
        <button
          onClick={() => navigate('/people/contractors')}
          className="p-2 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors mt-0.5"
        >
          <ArrowLeft size={20} className="text-gray-500 dark:text-gray-400" />
        </button>

        {/* Avatar */}
        <div className="flex-shrink-0 w-12 h-12 rounded-full bg-amber-100 dark:bg-amber-900/30 flex items-center justify-center text-amber-700 dark:text-amber-300 font-bold text-lg">
          <HardHat size={20} />
        </div>

        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 flex-wrap">
            <h1 className="text-xl font-semibold text-gray-900 dark:text-gray-100">
              {gc.company_name}
            </h1>
            {gc.is_active ? (
              <Badge variant="success">Active</Badge>
            ) : (
              <Badge variant="danger">Inactive</Badge>
            )}
            <Badge variant={TRADE_TYPE_BADGE[gc.trade_type]}>
              {TRADE_TYPE_LABELS[gc.trade_type]}
            </Badge>
          </div>
          <div className="flex items-center gap-2 mt-0.5 text-sm text-gray-500 dark:text-gray-400">
            <Tag size={14} />
            <span className="font-mono">{gc.gc_code}</span>
            {gc.license_number && (
              <>
                <span>·</span>
                <span>License: {gc.license_number}</span>
              </>
            )}
          </div>
        </div>

        {/* Actions */}
        {canManage && (
          <div className="flex items-center gap-2">
            <Button
              variant={gc.is_active ? 'ghost' : 'primary'}
              size="sm"
              icon={gc.is_active ? <UserX size={16} /> : <UserCheck size={16} />}
              isLoading={toggleMutation.isPending}
              onClick={() => toggleMutation.mutate(!gc.is_active)}
            >
              <span className="hidden sm:inline">{gc.is_active ? 'Deactivate' : 'Activate'}</span>
            </Button>
          </div>
        )}
      </div>

      {/* ── Sub-tab bar ────────────────────────────────────── */}
      <div className="overflow-x-auto -mx-4 px-4 sm:mx-0 sm:px-0">
        <div className="flex gap-1 border-b border-gray-200 dark:border-gray-700 whitespace-nowrap">
          {TABS.map((tab) => {
            const Icon = tab.icon;
            const isActive = activeTab === tab.id;
            return (
              <button
                key={tab.id}
                onClick={() => setActiveTab(tab.id)}
                className={`flex items-center gap-1.5 px-3 py-2.5 text-sm font-medium border-b-2 transition-colors ${isActive
                  ? 'border-primary-500 text-primary-600 dark:text-primary-400'
                  : 'border-transparent text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-300'
                  }`}
              >
                <Icon size={14} />
                <span className="hidden sm:inline">{tab.label}</span>
              </button>
            );
          })}
        </div>
      </div>

      {/* ── Tab Content ────────────────────────────────────── */}
      {activeTab === 'overview' && <OverviewTab gc={gc} canManage={canManage} />}
      {activeTab === 'contacts' && <ContactsTab gcId={gcId} canManage={canManage} />}
      {activeTab === 'jobs' && <JobsTab gcId={gcId} />}
    </div>
  );
}


// ═════════════════════════════════════════════════════════════════
// Overview Tab — Edit form
// ═════════════════════════════════════════════════════════════════

function OverviewTab({ gc, canManage }: { gc: GCDetail; canManage: boolean }) {
  const queryClient = useQueryClient();
  const [editing, setEditing] = useState(false);

  const [companyName, setCompanyName] = useState(gc.company_name);
  const [gcCode, setGcCode] = useState(gc.gc_code);
  const [tradeType, setTradeType] = useState<GCTradeType>(gc.trade_type);
  const [licenseNumber, setLicenseNumber] = useState(gc.license_number ?? '');
  const [phone, setPhone] = useState(gc.phone ?? '');
  const [email, setEmail] = useState(gc.email ?? '');
  const [website, setWebsite] = useState(gc.website ?? '');
  const [addressLine1, setAddressLine1] = useState(gc.address_line1 ?? '');
  const [city, setCity] = useState(gc.city ?? '');
  const [state, setState] = useState(gc.state ?? '');
  const [zip, setZip] = useState(gc.zip ?? '');
  const [insuranceInfo, setInsuranceInfo] = useState(gc.insurance_info ?? '');
  const [notes, setNotes] = useState(gc.notes ?? '');
  const [coiCarrier, setCoiCarrier] = useState(gc.coi_carrier ?? '');
  const [coiPolicyNumber, setCoiPolicyNumber] = useState(gc.coi_policy_number ?? '');
  const [coiExpiryDate, setCoiExpiryDate] = useState(gc.coi_expiry_date ?? '');
  const [coiCoverage, setCoiCoverage] = useState(gc.coi_coverage_amount?.toString() ?? '');
  const [coiOnFile, setCoiOnFile] = useState(gc.coi_on_file ?? false);
  const [workersCompExpiry, setWorkersCompExpiry] = useState(gc.workers_comp_expiry ?? '');
  const [bonded, setBonded] = useState(gc.bonded ?? false);
  const [bondAmount, setBondAmount] = useState(gc.bond_amount?.toString() ?? '');

  const saveMutation = useMutation({
    mutationFn: (data: GCUpdate) => updateGC(gc.id, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['gc-detail', gc.id] });
      setEditing(false);
      toast.success('Contractor information saved');
    },
    onError: () => toast.error('Failed to save contractor information'),
  });

  const handleSave = () => {
    saveMutation.mutate({
      company_name: companyName.trim(),
      gc_code: gcCode.trim().toUpperCase(),
      trade_type: tradeType,
      license_number: licenseNumber.trim() || null,
      phone: phone.trim() || null,
      email: email.trim() || null,
      website: website.trim() || null,
      address_line1: addressLine1.trim() || null,
      city: city.trim() || null,
      state: state.trim() || null,
      zip: zip.trim() || null,
      insurance_info: insuranceInfo.trim() || null,
      notes: notes.trim() || null,
      coi_carrier: coiCarrier.trim() || null,
      coi_policy_number: coiPolicyNumber.trim() || null,
      coi_expiry_date: coiExpiryDate || null,
      coi_coverage_amount: coiCoverage ? parseFloat(coiCoverage) : null,
      coi_on_file: coiOnFile,
      workers_comp_expiry: workersCompExpiry || null,
      bonded,
      bond_amount: bondAmount ? parseFloat(bondAmount) : null,
    });
  };

  const handleCancel = () => {
    setCompanyName(gc.company_name);
    setGcCode(gc.gc_code);
    setTradeType(gc.trade_type);
    setLicenseNumber(gc.license_number ?? '');
    setPhone(gc.phone ?? '');
    setEmail(gc.email ?? '');
    setWebsite(gc.website ?? '');
    setAddressLine1(gc.address_line1 ?? '');
    setCity(gc.city ?? '');
    setState(gc.state ?? '');
    setZip(gc.zip ?? '');
    setInsuranceInfo(gc.insurance_info ?? '');
    setNotes(gc.notes ?? '');
    setCoiCarrier(gc.coi_carrier ?? '');
    setCoiPolicyNumber(gc.coi_policy_number ?? '');
    setCoiExpiryDate(gc.coi_expiry_date ?? '');
    setCoiCoverage(gc.coi_coverage_amount?.toString() ?? '');
    setCoiOnFile(gc.coi_on_file ?? false);
    setWorkersCompExpiry(gc.workers_comp_expiry ?? '');
    setBonded(gc.bonded ?? false);
    setBondAmount(gc.bond_amount?.toString() ?? '');
    setEditing(false);
  };

  return (
    <Card>
      <div className="flex items-center justify-between mb-4">
        <CardHeader title="Contractor Information" />
        {canManage && !editing && (
          <Button variant="ghost" size="sm" icon={<Edit2 size={14} />} onClick={() => setEditing(true)}>
            <span className="hidden sm:inline">Edit</span>
          </Button>
        )}
        {editing && (
          <div className="flex gap-2">
            <Button variant="ghost" size="sm" onClick={handleCancel}>Cancel</Button>
            <Button size="sm" icon={<Save size={14} />} isLoading={saveMutation.isPending} onClick={handleSave}>
              Save
            </Button>
          </div>
        )}
      </div>

      {editing ? (
        <div className="space-y-4">
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
            <div className="sm:col-span-2">
              <Input label="Company Name" value={companyName} onChange={(e) => setCompanyName(e.target.value)} />
            </div>
            <Input label="GC Code" value={gcCode} onChange={(e) => setGcCode(e.target.value.toUpperCase())} />
          </div>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <div>
              <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">Trade Type</label>
              <select
                value={tradeType}
                onChange={(e) => setTradeType(e.target.value as GCTradeType)}
                className="w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 px-3 py-2 text-sm"
              >
                {(Object.entries(TRADE_TYPE_LABELS) as [GCTradeType, string][]).map(([val, label]) => (
                  <option key={val} value={val}>{label}</option>
                ))}
              </select>
            </div>
            <Input label="License Number" value={licenseNumber} onChange={(e) => setLicenseNumber(e.target.value)} />
          </div>
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
            <Input label="Phone" value={phone} onChange={(e) => setPhone(e.target.value)} />
            <Input label="Email" value={email} onChange={(e) => setEmail(e.target.value)} />
            <Input label="Website" value={website} onChange={(e) => setWebsite(e.target.value)} />
          </div>
          <Input label="Address" value={addressLine1} onChange={(e) => setAddressLine1(e.target.value)} />
          <div className="grid grid-cols-2 sm:grid-cols-3 gap-3">
            <Input label="City" value={city} onChange={(e) => setCity(e.target.value)} />
            <Input label="State" value={state} onChange={(e) => setState(e.target.value)} />
            <Input label="ZIP" value={zip} onChange={(e) => setZip(e.target.value)} />
          </div>
          <div>
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">Insurance Info</label>
            <textarea
              value={insuranceInfo}
              onChange={(e) => setInsuranceInfo(e.target.value)}
              rows={2}
              className="w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 px-3 py-2 text-sm resize-none"
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">Notes</label>
            <textarea
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
              rows={3}
              className="w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 px-3 py-2 text-sm resize-none"
            />
          </div>

          {/* COI Section */}
          <div className="pt-4 border-t border-gray-200 dark:border-gray-700">
            <p className="text-sm font-medium text-gray-700 dark:text-gray-300 mb-3">Certificate of Insurance</p>
            <div className="space-y-3">
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <Input label="COI Carrier" value={coiCarrier} onChange={(e) => setCoiCarrier(e.target.value)} />
                <Input label="Policy Number" value={coiPolicyNumber} onChange={(e) => setCoiPolicyNumber(e.target.value)} />
              </div>
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <Input label="COI Expiry" type="date" value={coiExpiryDate} onChange={(e) => setCoiExpiryDate(e.target.value)} />
                <Input label="Coverage Amount" type="number" value={coiCoverage} onChange={(e) => setCoiCoverage(e.target.value)} />
              </div>
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <Input label="Workers' Comp Expiry" type="date" value={workersCompExpiry} onChange={(e) => setWorkersCompExpiry(e.target.value)} />
                <Input label="Bond Amount" type="number" value={bondAmount} onChange={(e) => setBondAmount(e.target.value)} />
              </div>
              <div className="flex gap-6">
                <label className="flex items-center gap-2 text-sm text-gray-700 dark:text-gray-300">
                  <input type="checkbox" checked={coiOnFile} onChange={(e) => setCoiOnFile(e.target.checked)}
                    className="rounded border-gray-300 dark:border-gray-600" />
                  COI on File
                </label>
                <label className="flex items-center gap-2 text-sm text-gray-700 dark:text-gray-300">
                  <input type="checkbox" checked={bonded} onChange={(e) => setBonded(e.target.checked)}
                    className="rounded border-gray-300 dark:border-gray-600" />
                  Bonded
                </label>
              </div>
            </div>
          </div>
        </div>
      ) : (
        <div className="space-y-3">
          {/* Contact details */}
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            {gc.phone && (
              <div className="flex items-center gap-2">
                <Phone size={16} className="text-gray-400 dark:text-gray-500 flex-shrink-0" />
                <a href={`tel:${gc.phone}`} className="text-sm text-primary-600 dark:text-primary-400 hover:underline">
                  {gc.phone}
                </a>
              </div>
            )}
            {gc.email && (
              <div className="flex items-center gap-2">
                <Mail size={16} className="text-gray-400 dark:text-gray-500 flex-shrink-0" />
                <a href={`mailto:${gc.email}`} className="text-sm text-primary-600 dark:text-primary-400 hover:underline truncate">
                  {gc.email}
                </a>
              </div>
            )}
            {gc.website && (
              <div className="flex items-center gap-2">
                <Globe size={16} className="text-gray-400 dark:text-gray-500 flex-shrink-0" />
                <a href={gc.website} target="_blank" rel="noopener noreferrer" className="text-sm text-primary-600 dark:text-primary-400 hover:underline truncate">
                  {gc.website}
                </a>
              </div>
            )}
          </div>

          {/* Address */}
          {gc.address_line1 && (
            <div className="flex items-start gap-2">
              <MapPin size={16} className="text-gray-400 dark:text-gray-500 flex-shrink-0 mt-0.5" />
              <div className="text-sm text-gray-700 dark:text-gray-300">
                <p>{gc.address_line1}</p>
                {(gc.city || gc.state || gc.zip) && (
                  <p>{[gc.city, gc.state, gc.zip].filter(Boolean).join(', ')}</p>
                )}
              </div>
            </div>
          )}

          {/* Insurance info */}
          {gc.insurance_info && (
            <div className="flex items-start gap-2">
              <Shield size={16} className="text-gray-400 dark:text-gray-500 flex-shrink-0 mt-0.5" />
              <div className="text-sm text-gray-700 dark:text-gray-300">
                <p className="text-xs font-medium text-gray-500 dark:text-gray-400 mb-0.5">Insurance</p>
                <p className="whitespace-pre-wrap">{gc.insurance_info}</p>
              </div>
            </div>
          )}

          {/* Notes */}
          {gc.notes && (
            <div className="mt-4 p-3 rounded-lg bg-gray-50 dark:bg-gray-800/50">
              <p className="text-xs font-medium text-gray-500 dark:text-gray-400 mb-1">Notes</p>
              <p className="text-sm text-gray-700 dark:text-gray-300 whitespace-pre-wrap">{gc.notes}</p>
            </div>
          )}

          {/* COI Summary */}
          {(gc.coi_carrier || gc.coi_on_file || gc.bonded) && (
            <div className="mt-4 pt-4 border-t border-gray-100 dark:border-gray-700/50">
              <p className="text-xs font-medium text-gray-500 dark:text-gray-400 mb-2">Certificate of Insurance</p>
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-2 text-sm text-gray-700 dark:text-gray-300">
                {gc.coi_carrier && (
                  <p><span className="text-gray-500 dark:text-gray-400">Carrier:</span> {gc.coi_carrier}</p>
                )}
                {gc.coi_policy_number && (
                  <p><span className="text-gray-500 dark:text-gray-400">Policy:</span> {gc.coi_policy_number}</p>
                )}
                {gc.coi_expiry_date && (
                  <p><span className="text-gray-500 dark:text-gray-400">Expires:</span> {new Date(gc.coi_expiry_date).toLocaleDateString()}</p>
                )}
                {gc.coi_coverage_amount != null && (
                  <p><span className="text-gray-500 dark:text-gray-400">Coverage:</span> ${gc.coi_coverage_amount.toLocaleString()}</p>
                )}
                {gc.workers_comp_expiry && (
                  <p><span className="text-gray-500 dark:text-gray-400">Workers' Comp Exp:</span> {new Date(gc.workers_comp_expiry).toLocaleDateString()}</p>
                )}
                <div className="flex gap-3">
                  {gc.coi_on_file && <Badge variant="success">COI on File</Badge>}
                  {gc.bonded && <Badge variant="info">Bonded{gc.bond_amount ? ` ($${gc.bond_amount.toLocaleString()})` : ''}</Badge>}
                </div>
              </div>
            </div>
          )}

          {/* Metadata */}
          <div className="flex items-center gap-4 text-xs text-gray-400 dark:text-gray-500 pt-2 border-t border-gray-100 dark:border-gray-700/50">
            {gc.created_at && <span>Created: {new Date(gc.created_at).toLocaleDateString()}</span>}
            {gc.updated_at && <span>Updated: {new Date(gc.updated_at).toLocaleDateString()}</span>}
          </div>
        </div>
      )}
    </Card>
  );
}


// ═════════════════════════════════════════════════════════════════
// Contacts Tab — Entity contacts CRUD
// ═════════════════════════════════════════════════════════════════

function ContactsTab({ gcId, canManage }: { gcId: number; canManage: boolean }) {
  const queryClient = useQueryClient();
  const [showAdd, setShowAdd] = useState(false);
  const [editingContact, setEditingContact] = useState<EntityContactResponse | null>(null);

  const { data: contacts, isLoading } = useQuery({
    queryKey: ['gc-contacts', gcId],
    queryFn: () => getGCContacts(gcId),
    staleTime: 10_000,
  });

  const addMutation = useMutation({
    mutationFn: (data: EntityContactCreate) => addGCContact(gcId, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['gc-contacts', gcId] });
      queryClient.invalidateQueries({ queryKey: ['gc-detail', gcId] });
      setShowAdd(false);
      toast.success('Contact added');
    },
    onError: () => toast.error('Failed to add contact'),
  });

  const updateMutation = useMutation({
    mutationFn: ({ id, data }: { id: number; data: EntityContactUpdate }) => updateEntityContact(id, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['gc-contacts', gcId] });
      setEditingContact(null);
      toast.success('Contact updated');
    },
    onError: () => toast.error('Failed to update contact'),
  });

  const deleteMutation = useMutation({
    mutationFn: deleteEntityContact,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['gc-contacts', gcId] });
      queryClient.invalidateQueries({ queryKey: ['gc-detail', gcId] });
      toast.success('Contact deleted');
    },
    onError: () => toast.error('Failed to delete contact'),
  });

  if (isLoading) return <PageSpinner label="Loading contacts..." />;

  return (
    <div className="space-y-3">
      {canManage && (
        <div className="flex justify-end">
          <Button size="sm" icon={<Plus size={16} />} onClick={() => setShowAdd(true)}>
            <span className="hidden sm:inline">Add Contact</span>
          </Button>
        </div>
      )}

      {(!contacts || contacts.length === 0) ? (
        <EmptyState
          icon={<Users size={48} />}
          title="No contacts yet"
          description="Add contact persons for this contractor."
          action={canManage ? <Button size="sm" onClick={() => setShowAdd(true)}>Add Contact</Button> : undefined}
        />
      ) : (
        contacts.map((c) => (
          <Card key={c.id} noPadding>
            <div className="p-3">
              <div className="flex items-center justify-between flex-wrap gap-2">
                <div>
                  <div className="flex items-center gap-2">
                    <span className="font-medium text-gray-900 dark:text-gray-100">
                      {c.first_name} {c.last_name}
                    </span>
                    {c.is_primary && <Badge variant="primary">Primary</Badge>}
                  </div>
                  <p className="text-sm text-gray-500 dark:text-gray-400">{c.role}</p>
                </div>
                {canManage && (
                  <div className="flex items-center gap-1">
                    <Button variant="ghost" size="sm" icon={<Edit2 size={14} />} onClick={() => setEditingContact(c)} />
                    <Button
                      variant="ghost"
                      size="sm"
                      icon={<Trash2 size={14} className="text-red-500" />}
                      onClick={() => { if (confirm('Delete this contact?')) deleteMutation.mutate(c.id); }}
                    />
                  </div>
                )}
              </div>
              <div className="flex items-center gap-4 mt-2 text-sm text-gray-600 dark:text-gray-400">
                {c.phone && (
                  <a href={`tel:${c.phone}`} className="flex items-center gap-1 hover:text-primary-600 dark:hover:text-primary-400">
                    <Phone size={14} /> {c.phone}
                  </a>
                )}
                {c.email && (
                  <a href={`mailto:${c.email}`} className="flex items-center gap-1 hover:text-primary-600 dark:hover:text-primary-400 truncate">
                    <Mail size={14} /> <span className="truncate">{c.email}</span>
                  </a>
                )}
              </div>
              {c.notes && (
                <p className="text-xs text-gray-500 dark:text-gray-400 mt-1">{c.notes}</p>
              )}
            </div>
          </Card>
        ))
      )}

      {/* Add contact modal */}
      {showAdd && (
        <ContactFormModal
          title="Add Contact"
          isLoading={addMutation.isPending}
          error={addMutation.error?.message ?? null}
          onSubmit={(data) => addMutation.mutate(data as EntityContactCreate)}
          onClose={() => setShowAdd(false)}
        />
      )}

      {/* Edit contact modal */}
      {editingContact && (
        <ContactFormModal
          title="Edit Contact"
          initial={editingContact}
          isLoading={updateMutation.isPending}
          error={updateMutation.error?.message ?? null}
          onSubmit={(data) => updateMutation.mutate({ id: editingContact.id, data: data as EntityContactUpdate })}
          onClose={() => setEditingContact(null)}
        />
      )}
    </div>
  );
}


// ═════════════════════════════════════════════════════════════════
// Jobs Tab — Linked jobs (read-only; linking is done from Job Detail)
// ═════════════════════════════════════════════════════════════════

const RELATIONSHIP_LABELS: Record<string, string> = {
  they_are_gc: 'They hired us',
  we_hired_them: 'We hired them',
};
const RELATIONSHIP_BADGE: Record<string, 'info' | 'warning'> = {
  they_are_gc: 'info',
  we_hired_them: 'warning',
};

function JobsTab({ gcId }: { gcId: number }) {
  const navigate = useNavigate();

  const { data: links, isLoading } = useQuery({
    queryKey: ['gc-jobs', gcId],
    queryFn: () => getGCJobs(gcId),
    staleTime: 15_000,
  });

  if (isLoading) return <PageSpinner label="Loading jobs..." />;

  if (!links || links.length === 0) {
    return (
      <EmptyState
        icon={<Briefcase size={48} />}
        title="No linked jobs"
        description="This contractor hasn't been linked to any jobs yet. Link contractors from the Job Detail page."
      />
    );
  }

  return (
    <div className="space-y-2">
      {links.map((link) => (
        <Card key={link.id} noPadding>
          <button
            onClick={() => navigate(`/jobs/${link.job_id}`)}
            className="w-full flex items-center gap-3 p-3 text-left hover:bg-gray-50 dark:hover:bg-gray-700/50 transition-colors rounded-lg"
          >
            <Briefcase size={16} className="text-gray-400 dark:text-gray-500 flex-shrink-0" />
            <div className="flex-1 min-w-0">
              <span className="font-medium text-gray-900 dark:text-gray-100">{link.job_name}</span>
              <div className="flex items-center gap-2 mt-0.5 flex-wrap">
                <Badge variant={RELATIONSHIP_BADGE[link.relationship] ?? 'default'}>
                  {RELATIONSHIP_LABELS[link.relationship] ?? link.relationship}
                </Badge>
                <Badge variant="neutral">{link.job_status.replace(/_/g, ' ')}</Badge>
                {link.is_primary && <Badge variant="primary">Primary</Badge>}
                {link.contract_number && (
                  <span className="text-xs text-gray-500 dark:text-gray-400">
                    Contract: {link.contract_number}
                  </span>
                )}
              </div>
            </div>
          </button>
        </Card>
      ))}
    </div>
  );
}


// ═════════════════════════════════════════════════════════════════
// Contact Form Modal (shared between Add/Edit)
// ═════════════════════════════════════════════════════════════════

function ContactFormModal({
  title,
  initial,
  isLoading,
  error,
  onSubmit,
  onClose,
}: {
  title: string;
  initial?: EntityContactResponse;
  isLoading: boolean;
  error: string | null;
  onSubmit: (data: EntityContactCreate | EntityContactUpdate) => void;
  onClose: () => void;
}) {
  const [firstName, setFirstName] = useState(initial?.first_name ?? '');
  const [lastName, setLastName] = useState(initial?.last_name ?? '');
  const [role, setRole] = useState(initial?.role ?? '');
  const [phone, setPhone] = useState(initial?.phone ?? '');
  const [email, setEmail] = useState(initial?.email ?? '');
  const [isPrimary, setIsPrimary] = useState(initial?.is_primary ?? false);
  const [notes, setNotes] = useState(initial?.notes ?? '');

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!firstName.trim() || !lastName.trim() || !phone.trim() || !role.trim()) return;
    onSubmit({
      first_name: firstName.trim(),
      last_name: lastName.trim(),
      role: role.trim(),
      phone: phone.trim(),
      email: email.trim() || null,
      is_primary: isPrimary,
      notes: notes.trim() || null,
    });
  };

  return (
    <Modal isOpen title={title} onClose={onClose}>
      <form onSubmit={handleSubmit} className="space-y-4">
        {error && (
          <div className="p-3 rounded-lg bg-red-50 dark:bg-red-900/20 text-red-600 dark:text-red-400 text-sm">
            {error}
          </div>
        )}

        <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
          <Input label="First Name *" value={firstName} onChange={(e) => setFirstName(e.target.value)} required autoFocus />
          <Input label="Last Name *" value={lastName} onChange={(e) => setLastName(e.target.value)} required />
        </div>

        <Input
          label="Role *"
          value={role}
          onChange={(e) => setRole(e.target.value)}
          placeholder="e.g. Foreman, Project Manager, Dispatcher"
          required
        />

        <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
          <Input label="Phone *" type="tel" value={phone} onChange={(e) => setPhone(e.target.value)} required />
          <Input label="Email" type="email" value={email} onChange={(e) => setEmail(e.target.value)} />
        </div>

        <div className="flex items-center gap-2">
          <input
            type="checkbox"
            id="isPrimaryGC"
            checked={isPrimary}
            onChange={(e) => setIsPrimary(e.target.checked)}
            className="rounded border-gray-300 dark:border-gray-600"
          />
          <label htmlFor="isPrimaryGC" className="text-sm text-gray-700 dark:text-gray-300">Primary contact</label>
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">Notes</label>
          <textarea
            value={notes}
            onChange={(e) => setNotes(e.target.value)}
            rows={2}
            className="w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 px-3 py-2 text-sm resize-none"
          />
        </div>

        <div className="flex justify-end gap-2 pt-2">
          <Button variant="ghost" onClick={onClose}>Cancel</Button>
          <Button
            type="submit"
            isLoading={isLoading}
            disabled={!firstName.trim() || !lastName.trim() || !phone.trim() || !role.trim()}
          >
            {initial ? 'Save Changes' : 'Add Contact'}
          </Button>
        </div>
      </form>
    </Modal>
  );
}
