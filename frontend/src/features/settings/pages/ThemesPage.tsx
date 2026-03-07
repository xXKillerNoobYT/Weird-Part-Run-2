/**
 * ThemesPage — theme and appearance settings.
 *
 * Allows switching between Light, Dark, and System theme modes.
 * Also exposes primary accent color and font family customization.
 * Changes are persisted to the backend via the settings API.
 */

import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Sun, Moon, Monitor, Palette, Type } from 'lucide-react';
import { Card, CardHeader } from '../../../components/ui/Card';
import { useThemeStore } from '../../../stores/theme-store';
import { getTheme, updateTheme } from '../../../api/settings';
import { toast } from '../../../lib/toast';

const themeOptions = [
  {
    mode: 'light' as const,
    label: 'Light',
    description: 'Always use light mode',
    icon: <Sun className="h-5 w-5" />,
  },
  {
    mode: 'dark' as const,
    label: 'Dark',
    description: 'Always use dark mode',
    icon: <Moon className="h-5 w-5" />,
  },
  {
    mode: 'system' as const,
    label: 'System',
    description: 'Follow your operating system preference',
    icon: <Monitor className="h-5 w-5" />,
  },
];

const COLOR_PRESETS = [
  { label: 'Blue', value: '#3B82F6' },
  { label: 'Indigo', value: '#6366F1' },
  { label: 'Emerald', value: '#10B981' },
  { label: 'Amber', value: '#F59E0B' },
  { label: 'Rose', value: '#F43F5E' },
  { label: 'Purple', value: '#8B5CF6' },
  { label: 'Teal', value: '#14B8A6' },
  { label: 'Orange', value: '#F97316' },
];

const FONT_OPTIONS = [
  { label: 'Inter (Default)', value: 'Inter' },
  { label: 'System UI', value: 'system-ui' },
  { label: 'Roboto', value: 'Roboto' },
  { label: 'Open Sans', value: 'Open Sans' },
  { label: 'Nunito', value: 'Nunito' },
];

