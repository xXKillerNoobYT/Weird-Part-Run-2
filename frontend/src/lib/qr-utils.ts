/**
 * QR Code utilities — shared encoding/decoding for WiredPart QR labels.
 *
 * Format: {"app":"wiredpart","part_id":9,"code":"DRC-50","v":1}
 * The `app` prefix distinguishes our labels from random QR codes.
 * The `v` field allows future format changes without breaking old labels.
 */

export interface WiredPartQRData {
  app: 'wiredpart';
  part_id: number;
  code: string;
  v: 1;
}

/** Encode part data into the JSON string that goes inside a QR code. */
export function encodeQRData(partId: number, code: string | null): string {
  const payload: WiredPartQRData = {
    app: 'wiredpart',
    part_id: partId,
    code: code ?? '',
    v: 1,
  };
  return JSON.stringify(payload);
}

/**
 * Decode a scanned QR code string back into part data.
 * Returns null if the string isn't a valid WiredPart QR code.
 */
export function decodeQRData(raw: string): WiredPartQRData | null {
  try {
    const parsed = JSON.parse(raw);
    if (
      parsed &&
      parsed.app === 'wiredpart' &&
      typeof parsed.part_id === 'number' &&
      parsed.v === 1
    ) {
      return parsed as WiredPartQRData;
    }
    return null;
  } catch {
    return null;
  }
}
