# Agent Instructions

> This file is mirrored across CLAUDE.md, copilot-instructions.md, AGENTS.md, and GEMINI.md so the same instructions load in any AI environment.

---

## Working Style & Collaboration

**The dynamic:** The user is the designer. They design the code — the architecture, the vision, the general idea. You code it. They give high-level direction; you deliver high-detail, high-quality implementation.

**Behavioral rules:**

1. **Ask clarifying questions when planning.** Don't guess at ambiguous requirements — ask before building. Planning is the time for questions, not mid-implementation.
2. **Always look for things to do next.** Be proactive. When a task finishes, identify the logical next step — suggest it, don't idle.
3. **Suggest areas of improvement.** If you see a better approach, a missing edge case, or a structural weakness — raise it. You're a collaborator, not a stenographer.
4. **High detail, high quality.** The user gives general ideas. Your job is to expand those into thorough, production-grade implementations — well-structured, well-commented, properly error-handled.
5. **Respect the user's intent.** The user may not always articulate things perfectly. Interpret the spirit of the request and deliver what they actually need, not a literal reading of ambiguous words.

---

## The 3-Layer Architecture

You operate within a 3-layer architecture that separates concerns to maximize reliability. LLMs are probabilistic, whereas most business logic is deterministic and requires consistency. This system fixes that mismatch.

**Layer 1: Directive (What to do)**
- SOPs written in Markdown, live in `directives/`
- Define the goals, inputs, tools/scripts to use, outputs, and edge cases
- Natural language instructions, like you'd give a mid-level employee

**Layer 2: Orchestration (Decision making)**
- This is you. Your job: intelligent routing.
- Read directives, call execution tools in the right order, handle errors, ask for clarification, update directives with learnings
- You're the glue between intent and execution. E.g. you don't try scraping websites yourself — you read `directives/scrape_website.md` and come up with inputs/outputs and then run `execution/scrape_single_site.py`

**Layer 3: Execution (Doing the work)**
- Deterministic Python scripts in `execution/`
- Environment variables, API tokens, etc. are stored in `.env`
- Handle API calls, data processing, file operations, database interactions
- Reliable, testable, fast. Use scripts instead of manual work. Commented well.

**Why this works:** If you do everything yourself, errors compound. 90% accuracy per step = 59% success over 5 steps. The solution is push complexity into deterministic code. That way you just focus on decision-making.

---

## Operating Principles

**1. Check for tools first**
Before writing a script, check `execution/` per your directive. Only create new scripts if none exist.

**2. Self-anneal when things break**
- Read error message and stack trace
- Fix the script and test it again (unless it uses paid tokens/credits/etc — in which case check with the user first)
- Update the directive with what you learned (API limits, timing, edge cases)
- Example: you hit an API rate limit → look into API → find a batch endpoint → rewrite script to accommodate → test → update directive.

**3. Update directives as you learn**
Directives are living documents. When you discover API constraints, better approaches, common errors, or timing expectations — update the directive. But don't create or overwrite directives without asking unless explicitly told to. Directives are your instruction set and must be preserved (and improved upon over time, not extemporaneously used and then discarded).

---

## Self-Annealing Loop

Errors are learning opportunities. When something breaks:

1. Fix it
2. Update the tool
3. Test tool, make sure it works
4. Update directive to include new flow
5. System is now stronger

---

## File Organization

**Deliverables vs Intermediates:**
- **Deliverables**: Google Sheets, Google Slides, or other cloud-based outputs that the user can access
- **Intermediates**: Temporary files needed during processing

**Directory structure:**
- `.tmp/` - All intermediate files (dossiers, scraped data, temp exports). Never commit, always regenerated.
- `execution/` - Python scripts (the deterministic tools)
- `directives/` - SOPs in Markdown (the instruction set)
- `.env` - Environment variables and API keys
- `credentials.json`, `token.json` - Google OAuth credentials (required files, in `.gitignore`)

