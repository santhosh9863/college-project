-- Phase 2 — Reports System (fix round): restore evidence owner provenance.
--
-- Context: 20260815104000_fix_evidence_owner.sql removed the
-- storage.objects.owner conjunct after a live upload was rejected with the
-- storage service appearing not to set owner. Subsequent live verification
-- (2026-08-15, debug policy + object inspection) proved the service DOES set
-- owner = auth.uid() on user uploads; the real blockers were the object-path
-- parsing (20260815105000) and the missing storage.buckets select policy
-- (20260815106000). The owner conjunct is therefore restored as the
-- approved defense-in-depth check (storage design: owner provenance, u17).

drop policy "evidence_insert_owner" on storage.objects;

create policy "evidence_insert_owner"
  on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'evidence'
    and owner = auth.uid()
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
