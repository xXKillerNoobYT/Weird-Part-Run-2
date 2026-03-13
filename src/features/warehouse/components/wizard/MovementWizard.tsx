/**
 * MovementWizard — hybrid modal (desktop) / full-page (mobile) container.
 *
 * Renders the active wizard step, progress stepper, and navigation buttons.
 * Handles the resume prompt when localStorage has unsaved wizard state.
 */

import { useEffect } from 'react';
import {
  X, ArrowLeft, ArrowRight, AlertTriangle,
} from 'lucide-react';
import { Button } from '../../../../components/ui/Button';
import { cn } from '../../../../lib/utils';
import { useMovementWizardStore, type WizardStep } from '../../stores/movement-wizard-store';
import { WizardStepper } from './WizardStepper';
import { StepLocations } from './steps/StepLocations';
import { StepSelectParts } from './steps/StepSelectParts';
import { StepQuantities } from './steps/StepQuantities';
import { StepVerification } from './steps/StepVerification';
import { StepNotesReason } from './steps/StepNotesReason';
import { StepPreview } from './steps/StepPreview';
import { StepExecute } from './steps/StepExecute';

const STEP_LABELS: Record<WizardStep, string> = {
  1: 'Locations',
  2: 'Select Parts',
  3: 'Quantities',
  4: 'Verification',
  5: 'Notes & Reason',
  6: 'Preview',
  7: 'Execute',
};

export function MovementWizard() {
  const {
    isOpen,
    currentStep,
    hasUnsavedState,
    selectedParts,
    isVerificationRequired,
    canAdvanceFromStep,
    nextStep,
    prevStep,
    close,
    discardAndClose,
    resumeSession,
    executeResult,
  } = useMovementWizardStore();

  // Prevent body scroll when wizard is open
  useEffect(() => {
    if (isOpen) {
      document.body.style.overflow = 'hidden';
    }
    return () => {
      document.body.style.overflow = '';
    };
  }, [isOpen]);

  if (!isOpen) return null;

  // Resume prompt: we have unsaved state from a previous session
  if (hasUnsavedState && selectedParts.length > 0) {
    return (
      <WizardShell onClose={discardAndClose}>
        <div className="flex flex-col items-center justify-center min-h-[300px] gap-6 p-8">
          <div className="p-4 rounded-full bg-amber-50 dark:bg-amber-900/30">
            <AlertTriangle className="h-10 w-10 text-amber-500" />
          </div>
          <div className="text-center">
            <h3 className="text-lg font-semibold text-gray-900 dark:text-gray-100 mb-2">
              Resume Previous Movement?
            </h3>
            <p className="text-sm text-gray-500 dark:text-gray-400 max-w-md">
              You have an incomplete movement with {selectedParts.length} part
              {selectedParts.length !== 1 ? 's' : ''} selected.
              Would you like to continue where you left off?
            </p>
          </div>
          <div className="flex gap-3">
            <Button variant="secondary" onClick={discardAndClose}>
              Discard & Start New
            </Button>
            <Button onClick={resumeSession}>
              Resume Movement
            </Button>
          </div>
        </div>
      </WizardShell>
    );
  }

  // Determine which steps to show (skip verification if not required)
  const verificationRequired = isVerificationRequired();
  const activeSteps: WizardStep[] = verificationRequired
    ? [1, 2, 3, 4, 5, 6, 7]
    : [1, 2, 3, 5, 6, 7];

  const canGoNext = canAdvanceFromStep(currentStep);
  const isLastStep = currentStep === 7;
  const isFirstStep = currentStep === 1;

  return (
    <WizardShell onClose={close}>
      {/* Stepper */}
      <div className="px-4 sm:px-6 pt-4 pb-2">
        <WizardStepper
          steps={activeSteps}
          currentStep={currentStep}
          labels={STEP_LABELS}
        />
      </div>

      {/* Step Content */}
      <div className="flex-1 overflow-y-auto px-4 sm:px-6 py-4">
        {currentStep === 1 && <StepLocations />}
        {currentStep === 2 && <StepSelectParts />}
        {currentStep === 3 && <StepQuantities />}
        {currentStep === 4 && <StepVerification />}
        {currentStep === 5 && <StepNotesReason />}
        {currentStep === 6 && <StepPreview />}
        {currentStep === 7 && <StepExecute />}
      </div>

      {/* Navigation Footer */}
      {!isLastStep && (
        <div className="flex items-center justify-between px-4 sm:px-6 py-4 border-t border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800">
          <Button
            variant="ghost"
            icon={<ArrowLeft className="h-4 w-4" />}
            onClick={prevStep}
            disabled={isFirstStep}
          >
            Back
          </Button>

          <span className="text-sm text-gray-500 dark:text-gray-400">
            Step {activeSteps.indexOf(currentStep) + 1} of {activeSteps.length}
          </span>

          <Button
            iconRight={<ArrowRight className="h-4 w-4" />}
            onClick={nextStep}
            disabled={!canGoNext}
          >
            {currentStep === 6 ? 'Confirm & Execute' : 'Next'}
          </Button>
        </div>
      )}

      {/* Close button on execute step (after completion) */}
      {isLastStep && executeResult && (
        <div className="flex justify-center px-4 sm:px-6 py-4 border-t border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800">
          <Button onClick={discardAndClose}>
            Done
          </Button>
        </div>
      )}
    </WizardShell>
  );
}

// ── Shell: modal on desktop, full-page on mobile ────────────────

function WizardShell({
  onClose,
  children,
}: {
  onClose: () => void;
  children: React.ReactNode;
}) {
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center">
      {/* Backdrop (desktop) */}
      <div
        className="absolute inset-0 bg-black/50 backdrop-blur-sm hidden sm:block"
        onClick={onClose}
      />

      {/* Container: full-screen on mobile, modal on desktop */}
      <div
        className={cn(
          'relative flex flex-col bg-white dark:bg-gray-800',
          // Mobile: full-screen
          'w-full h-full',
          // Desktop: modal sizing
          'sm:w-[90vw] sm:max-w-3xl sm:h-auto sm:max-h-[90vh] sm:rounded-2xl sm:shadow-2xl',
        )}
      >
        {/* Header */}
        <div className="flex items-center justify-between px-4 sm:px-6 py-3 border-b border-gray-200 dark:border-gray-700">
          <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-100">
            Stock Movement
          </h2>
          <button
            onClick={onClose}
            className="p-2 rounded-lg text-gray-400 hover:text-gray-600 hover:bg-gray-100 dark:hover:text-gray-300 dark:hover:bg-gray-700 transition-colors"
          >
            <X className="h-5 w-5" />
          </button>
        </div>

        {children}
      </div>
    </div>
  );
}
