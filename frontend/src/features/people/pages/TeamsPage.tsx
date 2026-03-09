/**
 * TeamsPage — manage global employee teams.
 *
 * Shows all teams with member counts and lead info. Each team card can
 * expand to show its full member list. Supports create, edit, delete
 * teams, and add/remove members.
 *
 * Teams can be assigned to jobs as a group (e.g., "Crew A"),
 * streamlining dispatch and scheduling workflows.
 */

import { useState, useMemo } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  Users2, Plus, Pencil, Trash2, ChevronDown, ChevronRight,
  UserPlus, UserMinus, Crown, Search, X,
} from 'lucide-react';
import { Button } from '../../../components/ui/Button';
import { Card } from '../../../components/ui/Card';
import { Modal } from '../../../components/ui/Modal';
import { Badge } from '../../../components/ui/Badge';
import { Input } from '../../../components/ui/Input';
import { EmptyState } from '../../../components/ui/EmptyState';
import { PageSpinner } from '../../../components/ui/Spinner';
import { useAuthStore } from '../../../stores/auth-store';
import { PERMISSIONS } from '../../../lib/constants';
import { toast } from '../../../lib/toast';
import {
  getTeams,
  getTeam,
  createTeam,
  updateTeam,
  deleteTeam,
  addTeamMember,
  removeTeamMember,
  updateTeamMemberRole,
  getEmployees,
} from '../../../api/people';
import type {
  EmployeeTeamListItem,
  EmployeeTeamDetail,
  EmployeeTeamCreate,
  TeamMemberItem,
} from '../../../lib/types';


