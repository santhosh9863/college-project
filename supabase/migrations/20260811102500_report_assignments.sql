-- Phase 1.2 — Database Foundation
-- Migration 7: report_assignments
-- Preserves assignment/reassignment history. The current assignment is the row with active = true.

create table public.report_assignments (
  id uuid primary key default gen_random_uuid(),
  report_id uuid not null references public.reports (id),
  assigned_by uuid not null references public.profiles (id),
  assigned_to uuid not null references public.profiles (id),
  assigned_at timestamptz not null default now(),
  active boolean not null,
  notes text
);
