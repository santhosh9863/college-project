-- Phase 2 — Reports System (Part 2-A): add 'critical' to the priority enum.
-- Additive only: appends a value to the existing type; nothing existing is
-- modified. Approved decision (BLOCKER 3): UI exposes Low/Medium/High/Critical.

alter type public.priority add value 'critical';
