/**
 * ThemesPage — theme and appearance settings.
 *
 * Functional page. Allows switching between Light, Dark, and System theme modes.
 * Uses useThemeStore for state management and DOM application.
 */

import { Sun, Moon, Monitor } from 'lucide-react';
import { Button } from '../../../components/ui/Button';
import { Card, CardHeader } from '../../../components/ui/Card';
import { useThemeStore } from '../../../stores/theme-store';

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

export function ThemesPage() {
  const { mode, setMode, isDark } = useThemeStore();

  return (
    <div className="mx-auto max-w-2xl space-y-6">
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
                onClick={() => setMode(option.mode)}
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

      {/* Current state indicator */}
      <Card>
        <div className="flex items-center justify-between">
          <div>
            <p className="text-sm font-medium text-gray-500 dark:text-gray-400">
              Current resolved theme
            </p>
            <p className="text-lg font-semibold text-gray-900 dark:text-gray-100">
              {isDark ? 'Dark' : 'Light'} mode active
            </p>
          </div>
          <div className="flex gap-2">
            <Button
              variant="secondary"
              size="sm"
              icon={<Sun className="h-4 w-4" />}
              onClick={() => setMode('light')}
            >
              Light
            </Button>
            <Button
              variant="secondary"
              size="sm"
              icon={<Moon className="h-4 w-4" />}
              onClick={() => setMode('dark')}
            >
              Dark
            </Button>
            <Button
              variant="secondary"
              size="sm"
              icon={<Monitor className="h-4 w-4" />}
              onClick={() => setMode('system')}
            >
              System
            </Button>
          </div>
        </div>
      </Card>
    </div>
  );
}
