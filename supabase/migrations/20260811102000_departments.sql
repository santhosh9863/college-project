-- Phase 1.2 — Database Foundation
-- Migration 2: departments

create table public.departments (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  code text not null unique,
  created_at timestamptz not null default now()
);
