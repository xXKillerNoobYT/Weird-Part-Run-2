/**
 * AiConfigPage — AI assistant configuration.
 *
 * Stub page. Will manage AI model selection, prompt tuning, and automation rules.
 */

import { Bot } from 'lucide-react';
import { EmptyState } from '../../../components/ui/EmptyState';

export function AiConfigPage() {
  return (
    <EmptyState
      icon={<Bot className="h-12 w-12" />}
      title="AI Config"
      description="Configure AI assistant behavior, model preferences, and automation rules. Coming soon."
    />
  );
}