export function ThemesPage() {
  const { mode, setMode, isDark } = useThemeStore();
  const queryClient = useQueryClient();

  // Load saved theme settings from backend
  const themeQuery = useQuery({
    queryKey: ['settings', 'theme'],
    queryFn: getTheme,
    staleTime: 60_000,
  });

  const [primaryColor, setPrimaryColor] = useState<string | null>(null);
  const [fontFamily, setFontFamily] = useState<string | null>(null);

  // Use server values as defaults until user changes them
  const currentColor = primaryColor ?? themeQuery.data?.primary_color ?? '#3B82F6';
  const currentFont = fontFamily ?? themeQuery.data?.font_family ?? 'Inter';

  const saveMut = useMutation({
    mutationFn: (params: { color?: string; font?: string; themeMode?: string }) =>
      updateTheme({
        theme_mode: params.themeMode ?? mode,
        primary_color: params.color ?? currentColor,
        font_family: params.font ?? currentFont,
      }),
    onSuccess: (data) => {
      queryClient.setQueryData(['settings', 'theme'], data);
      toast.success('Theme saved');
    },
    onError: () => toast.error('Failed to save theme'),
  });

  const handleModeChange = (newMode: 'light' | 'dark' | 'system') => {
    setMode(newMode);
    saveMut.mutate({ themeMode: newMode });
  };

  const handleColorChange = (color: string) => {
    setPrimaryColor(color);
    saveMut.mutate({ color });
  };

  const handleFontChange = (font: string) => {
    setFontFamily(font);
    saveMut.mutate({ font });
  };

  return (
    <div className="mx-auto max-w-2xl space-y-6">
      {/* Theme Mode */}
      <Card>
        <CardHeader
          title="Appearance"
          subtitle="Choose how Wired Part looks to you"
        />

        <div className="space-y-3">
          {themeOptions.map((option) => {
            const isActive = mode === option.mode;

            return (
              <button
                key={option.mode}
                onClick={() => handleModeChange(option.mode)}
                className={`flex w-full items-center gap-4 rounded-lg border-2 p-4 text-left transition-colors ${
                  isActive
                    ? 'border-primary-500 bg-primary-50 dark:bg-primary-900/20'
                    : 'border-gray-200 hover:border-gray-300 dark:border-gray-700 dark:hover:border-gray-600'
                }`}
              >
                <div
                  className={`flex h-10 w-10 items-center justify-center rounded-lg ${
                    isActive
                      ? 'bg-primary-500 text-white'
                      : 'bg-gray-100 text-gray-500 dark:bg-gray-800 dark:text-gray-400'
                  }`}
                >
                  {option.icon}
                </div>
                <div className="flex-1">
                  <p
                    className={`font-medium ${
                      isActive
                        ? 'text-primary-700 dark:text-primary-300'
                        : 'text-gray-900 dark:text-gray-100'
                    }`}
                  >
                    {option.label}
                  </p>
                  <p className="text-sm text-gray-500 dark:text-gray-400">
                    {option.description}
                  </p>
                </div>
                {isActive && (
                  <div className="flex h-6 w-6 items-center justify-center rounded-full bg-primary-500 text-white">
                    <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={3}>
                      <path strokeLinecap="round" strokeLinejoin="round" d="M5 13l4 4L19 7" />
                    </svg>
                  </div>
                )}
              </button>
            );
          })}
        </div>
      </Card>

      {/* Accent Color */}
      <Card>
        <CardHeader
          title="Accent Color"
          subtitle="Choose the primary accent color used across the interface"
        />

        <div className="flex items-center gap-3 flex-wrap">
          {COLOR_PRESETS.map((preset) => (
            <button
              key={preset.value}
              onClick={() => handleColorChange(preset.value)}
              title={preset.label}
              className={`relative h-10 w-10 rounded-full border-2 transition-all ${
                currentColor === preset.value
                  ? 'border-gray-900 dark:border-white scale-110'
                  : 'border-transparent hover:scale-105'
              }`}
              style={{ backgroundColor: preset.value }}
            >
              {currentColor === preset.value && (
                <svg
                  className="absolute inset-0 m-auto h-5 w-5 text-white drop-shadow-sm"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke="currentColor"
                  strokeWidth={3}
                >
                  <path strokeLinecap="round" strokeLinejoin="round" d="M5 13l4 4L19 7" />
                </svg>
              )}
            </button>
          ))}

          {/* Custom color input */}
          <div className="flex items-center gap-2 ml-2">
            <Palette className="h-4 w-4 text-gray-400" />
            <input
              type="color"
              value={currentColor}
              onChange={(e) => handleColorChange(e.target.value)}
              className="h-10 w-10 rounded-lg border border-gray-300 dark:border-gray-600 cursor-pointer bg-transparent p-0.5"
              title="Custom color"
            />
          </div>
        </div>

        <p className="mt-3 text-xs text-gray-500 dark:text-gray-400">
          Current: <code className="px-1 py-0.5 rounded bg-gray-100 dark:bg-gray-700">{currentColor}</code>
        </p>
      </Card>

      {/* Font Family */}
      <Card>
        <CardHeader
          title="Font Family"
          subtitle="Choose the primary font used across the interface"
        />

        <div className="flex items-center gap-3">
          <Type className="h-5 w-5 text-gray-400 flex-shrink-0" />
          <select
            value={currentFont}
            onChange={(e) => handleFontChange(e.target.value)}
            className="flex-1 rounded-lg border border-gray-300 dark:border-gray-600
                       bg-white dark:bg-gray-700 px-3 py-2.5 text-sm
                       text-gray-900 dark:text-gray-100 min-h-[44px]"
          >
            {FONT_OPTIONS.map((f) => (
              <option key={f.value} value={f.value}>
                {f.label}
              </option>
            ))}
          </select>
        </div>

        <p className="mt-3 text-sm text-gray-500 dark:text-gray-400" style={{ fontFamily: currentFont }}>
          The quick brown fox jumps over the lazy dog
        </p>
      </Card>

      {/* Current state indicator */}
      <Card>
        <div className="flex items-center justify-between flex-wrap gap-3">
          <div>
            <p className="text-sm font-medium text-gray-500 dark:text-gray-400">
              Current resolved theme
            </p>
            <p className="text-lg font-semibold text-gray-900 dark:text-gray-100">
              {isDark ? 'Dark' : 'Light'} mode active
            </p>
          </div>
          <div
            className="h-8 w-8 rounded-full border-2 border-gray-200 dark:border-gray-600"
            style={{ backgroundColor: currentColor }}
            title={`Accent: ${currentColor}`}
          />
        </div>
      </Card>
    </div>
  );
}
