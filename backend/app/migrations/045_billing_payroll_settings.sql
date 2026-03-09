-- Migration 045: Billing & Payroll Configuration Settings
-- Seeds configurable settings for billing cycle, pay period, and drive-time warnings.
-- These drive the fast-filter buttons on Pre-Billing, Timesheets, and Daily Reports pages.

-- ─── Billing Settings ───────────────────────────────────────────
-- billing_cycle_start: day-of-month the billing cycle begins (1-28)
-- billing_cycle_type: 'monthly' | 'biweekly' | 'weekly'
INSERT OR IGNORE INTO settings (key, value, category) VALUES
    ('billing_cycle_start',     '1',            'billing'),
    ('billing_cycle_type',      '"monthly"',    'billing');

-- ─── Payroll Settings ───────────────────────────────────────────
-- pay_period_type: 'weekly' | 'biweekly' | 'semimonthly' | 'monthly'
-- pay_period_start_day: 1=Monday .. 7=Sunday (for weekly/biweekly)
INSERT OR IGNORE INTO settings (key, value, category) VALUES
    ('pay_period_type',         '"weekly"',     'payroll'),
    ('pay_period_start_day',    '1',            'payroll');

-- ─── Report Threshold Settings ──────────────────────────────────
-- max_drive_ratio: drive-time / total-time threshold for warning badge (0.0–1.0)
-- max_drive_ratio_critical: threshold for danger badge
INSERT OR IGNORE INTO settings (key, value, category) VALUES
    ('max_drive_ratio',             '0.33',     'reports'),
    ('max_drive_ratio_critical',    '0.50',     'reports');
