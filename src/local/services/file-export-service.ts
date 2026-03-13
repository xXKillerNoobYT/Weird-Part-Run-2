/**
 * File Export Service — native save dialog + file write for Tauri.
 *
 * In browser mode, exports use the standard blob download pattern:
 *   URL.createObjectURL → <a>.click() → browser download dialog.
 *
 * In Tauri mode, that pattern doesn't work reliably (especially on iOS
 * where WebView download is restricted). Instead, this service:
 *   1. Opens a native OS "Save As" dialog via tauri-plugin-dialog
 *   2. Writes the file directly to disk via tauri-plugin-fs
 *
 * Usage: Replace all `downloadBlob(blob, filename)` calls with
 *   `exportFile(blob, filename)` — it auto-detects the environment
 *   and routes to the correct implementation.
 */

import { isTauri } from '../../lib/environment';

/** File type filter for native save dialogs */
interface FileFilter {
  name: string;
  extensions: string[];
}

/** Infer file type filters from filename extension */
function inferFilters(filename: string): FileFilter[] {
  const ext = filename.split('.').pop()?.toLowerCase();
  switch (ext) {
    case 'csv':
      return [{ name: 'CSV Files', extensions: ['csv'] }];
    case 'pdf':
      return [{ name: 'PDF Documents', extensions: ['pdf'] }];
    case 'json':
      return [{ name: 'JSON Files', extensions: ['json'] }];
    case 'iif':
      return [{ name: 'IIF Files (QuickBooks)', extensions: ['iif'] }];
    case 'xlsx':
      return [{ name: 'Excel Files', extensions: ['xlsx'] }];
    case 'zip':
      return [{ name: 'ZIP Archives', extensions: ['zip'] }];
    case 'db':
    case 'sqlite':
      return [{ name: 'Database Files', extensions: ['db', 'sqlite'] }];
    default:
      return [{ name: 'All Files', extensions: ['*'] }];
  }
}

/**
 * Export a file — auto-detects environment.
 *
 * - Tauri: native "Save As" dialog → writes to chosen path
 * - Browser: standard blob download via createObjectURL
 *
 * @param data — Blob, string, or Uint8Array to save
 * @param defaultFilename — suggested filename (e.g. "report-2026-03-12.csv")
 * @returns true if saved, false if user cancelled the dialog
 */
export async function exportFile(
  data: Blob | string | Uint8Array,
  defaultFilename: string,
): Promise<boolean> {
  if (isTauri()) {
    return exportFileTauri(data, defaultFilename);
  }
  exportFileBrowser(data, defaultFilename);
  return true;
}

/** Browser fallback — the classic blob download trick */
function exportFileBrowser(data: Blob | string | Uint8Array, filename: string): void {
  let blob: Blob;
  if (data instanceof Blob) {
    blob = data;
  } else if (typeof data === 'string') {
    blob = new Blob([data], { type: 'text/plain;charset=utf-8' });
  } else {
    blob = new Blob([data], { type: 'application/octet-stream' });
  }

  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
}

/** Tauri path — native save dialog → fs write */
async function exportFileTauri(
  data: Blob | string | Uint8Array,
  defaultFilename: string,
): Promise<boolean> {
  const { save } = await import('@tauri-apps/plugin-dialog');
  const { writeTextFile, writeFile } = await import('@tauri-apps/plugin-fs');

  // Show native "Save As" dialog
  const filePath = await save({
    defaultPath: defaultFilename,
    filters: inferFilters(defaultFilename),
  });

  if (!filePath) return false; // User cancelled

  // Convert data to the right format and write
  if (typeof data === 'string') {
    await writeTextFile(filePath, data);
  } else if (data instanceof Uint8Array) {
    await writeFile(filePath, data);
  } else {
    // Blob → Uint8Array
    const buffer = await data.arrayBuffer();
    await writeFile(filePath, new Uint8Array(buffer));
  }

  return true;
}

/**
 * Open a native file picker for importing files.
 *
 * - Tauri: native "Open" dialog
 * - Browser: triggers an `<input type="file">` click (returns via callback)
 *
 * @param filters — file type filters (e.g. [{ name: 'CSV', extensions: ['csv'] }])
 * @returns selected file path (Tauri) or null if cancelled
 */
export async function importFile(
  filters?: FileFilter[],
): Promise<{ path: string; contents: string } | null> {
  if (!isTauri()) {
    // Browser: use the existing file input pattern (caller handles <input>)
    return null;
  }

  const { open } = await import('@tauri-apps/plugin-dialog');
  const { readTextFile } = await import('@tauri-apps/plugin-fs');

  const filePath = await open({
    multiple: false,
    filters: filters ?? [{ name: 'All Files', extensions: ['*'] }],
  });

  if (!filePath) return null; // User cancelled

  const path = typeof filePath === 'string' ? filePath : (filePath as any).path;
  const contents = await readTextFile(path);
  return { path, contents };
}
