-- Phase 1.2 — Database Foundation (v2: Community & Linways Integration)
-- Migration: communities
-- One community per semester + section + batch (BCA 2024 S5 C != BCA 2024 S6 C).
-- course_code is intentionally independent from departments for MVP (no FK).
-- display_name is derived from the community key, not user-typed.

create table public.communities (
  id uuid primary key default gen_random_uuid(),
  course_code text not null,
  batch_year integer not null,
  semester text not null,
  section text not null,
  display_name text not null,
  created_at timestamptz not null default now(),
  unique (course_code, batch_year, semester, section)
);