export function TeamsPage() {
  const { hasPermission } = useAuthStore();
  const canManage = hasPermission(PERMISSIONS.MANAGE_PEOPLE);
  const queryClient = useQueryClient();

  // ── State ──────────────────────────────────────────────────────
  const [expandedTeamId, setExpandedTeamId] = useState<number | null>(null);
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [editingTeam, setEditingTeam] = useState<EmployeeTeamListItem | null>(null);
  const [addMemberTeamId, setAddMemberTeamId] = useState<number | null>(null);
  const [search, setSearch] = useState('');

  // ── Queries ────────────────────────────────────────────────────
  const { data: teams, isLoading } = useQuery({
    queryKey: ['teams'],
    queryFn: () => getTeams(false), // show all, including inactive
  });

  const { data: expandedDetail } = useQuery({
    queryKey: ['teams', expandedTeamId],
    queryFn: () => getTeam(expandedTeamId!),
    enabled: expandedTeamId !== null,
  });

  // ── Mutations ──────────────────────────────────────────────────
  const createMut = useMutation({
    mutationFn: (data: EmployeeTeamCreate) => createTeam(data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['teams'] });
      setShowCreateModal(false);
      toast.success('Team created');
    },
    onError: (err: any) => toast.error(err?.response?.data?.detail ?? 'Failed to create team'),
  });

  const updateMut = useMutation({
    mutationFn: ({ id, data }: { id: number; data: any }) => updateTeam(id, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['teams'] });
      setEditingTeam(null);
      toast.success('Team updated');
    },
    onError: (err: any) => toast.error(err?.response?.data?.detail ?? 'Failed to update team'),
  });

  const deleteMut = useMutation({
    mutationFn: (id: number) => deleteTeam(id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['teams'] });
      toast.success('Team deleted');
    },
    onError: () => toast.error('Failed to delete team'),
  });

  const addMemberMut = useMutation({
    mutationFn: ({ teamId, userId, role }: { teamId: number; userId: number; role: 'lead' | 'member' }) =>
      addTeamMember(teamId, { user_id: userId, role }),
    onSuccess: (_, vars) => {
      queryClient.invalidateQueries({ queryKey: ['teams'] });
      queryClient.invalidateQueries({ queryKey: ['teams', vars.teamId] });
      toast.success('Member added');
    },
    onError: (err: any) => toast.error(err?.response?.data?.detail ?? 'Failed to add member'),
  });

  const removeMemberMut = useMutation({
    mutationFn: ({ teamId, userId }: { teamId: number; userId: number }) =>
      removeTeamMember(teamId, userId),
    onSuccess: (_, vars) => {
      queryClient.invalidateQueries({ queryKey: ['teams'] });
      queryClient.invalidateQueries({ queryKey: ['teams', vars.teamId] });
      toast.success('Member removed');
    },
    onError: () => toast.error('Failed to remove member'),
  });

  const updateRoleMut = useMutation({
    mutationFn: ({ teamId, userId, role }: { teamId: number; userId: number; role: 'lead' | 'member' }) =>
      updateTeamMemberRole(teamId, userId, role),
    onSuccess: (_, vars) => {
      queryClient.invalidateQueries({ queryKey: ['teams', vars.teamId] });
      toast.success('Role updated');
    },
    onError: () => toast.error('Failed to update role'),
  });

  // ── Derived ────────────────────────────────────────────────────
  const filteredTeams = useMemo(() => {
    if (!teams) return [];
    if (!search.trim()) return teams;
    const q = search.toLowerCase();
    return teams.filter(t =>
      t.name.toLowerCase().includes(q) ||
      t.lead_name?.toLowerCase().includes(q) ||
      t.description?.toLowerCase().includes(q)
    );
  }, [teams, search]);

  const toggleExpand = (id: number) => {
    setExpandedTeamId(prev => (prev === id ? null : id));
  };

  // ── Loading ────────────────────────────────────────────────────
  if (isLoading) return <PageSpinner label="Loading teams..." />;

  return (
    <>
      {/* Header */}
      <div className="flex items-center justify-between flex-wrap gap-3 mb-4">
        <div className="flex items-center gap-3 flex-1 min-w-0">
          <div className="relative flex-1 max-w-xs">
            <Search size={16} className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400" />
            <input
              type="text"
              value={search}
              onChange={e => setSearch(e.target.value)}
              placeholder="Search teams..."
              className="w-full pl-9 pr-3 py-2 text-sm rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 placeholder-gray-400"
            />
          </div>
          <Badge variant="neutral">{filteredTeams.length} team{filteredTeams.length !== 1 ? 's' : ''}</Badge>
        </div>
        {canManage && (
          <Button size="sm" variant="primary" onClick={() => setShowCreateModal(true)}>
            <Plus size={16} />
            <span className="hidden sm:inline">New Team</span>
          </Button>
        )}
      </div>

      {/* Teams List */}
      {filteredTeams.length === 0 ? (
        <EmptyState
          icon={<Users2 className="h-12 w-12" />}
          title={search ? 'No Matching Teams' : 'No Teams Yet'}
          description={search
            ? 'Try adjusting your search.'
            : 'Create teams to group employees for easier dispatch and scheduling.'
          }
        />
      ) : (
        <div className="space-y-3">
          {filteredTeams.map(team => (
            <TeamCard
              key={team.id}
              team={team}
              detail={expandedTeamId === team.id ? expandedDetail ?? null : null}
              expanded={expandedTeamId === team.id}
              canManage={canManage}
              onToggle={() => toggleExpand(team.id)}
              onEdit={() => setEditingTeam(team)}
              onDelete={() => {
                if (confirm(`Delete team "${team.name}"? This cannot be undone.`)) {
                  deleteMut.mutate(team.id);
                }
              }}
              onAddMember={() => setAddMemberTeamId(team.id)}
              onRemoveMember={(userId) => removeMemberMut.mutate({ teamId: team.id, userId })}
              onToggleRole={(userId, currentRole) => {
                const newRole = currentRole === 'lead' ? 'member' : 'lead';
                updateRoleMut.mutate({ teamId: team.id, userId, role: newRole });
              }}
            />
          ))}
        </div>
      )}

      {/* Create Modal */}
      {showCreateModal && (
        <TeamFormModal
          title="New Team"
          onClose={() => setShowCreateModal(false)}
          onSubmit={(data) => createMut.mutate(data)}
          isLoading={createMut.isPending}
        />
      )}

      {/* Edit Modal */}
      {editingTeam && (
        <TeamFormModal
          title="Edit Team"
          initial={editingTeam}
          onClose={() => setEditingTeam(null)}
          onSubmit={(data) => updateMut.mutate({ id: editingTeam.id, data })}
          isLoading={updateMut.isPending}
        />
      )}

      {/* Add Member Modal */}
      {addMemberTeamId !== null && (
        <AddMemberModal
          teamId={addMemberTeamId}
          existingMembers={expandedDetail?.members ?? []}
          onClose={() => setAddMemberTeamId(null)}
          onAdd={(userId, role) => {
            addMemberMut.mutate({ teamId: addMemberTeamId, userId, role });
            setAddMemberTeamId(null);
          }}
        />
      )}
    </>
  );
}


