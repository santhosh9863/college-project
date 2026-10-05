-- ============================================================================
-- Why does the u8 UPDATE fail when can_update_report() returns true when
-- called directly? Read the LIVE catalog instead of trusting the migrations.
-- Run all three; only the LAST result set is displayed, which is deliberate.
-- ============================================================================

-- 1. Are there extra overloads of can_update_report that a policy might bind to?
select p.oid::regprocedure as signature,
       p.prosecdef       as security_definer,
       p.provolatile,
       p.pronargs
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('can_update_report', 'can_update_report_row',
                    'report_visible_to_caller', 'report_visible_to_caller_row')
order by p.proname, p.oid::regprocedure::text;

-- 2. Did 20261005140000 actually land? Compare the live body against the repo.
select pg_get_functiondef(p.oid) as live_definition
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'can_update_report'
  and p.pronargs = 3;

-- 3. THE ONE THAT MATTERS. Every policy the live database actually has on
--    public.reports, with its real USING and WITH CHECK expressions.
--    The repo only knows about three policies (one SELECT, one INSERT, one
--    UPDATE). If this returns an UPDATE policy the migrations never created,
--    or a restrictive one, that is the answer.
select policyname,
       cmd,
       roles,
       permissive,
       coalesce(qual, '(none)')       as using_expr,
       coalesce(with_check, '(none)') as check_expr
from pg_policies
where schemaname = 'public'
  and tablename = 'reports'
order by cmd, policyname;
