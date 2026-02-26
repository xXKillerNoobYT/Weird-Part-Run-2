"""
Companions Service — the suggestion engine brain.

Core responsibilities:
1. Generate suggestions from manual trigger items (and future order hooks)
2. Match rules to source categories with style auto-matching
3. Calculate suggested quantities based on rule qty_mode
4. Build human-readable reason text for every suggestion
5. Approve/discard suggestions with feedback tracking
6. Coordinate co-occurrence refresh
7. Aggregate stats for the KPI dashboard

This service orchestrates the three companion repos and contains all the
business logic — the repos are pure data access.
"""

from __future__ import annotations

import json
import logging
from typing import Any

import aiosqlite

from app.repositories.companions_repo import (
    CompanionRuleRepo,
    CompanionSuggestionRepo,
    CoOccurrenceRepo,
)

logger = logging.getLogger(__name__)


class CompanionsService:
    """Orchestrates companion rule matching and suggestion generation."""

    def __init__(self, db: aiosqlite.Connection) -> None:
        self.db = db
        self.rules = CompanionRuleRepo(db)
        self.suggestions = CompanionSuggestionRepo(db)
        self.cooccurrence = CoOccurrenceRepo(db)

    # ══════════════════════════════════════════════════════════════
    # SUGGESTION GENERATION — the core engine
    # ══════════════════════════════════════════════════════════════

    async def generate_suggestions(
        self,
        items: list[dict],
        user_id: int | None = None,
    ) -> list[dict]:
        """Generate companion suggestions from a list of input items.

        Each item is: {category_id: int, style_id?: int, qty: int}

        Algorithm:
        1. Collect unique category IDs from input
        2. Find all active rules that match ANY source category
        3. For each matched rule:
           a. Identify which input items match the rule's sources
           b. For each target in the rule:
              - Style matching: auto → find same-name style; any → no filter
              - Qty calculation: sum → total matched qty; ratio → sum × ratio
              - Build reason text explaining the suggestion
        4. Create suggestion + source records in DB
        """
        if not items:
            return []

        # Index items by category for fast lookup
        items_by_category: dict[int, list[dict]] = {}
        for item in items:
            cat_id = item["category_id"]
            items_by_category.setdefault(cat_id, []).append(item)

        category_ids = list(items_by_category.keys())

        # Find matching rules
        matched_rules = await self.rules.get_rules_for_categories(category_ids)
        if not matched_rules:
            logger.info(
                "No companion rules match categories: %s", category_ids
            )
            return []

        created_suggestions = []

        for rule in matched_rules:
            # Find which input items match this rule's sources
            matched_items = self._match_sources(rule, items_by_category)
            if not matched_items:
                continue

            # Process each target in the rule
            for target in rule["targets"]:
                suggestion = await self._generate_for_target(
                    rule=rule,
                    target=target,
                    matched_items=matched_items,
                    all_items=items,
                    user_id=user_id,
                )
                if suggestion:
                    created_suggestions.append(suggestion)

        logger.info(
            "Generated %d suggestions from %d rules for %d input items",
            len(created_suggestions),
            len(matched_rules),
            len(items),
        )
        return created_suggestions

    # ══════════════════════════════════════════════════════════════
    # DECISIONS — approve/discard
    # ══════════════════════════════════════════════════════════════

    async def decide_suggestion(
        self,
        suggestion_id: int,
        action: str,
        user_id: int,
        approved_qty: int | None = None,
        notes: str | None = None,
    ) -> dict | None:
        """Approve or discard a suggestion, recording feedback for learning."""
        suggestion = await self.suggestions.get_suggestion_with_sources(
            suggestion_id
        )
        if not suggestion:
            return None

        if suggestion["status"] != "pending":
            return None  # Already decided

        # Update the suggestion
        await self.suggestions.decide(
            suggestion_id=suggestion_id,
            action=action,
            decided_by=user_id,
            approved_qty=approved_qty,
            notes=notes,
        )

        # Record feedback for the learning loop
        source_categories = json.dumps([
            {"category_id": s["category_id"], "qty": s["qty"]}
            for s in suggestion.get("sources", [])
        ])

        await self.suggestions.record_feedback({
            "suggestion_id": suggestion_id,
            "rule_id": suggestion.get("rule_id"),
            "action": action,
            "suggested_qty": suggestion["suggested_qty"],
            "final_qty": approved_qty or suggestion["suggested_qty"],
            "source_categories": source_categories,
            "target_category_id": suggestion["target_category_id"],
            "target_style_id": suggestion.get("target_style_id"),
            "user_id": user_id,
        })

        # Return the updated suggestion
        return await self.suggestions.get_suggestion_with_sources(
            suggestion_id
        )

    # ══════════════════════════════════════════════════════════════
    # STATS & CO-OCCURRENCE
    # ══════════════════════════════════════════════════════════════

    async def get_stats(self) -> dict:
        """Get aggregate counts for the KPI dashboard."""
        suggestion_stats = await self.suggestions.get_stats()

        # Rule counts
        total_rules = await self.rules.count()
        active_rules = await self.rules.count(
            where="is_active = 1"
        )

        # Co-occurrence count
        co_pairs = await self.cooccurrence.count_pairs()

        return {
            "total_rules": total_rules,
            "active_rules": active_rules,
            "pending_suggestions": suggestion_stats["pending_suggestions"],
            "approved_count": suggestion_stats["approved_count"],
            "discarded_count": suggestion_stats["discarded_count"],
            "co_occurrence_pairs": co_pairs,
        }

    async def refresh_cooccurrence(self) -> int:
        """Recompute co-occurrence pairs from stock_movements."""
        count = await self.cooccurrence.refresh_from_movements()
        logger.info("Refreshed co-occurrence: %d pairs computed", count)
        return count

    # ══════════════════════════════════════════════════════════════
    # PRIVATE — matching & generation helpers
    # ══════════════════════════════════════════════════════════════

    def _match_sources(
        self,
        rule: dict,
        items_by_category: dict[int, list[dict]],
    ) -> list[dict]:
        """Find input items that match any of the rule's source categories.

        Returns the matched items with their resolved context (category name,
        style, qty) for use in reason text generation.
        """
        matched = []
        for source in rule["sources"]:
            cat_id = source["category_id"]
            if cat_id not in items_by_category:
                continue

            for item in items_by_category[cat_id]:
                # If rule source specifies a style, check style match
                if source.get("style_id") and item.get("style_id"):
                    if source["style_id"] != item["style_id"]:
                        continue

                matched.append({
                    "category_id": cat_id,
                    "category_name": source.get("category_name", ""),
                    "style_id": item.get("style_id"),
                    "style_name": item.get("style_name"),
                    "qty": item["qty"],
                })

        return matched

    async def _generate_for_target(
        self,
        rule: dict,
        target: dict,
        matched_items: list[dict],
        all_items: list[dict],
        user_id: int | None,
    ) -> dict | None:
        """Generate a single suggestion for one target in a rule.

        Handles style auto-matching and qty calculation.
        """
        target_cat_id = target["category_id"]
        target_cat_name = target.get("category_name", "")
        target_style_id = target.get("style_id")
        target_style_name = target.get("style_name")

        # ── Style matching ──────────────────────────────────────
        if rule["style_match"] == "auto" and not target_style_id:
            # Auto-match: find the dominant style name from sources,
            # then look for a style with the same name in the target category
            dominant_style = self._get_dominant_style(matched_items)
            if dominant_style:
                resolved = await self._resolve_style_by_name(
                    target_cat_id, dominant_style
                )
                if resolved:
                    target_style_id = resolved["id"]
                    target_style_name = resolved["name"]

        # ── Qty calculation ─────────────────────────────────────
        suggested_qty = self._calculate_qty(rule, matched_items)
        if suggested_qty <= 0:
            return None

        # ── Target description ──────────────────────────────────
        target_desc = target_cat_name
        if target_style_name:
            target_desc += f" ({target_style_name})"

        # ── Reason text ─────────────────────────────────────────
        reason_text = self._build_reason(
            rule=rule,
            matched_items=matched_items,
            target_desc=target_desc,
            suggested_qty=suggested_qty,
        )

        # ── Create the suggestion ───────────────────────────────
        suggestion_data = {
            "rule_id": rule["id"],
            "target_category_id": target_cat_id,
            "target_style_id": target_style_id,
            "target_description": target_desc,
            "suggested_qty": suggested_qty,
            "reason_type": "rule",
            "reason_text": reason_text,
            "status": "pending",
            "triggered_by": user_id,
        }

        source_records = [
            {
                "category_id": m["category_id"],
                "category_name": m.get("category_name"),
                "style_id": m.get("style_id"),
                "style_name": m.get("style_name"),
                "qty": m["qty"],
            }
            for m in matched_items
        ]

        suggestion_id = await self.suggestions.create_suggestion(
            suggestion_data, source_records
        )

        return await self.suggestions.get_suggestion_with_sources(
            suggestion_id
        )

    def _get_dominant_style(self, matched_items: list[dict]) -> str | None:
        """Find the most common style name among matched items.

        Used for 'auto' style matching — if 3 out of 4 matched items are
        'Decora', we auto-match to 'Decora' in the target category.
        """
        style_counts: dict[str, int] = {}
        for item in matched_items:
            name = item.get("style_name")
            if name:
                style_counts[name] = style_counts.get(name, 0) + item["qty"]

        if not style_counts:
            return None

        return max(style_counts, key=style_counts.get)  # type: ignore[arg-type]

    async def _resolve_style_by_name(
        self, category_id: int, style_name: str
    ) -> dict | None:
        """Look up a style by name within a specific category."""
        cursor = await self.db.execute(
            """SELECT id, name FROM part_styles
               WHERE category_id = ? AND name = ? AND is_active = 1
               LIMIT 1""",
            (category_id, style_name),
        )
        row = await cursor.fetchone()
        return dict(row) if row else None

    def _calculate_qty(
        self, rule: dict, matched_items: list[dict]
    ) -> int:
        """Calculate the suggested quantity based on the rule's qty_mode.

        - sum:   Total of all matched item quantities
        - max:   Largest single matched item quantity
        - ratio: Sum × qty_ratio (e.g., 0.5 means half)
        """
        if not matched_items:
            return 0

        qtys = [m["qty"] for m in matched_items]
        mode = rule["qty_mode"]

        if mode == "sum":
            return sum(qtys)
        elif mode == "max":
            return max(qtys)
        elif mode == "ratio":
            ratio = rule.get("qty_ratio", 1.0)
            return max(1, round(sum(qtys) * ratio))
        else:
            return sum(qtys)  # Fallback to sum

    def _build_reason(
        self,
        rule: dict,
        matched_items: list[dict],
        target_desc: str,
        suggested_qty: int,
    ) -> str:
        """Build a human-readable reason for why this suggestion was made.

        Example output:
        "Rule 'Cover Plates for Devices': 28× Outlets (Decora) + 17× Switches
        (Decora) = 45× Cover Plates (Decora)"
        """
        # Build source description parts
        source_parts = []
        for item in matched_items:
            desc = f"{item['qty']}× {item.get('category_name', 'Unknown')}"
            if item.get("style_name"):
                desc += f" ({item['style_name']})"
            source_parts.append(desc)

        sources_text = " + ".join(source_parts)

        return (
            f"Rule '{rule['name']}': {sources_text} "
            f"= {suggested_qty}× {target_desc}"
        )
