-- Phase 2 — Panel System (Phase 2.2): corrective fix for routed_staff_for_report.
--
-- The 20260815121000 helper was declared `returns setof uuid`; a bare
-- set-of-scalar column is named after the function, so the trigger references
-- `s.id` in 20260815121000 were invalid at runtime and would abort the
-- created/reopened notification inserts. Redefines the helper with an explicit
-- output column (`user_id`) and updates both trigger recipient selects.
-- No behavioral change: same D1-scoped recipient set (PANEL_SYSTEM.md §2, D1).

create or replace function public.routed_staff_for_report(p_report_id uuid)
returns table (user_id uuid)
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
  select s.user_id, 'New report', NEW.title, 'report_new', NEW.id, false
  from public.routed_staff_for_report(NEW.id) s
  where s.user_id <> NEW.reporter_id;

  return new;
end;
$$;

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
    select s.user_id, 'Report reopened', NEW.title, 'status_change', NEW.id, false
    from public.routed_staff_for_report(NEW.id) s
    where s.user_id <> NEW.reporter_id;
  end if;

  return new;
end;
$$;
