-- Phase 1.2 — Database Foundation
-- Migration 8: report_supports
-- UNIQUE(report_id, supporter_id) — one student can support a report only once.

create table public.report_supports (
  id uuid primary key default gen_random_uuid(),
  report_id uuid not null references public.reports (id),
  supporter_id uuid not null references public.profiles (id),
  comment text,
  created_at timestamptz not null default now(),
  unique (report_id, supporter_id)
);
