/**
 * PeopleTab — Team members, customers, and GCs linked to a job.
 * Extracted from JobDetailPage.
 */

import { useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import {
  Users, UserPlus, Building2, Link2, Unlink,
  Phone, Mail, X, HardHat, Crown,
} from 'lucide-react';
import { Button } from '../../../../components/ui/Button';
import { Badge } from '../../../../components/ui/Badge';
import { Card } from '../../../../components/ui/Card';
import { useAuthStore } from '../../../../stores/auth-store';
import { PERMISSIONS } from '../../../../lib/constants';
import {
  getJobTeam, addJobTeamMember, removeJobTeamMember,
} from '../../../../api/jobs';
import { getEmployees } from '../../../../api/people';
import {
  getJobCustomers, getJobGCs, linkCustomerToJob, unlinkCustomerFromJob,
  linkGCToJob, unlinkGCFromJob, searchCustomers, searchGCs,
} from '../../../../api/contacts';
import type {
  CustomerContactRole,
  GCRelationship, CustomerListItem, GCListItem,
  EmployeeListItem,
} from '../../../../lib/types';

const CONTACT_ROLE_LABELS: Record<CustomerContactRole, string> = {
  owner: 'Owner',
  property_manager: 'Property Manager',
  tenant: 'Tenant',
  site_contact: 'Site Contact',
  billing: 'Billing',
  other: 'Other',
};

const GC_RELATIONSHIP_LABELS: Record<GCRelationship, string> = {
  they_are_gc: 'They hired us',
  we_hired_them: 'We hired them',
};

export function PeopleTab({ jobId }: { jobId: number }) {
  const queryClient = useQueryClient();
  const { hasPermission } = useAuthStore();
  const canManage = hasPermission(PERMISSIONS.MANAGE_JOBS);

  // ── Team members ──
  const { data: teamMembers = [] } = useQuery({
    queryKey: ['job-team', jobId],
    queryFn: () => getJobTeam(jobId),
    staleTime: 30_000,
  });

  const [showAddTeam, setShowAddTeam] = useState(false);
  const [teamSearch, setTeamSearch] = useState('');
  const [teamRole, setTeamRole] = useState<'lead' | 'member'>('member');
  const [empResults, setEmpResults] = useState<EmployeeListItem[]>([]);

  const searchEmpMut = useMutation({
    mutationFn: (q: string) => getEmployees({ search: q, page_size: 10 }),
    onSuccess: (data) => setEmpResults(data.items),
  });

  const addTeamMut = useMutation({
    mutationFn: (userId: number) =>
      addJobTeamMember(jobId, { user_id: userId, role: teamRole }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['job-team', jobId] });
      setShowAddTeam(false);
      setTeamSearch('');
      setEmpResults([]);
    },
  });

  const removeTeamMut = useMutation({
    mutationFn: (memberId: number) => removeJobTeamMember(jobId, memberId),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['job-team', jobId] }),
  });

  // ── Linked customers & GCs ──
  const { data: customers = [] } = useQuery({
    queryKey: ['job-customers', jobId],
    queryFn: () => getJobCustomers(jobId),
    staleTime: 30_000,
  });

  const { data: gcs = [] } = useQuery({
    queryKey: ['job-gcs', jobId],
    queryFn: () => getJobGCs(jobId),
    staleTime: 30_000,
  });

  // ── Customer linking ──
  const [custSearch, setCustSearch] = useState('');
  const [custResults, setCustResults] = useState<CustomerListItem[]>([]);
  const [showCustSearch, setShowCustSearch] = useState(false);

  const searchCustMut = useMutation({
    mutationFn: (q: string) => searchCustomers(q),
    onSuccess: (data) => setCustResults(data),
  });

  const linkCustMut = useMutation({
    mutationFn: (custId: number) =>
      linkCustomerToJob(jobId, { customer_id: custId }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['job-customers', jobId] });
      setShowCustSearch(false);
      setCustSearch('');
      setCustResults([]);
    },
  });

  const unlinkCustMut = useMutation({
    mutationFn: (linkId: number) => unlinkCustomerFromJob(jobId, linkId),
    onSuccess: () =>
      queryClient.invalidateQueries({ queryKey: ['job-customers', jobId] }),
  });

  // ── GC linking ──
  const [gcSearch, setGcSearch] = useState('');
  const [gcResults, setGcResults] = useState<GCListItem[]>([]);
  const [showGcSearch, setShowGcSearch] = useState(false);
  const [gcRelationship, setGcRelationship] = useState<GCRelationship>('they_are_gc');

  const searchGcMut = useMutation({
    mutationFn: (q: string) => searchGCs(q),
    onSuccess: (data) => setGcResults(data),
  });

  const linkGcMut = useMutation({
    mutationFn: (gcId: number) =>
      linkGCToJob(jobId, { gc_id: gcId, relationship: gcRelationship }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['job-gcs', jobId] });
      setShowGcSearch(false);
      setGcSearch('');
      setGcResults([]);
    },
  });

  const unlinkGcMut = useMutation({
    mutationFn: (linkId: number) => unlinkGCFromJob(jobId, linkId),
    onSuccess: () =>
      queryClient.invalidateQueries({ queryKey: ['job-gcs', jobId] }),
  });

  return (
    <div className="space-y-6">
      {/* ── Team Section ──────────────────────────────────── */}
      <Card className="p-4">
        <div className="flex items-center justify-between mb-3">
          <h3 className="font-semibold text-gray-900 dark:text-white flex items-center gap-2">
            <HardHat size={16} />
            Assigned Team
            <Badge variant="neutral" className="text-xs">{teamMembers.length}</Badge>
          </h3>
          {canManage && (
            <Button
              size="sm"
              variant="secondary"
              onClick={() => setShowAddTeam(!showAddTeam)}
            >
              <UserPlus size={14} />
              <span className="hidden sm:inline ml-1">Add Member</span>
            </Button>
          )}
        </div>

        {/* Add member search panel */}
        {showAddTeam && (
          <div className="mb-3 p-3 bg-surface-secondary rounded-lg border border-border space-y-2">
            {/* Role selector */}
            <div className="flex items-center gap-2">
              <span className="text-xs text-gray-500 dark:text-gray-400">Role:</span>
              <button
                onClick={() => setTeamRole('member')}
                className={`px-2.5 py-1 rounded-md text-xs font-medium transition-colors ${teamRole === 'member'
                  ? 'bg-blue-100 dark:bg-blue-900/40 text-blue-700 dark:text-blue-300'
                  : 'text-gray-500 dark:text-gray-400 hover:bg-surface'
                  }`}
              >
                Member
              </button>
              <button
                onClick={() => setTeamRole('lead')}
                className={`flex items-center gap-1 px-2.5 py-1 rounded-md text-xs font-medium transition-colors ${teamRole === 'lead'
                  ? 'bg-amber-100 dark:bg-amber-900/40 text-amber-700 dark:text-amber-300'
                  : 'text-gray-500 dark:text-gray-400 hover:bg-surface'
                  }`}
              >
                <Crown size={11} />
                Lead
              </button>
            </div>
            {/* Employee search */}
            <div className="flex items-center gap-2">
              <input
                type="text"
                value={teamSearch}
                onChange={e => {
                  setTeamSearch(e.target.value);
                  if (e.target.value.length >= 1) searchEmpMut.mutate(e.target.value);
                  else setEmpResults([]);
                }}
                placeholder="Search employees by name\u2026"
                className="flex-1 text-sm px-3 py-1.5 rounded-md border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-white"
                autoFocus
              />
              <button onClick={() => { setShowAddTeam(false); setTeamSearch(''); setEmpResults([]); }}>
                <X size={16} className="text-gray-400" />
              </button>
            </div>
            {empResults.length > 0 && (
              <div className="space-y-1 max-h-40 overflow-y-auto">
                {empResults
                  .filter(e => !teamMembers.some(m => m.user_id === e.id))
                  .map(emp => (
                    <button
                      key={emp.id}
                      onClick={() => addTeamMut.mutate(emp.id)}
                      disabled={addTeamMut.isPending}
                      className="w-full text-left px-3 py-2 rounded-lg hover:bg-surface text-sm text-gray-900 dark:text-white transition-colors"
                    >
                      <span className="font-medium">{emp.display_name}</span>
                      {emp.email && (
                        <span className="text-gray-500 dark:text-gray-400 ml-2 text-xs">
                          {emp.email}
                        </span>
                      )}
                    </button>
                  ))}
              </div>
            )}
            {teamSearch.length >= 1 && empResults.length === 0 && !searchEmpMut.isPending && (
              <p className="text-xs text-gray-400 dark:text-gray-500 px-1">No matching employees</p>
            )}
          </div>
        )}

        {/* Team member list */}
        {teamMembers.length === 0 ? (
          <p className="text-sm text-gray-400 dark:text-gray-500 py-2">
            No team members assigned yet.
          </p>
        ) : (
          <div className="space-y-2">
            {teamMembers.map(member => (
              <div
                key={member.id}
                className="flex items-center gap-3 p-2.5 rounded-lg bg-surface-secondary border border-border"
              >
                <div className={`flex-shrink-0 w-7 h-7 rounded-full flex items-center justify-center ${member.role === 'lead'
                  ? 'bg-amber-100 dark:bg-amber-900/40'
                  : 'bg-blue-100 dark:bg-blue-900/40'
                  }`}>
                  {member.role === 'lead'
                    ? <Crown size={13} className="text-amber-600 dark:text-amber-400" />
                    : <Users size={13} className="text-blue-600 dark:text-blue-400" />
                  }
                </div>
                <div className="flex-1 min-w-0">
                  <p className="text-sm font-medium text-gray-900 dark:text-gray-100 truncate">
                    {member.display_name}
                  </p>
                  {member.email && (
                    <p className="text-xs text-gray-500 dark:text-gray-400 truncate">
                      {member.email}
                    </p>
                  )}
                </div>
                <Badge variant={member.role === 'lead' ? 'warning' : 'default'}>
                  {member.role === 'lead' ? 'Lead' : 'Member'}
                </Badge>
                {canManage && (
                  <button
                    onClick={() => removeTeamMut.mutate(member.id)}
                    disabled={removeTeamMut.isPending}
                    className="text-gray-300 dark:text-gray-600 hover:text-red-400 dark:hover:text-red-400 transition-colors flex-shrink-0"
                    title="Remove from team"
                  >
                    <X size={15} />
                  </button>
                )}
              </div>
            ))}
          </div>
        )}
      </Card>

      {/* ── Customers Section ─────────────────────────────── */}
      <Card className="p-4">
        <div className="flex items-center justify-between mb-3">
          <h3 className="font-semibold text-gray-900 dark:text-white flex items-center gap-2">
            <UserPlus size={16} />
            Customers
            <Badge variant="neutral" className="text-xs">{customers.length}</Badge>
          </h3>
          {canManage && (
            <Button
              size="sm"
              variant="secondary"
              onClick={() => setShowCustSearch(!showCustSearch)}
            >
              <Link2 size={14} />
              <span className="hidden sm:inline ml-1">Link Customer</span>
            </Button>
          )}
        </div>

        {/* Search to link */}
        {showCustSearch && (
          <div className="mb-3 p-3 bg-surface-secondary rounded-lg border border-border">
            <div className="flex items-center gap-2">
              <input
                type="text"
                value={custSearch}
                onChange={e => {
                  setCustSearch(e.target.value);
                  if (e.target.value.length >= 2) searchCustMut.mutate(e.target.value);
                }}
                placeholder="Search customers..."
                className="flex-1 text-sm px-3 py-1.5 rounded-md border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-white"
                autoFocus
              />
              <button onClick={() => { setShowCustSearch(false); setCustSearch(''); setCustResults([]); }}>
                <X size={16} className="text-gray-400" />
              </button>
            </div>
            {custResults.length > 0 && (
              <div className="mt-2 space-y-1 max-h-40 overflow-y-auto">
                {custResults
                  .filter(c => !customers.some(lc => lc.customer_id === c.id))
                  .map(c => (
                    <button
                      key={c.id}
                      onClick={() => linkCustMut.mutate(c.id)}
                      className="w-full text-left p-2 rounded text-sm hover:bg-gray-100 dark:hover:bg-gray-700 text-gray-700 dark:text-gray-300"
                    >
                      <span className="font-medium">{c.display_name}</span>
                      {c.company_name && (
                        <span className="text-gray-500 dark:text-gray-400 ml-1">({c.company_name})</span>
                      )}
                    </button>
                  ))}
              </div>
            )}
          </div>
        )}

        {/* Linked customers list */}
        {customers.length === 0 ? (
          <p className="text-sm text-gray-400 dark:text-gray-500 text-center py-3">
            No customers linked to this job yet.
          </p>
        ) : (
          <div className="space-y-2">
            {customers.map(c => (
              <div
                key={c.id}
                className="flex items-center justify-between p-3 rounded-lg border border-gray-200 dark:border-gray-700"
              >
                <div className="min-w-0 flex-1">
                  <div className="flex items-center gap-2 flex-wrap">
                    <span className="font-medium text-sm text-gray-900 dark:text-white">
                      {c.customer_name}
                    </span>
                    {c.company_name && (
                      <span className="text-xs text-gray-500 dark:text-gray-400">
                        {c.company_name}
                      </span>
                    )}
                    <Badge variant="neutral" className="text-[10px]">
                      {CONTACT_ROLE_LABELS[c.contact_role]}
                    </Badge>
                    {c.is_primary && <Badge variant="success" className="text-[10px]">Primary</Badge>}
                  </div>
                  <div className="flex items-center gap-3 mt-1 text-xs text-gray-500 dark:text-gray-400">
                    {c.phone && (
                      <span className="flex items-center gap-1">
                        <Phone size={10} /> {c.phone}
                      </span>
                    )}
                    {c.email && (
                      <span className="flex items-center gap-1">
                        <Mail size={10} /> {c.email}
                      </span>
                    )}
                  </div>
                </div>
                {canManage && (
                  <button
                    onClick={() => unlinkCustMut.mutate(c.id)}
                    className="p-1.5 rounded hover:bg-red-50 dark:hover:bg-red-900/20 text-gray-400 hover:text-red-500"
                    title="Unlink customer"
                  >
                    <Unlink size={14} />
                  </button>
                )}
              </div>
            ))}
          </div>
        )}
      </Card>

      {/* ── General Contractors Section ────────────────────── */}
      <Card className="p-4">
        <div className="flex items-center justify-between mb-3">
          <h3 className="font-semibold text-gray-900 dark:text-white flex items-center gap-2">
            <Building2 size={16} />
            General Contractors
            <Badge variant="neutral" className="text-xs">{gcs.length}</Badge>
          </h3>
          {canManage && (
            <Button
              size="sm"
              variant="secondary"
              onClick={() => setShowGcSearch(!showGcSearch)}
            >
              <Link2 size={14} />
              <span className="hidden sm:inline ml-1">Link GC</span>
            </Button>
          )}
        </div>

        {/* Search to link */}
        {showGcSearch && (
          <div className="mb-3 p-3 bg-surface-secondary rounded-lg border border-border">
            <div className="flex items-center gap-2 mb-2">
              <input
                type="text"
                value={gcSearch}
                onChange={e => {
                  setGcSearch(e.target.value);
                  if (e.target.value.length >= 2) searchGcMut.mutate(e.target.value);
                }}
                placeholder="Search general contractors..."
                className="flex-1 text-sm px-3 py-1.5 rounded-md border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-white"
                autoFocus
              />
              <button onClick={() => { setShowGcSearch(false); setGcSearch(''); setGcResults([]); }}>
                <X size={16} className="text-gray-400" />
              </button>
            </div>
            <div className="flex items-center gap-2 mb-2">
              <span className="text-xs text-gray-500 dark:text-gray-400">Relationship:</span>
              <select
                value={gcRelationship}
                onChange={e => setGcRelationship(e.target.value as GCRelationship)}
                className="text-xs px-2 py-1 rounded border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-700 dark:text-gray-300"
              >
                <option value="they_are_gc">They hired us</option>
                <option value="we_hired_them">We hired them</option>
              </select>
            </div>
            {gcResults.length > 0 && (
              <div className="space-y-1 max-h-40 overflow-y-auto">
                {gcResults
                  .filter(g => !gcs.some(lg => lg.gc_id === g.id))
                  .map(g => (
                    <button
                      key={g.id}
                      onClick={() => linkGcMut.mutate(g.id)}
                      className="w-full text-left p-2 rounded text-sm hover:bg-gray-100 dark:hover:bg-gray-700 text-gray-700 dark:text-gray-300"
                    >
                      <span className="font-medium">{g.company_name}</span>
                      <Badge variant="neutral" className="text-[10px] ml-2">{g.gc_code}</Badge>
                    </button>
                  ))}
              </div>
            )}
          </div>
        )}

        {/* Linked GCs list */}
        {gcs.length === 0 ? (
          <p className="text-sm text-gray-400 dark:text-gray-500 text-center py-3">
            No general contractors linked to this job yet.
          </p>
        ) : (
          <div className="space-y-2">
            {gcs.map(g => (
              <div
                key={g.id}
                className="flex items-center justify-between p-3 rounded-lg border border-gray-200 dark:border-gray-700"
              >
                <div className="min-w-0 flex-1">
                  <div className="flex items-center gap-2 flex-wrap">
                    <span className="font-medium text-sm text-gray-900 dark:text-white">
                      {g.company_name}
                    </span>
                    <Badge variant="neutral" className="text-[10px] font-mono">
                      {g.gc_code}
                    </Badge>
                    <Badge
                      variant={g.relationship === 'they_are_gc' ? 'success' : 'warning'}
                      className="text-[10px]"
                    >
                      {GC_RELATIONSHIP_LABELS[g.relationship]}
                    </Badge>
                    {g.is_primary && <Badge variant="success" className="text-[10px]">Primary</Badge>}
                  </div>
                  <div className="flex items-center gap-3 mt-1 text-xs text-gray-500 dark:text-gray-400">
                    <span className="capitalize">{g.trade_type.replace('_', ' ')}</span>
                    {g.phone && (
                      <span className="flex items-center gap-1">
                        <Phone size={10} /> {g.phone}
                      </span>
                    )}
                    {g.contract_number && (
                      <span>Contract: {g.contract_number}</span>
                    )}
                  </div>
                </div>
                {canManage && (
                  <button
                    onClick={() => unlinkGcMut.mutate(g.id)}
                    className="p-1.5 rounded hover:bg-red-50 dark:hover:bg-red-900/20 text-gray-400 hover:text-red-500"
                    title="Unlink GC"
                  >
                    <Unlink size={14} />
                  </button>
                )}
              </div>
            ))}
          </div>
        )}
      </Card>
    </div>
  );
}
