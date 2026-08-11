-- Phase 1.3 — Security: Server-Generated Events (F4 mechanism)
-- Migration: server_generated_events
-- Implements the approved F4 proposal (documented in section 6 of
-- 20260811103300_rls_security.sql REVISION 2; REPORT_LIFECYCLE.md §7-§8;
-- MASTER_ARCHITECTURE.md §13; RLS u15/u18/u19).
--
-- Design invariants:
--   * Every trigger function is SECURITY DEFINER (owner = postgres), so RLS and
--     the client write-revocations (u15/u19) cannot block the side effects.
--   * SET search_path = '' and fully qualified references throughout.
--   * No trigger writes to the table that fired it -> no recursive triggering
--     (side effects land only on report_activity/notifications, which have no
--     triggers, or on report_assignments via one-level deactivation updates).
--   * Actor attribution: auth.uid() is used when the change came from an
--     authenticated client. service_role/console changes carry no JWT subject,
--     so activity rows are skipped for those paths (actor_id is NOT NULL and
--     must never be fabricated); notifications never depend on the actor.
--   * Clients cannot write report_activity/notifications: the RLS migration
--     revokes INSERT/UPDATE/DELETE from authenticated/anon and defines no
--     INSERT policies; the helper functions below are additionally revoked
--     from PUBLIC (no client role can invoke them).
--   * Applies after 20260811103300_rls_security.sql (ordering by filename).

-- =============================================================================
-- 1. Server-write helpers (owner-only; NOT client-callable)
-- =============================================================================

create or replace function public.server_notify(
  p_user_id uuid,
  p_title text,
  p_body text,
  p_type text,
  p_reference_id uuid
)
returns void
language sql
volatile
security definer
set search_path = ''
as $$
  insert into public.notifications (user_id, title, body, type, reference_id, read)
  values (p_user_id, p_title, p_body, p_type, p_reference_id, false)
$$;

create or replace function public.server_activity(
  p_report_id uuid,
  p_actor_id uuid,
  p_activity_type text,
  p_metadata jsonb
)
returns void
language sql
volatile
security definer
set search_path = ''
as $$
  insert into public.report_activity (report_id, actor_id, activity_type, metadata)
  values (p_report_id, p_actor_id, p_activity_type, p_metadata)
$$;

revoke all on function public.server_notify(uuid, text, text, text, uuid) from public;
revoke all on function public.server_activity(uuid, uuid, text, jsonb) from public;

-- =============================================================================
-- 2. reports triggers
-- =============================================================================

-- 2.1 AFTER INSERT -> activity 'created' + 'report_new' notifications to the
--     staff whose role the category routes to (D9; category_routes priority
--     order determines the recipient set).
create or replace function public.trg_log_report_created()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  perform public.server_activity(
    NEW.id,
    NEW.reporter_id,
    'created',
    jsonb_build_object('report_type', NEW.report_type)
  );

  insert into public.notifications (user_id, title, body, type, reference_id, read)
  select p.id, 'New report', NEW.title, 'report_new', NEW.id, false
  from public.category_routes cr
  join public.profiles p on p.role = cr.role
  where cr.category_id = NEW.category_id
    and p.id <> NEW.reporter_id;

  return new;
end;
$$;

create trigger reports_after_insert_log
  after insert on public.reports
  for each row execute function public.trg_log_report_created();

-- 2.2 AFTER status UPDATE -> activity 'status_change' {from,to} + notifications
--     per the D9 matrix: reporter always; active assignee when entering
--     in_progress from pending/under_review; routed staff on reopen.
create or replace function public.trg_log_status_change()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_active_assignee uuid;
begin
  if auth.uid() is not null then
    perform public.server_activity(
      NEW.id,
      auth.uid(),
      'status_change',
      jsonb_build_object('from_status', OLD.status, 'to_status', NEW.status)
    );
  end if;

  perform public.server_notify(
    NEW.reporter_id,
    'Status updated',
    'Your report "' || NEW.title || '" is now ' || NEW.status::text,
    'status_change',
    NEW.id
  );

  if NEW.status = 'in_progress' and OLD.status in ('pending', 'under_review') then
    select ra.assigned_to into v_active_assignee
    from public.report_assignments ra
    where ra.report_id = NEW.id and ra.active
    limit 1;
    if v_active_assignee is not null then
      perform public.server_notify(
        v_active_assignee,
        'Report in progress',
        'Report "' || NEW.title || '" is now in progress',
        'status_change',
        NEW.id
      );
    end if;
  end if;

  if OLD.status in ('resolved', 'rejected')
     and NEW.status in ('under_review', 'in_progress') then
    insert into public.notifications (user_id, title, body, type, reference_id, read)
    select p.id, 'Report reopened', NEW.title, 'status_change', NEW.id, false
    from public.category_routes cr
    join public.profiles p on p.role = cr.role
    where cr.category_id = NEW.category_id
      and p.id <> NEW.reporter_id;
  end if;

  return new;
end;
$$;

create trigger reports_after_update_status
  after update on public.reports
  for each row
  when (OLD.status is distinct from NEW.status)
  execute function public.trg_log_status_change();

