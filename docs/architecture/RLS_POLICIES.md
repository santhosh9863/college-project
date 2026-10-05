# Row-Level Security Policies

> RLS policy design for the college project database, enforcing role-based access and community isolation at the database level.
> ⚠️ **Status: IMPLEMENTED — this document describes the design; the SQL is applied.**
> Its header previously read "NO RLS SQL written or applied yet" and `:232` repeated it.
> In fact `20260811103300_rls_security.sql` defines 28 policies and 25 helpers,
> `20260811103400_server_generated_events.sql` adds the audit triggers, and
> `20260815125000_security_hardening.sql` closes the EXECUTE grants. There are 32 live
> policies across 15 tables plus Storage.
> **Read `docs/decisions/ADR-002-Database.md` for the schema and security model as
> built.** Two rows below are wrong as written — u23 and the u2/u10 grants — and are
> marked inline.
> **These policies are executable, not just documented:** `supabase/tests/rls_policy_tests.sql`
> asserts u1–u23 against a live database — see §7.
> **Dependencies cleared:** u22 via `docs/architecture/JWT_AUTH_COMPATIBILITY.md`;
> u7 via `docs/architecture/REPORT_LIFECYCLE.md` (D1–D10 + amended matrix). Note the
> lifecycle is D1–D10, not D1–D9; D10 is the removed `pending → resolved` transition.

---

## Table of Contents