/* ─── Team Card ───────────────────────────────────────────────────── */

function TeamCard({
  team,
  detail,
  expanded,
  canManage,
  onToggle,
  onEdit,
  onDelete,
  onAddMember,
  onRemoveMember,
  onToggleRole,
}: {
  team: EmployeeTeamListItem;
  detail: EmployeeTeamDetail | null;
  expanded: boolean;
  canManage: boolean;
  onToggle: () => void;
  onEdit: () => void;
  onDelete: () => void;
  onAddMember: () => void;
  onRemoveMember: (userId: number) => void;
  onToggleRole: (userId: number, currentRole: string) => void;
}) {
  return (
    <Card className={`overflow-hidden transition-shadow ${
      !team.is_active ? 'opacity-60' : ''
    }`}>
      {/* Header Row */}
      <button
        onClick={onToggle}
        className="w-full flex items-center justify-between px-4 py-3 text-left hover:bg-gray-50 dark:hover:bg-gray-800/50 transition-colors"
      >
        <div className="flex items-center gap-3 min-w-0">
          {expanded
            ? <ChevronDown size={16} className="text-gray-400 flex-shrink-0" />
            : <ChevronRight size={16} className="text-gray-400 flex-shrink-0" />
          }
          <div className="min-w-0">
            <div className="flex items-center gap-2">
              <p className="text-sm font-semibold text-gray-900 dark:text-gray-100 truncate">
                {team.name}
              </p>
              {!team.is_active && <Badge variant="neutral">Inactive</Badge>}
            </div>
            <p className="text-xs text-gray-500 dark:text-gray-400">
              {team.member_count} member{team.member_count !== 1 ? 's' : ''}
              {team.lead_name && (
                <> &middot; Lead: <span className="font-medium">{team.lead_name}</span></>
              )}
              {team.description && (
                <> &middot; {team.description}</>
              )}
            </p>
          </div>
        </div>

        {/* Action buttons */}
        {canManage && (
          <div className="flex items-center gap-1 flex-shrink-0 ml-2" onClick={e => e.stopPropagation()}>
            <button
              onClick={onEdit}
              className="p-1.5 text-gray-400 hover:text-blue-500 dark:hover:text-blue-400 rounded transition-colors"
              title="Edit team"
            >
              <Pencil size={14} />
            </button>
            <button
              onClick={onDelete}
              className="p-1.5 text-gray-400 hover:text-red-500 dark:hover:text-red-400 rounded transition-colors"
              title="Delete team"
            >
              <Trash2 size={14} />
            </button>
          </div>
        )}
      </button>

      {/* Expanded Members */}
      {expanded && (
        <div className="border-t border-gray-200 dark:border-gray-700">
          {canManage && (
            <div className="px-4 py-2 bg-gray-50 dark:bg-gray-800/30 flex items-center justify-between">
              <span className="text-xs font-medium text-gray-500 dark:text-gray-400">Members</span>
              <Button size="sm" variant="ghost" onClick={onAddMember}>
                <UserPlus size={14} />
                <span className="text-xs">Add Member</span>
              </Button>
            </div>
          )}

          {detail?.members && detail.members.length > 0 ? (
            <div className="divide-y divide-gray-100 dark:divide-gray-700/50">
              {detail.members.map((member) => (
                <MemberRow
                  key={member.user_id}
                  member={member}
                  canManage={canManage}
                  onRemove={() => onRemoveMember(member.user_id)}
                  onToggleRole={() => onToggleRole(member.user_id, member.role)}
                />
              ))}
            </div>
          ) : (
            <p className="px-4 py-4 text-sm text-gray-400 dark:text-gray-500 text-center">
              No members yet. Add employees to this team.
            </p>
          )}
        </div>
      )}
    </Card>
  );
}


