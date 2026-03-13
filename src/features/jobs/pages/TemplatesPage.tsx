/**
 * TemplatesPage — reusable job notebook templates.
 *
 * Stub page. Will manage templates for common job types with pre-filled parts lists.
 */

import { FileText } from 'lucide-react';
import { EmptyState } from '../../../components/ui/EmptyState';

export function TemplatesPage() {
  return (
    <EmptyState
      icon={<FileText className="h-12 w-12" />}
      title="Notebook Templates"
      description="Create and manage reusable job templates with pre-filled parts lists. Coming soon."
    />
  );
}