1. [Approved Decisions](#1-approved-decisions)
2. [Identity & Helpers](#2-identity--helpers)
3. [Policy Matrix](#3-policy-matrix)
4. [Cross-Cutting Guards](#4-cross-cutting-guards)
5. [Dependencies & Blockers](#5-dependencies--blockers)
6. [Implementation Order (after approval)](#6-implementation-order-after-approval)
7. [Executable Verification](#7-executable-verification)

---

## 1. Approved Decisions

All rows below are APPROVED by the project owner (2026-08). u22 and u7 are resolved as documented dependencies (see §5).

| # | Decision | Status |
|---|---|---|
| u1 | Students may see their own historical reports from previous communities. | ✅ Approved |
| u2 | Authorized staff may see soft-deleted reports; students never see deleted reports. | ✅ Approved |
| u3 | MVP uses community reports only. Do not expose private-report semantics yet. | ✅ Approved |
| u4 | Students may choose priority. AI may predict/recommend priority but must not silently overwrite the student's value. | ✅ Approved |
| u5 | Staff cannot create reports in MVP. | ✅ Approved |
| u6 | Students cannot edit reports in MVP. | ✅ Approved |
| u7 | Do NOT implement staff status-transition policies yet. Lifecycle/state machine must be documented first. | ✅ Approved — `REPORT_LIFECYCLE.md` (D1–D9 + amendment) |
| u8 | A student may soft-delete their own report while it is pending. Authorized staff/admin may perform moderation/deletion per their authority. Students never see deleted reports. | ✅ Approved |
| u9 | Operations and Admin may manually assign/reassign reports. HOD and Technician are receivers/readers for MVP, not manual assigners. | ✅ Approved |
| u10 | Students cannot support their own report. | ✅ Approved |
| u11 | Students may support only reports with status: `pending`, `under_review`, `in_progress`. | ✅ Approved |
| u12 | Staff cannot support reports. | ✅ Approved |
| u13 | Students may withdraw their own support. Support comments cannot be edited in MVP. | ✅ Approved |
| u14 | Comments cannot be edited in MVP. Authors may delete their own comments. Admin may moderate/delete comments. | ✅ Approved |
| u15 | `report_activity` must be server-generated only. No direct client INSERT/UPDATE/DELETE. | ✅ Approved |
| u16 | Students may upload evidence only to reports they own. | ✅ Approved |
| u17 | Evidence deletion/moderation is Admin-only for MVP. | ✅ Approved |
| u18 | `ai_classification_log` is Admin-only. | ✅ Approved |
| u19 | Users may dismiss/delete their own notifications. | ✅ Approved |
| u20 | Authenticated users may read `departments` as reference data. | ✅ Approved |
| u21 | `category_routes` are visible only to staff. | ✅ Approved |
| u22 | JWT/auth compatibility with Supabase RLS — NOT assumed; under investigation. | ✅ Approved — native Supabase Auth sessions (`JWT_AUTH_COMPATIBILITY.md`); `auth.users.id = profiles.id = auth.uid()` |
| u23 | ~~Staff department-specific scoping is deferred. MVP staff visibility uses category routing + assignments.~~ **SUPERSEDED — scoping IS implemented.** `20260815121000_staff_department_scope.sql:43-52` redefines `report_visible_to_staff` to require `p.department_id = r.department_id` on the routing branch, and cites locked decision D1 of `PANEL_SYSTEM.md`. Consequence: staff with `department_id IS NULL` see **only assigned reports**, not category-routed ones. | ⚠️ Superseded — see ADR-002 §5.3 |

---

## 2. Identity & Helpers

All policies key off `auth.uid()` (the JWT subject) = `profiles.id` (1:1 with `auth.users`) — approved identity model (u22, `JWT_AUTH_COMPATIBILITY.md`).

| Helper (concept) | Purpose |
|---|---|
| `me` | `auth.uid()` — must always equal `profiles.id` |
| `my_role` | caller's `profiles.role` (database is the source of truth, not JWT claims) — via a `SECURITY DEFINER` helper to avoid RLS recursion on `profiles` |
| `my_community_id` | `community_members.community_id` where `profile_id = me AND is_active = true` (helper function; MVP = exactly one active community) |
| `staff` | `my_role IN (hod, technician, operations, admin)` |

---

## 3. Policy Matrix

Legend: **S**=student, **H**=hod, **T**=technician, **O**=operations, **A**=admin. "Routed/assigned" for staff = `category_id` routes to the caller's role (`category_routes`) OR an active assignment to the caller (`report_assignments` where `active = true`). All predicates are design-level descriptions; SQL generation is pending explicit authorization.

### 3.1 profiles
| Op | Who | Rule |
|---|---|---|
| SELECT | S, H, T, O | `id = me` only |
| SELECT | A | all rows (admin manages `community_pending`, staff provisioning later) |
| INSERT | — | **DENY all** — profile created only by the auth Edge Function via `service_role` |
| UPDATE | S, H, T, O | **DENY for MVP** (no self-edit feature; prevents role/semester/section/student_id tampering) |
| UPDATE | A | all (staff provisioning/role fixes later) |
| DELETE | — | **DENY all** (lifecycle via `auth.users` cascade) |
| Guards | — | `role` never client-settable or client-changeable |

### 3.2 communities
| Op | Who | Rule |
|---|---|---|
| SELECT | S | only communities where `me` has an **active membership** |
| SELECT | H, T, O, A | all (staff serve across classes; routing is global per u23) |
| INSERT | — | **DENY all** — idempotent get-or-create by auth service (`service_role`), never client |
| UPDATE / DELETE | — | **DENY all** — `display_name` is derived, not user-typed |

### 3.3 community_members
| Op | Who | Rule |
|---|---|---|
| SELECT | S | `profile_id = me` only (enables the community-scope subquery used by every other policy) |
| SELECT | H, T, O, A | all |
| INSERT | S | **DENY** — the client never chooses its class (locked decision 7) |
| INSERT | A | allowed — admin assigns `community_pending` students |
| UPDATE | S | **DENY** — cannot flip own `is_active`/move community |
| UPDATE | A | allowed — deactivate/reactivate membership (semester rollover) |
| DELETE | — | **DENY all** — history preserved via `is_active`/`left_at` |

### 3.4 reports
| Op | Who | Rule |
|---|---|---|
| SELECT | S | `(community_id = my_community_id OR reporter_id = me) AND deleted_at IS NULL` — u1 allows own historical reports; u2 keeps deleted reports invisible to students |
| SELECT | H, T, O | routed/assigned — **including soft-deleted** (u2); **plus department scoping (u23 superseded)** — `20260815121000` |
| SELECT | A | all, including soft-deleted |
| INSERT | S | `reporter_id = me AND community_id = my_community_id AND status = 'pending' AND deleted_at IS NULL AND ai_confidence IS NULL AND duplicate_of IS NULL`; `report_type` = community only (u3); `priority` chosen by student, AI must not silently overwrite (u4) |
| INSERT | H, T, O | **DENY** (u5 — staff cannot create reports in MVP) |
| INSERT | A | allowed (support/test data) |
| UPDATE | S | **DENY** (u6 — no editing in MVP). Soft delete of own **pending** report via `UPDATE deleted_at` only (u8) — i.e., the single permitted student UPDATE is `deleted_at` on own-pending rows |
| UPDATE | H, T, O | `status` transitions **per the approved lifecycle matrix** (`REPORT_LIFECYCLE.md` §3) — forward/reject/reopen edges valid for the actor's role (D1–D9); validations via `SECURITY DEFINER` transition helper; staff soft-delete of visible reports per u8 |
| UPDATE | A | all, incl. `deleted_at = null` restore and moderation (u8) |
| DELETE | — | **DENY all** — soft delete only |

### 3.5 report_assignments
| Op | Who | Rule |
|---|---|---|
| SELECT | S | reports visible to them (community scope; shows assignee read-only) |
| SELECT | H, T, O | routed/assigned reports; A: all |
| INSERT | S | **DENY** |
| INSERT | O, A | allowed — manual assignment (u9); `assigned_by = me`, `active = true`; prior assignment deactivated at trigger/app layer |
| INSERT | H, T | **DENY** (u9 — receivers/readers, not manual assigners) |
| UPDATE / DELETE | S | **DENY** |
| UPDATE / DELETE | H, T | **DENY** |
| UPDATE | O, A | history-preserving reassignment (deactivate/reactivate); no hard delete |

### 3.6 report_supports
| Op | Who | Rule |
|---|---|---|
| SELECT | S | `report.community_id = my_community_id` (or own report per u1) |
| SELECT | H, T, O, A | routed/assigned (or all for A) |
| INSERT | S | `supporter_id = me AND report in my_community AND report.deleted_at IS NULL AND supporter_id != reporter_id` (u10) AND `report.status IN (pending, under_review, in_progress)` (u11) |
| INSERT | staff | **DENY** (u12) |
| UPDATE | S | **DENY** — support comments cannot be edited (u13) |
| DELETE | S | own row allowed — withdraw support (u13) |
| UPDATE / DELETE | staff | **DENY** |

### 3.7 report_comments
| Op | Who | Rule |
|---|---|---|
| SELECT | S | `report.community_id = my_community_id` (or own report per u1) |
| SELECT | H, T, O, A | routed/assigned / all |
| INSERT | S | `author_id = me AND report in my_community AND deleted_at IS NULL` |
| INSERT | H, T, O, A | on routed/assigned reports, `author_id = me` |
| UPDATE | S | **DENY** (u14 — no comment editing in MVP) |
| UPDATE | staff | **DENY** (u14 — no editing in MVP; moderation by deletion, not edit) |
| DELETE | S | own comments only (u14) |
| DELETE | A | all (moderation, u14) |

### 3.8 report_activity
| Op | Who | Rule |
|---|---|---|
| SELECT | S | `report.community_id = my_community_id` (or own report per u1) — timeline |
| SELECT | H, T, O, A | routed/assigned / all |
| INSERT | — | **DENY all clients** (u15) — server-generated only (triggers `SECURITY DEFINER` or `service_role`); `actor_id` set server-side, never spoofable |
| UPDATE / DELETE | — | **DENY all** — append-only audit trail |

### 3.9 evidence_files
| Op | Who | Rule |
|---|---|---|
| SELECT | S | `report.community_id = my_community_id` (or own report per u1) |
| SELECT | H, T, O, A | routed/assigned / all |
| INSERT | S | `uploaded_by = me AND report in my_community AND report.reporter_id = me` (u16 — own reports only) |
| INSERT | H, T, O | on routed/assigned reports, `uploaded_by = me` (staff attachment pending u7 clarity; default: allowed on reports they can see) |
| INSERT | A | all |
| UPDATE / DELETE | S, H, T, O | **DENY** |
| UPDATE / DELETE | A | allowed — moderation (u17) |
| Note | — | Storage **bucket** policies are a separate phase (not schema RLS) |

### 3.10 ai_classification_log
| Op | Who | Rule |
|---|---|---|
| SELECT | A | only (u18) |
| SELECT | S, H, T, O | **DENY** |
| INSERT | — | **DENY all clients** — written only by the AI Edge Function via `service_role` |
| UPDATE / DELETE | — | **DENY all** — append-only audit log |

### 3.11 notifications
| Op | Who | Rule |
|---|---|---|
| SELECT | all roles | `user_id = me` only |
| INSERT | — | **DENY all clients** — server-generated (`service_role`) |
| UPDATE | all roles | own rows, **`read` column only** (column-grant whitelist) |
| DELETE | all roles | own rows — dismiss (u19) |

### 3.12 departments (reference data)
| Op | Who | Rule |
|---|---|---|
| SELECT | all authenticated | read-only reference (u20) |
| INSERT / UPDATE / DELETE | — | **DENY** (seed/`service_role` only) |

### 3.13 categories (reference data)
| Op | Who | Rule |
|---|---|---|
| SELECT | all authenticated | required for report creation (category picker) |
| INSERT / UPDATE / DELETE | — | **DENY** (seed/`service_role` only) |

### 3.14 category_routes (routing internals)
| Op | Who | Rule |
|---|---|---|
| SELECT | staff only | u21 |
| SELECT | S | DENY |
| INSERT / UPDATE / DELETE | — | **DENY** (admin/`service_role` only) |

---

## 4. Cross-Cutting Guards

1. **Community isolation invariant** — every student-scoped SELECT/INSERT on report-related tables funnels through `community_id = my_community_id` (with the single u1 exception for own historical reports); no policy references another student's membership.
2. **No client writes to identity/social data** — `profiles`, `communities`, `community_members`, `ai_classification_log`, `notifications`, reference tables: writes only via `service_role` (auth/AI Edge Functions) or admin. The auth flow needs **zero** user-token INSERT policies.
3. **Role immutability** — `profiles.role` can never be set/changed by the row owner; only admin (or `service_role`) writes it.
4. **Soft-delete** — `deleted_at IS NULL` on every student-scoped predicate (u2); staff see deleted; admin manages restore.
5. **Append-only audit** — `report_activity`, `ai_classification_log`: no UPDATE/DELETE policies at all (u15, u18).
6. **Priority integrity** — student-chosen `priority` (u4); the AI Edge Function records predictions in `ai_classification_log` and must not silently overwrite the student's value.
7. **Admin** — full visibility + repair rights (community assignment, restore soft-deletes, moderation) via the same identity channel (`auth.uid()`), not a separate role.

---

## 5. Dependencies (resolved)

| Dependency | Resolution |
|---|---|
| **u22 — JWT/auth compatibility** | ✅ **APPROVED** — `docs/architecture/JWT_AUTH_COMPATIBILITY.md`: native Supabase Auth sessions (admin `createUser` + `generateLink`/`verifyOtp` minting); identity model `auth.users.id = profiles.id = auth.uid()`. Linways remains the external college identity source; Supabase Auth provides the session used by RLS. |
| **u7 — report lifecycle/state machine** | ✅ **APPROVED** — `docs/architecture/REPORT_LIFECYCLE.md`: D1–D9 approved with the amendment that the direct `pending → resolved` transition is removed entirely (including Admin). Staff UPDATE policies will reference this matrix. |

---

## 6. Implementation Order (pending explicit authorization)

1. ~~Generate the RLS migration~~ — **done**, `20260811103300_rls_security.sql`.
2. ~~Apply via the established preflight flow~~ — **partly done**: 34 of 38 migrations
   were applied by hand through the SQL Editor (no Supabase CLI in this environment),
   so the `migration list --linked` / `db push` flow in this section was never used.
   `20261005130000` (evidence path prefix fix), `20261005120000` (staff seed) and
   `20261005123000` (AI-1) remain unapplied. `20261005140000` was applied but is
   **superseded and ineffective** — see §7; `20261005150000` is the real fix and is
   also unapplied.
3. ~~Prove the policies~~ — **done**: `supabase/tests/rls_policy_tests.sql` asserts
   u1–u23 and the lifecycle invariants it can currently reach against a live database
   (D1, D3, D5, D6, D8, D10) against a live database. See §7.

*This document is the design record. The applied SQL is the source of truth — see
`docs/decisions/ADR-002-Database.md` §1.1 for the full list of divergences.*

---

## 7. Executable Verification

`supabase/tests/rls_policy_tests.sql` is the executable form of this document. It
asserts every requirement in §1 and the lifecycle invariants from
`REPORT_LIFECYCLE.md` against a real database, rather than leaving them as prose.

Run it by pasting the whole file into the **Supabase SQL Editor**. There is no
Supabase CLI in this environment, so it cannot be run from the repo. It needs only
migrations through `20260815125000` and it works on either side of AI-1.

How it works, and why it is safe to point at a live database:

| Concern | Approach |
|---|---|
| No service-role key | Never used. It impersonates users with `set local role authenticated` plus `request.jwt.claims`, so every predicate resolves `auth.uid()` / `my_role()` exactly as it would in production. |
| No persistent state | Fixtures and helper objects are deleted explicitly, both before the assertions and after them, so an aborted run leaves nothing behind and re-running is safe. A final `ROLLBACK` is belt and braces. |
| Editor compatibility | Helpers live in an ordinary schema (`f1ce_rls`), not `pg_temp`, because the Supabase SQL Editor rejects `create function pg_temp.…` with `3F000: schema "pg_temp" does not exist`. Answer **Run without RLS** if prompted. |
| No pollution | Fixture rows are fresh uuids sharing the `f1ce0000` prefix, and every count filters on it, so a run measures the fixtures and not the existing data. The `GENERAL` department and the two `BCA 2024 S5/S6 C` communities are **resolved by key and reused** rather than inserted, because both have uniqueness constraints a fixture id cannot dodge. |
| "Denied" is not always an error | A `WHERE` matching only RLS-hidden rows updates **zero** rows and reports success. Every "must not change" test therefore asserts the resulting **row state** via a `SECURITY DEFINER` probe, which holds whether the statement raised or was silently filtered — and which also catches the dangerous case where it succeeded and did change the row. |

A failing assertion means the database disagrees with this document. That is the
point: it is either a real security bug or a documentation error, and both are
worth finding before a demo rather than after.

### 7.1 Verification status — read this before trusting §1

The suite has been **run twice against the live database (2026-10-05)**. It is not a
paper claim.

| Run | Result |
|---|---|
| 1st | 91 assertions — **89 passed, 2 failed**, 0 fixture problems |
| 2nd | 92 assertions — **91 passed, 1 failed**, 0 fixture problems |

Zero fixture problems on both runs is the load-bearing part: the 8 users, 2 communities
and 8 reports all built correctly, so every failure was a real disagreement rather
than harness noise.

**u1** was a wrong *test* expectation, now corrected — community B deliberately holds
two reports, and isolation is per-*community*.

**u8 is a genuine bug in this document's subject matter and is still open.** A student
cannot soft-delete their own pending report:

```
new row violates row-level security policy for table "reports"   (42501)
```

Root cause: the student branch of `can_update_report()` re-read the row via
`exists (select 1 from public.reports … where r.reporter_id = auth.uid())`. That is a
`SELECT` on `reports`, so **§1's own SELECT policy applies to it** — and for a student
that policy requires `deleted_at is null`, the exact column the UPDATE is setting.
Standalone the read passes; as `WITH CHECK` it is evaluated after the new tuple exists,
the row is no longer visible to the caller, and the gate returns false.

Only students are affected, and the reason is structural rather than accidental:
**a policy helper that re-reads its own row is safe only while the SELECT policy ignores
the columns being updated.** §1's `when 'admin' then true` is unconditional and the
staff branches delegate to `report_visible_to_staff()`, which ignores `deleted_at`, so
every staff path is immune. Student is the only role whose visibility depends on the
changing column, and the only role whose branch self-read. This is the same defect class
as the `INSERT … RETURNING` failure already fixed in `20260815103000`.

`20261005140000` was an attempt at this and **did not work** — it is applied to the live
database and must not be relied on. `20261005150000_fix_policy_self_read.sql` is the
real fix: it moves ownership and prior state into `USING`, which sees the pre-update
row, so no self-read remains. It is **not yet applied**. Full account, including why the
first attempt failed and what was ruled out, is in
`docs/development/CURRENT_STATE.md` §7c.
