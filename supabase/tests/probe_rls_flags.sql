-- ============================================================================
-- HYPOTHESIS UNDER TEST
--
-- can_update_report() reads its own row:
--     select r.status, r.deleted_at into v_old_status, v_old_deleted_at
--     from public.reports r where r.id = p_report_id for update;
--
-- If that read is subject to reports' own RLS, then during the UPDATE the
-- engine's EvalPlanQual re-checks the SELECT policy against the NEW tuple --
-- where deleted_at is already set. The student branch of
-- report_visible_to_caller_row requires `p_deleted_at is null`, so the row
-- disappears, the subquery returns NO ROW, v_old_status stays NULL, and the
-- function returns false -> 42501.
--
-- This predicts four things we have already observed:
--   1. Calling can_update_report() directly OUTSIDE an update returns TRUE
--      (old tuple, deleted_at is null, row visible).
--   2. Calling it as the UPDATE policy does returns FALSE.
--   3. ADMIN soft-delete PASSES - because report_visible_to_caller_row has
--      `when 'admin' then true`, so the row is never filtered for admin.
--   4. Rewriting the guard changes nothing, because the `for update` read
--      fails in exactly the same way the old visibility guard did.
--
-- That last point is why the first fix appeared to change the error not at all.
--
-- One query, one result set: the flags and ownership that decide this.
-- ============================================================================

select 'reports.relrowsecurity' as what, relrowsecurity::text as value
  from pg_class where oid = 'public.reports'::regclass
union all
select 'reports.relforcerowsecurity', relforcerowsecurity::text
  from pg_class where oid = 'public.reports'::regclass
union all
select 'reports owner', pg_get_userbyid(relowner)
  from pg_class where oid = 'public.reports'::regclass
union all
select 'current_user', current_user
union all
select 'session_user', session_user
union all
select 'authenticated has BYPASSRLS', rolbypassrls::text
  from pg_roles where rolname = 'authenticated'
union all
select 'anon has BYPASSRLS', rolbypassrls::text
  from pg_roles where rolname = 'anon'
union all
select 'can_update_report owner',
       (select pg_get_userbyid(p.proowner)
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname = 'can_update_report'
           and p.pronargs = 3)
union all
select 'can_update_report security_definer',
       (select p.prosecdef::text
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname = 'can_update_report'
           and p.pronargs = 3)
union all
select 'can_update_report proconfig',
       (select coalesce(array_to_string(p.proconfig, ', '), '(none)')
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname = 'can_update_report'
           and p.pronargs = 3)
union all
select 'can_update_report live body is the NEW one (has student branch first)',
       (select case when position('if v_role = ''student''' in p.prosrc) > 0
                    then 'yes - 20261005140000 IS applied'
                    else 'no - OLD body still live' end
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname = 'can_update_report'
           and p.pronargs = 3)
union all
select 'reports_select_visible permissive', permissive::text
  from pg_policies
 where schemaname = 'public' and tablename = 'reports'
   and policyname = 'reports_select_visible';
