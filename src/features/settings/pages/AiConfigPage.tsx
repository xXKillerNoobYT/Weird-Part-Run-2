/**
 * AiConfigPage — AI assistant configuration.
 *
 * Configures the LM Studio local LLM integration (Phase 12).
 * All AI processing runs on-premises — zero cloud dependency.
 *
 * Sections:
 *   1. Connection — LM Studio URL + connection test
 *   2. Feature Toggles — enable/disable each AI capability
 *   3. About — examples for each capability
 *
 * Settings are persisted via the generic key/value settings API
 * under category "ai". No new backend endpoints required.
 */

import { useState, useEffect } from 'react';
import { useQuery } from '@tanstack/react-query';
import {
  Bot, Wifi, WifiOff, Loader2, Save, ChevronDown, ChevronUp,
  MessageSquare, FileText, AlertTriangle, ShoppingCart, LayoutGrid, Server,
  Info, Cpu, RefreshCw, CheckCircle2, XCircle, FolderOpen, Download,
} from 'lucide-react';
import { Button } from '../../../components/ui/Button';
import { Card, CardHeader } from '../../../components/ui/Card';
import { Badge } from '../../../components/ui/Badge';
import { ErrorFallback } from '../../../components/ui/ErrorFallback';
import { getAllSettings, updateSetting } from '../../../api/settings';
import { toast } from '../../../lib/toast';
import { getPlatform } from '../../../lib/environment';
import {
  checkAvailability, resetAvailability, getModelsDir, getServerDir,
  getAvailabilityMessage,
  type LlmAvailability,
} from '../../../lib/foundation-models';


// ── Feature definitions ──────────────────────────────────────────

interface AiFeature {
  key: string;
  label: string;
  description: string;
  icon: React.FC<{ className?: string }>;
  example: string;
}

const AI_FEATURES: AiFeature[] = [
  {
    key: 'ai_nl_queries',
    label: 'Natural Language Queries',
    description: 'Ask questions in plain English and get data-backed answers from the database.',
    icon: MessageSquare,
    example: '"How many hours did Roy work last week?" — "Which jobs are over budget?"',
  },
  {
    key: 'ai_report_summaries',
    label: 'Report Summaries',
    description: 'Auto-generate readable summaries from daily reports, timesheets, and job cost data.',
    icon: FileText,
    example: '"Today: 4 workers on Smith job (32 hrs). Roy flagged a panel issue."',
  },
  {
    key: 'ai_anomaly_detection',
    label: 'Anomaly Detection',
    description: 'Automatically flag unusual patterns in labor, parts usage, and scheduling.',
    icon: AlertTriangle,
    example: '"Roy has 12 OT hours this week — above his 4-week average of 3"',
  },
  {
    key: 'ai_predictive_ordering',
    label: 'Predictive Ordering',
    description: 'Suggest parts to order based on job schedules and historical usage rates.',
    icon: ShoppingCart,
    example: '"Based on last 90 days, you\'ll need ~200 outlets in the next 30 days"',
  },
  {
    key: 'ai_scheduling_suggestions',
    label: 'Scheduling Suggestions',
    description: 'Recommend optimal crew assignments based on job type and worker history.',
    icon: LayoutGrid,
    example: '"Roy and Mike finish panel work 15% faster — assign them to the Smith panel"',
  },
];


// ── Toggle switch ────────────────────────────────────────────────

function Toggle({
  checked, onChange, disabled = false,
}: {
  checked: boolean;
  onChange: (v: boolean) => void;
  disabled?: boolean;
}) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={checked}
      disabled={disabled}
      onClick={() => onChange(!checked)}
      className={`relative inline-flex h-6 w-11 flex-shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 focus:outline-none focus:ring-2 focus:ring-primary focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50 ${checked ? 'bg-green-500' : 'bg-gray-200 dark:bg-gray-700'
        }`}
    >
      <span
        className={`pointer-events-none inline-block h-5 w-5 rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out ${checked ? 'translate-x-5' : 'translate-x-0'
          }`}
      />
    </button>
  );
}


// ── Connection status pill ────────────────────────────────────────

type ConnStatus = 'untested' | 'testing' | 'ok' | 'error';

