-- =============================================================
-- MIGRATION 027: Phase 10 Permissions & Default Schedules
-- =============================================================
-- Seeds 9 new permission keys for Contacts + Scheduling.
-- Creates default Mon-Fri 07:00-15:30 schedules for all active users.
-- =============================================================


-- ═══════════════════════════════════════════════════════════════
-- PERMISSIONS
-- ═══════════════════════════════════════════════════════════════

-- ── Contacts / Customers ──

-- view_customers: See customer list, details, contacts
INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key)
SELECT id, 'view_customers' FROM hats WHERE name IN ('Admin', 'Manager', 'Lead', 'Worker');

-- manage_customers: Create/edit/deactivate customers, manage contacts
INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key)
SELECT id, 'manage_customers' FROM hats WHERE name IN ('Admin', 'Manager');

-- ── Contacts / Contractors ──

-- view_contractors: See GC list, details, contacts
INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key)
SELECT id, 'view_contractors' FROM hats WHERE name IN ('Admin', 'Manager', 'Lead', 'Worker');

-- manage_contractors: Create/edit/deactivate GCs, manage contacts
INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key)
SELECT id, 'manage_contractors' FROM hats WHERE name IN ('Admin', 'Manager');

-- ── Scheduling ──

-- view_schedule: See calendar, dispatch board, schedules
INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key)
SELECT id, 'view_schedule' FROM hats WHERE name IN ('Admin', 'Manager', 'Lead', 'Worker');

-- manage_schedule: Edit employee default schedules
INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key)
SELECT id, 'manage_schedule' FROM hats WHERE name IN ('Admin', 'Manager');

-- request_time_off: Submit time-off requests (everyone)
INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key)
SELECT id, 'request_time_off' FROM hats WHERE name IN ('Admin', 'Manager', 'Lead', 'Worker');

-- approve_time_off: Approve/deny time-off requests
INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key)
SELECT id, 'approve_time_off' FROM hats WHERE name IN ('Admin', 'Manager');

-- dispatch_employees: Assign employees to jobs, manage sub schedules
INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key)
SELECT id, 'dispatch_employees' FROM hats WHERE name IN ('Admin', 'Manager');


-- ═══════════════════════════════════════════════════════════════
-- DEFAULT SCHEDULES — Mon-Fri 07:00-15:30
-- ═══════════════════════════════════════════════════════════════
-- Create default working schedules for all currently active users.
-- day_of_week: 0=Sun, 1=Mon, 2=Tue, 3=Wed, 4=Thu, 5=Fri, 6=Sat
-- Mon-Fri = working days (1-5), Sat-Sun = off (0, 6).

-- Monday
INSERT OR IGNORE INTO employee_default_schedules (user_id, day_of_week, start_time, end_time, is_working_day)
SELECT id, 1, '07:00', '15:30', 1 FROM users WHERE is_active = 1;

-- Tuesday
INSERT OR IGNORE INTO employee_default_schedules (user_id, day_of_week, start_time, end_time, is_working_day)
SELECT id, 2, '07:00', '15:30', 1 FROM users WHERE is_active = 1;

-- Wednesday
INSERT OR IGNORE INTO employee_default_schedules (user_id, day_of_week, start_time, end_time, is_working_day)
SELECT id, 3, '07:00', '15:30', 1 FROM users WHERE is_active = 1;

-- Thursday
INSERT OR IGNORE INTO employee_default_schedules (user_id, day_of_week, start_time, end_time, is_working_day)
SELECT id, 4, '07:00', '15:30', 1 FROM users WHERE is_active = 1;

-- Friday
INSERT OR IGNORE INTO employee_default_schedules (user_id, day_of_week, start_time, end_time, is_working_day)
SELECT id, 5, '07:00', '15:30', 1 FROM users WHERE is_active = 1;

-- Saturday (off)
INSERT OR IGNORE INTO employee_default_schedules (user_id, day_of_week, start_time, end_time, is_working_day)
SELECT id, 6, '07:00', '15:30', 0 FROM users WHERE is_active = 1;

-- Sunday (off)
INSERT OR IGNORE INTO employee_default_schedules (user_id, day_of_week, start_time, end_time, is_working_day)
SELECT id, 0, '07:00', '15:30', 0 FROM users WHERE is_active = 1;
