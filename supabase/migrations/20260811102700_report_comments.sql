-- Phase 1.2 — Database Foundation
-- Migration 9: report_comments

create table public.report_comments (
  id uuid primary key default gen_random_uuid(),
  report_id uuid not null references public.reports (id),
  author_id uuid not null references public.profiles (id),
  message text not null,
  created_at timestamptz not null default now()
);
