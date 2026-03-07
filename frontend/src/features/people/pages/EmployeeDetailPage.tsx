/**
 * EmployeeDetailPage — full employee profile with sub-tabs for
 * overview, certifications, wage history, notes, and skills.
 *
 * Contact info is prominently displayed in the Overview tab for cross-module
 * reference (Jobs, Trucks, Orders, etc. all link here for employee contact).
 */

import { useState, useRef } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  ArrowLeft, Mail, Phone, AlertTriangle, Calendar, DollarSign,
  Shield, Award, FileText, Wrench, Edit2, UserCheck, UserX,
  Plus, Trash2, X, Clock, ChevronRight, Camera,
} from 'lucide-react';
import { PageSpinner } from '../../../components/ui/Spinner';
import { Button } from '../../../components/ui/Button';
import { Badge } from '../../../components/ui/Badge';
import { Card, CardHeader } from '../../../components/ui/Card';
import { Modal } from '../../../components/ui/Modal';
import { Input } from '../../../components/ui/Input';
import { useAuthStore } from '../../../stores/auth-store';
import { PERMISSIONS } from '../../../lib/constants';
import {
  getEmployee, updateEmployee, toggleEmployeeActive,
  uploadEmployeeAvatar,
  createCertification, updateCertification, deleteCertification,
  createWageEntry,
  createEmployeeNote, updateEmployeeNote, deleteEmployeeNote,
  createSkill, updateSkill, deleteSkill,
} from '../../../api/people';
import type {
  EmployeeDetail, EmployeeUpdate,
  CertificationCreate, CertificationResponse,
  WageHistoryCreate, WageHistoryResponse,
  EmployeeNoteCreate, EmployeeNoteResponse, NoteType,
  UserSkillCreate, UserSkillResponse, Proficiency,
} from '../../../lib/types';

// ── Sub-tab IDs ───────────────────────────────────────────────────
const TABS = [
  { id: 'overview', label: 'Overview', icon: Shield },
  { id: 'certifications', label: 'Certifications', icon: Award },
  { id: 'wages', label: 'Wage History', icon: DollarSign },
  { id: 'notes', label: 'Notes', icon: FileText },
  { id: 'skills', label: 'Skills', icon: Wrench },
] as const;

type TabId = typeof TABS[number]['id'];

// ── Helpers ───────────────────────────────────────────────────────

function daysUntil(dateStr: string | null): number | null {
  if (!dateStr) return null;
  const diff = new Date(dateStr).getTime() - Date.now();
  return Math.ceil(diff / (1000 * 60 * 60 * 24));
}

function expiryColor(days: number | null): string {
  if (days === null) return 'text-gray-500 dark:text-gray-400';
  if (days < 0) return 'text-red-600 dark:text-red-400';
  if (days <= 30) return 'text-red-500 dark:text-red-400';
  if (days <= 60) return 'text-amber-500 dark:text-amber-400';
  return 'text-green-600 dark:text-green-400';
}

function proficiencyColor(p: Proficiency): 'default' | 'primary' | 'success' | 'warning' {
  switch (p) {
    case 'expert': return 'success';
    case 'advanced': return 'primary';
    case 'intermediate': return 'warning';
    default: return 'default';
  }
}

const NOTE_TYPE_COLORS: Record<NoteType, 'default' | 'primary' | 'success' | 'warning' | 'danger'> = {
  general: 'default',
  performance: 'primary',
  incident: 'danger',
  commendation: 'success',
  training: 'warning',
  disciplinary: 'danger',
};

// ═════════════════════════════════════════════════════════════════
// MAIN PAGE
// ═════════════════════════════════════════════════════════════════

