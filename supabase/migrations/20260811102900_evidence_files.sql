-- Phase 1.2 — Database Foundation
-- Migration 11: evidence_files

create table public.evidence_files (
  id uuid primary key default gen_random_uuid(),
  report_id uuid not null references public.reports (id),
  file_url text not null,
  file_type text not null,
  uploaded_by uuid not null references public.profiles (id),
  created_at timestamptz not null default now()
);
