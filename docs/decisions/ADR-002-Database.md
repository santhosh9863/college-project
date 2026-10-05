# ADR-002: Database Design

> Decision record for the PostgreSQL database schema and migration strategy.
> **Status: ACCEPTED — records the schema as actually applied.** Written from the 38
> migration files, not from `DATABASE_DESIGN.md`, which predates them and contradicts
> them in six places (§1.1).
> **Scope of this record: where data lives and who may touch it.** Identity
> verification is `ADR-001-Authentication.md`; intelligence is `ADR-003-AI.md`.

---

## Table of Contents

1. [Context](#1-context)
2. [Decision](#2-decision)
3. [Consequences](#3-consequences)
4. [Alternatives Considered](#4-alternatives-considered)
5. [Open Questions](#5-open-questions)
6. [References](#6-references)

---

## 1. Context

One Supabase project must hold four things that pull in opposite directions:

- **Community isolation.** A student in BCA 2024 S5 C must not read a report from BCA
  2024 S6 C. There is no server-side application layer to filter with — the Flutter app
  is the only client and it is on a user's device, so it cannot be trusted to filter.
  Isolation has to be a property of the row, enforced by the database.
- **Five roles** (`student`, `hod`, `technician`, `operations`, `admin`) with different
  visibility and different write powers, including a documented state machine for
  report status.
- **Auditability.** Activity, notifications and the AI decision log must be
  server-generated and append-only, or they are worthless as evidence.
- **No DBA.** Supabase CLI is not installed in this environment, so migrations are
  pasted into the Supabase SQL Editor by hand. That makes migrations effectively
  **append-only**: a file already applied cannot be edited and re-run safely, which is
  why six corrective migrations exist alongside the originals.

The isolation requirement is what decides the rest. Once the database is the only
trustworthy filter, every read and write becomes a policy question, and the schema has
to be shaped around what policies can express.

### 1.1 What the documentation previously claimed

As in ADR-001, the drafts are behind the code. Verified by reading all 38 migrations:

1. **`DATABASE_DESIGN.md:4` claimed "14 files under `supabase/migrations/`, not yet
   applied to any database."** There are **38** files: 34 applied, and four still
   pending — `20261005120000` (staff seed), `20261005123000` (AI-1),
   `20261005130000` (evidence path prefix) and `20261005150000` (the u8 policy
   self-read fix); see `docs/development/CURRENT_STATE.md` §7c. Of the applied ones,
   the migrations themselves record the truth: `:3` of several files says
   "reproduced live, 2026-08-15", and `20260811103500_login_rate_limit.sql:3` refers to
   "the 18 applied migrations".
2. **`RLS_POLICIES.md:4` claimed "NO RLS SQL written or applied yet"**, and `:232`
   repeated it. `20260811103300_rls_security.sql` alone is 741 lines and 28 policies.
3. **`RLS_POLICIES.md:49` records u23 as "Staff department-specific scoping is
   deferred."** It is implemented — `20260815121000_staff_department_scope.sql:43-52`
   requires `department_id` equality on the routing branch, and is cited there as
   locked decision D1.
4. **The docs list 14 tables.** There are 15. `login_attempts` is undocumented in
   `docs/architecture/` entirely.
5. **The docs list three priority values** (`low`, `medium`, `high`) at
   `DATABASE_DESIGN.md:274-280`. A fourth, `'critical'`, was added by
   `20260815100000_priority_critical.sql:5` and appears in no architecture doc.
6. **`DATABASE_DESIGN.md:336` claimed "No migration files have been modified"** and
   `:401` proposed revising in place "before first cloud apply, database is pristine".
   Both are moot; the apply has happened, repeatedly, by hand.

`STORAGE_DESIGN.md` is a related problem: all six of its sections are empty, so the
entire storage model exists only as migration comments.

---

## 2. Decision

Tags: **[D]** = already applied. **[N]** = new proposal here, not yet applied.

### 2.1 Supabase-managed Postgres, migrations applied by hand in filename order **[D]**

38 files under `supabase/migrations/`, named `YYYYMMDDHHMMSS_slug.sql`, applied in
lexicographic order through the SQL Editor. 34 are applied; `20261005120000` (staff
seed), `20261005123000` (AI-1 duplicate detection), `20261005130000` (evidence path
prefix) and `20261005150000` (u8 policy self-read fix) are not.

Because re-running an applied file is unsafe, **corrections are new files that drop and
recreate** rather than edits — hence `drop policy` appearing 3 times against 38
`create policy` statements, and six `fix_*`/`restore_*` migrations. See §5.4 on
whether this should be formalised.

### 2.2 The identity chain is structural, not conventional **[D]**

`auth.uid() = profiles.id = auth.users.id`, guaranteed by a foreign key:
`profiles.id uuid primary key references auth.users (id) on delete cascade`
(`20260811102300_profiles.sql:6`). Stated as an invariant at
`20260811103300_rls_security.sql:5`.

This is only true because ADR-001 §2.2 mints a real GoTrue session. There is **no
`handle_new_user` trigger**; profile creation is entirely explicit, in the Edge
Function or the staff seed. `my_role()` returns NULL when no profile row exists
(`:24-31`), and every NULL-comparing predicate is false — so a valid session with no
profile sees nothing. The model fails closed.

### 2.3 Revoke-first: `anon` gets nothing **[D]**

`revoke all ... from anon` runs before any grant (`20260811103300_rls_security.sql:408`),
then `authenticated` receives a broad `SELECT` followed by **column-level** write
grants (`:426-492`). Table-level `UPDATE` is revoked on `reports` (`:453`) and replaced
by `grant update (status, deleted_at, updated_at)` (`:454`).

This ordering matters: the default posture is denial, and privilege is added
deliberately. It also means the blast radius of a missing policy is nil, because a
missing *grant* denies too.

`20260815125000_security_hardening.sql:19-35` exists because Supabase's default
privileges had granted EXECUTE on newly created functions; the migration revokes it
from `anon` on all 14 public functions and from both client roles on the two
server-write helpers. Without it, hardening was silently incomplete.

### 2.4 Application role comes from the database, never the token **[D]**

Every JWT carries `role: 'authenticated'` — the *Postgres* role. The application
`user_role` is read from `profiles.role` through `my_role()`
(`20260811103300_rls_security.sql:24-31`), marked `security definer` specifically so
that reading `profiles` does not recurse into `profiles` RLS.

The concept doc calls this helper `staff` (`RLS_POLICIES.md:2`); it was never
implemented as a function and is inlined as `my_role() <> 'student'` at `:513`, `:525`,
`:532`.

### 2.5 Community isolation is a NOT NULL snapshot on the report **[D]**

`reports.community_id uuid not null references public.communities(id)`
(`20260811102400_reports.sql:23`), snapshotted at creation. `my_community_id()`
(`20260811103300_rls_security.sql:35-47`) resolves the caller's single active
membership.

Student visibility is then one expression, used by the read policy, the insert policy,
and the supports policy:

```
r.community_id = public.my_community_id() or r.reporter_id = auth.uid()
```

The `or reporter_id` arm satisfies u1 — a student keeps seeing their own reports from
previous communities, because the snapshot changes but the reporter does not.

`20260815103000_fix_returning_visibility.sql` introduced the row-aware variant
(`report_visible_to_caller_row`, `:38-39`). This was a real MVCC bug: the subquery form
`report_visible_to_caller(r.id)` cannot see the row being inserted in the same
statement, so `INSERT ... RETURNING` returned nothing to the student who created it.

### 2.6 One active membership per profile, enforced by index **[D]**

A partial unique index on `(profile_id) where is_active`
(`20260811103300_rls_security.sql:710-712`) makes `my_community_id()`'s
`order by joined_at desc limit 1` well-defined and turns "which class am I in?" from an
ambiguous question into a single row. An equivalent index enforces one active
assignment per report (`:703-705`).

Neither index is documented in `DATABASE_DESIGN.md` §5.

### 2.7 Policies are narrow, named, and single-command **[D]**

32 live policies — 28 on `public.*`, 3 on `storage.objects`, 1 on `storage.buckets`.
Characteristics worth preserving:

- **No `FOR ALL` policies.** Every policy names exactly one command, so a table's
  insert and update rules can never be conflated.
- **No inline authorisation.** Leaf policies delegate to named helpers;
  `auth.uid()` appears only in simple comparisons. This makes `report_visible_to_caller`
  the single funnel for row visibility — 8 policies plus storage reuse it.
- **13 `with check` clauses** enforce post-write validity, not just pre-write
  visibility. Without them a policy would permit a row it then refuses to expose.

### 2.8 The report lifecycle is a state machine in SQL, not a constraint **[D]**

This is the schema's most unusual property. `reports.status` has **no CHECK constraint
and no enum type guarding transitions**. Across all 38 migrations there is exactly
**one** CHECK constraint — `login_attempts.outcome in ('success','failure')`
(`20260811103500_login_rate_limit.sql:10`) — and `reports` is not it.

Validity is enforced in three layers:

1. **Column grant** — only `status`, `deleted_at`, `updated_at` are client-writable
   (`:454`).
2. **Policy gate** — `using (can_update_report_row(id))` and
   `with check (can_update_report(id, status, deleted_at))` (`:558-562`).
3. **`SECURITY DEFINER` state machine** — `can_transition_status` (`:143-229`) locks
   the row `FOR UPDATE` before reading it (`:165`) to close a TOCTOU window, refuses
   transitions out of `closed` (`:177-179`), requires an active assignment to reach
   `in_progress` (`:188-195`), then applies a per-source-status `CASE` matrix
   (`:197-225`).

Races and stale reads are therefore handled correctly by the database rather than
trusted to the client. `pending → resolved` is deliberately absent (`:203`).

The cost is that this protects the `authenticated` role only. See §3.

### 2.9 Audit rows are server-generated and unwriteable by clients **[D]**

`report_activity`, `notifications` and `ai_classification_log` have their
`INSERT`/`UPDATE`/`DELETE` revoked (`:474`, `:487`, `:481`) and expose `SELECT`-only
policies. Rows arrive exclusively through `SECURITY DEFINER` triggers and helpers —
`server_activity` (`20260811103400:45`), `server_notify` (`:28`),
`trg_log_status_change` (`20260815122000:47`). This is what makes them usable as
evidence: a client cannot forge an entry saying something happened.

### 2.10 Every `SECURITY DEFINER` function sets `search_path = ''` **[D]**

32 functions, 32 occurrences of `set search_path = ''` — an exact 1:1 match, verified by
count. All references are schema-qualified as a result.

This is the standard mitigation for the `SECURITY DEFINER` privilege-escalation pattern
(a caller who can create objects in a writable schema could otherwise hijack name
resolution inside a definer function). A project this size getting it right on all 32
is worth stating explicitly, because it is invisible in review until you count.

### 2.11 Deny-all tables are used deliberately **[D]**

`public.login_attempts` has RLS enabled with **zero** policies plus explicit `revoke
all` from both client roles (`20260811103500_login_rate_limit.sql:19-22`). RLS-with-no-
policies is deny-all, so the table is `service_role`-write-only. 16 tables have RLS
enabled in total.

This is the cleanest available pattern for "the server writes, nobody reads", and it
needs no policy to be correct — the default is already denial.

### 2.12 Storage is private, and object access inherits report visibility **[D]**

One bucket, `evidence`, `public = false`, 20 MiB cap, five allowed MIME types
(`20260815102000_evidence_storage.sql:15-23`). Three storage policies, all requiring
`bucket_id = 'evidence'` and delegating to the same visibility helper as the database
rows (`evidence_select_visible`, `:44-50`). There is **no UPDATE policy**, so evidence
objects are immutable; re-upload creates a new object.

Path parsing fails closed: `storage_evidence_report_id` returns NULL for any non-UUID
first folder, and every policy rejects NULL (`20260815105000:16-23`).

Two corrections were needed and both were caused by live 403s, not by reasoning:
`storage.objects.name` **excludes the bucket**, so the path convention documented as
`evidence/<report_id>/<file_id>_<name>` at `20260815102000:9` is wrong — the first
folder *is* the report id (`20260815105000:3-5`) — and `storage.buckets` had no SELECT
policy at all, so every upload failed (`20260815106000:3-10`).

### 2.13 `pg_trgm` is the only extension **[D]**

`create extension if not exists pg_trgm` (`20261005123000:22`), with a GIN trigram index
on `title || ' ' || description` (`:28-29`). `gen_random_uuid()` is used as the
primary-key default in all 15 tables but is built into the Supabase Postgres baseline,
so it is not an explicit dependency.

The AI decision therefore required no service, no model and no new runtime — see
`ADR-003-AI.md` §2.1.

---

## 3. Consequences

- **The client cannot be trusted, and does not need to be.** Every read and write is
  filtered by the database. The app's job reduces to rendering what it is given, and a
  tampered client gains nothing.
- **`status` validity is not a property of the data.** Because the lifecycle lives in
  RLS (§2.8), `service_role` and the SQL Editor can write a status that no client ever
  could. Any backfill or admin script touching `reports.status` must respect
  `can_transition_status` itself. This is the single most surprising property of the
  schema and it is not documented anywhere outside the migration.
- **28 policies in one file is a review hazard.** `20260811103300_rls_security.sql` is
  741 lines defining helpers and policies together. A change to `my_role()` semantics
  silently affects every policy that calls it, and no test asserts the aggregate.
- **Hand-applied migrations are only as ordered as the operator.** There is no
  `migration_history` table equivalent being consulted, no checksum, and no dry run. The
  evidence that 34 applied correctly is migration-header prose and the absence of
  errors — not a record the database keeps.
- **Six corrective migrations exist** — a seventh, `20261005150000`, is written but not
  yet applied — because fixes could not be edited in place. Each
  is a correct fix, but the final state is only readable by replaying 38 files in
  order. `DATABASE_DESIGN.md` is not a substitute and never was.
- **`STORAGE_DESIGN.md` was empty**, so storage security knowledge lives only in
  migration comments — the least durable place for it.
- **Community isolation holds even if the app is entirely replaced.** Because
  `reports.community_id` is a snapshot column rather than a join, a student's access
  does not depend on current membership state.
- **Trigram search has no trigram operator class on the extension by default**, so the
  index is an expression index and cannot serve plain `title` lookups. Fine for this
  workload; would need revisiting for a title-only search feature.

---

## 4. Alternatives Considered

| Option | Verdict |
|---|---|
| **A. RLS as the sole authorisation layer** | **Accepted.** 32 policies, deny-first ACLs, `SECURITY DEFINER` helpers with pinned `search_path`. Gives server-side guarantees with no application authorisation code to get wrong. |
| **B. Application-side authorisation only** | **Rejected.** The client is on an untrusted device; any policy decision made in Dart is advisory. Community isolation would be a suggestion. |
| **C. Postgres row-level security via views + `security_invoker`** | **Rejected for now.** A cleaner long-term shape, but it requires every table to be reached through a view, which is a large refactor of 15 tables and 32 policies. Worth revisiting if the policy count keeps growing. |
| **D. `CHECK` constraints for the report lifecycle** | **Rejected.** A CHECK cannot express "requires an active assignment", "previous status was X", or "TOCTOU-safe under concurrency" — it sees only the new row. The state machine needs to read the old row under a lock, which only a definer function can do. |
| **E. Enum type for `report_status` with a transition table** | **Rejected.** The enum plus a trigger was considered. The trigger would still need the row lock and the assignment lookup, so it saves nothing over the definer function while adding a second place where the lifecycle is defined. |
| **F. An external ORM / migration tool (Prisma, Drizzle, Supabase CLI)** | **Not available.** No CLI in this environment and no Node toolchain. Hand application in filename order is the fallback, with the consequences in §3. |
| **G. Separate schemas per role** | **Rejected.** Postgres has no per-role schemas, and role separation via schemas would not survive a Supabase role change. |

---

## 5. Open Questions

1. **`reports.status` has no declarative constraint.** §2.8 explains why, but the
   consequence in §3 — that `service_role` can violate the lifecycle — is unrecorded
   anywhere else. Any future backfill touching `status` must call
   `can_transition_status` explicitly. Consider a trigger that rejects invalid
   transitions even for `service_role`, as a second line of defence.
2. **`STORAGE_DESIGN.md` is an empty skeleton.** Six empty sections while the entire
   storage model — bucket, limits, MIME list, path convention, four policies, and two
   live-corrected mistakes — exists only in migration comments. This is the largest
   documentation hole in the project.
3. **`RLS_POLICIES.md` is stale on u23 and on its own status.** §3.4 and §4 still say
   department scoping is deferred; it is applied and cited as locked decision D1. The
   doc's header also still says no RLS SQL exists.
4. **Should migration drift be formalised?** Six `fix_*`/`restore_*` files exist
   because corrections cannot be edited in place. A convention that distinguishes
   "applied" from "proposed" migrations — or an applied-migrations ledger checked into
   the repo — would make the current state readable without replaying 38 files.
5. **`login_attempts` is undocumented in `docs/architecture/`** and holds IP addresses.
   Under most retention policies that is personal data, and the table has no expiry
   mechanism of its own; pruning depends on the Edge Function running
   (`index.ts:129-135`). If the function is never called, rows accumulate forever.
6. **The student UPDATE grant is wider than the policy intends.** All three of
   `status`, `deleted_at`, `updated_at` are granted to every `authenticated` role
   (`:454`); the policy forces students to leave `status` unchanged (`:287`), but
   nothing stops a client writing `updated_at` arbitrarily, and no trigger maintains it.
7. **`DATABASE_DESIGN.md` §8's "do not add undocumented fields" rule was broken twice**,
   by `reports.community_id` and by `'critical'`. Both were correct decisions; the rule
   is what failed.
8. **`ANALYTICS` has no RPC.** `analytics_overview()`
   (`20260815124000:16-68`) is undocumented in `RLS_POLICIES.md`, which still frames
   analytics as an admin-panel concern with no data path.

---

## 6. References

- `supabase/migrations/` — all 38 files; the schema exists only here
- `supabase/migrations/20260811102400_reports.sql` — central table, `community_id` snapshot
- `supabase/migrations/20260811103300_rls_security.sql` — 741 lines, 28 policies, all helpers
- `supabase/migrations/20260811103400_server_generated_events.sql` — audit triggers, `server_notify`
- `supabase/migrations/20260811103500_login_rate_limit.sql` — deny-all pattern, the schema's only CHECK
- `supabase/migrations/20260815102000_evidence_storage.sql` — bucket + 3 storage policies
- `supabase/migrations/20260815103000_fix_returning_visibility.sql` — MVCC `RETURNING` fix
- `supabase/migrations/20260815105000_fix_evidence_path.sql` — bucket-name path fix
- `supabase/migrations/20260815106000_fix_storage_bucket_policy.sql` — missing bucket policy
- `supabase/migrations/20260815121000_staff_department_scope.sql` — u23, department scoping
- `supabase/migrations/20260815125000_security_hardening.sql` — EXECUTE revokes
- `supabase/migrations/20261005123000_ai1_duplicate_detection.sql` — `pg_trgm`, unapplied
- `docs/architecture/DATABASE_DESIGN.md` — superseded; see §1.1
- `docs/architecture/RLS_POLICIES.md` — u1–u23, stale on u23 and on status
- `docs/architecture/STORAGE_DESIGN.md` — empty
- `docs/architecture/REPORT_LIFECYCLE.md` — D1–D10
- `ADR-001-Authentication.md` — why `auth.uid()` is trustworthy
- `ADR-003-AI.md` — sibling record; the `pg_trgm` decision
- `docs/development/CURRENT_STATE.md` — authoritative current status
