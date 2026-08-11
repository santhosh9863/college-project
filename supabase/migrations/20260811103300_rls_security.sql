-- Phase 1.3 — Security: Row Level Security (RLS)
-- Migration: rls_security
-- Implements the APPROVED RLS design (docs/architecture/RLS_POLICIES.md, decisions u1-u23)
-- and the approved lifecycle validation (docs/architecture/REPORT_LIFECYCLE.md, D1-D10).
-- Identity model: auth.users.id = profiles.id = auth.uid() (JWT_AUTH_COMPATIBILITY.md, u22).
-- Server-generated paths (report_activity, notifications, ai_classification_log) have
-- NO client write policies (u15, u18, u19).
--
-- REVISION 2 (post-security-review; still not applied):
--   F1 restore preserves status; F3 report_assignments updates restricted to
--   `active`; F5 transition helpers visibility-gated (no status oracle);
--   F6 assignment targets must be staff; F7 O/A assignment scope per u9;
--   F8/F9 single-active invariants via partial unique indexes; TOCTOU
--   serialization via locked reads in can_update_report/can_transition_status.
--   F4 server-generated mechanism: documented in section 6, pending approval,
--   NOT implemented in this migration.

-- =============================================================================
-- 1. SECURITY DEFINER helper functions
--    search_path locked; role/community come from the database, never the client.
-- =============================================================================

-- App role of the caller; NULL when the caller has no profile (fail-closed).
create or replace function public.my_role()
returns public.user_role
language sql
stable
security definer
set search_path = ''
as $$
  select role from public.profiles where id = auth.uid()
$$;

-- Active community id of the caller (MVP: one active membership).
create or replace function public.my_community_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select community_id
  from public.community_members
  where profile_id = auth.uid() and is_active
  order by joined_at desc
  limit 1
$$;

