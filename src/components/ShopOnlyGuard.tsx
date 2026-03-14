/**
 * ShopOnlyGuard — wraps pages that require the shop server (HTTP API).
 *
 * On Tauri (native) devices these pages cannot function because there
 * is no HTTP backend. Instead of crashing or showing infinite spinners,
 * this guard renders a friendly "shop-only" message.
 *
 * On desktop browsers (hitting the shop server) the children render normally.
 */

import { Monitor } from 'lucide-react';
import { isNativeApp } from '../lib/environment';

interface ShopOnlyGuardProps {
  children: React.ReactNode;
  /** Short description of what this page does (shown in the message) */
  feature?: string;
}

export function ShopOnlyGuard({ children, feature }: ShopOnlyGuardProps) {
  if (!isNativeApp()) {
    return <>{children}</>;
  }

  return (
    <div className="flex flex-col items-center justify-center py-16 px-4 text-center">
      <div className="flex h-14 w-14 items-center justify-center rounded-full bg-blue-100 dark:bg-blue-900/30 mb-4">
        <Monitor className="h-7 w-7 text-blue-500" />
      </div>
      <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-100 mb-1">
        Shop Computer Only
      </h2>
      <p className="text-sm text-gray-500 dark:text-gray-400 max-w-sm mb-2">
        {feature
          ? `${feature} is only available on the shop computer.`
          : 'This feature is only available on the shop computer.'}
      </p>
      <p className="text-xs text-gray-400 dark:text-gray-500 max-w-sm">
        Open Wired-Part in a browser on the shop network to access this page.
      </p>
    </div>
  );
}
