-- Phase 1.2 — Database Foundation
-- Migration 13: notifications
-- type + reference_id allow notifications to reference reports, comments, status changes, etc.

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id),
  title text not null,
  body text not null,
  type text not null,
  reference_id uuid,
  read boolean not null,
  created_at timestamptz not null default now()
);
