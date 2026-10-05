-- =============================================================================
-- 20261005150000_fix_policy_self_read.sql
--
-- FIX (supersedes the approach in 20261005140000): stop the reports UPDATE
-- policy functions from re-reading the row they are authorising.
--
-- SYMPTOM, still live after 20261005140000
--   u8 "a student may soft-delete her own pending report"
--     pgerror: new row violates row-level security policy for table "reports"
--
-- WHAT THE INSTRUMENTED SUITE ALREADY PROVED
--   * policies in the live database match the repo exactly - no drift, no
--     restrictive policy, one UPDATE policy, check_expr =
--     can_update_report(id, status, deleted_at)
--   * called directly as alice, can_update_report(...20,'pending',now())
--     returns TRUE
--   * my_role()='student', auth.uid() correct, alice owns ...20, ...20 is
--     visible to alice, old state reads 'pending / null'
--   * admin moderation soft-delete (same statement shape) SUCCEEDS
--
-- So the function is arithmetically correct and the policy text is correct,
-- yet the policy's own invocation of it returns false. The difference must be
-- the *context* in which the policy calls it.
--
-- THE DEFECT BEING FIXED
--   The student branch of can_update_report() re-read the row twice:
--
--     (a) select r.status, r.deleted_at into v_old_status, v_old_deleted_at
--           from public.reports r where r.id = p_report_id for update;
--
--     (b) and (fatal) exists (
--           select 1 from public.reports r
--           where r.id = p_report_id and r.reporter_id = auth.uid())
--
--   Both reads are SELECTs against public.reports, so both are evaluated under
--   reports' own SELECT policy - report_visible_to_caller_row(). For a student
--   that policy's branch is:
--
--       when 'student' then r.reporter_id = auth.uid() and p_deleted_at is null
--
--   Note the second conjunct. It tests the very column this UPDATE is setting.
--   Called as a standalone statement the row still has deleted_at = null, so
--   the read passes and the gate returns true - which is exactly what the
--   diagnostics recorded. Invoked as the policy's WITH CHECK, the read is
--   evaluated once the new tuple exists, reports' SELECT policy is re-checked
--   against it, p_deleted_at is now non-null, the row ceases to be visible to
--   alice, and:
--
--       exists (...)        -> false      (reporter check disappears)
--       OR the locked read  -> no row     (v_old_status stays NULL)
--
--   Either way the conjunction is false and the UPDATE is refused with 42501.
--
--   The `exists` clause is the decisive one, and it is why the fault looked
--   inexplicable. The direct-call diagnostic returned true, so the obvious
--   reading was "the function is fine, the policy wiring is wrong". But the
--   wired policy is verbatim what the migration defines, so that could not be
--   it either. The resolution is that the function is correct AND the wiring is
--   correct, and the *self-read* is what breaks: a policy helper that re-reads
--   its own row is only safe while reports' SELECT policy ignores the columns
--   being updated. A student's does not; a staff member's does, because
--   report_visible_to_caller_row answers `when 'admin' then true`
--   unconditionally and the hod/technician/operations branches delegate to
--   report_visible_to_staff(), which never considers deleted_at.
--
--   That is the entire asymmetry. Student is the only role whose SELECT
--   visibility depends on the column the UPDATE changes, and it is the only
--   role whose branch contained a self-read. Admin soft-deletes fine; alice
--   cannot.
--
--   Same class of bug as 20260815103000, where report_visible_to_caller(id)
--   made INSERT ... RETURNING fail for every student with the same 42501. The
--   precedent there was explicit: take the row's own columns as arguments
--   rather than re-reading the table. That is what this migration does.
--
-- THE CHANGE
--   USING gains the row's own columns, so ownership and prior state are read
--   from the tuple directly instead of from the table:
--       using (can_update_report_row(id, status, deleted_at, reporter_id))
--   The student branch of can_update_report() then validates only the NEW
--   values and performs no table read at all. Prior-state conditions
--   (not already deleted, status pending, caller is the reporter) are enforced
--   in USING, which is evaluated against the pre-update row.
--
--   Staff keep their existing logic and their existing table read, byte for
--   byte, because their SELECT-policy branch delegates to
--   report_visible_to_staff(), which does not consider deleted_at and so is
--   unaffected. Every staff test already passes.
--
-- NOT A PRIVILEGE LOOSENING
--   A student can still only reach rows that USING accepts, and USING now
--   demands all three of: prior deleted_at IS NULL, prior status 'pending',
--   and reporter_id = auth.uid() - read from the tuple, so none of it can be
--   filtered away. WITH CHECK then demands the new deleted_at IS NOT NULL and
--   status unchanged. A student therefore cannot delete a report twice, cannot
--   touch a non-pending report, cannot touch anyone else's report, and cannot
--   smuggle a status change out inside the same UPDATE, because 'resolved'
--   would fail new_status = 'pending'.
--   An unknown report id never reaches WITH CHECK: USING is only evaluated for
--   rows the UPDATE actually matched, so existence is still not disclosed (F5).
--
-- VERIFICATION
--   supabase/tests/rls_policy_tests.sql must report 92 / 92 / 0 failures with
--   0 fixture problems after this is applied.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. USING gate, now row-aware: takes the prior state from the tuple.
-- -----------------------------------------------------------------------------
create or replace function public.can_update_report_row(
  p_report_id uuid,
  p_status public.report_status,
  p_deleted_at timestamptz,
  p_reporter_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case public.my_role()
    when 'student' then
      -- Own report, still pending, not already deleted. All three are read
      -- from the tuple's own columns, so no self-reference to filter.
      p_deleted_at is null
      and p_status = 'pending'
      and p_reporter_id = auth.uid()
    when 'hod'         then public.report_visible_to_staff(p_report_id)
    when 'technician'  then public.report_visible_to_staff(p_report_id)
    when 'operations'  then public.report_visible_to_staff(p_report_id)
    when 'admin'       then public.report_visible_to_staff(p_report_id)
    else false
  end
$$;

revoke all on function public.can_update_report_row(uuid, public.report_status, timestamptz, uuid) from public;
grant execute on function public.can_update_report_row(uuid, public.report_status, timestamptz, uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- 2. WITH CHECK gate. The student branch performs NO table read; the staff
--    branch is unchanged.
-- -----------------------------------------------------------------------------
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
  v_role := public.my_role();

  -- Student: validate the incoming values only.
  --
  -- USING (can_update_report_row) has already established, against the
  -- pre-update row, that this report is the caller's own, is 'pending', and is
  -- not already deleted. Re-deriving any of that here would mean reading the
  -- row back mid-UPDATE, which is exactly what makes this policy fragile.
  if v_role = 'student' then
    return p_new_deleted_at is not null
       and p_new_status = 'pending';
  end if;

  -- Staff: unchanged. Their SELECT-policy branch delegates to
  -- report_visible_to_staff(), which ignores deleted_at, so this read is not
  -- filtered and the old state is read correctly.
  if v_role in ('hod', 'technician', 'operations', 'admin') then
    select r.status, r.deleted_at into v_old_status, v_old_deleted_at
    from public.reports r
    where r.id = p_report_id
    for update;

    -- Unknown report: refuse without disclosing that it does not exist (F5).
    if v_old_status is null then
      return false;
    end if;

    if not public.report_visible_to_staff(p_report_id) then
      return false;
    end if;

    -- restore: admin only, status must be preserved (F1) - a restore may not
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

revoke all on function public.can_update_report(uuid, public.report_status, timestamptz) from public;
grant execute on function public.can_update_report(uuid, public.report_status, timestamptz) to authenticated;

-- -----------------------------------------------------------------------------
-- 3. Rewire the policy onto the row-aware USING gate.
-- -----------------------------------------------------------------------------
drop policy if exists "reports_update_gated" on public.reports;

create policy "reports_update_gated"
  on public.reports
  for update to authenticated
  using (public.can_update_report_row(id, status, deleted_at, reporter_id))
  with check (public.can_update_report(id, status, deleted_at));

-- -----------------------------------------------------------------------------
-- 4. Retire the superseded one-argument USING helper so nothing can bind to it.
-- -----------------------------------------------------------------------------
drop function if exists public.can_update_report_row(uuid);
