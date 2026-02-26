/**
 * PinLoginForm — PIN entry screen for user authentication.
 *
 * Features:
 * - 4-6 digit PIN input with large touch-friendly digit boxes
 * - Auto-submit when PIN length reaches 4+ digits
 * - Back button to return to user picker
 * - Error display with shake animation on wrong PIN
 * - Loading state during verification
 */

import { useState, useRef, useEffect } from 'react';
import { ArrowLeft, UserCircle, Lock } from 'lucide-react';
import { pinLogin } from '../../api/auth';
import { Button } from '../ui/Button';

interface PinLoginFormProps {
  userId: number;
  userName: string;
  deviceFingerprint: string;
  deviceName: string;
  onSuccess: (token: string) => void;
  onBack: () => void;
}

export function PinLoginForm({
  userId,
  userName,
  deviceFingerprint,
  deviceName,
  onSuccess,
  onBack,
}: PinLoginFormProps) {
  const [pin, setPin] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [shake, setShake] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);

  // Focus the hidden input on mount
  useEffect(() => {
    inputRef.current?.focus();
  }, []);

  // Auto-submit when PIN is 4+ digits
  useEffect(() => {
    if (pin.length >= 4 && !loading) {
      handleSubmit();
    }
  }, [pin]);

  async function handleSubmit() {
    if (pin.length < 4) return;
    setLoading(true);
    setError(null);

    try {
      const result = await pinLogin(userId, pin, deviceFingerprint, deviceName);
      onSuccess(result.access_token);
    } catch (err: any) {
      const msg = err.response?.data?.detail ?? 'Invalid PIN. Try again.';
      setError(msg);
      setPin('');
      setShake(true);
      setTimeout(() => setShake(false), 500);
      inputRef.current?.focus();
    } finally {
      setLoading(false);
    }
  }

  function handleKeyDown(e: React.KeyboardEvent) {
    // Only allow digits and control keys
    if (e.key === 'Backspace' || e.key === 'Delete' || e.key === 'Tab') return;
    if (e.key === 'Enter' && pin.length >= 4) {
      handleSubmit();
      return;
    }
    if (!/^\d$/.test(e.key)) {
      e.preventDefault();
    }
  }

  function handleChange(e: React.ChangeEvent<HTMLInputElement>) {
    const value = e.target.value.replace(/\D/g, '').slice(0, 6);
    setPin(value);
    setError(null);
  }

  return (
    <div className="min-h-screen bg-surface-secondary flex flex-col items-center justify-center p-6">
      {/* Back button */}
      <button
        onClick={onBack}
        className="absolute top-6 left-6 flex items-center gap-2 text-sm text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-300 transition-colors"
      >
        <ArrowLeft className="h-4 w-4" />
        Back
      </button>

      {/* User avatar + name */}
      <div className="flex flex-col items-center mb-8">
        <div className="w-20 h-20 rounded-full bg-primary-100 dark:bg-primary-900 flex items-center justify-center mb-4">
          <UserCircle className="w-14 h-14 text-primary-500" />
        </div>
        <h2 className="text-xl font-semibold text-gray-900 dark:text-gray-100">
          {userName}
        </h2>
        <p className="text-sm text-gray-500 dark:text-gray-400 mt-1 flex items-center gap-1">
          <Lock className="h-3.5 w-3.5" />
          Enter your PIN
        </p>
      </div>

      {/* PIN Dots Display */}
      <div className={`flex gap-3 mb-6 ${shake ? 'animate-shake' : ''}`}>
        {[0, 1, 2, 3].map((i) => (
          <div
            key={i}
            className={`w-4 h-4 rounded-full transition-all duration-150 ${
              i < pin.length
                ? 'bg-primary-500 scale-110'
                : 'bg-gray-300 dark:bg-gray-600'
            }`}
          />
        ))}
        {pin.length > 4 &&
          Array.from({ length: pin.length - 4 }).map((_, i) => (
            <div
              key={`extra-${i}`}
              className="w-4 h-4 rounded-full bg-primary-500 scale-110 transition-all duration-150"
            />
          ))}
      </div>

      {/* Hidden input for keyboard capture */}
      <input
        ref={inputRef}
        type="password"
        inputMode="numeric"
        pattern="[0-9]*"
        value={pin}
        onChange={handleChange}
        onKeyDown={handleKeyDown}
        className="sr-only"
        autoComplete="off"
        aria-label="PIN input"
      />

      {/* Tap to focus (for mobile) */}
      <button
        onClick={() => inputRef.current?.focus()}
        className="text-sm text-gray-500 dark:text-gray-400 mb-4"
      >
        Tap here if keyboard doesn't appear
      </button>

      {/* Error */}
      {error && (
        <p className="text-sm text-red-500 mb-4">{error}</p>
      )}

      {/* Submit button (backup for 5-6 digit PINs) */}
      {pin.length >= 4 && (
        <Button
          onClick={handleSubmit}
          isLoading={loading}
          size="lg"
          className="min-w-[200px]"
        >
          Sign In
        </Button>
      )}

      <style>{`
        @keyframes shake {
          0%, 100% { transform: translateX(0); }
          20%, 60% { transform: translateX(-8px); }
          40%, 80% { transform: translateX(8px); }
        }
        .animate-shake {
          animation: shake 0.4s ease-in-out;
        }
      `}</style>
    </div>
  );
}
