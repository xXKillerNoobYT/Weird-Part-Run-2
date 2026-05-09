# Auth/Sync Security Observability Guardrails

## Event Coverage

`security_observability_events` records security-relevant auth/sync anomalies with typed events:

- `auth_failed`: incorrect PIN attempts
- `auth_lockout`: active lockout or lockout-triggering auth failures
- `token_rejected`: invalid/expired token profile lookups
- `sync_replay_rejected`: replay header failures, stale timestamps, nonce reuse
- `sync_auth_rejected`: sync auth rejects (company mismatch, cert required/rejected)
- `sync_dead_letter`: sync apply failures sent to incident triage path

## Query and Dashboard Views

Use these baseline SQL queries for a staging dashboard:

```sql
-- 15-minute rolling auth failures/lockouts
SELECT event_type, COUNT(*) AS count
FROM security_observability_events
WHERE event_type IN ('auth_failed', 'auth_lockout')
  AND created_at >= datetime('now', '-15 minutes')
GROUP BY event_type;

-- Replay or sync auth rejects in the last hour
SELECT event_type, COUNT(*) AS count
FROM security_observability_events
WHERE event_type IN ('sync_replay_rejected', 'sync_auth_rejected')
  AND created_at >= datetime('now', '-1 hour')
GROUP BY event_type;

-- Most recent critical security events with trace context
SELECT id, event_type, source, outcome, trace_id, details_json, created_at
FROM security_observability_events
WHERE severity = 'critical'
ORDER BY id DESC
LIMIT 100;
```

## Alert Thresholds

Default non-prod thresholds:

- `auth_lockout >= 3` events in 15 minutes: page on-call
- `sync_replay_rejected >= 2` events in 10 minutes: page on-call
- `sync_auth_rejected >= 3` events in 15 minutes: page on-call
- any `sync_dead_letter` with severity `critical`: open incident immediately

## On-Call Runbook

1. Confirm event burst using dashboard queries above.
2. Correlate `details_json`, `trace_id`, and source endpoint (`AuthService`, `LanSyncServer`, `PeerManager`).
3. Scope blast radius:
   - Single user/device: isolate user/device and rotate local auth/session.
   - Multi-device: pause peer sync and inspect cert/company-id path.
4. Mitigation:
   - Replay/auth rejects: enforce cert/key rotation and peer trust re-sync.
   - Dead-letter incidents: quarantine failed sync payload path, then replay once root cause fixed.
5. Escalation chain:
   - Primary: implementing engineer on `WEI-62`
   - Secondary: CTO
6. Rollback path:
   - Disable peer sync loop temporarily and revert latest sync transport change if incident severity stays critical.

## Synthetic Validation

For smallest non-prod validation, trigger one synthetic auth failure and one synthetic replay rejection, then verify:

- event rows appear in `security_observability_events`
- thresholds are evaluated by alerting pipeline
- on-call response path is documented in the incident ticket
