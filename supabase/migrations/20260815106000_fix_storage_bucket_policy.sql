-- Phase 2 — Reports System (fix): storage.buckets visibility.
--
-- ROOT CAUSE (reproduced live, 2026-08-15): the evidence bucket row was
-- created directly in storage.buckets by the migration, but storage.buckets
-- has RLS enabled with NO select policy. The storage service evaluates
-- bucket lookups as the requesting user, so every authenticated request saw
-- the bucket as missing (GET /bucket -> [], GET /bucket/evidence -> 404) and
-- every upload was rejected (403). Creating a bucket via the dashboard or
-- the Storage API auto-creates exactly this policy; the migration path
-- omitted it.
--
-- FIX: allow all authenticated users to see buckets. Object-level access is
-- still fully gated by the storage.objects policies (evidence_select_visible
-- / evidence_insert_owner / evidence_delete_admin); the private bucket name
-- is not sensitive (it appears in object paths anyway).

create policy "bucket_select_authenticated"
  on storage.buckets
  for select to authenticated
  using (true);
