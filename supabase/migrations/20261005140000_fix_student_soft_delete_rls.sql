-- =============================================================================
-- 20261005140000_fix_student_soft_delete_rls.sql
--
-- FIX: a student can never soft-delete their own pending report (u8).
--
-- FOUND BY: supabase/tests/rls_policy_tests.sql, requirement u8:
--   "alice may soft-delete her own pending report"
--     expected: true
--     got:      WRONG STATE ... (statement was rejected by error)
--     pgerror:  new row violates row-level security policy for table "reports"
--
--   Every other assertion in that suite passes (91/92, and 0 fixture problems),
--   so this is a genuine policy defect, not a bad fixture. It is invisible to the
--   258 Flutter tests because they all mock the repository.
--
-- ROOT CAUSE
--   The UPDATE policy "reports_update_gated" is:
--       using      (public.can_update_report_row(id))
--       with check (public.can_update_report(id, status, deleted_at))
--
--   can_update_report() opened with a blanket visibility re-check:
--       if not public.report_visible_to_caller(p_report_id) then
--         return false;
--       end if;
--
--   and for a student, report_visible_to_caller() requires:
--       r.deleted_at is null
--       and (r.community_id = my_community_id() or r.reporter_id = auth.uid())
--
--   That is self-defeating for exactly the operation being authorised. The whole
--   point of a soft-delete is to SET deleted_at, and a soft-deleted report is by
--   design invisible to students (u2: "students never see soft-deleted reports,
--   INCLUDING their own"). The WITH CHECK expression is evaluated against the
--   post-update row, so deleted_at is already non-null by the time the guard
--   runs, the guard is unsatisfiable, and the UPDATE is rejected with 42501.
--
--   This is why only students were affected: the staff branch of the same
--   function gates on report_visible_to_staff(), which does NOT filter
--   deleted_at - so admin moderation soft-delete (also u8) worked fine, and so
--   did the admin restore (F1). The asymmetry is the tell.
--
--   Net effect in production: a student tapping "cancel my report" in the app
--   gets "new row violates row-level security policy" and the report silently
--   stays open.
--
-- THE FIX
--   Authorise the student branch by OWNERSHIP and by the specific transition,
--   and drop the blanket post-state visibility re-check. This is NOT a
--   privilege loosening:
--
--     * which rows a student may touch is still decided by the USING clause,
--       can_update_report_row(), which for a student means
--       "reporter_id = auth.uid()". Unchanged.
--     * the WITH CHECK still re-asserts ownership explicitly, plus
--       old deleted_at IS NULL, new deleted_at IS NOT NULL, and status
--       unchanged and 'pending'. Every one of those conditions is stricter
--       than the visibility re-check it replaces.
--     * the staff branch is byte-for-byte unchanged, including the
--       report_visible_to_staff() gate, the admin-only restore (F1), the
--       status-preserving moderation soft-delete (u8) and the lifecycle
--       transition path (D1-D10).
--     * an unknown report id still returns false without leaking existence
--       (F5), because the locked read below yields no row.
--
--   The staff branch keeps its own visibility gate, so removing the shared
--   top-of-function guard removes no check for staff.
-- =============================================================================

create or replace function public.can_update_report(
  p_report_id uuid,
  p_new_status public.report_status,
  p_new_deleted_at timestamptz
)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_old_status public.report_status;
  v_old_deleted_at timestamptz;
  v_role public.user_role;
begin
  -- Locked read first, so the old state we reason about cannot change
  -- underneath us (TOCTOU). A missing report leaves the variables null.
  select r.status, r.deleted_at into v_old_status, v_old_deleted_at
  from public.reports r
  where r.id = p_report_id
  for update;

  -- Unknown report: refuse without disclosing that it does not exist (F5).
  if v_old_status is null then
    return false;
  end if;

  v_role := public.my_role();

  -- Student: ownership + the one transition u8 allows. Deliberately does NOT
  -- re-check post-update visibility - see the header. Soft-deleting is what
  -- makes the report invisible to the student, so requiring continued
  -- visibility here forbids the operation outright.
  if v_role = 'student' then
    return v_old_deleted_at is null
       and p_new_deleted_at is not null
       and v_old_status = 'pending'
       and p_new_status = 'pending'
       and exists (
         select 1 from public.reports r
         where r.id = p_report_id and r.reporter_id = auth.uid()
       );
  end if;

  if v_role in ('hod', 'technician', 'operations', 'admin') then
    if not public.report_visible_to_staff(p_report_id) then
      return false;
    end if;

    -- restore: admin only, status must be preserved (F1) — a restore may not
    -- change status or bypass the lifecycle matrix (D4/D5/D8)
    if v_old_deleted_at is not null and p_new_deleted_at is null then
      return v_role = 'admin' and p_new_status = v_old_status;
    end if;

    -- moderation soft-delete: status must not change (u8)
    if p_new_deleted_at is not null then
      return v_old_deleted_at is null and p_new_status = v_old_status;
    end if;

    -- status transition: deleted_at stays null
    if p_new_status is distinct from v_old_status then
      return public.can_transition_status(p_report_id, p_new_status);
    end if;

    return true;
  end if;

  -- anon, or any role not listed above (e.g. a null role).
  return false;
end;
$$;

-- Privileges: the signature is unchanged, so the existing REVOKE/GRANT pairs
-- from 20260811103300_rls_security.sql still apply to this definition. Re-issue
-- them anyway so this migration is safe to apply to a database whose grants
-- were changed out of band.
revoke all on function public.can_update_report(uuid, public.report_status, timestamptz) from public;
grant execute on function public.can_update_report(uuid, public.report_status, timestamptz) to authenticated;
