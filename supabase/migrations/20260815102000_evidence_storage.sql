-- Phase 2 — Reports System (Part 2-A): private evidence storage.
-- Approved decision (BLOCKER 4): private bucket + storage RLS mirroring the
-- evidence_files policy (u16/u17):
--   * SELECT  — report viewers (report_visible_to_caller)
--   * INSERT  — owner upload to their own report, or staff-visible report
--   * DELETE  — admin only
--   * no UPDATE — evidence is immutable; re-upload = new object
-- Object path convention: evidence/<report_id>/<file_id>_<name>. The report id
-- is parsed from the path by a SECURITY DEFINER helper so an invalid path
-- fails closed (never an exception). 20 MiB limit; images + PDF (approved).
-- The student-facing create flow also writes the matching evidence_files row
-- (RLS-gated); the object itself is never publicly accessible.

-- 1. Private bucket (20 MiB; images + PDF)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'evidence',
  'evidence',
  false,
  20971520,
  array['image/png', 'image/jpeg', 'image/webp', 'image/heic', 'application/pdf']::text[]
)
on conflict (id) do nothing;

-- 2. Path helper: report id from an object name, or NULL (fail closed).
--    Array out-of-bounds access yields NULL in Postgres, so any path that is
--    not evidence/<uuid>/... resolves to NULL and every policy rejects it.
create or replace function public.storage_evidence_report_id(p_name text)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select (storage.foldername(p_name))[2]::uuid
  where (storage.foldername(p_name))[1] = 'evidence'
$$;

revoke all on function public.storage_evidence_report_id(text) from public;
grant execute on function public.storage_evidence_report_id(text) to authenticated;

-- 3. Storage RLS (already enabled by default on storage.objects in Supabase;
--    the ALTER would require table ownership, so it is intentionally omitted)
create policy "evidence_select_visible"
  on storage.objects
  for select to authenticated
  using (
    bucket_id = 'evidence'
    and public.report_visible_to_caller(public.storage_evidence_report_id(name))
  );

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

create policy "evidence_delete_admin"
  on storage.objects
  for delete to authenticated
  using (bucket_id = 'evidence' and public.my_role() = 'admin');
