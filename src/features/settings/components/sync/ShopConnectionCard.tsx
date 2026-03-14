/**
 * ShopConnectionCard — shop server URL configuration for native (Tauri) devices.
 */

import { useState, useEffect } from 'react';
import {
  RefreshCw, CheckCircle, CloudOff, Settings2,
} from 'lucide-react';
import { Button } from '../../../../components/ui/Button';

export function ShopConnectionCard() {
  const [url, setUrl] = useState('');
  const [_savedUrl, setSavedUrl] = useState<string | null>(null);
  const [reachable, setReachable] = useState<boolean | null>(null);
  const [shopInfo, setShopInfo] = useState<any>(null);
  const [checking, setChecking] = useState(false);

  useEffect(() => {
    import('../../../../lib/shop-config').then(async (mod) => {
      const u = await mod.getShopUrl();
      setSavedUrl(u);
      if (u) setUrl(u);
    });
  }, []);

  async function handleSave() {
    const mod = await import('../../../../lib/shop-config');
    await mod.setShopUrl(url);
    setSavedUrl(url);
    handleCheck();
  }

  async function handleCheck() {
    setChecking(true);
    const mod = await import('../../../../lib/shop-config');
    const ok = await mod.isShopReachable();
    setReachable(ok);
    if (ok) {
      const info = await mod.getShopInfo();
      setShopInfo(info);
    }
    setChecking(false);
  }

  return (
    <div className="bg-surface border border-border rounded-lg p-4 space-y-3">
      <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100 flex items-center gap-2">
        <Settings2 className="h-4 w-4" />
        Shop Server Connection
      </h3>

      <div className="flex flex-wrap gap-2">
        <input
          type="url"
          value={url}
          onChange={(e) => setUrl(e.target.value)}
          placeholder="http://192.168.1.100:8000"
          className="flex-1 min-w-[200px] px-3 py-2 text-sm border border-border rounded-md bg-surface text-gray-900 dark:text-gray-100"
        />
        <Button size="sm" onClick={handleSave}>Save</Button>
        <Button size="sm" variant="secondary" onClick={handleCheck} disabled={checking}>
          {checking ? <RefreshCw className="h-4 w-4 animate-spin" /> : 'Test'}
        </Button>
      </div>

      {reachable !== null && (
        <div className={`flex items-center gap-2 text-sm ${reachable ? 'text-green-600 dark:text-green-400' : 'text-red-600 dark:text-red-400'}`}>
          {reachable ? <CheckCircle className="h-4 w-4" /> : <CloudOff className="h-4 w-4" />}
          {reachable ? 'Connected to shop server' : 'Cannot reach shop server'}
        </div>
      )}

      {shopInfo && (
        <div className="text-xs text-gray-500 dark:text-gray-400 space-y-0.5">
          <div>Host: {shopInfo.hostname}</div>
          <div>IP: {shopInfo.local_ip}:{shopInfo.port}</div>
        </div>
      )}
    </div>
  );
}