/* ─── Member Row ──────────────────────────────────────────────────── */

function MemberRow({
  member,
  canManage,
  onRemove,
  onToggleRole,
}: {
  member: TeamMemberItem;
  canManage: boolean;
  onRemove: () => void;
  onToggleRole: () => void;
}) {
  return (
    <div className="flex items-center justify-between px-4 py-2.5 hover:bg-gray-50/50 dark:hover:bg-gray-800/20">
      <div className="flex items-center gap-3 min-w-0">
        {/* Avatar */}
        <div className="w-8 h-8 rounded-full bg-gray-200 dark:bg-gray-700 flex items-center justify-center flex-shrink-0 overflow-hidden">
          {member.avatar_url ? (
            <img src={member.avatar_url} alt="" className="w-full h-full object-cover" />
          ) : (
            <span className="text-xs font-medium text-gray-500 dark:text-gray-400">
              {member.display_name.charAt(0).toUpperCase()}
            </span>
          )}
        </div>
        <div className="min-w-0">
          <p className={`text-sm font-medium truncate ${
            member.user_is_active
              ? 'text-gray-900 dark:text-gray-100'
              : 'text-gray-400 dark:text-gray-500 line-through'
          }`}>
            {member.display_name}
          </p>
          <div className="flex items-center gap-1.5">
            {member.role === 'lead' ? (
              <Badge variant="warning" className="text-[10px] px-1.5 py-0">
                <Crown size={10} className="mr-0.5" />
                Lead
              </Badge>
            ) : (
              <Badge variant="neutral" className="text-[10px] px-1.5 py-0">Member</Badge>
            )}
          </div>
        </div>
      </div>

      {canManage && (
        <div className="flex items-center gap-1 flex-shrink-0">
          <button
            onClick={onToggleRole}
            className="p-1.5 text-gray-400 hover:text-amber-500 rounded transition-colors"
            title={member.role === 'lead' ? 'Demote to Member' : 'Promote to Lead'}
          >
            <Crown size={14} />
          </button>
          <button
            onClick={onRemove}
            className="p-1.5 text-gray-400 hover:text-red-500 rounded transition-colors"
            title="Remove from team"
          >
            <UserMinus size={14} />
          </button>
        </div>
      )}
    </div>
  );
}


/* ─── Team Form Modal (Create / Edit) ─────────────────────────────── */

function TeamFormModal({
  title,
  initial,
  onClose,
  onSubmit,
  isLoading,
}: {
  title: string;
  initial?: EmployeeTeamListItem;
  onClose: () => void;
  onSubmit: (data: EmployeeTeamCreate) => void;
  isLoading: boolean;
}) {
  const [name, setName] = useState(initial?.name ?? '');
  const [description, setDescription] = useState(initial?.description ?? '');

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!name.trim()) return;
    onSubmit({
      name: name.trim(),
      description: description.trim() || null,
    });
  };

  return (
    <Modal isOpen onClose={onClose} title={title}>
      <form onSubmit={handleSubmit} className="space-y-4">
        <Input
          label="Team Name"
          value={name}
          onChange={e => setName(e.target.value)}
          required
          autoFocus
          placeholder="e.g., Crew A, Install Team"
        />
        <div>
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
            Description
          </label>
          <textarea
            value={description}
            onChange={e => setDescription(e.target.value)}
            placeholder="Optional description..."
            rows={2}
            className="w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 px-3 py-2 text-sm"
          />
        </div>
        <div className="flex justify-end gap-2 pt-2">
          <Button type="button" variant="ghost" onClick={onClose}>Cancel</Button>
          <Button type="submit" variant="primary" disabled={!name.trim() || isLoading}>
            {isLoading ? 'Saving...' : initial ? 'Save Changes' : 'Create Team'}
          </Button>
        </div>
      </form>
    </Modal>
  );
}


