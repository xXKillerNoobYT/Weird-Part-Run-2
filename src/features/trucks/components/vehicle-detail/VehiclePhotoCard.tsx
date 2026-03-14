/**
 * VehiclePhotoCard — displays vehicle photo with upload/remove controls.
 */

import { useMutation, useQueryClient } from '@tanstack/react-query';
import { Camera, Trash2, ImageOff } from 'lucide-react';
import { Card } from '../../../../components/ui/Card';
import { uploadVehiclePhoto, removeVehiclePhoto } from '../../../../api/vehicles';


export function VehiclePhotoCard({
  vehicleId,
  photoPath,
  canManage,
}: {
  vehicleId: number;
  photoPath: string | null;
  canManage: boolean;
}) {
  const queryClient = useQueryClient();

  const uploadMut = useMutation({
    mutationFn: (file: File) => uploadVehiclePhoto(vehicleId, file),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['vehicle', vehicleId] });
      queryClient.invalidateQueries({ queryKey: ['vehicles'] });
    },
  });

  const removeMut = useMutation({
    mutationFn: () => removeVehiclePhoto(vehicleId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['vehicle', vehicleId] });
      queryClient.invalidateQueries({ queryKey: ['vehicles'] });
    },
  });

  const handleFileSelect = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (file) uploadMut.mutate(file);
    e.target.value = '';
  };

  return (
    <Card noPadding className="lg:col-span-2">
      <div className="p-4">
        <div className="flex items-center justify-between mb-3">
          <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100">Vehicle Photo</h3>
          {canManage && (
            <div className="flex items-center gap-2">
              <label className="cursor-pointer">
                <input
                  type="file"
                  accept="image/*"
                  onChange={handleFileSelect}
                  className="hidden"
                />
                <span className="inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium text-blue-500 hover:text-blue-600 hover:bg-blue-50 dark:hover:bg-blue-900/20 rounded-lg transition-colors cursor-pointer">
                  <Camera className="h-3.5 w-3.5" />
                  {photoPath ? 'Change' : 'Upload'}
                </span>
              </label>
              {photoPath && (
                <button
                  onClick={() => {
                    if (window.confirm('Remove vehicle photo?')) removeMut.mutate();
                  }}
                  disabled={removeMut.isPending}
                  className="p-1.5 rounded text-gray-400 hover:text-red-500 hover:bg-red-50 dark:hover:bg-red-900/20 transition-colors"
                  title="Remove photo"
                >
                  <Trash2 className="h-3.5 w-3.5" />
                </button>
              )}
            </div>
          )}
        </div>

        {uploadMut.isPending && (
          <div className="flex items-center gap-2 mb-3 p-2 bg-blue-50 dark:bg-blue-900/20 rounded-lg">
            <div className="h-4 w-4 animate-spin rounded-full border-2 border-blue-500 border-t-transparent" />
            <span className="text-xs text-blue-600 dark:text-blue-400">Uploading photo...</span>
          </div>
        )}

        {photoPath ? (
          <div className="relative rounded-lg overflow-hidden bg-gray-100 dark:bg-gray-800 max-h-64">
            <img
              src={`/api${photoPath}`}
              alt="Vehicle"
              className="w-full h-full object-contain max-h-64"
            />
          </div>
        ) : (
          <div className="flex flex-col items-center justify-center py-8 text-gray-400 dark:text-gray-500">
            <ImageOff className="h-10 w-10 mb-2" />
            <p className="text-sm">No photo uploaded</p>
          </div>
        )}
      </div>
    </Card>
  );
}
