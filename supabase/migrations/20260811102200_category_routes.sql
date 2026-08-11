-- Phase 1.2 — Database Foundation
-- Migration 4: category_routes
-- Allows one category to route to multiple roles. priority determines routing order.

create table public.category_routes (
  id uuid primary key default gen_random_uuid(),
  category_id uuid not null references public.categories (id),
  role user_role not null,
  priority integer not null,
  created_at timestamptz not null default now()
);