/* ─── Add Member Modal ────────────────────────────────────────────── */

function AddMemberModal({
  existingMembers,
  onClose,
  onAdd,
}: {
  teamId: number;
  existingMembers: TeamMemberItem[];
  onClose: () => void;
  onAdd: (userId: number, role: 'lead' | 'member') => void;
}) {
  const [search, setSearch] = useState('');
  const [selectedRole, setSelectedRole] = useState<'lead' | 'member'>('member');

  const { data: employees } = useQuery({
    queryKey: ['employees-for-team'],
    queryFn: () => getEmployees({ is_active: true, page_size: 500 }),
  });

  const existingIds = new Set(existingMembers.map(m => m.user_id));

  const filtered = useMemo(() => {
    if (!employees?.items) return [];
    const q = search.toLowerCase();
    return employees.items
      .filter(emp => !existingIds.has(emp.id))
      .filter(emp =>
        !q || emp.display_name.toLowerCase().includes(q) || emp.email?.toLowerCase().includes(q)
      );
  }, [employees, search, existingIds]);

  return (
    <Modal isOpen onClose={onClose} title="Add Team Member">
      <div className="space-y-3">
        {/* Search */}
        <div className="relative">
          <Search size={16} className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400" />
          <input
            type="text"
            value={search}
            onChange={e => setSearch(e.target.value)}
            placeholder="Search employees..."
            autoFocus
            className="w-full pl-9 pr-3 py-2 text-sm rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 placeholder-gray-400"
          />
        </div>

        {/* Role selector */}
        <div className="flex items-center gap-2 text-xs text-gray-600 dark:text-gray-400">
          <span>Add as:</span>
          <button
            onClick={() => setSelectedRole('member')}
            className={`px-2 py-1 rounded ${
              selectedRole === 'member'
                ? 'bg-blue-100 text-blue-700 dark:bg-blue-900 dark:text-blue-300'
                : 'bg-gray-100 dark:bg-gray-700'
            }`}
          >
            Member
          </button>
          <button
            onClick={() => setSelectedRole('lead')}
            className={`px-2 py-1 rounded ${
              selectedRole === 'lead'
                ? 'bg-amber-100 text-amber-700 dark:bg-amber-900 dark:text-amber-300'
                : 'bg-gray-100 dark:bg-gray-700'
            }`}
          >
            Lead
          </button>
        </div>

        {/* Employee list */}
        <div className="max-h-64 overflow-y-auto divide-y divide-gray-100 dark:divide-gray-700/50 border border-gray-200 dark:border-gray-700 rounded-lg">
          {filtered.length === 0 ? (
            <p className="px-4 py-6 text-sm text-gray-400 text-center">
              {search ? 'No matching employees found.' : 'All employees are already on this team.'}
            </p>
          ) : (
            filtered.map(emp => (
              <button
                key={emp.id}
                onClick={() => onAdd(emp.id, selectedRole)}
                className="w-full flex items-center gap-3 px-4 py-2.5 text-left hover:bg-blue-50 dark:hover:bg-blue-900/20 transition-colors"
              >
                <div className="w-8 h-8 rounded-full bg-gray-200 dark:bg-gray-700 flex items-center justify-center flex-shrink-0">
                  <span className="text-xs font-medium text-gray-500 dark:text-gray-400">
                    {emp.display_name.charAt(0).toUpperCase()}
                  </span>
                </div>
                <div className="min-w-0">
                  <p className="text-sm font-medium text-gray-900 dark:text-gray-100 truncate">
                    {emp.display_name}
                  </p>
                  {emp.email && (
                    <p className="text-xs text-gray-400 truncate">{emp.email}</p>
                  )}
                </div>
                <UserPlus size={14} className="ml-auto text-gray-300 dark:text-gray-600 flex-shrink-0" />
              </button>
            ))
          )}
        </div>

        <div className="flex justify-end pt-1">
          <Button variant="ghost" onClick={onClose}>
            <X size={14} />
            Close
          </Button>
        </div>
      </div>
    </Modal>
  );
}