function ConnectionPill({ status }: { status: ConnStatus }) {
  if (status === 'testing') {
    return (
      <span className="inline-flex items-center gap-1.5 text-xs text-amber-600 dark:text-amber-400">
        <Loader2 className="h-3.5 w-3.5 animate-spin" /> Testing…
      </span>
    );
  }
  if (status === 'ok') {
    return (
      <span className="inline-flex items-center gap-1.5 text-xs text-green-600 dark:text-green-400">
        <Wifi className="h-3.5 w-3.5" /> Connected
      </span>
    );
  }
  if (status === 'error') {
    return (
      <span className="inline-flex items-center gap-1.5 text-xs text-red-500 dark:text-red-400">
        <WifiOff className="h-3.5 w-3.5" /> Unreachable
      </span>
    );
  }
  return (
    <span className="inline-flex items-center gap-1.5 text-xs text-gray-400 dark:text-gray-500">
      <Wifi className="h-3.5 w-3.5" /> Not tested
    </span>
  );
}


// ── Main Page ────────────────────────────────────────────────────

export function AiConfigPage() {
  const { data: allSettings, isLoading, isError, refetch } = useQuery({
    queryKey: ['all-settings'],
    queryFn: getAllSettings,
    staleTime: 60_000,
  });

  const [lmStudioUrl, setLmStudioUrl] = useState('http://localhost:1234');
  const [masterEnabled, setMasterEnabled] = useState(false);
  const [features, setFeatures] = useState<Record<string, boolean>>({});
  const [connStatus, setConnStatus] = useState<ConnStatus>('untested');
  const [saving, setSaving] = useState(false);
  const [detailsOpen, setDetailsOpen] = useState(false);

  // ── On-device AI state ──
  const platform = getPlatform();
  const isWindows = platform === 'windows';
  const isApple = platform === 'ios' || platform === 'macos';
  const [llmStatus, setLlmStatus] = useState<LlmAvailability | null>(null);
  const [llmChecking, setLlmChecking] = useState(false);
  const [modelsDir, setModelsDir] = useState('');
  const [serverDir, setServerDir] = useState('');

  // Check on-device AI availability on mount
  useEffect(() => {
    let cancelled = false;
    const check = async () => {
      setLlmChecking(true);
      const status = await checkAvailability();
      if (!cancelled) setLlmStatus(status);
      if (isWindows) {
        const [mDir, sDir] = await Promise.all([getModelsDir(), getServerDir()]);
        if (!cancelled) {
          setModelsDir(mDir);
          setServerDir(sDir);
        }
      }
      if (!cancelled) setLlmChecking(false);
    };
    check();
    return () => { cancelled = true; };
  }, [isWindows]);

  const handleRefreshLlm = async () => {
    setLlmChecking(true);
    await resetAvailability();
    const status = await checkAvailability();
    setLlmStatus(status);
    setLlmChecking(false);
    if (status === 'available') {
      toast.success('On-device AI is ready!');
    }
  };

  // Seed form from persisted settings
  useEffect(() => {
    if (!allSettings) return;
    const ai = (allSettings.ai ?? {}) as Record<string, string>;
    if (ai.ai_lm_studio_url) setLmStudioUrl(ai.ai_lm_studio_url);
    if (ai.ai_enabled !== undefined) setMasterEnabled(ai.ai_enabled === 'true');
    const featureState: Record<string, boolean> = {};
    for (const f of AI_FEATURES) {
      featureState[f.key] = ai[f.key] === 'true';
    }
    setFeatures(featureState);
  }, [allSettings]);

  const testConnection = async () => {
    setConnStatus('testing');
    try {
      const url = lmStudioUrl.replace(/\/$/, '');
      const res = await fetch(`${url}/v1/models`, {
        signal: AbortSignal.timeout(5000),
      });
      setConnStatus(res.ok ? 'ok' : 'error');
    } catch {
      setConnStatus('error');
    }
  };

  const handleSave = async () => {
    setSaving(true);
    try {
      await Promise.all([
        updateSetting('ai_lm_studio_url', lmStudioUrl, 'ai'),
        updateSetting('ai_enabled', String(masterEnabled), 'ai'),
        ...AI_FEATURES.map((f) =>
          updateSetting(f.key, String(features[f.key] ?? false), 'ai'),
        ),
      ]);
      toast.success('AI settings saved');
    } catch {
      toast.error('Failed to save AI settings');
    } finally {
      setSaving(false);
    }
  };

  const setFeature = (key: string, val: boolean) => {
    setFeatures((prev) => ({ ...prev, [key]: val }));
  };

  if (isLoading) {
    return (
      <div className="flex items-center justify-center py-16">
        <Loader2 className="h-6 w-6 animate-spin text-gray-400" />
      </div>
    );
  }

  if (isError) return <ErrorFallback onRetry={refetch} />;

  return (
    <div className="space-y-5 max-w-2xl">
      {/* Header */}
      <div className="flex items-start justify-between flex-wrap gap-3">
        <div>
          <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-100">
            AI Assistant
          </h2>
          <p className="text-sm text-gray-500 dark:text-gray-400 mt-0.5">
            Local LLM via LM Studio — all processing stays on your network.
          </p>
        </div>
        <Badge variant={masterEnabled ? 'success' : 'default'}>
          {masterEnabled ? 'Enabled' : 'Disabled'}
        </Badge>
      </div>

      {/* How it works — local vs field */}
      <div className="space-y-2">
        <div className="flex items-start gap-3 p-3 rounded-xl bg-green-50 dark:bg-green-900/20 border border-green-200 dark:border-green-700">
          <Server className="h-4 w-4 text-green-600 dark:text-green-400 mt-0.5 flex-shrink-0" />
          <p className="text-sm text-green-700 dark:text-green-300">
            <strong>At the shop:</strong> If LM Studio is running on this computer, AI queries
            from any browser on the local network get results right away — fast and private.
          </p>
        </div>
        <div className="flex items-start gap-3 p-3 rounded-xl bg-amber-50 dark:bg-amber-900/20 border border-amber-200 dark:border-amber-700">
          <Info className="h-4 w-4 text-amber-600 dark:text-amber-400 mt-0.5 flex-shrink-0" />
          <p className="text-sm text-amber-700 dark:text-amber-300">
            <strong>In the field:</strong> AI requests get queued on your device and process
            when it syncs back at the shop. Results may take until the next device courier cycle.
          </p>
        </div>
      </div>

      {/* On-Device AI Status (Windows llama.cpp / Apple Foundation Models) */}
      {(isWindows || isApple) && (
        <Card>
          <CardHeader
            title="On-Device AI"
            subtitle={isWindows
              ? 'Local AI text assistance powered by llama.cpp'
              : 'Powered by Apple Intelligence on this device'}
            action={
              llmChecking
                ? <Loader2 className="h-4 w-4 animate-spin text-gray-400" />
                : <Cpu className="h-4 w-4 text-gray-400 dark:text-gray-500" />
            }
          />
          <div className="px-4 pb-4 space-y-3">
            {/* Status badge */}
            <div className="flex items-center justify-between flex-wrap gap-2">
              <div className="flex items-center gap-2">
                {llmStatus === 'available' ? (
                  <CheckCircle2 className="h-4 w-4 text-green-500" />
                ) : (
                  <XCircle className="h-4 w-4 text-gray-400" />
                )}
                <span className="text-sm text-gray-700 dark:text-gray-300">
                  {llmStatus ? getAvailabilityMessage(llmStatus) : 'Checking…'}
                </span>
              </div>
              <Button size="sm" variant="ghost" onClick={handleRefreshLlm} disabled={llmChecking}>
                <RefreshCw className={`h-3.5 w-3.5 ${llmChecking ? 'animate-spin' : ''}`} />
                <span className="hidden sm:inline ml-1">Refresh</span>
              </Button>
            </div>

            {/* Windows setup instructions — shown when not fully available */}
            {isWindows && llmStatus && llmStatus !== 'available' && (
              <div className="space-y-2 pt-2 border-t border-border">
                <p className="text-xs font-semibold text-gray-700 dark:text-gray-300">
                  Setup Instructions
                </p>

                {(llmStatus === 'not_installed' || llmStatus === 'no_server') && (
                  <div className="flex items-start gap-2.5 text-xs text-gray-500 dark:text-gray-400">
                    <Download className="h-3.5 w-3.5 mt-0.5 flex-shrink-0 text-blue-500" />
                    <div>
                      <p className="font-medium text-gray-700 dark:text-gray-300">1. Download llama-server</p>
                      <p className="mt-0.5">
                        Go to{' '}
                        <span className="font-mono text-xs text-blue-600 dark:text-blue-400 select-all">
                          github.com/ggerganov/llama.cpp/releases
                        </span>
                        {' '}→ download <strong>llama-server.exe</strong> (from the Windows zip).
                      </p>
                      {serverDir && (
                        <div className="flex items-center gap-1.5 mt-1">
                          <FolderOpen className="h-3 w-3 flex-shrink-0" />
                          <span className="font-mono text-xs select-all break-all">{serverDir}</span>
                        </div>
                      )}
                    </div>
                  </div>
                )}

                {(llmStatus === 'not_installed' || llmStatus === 'no_model') && (
                  <div className="flex items-start gap-2.5 text-xs text-gray-500 dark:text-gray-400">
                    <Download className="h-3.5 w-3.5 mt-0.5 flex-shrink-0 text-violet-500" />
                    <div>
                      <p className="font-medium text-gray-700 dark:text-gray-300">
                        {llmStatus === 'not_installed' ? '2' : '1'}. Download a GGUF model
                      </p>
                      <p className="mt-0.5">
                        Download a quantized model file (e.g.{' '}
                        <span className="font-mono text-xs">Phi-3-mini-4k-instruct-q4_k_m.gguf</span>
                        ) from Hugging Face. Place the <strong>.gguf</strong> file in:
                      </p>
                      {modelsDir && (
                        <div className="flex items-center gap-1.5 mt-1">
                          <FolderOpen className="h-3 w-3 flex-shrink-0" />
                          <span className="font-mono text-xs select-all break-all">{modelsDir}</span>
                        </div>
                      )}
                    </div>
                  </div>
                )}

                {llmStatus === 'not_ready' && (
                  <p className="text-xs text-amber-600 dark:text-amber-400">
                    The AI model is starting up. This can take 10–30 seconds for the first request.
                    Try refreshing in a moment.
                  </p>
                )}

                <p className="text-xs text-gray-400 dark:text-gray-500 pt-1">
                  Recommended: Phi-3 Mini (4GB, fast) or Llama 3.1 8B (6GB, versatile).
                  Q4_K_M quantization is a good balance of quality and speed.
                </p>
              </div>
            )}

            {/* Available confirmation */}
            {llmStatus === 'available' && (
              <p className="text-xs text-green-600 dark:text-green-400">
                AI text assistance is active. Start typing in any AI-enabled text field to see suggestions.
              </p>
            )}
          </div>
        </Card>
      )}

      {/* Master toggle */}
      <Card>
        <div className="p-4 flex items-center justify-between gap-4">
          <div className="flex items-center gap-3">
            <div className="p-2 rounded-lg bg-violet-100 dark:bg-violet-900/30">
              <Bot className="h-5 w-5 text-violet-600 dark:text-violet-400" />
            </div>
            <div>
              <p className="text-sm font-medium text-gray-900 dark:text-gray-100">
                Enable AI Assistant
              </p>
              <p className="text-xs text-gray-500 dark:text-gray-400 mt-0.5">
                Master switch. Requires LM Studio running on this computer.
              </p>
            </div>
          </div>
          <Toggle checked={masterEnabled} onChange={setMasterEnabled} />
        </div>
      </Card>

      {/* Connection config */}
      <Card>
        <CardHeader
          title="LM Studio Connection"
          subtitle="Point this to your local LM Studio server"
          action={<Server className="h-4 w-4 text-gray-400 dark:text-gray-500" />}
        />
        <div className="px-4 pb-4">
          <label className="block text-xs font-medium text-gray-700 dark:text-gray-300 mb-1">
            Server URL
          </label>
          <div className="flex gap-2">
            <input
              type="url"
              value={lmStudioUrl}
              onChange={(e) => { setLmStudioUrl(e.target.value); setConnStatus('untested'); }}
              placeholder="http://localhost:1234"
              className="flex-1 rounded-lg border border-border bg-surface px-3 py-2 text-sm text-gray-900 dark:text-gray-100 placeholder:text-gray-400 dark:placeholder:text-gray-500 focus:ring-2 focus:ring-primary focus:border-primary"
            />
            <Button
              size="sm"
              variant="secondary"
              onClick={testConnection}
              disabled={connStatus === 'testing' || !lmStudioUrl}
            >
              Test
            </Button>
          </div>
          <div className="mt-1.5 flex items-center justify-between flex-wrap gap-2">
            <p className="text-xs text-gray-400 dark:text-gray-500">
              LM Studio runs on port 1234 by default. Open LM Studio → Load a model → Start Server.
            </p>
            <ConnectionPill status={connStatus} />
          </div>
        </div>
      </Card>

      {/* Feature toggles */}
      <Card>
        <CardHeader title="Features" subtitle="Enable the AI capabilities you want to use" />
        <div className="divide-y divide-border">
          {AI_FEATURES.map((feature) => {
            const Icon = feature.icon;
            const enabled = features[feature.key] ?? false;
            return (
              <div
                key={feature.key}
                className={`flex items-center gap-3 px-4 py-3.5 ${!masterEnabled ? 'opacity-50' : ''
                  }`}
              >
                <Icon className="h-4 w-4 text-gray-400 dark:text-gray-500 flex-shrink-0" />
                <div className="flex-1 min-w-0">
                  <p className="text-sm font-medium text-gray-900 dark:text-gray-100">
                    {feature.label}
                  </p>
                  <p className="text-xs text-gray-500 dark:text-gray-400 mt-0.5">
                    {feature.description}
                  </p>
                </div>
                <Toggle
                  checked={enabled}
                  onChange={(v) => setFeature(feature.key, v)}
                  disabled={!masterEnabled}
                />
              </div>
            );
          })}
        </div>
      </Card>

      {/* Capability examples collapsible */}
      <Card>
        <button
          type="button"
          onClick={() => setDetailsOpen(!detailsOpen)}
          className="w-full flex items-center justify-between px-4 py-3 text-left hover:bg-surface-secondary transition-colors rounded-xl"
        >
          <div className="flex items-center gap-2">
            <MessageSquare className="h-4 w-4 text-gray-400 dark:text-gray-500" />
            <span className="text-sm font-medium text-gray-900 dark:text-gray-100">
              What can AI do?
            </span>
          </div>
          {detailsOpen
            ? <ChevronUp className="h-4 w-4 text-gray-400" />
            : <ChevronDown className="h-4 w-4 text-gray-400" />
          }
        </button>
        {detailsOpen && (
          <div className="px-4 pb-4 space-y-3 border-t border-border pt-3">
            {AI_FEATURES.map((feature) => {
              const Icon = feature.icon;
              return (
                <div key={feature.key} className="space-y-1">
                  <div className="flex items-center gap-2">
                    <Icon className="h-3.5 w-3.5 text-violet-500 dark:text-violet-400" />
                    <span className="text-xs font-semibold text-gray-900 dark:text-gray-100">
                      {feature.label}
                    </span>
                  </div>
                  <p className="text-xs text-gray-500 dark:text-gray-400 pl-5">
                    {feature.description}
                  </p>
                  <p className="text-xs text-violet-600 dark:text-violet-400 pl-5 italic">
                    e.g. {feature.example}
                  </p>
                </div>
              );
            })}
            <div className="mt-3 pt-3 border-t border-border">
              <p className="text-xs text-gray-400 dark:text-gray-500">
                <strong className="text-gray-600 dark:text-gray-300">Privacy:</strong>{' '}
                All AI processing happens on this shop computer. No data leaves the network.
                Recommended models: Llama 3 8B (fast, low RAM) or Llama 3 70B (accurate, 64GB+ RAM).
              </p>
            </div>
          </div>
        )}
      </Card>

      {/* Save button */}
      <div className="flex items-center justify-end pt-1">
        <Button
          variant="primary"
          onClick={handleSave}
          disabled={saving}
          icon={saving
            ? <Loader2 className="h-4 w-4 animate-spin" />
            : <Save className="h-4 w-4" />
          }
        >
          {saving ? 'Saving…' : 'Save Settings'}
        </Button>
      </div>
    </div>
  );
}
