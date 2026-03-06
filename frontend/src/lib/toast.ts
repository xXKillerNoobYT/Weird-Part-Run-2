/**
 * Lightweight toast notification utility.
 *
 * Drop-in replacement for react-hot-toast's basic API:
 *   toast.success('message')
 *   toast.error('message')
 *   toast('message')
 *
 * Renders small banners at the top-right of the viewport with auto-dismiss.
 * Supports dark mode via Tailwind-compatible inline styles.
 * No external dependencies — pure DOM manipulation.
 */

let containerId = '__toast-container';

function getContainer(): HTMLDivElement {
  let container = document.getElementById(containerId) as HTMLDivElement | null;
  if (!container) {
    container = document.createElement('div');
    container.id = containerId;
    Object.assign(container.style, {
      position: 'fixed',
      top: '16px',
      right: '16px',
      zIndex: '9999',
      display: 'flex',
      flexDirection: 'column',
      gap: '8px',
      pointerEvents: 'none',
    });
    document.body.appendChild(container);
  }
  return container;
}

interface ToastOptions {
  duration?: number;
}

function showToast(
  message: string,
  variant: 'default' | 'success' | 'error' = 'default',
  options: ToastOptions = {},
) {
  const duration = options.duration ?? 3500;
  const container = getContainer();

  const el = document.createElement('div');
  el.textContent = message;

  // Determine colors based on variant and current theme
  const isDark = document.documentElement.classList.contains('dark');

  const colors: Record<string, { bg: string; text: string; border: string }> = {
    default: {
      bg: isDark ? '#1f2937' : '#ffffff',
      text: isDark ? '#e5e7eb' : '#1f2937',
      border: isDark ? '#374151' : '#e5e7eb',
    },
    success: {
      bg: isDark ? '#064e3b' : '#ecfdf5',
      text: isDark ? '#6ee7b7' : '#065f46',
      border: isDark ? '#065f46' : '#a7f3d0',
    },
    error: {
      bg: isDark ? '#7f1d1d' : '#fef2f2',
      text: isDark ? '#fca5a5' : '#991b1b',
      border: isDark ? '#991b1b' : '#fecaca',
    },
  };

  const c = colors[variant];

  Object.assign(el.style, {
    background: c.bg,
    color: c.text,
    border: `1px solid ${c.border}`,
    borderRadius: '8px',
    padding: '10px 16px',
    fontSize: '14px',
    fontWeight: '500',
    boxShadow: '0 4px 12px rgba(0,0,0,0.15)',
    pointerEvents: 'auto',
    cursor: 'pointer',
    maxWidth: '360px',
    wordBreak: 'break-word' as const,
    opacity: '0',
    transform: 'translateX(100%)',
    transition: 'opacity 0.25s ease, transform 0.25s ease',
  });

  container.appendChild(el);

  // Animate in
  requestAnimationFrame(() => {
    el.style.opacity = '1';
    el.style.transform = 'translateX(0)';
  });

  // Click to dismiss early
  el.addEventListener('click', () => dismiss(el));

  // Auto-dismiss
  setTimeout(() => dismiss(el), duration);
}

function dismiss(el: HTMLDivElement) {
  el.style.opacity = '0';
  el.style.transform = 'translateX(100%)';
  setTimeout(() => el.remove(), 300);
}

// ── Public API (matches react-hot-toast surface) ─────────────────

function toast(message: string, options?: ToastOptions) {
  showToast(message, 'default', options);
}

toast.success = (message: string, options?: ToastOptions) => {
  showToast(message, 'success', options);
};

toast.error = (message: string, options?: ToastOptions) => {
  showToast(message, 'error', options);
};

export default toast;
