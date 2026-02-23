/**
 * AppConfigPage — global application configuration.
 *
 * Stub page. Will manage company info, default units, tax rates, and feature flags.
 */

import { Settings } from 'lucide-react';
import { EmptyState } from '../../../components/ui/EmptyState';

export function AppConfigPage() {
  return (
    <EmptyState
      icon={<Settings className="h-12 w-12" />}
      title="App Config"
      description="Manage company info, default units, tax rates, and feature flags. Coming soon."
    />
  );
}
