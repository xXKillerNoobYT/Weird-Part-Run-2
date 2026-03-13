/**
 * EmptyState — placeholder shown when a page/section has no content yet.
 *
 * Used for stub pages in Phase 1 and genuinely empty data states later.
 *
 * The `icon` prop accepts either:
 *   - A rendered element:   icon={<Package className="h-12 w-12" />}
 *   - A component reference: icon={Package}   (auto-rendered at h-12 w-12)
 */

import { isValidElement, createElement } from 'react';
import type { ReactNode, ComponentType } from 'react';
import { cn } from '../../lib/utils';

interface EmptyStateProps {
  icon?: ReactNode | ComponentType<{ className?: string }>;
  title: string;
  description?: string;
  action?: ReactNode;
  className?: string;
}

/** Render the icon — handles both <Icon /> elements and bare Icon references */
function renderIcon(icon: EmptyStateProps['icon']): ReactNode {
  if (!icon) return null;
  // Already a rendered element (e.g. <Package className="h-12 w-12" />)
  if (isValidElement(icon)) return icon;
  // A component reference (e.g. Package) — render it with default sizing
  if (typeof icon === 'function' || (typeof icon === 'object' && icon !== null && '$$typeof' in icon)) {
    return createElement(icon as ComponentType<{ className?: string }>, { className: 'h-12 w-12' });
  }
  return icon;
}

export function EmptyState({
  icon,
  title,
  description,
  action,
  className,
}: EmptyStateProps) {
  const renderedIcon = renderIcon(icon);

  return (
    <div
      className={cn(
        'flex flex-col items-center justify-center py-16 px-6 text-center',
        className,
      )}
    >
      {renderedIcon && (
        <div className="mb-4 text-gray-400 dark:text-gray-500">{renderedIcon}</div>
      )}
      <h3 className="text-lg font-semibold text-gray-900 dark:text-gray-100 mb-1">
        {title}
      </h3>
      {description && (
        <p className="text-sm text-gray-500 dark:text-gray-400 max-w-md mb-6">
          {description}
        </p>
      )}
      {action}
    </div>
  );
}
