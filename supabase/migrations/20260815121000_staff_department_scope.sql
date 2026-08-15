-- Phase 2 â€” Panel System (Phase 2.2): department-scoped staff routing (D1).
--
-- LOCKED decision D1 (docs/architecture/PANEL_SYSTEM.md Â§2): a staff member sees
-- category-routed reports only when reports.department_id = profiles.department_id.
-- The active-assignment branch stays unscoped (an explicit assignment always
-- grants visibility, any department). Admin sees all.
--
-- Consequences:
--   * report_visible_to_staff now joins profiles for the department comparison
--     (staff with NULL department_id fail closed on the routing branch â€” they
--     see only assigned reports until a department is set via the dashboard).
--   * Notification recipient sets (report created; reopened) are D1-scoped via
--     the new routed_staff_for_report() helper, so HODs of other departments are
--     not notified about this department's reports.
--   * No other helper/policy changes: assignment, evidence, comments, activity
--     and storage visibility all delegate to report_visible_to_staff already.

-- 1. Shared routed-recipient helper (owner-only, D1-scoped). Used by the
--    notification triggers so recipient semantics always match visibility.
create or replace function public.routed_staff_for_report(p_report_id uuid)
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select p.id
  from public.category_routes cr
  join public.reports r on r.id = p_report_id and r.category_id = cr.category_id
  join public.profiles p on p.role = cr.role and p.department_id = r.department_id
$$;

revoke all on function public.routed_staff_for_report(uuid) from public;

-- 2. D1 scope in staff visibility.
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
           join public.reports r on r.id = p_report_id
             and r.category_id = cr.category_id
           join public.profiles p on p.id = auth.uid()
             and p.role = cr.role
             and p.department_id = r.department_id
         )
      or exists (
           select 1
           from public.report_assignments ra
           where ra.report_id = p_report_id
             and ra.assigned_to = auth.uid()
             and ra.active
         )
$$;

-- 3. Notification triggers: D1-scoped recipients via the helper.
--    3.1 report created -> routed staff of the category AND department.
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
  select s.id, 'New report', NEW.title, 'report_new', NEW.id, false
  from public.routed_staff_for_report(NEW.id) s
  where s.id <> NEW.reporter_id;

  return new;
end;
$$;

--    3.2 reopen (resolved/rejected -> under_review/in_progress): routed staff
--        of the category AND department.
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
    select s.id, 'Report reopened', NEW.title, 'status_change', NEW.id, false
    from public.routed_staff_for_report(NEW.id) s
    where s.id <> NEW.reporter_id;
  end if;

  return new;
end;
$$;