export function EmployeeDetailPage() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const { hasPermission } = useAuthStore();
  const canManage = hasPermission(PERMISSIONS.MANAGE_PEOPLE);
  const canSeeDollars = hasPermission(PERMISSIONS.SHOW_DOLLAR_VALUES) || canManage;

  const [activeTab, setActiveTab] = useState<TabId>('overview');

  const userId = Number(id);

  const { data: emp, isLoading, error } = useQuery({
    queryKey: ['employee-detail', userId],
    queryFn: () => getEmployee(userId),
    enabled: !!id && !isNaN(userId),
    staleTime: 10_000,
  });

  const toggleMutation = useMutation({
    mutationFn: (isActive: boolean) => toggleEmployeeActive(userId, isActive),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['employee-detail', userId] }),
  });

  const avatarInputRef = useRef<HTMLInputElement>(null);
  const avatarMutation = useMutation({
    mutationFn: (file: File) => uploadEmployeeAvatar(userId, file),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['employee-detail', userId] }),
  });

  if (isLoading) return <PageSpinner label="Loading employee..." />;
  if (error || !emp) {
    return (
      <div className="text-center py-16">
        <p className="text-red-500">Employee not found.</p>
        <Button variant="ghost" className="mt-4" onClick={() => navigate('/people/employees')}>
          Back to Employees
        </Button>
      </div>
    );
  }

  return (
    <div className="space-y-4">
      {/* ── Header ─────────────────────────────────────────── */}
      <div className="flex items-start gap-3 flex-wrap">
        <button
          onClick={() => navigate('/people/employees')}
          className="p-2 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors mt-0.5"
        >
          <ArrowLeft size={20} className="text-gray-500 dark:text-gray-400" />
        </button>

        {/* Avatar — click to upload when canManage */}
        <div className="flex-shrink-0 relative group">
          <div className="w-12 h-12 rounded-full bg-primary-100 dark:bg-primary-900/30 flex items-center justify-center text-primary-700 dark:text-primary-300 font-bold text-lg overflow-hidden">
            {emp.avatar_url ? (
              <img src={emp.avatar_url} alt="" className="w-12 h-12 rounded-full object-cover" />
            ) : (
              emp.display_name.charAt(0).toUpperCase()
            )}
          </div>
          {canManage && (
            <>
              <button
                onClick={() => avatarInputRef.current?.click()}
                className="absolute inset-0 rounded-full flex items-center justify-center bg-black/40 opacity-0 group-hover:opacity-100 transition-opacity"
                title="Change photo"
                disabled={avatarMutation.isPending}
              >
                <Camera size={16} className="text-white" />
              </button>
              <input
                ref={avatarInputRef}
                type="file"
                accept="image/*"
                className="hidden"
                onChange={(e) => {
                  const file = e.target.files?.[0];
                  if (file) avatarMutation.mutate(file);
                  e.target.value = '';
                }}
              />
            </>
          )}
        </div>

        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 flex-wrap">
            <h1 className="text-xl font-semibold text-gray-900 dark:text-gray-100">
              {emp.display_name}
            </h1>
            {emp.is_active ? (
              <Badge variant="success">Active</Badge>
            ) : (
              <Badge variant="danger">Inactive</Badge>
            )}
            {emp.certification && (
              <Badge variant="primary">{emp.certification.charAt(0).toUpperCase() + emp.certification.slice(1)}</Badge>
            )}
          </div>
          <div className="flex items-center gap-2 mt-0.5 flex-wrap">
            {emp.hats.map((h) => (
              <span key={h.id} className="text-xs px-1.5 py-0.5 rounded bg-gray-100 dark:bg-gray-700 text-gray-600 dark:text-gray-400">
                {h.name}
              </span>
            ))}
          </div>
        </div>

        {/* Actions */}
        {canManage && (
          <div className="flex items-center gap-2">
            <Button
              variant={emp.is_active ? 'ghost' : 'primary'}
              size="sm"
              icon={emp.is_active ? <UserX size={16} /> : <UserCheck size={16} />}
              isLoading={toggleMutation.isPending}
              onClick={() => toggleMutation.mutate(!emp.is_active)}
            >
              <span className="hidden sm:inline">{emp.is_active ? 'Deactivate' : 'Activate'}</span>
            </Button>
          </div>
        )}
      </div>

      {/* ── Sub-tab bar ────────────────────────────────────── */}
      <div className="overflow-x-auto -mx-4 px-4 sm:mx-0 sm:px-0">
        <div className="flex gap-1 border-b border-gray-200 dark:border-gray-700 whitespace-nowrap">
          {TABS.map((tab) => {
            // Hide wages tab if no dollar permission
            if (tab.id === 'wages' && !canSeeDollars) return null;
            const Icon = tab.icon;
            const isActive = activeTab === tab.id;
            return (
              <button
                key={tab.id}
                onClick={() => setActiveTab(tab.id)}
                className={`flex items-center gap-1.5 px-3 py-2.5 text-sm font-medium border-b-2 transition-colors ${
                  isActive
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
      {activeTab === 'overview' && <OverviewTab emp={emp} canManage={canManage} canSeeDollars={canSeeDollars} />}
      {activeTab === 'certifications' && <CertificationsTab emp={emp} canManage={canManage} />}
      {activeTab === 'wages' && canSeeDollars && <WagesTab emp={emp} canManage={canManage} />}
      {activeTab === 'notes' && <NotesTab emp={emp} canManage={canManage} />}
      {activeTab === 'skills' && <SkillsTab emp={emp} canManage={canManage} />}
    </div>
  );
}


// ═════════════════════════════════════════════════════════════════
// OVERVIEW TAB
// ═════════════════════════════════════════════════════════════════

function OverviewTab({ emp, canManage, canSeeDollars }: { emp: EmployeeDetail; canManage: boolean; canSeeDollars: boolean }) {
  return (
    <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
      {/* Contact Info Card — primary contact reference */}
      <Card>
        <CardHeader title="Contact Information" />
        <div className="space-y-3 mt-3">
          {emp.email && (
            <div className="flex items-center gap-3">
              <Mail size={16} className="text-gray-400 dark:text-gray-500 flex-shrink-0" />
              <a href={`mailto:${emp.email}`} className="text-sm text-primary-600 dark:text-primary-400 hover:underline truncate">
                {emp.email}
              </a>
            </div>
          )}
          {emp.phone && (
            <div className="flex items-center gap-3">
              <Phone size={16} className="text-gray-400 dark:text-gray-500 flex-shrink-0" />
              <a href={`tel:${emp.phone}`} className="text-sm text-primary-600 dark:text-primary-400 hover:underline">
                {emp.phone}
              </a>
            </div>
          )}
          {!emp.email && !emp.phone && (
            <p className="text-sm text-gray-400 dark:text-gray-500 italic">No contact info on file</p>
          )}
        </div>
      </Card>

      {/* Emergency Contact Card */}
      <Card>
        <CardHeader title="Emergency Contact" />
        <div className="space-y-3 mt-3">
          {emp.emergency_contact_name ? (
            <>
              <div className="flex items-center gap-3">
                <AlertTriangle size={16} className="text-amber-500 flex-shrink-0" />
                <span className="text-sm text-gray-900 dark:text-gray-100">{emp.emergency_contact_name}</span>
              </div>
              {emp.emergency_contact_phone && (
                <div className="flex items-center gap-3 pl-7">
                  <Phone size={14} className="text-gray-400 dark:text-gray-500 flex-shrink-0" />
                  <a href={`tel:${emp.emergency_contact_phone}`} className="text-sm text-primary-600 dark:text-primary-400 hover:underline">
                    {emp.emergency_contact_phone}
                  </a>
                </div>
              )}
            </>
          ) : (
            <p className="text-sm text-gray-400 dark:text-gray-500 italic">No emergency contact on file</p>
          )}
        </div>
      </Card>

      {/* Employment Info Card */}
      <Card>
        <CardHeader title="Employment" />
        <div className="space-y-3 mt-3">
          {emp.hire_date && (
            <div className="flex items-center gap-3">
              <Calendar size={16} className="text-gray-400 dark:text-gray-500 flex-shrink-0" />
              <span className="text-sm text-gray-700 dark:text-gray-300">Hired: {emp.hire_date}</span>
            </div>
          )}
          {emp.certification && (
            <div className="flex items-center gap-3">
              <Award size={16} className="text-gray-400 dark:text-gray-500 flex-shrink-0" />
              <span className="text-sm text-gray-700 dark:text-gray-300">
                {emp.certification.charAt(0).toUpperCase() + emp.certification.slice(1)} Electrician
              </span>
            </div>
          )}
          {canSeeDollars && emp.pay_rate != null && (
            <div className="flex items-center gap-3">
              <DollarSign size={16} className="text-gray-400 dark:text-gray-500 flex-shrink-0" />
              <span className="text-sm text-gray-700 dark:text-gray-300">
                ${emp.pay_rate.toFixed(2)}/hr
              </span>
            </div>
          )}
        </div>
      </Card>

      {/* Quick Stats Card */}
      <Card>
        <CardHeader title="Quick Stats" />
        <div className="grid grid-cols-2 gap-3 mt-3">
          <StatBox label="Certifications" value={emp.certifications.length} />
          <StatBox label="Skills" value={emp.skills.length} />
          <StatBox label="Notes" value={emp.notes.length} />
          <StatBox label="Roles" value={emp.hats.length} />
        </div>
      </Card>
    </div>
  );
}

function StatBox({ label, value }: { label: string; value: number }) {
  return (
    <div className="text-center p-2 rounded-lg bg-gray-50 dark:bg-gray-800/50">
      <div className="text-lg font-semibold text-gray-900 dark:text-gray-100">{value}</div>
      <div className="text-xs text-gray-500 dark:text-gray-400">{label}</div>
    </div>
  );
}


// ═════════════════════════════════════════════════════════════════
// CERTIFICATIONS TAB
// ═════════════════════════════════════════════════════════════════

function CertificationsTab({ emp, canManage }: { emp: EmployeeDetail; canManage: boolean }) {
  const queryClient = useQueryClient();
  const [showAdd, setShowAdd] = useState(false);

  const addMut = useMutation({
    mutationFn: (data: CertificationCreate) => createCertification(emp.id, data),
    onSuccess: () => { queryClient.invalidateQueries({ queryKey: ['employee-detail', emp.id] }); setShowAdd(false); },
  });

  const deleteMut = useMutation({
    mutationFn: deleteCertification,
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['employee-detail', emp.id] }),
  });

  return (
    <div className="space-y-3">
      {canManage && (
        <div className="flex justify-end">
          <Button size="sm" icon={<Plus size={16} />} onClick={() => setShowAdd(true)}>
            <span className="hidden sm:inline">Add Certification</span>
          </Button>
        </div>
      )}

      {emp.certifications.length === 0 ? (
        <Card><p className="text-sm text-gray-500 dark:text-gray-400 text-center py-4">No certifications on file.</p></Card>
      ) : (
        emp.certifications.map((cert) => {
          const days = daysUntil(cert.expiry_date);
          return (
            <Card key={cert.id}>
              <div className="flex items-start justify-between gap-3">
                <div className="min-w-0">
                  <div className="flex items-center gap-2 flex-wrap">
                    <span className="font-medium text-gray-900 dark:text-gray-100">{cert.cert_name}</span>
                    <Badge variant="primary">{cert.cert_type.replace('_', ' ')}</Badge>
                    {!cert.is_active && <Badge variant="danger">Inactive</Badge>}
                  </div>
                  {cert.issuing_authority && (
                    <p className="text-sm text-gray-500 dark:text-gray-400 mt-0.5">Issued by: {cert.issuing_authority}</p>
                  )}
                  <div className="flex items-center gap-4 mt-1 text-xs text-gray-500 dark:text-gray-400 flex-wrap">
                    {cert.cert_number && <span>#{cert.cert_number}</span>}
                    {cert.issued_date && <span>Issued: {cert.issued_date}</span>}
                    {cert.expiry_date && (
                      <span className={expiryColor(days)}>
                        Expires: {cert.expiry_date}
                        {days !== null && ` (${days < 0 ? 'expired' : `${days}d`})`}
                      </span>
                    )}
                  </div>
                </div>
                {canManage && (
                  <button
                    onClick={() => deleteMut.mutate(cert.id)}
                    className="p-1.5 text-gray-400 hover:text-red-500 transition-colors flex-shrink-0"
                  >
                    <Trash2 size={14} />
                  </button>
                )}
              </div>
            </Card>
          );
        })
      )}

      {showAdd && (
        <AddCertModal
          isLoading={addMut.isPending}
          error={addMut.error?.message ?? null}
          onSubmit={(data) => addMut.mutate(data)}
          onClose={() => setShowAdd(false)}
        />
      )}
    </div>
  );
}

function AddCertModal({ isLoading, error, onSubmit, onClose }: {
  isLoading: boolean; error: string | null;
  onSubmit: (data: CertificationCreate) => void; onClose: () => void;
}) {
  const [form, setForm] = useState<CertificationCreate>({ cert_type: 'custom', cert_name: '' });
  return (
    <Modal isOpen onClose={onClose} title="Add Certification" size="md">
      <form onSubmit={(e) => { e.preventDefault(); onSubmit(form); }} className="space-y-4">
        {error && <div className="p-2 text-sm text-red-600 dark:text-red-400 bg-red-50 dark:bg-red-900/20 rounded">{error}</div>}
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div className="space-y-1.5">
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300">Type *</label>
            <select value={form.cert_type} onChange={(e) => setForm({ ...form, cert_type: e.target.value as any })}
              className="block w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 px-3 py-2 text-sm">
              {['journeyman','apprentice','master','osha_10','osha_30','first_aid','cpr','forklift','confined_space','custom'].map((t) => (
                <option key={t} value={t}>{t.replace('_',' ')}</option>
              ))}
            </select>
          </div>
          <Input label="Name *" value={form.cert_name} onChange={(e) => setForm({ ...form, cert_name: e.target.value })} required placeholder="e.g. OSHA 30-Hour" />
        </div>
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <Input label="Issuing Authority" value={form.issuing_authority ?? ''} onChange={(e) => setForm({ ...form, issuing_authority: e.target.value || null })} placeholder="OSHA, Red Cross..." />
          <Input label="Cert Number" value={form.cert_number ?? ''} onChange={(e) => setForm({ ...form, cert_number: e.target.value || null })} />
        </div>
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <Input label="Issued Date" type="date" value={form.issued_date ?? ''} onChange={(e) => setForm({ ...form, issued_date: e.target.value || null })} />
          <Input label="Expiry Date" type="date" value={form.expiry_date ?? ''} onChange={(e) => setForm({ ...form, expiry_date: e.target.value || null })} />
        </div>
        <div className="flex justify-end gap-3 pt-2 border-t border-gray-200 dark:border-gray-700">
          <Button variant="ghost" type="button" onClick={onClose}>Cancel</Button>
          <Button type="submit" isLoading={isLoading} disabled={!form.cert_name}>Add Certification</Button>
        </div>
      </form>
    </Modal>
  );
}


// ═════════════════════════════════════════════════════════════════
// WAGE HISTORY TAB
// ═════════════════════════════════════════════════════════════════

function WagesTab({ emp, canManage }: { emp: EmployeeDetail; canManage: boolean }) {
  const queryClient = useQueryClient();
  const [showAdd, setShowAdd] = useState(false);

  const addMut = useMutation({
    mutationFn: (data: WageHistoryCreate) => createWageEntry(emp.id, data),
    onSuccess: () => { queryClient.invalidateQueries({ queryKey: ['employee-detail', emp.id] }); setShowAdd(false); },
  });

  return (
    <div className="space-y-3">
      {canManage && (
        <div className="flex justify-end">
          <Button size="sm" icon={<Plus size={16} />} onClick={() => setShowAdd(true)}>
            <span className="hidden sm:inline">Add Wage Entry</span>
          </Button>
        </div>
      )}

      {emp.wage_history.length === 0 ? (
        <Card><p className="text-sm text-gray-500 dark:text-gray-400 text-center py-4">No wage history on file.</p></Card>
      ) : (
        <Card noPadding>
          <div className="divide-y divide-gray-200 dark:divide-gray-700">
            {emp.wage_history.map((w) => (
              <div key={w.id} className="p-3 sm:p-4 flex items-center justify-between gap-3">
                <div className="min-w-0">
                  <div className="flex items-center gap-2 flex-wrap">
                    <span className="font-medium text-gray-900 dark:text-gray-100">
                      ${w.pay_rate.toFixed(2)}/hr
                    </span>
                    {w.reason && <Badge variant="default">{w.reason}</Badge>}
                  </div>
                  <div className="text-xs text-gray-500 dark:text-gray-400 mt-0.5">
                    Effective: {w.effective_date}
                    {w.changed_by_name && ` · Changed by ${w.changed_by_name}`}
                  </div>
                </div>
                <Clock size={14} className="text-gray-300 dark:text-gray-600 flex-shrink-0" />
              </div>
            ))}
          </div>
        </Card>
      )}

      {showAdd && (
        <Modal isOpen onClose={() => setShowAdd(false)} title="Add Wage Entry" size="sm">
          <AddWageForm
            isLoading={addMut.isPending}
            error={addMut.error?.message ?? null}
            onSubmit={(data) => addMut.mutate(data)}
            onClose={() => setShowAdd(false)}
          />
        </Modal>
      )}
    </div>
  );
}

function AddWageForm({ isLoading, error, onSubmit, onClose }: {
  isLoading: boolean; error: string | null;
  onSubmit: (data: WageHistoryCreate) => void; onClose: () => void;
}) {
  const [form, setForm] = useState<WageHistoryCreate>({ pay_rate: 0, effective_date: new Date().toISOString().slice(0, 10) });
  return (
    <form onSubmit={(e) => { e.preventDefault(); onSubmit(form); }} className="space-y-4">
      {error && <div className="p-2 text-sm text-red-600 dark:text-red-400 bg-red-50 dark:bg-red-900/20 rounded">{error}</div>}
      <Input label="Pay Rate *" type="number" step="0.01" min="0.01" value={form.pay_rate || ''} onChange={(e) => setForm({ ...form, pay_rate: Number(e.target.value) })} required />
      <Input label="Effective Date *" type="date" value={form.effective_date} onChange={(e) => setForm({ ...form, effective_date: e.target.value })} required />
      <div className="space-y-1.5">
        <label className="block text-sm font-medium text-gray-700 dark:text-gray-300">Reason</label>
        <select value={form.reason ?? ''} onChange={(e) => setForm({ ...form, reason: (e.target.value || null) as any })}
          className="block w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 px-3 py-2 text-sm">
          <option value="">Select reason...</option>
          {['hire','raise','promotion','demotion','adjustment','correction'].map((r) => (
            <option key={r} value={r}>{r.charAt(0).toUpperCase() + r.slice(1)}</option>
          ))}
        </select>
      </div>
      <div className="flex justify-end gap-3 pt-2 border-t border-gray-200 dark:border-gray-700">
        <Button variant="ghost" type="button" onClick={onClose}>Cancel</Button>
        <Button type="submit" isLoading={isLoading} disabled={!form.pay_rate}>Add Entry</Button>
      </div>
    </form>
  );
}


// ═════════════════════════════════════════════════════════════════
// NOTES TAB
// ═════════════════════════════════════════════════════════════════

function NotesTab({ emp, canManage }: { emp: EmployeeDetail; canManage: boolean }) {
  const queryClient = useQueryClient();
  const [showAdd, setShowAdd] = useState(false);

  const addMut = useMutation({
    mutationFn: (data: EmployeeNoteCreate) => createEmployeeNote(emp.id, data),
    onSuccess: () => { queryClient.invalidateQueries({ queryKey: ['employee-detail', emp.id] }); setShowAdd(false); },
  });

  const deleteMut = useMutation({
    mutationFn: deleteEmployeeNote,
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['employee-detail', emp.id] }),
  });

  return (
    <div className="space-y-3">
      {canManage && (
        <div className="flex justify-end">
          <Button size="sm" icon={<Plus size={16} />} onClick={() => setShowAdd(true)}>
            <span className="hidden sm:inline">Add Note</span>
          </Button>
        </div>
      )}

      {emp.notes.length === 0 ? (
        <Card><p className="text-sm text-gray-500 dark:text-gray-400 text-center py-4">No notes on file.</p></Card>
      ) : (
        emp.notes.map((note) => (
          <Card key={note.id}>
            <div className="flex items-start justify-between gap-3">
              <div className="min-w-0">
                <div className="flex items-center gap-2 flex-wrap">
                  <span className="font-medium text-gray-900 dark:text-gray-100">{note.title}</span>
                  <Badge variant={NOTE_TYPE_COLORS[note.note_type as NoteType] ?? 'default'}>
                    {note.note_type}
                  </Badge>
                  {note.is_private && <Badge variant="warning">Private</Badge>}
                </div>
                <p className="text-sm text-gray-600 dark:text-gray-400 mt-1 whitespace-pre-wrap line-clamp-3">
                  {note.body}
                </p>
                <div className="text-xs text-gray-400 dark:text-gray-500 mt-1.5">
                  {note.created_by_name && `By ${note.created_by_name} · `}
                  {note.created_at ? new Date(note.created_at).toLocaleDateString() : ''}
                </div>
              </div>
              {canManage && (
                <button
                  onClick={() => deleteMut.mutate(note.id)}
                  className="p-1.5 text-gray-400 hover:text-red-500 transition-colors flex-shrink-0"
                >
                  <Trash2 size={14} />
                </button>
              )}
            </div>
          </Card>
        ))
      )}

      {showAdd && (
        <Modal isOpen onClose={() => setShowAdd(false)} title="Add Note" size="md">
          <AddNoteForm
            isLoading={addMut.isPending}
            error={addMut.error?.message ?? null}
            onSubmit={(data) => addMut.mutate(data)}
            onClose={() => setShowAdd(false)}
          />
        </Modal>
      )}
    </div>
  );
}

function AddNoteForm({ isLoading, error, onSubmit, onClose }: {
  isLoading: boolean; error: string | null;
  onSubmit: (data: EmployeeNoteCreate) => void; onClose: () => void;
}) {
  const [form, setForm] = useState<EmployeeNoteCreate>({ title: '', body: '' });
  return (
    <form onSubmit={(e) => { e.preventDefault(); onSubmit(form); }} className="space-y-4">
      {error && <div className="p-2 text-sm text-red-600 dark:text-red-400 bg-red-50 dark:bg-red-900/20 rounded">{error}</div>}
      <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <Input label="Title *" value={form.title} onChange={(e) => setForm({ ...form, title: e.target.value })} required />
        <div className="space-y-1.5">
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300">Type</label>
          <select value={form.note_type ?? 'general'} onChange={(e) => setForm({ ...form, note_type: e.target.value as any })}
            className="block w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 px-3 py-2 text-sm">
            {['general','performance','incident','commendation','training','disciplinary'].map((t) => (
              <option key={t} value={t}>{t.charAt(0).toUpperCase() + t.slice(1)}</option>
            ))}
          </select>
        </div>
      </div>
      <div className="space-y-1.5">
        <label className="block text-sm font-medium text-gray-700 dark:text-gray-300">Body *</label>
        <textarea
          value={form.body}
          onChange={(e) => setForm({ ...form, body: e.target.value })}
          rows={4}
          required
          className="block w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 px-3 py-2 text-sm resize-y"
        />
      </div>
      <label className="flex items-center gap-2 text-sm text-gray-700 dark:text-gray-300">
        <input type="checkbox" checked={form.is_private ?? false} onChange={(e) => setForm({ ...form, is_private: e.target.checked })}
          className="rounded border-gray-300 dark:border-gray-600" />
        Private (only visible to managers)
      </label>
      <div className="flex justify-end gap-3 pt-2 border-t border-gray-200 dark:border-gray-700">
        <Button variant="ghost" type="button" onClick={onClose}>Cancel</Button>
        <Button type="submit" isLoading={isLoading} disabled={!form.title || !form.body}>Add Note</Button>
      </div>
    </form>
  );
}


// ═════════════════════════════════════════════════════════════════
// SKILLS TAB
// ═════════════════════════════════════════════════════════════════

function SkillsTab({ emp, canManage }: { emp: EmployeeDetail; canManage: boolean }) {
  const queryClient = useQueryClient();
  const [showAdd, setShowAdd] = useState(false);

  const addMut = useMutation({
    mutationFn: (data: UserSkillCreate) => createSkill(emp.id, data),
    onSuccess: () => { queryClient.invalidateQueries({ queryKey: ['employee-detail', emp.id] }); setShowAdd(false); },
  });

  const deleteMut = useMutation({
    mutationFn: deleteSkill,
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['employee-detail', emp.id] }),
  });

  return (
    <div className="space-y-3">
      {canManage && (
        <div className="flex justify-end">
          <Button size="sm" icon={<Plus size={16} />} onClick={() => setShowAdd(true)}>
            <span className="hidden sm:inline">Add Skill</span>
          </Button>
        </div>
      )}

      {emp.skills.length === 0 ? (
        <Card><p className="text-sm text-gray-500 dark:text-gray-400 text-center py-4">No skills on file.</p></Card>
      ) : (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
          {emp.skills.map((skill) => (
            <Card key={skill.id}>
              <div className="flex items-start justify-between gap-2">
                <div className="min-w-0">
                  <div className="flex items-center gap-2 flex-wrap">
                    <span className="font-medium text-gray-900 dark:text-gray-100 text-sm">{skill.skill_name}</span>
                    <Badge variant={proficiencyColor(skill.proficiency)}>{skill.proficiency}</Badge>
                  </div>
                  {skill.years_experience != null && (
                    <p className="text-xs text-gray-500 dark:text-gray-400 mt-1">{skill.years_experience} yrs experience</p>
                  )}
                  {skill.verified_by_name && (
                    <p className="text-xs text-green-600 dark:text-green-400 mt-0.5">✓ Verified by {skill.verified_by_name}</p>
                  )}
                </div>
                {canManage && (
                  <button onClick={() => deleteMut.mutate(skill.id)} className="p-1 text-gray-400 hover:text-red-500 transition-colors flex-shrink-0">
                    <Trash2 size={12} />
                  </button>
                )}
              </div>
            </Card>
          ))}
        </div>
      )}

      {showAdd && (
        <Modal isOpen onClose={() => setShowAdd(false)} title="Add Skill" size="sm">
          <AddSkillForm
            isLoading={addMut.isPending}
            error={addMut.error?.message ?? null}
            onSubmit={(data) => addMut.mutate(data)}
            onClose={() => setShowAdd(false)}
          />
        </Modal>
      )}
    </div>
  );
}

function AddSkillForm({ isLoading, error, onSubmit, onClose }: {
  isLoading: boolean; error: string | null;
  onSubmit: (data: UserSkillCreate) => void; onClose: () => void;
}) {
  const [form, setForm] = useState<UserSkillCreate>({ skill_name: '' });
  return (
    <form onSubmit={(e) => { e.preventDefault(); onSubmit(form); }} className="space-y-4">
      {error && <div className="p-2 text-sm text-red-600 dark:text-red-400 bg-red-50 dark:bg-red-900/20 rounded">{error}</div>}
      <Input label="Skill Name *" value={form.skill_name} onChange={(e) => setForm({ ...form, skill_name: e.target.value })} required placeholder="e.g. Conduit Bending" />
      <div className="space-y-1.5">
        <label className="block text-sm font-medium text-gray-700 dark:text-gray-300">Proficiency</label>
        <select value={form.proficiency ?? 'intermediate'} onChange={(e) => setForm({ ...form, proficiency: e.target.value as any })}
          className="block w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 px-3 py-2 text-sm">
          {['beginner','intermediate','advanced','expert'].map((p) => (
            <option key={p} value={p}>{p.charAt(0).toUpperCase() + p.slice(1)}</option>
          ))}
        </select>
      </div>
      <Input label="Years Experience" type="number" step="0.5" min="0" value={form.years_experience ?? ''} onChange={(e) => setForm({ ...form, years_experience: e.target.value ? Number(e.target.value) : null })} />
      <div className="flex justify-end gap-3 pt-2 border-t border-gray-200 dark:border-gray-700">
        <Button variant="ghost" type="button" onClick={onClose}>Cancel</Button>
        <Button type="submit" isLoading={isLoading} disabled={!form.skill_name}>Add Skill</Button>
      </div>
    </form>
  );
}
