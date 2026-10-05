-- =============================================================================
-- RLS policy test suite - requirements u1..u23 and the lifecycle invariants.
-- =============================================================================
--
-- WHY THIS EXISTS
--   The project's main security claim is 32 RLS policies. Until now that claim
--   rested on zero executable evidence: all 258 Flutter tests mock every
--   repository, and no staff account has ever existed in a live database. "The
--   docs say students cannot see other communities' reports" is an assertion,
--   not evidence. This file is the evidence.
--
-- HOW TO RUN
--   Paste the whole file into the Supabase SQL Editor and Run. It prints a
--   pass/fail table. Nothing is left behind: every statement runs in one
--   transaction that is ROLLBACK'd, so the fixtures, the results table and the
--   helper functions all disappear.
--
-- HOW IT IMPERSONATES A USER
--   There is no Supabase CLI here and no service-role key in the app, and
--   creating throwaway accounts would pollute a real database. Instead it uses
--   the standard Postgres technique:
--       set local role authenticated;
--       set local request.jwt.claims = '{"sub":"<uuid>","role":"authenticated"}';
--   Every predicate then resolves auth.uid() and my_role() exactly as it would
--   for that real user, because RLS is enforced against the current role and the
--   JWT claims and nothing else.
--
--   Fixture auth.users rows ARE created, because profiles.id has a foreign key to
--   auth.users so the profile rows cannot exist without them - but only inside
--   the rolled-back transaction.
--
-- WHY THERE ARE THREE ASSERTION HELPERS, NOT ONE
--   "Denied" does not mean "raised an error", and assuming it does is the trap
--   that makes naive RLS suites report false failures:
--
--     * INSERT and UPDATE-WITH-CHECK violations DO raise: the row fails the
--       policy check, so the statement errors. -> rls_denied.
--     * A missing table privilege also raises (42501). -> rls_denied.
--     * But a WHERE clause matching only rows that RLS HIDES does NOT raise. The
--       UPDATE/DELETE simply matches zero rows and reports success. A student
--       "updating" a report in another community is filtered out silently, so a
--       helper that waits for an exception records ALLOWED and the suite fails
--       even though the policy is correct.
--
--   So every "must not change" test goes through rls_effect instead: it runs the
--   statement, then PROBES the resulting row state and compares it to the
--   required value. That assertion holds whether the statement was rejected by
--   an error or silently filtered to zero rows - and it also catches the
--   dangerous case, where the statement succeeded and did change the row.
--
--   The probes must see rows the impersonated user cannot, so f1ce_probe and the
--   id resolvers are SECURITY DEFINER: they read as the table owner and bypass
--   RLS. Without that, "verify bob's report is untouched" would read 0 rows for
--   alice and pass for the wrong reason - and, worse, resolving a community id
--   through an RLS-filtered lookup would return NULL inside an impersonated
--   block and make a policy test fail on a NOT NULL violation instead.
--
-- WHY EVERY WRITE IS ROLLED BACK
--   rls_effect raises a private marker to unwind its own subtransaction, so an
--   ALLOWED write is recorded and then undone. Otherwise a successful "alice may
--   create a report" would add a row and change every later count. The result
--   row is written OUTSIDE that subtransaction, in the exception handler, which
--   is why it survives.
--
-- WHY THE IDs ARE NOT ALL LITERALS
--   This database is live and already holds real data, and two tables have
--   uniqueness constraints that a literal fixture id cannot dodge:
--     * departments.code is unique and 'GENERAL' is seeded by 20260815101000,
--       so inserting a second 'GENERAL' under a new id raises regardless of
--       ON CONFLICT (id).
--     * communities is UNIQUE (course_code, batch_year, semester, section), and
--       a real BCA 2024 S5 C community is exactly what a seeded project has.
--   So the department and both communities are RESOLVED BY KEY and reused if
--   they already exist. Everything the suite owns is a fresh uuid carrying the
--   f1ce0000 prefix, and every count filters on that prefix, so a run measures
--   the fixtures and never the existing backlog.
--
-- PREREQUISITES
--   Migrations through 20260815125000 applied. The suite works either side of
--   AI-1; if 20261005123000 has been applied its AFTER INSERT duplicate trigger
--   is disabled for the run so trigram similarity cannot flag one fixture as a
--   duplicate of another and change what the fixtures mean.
--
-- READING THE OUTPUT
--   passed = false means the DATABASE disagrees with docs/architecture/RLS_POLICIES.md.
--   That is the interesting outcome: either a real security bug or a doc error,
--   and both are worth knowing before a demo. A failure in the "sanity" group
--   means the fixture itself is wrong, so fix that first and re-run.
-- =============================================================================

begin;

-- =============================================================================
-- 0. Results plumbing and helpers.
--    A real table rather than TEMP so the authenticated role can be granted
--    INSERT explicitly. It exists only until the ROLLBACK at the end.
-- =============================================================================
create table public.rls_test_results (
  id serial primary key,
  requirement text not null,
  expectation text not null,
  expected text not null,
  actual text not null
);

grant insert on public.rls_test_results to authenticated;
grant select on public.rls_test_results to authenticated;
-- GRANT INSERT does NOT imply USAGE on the serial sequence, and every helper
-- inserts while the role is authenticated. Without this they fail with
-- "permission denied for sequence" instead of recording a result. The name is
-- Postgres's default <table>_<column>_seq for a serial column.
grant usage on sequence public.rls_test_results_id_seq to authenticated;

