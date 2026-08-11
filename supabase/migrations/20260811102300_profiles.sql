-- Phase 1.2 — Database Foundation
-- Migration 5: profiles
-- Extends Supabase auth.users (1:1).

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  email text not null,
  full_name text not null,
  role user_role not null,
  department_id uuid references public.departments (id),
  semester integer,
  section text,
  student_id text unique,
  created_at timestamptz not null default now()
);
