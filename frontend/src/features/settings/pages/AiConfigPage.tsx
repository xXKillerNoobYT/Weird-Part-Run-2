/**
 * AiConfigPage — AI assistant configuration.
 *
 * Planned for v2.0+: LM Studio local LLM integration with read-only tools
 * for natural language queries against inventory, jobs, and labor data.
 */

import { Bot } from 'lucide-react';
import { EmptyState } from '../../../components/ui/EmptyState';

export function AiConfigPage() {
  return (
    <EmptyState
      icon={<Bot className="h-12 w-12" />}
      title="AI Assistant"
      description="Local AI assistant integration (LM Studio) is planned for a future release. Will provide natural language queries for inventory, jobs, and labor data."
    />
  );
}
