-- Phase 1.2 — Database Foundation (v2: Community & Linways Integration)
-- Migration: community_members
-- Membership history: UNIQUE(community_id, profile_id) — one membership row per
-- student per community; is_active marks the current one, left_at closes it.

create table public.community_members (
  id uuid primary key default gen_random_uuid(),
  community_id uuid not null references public.communities (id),
  profile_id uuid not null references public.profiles (id),
  is_active boolean not null,
  joined_at timestamptz not null default now(),
  left_at timestamptz,
  unique (community_id, profile_id)
);
