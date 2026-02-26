/**
 * Step 4: Verification — photo upload, barcode scan, qty double-confirm.
 *
 * Only shown for movements that require it (Truck→Job, Job→Truck).
 * Auto-skipped for other movement types.
 */

import { useRef } from 'react';
import { Camera, ScanLine, CheckSquare, Square, Image } from 'lucide-react';
import { Button } from '../../../../../components/ui/Button';
import { cn } from '../../../../../lib/utils';
import { uploadPhoto } from '../../../../../api/warehouse';
import { useMovementWizardStore } from '../../../stores/movement-wizard-store';

export function StepVerification() {
  const {
    photoPath,
    scanConfirmed,
    qtyConfirmed,
    setPhoto,
    setScanConfirmed,
    setQtyConfirmed,
    selectedParts,
  } = useMovementWizardStore();

  const fileInputRef = useRef<HTMLInputElement>(null);

  const handlePhotoCapture = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    try {
      const result = await uploadPhoto(file);
      setPhoto(result.path);
    } catch (err) {
      console.error('Photo upload failed:', err);
    }
  };

  return (
    <div className="space-y-6">
      <p className="text-sm text-gray-500 dark:text-gray-400">
        This movement requires photo verification. Please take a photo of the
        parts before proceeding.
      </p>

      {/* Photo Upload */}
      <div className="space-y-3">
        <label className="block text-sm font-medium text-gray-700 dark:text-gray-300">
          Photo Verification
        </label>

        {photoPath ? (
          <div className="relative inline-block">
            <div className="w-48 h-48 rounded-lg border-2 border-green-400 bg-green-50 dark:bg-green-900/20 flex items-center justify-center">
              <div className="text-center">
                <Image className="h-8 w-8 text-green-500 mx-auto mb-2" />
                <span className="text-sm text-green-600 dark:text-green-400 font-medium">
                  Photo captured
                </span>
              </div>
            </div>
            <button
              onClick={() => setPhoto(null)}
              className="absolute -top-2 -right-2 p-1 rounded-full bg-red-500 text-white text-xs"
            >
              ×
            </button>
          </div>
        ) : (
          <button
            onClick={() => fileInputRef.current?.click()}
            className="flex flex-col items-center justify-center w-48 h-48 rounded-lg border-2 border-dashed border-gray-300 dark:border-gray-600 hover:border-primary-400 dark:hover:border-primary-600 transition-colors cursor-pointer"
          >
            <Camera className="h-8 w-8 text-gray-400 mb-2" />
            <span className="text-sm text-gray-500 dark:text-gray-400">
              Take Photo
            </span>
            <span className="text-xs text-gray-400 mt-1">
              or upload from gallery
            </span>
          </button>
        )}

        <input
          ref={fileInputRef}
          type="file"
          accept="image/*"
          capture="environment"
          onChange={handlePhotoCapture}
          className="hidden"
        />
      </div>

      {/* Barcode / QR Scan */}
      <div className="space-y-3">
        <label className="block text-sm font-medium text-gray-700 dark:text-gray-300">
          Barcode / QR Scan (optional)
        </label>
        <div className="relative">
          <ScanLine className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-gray-400" />
          <input
            type="text"
            placeholder="Scan or type part code..."
            className="w-full pl-10 pr-4 py-2.5 rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 text-sm"
            onKeyDown={(e) => {
              if (e.key === 'Enter') {
                setScanConfirmed(true);
              }
            }}
          />
        </div>
        <p className="text-xs text-gray-400">
          Bluetooth scanners work as keyboard input. Press Enter after scanning.
        </p>
      </div>

      {/* Quantity Double-Confirm */}
      <div className="space-y-3">
        <label className="block text-sm font-medium text-gray-700 dark:text-gray-300">
          Quantity Confirmation
        </label>

        <button
          onClick={() => setQtyConfirmed(!qtyConfirmed)}
          className="flex items-start gap-3 p-4 rounded-lg border border-gray-200 dark:border-gray-700 hover:bg-gray-50 dark:hover:bg-gray-900/50 transition-colors w-full text-left"
        >
          {qtyConfirmed ? (
            <CheckSquare className="h-5 w-5 text-primary-500 flex-shrink-0 mt-0.5" />
          ) : (
            <Square className="h-5 w-5 text-gray-400 flex-shrink-0 mt-0.5" />
          )}
          <div>
            <span className={cn(
              'text-sm font-medium block',
              qtyConfirmed
                ? 'text-gray-900 dark:text-gray-100'
                : 'text-gray-600 dark:text-gray-400',
            )}>
              I confirm the quantities are correct
            </span>
            <span className="text-xs text-gray-400 mt-1 block">
              {selectedParts.length} part{selectedParts.length !== 1 ? 's' : ''},{' '}
              {selectedParts.reduce((s, p) => s + p.qty, 0)} total units
            </span>
          </div>
        </button>
      </div>
    </div>
  );
}
