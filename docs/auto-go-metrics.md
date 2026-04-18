# AUTO GO Metrics

> **Auto-maintained** by `/auto-go` STEP 7.
> Read by the weekly `loop-self-improve` meta-check (Sunday afternoon) to analyze trends and mutate the loop.
> **Do not edit** by hand — this is raw data for the self-improvement pass.

## Per-iteration rows

| date | iteration | area | check | status | findings | fixes_applied | tests_added | duration_sec | meta_checks_fired |
|------|-----------|------|-------|--------|----------|---------------|-------------|--------------|-------------------|

## Weekly Roll-ups (updated by loop-self-improve)

_(empty — first roll-up on first Sunday after install)_

## What loop-self-improve Looks For

- **Per-check yield** — findings per run per check type; low-yield checks demoted
- **Per-area velocity** — iterations to graduate an area; stalled areas flagged
- **Q&A latency** — time between question filed and answered; slow Q&A triggers "tighten questions" recommendation
- **Xcode-prompt latency** — time between prompt written and marked done; growing queue = throughput issue
- **Automation-recommendation uptake** — adopted / deferred / ignored ratios per category

Self-improvements are applied autonomously for safe changes (reordering, enabling/disabling checks, adding chained skills) and filed as Q&A for the user when larger (new areas, new routines, architecture).