-- Staff visibility: routed via category_routes to the caller's role, or active
-- assignment to the caller, or admin. Includes soft-deleted reports (u2).
create or replace function public.report_visible_to_staff(p_report_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.my_role() = 'admin'
      or exists (
           select 1
           from public.category_routes cr
           join public.reports r on r.category_id = cr.category_id
           where r.id = p_report_id
             and cr.role = public.my_role()
         )
      or exists (
           select 1
           from public.report_assignments ra
           where ra.report_id = p_report_id
             and ra.assigned_to = auth.uid()
             and ra.active
         )
$$;

-- Any-caller visibility:
--   student -> own active community reports OR own historical reports, never deleted (u1, u2)
--   staff   -> routed/assigned (incl. soft-deleted, u2)
--   admin   -> all
create or replace function public.report_visible_to_caller(p_report_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case public.my_role()
    when 'admin'       then true
    when 'hod'         then public.report_visible_to_staff(p_report_id)
    when 'technician'  then public.report_visible_to_staff(p_report_id)
    when 'operations'  then public.report_visible_to_staff(p_report_id)
    else exists (
      select 1 from public.reports r
      where r.id = p_report_id
        and r.deleted_at is null
        and (r.community_id = public.my_community_id() or r.reporter_id = auth.uid())
    )
  end
$$;

-- Report creation guard (student community-scoped; admin allowed for test data; u3, u5).
create or replace function public.can_create_report(
  p_report_type public.report_type,
  p_status public.report_status,
  p_community_id uuid,
  p_reporter_id uuid,
  p_ai_confidence double precision,
  p_duplicate_of uuid,
  p_deleted_at timestamptz
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_role public.user_role;
begin
  v_role := public.my_role();

  if v_role = 'student' then
    return p_reporter_id = auth.uid()
       and p_community_id = public.my_community_id()
       and p_status = 'pending'
       and p_report_type = 'community'
       and p_deleted_at is null
       and p_ai_confidence is null
       and p_duplicate_of is null;
  end if;

  if v_role = 'admin' then
    return p_report_type = 'community' and p_deleted_at is null;
  end if;

  return false;
end;
$$;

-- Status transition validation per the approved lifecycle matrix (REPORT_LIFECYCLE.md
-- section 3, D1-D10): forward path, rejection, O/A-only reopen, closed terminal.
-- F5: visibility-gated — never reveals feasibility for reports the caller may not see.
-- Concurrency: locked reads serialize concurrent transitions (TOCTOU fix).
create or replace function public.can_transition_status(
  p_report_id uuid,
  p_new_status public.report_status
)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_old_status public.report_status;
  v_role public.user_role;
  v_has_active_assignment boolean;
begin
  if not public.report_visible_to_caller(p_report_id) then
    return false;
  end if;

  select r.status into v_old_status
  from public.reports r
  where r.id = p_report_id
  for update;

  if v_old_status is null then
    return false;
  end if;

  v_role := public.my_role();

  if v_old_status = p_new_status then
    return true;
  end if;

  if v_old_status = 'closed' then
    return false; -- D6: closed is terminal, no transitions out
  end if;

  v_has_active_assignment := exists (
    select 1 from public.report_assignments ra
    where ra.report_id = p_report_id and ra.active
    for update
  );

  -- D8: entering work, or re-entering after reopen, requires an active assignment
  if p_new_status = 'in_progress'
     or (v_old_status in ('resolved', 'rejected')
         and p_new_status in ('under_review', 'in_progress'))
  then
    if not v_has_active_assignment then
      return false;
    end if;
  end if;

  if v_old_status = 'pending' then
    return case p_new_status
      when 'under_review' then v_role in ('hod', 'technician', 'operations', 'admin')
      when 'in_progress'  then v_role in ('hod', 'technician', 'operations', 'admin')
      when 'rejected'     then v_role in ('hod', 'technician', 'operations', 'admin')
      when 'closed'       then v_role = 'admin'
      else false -- 'resolved' removed from pending (approved amendment)
    end;
  elsif v_old_status = 'under_review' then
    return case p_new_status
      when 'in_progress' then v_role in ('hod', 'technician', 'operations', 'admin')
      when 'rejected'    then v_role in ('hod', 'technician', 'operations', 'admin')
      when 'closed'      then v_role = 'admin'
      else false -- 'resolved' requires in_progress (D2)
    end;
  elsif v_old_status = 'in_progress' then
    return case p_new_status
      when 'resolved' then v_role in ('hod', 'technician', 'operations', 'admin')
      when 'rejected' then v_role in ('hod', 'technician', 'operations', 'admin')
      when 'closed'   then v_role = 'admin'
      else false
    end;
  elsif v_old_status = 'resolved' then
    return p_new_status in ('under_review', 'in_progress')
       and v_role in ('operations', 'admin'); -- D5: reopen O/A only
  elsif v_old_status = 'rejected' then
    return p_new_status in ('under_review', 'in_progress')
       and v_role in ('operations', 'admin'); -- D4: reopen O/A only
  end if;

  return false;
end;
$$;

-- Row gate for report UPDATE (USING): own rows for students, staff-visible for staff.
create or replace function public.can_update_report_row(p_report_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (public.my_role() = 'student' and exists (
            select 1 from public.reports r
            where r.id = p_report_id and r.reporter_id = auth.uid()
          ))
      or public.report_visible_to_staff(p_report_id)
$$;

-- Update guard (WITH CHECK):
--   student -> cancel own pending report only (set deleted_at, status unchanged; u6, u8)
--   staff   -> status transition per matrix, or moderation soft-delete (u8)
--   admin   -> restore (deleted_at cleared) with status preserved (F1)
-- F5: visibility-gated; not usable as a probe on reports the caller may not see.
-- Concurrency: locked reads serialize concurrent updates (TOCTOU fix).
create or replace function public.can_update_report(
  p_report_id uuid,
  p_new_status public.report_status,
  p_new_deleted_at timestamptz
)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_old_status public.report_status;
  v_old_deleted_at timestamptz;
  v_role public.user_role;
begin
  if not public.report_visible_to_caller(p_report_id) then
    return false;
  end if;

  select r.status, r.deleted_at into v_old_status, v_old_deleted_at
  from public.reports r
  where r.id = p_report_id
  for update;

  if v_old_status is null then
    return false;
  end if;

  v_role := public.my_role();

  if v_role = 'student' then
    return v_old_deleted_at is null
       and p_new_deleted_at is not null
       and v_old_status = 'pending'
       and p_new_status = 'pending'
       and exists (
         select 1 from public.reports r
         where r.id = p_report_id and r.reporter_id = auth.uid()
       );
  end if;

  if v_role in ('hod', 'technician', 'operations', 'admin') then
    if not public.report_visible_to_staff(p_report_id) then
      return false;
    end if;

    -- restore: admin only, status must be preserved (F1) — a restore may not
    -- change status or bypass the lifecycle matrix (D4/D5/D8)
    if v_old_deleted_at is not null and p_new_deleted_at is null then
      return v_role = 'admin' and p_new_status = v_old_status;
    end if;

    -- moderation soft-delete: status must not change (u8)
    if p_new_deleted_at is not null then
      return v_old_deleted_at is null and p_new_status = v_old_status;
    end if;

    -- status transition: deleted_at stays null
    if p_new_status is distinct from v_old_status then
      return public.can_transition_status(p_report_id, p_new_status);
    end if;

    return true;
  end if;

  return false;
end;
$$;

-- Assignment management guard (u9; F6, F7):
--   Operations/Admin may assign/reassign without a per-category routing
--   restriction (u9; F7 removes the ops-routed-only scope). The target profile
--   must be a staff member (F6) and the report must exist.
create or replace function public.can_manage_assignment(
  p_report_id uuid,
  p_assigned_to uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_role public.user_role;
  v_target_role public.user_role;
begin
  v_role := public.my_role();
  if v_role not in ('operations', 'admin') then
    return false;
  end if;

  if not exists (select 1 from public.reports r where r.id = p_report_id) then
    return false;
  end if;

  select role into v_target_role
  from public.profiles
  where id = p_assigned_to;

  return v_target_role is not null and v_target_role <> 'student';
end;
$$;

-- Function access control: helpers are for authenticated users only.
revoke all on function public.my_role() from public;
revoke all on function public.my_community_id() from public;
revoke all on function public.report_visible_to_staff(uuid) from public;
revoke all on function public.report_visible_to_caller(uuid) from public;
revoke all on function public.can_create_report(
  public.report_type, public.report_status, uuid, uuid, double precision, uuid, timestamptz
) from public;
revoke all on function public.can_transition_status(uuid, public.report_status) from public;
revoke all on function public.can_update_report_row(uuid) from public;
revoke all on function public.can_update_report(uuid, public.report_status, timestamptz) from public;
revoke all on function public.can_manage_assignment(uuid, uuid) from public;

grant execute on function public.my_role() to authenticated;
grant execute on function public.my_community_id() to authenticated;
grant execute on function public.report_visible_to_staff(uuid) to authenticated;
grant execute on function public.report_visible_to_caller(uuid) to authenticated;
grant execute on function public.can_create_report(
  public.report_type, public.report_status, uuid, uuid, double precision, uuid, timestamptz
) to authenticated;
grant execute on function public.can_transition_status(uuid, public.report_status) to authenticated;
grant execute on function public.can_update_report_row(uuid) to authenticated;
grant execute on function public.can_update_report(uuid, public.report_status, timestamptz) to authenticated;
grant execute on function public.can_manage_assignment(uuid, uuid) to authenticated;

-- =============================================================================
-- 2. Enable Row Level Security on all 14 tables
-- =============================================================================

alter table public.departments enable row level security;
alter table public.categories enable row level security;
alter table public.category_routes enable row level security;
alter table public.profiles enable row level security;
alter table public.communities enable row level security;
alter table public.community_members enable row level security;
alter table public.reports enable row level security;
alter table public.report_assignments enable row level security;
alter table public.report_supports enable row level security;
alter table public.report_comments enable row level security;
alter table public.report_activity enable row level security;
alter table public.evidence_files enable row level security;
alter table public.ai_classification_log enable row level security;
alter table public.notifications enable row level security;

-- =============================================================================
-- 3. Table/column privileges (defense in depth; Supabase default privileges
--    grant ALL to anon/authenticated, so writes are revoked and only the
--    approved columns/operations are re-granted)
-- =============================================================================

-- Anonymous: no access to any table.
revoke all on table
  public.departments,
  public.categories,
  public.category_routes,
  public.profiles,
  public.communities,
  public.community_members,
  public.reports,
  public.report_assignments,
  public.report_supports,
  public.report_comments,
  public.report_activity,
  public.evidence_files,
  public.ai_classification_log,
  public.notifications
from anon;

-- Authenticated: SELECT on all tables (row access is policy-controlled).
grant select on table
  public.departments,
  public.categories,
  public.category_routes,
  public.profiles,
  public.communities,
  public.community_members,
  public.reports,
  public.report_assignments,
  public.report_supports,
  public.report_comments,
  public.report_activity,
  public.evidence_files,
  public.ai_classification_log,
  public.notifications
to authenticated;

-- Identity/social tables: read-only for authenticated (service_role writes).
revoke insert, update, delete on public.profiles from authenticated;
revoke insert, update, delete on public.communities from authenticated;

-- community_members: admin-gated inserts/updates (policy-enforced).
grant insert, update on public.community_members to authenticated;
revoke delete on public.community_members from authenticated;

-- reports: student/admin inserts; status/deleted_at/updated_at updates only.
grant insert on public.reports to authenticated;
revoke update on public.reports from authenticated;
grant update (status, deleted_at, updated_at) on public.reports to authenticated;
revoke delete on public.reports from authenticated;

-- report_assignments: ops/admin inserts; reassignment is insert-new + deactivate-old
-- (F3: only `active` is client-updatable — attribution, report identity and
-- timestamps are insert-only; no deletes).
grant insert on public.report_assignments to authenticated;
revoke update on public.report_assignments from authenticated;
grant update (active) on public.report_assignments to authenticated;
revoke delete on public.report_assignments from authenticated;

-- report_supports: inserts and own-row deletes; no updates (u13).
grant insert, delete on public.report_supports to authenticated;
revoke update on public.report_supports from authenticated;

-- report_comments: inserts and own/admin deletes; no updates (u14).
grant insert, delete on public.report_comments to authenticated;
revoke update on public.report_comments from authenticated;

-- report_activity: read-only (server-generated only, u15).
revoke insert, update, delete on public.report_activity from authenticated;

-- evidence_files: inserts; admin-only deletes (u17); no updates.
grant insert, delete on public.evidence_files to authenticated;
revoke update on public.evidence_files from authenticated;

-- ai_classification_log: read-only, admin-gated by policy (u18).
revoke insert, update, delete on public.ai_classification_log from authenticated;

-- notifications: own read; own read-column update; own delete; no inserts (u19).
revoke update on public.notifications from authenticated;
grant update (read) on public.notifications to authenticated;
grant delete on public.notifications to authenticated;
revoke insert on public.notifications from authenticated;

-- Reference data: read-only.
revoke insert, update, delete
  on public.departments, public.categories, public.category_routes
  from authenticated;

-- =============================================================================
-- 4. Policies
-- =============================================================================

-- 4.1 departments / categories: reference data for all authenticated users (u20).
create policy "departments_select_all_authenticated"
  on public.departments
  for select to authenticated
  using (true);

create policy "categories_select_all_authenticated"
  on public.categories
  for select to authenticated
  using (true);

-- 4.2 category_routes: staff only (u21).
create policy "category_routes_select_staff"
  on public.category_routes
  for select to authenticated
  using (public.my_role() <> 'student');

-- 4.3 profiles: own row; admin sees all. No client writes (role immutability).
create policy "profiles_select_own_or_admin"
  on public.profiles
  for select to authenticated
  using (id = auth.uid() or public.my_role() = 'admin');

-- 4.4 communities: students see their active community; staff see all.
create policy "communities_select_visible"
  on public.communities
  for select to authenticated
  using (public.my_community_id() = id or public.my_role() <> 'student');

-- 4.5 community_members: own memberships for students, all for staff;
--     admin assigns (community_pending) and manages memberships.
create policy "community_members_select_own_or_staff"
  on public.community_members
  for select to authenticated
  using (profile_id = auth.uid() or public.my_role() <> 'student');

create policy "community_members_insert_admin"
  on public.community_members
  for insert to authenticated
  with check (public.my_role() = 'admin' and is_active and left_at is null);

create policy "community_members_update_admin"
  on public.community_members
  for update to authenticated
  using (public.my_role() = 'admin')
  with check (public.my_role() = 'admin');

-- 4.6 reports: community-isolated reads; student/admin inserts; lifecycle-gated updates.
create policy "reports_select_visible"
  on public.reports
  for select to authenticated
  using (public.report_visible_to_caller(id));

create policy "reports_insert"
  on public.reports
  for insert to authenticated
  with check (
    public.can_create_report(report_type, status, community_id, reporter_id, ai_confidence, duplicate_of, deleted_at)
  );

create policy "reports_update_gated"
  on public.reports
  for update to authenticated
  using (public.can_update_report_row(id))
  with check (public.can_update_report(id, status, deleted_at));

-- 4.7 report_assignments: visible to report viewers; O/A create and reassign.
create policy "report_assignments_select_visible"
  on public.report_assignments
  for select to authenticated
  using (public.report_visible_to_caller(report_id));

create policy "report_assignments_insert_ops_admin"
  on public.report_assignments
  for insert to authenticated
  with check (
    assigned_by = auth.uid()
    and active
    and public.can_manage_assignment(report_id, assigned_to)
  );

create policy "report_assignments_update_ops_admin"
  on public.report_assignments
  for update to authenticated
  using (public.my_role() in ('operations', 'admin'))
  with check (public.can_manage_assignment(report_id, assigned_to));

-- 4.8 report_supports: community-scoped reads; student inserts on open reports
--     they did not create (u10, u11, u12); own-row withdrawal (u13).
create policy "report_supports_select_visible"
  on public.report_supports
  for select to authenticated
  using (public.report_visible_to_caller(report_id));

create policy "report_supports_insert_student"
  on public.report_supports
  for insert to authenticated
  with check (
    public.my_role() = 'student'
    and supporter_id = auth.uid()
    and exists (
      select 1 from public.reports r
      where r.id = report_id
        and r.deleted_at is null
        and r.reporter_id <> auth.uid()
        and r.status in ('pending', 'under_review', 'in_progress')
        and (r.community_id = public.my_community_id() or r.reporter_id = auth.uid())
    )
  );

create policy "report_supports_delete_own"
  on public.report_supports
  for delete to authenticated
  using (supporter_id = auth.uid());

-- 4.9 report_comments: visible to report viewers; authors insert; own/admin deletes.
create policy "report_comments_select_visible"
  on public.report_comments
  for select to authenticated
  using (public.report_visible_to_caller(report_id));

create policy "report_comments_insert"
  on public.report_comments
  for insert to authenticated
  with check (
    author_id = auth.uid()
    and public.report_visible_to_caller(report_id)
    and exists (
      select 1 from public.reports r
      where r.id = report_id and r.deleted_at is null
    )
  );

create policy "report_comments_delete_own_or_admin"
  on public.report_comments
  for delete to authenticated
  using (author_id = auth.uid() or public.my_role() = 'admin');

-- 4.10 report_activity: read-only timeline for report viewers (u15).
create policy "report_activity_select_visible"
  on public.report_activity
  for select to authenticated
  using (public.report_visible_to_caller(report_id));

-- 4.11 evidence_files: visible with the report; students upload to own reports
--      only (u16); admin-only deletes (u17).
create policy "evidence_files_select_visible"
  on public.evidence_files
  for select to authenticated
  using (public.report_visible_to_caller(report_id));

create policy "evidence_files_insert"
  on public.evidence_files
  for insert to authenticated
  with check (
    uploaded_by = auth.uid()
    and exists (
      select 1 from public.reports r
      where r.id = report_id and r.deleted_at is null
        and (
          (public.my_role() = 'student' and r.reporter_id = auth.uid())
          or public.report_visible_to_staff(report_id)
        )
    )
  );

create policy "evidence_files_delete_admin"
  on public.evidence_files
  for delete to authenticated
  using (public.my_role() = 'admin');

-- 4.12 ai_classification_log: admin-only reads (u18); server-written.
create policy "ai_classification_log_select_admin"
  on public.ai_classification_log
  for select to authenticated
  using (public.my_role() = 'admin');

-- 4.13 notifications: own reads, own read-column updates, own deletes (u19).
create policy "notifications_select_own"
  on public.notifications
  for select to authenticated
  using (user_id = auth.uid());

create policy "notifications_update_own_read"
  on public.notifications
  for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy "notifications_delete_own"
  on public.notifications
  for delete to authenticated
  using (user_id = auth.uid());

-- =============================================================================
-- 5. Invariant constraints (F8, F9)
--    Enforced at the database level so they hold regardless of RLS or
--    concurrency. CAUTION: each unique index FAILS at apply time if existing
--    data already violates the invariant (verify data before pushing).
-- =============================================================================

-- F8: a report has at most one active assignment at any time. History rows
--     keep active = false; reassignment = deactivate the old row, then insert
--     the new active row (the BEFORE INSERT trigger proposed in section 6 will
--     make this atomic once approved).
create unique index report_assignments_one_active_per_report
  on public.report_assignments (report_id)
  where active;

-- F9: a profile has at most one active community membership (MVP invariant).
--     Admin moves: deactivate the current membership first, then activate the
--     new one.
create unique index community_members_one_active_per_profile
  on public.community_members (profile_id)
  where is_active;

-- =============================================================================
-- 6. Server-generated paths (F4) — PROPOSED MECHANISM, PENDING APPROVAL.
--    Nothing in this section is implemented. Triggers will be added in a
--    follow-up migration once approved. All trigger functions will be
--    SECURITY DEFINER with SET search_path = '' and fully qualified references.
--
--    Event map (design docs: REPORT_LIFECYCLE.md §7-§8, MASTER_ARCHITECTURE §13):
--      reports AFTER INSERT                 -> report_activity 'created' {report_type}
--                                            + 'report_new' notifications to routed staff
--      reports AFTER UPDATE (status)        -> report_activity 'status_change' {from,to}
--                                            + notifications per the D9 matrix (reporter,
--                                              active assignee, routed staff on reopen)
--      reports AFTER UPDATE (deleted_at)    -> report_activity 'soft_deleted'/'restored'
--                                            + 'report_deleted'/'report_restored' notifications
--      reports AFTER UPDATE (-> resolved/rejected/closed) -> deactivate active assignment (D8)
--      report_assignments AFTER INSERT      -> report_activity 'assigned' {assigned_to, notes}
--                                            + 'assignment' notification to the new assignee
--      report_assignments AFTER UPDATE (active true -> false) -> report_activity 'unassigned'
--                                            + 'assignment' notification to the former assignee
--      report_assignments BEFORE INSERT     -> auto-deactivate the prior active row (atomic
--                                              reassignment; required once section 5's unique
--                                              index is in place)
--
--    Alternative (rejected for MVP): a service_role Edge Function writes the
--    same rows on each event. DB triggers are recommended because they are
--    atomic with the change, cannot be skipped by the client, and keep a single
--    auditable write path.
-- =============================================================================