-- 2.3 AFTER deleted_at set/cleared -> 'soft_deleted'/'restored' activity +
--     notifications (D9: none for student self-cancel; routed staff when
--     staff-initiated; reporter on restore).
create or replace function public.trg_log_soft_delete_restore()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_deleted_by text;
begin
  if NEW.deleted_at is not null then
    if auth.uid() is not null then
      v_deleted_by := case when auth.uid() = NEW.reporter_id then 'student' else 'staff' end;
      perform public.server_activity(
        NEW.id,
        auth.uid(),
        'soft_deleted',
        jsonb_build_object('deleted_by', v_deleted_by)
      );
      if v_deleted_by = 'staff' then
        insert into public.notifications (user_id, title, body, type, reference_id, read)
        select p.id, 'Report deleted', NEW.title, 'report_deleted', NEW.id, false
        from public.category_routes cr
        join public.profiles p on p.role = cr.role
        where cr.category_id = NEW.category_id
          and p.id <> NEW.reporter_id;
      end if;
    end if;
  else
    if auth.uid() is not null then
      perform public.server_activity(NEW.id, auth.uid(), 'restored', '{}'::jsonb);
    end if;
    perform public.server_notify(
      NEW.reporter_id,
      'Report restored',
      'Your report "' || NEW.title || '" was restored',
      'report_restored',
      NEW.id
    );
  end if;

  return new;
end;
$$;

create trigger reports_after_update_deleted
  after update on public.reports
  for each row
  when (OLD.deleted_at is distinct from NEW.deleted_at)
  execute function public.trg_log_soft_delete_restore();

-- 2.4 AFTER transition to resolved/rejected/closed -> deactivate the active
--     assignment (D8). The nested UPDATE fires the assignments deactivation
--     logging trigger below ('unassigned' activity + former-assignee
--     notification), which is the intended side effect chain.
create or replace function public.trg_deactivate_assignment_on_terminal()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  update public.report_assignments
  set active = false
  where report_id = NEW.id and active;

  return new;
end;
$$;

create trigger reports_after_update_terminal
  after update on public.reports
  for each row
  when (OLD.status is distinct from NEW.status
        and NEW.status in ('resolved', 'rejected', 'closed'))
  execute function public.trg_deactivate_assignment_on_terminal();

-- =============================================================================
-- 3. report_assignments triggers
-- =============================================================================

-- 3.1 BEFORE INSERT -> atomically deactivate the previous active assignment
--     (single statement; works with the F8 partial unique index). The nested
--     UPDATE fires the deactivation logging trigger for the former assignee.
create or replace function public.trg_deactivate_prior_assignment()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if NEW.active then
    update public.report_assignments
    set active = false
    where report_id = NEW.report_id and active;
  end if;

  return new;
end;
$$;

create trigger assignments_before_insert_deactivate_prior
  before insert on public.report_assignments
  for each row execute function public.trg_deactivate_prior_assignment();

-- 3.2 AFTER INSERT -> activity 'assigned' {assigned_to, notes} + notification
--     to the new assignee (D9).
create or replace function public.trg_log_assignment_created()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if auth.uid() is not null then
    perform public.server_activity(
      NEW.report_id,
      auth.uid(),
      'assigned',
      jsonb_build_object('assigned_to', NEW.assigned_to, 'notes', NEW.notes)
    );
  end if;

  perform public.server_notify(
    NEW.assigned_to,
    'New assignment',
    'A report has been assigned to you',
    'assignment',
    NEW.report_id
  );

  return new;
end;
$$;

create trigger assignments_after_insert_log
  after insert on public.report_assignments
  for each row execute function public.trg_log_assignment_created();

-- 3.3 AFTER active true->false -> activity 'unassigned' {assigned_to} +
--     notification to the former assignee (D9). Fires for client deactivation,
--     terminal-transition deactivation, and reassignment deactivation alike.
create or replace function public.trg_log_assignment_deactivated()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if auth.uid() is not null then
    perform public.server_activity(
      OLD.report_id,
      auth.uid(),
      'unassigned',
      jsonb_build_object('assigned_to', OLD.assigned_to)
    );
  end if;

  perform public.server_notify(
    OLD.assigned_to,
    'Assignment removed',
    'The assignment on one of your reports was deactivated',
    'assignment',
    OLD.report_id
  );

  return new;
end;
$$;

create trigger assignments_after_update_deactivate
  after update on public.report_assignments
  for each row
  when (OLD.active and not NEW.active)
  execute function public.trg_log_assignment_deactivated();

-- Defense in depth: trigger entry points are context-protected anyway (they
-- fail outside a trigger call), but revoke default PUBLIC execute so no client
-- role can even attempt them.
revoke all on function public.trg_log_report_created() from public;
revoke all on function public.trg_log_status_change() from public;
revoke all on function public.trg_log_soft_delete_restore() from public;
revoke all on function public.trg_deactivate_assignment_on_terminal() from public;
revoke all on function public.trg_deactivate_prior_assignment() from public;
revoke all on function public.trg_log_assignment_created() from public;
revoke all on function public.trg_log_assignment_deactivated() from public;

-- Note: exact notification title/body copy is presentational and may be refined
-- by the app layer; types, recipients, activity metadata and side effects match
-- REPORT_LIFECYCLE.md §7-§8 exactly. No new product behavior is introduced.
