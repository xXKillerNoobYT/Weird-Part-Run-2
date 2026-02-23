/**
 * EditColorPanel — right-panel form for editing a global color entry.
 *
 * Shows name, hex code picker, active toggle, delete button.
 */

import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Check, ToggleLeft, ToggleRight, Trash2 } from 'lucide-react';
import { Button } from '../../../../components/ui/Button';
import { Input } from '../../../../components/ui/Input';
import { Badge } from '../../../../components/ui/Badge';
import { Spinner } from '../../../../components/ui/Spinner';
import { listColors, updateColor } from '../../../../api/parts';
import type { PartColorUpdate } from '../../../../lib/types';


export interface EditColorPanelProps {
  colorId: number;
  canEdit: boolean;
  onDelete: () => void;
}

export function EditColorPanel({ colorId, canEdit, onDelete }: EditColorPanelProps) {
  const queryClient = useQueryClient();
  const { data: colors } = useQuery({ queryKey: ['colors'], queryFn: () => listColors() });
  const color = colors?.find((c) => c.id === colorId);

  const [name, setName] = useState('');
  const [hexCode, setHexCode] = useState('#FFFFFF');
  const [initialized, setInitialized] = useState(false);
  const [prevId, setPrevId] = useState(colorId);

  if (color && (!initialized || colorId !== prevId)) {
    setName(color.name);
    setHexCode(color.hex_code ?? '#FFFFFF');
    setInitialized(true);
    setPrevId(colorId);
  }

  const updateMutation = useMutation({
    mutationFn: (data: PartColorUpdate) => updateColor(colorId, data),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['colors'] }),
  });

  const toggleMutation = useMutation({
    mutationFn: (is_active: boolean) => updateColor(colorId, { is_active }),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['colors'] }),
  });

  if (!color) {
    return (
      <div className="flex-1 flex items-center justify-center">
        <Spinner size="lg" />
      </div>
    );
  }

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    updateMutation.mutate({ name, hex_code: hexCode || undefined });
  };

  return (
    <div className="flex flex-col h-full">
      <div className="px-6 py-4 border-b border-gray-200 dark:border-gray-700 bg-gray-50 dark:bg-gray-800/80 flex items-center justify-between">
        <div>
          <div className="flex items-center gap-2">
            <span
              className="inline-block w-5 h-5 rounded-full border-2 border-gray-300 dark:border-gray-500"
              style={{ backgroundColor: color.hex_code ?? '#ccc' }}
            />
            <h3 className="text-lg font-semibold text-gray-900 dark:text-gray-100">
              {color.name}
            </h3>
            <Badge variant={color.is_active ? 'success' : 'default'}>
              {color.is_active ? 'Active' : 'Inactive'}
            </Badge>
          </div>
          <p className="text-sm text-gray-500 dark:text-gray-400 mt-0.5">
            Color &middot; {color.part_count} parts &middot; {color.hex_code ?? 'No hex code'}
          </p>
        </div>
        {canEdit && (
          <div className="flex items-center gap-2">
            <button
              className="p-2 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors"
              onClick={() => toggleMutation.mutate(!color.is_active)}
            >
              {color.is_active ? (
                <ToggleRight className="h-5 w-5 text-green-500" />
              ) : (
                <ToggleLeft className="h-5 w-5 text-gray-400" />
              )}
            </button>
            <button
              className="p-2 rounded-lg hover:bg-red-50 dark:hover:bg-red-900/20 transition-colors"
              onClick={onDelete}
            >
              <Trash2 className="h-4 w-4 text-red-400" />
            </button>
          </div>
        )}
      </div>

      <form onSubmit={handleSubmit} className="flex-1 overflow-y-auto p-6 space-y-4">
        <Input label="Name" value={name} onChange={(e) => setName(e.target.value)} disabled={!canEdit} required />

        <div className="space-y-1.5">
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300">Hex Color Code</label>
          <div className="flex items-center gap-3">
            <input
              type="color"
              value={hexCode}
              onChange={(e) => setHexCode(e.target.value)}
              disabled={!canEdit}
              className="w-10 h-10 rounded-lg border border-gray-300 dark:border-gray-600 cursor-pointer disabled:opacity-50"
            />
            <Input
              value={hexCode}
              onChange={(e) => setHexCode(e.target.value)}
              disabled={!canEdit}
              className="font-mono"
            />
          </div>
        </div>

        {updateMutation.isSuccess && (
          <p className="text-green-600 text-sm flex items-center gap-1"><Check className="h-4 w-4" /> Saved</p>
        )}
        {updateMutation.isError && (
          <p className="text-red-500 text-sm">{(updateMutation.error as any)?.response?.data?.detail ?? 'Failed to save.'}</p>
        )}

        {canEdit && (
          <div className="flex justify-end pt-4 border-t border-gray-200 dark:border-gray-700">
            <Button type="submit" isLoading={updateMutation.isPending}>Save Changes</Button>
          </div>
        )}
      </form>
    </div>
  );
}
