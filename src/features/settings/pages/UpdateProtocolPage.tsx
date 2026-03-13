import { useMemo, useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import {
  GitBranch, ShieldCheck, Rocket, RefreshCw, HardDriveDownload,
  Monitor, Smartphone, Apple, CheckCircle2,
  XCircle, Play, Eye, ChevronDown, ChevronUp, Database,
  RotateCcw, PlusCircle, Loader2, ArrowRight, Shield,
  ClipboardList,
} from 'lucide-react';
import { Card } from '../../../components/ui/Card';
import { Button } from '../../../components/ui/Button';
import { Badge } from '../../../components/ui/Badge';
import { EmptyState } from '../../../components/ui/EmptyState';
import {
  listUpdateVersions,
  registerUpdateVersion,
  publishUpdateVersion,
  listUpdateValidations,
  createValidation,
  updateValidation,
  listFleetTargets,
  updateFleetTarget,
  refreshFleetTarget,
  listDeviceUpdateStatuses,
  getPendingUpdates,
  listUpdateBackups,
  createBackupSnapshot,
  markBackupRestored,
  type UpdatePlatform,
  type UpdateVersionRecord,
  type ValidationRecord,
  type DeviceUpdateStatusRecord,
  type BackupSnapshotRecord,
} from '../../../api/updates';

// ── Constants ───────────────────────────────────────────────────

type ValidationStatus = 'pending' | 'running' | 'passed' | 'failed' | 'blocked';

const PLATFORMS: UpdatePlatform[] = ['windows', 'macos', 'ios', 'android'];

const PLATFORM_ICON: Record<UpdatePlatform, React.ReactNode> = {
  windows: <Monitor className="h-4 w-4" />,
  macos: <Apple className="h-4 w-4" />,
  ios: <Smartphone className="h-4 w-4" />,
  android: <Smartphone className="h-4 w-4" />,
};

const PLATFORM_LABELS: Record<UpdatePlatform, string> = {
  windows: 'Windows',
  macos: 'macOS',
  ios: 'iOS',
  android: 'Android',
};

const VALIDATION_STATUS_BADGE: Record<string, { variant: 'success' | 'warning' | 'danger' | 'default'; label: string }> = {
  pending:  { variant: 'default', label: 'Pending' },
  running:  { variant: 'warning', label: 'Running' },
  passed:   { variant: 'success', label: 'Passed' },
  failed:   { variant: 'danger',  label: 'Failed' },
  blocked:  { variant: 'danger',  label: 'Blocked' },
};

// ── Main Page ───────────────────────────────────────────────────

export function UpdateProtocolPage() {
  const queryClient = useQueryClient();

  // Registration form
  const [newVersion, setNewVersion] = useState('');
  const [newPrevious, setNewPrevious] = useState('');
  const [newCriticality, setNewCriticality] = useState<'normal' | 'critical' | 'optional'>('normal');

  // Validation form
  const [showValidationForm, setShowValidationForm] = useState(false);
  const [valVersion, setValVersion] = useState('');
  const [valPlatform, setValPlatform] = useState<UpdatePlatform>('windows');

  // Backup form
  const [showBackupForm, setShowBackupForm] = useState(false);
  const [backupVersionBefore, setBackupVersionBefore] = useState('');
  const [backupVersionTarget, setBackupVersionTarget] = useState('');
  const [backupPath, setBackupPath] = useState('');

  // Device detail
  const [expandedDevice, setExpandedDevice] = useState<string | null>(null);

  // Expanded version for validation detail
  const [expandedVersion, setExpandedVersion] = useState<string | null>(null);

  // ── Queries ─────────────────────────────────────────────────────

  const versionsQ = useQuery({
    queryKey: ['updates', 'versions'],
    queryFn: () => listUpdateVersions({ limit: 100 }),
  });

  const validationsQ = useQuery({
    queryKey: ['updates', 'validations'],
    queryFn: () => listUpdateValidations(),
  });

  const fleetQ = useQuery({
    queryKey: ['updates', 'fleet'],
    queryFn: listFleetTargets,
  });

  const devicesQ = useQuery({
    queryKey: ['updates', 'devices'],
    queryFn: () => listDeviceUpdateStatuses({ limit: 200 }),
  });

  const backupsQ = useQuery({
    queryKey: ['updates', 'backups'],
    queryFn: () => listUpdateBackups({ limit: 50 }),
  });

  // ── Mutations ───────────────────────────────────────────────────

  const registerMutation = useMutation({
    mutationFn: () => registerUpdateVersion({
      version: newVersion.trim(),
      previous_version: newPrevious.trim() || null,
      source: 'manual',
      criticality: newCriticality,
    }),
    onSuccess: () => {
      setNewVersion('');
      setNewPrevious('');
      setNewCriticality('normal');
      queryClient.invalidateQueries({ queryKey: ['updates', 'versions'] });
    },
  });

  const publishMutation = useMutation({
    mutationFn: (version: string) => publishUpdateVersion(version),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['updates', 'versions'] });
      queryClient.invalidateQueries({ queryKey: ['updates', 'fleet'] });
    },
  });

  const createValidationMutation = useMutation({
    mutationFn: () => createValidation({
      version: valVersion.trim(),
      platform: valPlatform,
    }),
    onSuccess: () => {
      setValVersion('');
      setShowValidationForm(false);
      queryClient.invalidateQueries({ queryKey: ['updates', 'validations'] });
    },
  });

  const updateValidationMutation = useMutation({
    mutationFn: (payload: Parameters<typeof updateValidation>[0]) => updateValidation(payload),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['updates', 'validations'] });
    },
  });

  const refreshFleetMutation = useMutation({
    mutationFn: (platform: UpdatePlatform) => refreshFleetTarget(platform),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['updates', 'fleet'] });
      queryClient.invalidateQueries({ queryKey: ['updates', 'devices'] });
    },
  });

  const setFleetTargetMutation = useMutation({
    mutationFn: ({ platform, target }: { platform: UpdatePlatform; target: string }) =>
      updateFleetTarget(platform, { current_target: target }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['updates', 'fleet'] });
      queryClient.invalidateQueries({ queryKey: ['updates', 'devices'] });
    },
  });

  const toggleAutoAdvanceMutation = useMutation({
    mutationFn: ({ platform, enabled }: { platform: UpdatePlatform; enabled: boolean }) =>
      updateFleetTarget(platform, { auto_advance: enabled }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['updates', 'fleet'] });
    },
  });

  const createBackupMutation = useMutation({
    mutationFn: () => createBackupSnapshot({
      version_before: backupVersionBefore.trim(),
      version_target: backupVersionTarget.trim(),
      backup_path: backupPath.trim(),
    }),
    onSuccess: () => {
      setBackupVersionBefore('');
      setBackupVersionTarget('');
      setBackupPath('');
      setShowBackupForm(false);
      queryClient.invalidateQueries({ queryKey: ['updates', 'backups'] });
    },
  });

  const restoreBackupMutation = useMutation({
    mutationFn: (snapshotId: number) => markBackupRestored(snapshotId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['updates', 'backups'] });
    },
  });

  // ── Derived data ────────────────────────────────────────────────

  /** Map: version → platform → ValidationRecord */
  const validationMap = useMemo(() => {
    const map = new Map<string, Map<UpdatePlatform, ValidationRecord>>();
    for (const v of validationsQ.data ?? []) {
      if (!map.has(v.version)) map.set(v.version, new Map());
      map.get(v.version)!.set(v.platform as UpdatePlatform, v);
    }
    return map;
  }, [validationsQ.data]);

  /** Check whether a version has all 4 platforms passing */
  function allPlatformsPassed(version: string): boolean {
    const platMap = validationMap.get(version);
    if (!platMap) return false;
    return PLATFORMS.every((p) => platMap.get(p)?.status === 'passed');
  }



  return (
    <div className="space-y-5">

      {/* ── Header ───────────────────────────────────────────────── */}
      <div>
        <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-100 flex items-center gap-2">
          <HardDriveDownload className="h-5 w-5 text-indigo-500" />
          Update Protocol
        </h2>
        <p className="text-sm text-gray-500 dark:text-gray-400 mt-0.5">
          Shop-centric update control center: version registry, per-platform validation,
          staged fleet rollout, device status tracking, and backup management.
        </p>
      </div>

      {/* ── Quick Register ───────────────────────────────────────── */}
      <Card>
        <div className="p-4 space-y-3">
          <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100 flex items-center gap-2">
            <GitBranch className="h-4 w-4 text-gray-500" />
            Register Version (Manual)
          </h3>
          <div className="flex flex-wrap gap-2 items-end">
            <label className="flex-1 min-w-[140px]">
              <span className="block text-xs text-gray-500 mb-1">Version</span>
              <input
                value={newVersion}
                onChange={(e) => setNewVersion(e.target.value)}
                placeholder="e.g. 1.4.0"
                className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm"
              />
            </label>
            <label className="flex-1 min-w-[140px]">
              <span className="block text-xs text-gray-500 mb-1">Previous Version</span>
              <input
                value={newPrevious}
                onChange={(e) => setNewPrevious(e.target.value)}
                placeholder="e.g. 1.3.0"
                className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm"
              />
            </label>
            <label className="min-w-[120px]">
              <span className="block text-xs text-gray-500 mb-1">Criticality</span>
              <select
                value={newCriticality}
                onChange={(e) => setNewCriticality(e.target.value as typeof newCriticality)}
                className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm"
              >
                <option value="normal">Normal</option>
                <option value="critical">Critical</option>
                <option value="optional">Optional</option>
              </select>
            </label>
            <Button
              onClick={() => registerMutation.mutate()}
              disabled={!newVersion.trim()}
              isLoading={registerMutation.isPending}
              icon={<GitBranch className="h-4 w-4" />}
            >
              Register
            </Button>
          </div>
        </div>
      </Card>

      {/* ── Version Registry + Fleet Targets (side by side on xl) ─ */}
      <div className="grid grid-cols-1 xl:grid-cols-2 gap-4">

        {/* Version Registry */}
        <Card>
          <div className="p-4 space-y-3">
            <div className="flex items-center justify-between flex-wrap gap-2">
              <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100 flex items-center gap-2">
                <Rocket className="h-4 w-4 text-gray-500" />
                Version Registry
              </h3>
              <Button
                size="sm"
                variant="secondary"
                icon={<RefreshCw className={`h-3.5 w-3.5 ${versionsQ.isFetching ? 'animate-spin' : ''}`} />}
                onClick={() => versionsQ.refetch()}
              >Refresh</Button>
            </div>

            {(versionsQ.data ?? []).length === 0 ? (
              <EmptyState
                icon={<Rocket className="h-10 w-10" />}
                title="No versions"
                description="Register or fetch update versions to begin rollout."
              />
            ) : (
              <div className="space-y-2 max-h-[520px] overflow-y-auto pr-1">
                {(versionsQ.data ?? []).map((v) => (
                  <VersionRow
                    key={v.version}
                    version={v}
                    validationMap={validationMap.get(v.version)}
                    allPassed={allPlatformsPassed(v.version)}
                    isExpanded={expandedVersion === v.version}
                    onToggleExpand={() => setExpandedVersion(
                      expandedVersion === v.version ? null : v.version
                    )}
                    onPublish={() => publishMutation.mutate(v.version)}
                    isPublishing={publishMutation.isPending}
                    onRunValidation={(platform, status, flags) =>
                      updateValidationMutation.mutate({
                        version: v.version,
                        platform,
                        status,
                        ...(flags ?? {}),
                      })
                    }
                    onCreateValidation={(platform) => {
                      createValidation({ version: v.version, platform }).then(() => {
                        queryClient.invalidateQueries({ queryKey: ['updates', 'validations'] });
                      });
                    }}
                    isUpdatingValidation={updateValidationMutation.isPending}
                  />
                ))}
              </div>
            )}
          </div>
        </Card>

        {/* Fleet Targets */}
        <Card>
          <div className="p-4 space-y-3">
            <div className="flex items-center justify-between flex-wrap gap-2">
              <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100 flex items-center gap-2">
                <ShieldCheck className="h-4 w-4 text-gray-500" />
                Fleet Targets (Per-Platform)
              </h3>
              <Button
                size="sm"
                variant="secondary"
                icon={<RefreshCw className={`h-3.5 w-3.5 ${fleetQ.isFetching ? 'animate-spin' : ''}`} />}
                onClick={() => fleetQ.refetch()}
              >Refresh</Button>
            </div>

            {(fleetQ.data ?? []).length === 0 ? (
              <EmptyState
                icon={<ShieldCheck className="h-10 w-10" />}
                title="No fleet targets"
                description="Set per-platform targets after validation passes."
              />
            ) : (
              <div className="space-y-2">
                {(fleetQ.data ?? []).map((f) => (
                  <FleetTargetRow
                    key={f.platform}
                    target={f}
                    onSetTarget={(target) =>
                      setFleetTargetMutation.mutate({ platform: f.platform as UpdatePlatform, target })
                    }
                    onRefresh={() => refreshFleetMutation.mutate(f.platform as UpdatePlatform)}
                    onToggleAutoAdvance={(enabled) =>
                      toggleAutoAdvanceMutation.mutate({ platform: f.platform as UpdatePlatform, enabled })
                    }
                    isRefreshing={refreshFleetMutation.isPending}
                  />
                ))}
              </div>
            )}
          </div>
        </Card>
      </div>

      {/* ── Validation Management ────────────────────────────────── */}
      <Card>
        <div className="p-4 space-y-3">
          <div className="flex items-center justify-between flex-wrap gap-2">
            <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100 flex items-center gap-2">
              <ClipboardList className="h-4 w-4 text-gray-500" />
              Validation Pipeline
            </h3>
            <Button
              size="sm"
              variant="secondary"
              icon={<PlusCircle className="h-3.5 w-3.5" />}
              onClick={() => setShowValidationForm(!showValidationForm)}
            >
              {showValidationForm ? 'Cancel' : 'New Validation'}
            </Button>
          </div>

          {showValidationForm && (
            <div className="rounded-lg border border-border bg-gray-50 dark:bg-gray-800/50 p-3">
              <div className="flex flex-wrap gap-2 items-end">
                <label className="flex-1 min-w-[140px]">
                  <span className="block text-xs text-gray-500 mb-1">Version</span>
                  <input
                    value={valVersion}
                    onChange={(e) => setValVersion(e.target.value)}
                    placeholder="e.g. 1.4.0"
                    className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm"
                  />
                </label>
                <label className="min-w-[120px]">
                  <span className="block text-xs text-gray-500 mb-1">Platform</span>
                  <select
                    value={valPlatform}
                    onChange={(e) => setValPlatform(e.target.value as UpdatePlatform)}
                    className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm"
                  >
                    {PLATFORMS.map((p) => (
                      <option key={p} value={p}>{PLATFORM_LABELS[p]}</option>
                    ))}
                  </select>
                </label>
                <Button
                  onClick={() => createValidationMutation.mutate()}
                  disabled={!valVersion.trim()}
                  isLoading={createValidationMutation.isPending}
                  icon={<PlusCircle className="h-4 w-4" />}
                >Create</Button>
              </div>
            </div>
          )}

          {(validationsQ.data ?? []).length === 0 ? (
            <p className="text-sm text-gray-500">
              No validations yet. Create one per-platform before publishing.
            </p>
          ) : (
            <div className="space-y-1.5 max-h-[380px] overflow-y-auto pr-1">
              {(validationsQ.data ?? []).map((v) => (
                <ValidationRow
                  key={`${v.version}-${v.platform}`}
                  validation={v}
                  onUpdate={(status, flags) =>
                    updateValidationMutation.mutate({
                      version: v.version,
                      platform: v.platform,
                      status,
                      ...flags,
                    })
                  }
                  isUpdating={updateValidationMutation.isPending}
                />
              ))}
            </div>
          )}
        </div>
      </Card>

      {/* ── Device Status + Backups (side by side on xl) ─────────── */}
      <div className="grid grid-cols-1 xl:grid-cols-2 gap-4">

        {/* Device Update Status */}
        <Card>
          <div className="p-4 space-y-3">
            <div className="flex items-center justify-between flex-wrap gap-2">
              <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100 flex items-center gap-2">
                <Smartphone className="h-4 w-4 text-gray-500" />
                Device Update Status
              </h3>
              <Button
                size="sm"
                variant="secondary"
                icon={<RefreshCw className={`h-3.5 w-3.5 ${devicesQ.isFetching ? 'animate-spin' : ''}`} />}
                onClick={() => devicesQ.refetch()}
              >Refresh</Button>
            </div>

            <div className="max-h-[420px] overflow-y-auto pr-1 space-y-1.5">
              {(devicesQ.data ?? []).length === 0 ? (
                <p className="text-sm text-gray-500">No device reports yet.</p>
              ) : (devicesQ.data ?? []).map((d) => (
                <DeviceStatusRow
                  key={d.device_id}
                  device={d}
                  isExpanded={expandedDevice === d.device_id}
                  onToggle={() => setExpandedDevice(
                    expandedDevice === d.device_id ? null : d.device_id
                  )}
                />
              ))}
            </div>
          </div>
        </Card>

        {/* Backup Snapshots */}
        <Card>
          <div className="p-4 space-y-3">
            <div className="flex items-center justify-between flex-wrap gap-2">
              <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100 flex items-center gap-2">
                <Database className="h-4 w-4 text-gray-500" />
                Backup Snapshots
              </h3>
              <Button
                size="sm"
                variant="secondary"
                icon={<PlusCircle className="h-3.5 w-3.5" />}
                onClick={() => setShowBackupForm(!showBackupForm)}
              >
                {showBackupForm ? 'Cancel' : 'New Backup'}
              </Button>
            </div>

            {showBackupForm && (
              <div className="rounded-lg border border-border bg-gray-50 dark:bg-gray-800/50 p-3 space-y-2">
                <div className="flex flex-wrap gap-2 items-end">
                  <label className="flex-1 min-w-[120px]">
                    <span className="block text-xs text-gray-500 mb-1">Version Before</span>
                    <input
                      value={backupVersionBefore}
                      onChange={(e) => setBackupVersionBefore(e.target.value)}
                      placeholder="e.g. 1.3.0"
                      className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm"
                    />
                  </label>
                  <label className="flex-1 min-w-[120px]">
                    <span className="block text-xs text-gray-500 mb-1">Target Version</span>
                    <input
                      value={backupVersionTarget}
                      onChange={(e) => setBackupVersionTarget(e.target.value)}
                      placeholder="e.g. 1.4.0"
                      className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm"
                    />
                  </label>
                </div>
                <div className="flex flex-wrap gap-2 items-end">
                  <label className="flex-1 min-w-[200px]">
                    <span className="block text-xs text-gray-500 mb-1">Backup Path</span>
                    <input
                      value={backupPath}
                      onChange={(e) => setBackupPath(e.target.value)}
                      placeholder="/backups/pre-1.4.0.tar.gz"
                      className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm"
                    />
                  </label>
                  <Button
                    onClick={() => createBackupMutation.mutate()}
                    disabled={!backupVersionBefore.trim() || !backupVersionTarget.trim() || !backupPath.trim()}
                    isLoading={createBackupMutation.isPending}
                    icon={<Database className="h-4 w-4" />}
                  >Create Backup</Button>
                </div>
              </div>
            )}

            <div className="max-h-[380px] overflow-y-auto pr-1 space-y-1.5">
              {(backupsQ.data ?? []).length === 0 ? (
                <p className="text-sm text-gray-500">No backup snapshots recorded.</p>
              ) : (backupsQ.data ?? []).map((b) => (
                <BackupRow
                  key={b.id}
                  backup={b}
                  onRestore={() => restoreBackupMutation.mutate(b.id)}
                  isRestoring={restoreBackupMutation.isPending}
                />
              ))}
            </div>
          </div>
        </Card>
      </div>

      {/* ── Safety Info ──────────────────────────────────────────── */}
      <Card>
        <div className="p-4 space-y-3">
          <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100 flex items-center gap-2">
            <Shield className="h-4 w-4 text-amber-500" />
            Update Safety Protocol
          </h3>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 text-xs text-gray-700 dark:text-gray-300">
            <div className="flex items-start gap-2">
              <CheckCircle2 className="h-3.5 w-3.5 mt-0.5 text-green-500 flex-shrink-0" />
              <span>Versions must pass <strong>all 4 platforms</strong> before publishing.</span>
            </div>
            <div className="flex items-start gap-2">
              <CheckCircle2 className="h-3.5 w-3.5 mt-0.5 text-green-500 flex-shrink-0" />
              <span>Fleet targets advance <strong>one version at a time</strong> per platform.</span>
            </div>
            <div className="flex items-start gap-2">
              <CheckCircle2 className="h-3.5 w-3.5 mt-0.5 text-green-500 flex-shrink-0" />
              <span>Devices install updates in <strong>strict version chain order</strong>.</span>
            </div>
            <div className="flex items-start gap-2">
              <CheckCircle2 className="h-3.5 w-3.5 mt-0.5 text-green-500 flex-shrink-0" />
              <span>Backup is required before any update. Rollback restores the exact state.</span>
            </div>
            <div className="flex items-start gap-2">
              <CheckCircle2 className="h-3.5 w-3.5 mt-0.5 text-green-500 flex-shrink-0" />
              <span>Broken platforms can be <strong>blocked</strong> without affecting other platforms.</span>
            </div>
            <div className="flex items-start gap-2">
              <CheckCircle2 className="h-3.5 w-3.5 mt-0.5 text-green-500 flex-shrink-0" />
              <span>Auto-advance only triggers when <strong>all devices</strong> on a platform reach target.</span>
            </div>
          </div>
        </div>
      </Card>
    </div>
  );
}