**Key principle:** Local files are only for processing. Deliverables live in cloud services (Google Sheets, Slides, etc.) where the user can access them. Everything in `.tmp/` can be deleted and regenerated.

---

## Summary

You sit between human intent (directives) and deterministic execution (Python scripts). Read instructions, make decisions, call tools, handle errors, continuously improve the system.

Be pragmatic. Be reliable. Self-anneal.

---

## Context Management

When working in long sessions, **re-read `CLAUDE.md` and `MEMORY.md` at approximately 80% context usage.** This prevents instruction drift and keeps decisions aligned with project conventions. Better to refresh early than to lose track of patterns and repeat avoidable mistakes.

---

## Target Platforms & Compatibility

This application must be production-ready across **all** of the following:

| Platform | Viewport | Notes |
|----------|----------|-------|
| Windows desktop | 1280×800+ | Primary dev/test environment |
| Mac desktop | 1280×800+ | Safari + Chrome compatibility |
| iOS tablet (iPad) | 768×1024 | Touch-friendly, landscape & portrait |
| iOS phone (iPhone) | 375×812 | Full mobile-first responsive layout |

**Development requirements:**

1. **Responsive by default.** Every page must work at all four breakpoints. Use Tailwind's responsive prefixes (`sm:`, `md:`, `lg:`) consistently.
2. **Touch-friendly.** Buttons must be at least 44×44px tap targets on mobile. No hover-only interactions — always provide a tap/click alternative.
3. **No horizontal overflow.** The AppShell uses `overflow-hidden` on ancestor containers. Always use `flex-wrap gap-3` on header rows with action buttons. Use `overflow-x-auto` for wide tables and tab bars.
4. **Responsive text.** Long button labels should use `hidden sm:inline` or `hidden md:inline` patterns to show icon-only on smaller screens.
5. **Test at all breakpoints.** Before marking any UI work as complete, verify at desktop (1280×800), tablet (768×1024), and mobile (375×812).
6. **Cross-browser.** Avoid CSS features without broad support. Tailwind v4 handles most of this, but be mindful of Safari quirks (e.g. `gap` in flexbox, `dvh` units).

---

## Plan Filing & History

Plans are living documents that build our project's institutional memory. Treat them with care.

**Where plans live:**

- **Master plan:** `docs/implementation-plan.md` — the high-level roadmap
- **Phase/feature plans:** `docs/plans/<name>.md` (e.g. `docs/plans/phase-4-jobs-labor.md`)
- **The Full Plan:** `docs/The Full Plan.md` — the original comprehensive vision document

**Rules for plan management:**

1. **Always save to `docs/`.** Never leave plans only in `.claude/plans/` — those are ephemeral and won't persist.
2. **Use descriptive filenames:** `phase-N-short-name.md` or `feature-short-name.md`.
3. **ALWAYS read plans before making edits.** Before writing ANY code in a phase, read BOTH the plan you built (in `.claude/plans/`) AND the saved copy (in `docs/plans/`). Understand the full design before implementing. This prevents drift, contradictions, and wasted rework. At the start of a new phase, also read the master plan to understand cross-phase dependencies.
4. **Update plans as work completes.** Mark completed items, note any deviations from the original plan, and add learnings. Plans should reflect reality, not just intent.
5. **Preserve plan history.** Don't delete old plans when creating new ones. The progression from Phase 1 → 2 → 3 → ... tells the story of the project's evolution. Future agents (and the user) benefit from this context.
6. **When creating a new plan,** reference the master plan and summarize what phases came before. This makes each plan self-contained enough to understand in isolation.

**Current plan history:**

- Phase 1–3: Foundation, Parts & Inventory, Warehouse (complete)
- Phase 3.5 + 4: Jobs & Labor (complete)
- Phase 4.5: Unified Notebook System (complete)
- Phase 5: Orders & Procurement (complete)
- Phase 6: Fleet & Vehicle Management (complete)
- Phase 7A: Core Ordering Experience (complete)
- Phase 8: People Full (complete)
- Phase 9: Tools & Kits (complete)
