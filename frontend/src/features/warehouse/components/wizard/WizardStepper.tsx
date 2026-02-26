/**
 * WizardStepper — horizontal progress indicator for the movement wizard.
 *
 * Shows step numbers/labels with connecting lines.
 * Completed steps get a checkmark, current step is highlighted.
 */

import { Check } from 'lucide-react';
import { cn } from '../../../../lib/utils';
import type { WizardStep } from '../../stores/movement-wizard-store';

interface WizardStepperProps {
  steps: WizardStep[];
  currentStep: WizardStep;
  labels: Record<WizardStep, string>;
}

export function WizardStepper({ steps, currentStep, labels }: WizardStepperProps) {
  const currentIndex = steps.indexOf(currentStep);

  return (
    <div className="flex items-center justify-between w-full">
      {steps.map((step, idx) => {
        const isCompleted = idx < currentIndex;
        const isCurrent = step === currentStep;
        const isLast = idx === steps.length - 1;

        return (
          <div key={step} className="flex items-center flex-1 last:flex-none">
            {/* Step circle + label */}
            <div className="flex flex-col items-center gap-1">
              <div
                className={cn(
                  'flex items-center justify-center w-8 h-8 rounded-full text-sm font-medium transition-colors',
                  isCompleted &&
                    'bg-primary-500 text-white',
                  isCurrent &&
                    'bg-primary-500 text-white ring-4 ring-primary-100 dark:ring-primary-900',
                  !isCompleted &&
                    !isCurrent &&
                    'bg-gray-100 text-gray-500 dark:bg-gray-700 dark:text-gray-400',
                )}
              >
                {isCompleted ? (
                  <Check className="h-4 w-4" />
                ) : (
                  idx + 1
                )}
              </div>
              <span
                className={cn(
                  'text-xs whitespace-nowrap hidden sm:block',
                  isCurrent
                    ? 'text-primary-600 dark:text-primary-400 font-medium'
                    : 'text-gray-500 dark:text-gray-400',
                )}
              >
                {labels[step]}
              </span>
            </div>

            {/* Connecting line */}
            {!isLast && (
              <div className="flex-1 mx-2 h-0.5">
                <div
                  className={cn(
                    'h-full rounded-full transition-colors',
                    idx < currentIndex
                      ? 'bg-primary-500'
                      : 'bg-gray-200 dark:bg-gray-700',
                  )}
                />
              </div>
            )}
          </div>
        );
      })}
    </div>
  );
}