// ═══════════════════════════════════════════════════════════════════
// Sub-components
// ═══════════════════════════════════════════════════════════════════


// ── VersionRow ──────────────────────────────────────────────────

function VersionRow({
  version,
  validationMap,
  allPassed,
  isExpanded,
  onToggleExpand,
  onPublish,
  isPublishing,
  onRunValidation,
  onCreateValidation,
  isUpdatingValidation,
}: {
  version: UpdateVersionRecord;
  validationMap: Map<UpdatePlatform, ValidationRecord> | undefined;
  allPassed: boolean;
  isExpanded: boolean;
  onToggleExpand: () => void;
  onPublish: () => void;
  isPublishing: boolean;
  onRunValidation: (platform: UpdatePlatform, status: ValidationStatus, flags?: Record<string, boolean>) => void;
  onCreateValidation: (platform: UpdatePlatform) => void;
  isUpdatingValidation: boolean;
}) {
  const canPublish = !version.published_at && allPassed;
  const cantPublishReason = !version.published_at && !allPassed
    ? 'All 4 platforms must pass validation before publishing'
    : null;

  return (
    <div className="rounded-lg border border-border p-3 space-y-2">
      <div className="flex items-center justify-between gap-2 flex-wrap">
        <div className="flex items-center gap-2">
          <span className="text-sm font-semibold text-gray-900 dark:text-gray-100">
            {version.version}
          </span>
          {version.criticality === 'critical' && (
            <Badge variant="danger">Critical</Badge>
          )}
          {version.published_at ? (
            <Badge variant="success" className="flex items-center gap-1">
              <CheckCircle2 className="h-3 w-3" /> Published
            </Badge>
          ) : (
            <Badge variant="default">Draft</Badge>
          )}
        </div>
        <div className="flex items-center gap-1.5">
          {!version.published_at && (
            <div className="relative group">
              <Button
                size="sm"
                variant="secondary"
                isLoading={isPublishing}
                onClick={onPublish}
                disabled={!canPublish}
              >
                <Rocket className="h-3.5 w-3.5 mr-1" />
                Publish
              </Button>
              {cantPublishReason && (
                <div className="absolute bottom-full left-1/2 -translate-x-1/2 mb-1 px-2 py-1 text-xs bg-gray-900 text-white rounded shadow-lg whitespace-nowrap opacity-0 group-hover:opacity-100 transition-opacity pointer-events-none z-10">
                  {cantPublishReason}
                </div>
              )}
            </div>
          )}
          <button
            onClick={onToggleExpand}
            className="p-1 rounded hover:bg-gray-100 dark:hover:bg-gray-700"
          >
            {isExpanded
              ? <ChevronUp className="h-4 w-4 text-gray-400" />
              : <ChevronDown className="h-4 w-4 text-gray-400" />
            }
          </button>
        </div>
      </div>

      <div className="text-xs text-gray-600 dark:text-gray-400">
        prev: <strong>{version.previous_version ?? '(initial)'}</strong>
        {' · '}criticality: <strong>{version.criticality}</strong>
        {' · '}source: <strong>{version.source}</strong>
        {version.release_notes && (
          <span className="block mt-1 text-gray-500 italic">{version.release_notes}</span>
        )}
      </div>

      {/* Per-platform validation badges */}
      <div className="flex items-center gap-1.5 flex-wrap">
        {PLATFORMS.map((p) => {
          const val = validationMap?.get(p);
          const badgeInfo = val
            ? VALIDATION_STATUS_BADGE[val.status] ?? { variant: 'default' as const, label: val.status }
            : { variant: 'default' as const, label: 'No test' };
          return (
            <Badge key={p} variant={badgeInfo.variant}>
              {PLATFORM_LABELS[p]}: {badgeInfo.label}
            </Badge>
          );
        })}
      </div>

      {/* Expanded: per-platform validation controls */}
      {isExpanded && (
        <div className="border-t border-border pt-2 mt-2 space-y-2">
          <p className="text-xs font-medium text-gray-700 dark:text-gray-300">
            Per-Platform Validation Controls
          </p>
          {PLATFORMS.map((p) => {
            const val = validationMap?.get(p);
            return (
              <div key={p} className="flex items-center justify-between gap-2 flex-wrap rounded-md bg-gray-50 dark:bg-gray-800/50 p-2">
                <div className="flex items-center gap-2 text-xs">
                  {PLATFORM_ICON[p]}
                  <span className="font-medium">{PLATFORM_LABELS[p]}</span>
                  {val && (
                    <Badge variant={VALIDATION_STATUS_BADGE[val.status]?.variant ?? 'default'}>
                      {val.status}
                    </Badge>
                  )}
                </div>
                <div className="flex items-center gap-1">
                  {!val ? (
                    <Button
                      size="sm"
                      variant="secondary"
                      onClick={() => onCreateValidation(p)}
                    >
                      <PlusCircle className="h-3 w-3 mr-1" />
                      Init
                    </Button>
                  ) : val.status === 'pending' || val.status === 'failed' ? (
                    <>
                      <Button
                        size="sm"
                        variant="secondary"
                        isLoading={isUpdatingValidation}
                        onClick={() => onRunValidation(p, 'running')}
                      >
                        <Play className="h-3 w-3 mr-1" />
                        Start
                      </Button>
                    </>
                  ) : val.status === 'running' ? (
                    <>
                      <Button
                        size="sm"
                        variant="secondary"
                        isLoading={isUpdatingValidation}
                        onClick={() => onRunValidation(p, 'passed', {
                          schema_diff_ok: true,
                          migration_test_ok: true,
                          rollback_test_ok: true,
                          backward_compat_ok: true,
                        })}
                      >
                        <CheckCircle2 className="h-3 w-3 mr-1" />
                        Pass All
                      </Button>
                      <Button
                        size="sm"
                        variant="danger"
                        isLoading={isUpdatingValidation}
                        onClick={() => onRunValidation(p, 'failed')}
                      >
                        <XCircle className="h-3 w-3 mr-1" />
                        Fail
                      </Button>
                      <Button
                        size="sm"
                        variant="danger"
                        isLoading={isUpdatingValidation}
                        onClick={() => onRunValidation(p, 'blocked')}
                      >
                        Block
                      </Button>
                    </>
                  ) : val.status === 'passed' ? (
                    <span className="text-xs text-green-600 dark:text-green-400 flex items-center gap-1">
                      <CheckCircle2 className="h-3 w-3" /> All checks passed
                    </span>
                  ) : /* blocked */ (
                    <Button
                      size="sm"
                      variant="secondary"
                      isLoading={isUpdatingValidation}
                      onClick={() => onRunValidation(p, 'pending')}
                    >
                      Reset to Pending
                    </Button>
                  )}
                </div>
              </div>
            );
          })}
          {/* Validation detail flags */}
          {validationMap && Array.from(validationMap.entries()).some(([, v]) => v.status !== 'pending') && (
            <div className="text-xs text-gray-500 dark:text-gray-400 mt-1 space-y-1">
              {Array.from(validationMap.entries()).map(([platform, v]) => {
                if (v.status === 'pending') return null;
                return (
                  <div key={platform} className="flex items-center gap-3 flex-wrap">
                    <span className="font-medium w-16">{PLATFORM_LABELS[platform as UpdatePlatform]}</span>
                    <FlagPill label="Schema" ok={v.schema_diff_ok} />
                    <FlagPill label="Migration" ok={v.migration_test_ok} />
                    <FlagPill label="Rollback" ok={v.rollback_test_ok} />
                    <FlagPill label="Compat" ok={v.backward_compat_ok} />
                    {v.error_log && (
                      <span className="text-red-500 truncate max-w-[200px]" title={v.error_log}>
                        {v.error_log}
                      </span>
                    )}
                  </div>
                );
              })}
            </div>
          )}
        </div>
      )}
    </div>
  );
}


