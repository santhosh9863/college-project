# Testing Strategy

> Testing philosophy, coverage goals, and testing approaches for all layers of the college project system.

> ⚠️ **Status: PARTIAL.** Sections 2–4 and 6–7 are still empty skeletons. Only
> §5 (RLS Policy Testing) is written, because the suite it describes now exists;
> everything else describes work that has not been done. See
> `docs/development/CURRENT_STATE.md` §7c for why the RLS layer was the gap that
> mattered most.

---

## Table of Contents

1. [Testing Philosophy](#1-testing-philosophy)
2. [Unit Testing](#2-unit-testing)
3. [Widget Testing](#3-widget-testing)
4. [Integration Testing](#4-integration-testing)
5. [RLS Policy Testing](#5-rls-policy-testing)
6. [AI Module Testing](#6-ai-module-testing)
7. [Test Coverage Goals](#7-test-coverage-goals)

---

## 1. Testing Philosophy

The security properties of this project are enforced **in the database**, not in
application code. That choice has a consequence for testing: the most important
assertions in the system cannot be written in Dart, because the Dart tests mock
every repository and never reach Postgres.

So the rule is: **a security claim is not a claim until something executes it.**
Documentation is not evidence, and neither is a passing test suite that stops at the
repository boundary.

---

## 2. Unit Testing

_(Empty — not yet written.)_

---

## 3. Widget Testing

_(Empty — not yet written.)_

---

## 4. Integration Testing

_(Empty — not yet written.)_

---

## 5. RLS Policy Testing

**The suite:** `supabase/tests/rls_policy_tests.sql`

Run it by pasting the whole file into the **Supabase SQL Editor** and pressing Run.
It prints a pass/fail table per requirement. There is no Supabase CLI, `psql` or
Docker in this environment, so it cannot be executed from the repo — this is a
manual step, not a `flutter test` target.

It covers all of u1–u23 from `RLS_POLICIES.md` plus the lifecycle invariants from
`REPORT_LIFECYCLE.md` that the current fixtures can reach — **D1, D3, D5, D6, D8 and
D10** — including the ones that are easy to regress because they are subtle:

**Known coverage gap.** D2, D4, D7 and D9 are **not** asserted yet, so this suite is
not yet full D1–D10 evidence:

| Missing | Requirement | Why it is missing | Fixture needed |
|---|---|---|---|
| D2 | `under_review → resolved` denied (must pass through `in_progress`) | Only `pending → resolved` (D10) is tested | one `under_review` fixture |
| D4 | `rejected → under_review` / `→ in_progress`, operations/admin only | no `rejected` fixture exists at all | one `rejected` fixture |
| D7 | technician/operations forward transitions on reports they can see | only `hod` forward transitions are exercised | technician visible `pending` fixture (exists — assertion still missing) |
| D9 | notification recipients emitted on status change | u19 proves per-user notification *isolation*, not the trigger's recipient selection | assert on a status-change notification |

| Area | What is asserted |
|---|---|
| Community isolation | A student sees their own community plus their own historical reports, and nothing else. Verified from both directions (alice cannot see carol's, carol cannot see alice's). |
| u2 deleted rows | Students never see soft-deleted reports, **including their own**; staff always do. |
| Lifecycle | The full state machine is exercised through `can_transition_status` / `can_update_report` — including the two roles that are easy to get wrong: `pending → resolved` is removed entirely, and `closed` is terminal **even for admin**. |
| D5 reopen | `resolved → under_review` is denied to hod and allowed to operations, with the fixture deliberately carrying an active assignment so the assertion tests the role check and not the D8 assignment requirement. |
| D8 assignment gate | `→ in_progress` is denied without an active assignment and allowed with one. |
| F5 no existence oracle | An unknown report id, and a report the caller cannot see, are both reported infeasible rather than distinguishable. |
| F1 restore | Admin may restore a soft-deleted report, but a restore that also changes the status is denied. |
| Department scoping (u23/D1) | Each staff role sees exactly its routed category, and the assignment branch is shown to cross department boundaries. |
| Privilege revocations | `report_activity`, `ai_classification_log` and comment edits are refused because the privilege is absent, not merely because a policy exists. |

### Why it needs no key and no cleanup

- **No service-role key.** Users are impersonated with `set local role
  authenticated` plus `request.jwt.claims`, which is precisely what PostgREST does.
  Every predicate resolves `auth.uid()` / `my_role()` as it would in production.
- **No persistence.** Fixtures and helper objects are deleted explicitly, both
  before the assertions and after them, so an aborted run cannot pollute the
  database and the script is safe to re-run. A final `ROLLBACK` is belt and
  braces. Everything deleted carries the `f1ce0000` prefix or an
  `@rls-test.local` email, so real data is never touched.
- **Editor compatible.** Helpers live in an ordinary schema (`f1ce_rls`), not
  `pg_temp`: the Supabase SQL Editor rejects `create function pg_temp.…` with
  `3F000: schema "pg_temp" does not exist`. Answer **Run without RLS** if
  prompted.
- **No collision with real data.** Fixture rows are fresh uuids sharing the
  `f1ce0000` prefix and every count filters on it. The `GENERAL` department and the
  `BCA 2024 S5/S6 C` communities are resolved by key and reused, because both tables
  have uniqueness constraints that a literal fixture id cannot dodge.

### The trap worth knowing about

**A denied operation does not necessarily raise an error.** When a `WHERE` clause
matches only rows that RLS hides, the `UPDATE`/`DELETE` matches zero rows and
reports success. A helper that waits for an exception therefore records `ALLOWED`
for a perfectly correct policy, and the suite fails for the wrong reason.

Every "must not change" assertion in this suite therefore checks the resulting **row
state** via a `SECURITY DEFINER` probe, rather than waiting for an exception. That
form is correct in all three cases — raised, silently filtered, or (the dangerous
case) actually applied. `rls_denied` is used only where an error genuinely is the
correct outcome: a `WITH CHECK` violation or a missing table privilege.

---

## 6. AI Module Testing

_(Empty — not yet written.)_

---

## 7. Test Coverage Goals

_(Empty — not yet written.)_
