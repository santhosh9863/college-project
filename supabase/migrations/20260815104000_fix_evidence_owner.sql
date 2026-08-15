-- Phase 2 — Reports System (fix): evidence upload owner column.
--
-- ROOT CAUSE (reproduced live, 2026-08-15): the storage service on this
-- platform does not populate storage.objects.owner for user uploads. Verified
-- with identical INSERT statements as the authenticated role: the upload
-- succeeds with owner = auth.uid() and is rejected (42501) with owner = null.
-- Because evidence_insert_owner required owner = auth.uid(), EVERY student
-- evidence upload returned 403, failing the create-report flow when evidence
-- was attached.
--
-- FIX: the exists() clause already scopes uploads strictly — students may
-- only attach files to their own reports, staff to staff-visible reports, and
-- invalid object paths fail closed via storage_evidence_report_id (NULL).
-- The owner conjunct is therefore redundant and is removed; upload provenance
-- remains enforced by the exists() check.

drop policy "evidence_insert_owner" on storage.objects;

create policy "evidence_insert_owner"
  on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'evidence'
    and exists (
      select 1 from public.reports r
      where r.id = public.storage_evidence_report_id(name)
        and r.deleted_at is null
        and (
          (public.my_role() = 'student' and r.reporter_id = auth.uid())
          or public.report_visible_to_staff(r.id)
        )
    )
  );
