-- Phase 2 — Reports System (fix): evidence object path parsing.
--
-- ROOT CAUSE (reproduced live, 2026-08-15): storage.objects.name does NOT
-- include the bucket — the storage service stores only the path below the
-- bucket root (e.g. '<report_id>/<file>.png' inside bucket 'evidence').
-- storage_evidence_report_id required a leading 'evidence' folder and returned
-- NULL for every real object name, so evidence_select_visible and
-- evidence_insert_owner rejected every read/write (403). Verified: the
-- client-simulated INSERT with the full path succeeded, while the service's
-- real upload (path without the bucket prefix) was rejected.
--
-- FIX: the first folder of the stored name IS the report id. Parse [1] and
-- keep the fail-closed guarantee: any path whose first folder is not a uuid
-- (or has no folder at all) resolves to NULL and every policy rejects it.

create or replace function public.storage_evidence_report_id(p_name text)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select (storage.foldername(p_name))[1]::uuid
$$;

revoke all on function public.storage_evidence_report_id(text) from public;
grant execute on function public.storage_evidence_report_id(text) to authenticated;
