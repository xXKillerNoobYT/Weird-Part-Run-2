/**
 * CreateForm — right-panel form for creating new hierarchy items.
 *
 * Handles category, style, type, and color creation with dynamic fields
 * based on the target type.
 */

import { useState } from 'react';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { Plus } from 'lucide-react';
import { Button } from '../../../../components/ui/Button';
import { Input } from '../../../../components/ui/Input';
import {
  createCategory, createStyle, createType, createColor,
} from '../../../../api/parts';
import type {
  PartCategoryCreate, PartStyleCreate, PartTypeCreate, PartColorCreate,
  PartColor, CategoryNodeType,
} from '../../../../lib/types';


export interface CreateTarget {
  type: CategoryNodeType;
  parentId?: number;       // category_id when creating style, style_id when creating type
  grandparentId?: number;  // category_id when creating type (for breadcrumb)
}

export interface CreateFormProps {
  target: CreateTarget;
  allColors: PartColor[];
  onCancel: () => void;
  onCreated: (type: CategoryNodeType, id: number, parentId?: number) => void;
}

export function CreateForm({ target, allColors, onCancel, onCreated }: CreateFormProps) {
  const queryClient = useQueryClient();
  const [name, setName] = useState('');
  const [description, setDescription] = useState('');
  const [imageUrl, setImageUrl] = useState('');
  const [hexCode, setHexCode] = useState('#FFFFFF');

  const label =
    target.type === 'category' ? 'Category' :
    target.type === 'style' ? 'Style' :
    target.type === 'type' ? 'Type' : 'Color';

  const createCatMutation = useMutation({
    mutationFn: createCategory,
    onSuccess: (data) => {
      queryClient.invalidateQueries({ queryKey: ['categories'] });
      onCreated('category', data.id);
    },
  });

  const createStyleMutation = useMutation({
    mutationFn: createStyle,
    onSuccess: (data) => {
      queryClient.invalidateQueries({ queryKey: ['styles', target.parentId] });
      queryClient.invalidateQueries({ queryKey: ['categories'] });
      onCreated('style', data.id, target.parentId);
    },
  });

  const createTypeMutation = useMutation({
    mutationFn: createType,
    onSuccess: (data) => {
      queryClient.invalidateQueries({ queryKey: ['types', target.parentId] });
      queryClient.invalidateQueries({ queryKey: ['styles'] });
      onCreated('type', data.id, target.parentId);
    },
  });

  const createColorMutation = useMutation({
    mutationFn: createColor,
    onSuccess: (data) => {
      queryClient.invalidateQueries({ queryKey: ['colors'] });
      onCreated('color', data.id);
    },
  });

  const isPending =
    createCatMutation.isPending || createStyleMutation.isPending ||
    createTypeMutation.isPending || createColorMutation.isPending;

  const error =
    createCatMutation.error || createStyleMutation.error ||
    createTypeMutation.error || createColorMutation.error;

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    const base = {
      name,
      description: description || undefined,
      image_url: imageUrl || undefined,
    };

    switch (target.type) {
      case 'category':
        createCatMutation.mutate(base as PartCategoryCreate);
        break;
      case 'style':
        createStyleMutation.mutate({
          ...base,
          category_id: target.parentId!,
        } as PartStyleCreate);
        break;
      case 'type':
        createTypeMutation.mutate({
          ...base,
          style_id: target.parentId!,
        } as PartTypeCreate);
        break;
      case 'color':
        createColorMutation.mutate({
          name,
          hex_code: hexCode || undefined,
        } as PartColorCreate);
        break;
    }
  };

  return (
    <div className="flex flex-col h-full">
      <div className="px-6 py-4 border-b border-gray-200 dark:border-gray-700 bg-gray-50 dark:bg-gray-800/80">
        <h3 className="text-lg font-semibold text-gray-900 dark:text-gray-100">
          New {label}
        </h3>
        {target.type === 'style' && (
          <p className="text-sm text-gray-500 dark:text-gray-400 mt-0.5">
            Adding to category
          </p>
        )}
        {target.type === 'type' && (
          <p className="text-sm text-gray-500 dark:text-gray-400 mt-0.5">
            Adding to style
          </p>
        )}
      </div>

      <form onSubmit={handleSubmit} className="flex-1 overflow-y-auto p-6 space-y-4">
        <Input
          label={`${label} Name *`}
          value={name}
          onChange={(e) => setName(e.target.value)}
          placeholder={`e.g. ${
            target.type === 'category' ? 'Outlet' :
            target.type === 'style' ? 'Decora' :
            target.type === 'type' ? 'GFI' : 'White'
          }`}
          required
          autoFocus
        />

        {target.type !== 'color' && (
          <>
            <div className="space-y-1.5">
              <label className="block text-sm font-medium text-gray-700 dark:text-gray-300">
                Description
              </label>
              <textarea
                className="w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm min-h-[60px]"
                value={description}
                onChange={(e) => setDescription(e.target.value)}
                placeholder="Optional description..."
              />
            </div>

            <Input
              label="Image URL"
              value={imageUrl}
              onChange={(e) => setImageUrl(e.target.value)}
              placeholder="https://..."
              type="url"
              hint="Optional — add product images later"
            />
          </>
        )}

        {target.type === 'color' && (
          <div className="space-y-1.5">
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300">
              Hex Color Code
            </label>
            <div className="flex items-center gap-3">
              <input
                type="color"
                value={hexCode}
                onChange={(e) => setHexCode(e.target.value)}
                className="w-10 h-10 rounded-lg border border-gray-300 dark:border-gray-600 cursor-pointer"
              />
              <Input
                value={hexCode}
                onChange={(e) => setHexCode(e.target.value)}
                placeholder="#FFFFFF"
                className="font-mono"
              />
            </div>
          </div>
        )}

        {error && (
          <p className="text-red-500 text-sm">
            {(error as any)?.response?.data?.detail ?? `Failed to create ${label.toLowerCase()}.`}
          </p>
        )}

        <div className="flex justify-end gap-2 pt-4 border-t border-gray-200 dark:border-gray-700">
          <Button variant="secondary" type="button" onClick={onCancel}>
            Cancel
          </Button>
          <Button type="submit" isLoading={isPending} icon={<Plus className="h-4 w-4" />}>
            Create {label}
          </Button>
        </div>
      </form>
    </div>
  );
}
