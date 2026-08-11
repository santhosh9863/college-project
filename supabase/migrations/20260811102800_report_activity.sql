-- Phase 1.2 — Database Foundation
-- Migration 10: report_activity
-- Replaces the previously planned status_updates table.
-- Status changes are represented as activity_type = 'status_change'
-- with metadata like { "from_status": "pending", "to_status": "under_review" }.

create table public.report_activity (
  id uuid primary key default gen_random_uuid(),
  report_id uuid not null references public.reports (id),
  actor_id uuid not null references public.profiles (id),
  activity_type text not null,
  metadata jsonb,
  created_at timestamptz not null default now()
);
