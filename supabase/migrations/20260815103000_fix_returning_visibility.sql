-- Phase 2 — Reports System (fix): INSERT ... RETURNING visibility.
--
-- ROOT CAUSE (reproduced live, 2026-08-15): reports_select_visible uses
-- report_visible_to_caller(id), which re-reads public.reports in a subquery
-- to prove visibility. PostgreSQL applies SELECT policies to the rows
-- returned by INSERT ... RETURNING, and a subquery inside the same statement
-- cannot see the just-inserted row (MVCC snapshot). The visibility check
-- therefore evaluated FALSE for every freshly created report and the whole
-- INSERT was rejected with 42501. The Flutter client always requests the
-- returned row (.insert(...).select('id').single()), so report creation
-- failed for every student.
--
-- FIX: a row-aware helper, report_visible_to_caller_row, evaluates the
-- student branch from the row's OWN columns (community_id, reporter_id,
-- deleted_at) — no self-reference. Staff/admin branches delegate to the
-- existing helpers (semantics preserved: u1, u2, F5). Only the SELECT
-- policy on reports needs the row-aware form; every other policy that calls
-- report_visible_to_caller(report_id) references an EXISTING parent report
-- row, which is unaffected.

create or replace function public.report_visible_to_caller_row(
  p_report_id uuid,
  p_community_id uuid,
  p_reporter_id uuid,
  p_deleted_at timestamptz
)
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
    else p_deleted_at is null
      and (p_community_id = public.my_community_id() or p_reporter_id = auth.uid())
  end
$$;

revoke all on function public.report_visible_to_caller_row(uuid, uuid, uuid, timestamptz) from public;
grant execute on function public.report_visible_to_caller_row(uuid, uuid, uuid, timestamptz) to authenticated;

drop policy "reports_select_visible" on public.reports;

create policy "reports_select_visible"
  on public.reports
  for select to authenticated
  using (public.report_visible_to_caller_row(id, community_id, reporter_id, deleted_at));