// ── FlagPill ────────────────────────────────────────────────────

function FlagPill({ label, ok }: { label: string; ok: number | null }) {
  if (ok === null || ok === undefined) {
    return (
      <span className="inline-flex items-center gap-0.5 text-gray-400">
        <span className="h-1.5 w-1.5 rounded-full bg-gray-300 dark:bg-gray-600" />
        {label}
      </span>
    );
  }
  return ok ? (
    <span className="inline-flex items-center gap-0.5 text-green-600 dark:text-green-400">
      <CheckCircle2 className="h-3 w-3" />
      {label}
    </span>
  ) : (
    <span className="inline-flex items-center gap-0.5 text-red-500 dark:text-red-400">
      <XCircle className="h-3 w-3" />
      {label}
    </span>
  );
}


// ── FleetTargetRow ──────────────────────────────────────────────

function FleetTargetRow({
  target,
  onSetTarget,
  onRefresh,
  onToggleAutoAdvance,
  isRefreshing,
}: {
  target: {
    platform: string;
    current_target: string;
    latest_validated: string | null;
    devices_at_target: number;
    devices_total: number;
    devices_behind: number;
    auto_advance: number;
  };
  onSetTarget: (target: string) => void;
  onRefresh: () => void;
  onToggleAutoAdvance: (enabled: boolean) => void;
  isRefreshing: boolean;
}) {
  const platform = target.platform as UpdatePlatform;
  const allCaughtUp = target.devices_behind === 0 && target.devices_total > 0;
  const progressPct = target.devices_total > 0
    ? Math.round((target.devices_at_target / target.devices_total) * 100)
    : 0;

  return (
    <div className="rounded-lg border border-border p-3 space-y-2">
      <div className="flex items-center justify-between gap-2 flex-wrap">
        <div className="flex items-center gap-2 text-sm font-medium text-gray-900 dark:text-gray-100">
          {PLATFORM_ICON[platform]}
          <span>{PLATFORM_LABELS[platform]}</span>
        </div>
        <Badge variant={allCaughtUp ? 'success' : target.devices_behind > 0 ? 'warning' : 'default'}>
          {allCaughtUp ? 'All at target' : target.devices_behind > 0 ? `${target.devices_behind} behind` : 'No devices'}
        </Badge>
      </div>

      {/* Progress bar */}
      {target.devices_total > 0 && (
        <div className="w-full bg-gray-200 dark:bg-gray-700 rounded-full h-1.5">
          <div
            className={`h-1.5 rounded-full transition-all ${allCaughtUp ? 'bg-green-500' : 'bg-amber-500'}`}
            style={{ width: `${progressPct}%` }}
          />
        </div>
      )}

      <div className="text-xs text-gray-600 dark:text-gray-400">
        Target: <strong>{target.current_target}</strong>
        {' · '}Latest Validated: <strong>{target.latest_validated ?? '—'}</strong>
        {' · '}Devices: <strong>{target.devices_at_target}/{target.devices_total}</strong>
      </div>

      <div className="flex flex-wrap gap-2 items-center">
        <input
          defaultValue={target.current_target}
          onBlur={(e) => {
            const val = e.target.value.trim();
            if (val && val !== target.current_target) onSetTarget(val);
          }}
          className="rounded-lg border border-border bg-surface px-2 py-1.5 text-xs w-36"
          placeholder="Set target version"
        />
        <Button
          size="sm"
          variant="secondary"
          isLoading={isRefreshing}
          onClick={onRefresh}
          icon={<RefreshCw className="h-3 w-3" />}
        >Refresh</Button>
        <label className="flex items-center gap-1.5 text-xs text-gray-600 dark:text-gray-400 cursor-pointer">
          <input
            type="checkbox"
            checked={!!target.auto_advance}
            onChange={(e) => onToggleAutoAdvance(e.target.checked)}
            className="rounded border-gray-300"
          />
          Auto-advance
        </label>
      </div>
    </div>
  );
}


