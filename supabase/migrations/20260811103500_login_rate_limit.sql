-- Phase: Authentication — server-side login rate limiting
-- Used by the linways-login Edge Function (service_role only).
-- Isolated from the 18 applied migrations: nothing existing is modified.
-- Contains NO sensitive material: no passwords, access tokens, refresh
-- tokens, or Linways session cookies are stored in this table.

create table public.login_attempts (
  id uuid primary key default gen_random_uuid(),
  ip_address inet not null,
  outcome text not null check (outcome in ('success', 'failure')),
  attempted_at timestamptz not null default now()
);

create index login_attempts_ip_time_idx
  on public.login_attempts (ip_address, attempted_at desc);

-- Server-side write-only table. No client role may read or write it:
-- RLS enabled with no policies (deny all) + explicit revokes for defense.
alter table public.login_attempts enable row level security;

revoke all on table public.login_attempts from anon;
revoke all on table public.login_attempts from authenticated;