-- Read a row state as the table owner, bypassing RLS, for use as a probe.
create function pg_temp.f1ce_probe(p_sql text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v text;
begin
  execute p_sql into v;
  return coalesce(v, '<null>');
end;
$$;

-- Resolve the fixture department and communities by their natural keys so the
-- suite reuses whatever already exists instead of colliding with it. SECURITY
-- DEFINER so the lookup cannot be filtered by the very policies under test.
create function pg_temp.f1ce_dept()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select id from public.departments where code = 'GENERAL' limit 1
$$;

create function pg_temp.f1ce_community(p_semester text)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select id
  from public.communities
  where course_code = 'BCA'
    and batch_year = 2024
    and semester = p_semester
    and section = 'C'
  limit 1
$$;

-- Expect the statement to be rejected with an error. Only correct where the
-- policy is enforced by WITH CHECK or where a privilege is missing.
create function pg_temp.rls_denied(p_req text, p_what text, p_sql text)
returns void
language plpgsql
as $$
begin
  begin
    execute p_sql;
    insert into public.rls_test_results (requirement, expectation, expected, actual)
    values (p_req, p_what, 'denied', 'ALLOWED - POLICY IS TOO LOOSE');
  exception when others then
    insert into public.rls_test_results (requirement, expectation, expected, actual)
    values (p_req, p_what, 'denied', 'denied');
  end;
end;
$$;

-- Run the statement, probe the resulting state, report, then undo everything.
--   p_expected_after = the row state that proves the intent: '1' for an insert
--   that must have landed, '0' for a delete that must have removed it, or
--   'pending' for an update that must not have changed anything. There is no
--   separate "allowed"/"denied" expectation: the probe decides, which is the
--   whole point.
create function pg_temp.rls_effect(
  p_req text,
  p_what text,
  p_sql text,
  p_probe text,
  p_expected_after text
)
returns void
language plpgsql
as $$
declare
  v_verdict text;
  v_seen text;
  v_marker constant text := 'rls_test_undo_marker';
begin
  v_verdict := null;
  begin
    begin
      execute p_sql;
    exception when others then
      -- Rejected outright. Whatever the reason, nothing changed; the probe
      -- below confirms that rather than trusting the error.
      v_verdict := 'rejected by error';
    end;

    v_seen := pg_temp.f1ce_probe(p_probe);

    if v_seen = p_expected_after then
      if v_verdict = 'rejected by error' then
        v_verdict := 'rejected (state unchanged, as required)';
      else
        v_verdict := 'allowed (state is as required)';
      end if;
    else
      v_verdict := 'WRONG STATE: probe returned ' || v_seen
                   || ' but the requirement demands ' || p_expected_after
                   || ' (statement was ' || coalesce(v_verdict, 'allowed') || ')';
    end if;

    raise exception '%', v_marker;
  exception when others then
    if sqlerrm <> v_marker then
      v_verdict := 'HARNESS ERROR: ' || left(sqlerrm, 120);
    end if;
  end;

  insert into public.rls_test_results (requirement, expectation, expected, actual)
  values (p_req, p_what, p_expected_after, v_verdict);
end;
$$;

-- `set local role authenticated` changes current_user but not session_user, so
-- the session's temp namespace still resolves; granting USAGE explicitly keeps
-- the helpers callable as the impersonated role.
grant usage on schema pg_temp to authenticated;

-- =============================================================================
-- 1. Fixtures. Runs as postgres (superuser, RLS bypassed).
-- =============================================================================

-- 1.0 Neutralise AI-1 for the duration of the run. The trigger name is
--     reports_after_insert_flag_duplicate; trg_flag_duplicate_report is the
--     FUNCTION name, and disabling that raises "trigger does not exist".
do $$
begin
  if exists (
    select 1 from pg_trigger
    where tgrelid = 'public.reports'::regclass
      and tgname = 'reports_after_insert_flag_duplicate'
      and not tgisinternal
  ) then
    alter table public.reports disable trigger reports_after_insert_flag_duplicate;
  end if;
end $$;

-- 1.1 Reference data, inserted only when missing so a populated database is not
--     violated by a second 'GENERAL' or a second BCA 2024 S5 C community.
insert into public.departments (name, code)
select 'General', 'GENERAL'
where not exists (select 1 from public.departments where code = 'GENERAL');

insert into public.communities (course_code, batch_year, semester, section, display_name)
select 'BCA', 2024, v.semester, 'C', v.display_name
from (values
  ('5', 'BCA 2024 S5 C'),
  ('6', 'BCA 2024 S6 C')
) as v(semester, display_name)
where not exists (
  select 1 from public.communities c
  where c.course_code = 'BCA'
    and c.batch_year = 2024
    and c.semester = v.semester
    and c.section = 'C'
);

-- Re-assert the routing rows so the suite is self-sufficient even if
-- 20260815120000 has not been applied. The unique index on (category_id, role)
-- makes this idempotent.
insert into public.category_routes (category_id, role, priority)
select c.id, v.role::public.user_role, 1
from (values
  ('Academic',       'hod'),
  ('Infrastructure', 'operations'),
  ('Infrastructure', 'technician')
) as v(category_name, role)
join public.categories c on c.name = v.category_name
on conflict (category_id, role) do nothing;

-- 1.2 Users: auth.users + auth.identities + profiles, following the same
--     pattern as 20261005120000_seed_staff_demo_accounts.sql. crypt() with
--     gen_salt('bf') is the bcrypt format GoTrue itself writes.
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
select
  '00000000-0000-0000-0000-000000000000',
  f.id,
  'authenticated',
  'authenticated',
  f.email,
  crypt('rls-test-only', gen_salt('bf')),
  now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  jsonb_build_object('full_name', f.full_name),
  now(),
  now()
from (values
  ('f1ce0000-0000-4000-8000-000000000001'::uuid, 'alice@rls-test.local', 'Alice'),
  ('f1ce0000-0000-4000-8000-000000000002'::uuid, 'bob@rls-test.local',   'Bob'),
  ('f1ce0000-0000-4000-8000-000000000003'::uuid, 'carol@rls-test.local', 'Carol'),
  ('f1ce0000-0000-4000-8000-000000000004'::uuid, 'dave@rls-test.local',  'Dave'),
  ('f1ce0000-0000-4000-8000-000000000005'::uuid, 'hod@rls-test.local',   'Hod'),
  ('f1ce0000-0000-4000-8000-000000000006'::uuid, 'tech@rls-test.local',  'Tech'),
  ('f1ce0000-0000-4000-8000-000000000007'::uuid, 'ops@rls-test.local',   'Ops'),
  ('f1ce0000-0000-4000-8000-000000000008'::uuid, 'admin@rls-test.local', 'Admin')
) as f(id, email, full_name);

insert into auth.identities (
  id, user_id, provider_id, provider, identity_data,
  last_sign_in_at, created_at, updated_at
)
select u.id, u.id, u.id::text, 'email',
       jsonb_build_object('sub', u.id::text, 'email', u.email, 'email_verified', true),
       null, now(), now()
from auth.users u
where u.email like '%@rls-test.local';

-- department_id is mandatory for the fixtures: 20260815121000 fails staff
-- CLOSED on the routing branch when department_id is null (u23 / D1).
insert into public.profiles (id, email, full_name, role, department_id, student_id)
select
  u.id,
  u.email,
  u.raw_user_meta_data ->> 'full_name',
  f.role::public.user_role,
  pg_temp.f1ce_dept(),
  case when f.role = 'student' then split_part(u.email, '@', 1) else null end
from auth.users u
join (values
  ('f1ce0000-0000-4000-8000-000000000001'::uuid, 'student'),
  ('f1ce0000-0000-4000-8000-000000000002'::uuid, 'student'),
  ('f1ce0000-0000-4000-8000-000000000003'::uuid, 'student'),
  ('f1ce0000-0000-4000-8000-000000000004'::uuid, 'student'),
  ('f1ce0000-0000-4000-8000-000000000005'::uuid, 'hod'),
  ('f1ce0000-0000-4000-8000-000000000006'::uuid, 'technician'),
  ('f1ce0000-0000-4000-8000-000000000007'::uuid, 'operations'),
  ('f1ce0000-0000-4000-8000-000000000008'::uuid, 'admin')
) as f(id, role) on f.id = u.id
where u.email like '%@rls-test.local';

-- 1.3 Memberships. alice/bob/dave -> community A (S5), carol -> community B (S6).
--     Staff have none: their scope is role + routing + assignment, never
--     community.
insert into public.community_members (community_id, profile_id, is_active, joined_at)
select pg_temp.f1ce_community('5'), v.id, true, now()
from (values
  ('f1ce0000-0000-4000-8000-000000000001'::uuid),
  ('f1ce0000-0000-4000-8000-000000000002'::uuid),
  ('f1ce0000-0000-4000-8000-000000000004'::uuid)
) as v(id);

insert into public.community_members (community_id, profile_id, is_active, joined_at)
values (pg_temp.f1ce_community('6'),
        'f1ce0000-0000-4000-8000-000000000003', true, now());

-- 1.4 Reports. Titles are deliberately dissimilar so AI-1's trigram scoring
--     cannot flag one fixture as a duplicate of another.
--
--     id     reporter  community  category        status    deleted
--     ...20  alice     A          Academic        pending   no
--     ...21  bob       A          Academic        pending   no
--     ...22  bob       A          Infrastructure  pending   no
--     ...23  alice     A          Academic        pending   YES
--     ...24  alice     B          Academic        pending   no
--     ...25  bob       A          Academic        closed    no
--     ...26  bob       A          Academic        resolved  no
--     ...27  carol     B          Academic        pending   no
--
--     status needs an explicit ::public.report_status cast: an untyped literal in
--     a VALUES list alongside ::uuid columns resolves the column to text, and
--     text does not coerce into an enum on INSERT.
insert into public.reports (
  id, reporter_id, report_type, title, description, category_id, priority,
  status, department_id, semester, section, community_id, deleted_at
)
select
  f.id,
  f.reporter_id,
  'community',
  f.title,
  'fixture for the RLS suite',
  (select id from public.categories where name = f.category_name limit 1),
  'medium',
  f.status::public.report_status,
  pg_temp.f1ce_dept(),
  5,
  'C',
  pg_temp.f1ce_community(f.semester_key),
  f.deleted_at
from (values
  ('f1ce0000-0000-4000-8000-000000000020'::uuid, 'f1ce0000-0000-4000-8000-000000000001'::uuid,
   'Broken projector in lecture hall alpha', 'Academic', 'pending', '5',
   null::timestamptz),
  ('f1ce0000-0000-4000-8000-000000000021', 'f1ce0000-0000-4000-8000-000000000002',
   'Network drops during evening classes', 'Academic', 'pending', '5', null),
  ('f1ce0000-0000-4000-8000-000000000022', 'f1ce0000-0000-4000-8000-000000000002',
   'Drinking fountain leaking near gym', 'Infrastructure', 'pending', '5', null),
  ('f1ce0000-0000-4000-8000-000000000023', 'f1ce0000-0000-4000-8000-000000000001',
   'Ceiling fan sparking in studio', 'Academic', 'pending', '5', now()),
  ('f1ce0000-0000-4000-8000-000000000024', 'f1ce0000-0000-4000-8000-000000000001',
   'Lift jammed between second and third', 'Academic', 'pending', '6', null),
  ('f1ce0000-0000-4000-8000-000000000025', 'f1ce0000-0000-4000-8000-000000000002',
   'Lamp flickering above the stairwell', 'Academic', 'closed', '5', null),
  ('f1ce0000-0000-4000-8000-000000000026', 'f1ce0000-0000-4000-8000-000000000002',
   'Drinking water dispenser overflowing', 'Academic', 'resolved', '5', null),
  ('f1ce0000-0000-4000-8000-000000000027', 'f1ce0000-0000-4000-8000-000000000003',
   'Study chair collapsed by window', 'Academic', 'pending', '6', null)
) as f(id, reporter_id, title, category_name, status, semester_key, deleted_at);

-- 1.5 Active assignments. Two, deliberately in different categories:
--     ...20 (Academic) shows the assignment branch is department-UNSCOPED, so
--     operations sees an Academic report it is not routed to; ...26 (Academic,
--     resolved) carries an active assignment so the D5 reopen test can isolate
--     the role check from the D8 assignment requirement - which is the state
--     operations creates by reassigning before reopening.
insert into public.report_assignments (report_id, assigned_to, assigned_by, active)
values
  ('f1ce0000-0000-4000-8000-000000000020', 'f1ce0000-0000-4000-8000-000000000007',
   'f1ce0000-0000-4000-8000-000000000008', true),
  ('f1ce0000-0000-4000-8000-000000000026', 'f1ce0000-0000-4000-8000-000000000007',
   'f1ce0000-0000-4000-8000-000000000008', true);

-- 1.6 Ownership rows, so the ownership rules act on something real.
--     report_supports is UNIQUE(report_id, supporter_id), which is why the
--     "may support" test below targets a different report.
insert into public.report_supports (report_id, supporter_id)
values ('f1ce0000-0000-4000-8000-000000000021', 'f1ce0000-0000-4000-8000-000000000001');

insert into public.report_comments (report_id, author_id, message)
values ('f1ce0000-0000-4000-8000-000000000021', 'f1ce0000-0000-4000-8000-000000000001',
        'happens every single day');

insert into public.evidence_files (report_id, file_url, file_type, uploaded_by)
values ('f1ce0000-0000-4000-8000-000000000020', 'fixture/evidence.png', 'image/png',
        'f1ce0000-0000-4000-8000-000000000001');

-- notifications.read is NOT NULL with no default.
insert into public.notifications (user_id, title, body, type, reference_id, read)
values ('f1ce0000-0000-4000-8000-000000000002', 'fixture', 'fixture', 'status_change',
        'f1ce0000-0000-4000-8000-000000000021', false);

-- Note: the reports_after_insert_log trigger also creates notifications for
-- routed staff (hod for Academic, operations + technician for Infrastructure,
-- all D1-scoped to the fixture department). That is expected and harmless: the
-- notification assertions are scoped to a specific fixture user, who is a
-- student and is therefore never a routed recipient.

-- =============================================================================
-- 2. Fixture sanity. If these fail the fixtures are wrong and every later count
--    is meaningless, so they are asserted first and flagged 'sanity'.
--    categories.name has NO unique constraint, so a duplicate would silently
--    multiply the routing join; the limit 1 in the fixtures hides that and this
--    assertion is what makes it visible.
-- =============================================================================
insert into public.rls_test_results (requirement, expectation, expected, actual)
select 'sanity', 'the GENERAL department resolves', 'f1ce0000',
       case when pg_temp.f1ce_dept() is null then 'MISSING' else 'f1ce0000' end;

insert into public.rls_test_results (requirement, expectation, expected, actual)
select 'sanity', 'both fixture communities resolve', 'f1ce0000,f1ce0000',
       case when pg_temp.f1ce_community('5') is null then 'S5 MISSING' else 'f1ce0000' end
       || ',' ||
       case when pg_temp.f1ce_community('6') is null then 'S6 MISSING' else 'f1ce0000' end;

insert into public.rls_test_results (requirement, expectation, expected, actual)
select 'sanity', 'the two fixture communities are different rows', '2',
       count(distinct id)::text from public.communities
 where id in (pg_temp.f1ce_community('5'), pg_temp.f1ce_community('6'));

insert into public.rls_test_results (requirement, expectation, expected, actual)
select 'sanity', '8 fixture reports exist', '8',
       count(*)::text from public.reports where id::text like 'f1ce0000-%';

insert into public.rls_test_results (requirement, expectation, expected, actual)
select 'sanity', '8 fixture profiles exist', '8',
       count(*)::text from public.profiles where id::text like 'f1ce0000-%';

insert into public.rls_test_results (requirement, expectation, expected, actual)
select 'sanity', 'every fixture profile carries the routing department', '8',
       count(*)::text from public.profiles
 where id::text like 'f1ce0000-%' and department_id = pg_temp.f1ce_dept();

insert into public.rls_test_results (requirement, expectation, expected, actual)
select 'sanity', 'exactly one Academic category (categories.name is not unique)', '1',
       count(*)::text from public.categories where name = 'Academic';

insert into public.rls_test_results (requirement, expectation, expected, actual)
select 'sanity', 'exactly one Infrastructure category', '1',
       count(*)::text from public.categories where name = 'Infrastructure';

insert into public.rls_test_results (requirement, expectation, expected, actual)
select 'sanity',
       'the fixture reports kept their intended statuses (id order)',
       'pending,pending,pending,pending,pending,closed,resolved,pending',
       string_agg(status::text, ',' order by id) from public.reports
 where id::text like 'f1ce0000-%';

-- =============================================================================
-- 3. Assertions.
--
-- Expected visibility, derived by hand from the policy predicates:
--
--   report_visible_to_caller (rls_security:86-97, reports_update USING via
--   can_update_report_row): student -> not deleted AND (own community OR own row)
--
--   report_visible_to_staff (staff_department_scope:43-60, which SUPERSEDES
--   rls_security:58-72): admin -> all; otherwise category-routed AND
--   profiles.department_id = reports.department_id, OR actively assigned
--   (unscoped). The department conjunct is why every fixture carries a
--   department_id - without it staff fail closed and see nothing.
--
--   alice student A -> ...20 ...21 ...22 ...25 ...26 (community A) + ...24 (own, B) = 6
--   bob   student A -> ...20 ...21 ...22 ...25 ...26                                 = 5
--   carol student B -> ...27                                                          = 1
--   hod   Academic   -> ...20 ...21 ...23 ...24 ...25 ...26 ...27  (staff see deleted) = 7
--   tech  Infra      -> ...22                                                         = 1
--   ops   Infra + assigned ...20, ...26 -> ...20 ...22 ...26                           = 3
--   admin            -> all eight                                                      = 8
-- =============================================================================

-- ---------------------------------------------------------------- alice ------
set local role authenticated;
set local request.jwt.claim.sub = 'f1ce0000-0000-4000-8000-000000000001';
set local request.jwt.claims = '{"sub":"f1ce0000-0000-4000-8000-000000000001","role":"authenticated"}';

insert into public.rls_test_results (requirement, expectation, expected, actual)
select 'u1/u2', 'alice sees 6: her community, plus her own report from community B', '6',
       count(*)::text from public.reports where id::text like 'f1ce0000-%';

insert into public.rls_test_results (requirement, expectation, expected, actual)
select 'u2', 'alice cannot see her own soft-deleted report ...23', '0',
       count(*)::text from public.reports where id = 'f1ce0000-0000-4000-8000-000000000023';

insert into public.rls_test_results (requirement, expectation, expected, actual)
select 'u1', 'alice DOES see her own historical report ...24 (reporter branch)', '1',
       count(*)::text from public.reports where id = 'f1ce0000-0000-4000-8000-000000000024';

insert into public.rls_test_results (requirement, expectation, expected, actual)
select 'u1', 'alice cannot see carol''s report', '0',
       count(*)::text from public.reports where id = 'f1ce0000-0000-4000-8000-000000000027';

-- u22: the identity chain must resolve through profiles.
insert into public.rls_test_results (requirement, expectation, expected, actual)
select 'u22', 'alice my_role() resolves to student', 'student', public.my_role()::text;

insert into public.rls_test_results (requirement, expectation, expected, actual)
select 'u22', 'alice my_community_id() resolves to community A',
       pg_temp.f1ce_community('5')::text, public.my_community_id()::text;

-- u20 / u21.
insert into public.rls_test_results (requirement, expectation, expected, actual)
select 'u20', 'alice can read departments', '1',
       (select count(*)::text from public.departments where id = pg_temp.f1ce_dept());

insert into public.rls_test_results (requirement, expectation, expected, actual)
select 'u21', 'alice cannot read category_routes', '0',
       count(*)::text from public.category_routes;

insert into public.rls_test_results (requirement, expectation, expected, actual)
select 'profiles', 'alice sees only her own profile row', '1',
       count(*)::text from public.profiles;

insert into public.rls_test_results (requirement, expectation, expected, actual)
select 'communities', 'alice sees her own community', '1',
       (select count(*)::text from public.communities where id = pg_temp.f1ce_community('5'));

insert into public.rls_test_results (requirement, expectation, expected, actual)
select 'communities', 'alice cannot see community B', '0',
       (select count(*)::text from public.communities where id = pg_temp.f1ce_community('6'));

insert into public.rls_test_results (requirement, expectation, expected, actual)
select 'community_members', 'alice sees only her own membership', '1',
       count(*)::text from public.community_members;

insert into public.rls_test_results (requirement, expectation, expected, actual)
select 'u16', 'alice sees the 1 evidence row on her own report', '1',
       count(*)::text from public.evidence_files;

-- u3.
select pg_temp.rls_effect('u3', 'alice may create a report in her own community', $q$
  insert into public.reports (reporter_id, report_type, title, description, category_id,
    priority, status, department_id, community_id)
  values (auth.uid(), 'community', 'fixture new complaint', 'd',
          (select id from public.categories where name = 'Academic' limit 1),
          'low', 'pending', pg_temp.f1ce_dept(),
          pg_temp.f1ce_community('5'))
$q$,
  $q$select count(*)::text from public.reports where title = 'fixture new complaint'$q$, '1');

-- Cross-community creation is refused by WITH CHECK, so it genuinely raises.
select pg_temp.rls_denied('u3', 'alice cannot create a report in community B', $q$
  insert into public.reports (reporter_id, report_type, title, description, category_id,
    priority, status, department_id, community_id)
  values (auth.uid(), 'community', 'fixture cross community', 'd',
          (select id from public.categories where name = 'Academic' limit 1),
          'low', 'pending', pg_temp.f1ce_dept(),
          pg_temp.f1ce_community('6'))
$q$);

-- u4: a student may not pre-set the AI fields, which is what forces AI-1's
-- trigger to run AFTER INSERT.
select pg_temp.rls_denied('u4', 'alice cannot set duplicate_of on insert', $q$
  insert into public.reports (reporter_id, report_type, title, description, category_id,
    priority, status, department_id, community_id, duplicate_of)
  values (auth.uid(), 'community', 'fixture dup', 'd',
          (select id from public.categories where name = 'Academic' limit 1),
          'low', 'pending', pg_temp.f1ce_dept(),
          pg_temp.f1ce_community('5'),
          'f1ce0000-0000-4000-8000-000000000020')
$q$);

select pg_temp.rls_denied('u4', 'alice cannot set ai_confidence on insert', $q$
  insert into public.reports (reporter_id, report_type, title, description, category_id,
    priority, status, department_id, community_id, ai_confidence)
  values (auth.uid(), 'community', 'fixture ai', 'd',
          (select id from public.categories where name = 'Academic' limit 1),
          'low', 'pending', pg_temp.f1ce_dept(),
          pg_temp.f1ce_community('5'), 0.99)
$q$);

-- u6: no status changes by a student. ...21 is invisible to alice, so RLS filters
-- it out of the UPDATE silently and never raises - hence the probe.
select pg_temp.rls_effect('u6', 'alice cannot change a report''s status', $q$
  update public.reports set status = 'closed'
  where id = 'f1ce0000-0000-4000-8000-000000000021'
$q$,
  $q$select status::text from public.reports where id = 'f1ce0000-0000-4000-8000-000000000021'$q$,
  'pending');

-- u8: soft-delete her own pending report is allowed; someone else's is not.
select pg_temp.rls_effect('u8', 'alice may soft-delete her own pending report', $q$
  update public.reports set deleted_at = now()
  where id = 'f1ce0000-0000-4000-8000-000000000020'
$q$,
  $q$select (deleted_at is not null)::text from public.reports where id = 'f1ce0000-0000-4000-8000-000000000020'$q$,
  'true');

select pg_temp.rls_effect('u8', 'alice cannot soft-delete bob''s report', $q$
  update public.reports set deleted_at = now()
  where id = 'f1ce0000-0000-4000-8000-000000000022'
$q$,
  $q$select (deleted_at is not null)::text from public.reports where id = 'f1ce0000-0000-4000-8000-000000000022'$q$,
  'false');

-- u10: not your own report. ...20 is alice's own pending report.
select pg_temp.rls_denied('u10', 'alice cannot support her own report', $q$
  insert into public.report_supports (report_id, supporter_id)
  values ('f1ce0000-0000-4000-8000-000000000020', auth.uid())
$q$);

-- ...22 is bob's, open, in alice's community, and not yet supported by her.
select pg_temp.rls_effect('u10', 'alice may support bob''s open report', $q$
  insert into public.report_supports (report_id, supporter_id)
  values ('f1ce0000-0000-4000-8000-000000000022', auth.uid())
$q$,
  $q$select count(*)::text from public.report_supports
    where report_id = 'f1ce0000-0000-4000-8000-000000000022'$q$, '1');

-- u11 in isolation: ...25 is CLOSED, belongs to bob, not deleted, same community.
-- Only the status in ('pending','under_review','in_progress') clause can deny this.
select pg_temp.rls_denied('u11', 'alice cannot support a closed report', $q$
  insert into public.report_supports (report_id, supporter_id)
  values ('f1ce0000-0000-4000-8000-000000000025', auth.uid())
$q$);

-- u13: withdrawing the support seeded in 1.6.
select pg_temp.rls_effect('u13', 'alice may withdraw her own support', $q$
  delete from public.report_supports
  where report_id = 'f1ce0000-0000-4000-8000-000000000021'
    and supporter_id = 'f1ce0000-0000-4000-8000-000000000001'
$q$,
  $q$select count(*)::text from public.report_supports
    where report_id = 'f1ce0000-0000-4000-8000-000000000021'$q$, '0');

-- u14.
select pg_temp.rls_effect('u14', 'alice may comment on a visible report', $q$
  insert into public.report_comments (report_id, author_id, message)
  values ('f1ce0000-0000-4000-8000-000000000020', auth.uid(), 'fixture comment')
$q$,
  $q$select count(*)::text from public.report_comments where message = 'fixture comment'$q$, '1');

select pg_temp.rls_denied('u14', 'alice may not edit a comment (no UPDATE privilege)', $q$
  update public.report_comments set message = 'edited'
  where id = (select id from public.report_comments where id::text like 'f1ce0000-%' limit 1)
$q$);

-- u15: report_activity is server-written only.
select pg_temp.rls_denied('u15', 'alice cannot insert into report_activity', $q$
  insert into public.report_activity (report_id, actor_id, activity_type, metadata)
  values ('f1ce0000-0000-4000-8000-000000000020', auth.uid(), 'created', '{}'::jsonb)
$q$);

-- u16: evidence metadata only on her own report.
select pg_temp.rls_effect('u16', 'alice may attach evidence to her own report', $q$
  insert into public.evidence_files (report_id, file_url, file_type, uploaded_by)
  values ('f1ce0000-0000-4000-8000-000000000020', 'fixture/second.png', 'image/png', auth.uid())
$q$,
  $q$select count(*)::text from public.evidence_files
    where report_id = 'f1ce0000-0000-4000-8000-000000000020'$q$, '2');

select pg_temp.rls_denied('u16', 'alice cannot attach evidence to bob''s report', $q$
  insert into public.evidence_files (report_id, file_url, file_type, uploaded_by)
  values ('f1ce0000-0000-4000-8000-000000000022', 'fixture/other.png', 'image/png', auth.uid())
$q$);

-- u17: evidence deletion is admin-only. There IS a fixture row here, so a
-- successful delete would be observable - the assertion is not vacuous.
select pg_temp.rls_effect('u17', 'alice cannot delete evidence', $q$
  delete from public.evidence_files
  where report_id = 'f1ce0000-0000-4000-8000-000000000020'
$q$,
  $q$select count(*)::text from public.evidence_files
    where report_id = 'f1ce0000-0000-4000-8000-000000000020'$q$, '1');

-- u18: the AI log is admin-only.
insert into public.rls_test_results (requirement, expectation, expected, actual)
select 'u18', 'alice cannot read ai_classification_log', '0',
       count(*)::text from public.ai_classification_log;

-- u19: notifications are per-user.
insert into public.rls_test_results (requirement, expectation, expected, actual)
select 'u19', 'alice sees none of bob''s notifications', '0',
       count(*)::text from public.notifications;

insert into public.rls_test_results (requirement, expectation, expected, actual)
select 'u19', 'alice cannot read a notification addressed to bob', '0',
       count(*)::text from public.notifications
 where user_id = 'f1ce0000-0000-4000-8000-000000000002';

reset role;

-- ------------------------------------------------------------------ bob ------
set local role authenticated;
set local request.jwt.claim.sub = 'f1ce0000-0000-4000-8000-000000000002';
set local request.jwt.claims = '{"sub":"f1ce0000-0000-4000-8000-000000000002","role":"authenticated"}';

insert into public.rls_test_results (requirement, expectation, expected, actual)
select 'u1', 'bob sees 5 reports in his community', '5',
       count(*)::text from public.reports where id::text like 'f1ce0000-%';

insert into public.rls_test_results (requirement, expectation, expected, actual)
select 'u1', 'bob cannot see carol''s community B report', '0',
       count(*)::text from public.reports where id = 'f1ce0000-0000-4000-8000-000000000027';

insert into public.rls_test_results (requirement, expectation, expected, actual)
select 'u1', 'bob cannot see alice''s report in community B', '0',
       count(*)::text from public.reports where id = 'f1ce0000-0000-4000-8000-000000000024';

insert into public.rls_test_results (requirement, expectation, expected, actual)
select 'u1/u2', 'bob cannot see the soft-deleted report', '0',
       count(*)::text from public.reports where id = 'f1ce0000-0000-4000-8000-000000000023';

insert into public.rls_test_results (requirement, expectation, expected, actual)
select 'u1', 'bob DOES see alice''s report in his own community', '1',
       count(*)::text from public.reports where id = 'f1ce0000-0000-4000-8000-000000000020';

insert into public.rls_test_results (requirement, expectation, expected, actual)
select 'u19', 'bob sees exactly his own 1 notification', '1',
       count(*)::text from public.notifications;

insert into public.rls_test_results (requirement, expectation, expected, actual)
select 'profiles', 'bob sees only his own profile', '1',
       count(*)::text from public.profiles;

reset role;

-- ---------------------------------------------------------------- carol ------
set local role authenticated;
set local request.jwt.claim.sub = 'f1ce0000-0000-4000-8000-000000000003';
set local request.jwt.claims = '{"sub":"f1ce0000-0000-4000-8000-000000000003","role":"authenticated"}';

insert into public.rls_test_results (requirement, expectation, expected, actual)
select 'u1', 'carol sees exactly 1 report in her own community', '1',
       count(*)::text from public.reports where id::text like 'f1ce0000-%';

insert into public.rls_test_results (requirement, expectation, expected, actual)
select 'communities', 'carol sees her own community', '1',
       (select count(*)::text from public.communities where id = pg_temp.f1ce_community('6'));

insert into public.rls_test_results (requirement, expectation, expected, actual)
select 'communities', 'carol cannot see community A', '0',
       (select count(*)::text from public.communities where id = pg_temp.f1ce_community('5'));

insert into public.rls_test_results (requirement, expectation, expected, actual)
select 'community_members', 'carol sees only her own membership', '1',
       count(*)::text from public.community_members;

reset role;

-- ------------------------------------------------------------------ hod ------
set local role authenticated;
set local request.jwt.claim.sub = 'f1ce0000-0000-4000-8000-000000000005';
set local request.jwt.claims = '{"sub":"f1ce0000-0000-4000-8000-000000000005","role":"authenticated"}';

-- u23 / D1: Academic routes to hod; ...22 is Infrastructure and must be excluded.
-- Staff also see soft-deleted rows (u2), which is why 7 and not 6.
insert into public.rls_test_results (requirement, expectation, expected, actual)
select 'u23/D1', 'hod sees 7 Academic reports incl. deleted, excluding the Infrastructure one',
       '7', count(*)::text from public.reports where id::text like 'f1ce0000-%';

insert into public.rls_test_results (requirement, expectation, expected, actual)
select 'u23/D1', 'hod cannot see the Infrastructure report', '0',
       count(*)::text from public.reports where id = 'f1ce0000-0000-4000-8000-000000000022';

insert into public.rls_test_results (requirement, expectation, expected, actual)
select 'u2', 'hod sees soft-deleted reports', '1',
       count(*)::text from public.reports
 where id::text like 'f1ce0000-%' and deleted_at is not null;

-- Staff are not community-scoped: ...27 is community B and still visible.
insert into public.rls_test_results (requirement, expectation, expected, actual)
select 'u2', 'hod sees another community''s report (staff are not community-scoped)', '1',
       count(*)::text from public.reports where id = 'f1ce0000-0000-4000-8000-000000000027';

insert into public.rls_test_results (requirement, expectation, expected, actual)
select 'communities', 'hod sees both fixture communities (staff see all)', '2',
       (select count(*)::text from public.communities
        where id in (pg_temp.f1ce_community('5'), pg_temp.f1ce_community('6')));

insert into public.rls_test_results (requirement, expectation, expected, actual)
select 'u21', 'hod CAN read category_routes', '1',
       (select case when count(*) > 0 then '1' else '0' end from public.category_routes);

insert into public.rls_test_results (requirement, expectation, expected, actual)
select 'profiles', 'hod sees only his own profile (all-profiles is admin only)', '1',
       count(*)::text from public.profiles;

-- u5: staff may not create reports.
select pg_temp.rls_denied('u5', 'hod cannot create a report', $q$
  insert into public.reports (reporter_id, report_type, title, description, category_id,
    priority, status, department_id, community_id)
  values (auth.uid(), 'community', 'fixture staff report', 'd',
          (select id from public.categories where name = 'Academic' limit 1),
          'low', 'pending', pg_temp.f1ce_dept(),
          pg_temp.f1ce_community('5'))
$q$);

-- u12: the insert policy requires my_role() = 'student'.
select pg_temp.rls_denied('u12', 'hod cannot support a report', $q$
  insert into public.report_supports (report_id, supporter_id)
  values ('f1ce0000-0000-4000-8000-000000000020', auth.uid())
$q$);

-- u9: only operations/admin may assign.
select pg_temp.rls_denied('u9', 'hod cannot assign a report', $q$
  insert into public.report_assignments (report_id, assigned_to, assigned_by, active)
  values ('f1ce0000-0000-4000-8000-000000000021', auth.uid(), auth.uid(), true)
$q$);

-- u18: the AI log is admin-only, so a non-admin staff role gets nothing.
insert into public.rls_test_results (requirement, expectation, expected, actual)
select 'u18', 'hod cannot read ai_classification_log', '0',
       count(*)::text from public.ai_classification_log;

-- --- u7 lifecycle, through the real state machine ---------------------------
-- can_transition_status is exactly what the reports_update_gated WITH CHECK
-- calls, and it is visibility-gated (F5) so it never reveals feasibility for a
-- report the caller cannot see.
insert into public.rls_test_results (requirement, expectation, expected, actual)
select 'u7 matrix', 'pending -> under_review allowed for hod', 'true',
       public.can_transition_status('f1ce0000-0000-4000-8000-000000000021', 'under_review')::text;

-- D8: entering work requires an active assignment; ...21 has none.
insert into public.rls_test_results (requirement, expectation, expected, actual)
select 'u7 D8', 'pending -> in_progress DENIED with no active assignment', 'false',
       public.can_transition_status('f1ce0000-0000-4000-8000-000000000021', 'in_progress')::text;

insert into public.rls_test_results (requirement, expectation, expected, actual)
select 'u7 matrix', 'pending -> closed DENIED for hod (admin only)', 'false',
       public.can_transition_status('f1ce0000-0000-4000-8000-000000000021', 'closed')::text;

-- 'resolved' was deliberately removed from the pending row of the matrix.
insert into public.rls_test_results (requirement, expectation, expected, actual)
select 'u7 matrix', 'pending -> resolved DENIED (removed by approved amendment)', 'false',
       public.can_transition_status('f1ce0000-0000-4000-8000-000000000021', 'resolved')::text;

-- D6: closed is terminal.
insert into public.rls_test_results (requirement, expectation, expected, actual)
select 'u7 D6', 'closed -> under_review DENIED for hod (closed is terminal)', 'false',
       public.can_transition_status('f1ce0000-0000-4000-8000-000000000025', 'under_review')::text;

-- D5 reopen is operations/admin only. ...26 is resolved AND actively assigned,
-- so D8 is satisfied and the role check is what decides - which is the point of
-- giving this fixture an assignment.
insert into public.rls_test_results (requirement, expectation, expected, actual)
select 'u7 D5', 'hod cannot reopen a resolved report (operations/admin only)', 'false',
       public.can_transition_status('f1ce0000-0000-4000-8000-000000000026', 'under_review')::text;

-- F5: an unknown report must be infeasible, not visible.
insert into public.rls_test_results (requirement, expectation, expected, actual)
select 'F5', 'transition on an unknown report is infeasible (no existence leak)', 'false',
       public.can_transition_status('99999999-9999-4999-8999-999999999999', 'under_review')::text;

-- F5 proper: visibility-gating. ...22 is Infrastructure, which does not route to
-- hod, so hod must not be able to transition it even though he could if visible.
insert into public.rls_test_results (requirement, expectation, expected, actual)
select 'F5', 'hod cannot transition a report he cannot see', 'false',
       public.can_transition_status('f1ce0000-0000-4000-8000-000000000022', 'under_review')::text;

-- Sanity: hod must actually be able to see what the matrix allows, otherwise the
-- D5 result above would pass for the wrong reason (F5 gate, not the role check).
insert into public.rls_test_results (requirement, expectation, expected, actual)
select 'F5', 'hod CAN see the resolved report, so its D5 denial is a role check', 'true',
       public.report_visible_to_caller('f1ce0000-0000-4000-8000-000000000026')::text;

insert into public.rls_test_results (requirement, expectation, expected, actual)
select 'F5', 'hod CANNOT see the Infrastructure report the F5 test relies on', 'false',
       public.report_visible_to_caller('f1ce0000-0000-4000-8000-000000000022')::text;

reset role;

-- ----------------------------------------------------------- technician ------
set local role authenticated;
set local request.jwt.claim.sub = 'f1ce0000-0000-4000-8000-000000000006';
set local request.jwt.claims = '{"sub":"f1ce0000-0000-4000-8000-000000000006","role":"authenticated"}';

-- u23 / D1: technician is routed to Infrastructure only.
insert into public.rls_test_results (requirement, expectation, expected, actual)
select 'u23/D1', 'technician sees only the 1 Infrastructure report', '1',
       count(*)::text from public.reports where id::text like 'f1ce0000-%';

insert into public.rls_test_results (requirement, expectation, expected, actual)
select 'u23/D1', 'technician cannot see any Academic report', '0',
       count(*)::text from public.reports where id::text like 'f1ce0000-%'
   and category_id in (select id from public.categories where name = 'Academic');

reset role;

-- ------------------------------------------------------------ operations -----
set local role authenticated;
set local request.jwt.claim.sub = 'f1ce0000-0000-4000-8000-000000000007';
set local request.jwt.claims = '{"sub":"f1ce0000-0000-4000-8000-000000000007","role":"authenticated"}';

-- Routed to Infrastructure (...22) AND actively assigned ...20 and ...26. The
-- assignment branch is deliberately department-UNSCOPED
-- (staff_department_scope:53-59), which is why ops sees two Academic reports
-- it is not routed to.
insert into public.rls_test_results (requirement, expectation, expected, actual)
select 'u23/u9', 'operations sees 3 reports: 1 routed + 2 assigned (cross-department OK)', '3',
       count(*)::text from public.reports where id::text like 'f1ce0000-%';

insert into public.rls_test_results (requirement, expectation, expected, actual)
select 'u9', 'operations sees the 2 assignments it was given', '2',
       count(*)::text from public.report_assignments where assigned_to = auth.uid();

-- u9: operations may assign. ...21 has no assignment yet.
select pg_temp.rls_effect('u9', 'operations may assign a report', $q$
  insert into public.report_assignments (report_id, assigned_to, assigned_by, active)
  values ('f1ce0000-0000-4000-8000-000000000021', auth.uid(), auth.uid(), true)
$q$,
  $q$select count(*)::text from public.report_assignments
    where report_id = 'f1ce0000-0000-4000-8000-000000000021' and active$q$, '1');

-- u9 / F6: the target must be a staff member.
select pg_temp.rls_denied('u9/F6', 'operations cannot assign a report to a student', $q$
  insert into public.report_assignments (report_id, assigned_to, assigned_by, active)
  values ('f1ce0000-0000-4000-8000-000000000022',
          'f1ce0000-0000-4000-8000-000000000002', auth.uid(), true)
$q$);

-- D5 positive: the same reopen hod was denied above is allowed for operations.
insert into public.rls_test_results (requirement, expectation, expected, actual)
select 'u7 D5', 'operations CAN reopen the assigned resolved report', 'true',
       public.can_transition_status('f1ce0000-0000-4000-8000-000000000026', 'under_review')::text;

reset role;

-- ---------------------------------------------------------------- admin ------
set local role authenticated;
set local request.jwt.claim.sub = 'f1ce0000-0000-4000-8000-000000000008';
set local request.jwt.claims = '{"sub":"f1ce0000-0000-4000-8000-000000000008","role":"authenticated"}';

insert into public.rls_test_results (requirement, expectation, expected, actual)
select 'admin', 'admin sees all 8 reports regardless of routing or community', '8',
       count(*)::text from public.reports where id::text like 'f1ce0000-%';

insert into public.rls_test_results (requirement, expectation, expected, actual)
select 'profiles', 'admin sees every profile', '8',
       count(*)::text from public.profiles where id::text like 'f1ce0000-%';

insert into public.rls_test_results (requirement, expectation, expected, actual)
select 'communities', 'admin sees both fixture communities', '2',
       (select count(*)::text from public.communities
        where id in (pg_temp.f1ce_community('5'), pg_temp.f1ce_community('6')));

-- u17: admin may delete evidence. The probe goes 1 -> 0, so this proves the
-- delete actually happened rather than matching zero rows.
select pg_temp.rls_effect('u17', 'admin may delete evidence metadata', $q$
  delete from public.evidence_files
  where report_id = 'f1ce0000-0000-4000-8000-000000000020'
$q$,
  $q$select count(*)::text from public.evidence_files
    where report_id = 'f1ce0000-0000-4000-8000-000000000020'$q$, '0');

-- u8 / F1: restore is admin-only and must preserve status. ...23 is deleted+pending.
insert into public.rls_test_results (requirement, expectation, expected, actual)
select 'u8/F1', 'admin may restore a soft-deleted report', 'true',
       public.can_update_report('f1ce0000-0000-4000-8000-000000000023', 'pending', null)::text;

insert into public.rls_test_results (requirement, expectation, expected, actual)
select 'u8/F1', 'a restore that also changes status is DENIED', 'false',
       public.can_update_report('f1ce0000-0000-4000-8000-000000000023', 'resolved', null)::text;

-- u8: staff moderation soft-delete must not change the status.
select pg_temp.rls_effect('u8', 'admin may soft-delete any report (moderation)', $q$
  update public.reports set deleted_at = now()
  where id = 'f1ce0000-0000-4000-8000-000000000022'
$q$,
  $q$select (deleted_at is not null)::text || '/' || status::text
    from public.reports where id = 'f1ce0000-0000-4000-8000-000000000022'$q$,
  'true/pending');

-- D6: closed is terminal even for admin.
insert into public.rls_test_results (requirement, expectation, expected, actual)
select 'u7 D6', 'closed -> under_review DENIED for admin (closed is terminal)', 'false',
       public.can_transition_status('f1ce0000-0000-4000-8000-000000000025', 'under_review')::text;

-- D8: an admin may reach in_progress on ...20 because it IS actively assigned.
insert into public.rls_test_results (requirement, expectation, expected, actual)
select 'u7 D8', 'pending -> in_progress allowed when an active assignment exists', 'true',
       public.can_transition_status('f1ce0000-0000-4000-8000-000000000020', 'in_progress')::text;

-- u3: admin report creation is a documented exception in can_create_report.
select pg_temp.rls_effect('u3', 'admin may create a report (documented exception)', $q$
  insert into public.reports (reporter_id, report_type, title, description, category_id,
    priority, status, department_id, community_id)
  values (auth.uid(), 'community', 'fixture admin report', 'd',
          (select id from public.categories where name = 'Academic' limit 1),
          'low', 'pending', pg_temp.f1ce_dept(),
          pg_temp.f1ce_community('5'))
$q$,
  $q$select count(*)::text from public.reports where title = 'fixture admin report'$q$, '1');

reset role;

-- =============================================================================
-- 4. Report.
-- =============================================================================
select
  case when actual like '%(state is as required)%'
        or actual like '%(state unchanged, as required)%'
       then 'PASS' else 'FAIL' end as result,
  requirement,
  expectation,
  expected,
  actual
from public.rls_test_results
order by (case when actual like '%(state is as required)%'
                     or actual like '%(state unchanged, as required)%'
                then 1 else 0 end) asc,
         requirement, id;

select
  count(*) as total,
  count(*) filter (where actual like '%(state is as required)%'
                     or actual like '%(state unchanged, as required)%') as passed,
  count(*) filter (where actual not like '%(state is as required)%'
                     and actual not like '%(state unchanged, as required)%') as failed,
  count(*) filter (
    where requirement = 'sanity'
      and actual not like '%(state is as required)%'
      and actual not like '%(state unchanged, as required)%') as fixture_problems
from public.rls_test_results;

-- Nothing is persisted. Fixtures, the results table and the helper functions
-- all disappear with this statement.
rollback;