// ── ValidationRow ───────────────────────────────────────────────

function ValidationRow({
  validation,
  onUpdate,
  isUpdating,
}: {
  validation: ValidationRecord;
  onUpdate: (status: ValidationStatus, flags?: Record<string, boolean | null>) => void;
  isUpdating: boolean;
}) {
  const badgeInfo = VALIDATION_STATUS_BADGE[validation.status] ?? { variant: 'default' as const, label: validation.status };
  const platform = validation.platform as UpdatePlatform;

  return (
    <div className="rounded-lg border border-border p-2 text-xs">
      <div className="flex items-center justify-between gap-2 flex-wrap">
        <div className="flex items-center gap-2">
          {PLATFORM_ICON[platform]}
          <span className="font-medium text-gray-900 dark:text-gray-100">
            {validation.version}
          </span>
          <span className="text-gray-500">({PLATFORM_LABELS[platform]})</span>
          <Badge variant={badgeInfo.variant}>{badgeInfo.label}</Badge>
        </div>
        <div className="flex items-center gap-1">
          {(validation.status === 'pending' || validation.status === 'failed') && (
            <Button size="sm" variant="secondary" isLoading={isUpdating}
              onClick={() => onUpdate('running')}>
              <Play className="h-3 w-3 mr-1" /> Start
            </Button>
          )}
          {validation.status === 'running' && (
            <>
              <Button size="sm" variant="secondary" isLoading={isUpdating}
                onClick={() => onUpdate('passed', {
                  schema_diff_ok: true, migration_test_ok: true,
                  rollback_test_ok: true, backward_compat_ok: true,
                })}>
                <CheckCircle2 className="h-3 w-3 mr-1" /> Pass
              </Button>
              <Button size="sm" variant="danger" isLoading={isUpdating}
                onClick={() => onUpdate('failed')}>
                <XCircle className="h-3 w-3 mr-1" /> Fail
              </Button>
            </>
          )}
          {validation.status === 'blocked' && (
            <Button size="sm" variant="secondary" isLoading={isUpdating}
              onClick={() => onUpdate('pending')}>Reset</Button>
          )}
        </div>
      </div>
      <div className="flex items-center gap-3 mt-1 flex-wrap">
        <FlagPill label="Schema" ok={validation.schema_diff_ok} />
        <FlagPill label="Migration" ok={validation.migration_test_ok} />
        <FlagPill label="Rollback" ok={validation.rollback_test_ok} />
        <FlagPill label="Compat" ok={validation.backward_compat_ok} />
        {validation.error_log && (
          <span className="text-red-500 truncate max-w-[300px]" title={validation.error_log}>
            {validation.error_log}
          </span>
        )}
      </div>
    </div>
  );
}


