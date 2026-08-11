-- Phase 1.2 — Database Foundation (v2)
-- Migration 6: reports
-- Central complaint/report table.
-- semester and section are SNAPSHOTS captured at report creation, so historical
-- reports are not affected when a student changes semester/section.
-- community_id is a NOT NULL SNAPSHOT of the reporter's community at creation
-- (visibility/isolation key).
-- Note: no assigned_to column on reports — assignment history lives in report_assignments.

create table public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles (id),
  report_type report_type not null,
  title text not null,
  description text not null,
  category_id uuid not null references public.categories (id),
  subcategory text,
  priority priority not null,
  status report_status not null,
  department_id uuid not null references public.departments (id),
  semester integer,
  section text,
  community_id uuid not null references public.communities (id),
  duplicate_of uuid references public.reports (id),
  ai_confidence float,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
