/**
 * EscalationTimeline — visual timeline of Q&A escalation steps.
 *
 * Horizontal dots on desktop, vertical on mobile.
 * Color-coded by level: worker=blue, lead=cyan, foreman=yellow,
 * supervisor=orange, office=red. Completed steps filled, future empty.
 */

import {
  User,
  UserCheck,
  HardHat,
  Shield,
  Building2,
  ArrowUpRight,
  MessageSquare,
  CheckCircle2,
  Send,
  XCircle,
} from 'lucide-react';
import type { EscalationStep, QALevel } from '../../../lib/types';

interface EscalationTimelineProps {
  timeline: EscalationStep[];
  currentLevel: QALevel;
}

const LEVEL_CONFIG: Record<QALevel, {
  label: string;
  color: string;
  bgColor: string;
  borderColor: string;
  icon: typeof User;
}> = {
  worker:     { label: 'Worker',     color: 'text-blue-600 dark:text-blue-400',     bgColor: 'bg-blue-100 dark:bg-blue-900/40',     borderColor: 'border-blue-400', icon: User },
  lead:       { label: 'Lead',       color: 'text-cyan-600 dark:text-cyan-400',     bgColor: 'bg-cyan-100 dark:bg-cyan-900/40',     borderColor: 'border-cyan-400', icon: UserCheck },
  foreman:    { label: 'Foreman',    color: 'text-amber-600 dark:text-amber-400',   bgColor: 'bg-amber-100 dark:bg-amber-900/40',   borderColor: 'border-amber-400', icon: HardHat },
  supervisor: { label: 'Supervisor', color: 'text-orange-600 dark:text-orange-400', bgColor: 'bg-orange-100 dark:bg-orange-900/40', borderColor: 'border-orange-400', icon: Shield },
  office:     { label: 'Office',     color: 'text-red-600 dark:text-red-400',       bgColor: 'bg-red-100 dark:bg-red-900/40',       borderColor: 'border-red-400', icon: Building2 },
};

const ACTION_ICONS: Record<string, typeof User> = {
  asked: MessageSquare,
  escalated: ArrowUpRight,
  answered: CheckCircle2,
  sent_to_gc: Send,
  closed: XCircle,
};

function formatTime(ts: string | null | undefined): string {
  if (!ts) return '';
  const d = new Date(ts);
  return d.toLocaleDateString([], { month: 'short', day: 'numeric' }) +
    ' ' + d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
}

export function EscalationTimeline({ timeline, currentLevel: _currentLevel }: EscalationTimelineProps) {
  if (timeline.length === 0) return null;

  return (
    <div className="py-3">
      {/* Desktop: horizontal */}
      <div className="hidden sm:flex items-start gap-0">
        {timeline.map((step, i) => {
          const config = LEVEL_CONFIG[step.level as QALevel] || LEVEL_CONFIG.worker;
          const ActionIcon = ACTION_ICONS[step.action] || MessageSquare;
          const isLast = i === timeline.length - 1;

          return (
            <div key={i} className="flex items-start flex-1 min-w-0">
              {/* Dot + content */}
              <div className="flex flex-col items-center">
                <div className={`w-8 h-8 rounded-full ${config.bgColor} flex items-center justify-center border-2 ${config.borderColor}`}>
                  <ActionIcon className={`h-4 w-4 ${config.color}`} />
                </div>
                <div className="mt-1.5 text-center">
                  <p className={`text-[10px] font-semibold uppercase ${config.color}`}>
                    {config.label}
                  </p>
                  <p className="text-[10px] text-gray-500 dark:text-gray-400 capitalize">
                    {step.action.replace(/_/g, ' ')}
                  </p>
                  {step.user_name && (
                    <p className="text-[10px] text-gray-400 dark:text-gray-500 truncate max-w-[80px]">
                      {step.user_name}
                    </p>
                  )}
                  {step.timestamp && (
                    <p className="text-[10px] text-gray-400 dark:text-gray-500">
                      {formatTime(step.timestamp)}
                    </p>
                  )}
                </div>
              </div>

              {/* Connector line */}
              {!isLast && (
                <div className="flex-1 h-px bg-gray-300 dark:bg-gray-600 mt-4 mx-1" />
              )}
            </div>
          );
        })}
      </div>

      {/* Mobile: vertical */}
      <div className="sm:hidden space-y-0">
        {timeline.map((step, i) => {
          const config = LEVEL_CONFIG[step.level as QALevel] || LEVEL_CONFIG.worker;
          const ActionIcon = ACTION_ICONS[step.action] || MessageSquare;
          const isLast = i === timeline.length - 1;

          return (
            <div key={i} className="flex gap-3">
              {/* Vertical line + dot */}
              <div className="flex flex-col items-center">
                <div className={`w-7 h-7 rounded-full ${config.bgColor} flex items-center justify-center border-2 ${config.borderColor} flex-shrink-0`}>
                  <ActionIcon className={`h-3.5 w-3.5 ${config.color}`} />
                </div>
                {!isLast && (
                  <div className="w-px flex-1 bg-gray-300 dark:bg-gray-600 my-1" />
                )}
              </div>

              {/* Content */}
              <div className={`pb-4 min-w-0 ${isLast ? '' : ''}`}>
                <div className="flex items-center gap-2">
                  <span className={`text-xs font-semibold ${config.color}`}>
                    {config.label}
                  </span>
                  <span className="text-xs text-gray-500 dark:text-gray-400 capitalize">
                    {step.action.replace(/_/g, ' ')}
                  </span>
                </div>
                {step.user_name && (
                  <p className="text-xs text-gray-400 dark:text-gray-500">
                    {step.user_name}
                  </p>
                )}
                {step.comment && (
                  <p className="text-xs text-gray-600 dark:text-gray-300 mt-0.5 italic">
                    "{step.comment}"
                  </p>
                )}
                {step.timestamp && (
                  <p className="text-[10px] text-gray-400 dark:text-gray-500 mt-0.5">
                    {formatTime(step.timestamp)}
                  </p>
                )}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}
