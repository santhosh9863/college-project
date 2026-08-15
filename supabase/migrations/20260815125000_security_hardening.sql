-- Phase 2.10: Security hardening — align function ACLs with intent.
--
-- Supabase's platform default privileges grant EXECUTE on every new function
-- to anon/authenticated/service_role at creation time, so the earlier
-- `revoke ... from public` did NOT remove those role-level grants from the
-- stored ACL (PostgREST empirically hides the helpers anyway — 404 — but the
-- ACL should not promise what we do not intend).
--
-- 1. server_notify / server_activity are server-write helpers called ONLY
--    from SECURITY DEFINER trigger functions (which run as the owner). No
--    client role needs EXECUTE: revoke from anon and authenticated.
-- 2. Every other public function is view/check gating used by RLS policies
--    and the app (authenticated only): revoke EXECUTE from anon so the anon
--    role cannot invoke them at all.
-- 3. Drop the ad-hoc diagnostics table (public.repro_diag) created during
--    live verification; it had default PUBLIC grants and is not part of the
--    schema. Nothing references it.

revoke execute on function public.server_notify(uuid, text, text, text, uuid) from anon, authenticated;
revoke execute on function public.server_activity(uuid, uuid, text, jsonb) from anon, authenticated;

revoke execute on function public.my_role() from anon;
revoke execute on function public.my_community_id() from anon;
revoke execute on function public.report_visible_to_staff(uuid) from anon;
revoke execute on function public.report_visible_to_caller(uuid) from anon;
revoke execute on function public.report_visible_to_caller_row(uuid, uuid, uuid, timestamptz) from anon;
revoke execute on function public.can_create_report(public.report_type, public.report_status, uuid, uuid, double precision, uuid, timestamptz) from anon;
revoke execute on function public.can_transition_status(uuid, public.report_status) from anon;
revoke execute on function public.can_update_report_row(uuid) from anon;
revoke execute on function public.can_update_report(uuid, public.report_status, timestamptz) from anon;
revoke execute on function public.can_manage_assignment(uuid, uuid) from anon;
revoke execute on function public.routed_staff_for_report(uuid) from anon;
revoke execute on function public.storage_evidence_report_id(text) from anon;
revoke execute on function public.list_assignable_staff() from anon;
revoke execute on function public.analytics_overview() from anon;

drop table public.repro_diag;