// ── DeviceStatusRow ─────────────────────────────────────────────

function DeviceStatusRow({
  device,
  isExpanded,
  onToggle,
}: {
  device: DeviceUpdateStatusRecord;
  isExpanded: boolean;
  onToggle: () => void;
}) {
  const atTarget = device.current_version === device.target_version;
  const hasFailed = device.last_install_status === 'failed' || device.last_install_status === 'rolled_back';

  return (
    <div className="rounded-lg border border-border p-2 text-xs">
      <div className="flex items-center justify-between gap-2 cursor-pointer" onClick={onToggle}>
        <div className="flex items-center gap-2 min-w-0">
          {PLATFORM_ICON[device.platform]}
          <span className="font-mono text-gray-900 dark:text-gray-100 truncate">
            {device.device_id.slice(0, 12)}…
          </span>
          <span className="text-gray-500">{PLATFORM_LABELS[device.platform]}</span>
        </div>
        <div className="flex items-center gap-1.5">
          {hasFailed && <Badge variant="danger">{device.last_install_status}</Badge>}
          <Badge variant={atTarget ? 'success' : 'warning'}>
            {atTarget ? 'Current' : 'Behind'}
          </Badge>
          {isExpanded
            ? <ChevronUp className="h-3.5 w-3.5 text-gray-400" />
            : <ChevronDown className="h-3.5 w-3.5 text-gray-400" />}
        </div>
      </div>

      <div className="text-gray-600 dark:text-gray-400 mt-1 flex items-center gap-1">
        <span className="font-medium">{device.current_version}</span>
        <ArrowRight className="h-3 w-3" />
        <span className="font-medium">{device.target_version ?? '—'}</span>
        {device.pending_versions.length > 0 && (
          <span className="ml-1 text-amber-600">
            ({device.pending_versions.length} pending)
          </span>
        )}
      </div>

      {isExpanded && (
        <DeviceDetailExpanded device={device} />
      )}
    </div>
  );
}


