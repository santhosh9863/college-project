-- Phase 1.2 — Database Foundation
-- Migration 3: categories
-- Note: categories intentionally does NOT contain an assigned_role column.
-- Routing is handled separately through category_routes.

create table public.categories (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_at timestamptz not null default now()
);
