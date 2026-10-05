-- Panel System: seeded staff demo accounts.
--
-- WHY THIS EXISTS (CURRENT_STATE.md 5.2): the staff accounts were created by
-- hand in the dashboard, so no crypt()/auth.users insert existed in
-- supabase/migrations/. They did not survive the project pause, staff login
-- started returning "Invalid username or password", and there was no
-- reproducible way to bring them back. This migration makes them
-- reproducible.
--
-- ONE ACCOUNT PER ROLE IS NOW REQUIRED. Commit 18c98fd removed the panel
-- switcher: a staff shell renders the panel for the logged-in role and RLS
-- scopes every query to it. A single shared admin account therefore cannot
-- demonstrate the HOD, technician or operations panels at all - the accounts
-- below exist to make all four panels demoable.
--
-- These are DEMO CREDENTIALS with well-known passwords, committed in
-- plaintext so they are reproducible. The admin account has read-all queue,
-- close, soft-delete/restore and analytics on a real database. Before any
-- deployment outside a local demo, remove the accounts:
--   delete from auth.users where email like '%@college-project.local';
-- (profiles rows cascade via the FK). Nothing else references them.
--
-- Idempotent: safe to run repeatedly. A re-run does NOT reset an existing
-- account's password - to reissue a demo password, delete the auth.users row
-- above and re-run.
--
-- The staging table is TEMP, so it lives in this session only and is never
-- visible in the public schema. It is dropped explicitly at the end rather
-- than with ON COMMIT DROP: if the runner auto-commits each statement, ON
-- COMMIT DROP would discard the table immediately after CREATE and every
-- later statement would fail on a missing relation.

create temporary table staff_demo_seed (
  email text primary key,
  full_name text not null,
  role public.user_role not null,
  password text not null
);

insert into staff_demo_seed (email, full_name, role, password) values
  ('hod@college-project.local',        'Demo HOD',         'hod',        'Hod@12345'),
  ('technician@college-project.local', 'Demo Technician',  'technician', 'Tech@12345'),
  ('operations@college-project.local', 'Demo Operations', 'operations', 'Ops@12345'),
  ('admin@college-project.local',      'Demo Admin',       'admin',      'Staff@12345');

-- ---------------------------------------------------------------------------
-- 1. auth.users. crypt()/gen_salt('bf') produces the same bcrypt format GoTrue
--    itself writes, so signInWithPassword accepts it. email_confirmed_at is
--    set because the dashboard equivalent was "Auto Confirm User"; an
--    unconfirmed account cannot sign in. raw_app_meta_data.provider must list
--    "email" or GoTrue refuses the password grant for the account.
-- ---------------------------------------------------------------------------
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
select
  '00000000-0000-0000-0000-000000000000',
  gen_random_uuid(),
  'authenticated',
  'authenticated',
  s.email,
  crypt(s.password, gen_salt('bf')),
  now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  jsonb_build_object('full_name', s.full_name),
  now(),
  now()
from staff_demo_seed s
where not exists (select 1 from auth.users u where u.email = s.email);

-- ---------------------------------------------------------------------------
-- 2. auth.identities. GoTrue keeps the link between an auth user and a login
--    provider in its own table, and email/password sign-in resolves through
--    it - an auth.users row alone signs in as "Invalid username or password"
--    even when the hash is correct. This is the single most common reason a
--    hand-inserted GoTrue user will not authenticate.
-- ---------------------------------------------------------------------------
insert into auth.identities (
  id, user_id, provider_id, provider, identity_data,
  last_sign_in_at, created_at, updated_at
)
select
  u.id, u.id, u.id::text, 'email',
  jsonb_build_object('sub', u.id::text, 'email', u.email, 'email_verified', true),
  null, now(), now()
from staff_demo_seed s
join auth.users u on u.email = s.email
where not exists (select 1 from auth.identities i where i.user_id = u.id);

-- ---------------------------------------------------------------------------
-- 3. public.profiles. No handle_new_user trigger exists in this project, so
--    the profile row is never created automatically - omitting it makes the
--    staff path in linways-login/index.ts:571 fall through to the Linways
--    handshake and fail confusingly. id = auth.users.id is the project
--    invariant (rls_security.sql:5); department_id anchors D1 department
--    routing, so a NULL department would leave the HOD account seeing nothing;
--    student_id stays NULL for staff (unique, and NULLs do not collide).
-- ---------------------------------------------------------------------------
insert into public.profiles (id, email, full_name, role, department_id, student_id)
select
  u.id, s.email, s.full_name, s.role, d.id, null
from staff_demo_seed s
join auth.users u on u.email = s.email
join public.departments d on d.code = 'GENERAL'
on conflict (id) do update
  set email = excluded.email,
      full_name = excluded.full_name,
      role = excluded.role,
      department_id = excluded.department_id;

drop table staff_demo_seed;

-- ---------------------------------------------------------------------------
-- Verify: four profiles, four distinct roles, all with a department.
--   select email, role, department_id is not null as has_dept
--     from public.profiles where email like '%@college-project.local'
--    order by role;
-- ---------------------------------------------------------------------------
