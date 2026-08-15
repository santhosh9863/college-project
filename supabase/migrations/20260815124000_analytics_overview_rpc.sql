-- Phase 2.9: Analytics overview — view-gated aggregate RPC (D6).
--
-- Aggregates are computed in SQL over exactly the rows the caller may see:
-- the SAME predicate as the feed (report_visible_to_caller) — students see
-- their own reports, staff see department-routed + assigned + own, admin sees
-- everything. No client-side aggregation over the capped 50-row feed.
--
-- Soft-deleted reports are excluded from analytics for EVERYONE (moderation
-- removes a report from the project's active numbers; the admin moderation
-- queue still shows them separately).
--
-- Security: SECURITY DEFINER only to escape RLS self-joins; the visibility
-- predicate is re-evaluated per row with the caller's auth.uid(), so the
-- function returns nothing the caller could not already read.

create or replace function public.analytics_overview()
returns table (
  total_reports bigint,
  open_reports bigint,
  by_status jsonb,
  by_category jsonb,
  by_priority jsonb,
  resolved_avg_days numeric
)
language sql
stable
security definer
set search_path = ''
as $$
  with visible as (
    select r.status, r.priority, r.created_at, r.updated_at,
           c.name as category_name
    from public.reports r
    left join public.categories c on c.id = r.category_id
    where r.deleted_at is null
      and public.report_visible_to_caller(r.id)
  )
  select
    count(*)::bigint,
    (count(*) filter (where status in ('pending', 'under_review', 'in_progress')))::bigint,
    coalesce(
      (select jsonb_object_agg(s, c) from (
        select status::text as s, count(*)::bigint as c
        from visible group by status
      ) t),
      '{}'::jsonb
    ),
    coalesce(
      (select jsonb_object_agg(s, c) from (
        select coalesce(category_name, 'Uncategorized') as s, count(*)::bigint as c
        from visible group by category_name
      ) t),
      '{}'::jsonb
    ),
    coalesce(
      (select jsonb_object_agg(s, c) from (
        select priority::text as s, count(*)::bigint as c
        from visible group by priority
      ) t),
      '{}'::jsonb
    ),
    round(
      (select avg(extract(epoch from (updated_at - created_at)) / 86400.0)
       from visible where status = 'resolved'),
      1
    )
  from visible;
$$;

revoke all on function public.analytics_overview() from public;
grant execute on function public.analytics_overview() to authenticated;