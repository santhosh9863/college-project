-- Phase 2 - Reports System (fix round 2): evidence object path parsing.
--
-- ROOT CAUSE (identified by reading the client against the parser, 2026-10-05):
-- the two sides disagree about the object path.
--
--   client  flutter_app/lib/features/reports/data/reports_repository.dart:276-277
--             objectPath = 'evidence/$reportId/${...}_$safeName'
--           .storage.from('evidence').uploadBinary(objectPath, ...)
--           => storage.objects.name = 'evidence/<report_id>/<file>'
--
--   parser  20260815105000 took folder [1] and cast it to uuid, expecting
--           storage.objects.name = '<report_id>/<file>'.
--
-- storage.foldername('evidence/<rid>/<file>') = {evidence, <rid>}, so [1] is the
-- literal 'evidence' and 'evidence'::uuid raises
--   ERROR: invalid input syntax for type uuid: "evidence"
-- The declared fail-closed guarantee is also wrong as written: a bad ::uuid cast
-- throws, it does not return NULL, so a malformed path produced an error rather
-- than a clean denial.
--
-- The client has always sent the 'evidence/' prefix - it predates
-- 20260815105000 and was not changed by the commit that introduced it
-- (8b94a11 did not touch reports_repository.dart). So the prefix and the
-- post-15105 parser cannot both be right.
--
-- FIX: accept BOTH shapes rather than betting on which one is live, and make
-- the malformed case genuinely fail closed. An optional leading 'evidence/'
-- segment is stripped, the first remaining folder is taken, and it is admitted
-- only if it actually looks like a uuid. Anything else - no folder at all, a
-- non-uuid first folder, a NULL input - yields NULL, which every policy already
-- rejects.
--
-- The function signature is unchanged, so evidence_select_visible and
-- evidence_insert_owner pick up the new body with no policy changes.

create or replace function public.storage_evidence_report_id(p_name text)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select f.folder[1]::uuid
  from (
    select storage.foldername(
             case
               when (storage.foldername(p_name))[1] = 'evidence'
                 then regexp_replace(p_name, '^evidence/', '')
               else p_name
             end
           ) as folder
  ) f
  where f.folder[1] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
$$;

revoke all on function public.storage_evidence_report_id(text) from public;
grant execute on function public.storage_evidence_report_id(text) to authenticated;