// ── DeviceDetailExpanded (with pending chain) ───────────────────

function DeviceDetailExpanded({ device }: { device: DeviceUpdateStatusRecord }) {
  const { data: pending, isLoading } = useQuery({
    queryKey: ['updates', 'pending', device.device_id],
    queryFn: () => getPendingUpdates(device.device_id, device.platform),
    staleTime: 30_000,
  });

  return (
    <div className="border-t border-border pt-2 mt-2 space-y-2">
      <div className="grid grid-cols-2 gap-x-4 gap-y-1 text-xs text-gray-600 dark:text-gray-400">
        <div>Device ID: <span className="font-mono text-gray-900 dark:text-gray-100">{device.device_id}</span></div>
        <div>Platform: <span className="text-gray-900 dark:text-gray-100">{PLATFORM_LABELS[device.platform]}</span></div>
        <div>Current: <span className="font-medium text-gray-900 dark:text-gray-100">{device.current_version}</span></div>
        <div>Target: <span className="font-medium text-gray-900 dark:text-gray-100">{device.target_version ?? '—'}</span></div>
        {device.last_install_version && (
          <div>Last Install: <span className="text-gray-900 dark:text-gray-100">{device.last_install_version}</span></div>
        )}
        {device.last_install_at && (
          <div>Install Time: <span className="text-gray-900 dark:text-gray-100">{new Date(device.last_install_at).toLocaleString()}</span></div>
        )}
        {device.install_error && (
          <div className="col-span-2 text-red-500">Error: {device.install_error}</div>
        )}
        <div>Backup Taken: {device.backup_taken ? '✅ Yes' : '❌ No'}</div>
        <div>Reported: {new Date(device.reported_at).toLocaleString()}</div>
      </div>

      {/* Pending update chain */}
      <div className="mt-1">
        <p className="text-xs font-medium text-gray-700 dark:text-gray-300 flex items-center gap-1">
          <Eye className="h-3 w-3" />
          Pending Update Chain
        </p>
        {isLoading ? (
          <div className="flex items-center gap-1 text-xs text-gray-500 py-1">
            <Loader2 className="h-3 w-3 animate-spin" /> Loading chain…
          </div>
        ) : !pending || pending.length === 0 ? (
          <p className="text-xs text-gray-500 py-1">
            No pending updates — device is at target version.
          </p>
        ) : (
          <div className="flex flex-wrap items-center gap-1 mt-1">
            <span className="text-xs font-mono text-gray-500">{device.current_version}</span>
            {pending.map((u) => (
              <span key={u.version} className="flex items-center gap-1">
                <ArrowRight className="h-3 w-3 text-gray-400" />
                <span className={`text-xs font-mono px-1.5 py-0.5 rounded ${
                  u.criticality === 'critical'
                    ? 'bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-300'
                    : 'bg-gray-100 text-gray-700 dark:bg-gray-800 dark:text-gray-300'
                }`}>
                  {u.version}
                </span>
              </span>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}


// ── BackupRow ───────────────────────────────────────────────────

function BackupRow({
  backup,
  onRestore,
  isRestoring,
}: {
  backup: BackupSnapshotRecord;
  onRestore: () => void;
  isRestoring: boolean;
}) {
  const isRestorable = backup.status === 'created' || backup.status === 'verified';

  return (
    <div className="rounded-lg border border-border p-2 text-xs">
      <div className="flex items-center justify-between gap-2 flex-wrap">
        <div className="flex items-center gap-2">
          <Database className="h-3.5 w-3.5 text-gray-500" />
          <span className="font-medium text-gray-900 dark:text-gray-100">
            {backup.version_before} → {backup.version_target}
          </span>
          <Badge variant={
            backup.status === 'restored' ? 'warning'
            : backup.status === 'expired' ? 'danger'
            : backup.status === 'verified' ? 'success'
            : 'default'
          }>
            {backup.status}
          </Badge>
        </div>
        {isRestorable && (
          <Button
            size="sm"
            variant="danger"
            isLoading={isRestoring}
            onClick={onRestore}
            icon={<RotateCcw className="h-3 w-3" />}
          >Restore</Button>
        )}
      </div>
      <div className="text-gray-600 dark:text-gray-400 mt-1 break-all">
        {backup.backup_path}
        {backup.backup_size_bytes && (
          <span className="ml-2">({(backup.backup_size_bytes / 1024 / 1024).toFixed(1)} MB)</span>
        )}
      </div>
      <div className="flex items-center gap-2 mt-1 text-gray-500">
        {backup.includes_db ? '✅ DB' : '❌ DB'}
        {backup.includes_config ? ' · ✅ Config' : ' · ❌ Config'}
        {backup.includes_binary ? ' · ✅ Binary' : ' · ❌ Binary'}
        {backup.checksum_sha256 && (
          <span className="font-mono text-[10px] truncate max-w-[120px]" title={backup.checksum_sha256}>
            sha256:{backup.checksum_sha256.slice(0, 12)}…
          </span>
        )}
      </div>
    </div>
  );
}
