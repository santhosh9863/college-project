# Current State — read this first

> Handover doc. **Last updated 2026-10-05.**
> Purpose: whoever picks this up next (including an AI assistant with no memory
> of previous sessions) should be able to orient in under a minute.
>
> Supersedes `CHECKPOINT_2026-08-11.md` for day-to-day work; that file remains
> the record of the auth/Linways phase.

---

## TL;DR

**Three things must be run in the Supabase SQL Editor.** They are independent;
run them in any order.

| # | Run this | Unblocks |
|---|---|---|
| 1 | `supabase/migrations/20261005150000_fix_policy_self_read.sql` | **Student "cancel my report" (u8) — real bug, fix now verified by reasoning but NOT yet run** |
| 2 | `supabase/migrations/20261005120000_seed_staff_demo_accounts.sql` | All staff login + all four panel demos |
| 3 | `20261005123000_ai1_duplicate_detection.sql` | Duplicate flagging (`duplicate_of`) |
| 4 | `20261005130000_fix_evidence_path_prefix.sql` | Evidence upload — see below, **found 2026-10-05** |
| 5 | The one query in §3.1 | The remaining `NoSuchBucket` half of the evidence bug |
| 6 | Re-run `supabase/tests/rls_policy_tests.sql` | Confirms the u8 fix: expect **92/92, 0 failed** |

Items 2–4 are written and syntax-checked but never executed. Item 5 is a read-only
query. Item 6 is the RLS suite, which **has now been executed twice** — see §7c.

> **`20261005140000` was already applied to the live database and did NOT fix u8.**
> Do not re-run it and do not expect it to help. It was superseded by
> `20261005150000`; see §7c for why the first attempt was wrong and what the
> actual root cause turned out to be.

**The evidence blocker is now two independent bugs, not one.** Reading
`reports_repository.dart` against `storage_evidence_report_id` turned up a
second one that is a **live regression**: the client uploads to
`evidence/$reportId/<file>` but the parser reads folder `[1]` as the report
UUID, which only matches a path with no prefix. So `foldername()[1]` is the
literal string `evidence` and `'evidence'::uuid` **throws**. That has been
breaking evidence upload since `20260815105000`. `20261005130000` accepts both
path shapes and fails closed instead of throwing — apply it, it needs no
decision from you.

Student login works. Submitting a report works **if you attach nothing**.
AI is AI-0 (ADR written) + AI-1 (duplicate detection, not applied);
classification and priority prediction are still unbuilt proposals.

**The RLS policies now have an executable test suite** (§7c) — the first thing
in this project that can actually *prove* a security claim rather than assert it in
prose. **Run twice on 2026-10-05: first 91 assertions / 89 passed / 2 failed, now
92 / 91 / 1 — and it caught a real bug**, a student being unable to soft-delete their own
report (`u8`). Diagnosing it took three attempts and the first fix was wrong; §7c has the
full account, because the wrong fix is the useful part. **One assertion is outstanding
and the fix for it has not been run.**

Nothing is uncommitted.

---

## 1. Where we are

| Area | State |
|---|---|
| Student login (Linways) | ✅ Working — verified live 2026-10-04 |
| Staff login | ⚠️ Accounts **do not exist** — seeded by SQL, not yet run (§5.2) |
| Student report create (no evidence) | ✅ Working |
| Student report create (with evidence) | ❌ **Broken** — open blocker §3 |
| Staff panels (4 roles) | ✅ Built, untested this session |
| **RLS policy correctness** | 🟡 **Executable suite, run twice — 92 assertions, 91 passing** — §7c. `u8` fix written, **not yet run** |
| Notifications / analytics | ✅ Built (phases 2.8, 2.9) |
| Attendance + OCR import | ✅ Built (ML Kit, separate from reports) |
| AI / ML | 🟡 AI-0 + AI-1 written, **not applied** — duplicate detection only (§6) |
| Duplicate read surface | ✅ Built client-side — shows nothing until AI-1 is applied (§6) |
| Storage / evidence | ❌ Broken |
| `flutter analyze` | ✅ Clean (re-run 2026-10-05) |
| `flutter test` | ✅ **258/258** pass (was 241; +17 for the duplicate notice) |
| Supabase CLI | ❌ **Not installed** — nothing can be deployed |
| Uncommitted changes | ✅ None — working tree clean |
| Android emulator | 🟡 AVD `college_project` exists, **exits under memory pressure** (§5.4) |

---

## 2. Changes made 2026-10-04 (now committed as `cf7fd20` + `40944ee`)

Ten files, no new files, no migrations.

| File | Change | Why |
|---|---|---|
| `core/security/secure_local_storage.dart` | `accessToken()` now returns the stringified Session JSON from a single key, instead of a bare JWT under a second key | **Real bug.** gotrue's `setInitialSession`/`recoverSession` call `json.decode` on this value; a raw JWT threw `FormatException`, was swallowed, and **every cold start silently logged the user out** |
| `core/errors/auth_exceptions.dart` | New `projectUnavailable` kind | 54X platform states are not function responses and must not collapse into the generic error |
| `core/network/api_client.dart` | Maps 54X → `projectUnavailable`; debug-logs unmapped status + body **keys** | Diagnosability. Body *keys* only, never values — a 200 body carries session tokens |
| `services/auth_controller.dart` | Bare `catch (_)` → `catch (error, stackTrace)` + debug log | The old bare catch **discarded the entire cause** of every non-`LoginException` login failure. This is why the original bug was undiagnosable |
| `data/repositories/auth_repository.dart` | `setSession` now runs **before** cookies are written | A `setSession` failure used to leave Linways cookies on device with no session |
| `features/reports/create_report_controller.dart` | `submit()` split into `_createReport()` + `_uploadEvidence()`; per-file evidence errors; `failedEvidenceCount` / `lastEvidenceError` | A failed attachment no longer reports a **successfully created** report as a failure |
| `features/reports/create_report_screen.dart` | SnackBar on partial success | Same |
| `test/api_client_test.dart` | +2 tests (540, 544) | |
| `test/.../create_report_controller_test.dart` | +2 tests (failed upload keeps report; uploads continue past failure) | |
| `docs/architecture/AI_ARCHITECTURE.md` | Filled — was an **empty skeleton** | See §6 |

---

## 2b. Changes made 2026-10-05

Four commits. No Dart behaviour changes — `flutter analyze` clean and 258/258 tests
pass at every one of them, and the test count did not move, which is the point of
the last one.

| Commit | Change | Why |
|---|---|---|
| `00713cc` | Duplicate-flagged reports surfaced to students **and** staff: `Report.duplicateOf` + `isDuplicate`, repository wiring, a shared card, a staff queue `Duplicate` badge, navigation to the canonical report. +17 tests (241 → 258). | The `duplicate_of` column and the whole AI-1 detection path existed, but **no user could ever see the result**. The feature was invisible end-to-end. |
| `dc1a037` | Filled `docs/decisions/ADR-001-Authentication.md` — was a 454-byte skeleton with no decisions in it | It claimed a login response shape (`campus_pulse_jwt`) that the code does not produce, using a **banned project name** |
| `8830644` | Filled `docs/decisions/ADR-002-Database.md`; corrected the stale u23 and status rows in `RLS_POLICIES.md` | It claimed "no RLS SQL written or applied yet" while 32 policies were live, and recorded u23 as deferred when `20260815121000` had implemented it |
| `b45664b` | `20261005130000_fix_evidence_path_prefix.sql` + filled `STORAGE_DESIGN.md` | Found a **live regression**: the client uploads to `evidence/<report_id>/<file>` but the parser read `foldername()[1]` as the report UUID, so `'evidence'::uuid` **throws**. Evidence upload has been broken since `20260815105000` — see §3. |
| *(this change)* | `supabase/tests/rls_policy_tests.sql` + §7c + `RLS_POLICIES.md` §7 + `TESTING_STRATEGY.md` §5 | The 32 policies were documentation. This is the first executable check of them — §7c |

**Why the RLS suite was the highest-value thing available.** Everything else in this
table is a feature or a doc fix. This one closes the gap where the project's headline
security claim had *no* verification behind it at all: 258 Dart tests all mock the
repository layer, so nothing ever reached Postgres, and no staff account had ever
existed in a live database, so the staff policies had never run against real rows.

---

## 3. ⛔ THE OPEN BLOCKER — evidence upload

**Symptom:** attaching a photo to a report fails with:

```
StorageException(message: invalid input syntax for type uuid: "evidence",
                   statusCode: 400, error: InvalidParameter)
```

**Where:** `reports_repository.dart:279` — `_client.storage.from('evidence')`.

### 3.0 The earlier diagnosis in this file was wrong — read this first

An earlier revision of this section claimed: *"a live probe returned 400, not
404; a missing bucket gives 404; therefore `storage.buckets.id` is `uuid`."*
**That reasoning does not hold.** Re-probed 2026-10-05 with the anon key:

```
GET /storage/v1/bucket/evidence
→ HTTP 400  {"statusCode":"404","error":"NoSuchBucket","message":"Bucket not found","code":"NoSuchBucket"}
```

storage-api wraps a 404 **inside an HTTP 400**. The body says plainly that the
bucket is not visible. The status code was never evidence of a uuid schema.

**And an anon probe cannot answer the question at all**, because
`20260815106000_fix_storage_bucket_policy.sql:17` grants select on
`storage.buckets` **to `authenticated` only**:

```
GET /storage/v1/bucket        → []        (anon)
```

`[]` looks like "no buckets exist" but is what anon sees *even when the bucket
exists*. "Bucket absent" and "bucket hidden by RLS" are indistinguishable from
anon. Only an **authenticated** request separates them — and no staff or student
credential was available this session to make one.

### 3.1 One statement settles it

Run this (dashboard → SQL Editor):

```sql
select a.attname, a.atttypid::regtype as type
from pg_attribute a
where a.attrelid = 'storage.buckets'::regclass
  and a.attname = 'id' and a.attnum > 0 and not a.attisdropped;
```

- **`type` = `uuid`** → `20260815102000_evidence_storage.sql:15`
  (`insert into storage.buckets (id …) values ('evidence', …)`) can never have
  succeeded here. Needs the uuid-keyed corrective migration, and the bucket id
  must move into `AppConfig` instead of the hardcoded `'evidence'` at
  `reports_repository.dart:279` and `:302`.
- **`type` = `text`** → the bucket row *should* exist and the uuid cast is
  coming from somewhere else. Next probe is an **authenticated**
  `GET /storage/v1/bucket/evidence` to see whether the row is actually there.

Either way also worth running:

```sql
select id, name, public, file_size_limit, allowed_mime_types from storage.buckets;
```

**Workaround meanwhile:** submit without attaching evidence. The report saves
fine — evidence is the only broken part.

### 3.2 Orphan reports

Failed attempts left reports in the DB with no evidence (the row is created
before upload runs). Find them — read-only, run as `postgres` to list all:

```sql
select r.id, r.title, r.created_at, r.status, r.reporter_id,
       (select count(*) from public.evidence_files e where e.report_id = r.id) as files
from public.reports r
where r.deleted_at is null
order by r.created_at desc;
```

`files = 0` on rows from 2026-10-04 = failed attempts. **Do not delete until
confirmed with the user.**

---

## 4. How to start a session

```powershell
# 1. Is the project paused? (free tier does this after ~7 days idle)
#    Dashboard -> project bvxuvkpmpufsbxvpdkht -> shows "Restore" if paused

# 2. Backend reachable?
#    NOTE: do not inline the JSON in curl.exe on PowerShell - the shell eats the
#    quotes and GoTrue/GoTrue-style parsers reject the mangled body. Write the
#    body to a file first (no BOM) and use --data-binary "@file".
$h = @{ apikey = '<anon key from flutter_app/lib/core/config/app_config.dart>' }
Invoke-WebRequest -Uri "https://bvxuvkpmpufsbxvpdkht.functions.supabase.co/linways-login" `
  -Method POST -ContentType "application/json" -Body '{"username":"probe","password":"x"}' -Headers $h
# 401 + {"error":"invalid_credentials"} = backend healthy  (re-confirmed 2026-10-05)
# 540 = project paused -> restore it
# Anything else, check auth/v1/health -> {"version":"v2.197.0",...} means GoTrue is up

# 3. Run the app
cd flutter_app; flutter run        # Android emulator: see 5.4 before starting
```

`flutter analyze` and `flutter test` were both clean at last run (258 tests,
2026-10-05). A debug APK builds cleanly (~100s).

**Do not run `flutter build` / `flutter doctor` casually** — see §5.4; they can
create stray platform folders and a failing template test.

---

## 5. Gotchas that will bite again

### 5.1 The project auto-pauses — expect this every ~7 days
Free-tier projects pause on inactivity. Symptom chain: paused project → all
logins return **HTTP 540** → app showed **"Something went wrong. Please try
again."** because 540 had no mapping. Fixed (54X now maps to
`projectUnavailable`), but the **pause itself recurs**. Check it first whenever
login mysteriously breaks.

### 5.2 Staff demo accounts — now reproducible (was: hand-made in the dashboard)
`20261005120000_seed_staff_demo_accounts.sql` seeds **one account per role**,
because commit `18c98fd` removed the panel switcher — a staff shell renders
the panel for the logged-in role, so one shared admin account can no longer
demo HOD / technician / operations at all.

| Email | Password | Role |
|---|---|---|
| `hod@college-project.local` | `Hod@12345` | hod |
| `technician@college-project.local` | `Tech@12345` | technician |
| `operations@college-project.local` | `Ops@12345` | operations |
| `admin@college-project.local` | `Staff@12345` | admin |

All anchored to department `GENERAL`. **Status: written and syntax-checked,
never executed** — run it in the SQL Editor. Confirmed gone as of 2026-10-05:
GoTrue password grant for `staff@college-project.local` → `invalid_credentials`.

Two GoTrue facts that make or break a hand-inserted user (both commented in
the migration): the `auth.users` row alone signs in as *"Invalid username or
password"* even with a correct `crypt()` hash, because email/password
resolves through **`auth.identities`**; and `raw_app_meta_data.provider` must
list `"email"` or the password grant is refused. Role must be one of
`hod|technician|operations|admin` or the login silently falls through to the
Linways handshake (`index.ts:576`).

### 5.3 Web/browser login is impossible by design right now
`supabase/functions/linways-login/index.ts:38` — `ALLOWED_ORIGINS = []`. Browser
CORS blocks the response. Android/iOS unaffected (no CORS). Only matters if
demoing in Chrome.

### 5.4 An Android emulator now exists — but this machine is memory-starved
**Fixed 2026-10-05.** There was never a missing SDK; no **AVD** had been created.
Created `college_project` from the already-installed
`system-images;android-37.0;google_apis_playstore_ps16k;x86_64`
(Android 17, x86_64, boots in ~85s). It now shows in `flutter devices` as
`emulator-5554`.

**It keeps exiting on its own during app installs.** Host is **16 GB with only
~5 GB free**; the AVD plus a Gradle build exceeds that. Not a config fault —
`hw.ramSize` is already lowered to 2048. Practical rules:

- Build the APK **first**, with the emulator stopped. Then start the emulator
  and install the prebuilt APK. Do not run Gradle while it boots.
- Close Chrome and other heavy apps first.
- Expect roughly 80-90s to boot; poll with
  `adb -s emulator-5554 shell getprop sys.boot_completed` → `1`.

**Also: `flutter build` / `flutter doctor` pollute the repo.** They created
`linux/`, `macos/`, `web/`, `windows/` scaffolding, rewrote `.metadata`, and
dropped the *template* `test/widget_test.dart` — a default counter-app test
against a non-counter app, which **fails the suite**. If that file reappears,
delete it; those platform folders are not gitignored and will show as
untracked. The project targets android + ios only.

### 5.5 The project must be called "college project"
Never PULSE / SafeBunk / "Campus Pulse" — in code, docs, commit messages, or
the report. `docs/references/PULSE_AUTHENTICATION_ARCHITECTURE.md` is a
reference doc only. (A draft AI plan repeatedly called it "Campus Pulse".)

### 5.6 `docs/README.md` points at this file — keep them consistent
`docs/README.md` links `development/CURRENT_STATE.md` as its "Start here". A
stale claim in this file is the single most expensive kind of documentation bug
in this repo: it has already cost one session a dead end (§3.0). If you change
reality, change this file in the same commit.

---

## 6. AI/ML — AI-0 and AI-1 written, neither applied

**Do not describe the AI approach as pre-decided.** `ADR-003-AI.md` and
`AI_ARCHITECTURE.md` were empty skeletons; a draft plan claimed TF-IDF / cosine
similarity / logistic regression were "explicitly proposed by the project
documentation". **They were not** — those terms appear nowhere in `docs/`.
They are marked **[N]** (new proposal) vs **[D]** (existing decision)
throughout, and §1.1 of the ADR records the misattribution deliberately.

Now written:

| Phase | Artifact | State |
|---|---|---|
| AI-0 | `docs/decisions/ADR-003-AI.md` — **filled** (was 0 lines of prose) | Done |
| AI-1 | `20261005123000_ai1_duplicate_detection.sql` — `pg_trgm` duplicate detection | Written, **never applied** |
| AI-2+ | Edge Function, dataset, TF-IDF, priority | ⬜ Not started |
**AI-1 is the whole first slice: `pg_trgm` similarity in an `AFTER INSERT`
trigger.** No model, no dataset, no Edge Function, no Python. It exercises the
entire DB contract that already existed (`duplicate_of`, `ai_confidence`,
`ai_classification_log`) — that scaffolding was built in phase 1 and nothing
consumed it until now.

Two things to know before changing it:

- **The `AFTER INSERT` timing is forced, not stylistic.**
  `can_create_report()` (`rls_security.sql:101-127`) requires `ai_confidence IS
  NULL` **and** `duplicate_of IS NULL` for students, so classifying or linking
  *before* insert is rejected by the database. That is a deliberate invariant.
- **It cannot fail a submission.** The trigger body catches all exceptions and
  returns `NEW`, so a bug leaves `duplicate_of IS NULL` — exactly the state
  `can_create_report()` expects. Detection only flags; no report is ever
  rejected, merged, hidden, or closed (§8 invariant).

**AI-1's read surface is now built (client side).** `Report.duplicateOf` is
parsed (blank/non-string/self-reference all normalise to "not flagged"), a
shared `DuplicateNoticeCard` renders in both the student and staff detail
screens, the staff queue shows a **Duplicate** badge, and the notice links
through to the canonical report. Wording differs by viewer on purpose:
students get *"A similar report already exists — supporting their report helps
staff see one clear issue"*, staff get the triage framing. In this app several
students reporting one fault is the *intended* use of a community report, so
the student copy must never read as a reprimand.

**Caveat: it displays nothing until the migration is applied** — `duplicate_of`
is NULL for every existing row, and the trigger that sets it is
`20261005123000`. Purely a client-side read of a column the DB currently never
writes.

Also still open: the `0.85` threshold is a **guess, not measured** (ADR-003
§5.2), and pre-existing reports are **not backfilled** (§5.3).

---

## 7. Parked / not started

- **Run `20261005150000_fix_policy_self_read.sql`, then re-run the RLS suite** — the
  top outstanding item. Students currently cannot soft-delete their own report (`u8`,
  `42501`). Fix written, reasoned through, **not yet executed**; see §7c. Expect 92/92.
  `20261005140000` is already applied and does **not** fix it.
- **Run `20261005120000_seed_staff_demo_accounts.sql`** — written + syntax
  checked, never executed. Blocks all staff login and all four panel demos.
- **Run `20261005123000_ai1_duplicate_detection.sql`** — written, never executed.
  Until it runs, the duplicate notice is dead UI.
- **Run `20261005130000_fix_evidence_path_prefix.sql`** — written, never executed.
  Live evidence-upload regression; see §7 of `STORAGE_DESIGN.md`.
- Run the §3.1 type query — blocks the remaining `NoSuchBucket` half
- AI-2+ (Edge Function, dataset, classification, priority)
- Install the Supabase CLI — every migration is currently hand-applied
- **Evidence retention policy** — nothing ever deletes a storage object. Soft-deleting
  a report leaves its files forever. Security is fine (admin-only delete, nothing
  public), but it is a retention and cost decision nobody has made. `STORAGE_DESIGN.md` §6
- Real checkpoint doc for this phase (this file serves as it for now)

---

## 7b. Documentation audit — the ADRs were empty and the docs had drifted

All five ADRs are now filled. `ADR-001` and `ADR-002` were **454- and 433-byte
skeletons**: a Table of Contents, five empty sections, and no decisions at all. The
three other ADRs already had content.

Writing them required deciding what was actually true, because reading the
architecture drafts against the code produced a long list of contradictions. The
material ones:

| Claim in the docs | Reality |
|---|---|
| Login returns `{ campus_pulse_jwt, ... }` (`AUTHENTICATION_ARCHITECTURE.md:40`, `LINWAYS_INTEGRATION_ARCHITECTURE.md:100`) | It returns `supabase_session`. "Campus Pulse" is also a **banned project name** (§5.5), so the docs broke their own rule. Both diagrams fixed. |
| `JWT_AUTH_COMPATIBILITY.md:5` "No implementation" | Fully implemented — its recommended `verifyOtp` runs at `linways-login/index.ts:490-513`. Status header rewritten. |
| Staff auth is "OUT OF MVP" (`AUTHENTICATION_ARCHITECTURE.md:49` + 2 more) | Implemented at `index.ts:563-608` |
| `DATABASE_DESIGN.md:4` "14 migration files, not yet applied" | 36 files, 33 applied |
| `RLS_POLICIES.md:4` "NO RLS SQL written or applied yet" | 32 live policies |
| `RLS_POLICIES.md:49` u23 "department scoping is deferred" | Implemented in `20260815121000` and cited as locked decision D1 |
| Docs list 14 tables and 3 priority values | 15 tables (`login_attempts` undocumented), 4 values (`'critical'` added `20260815100000`) |

**`STORAGE_DESIGN.md` was an empty skeleton** — six empty sections, while the
whole storage model existed only in migration comments. It is now filled in, and was
the largest remaining doc hole.

Do not trust the "DECISIONS LOCKED" / "APPROVED" headers in `docs/architecture/`
without grepping the claim against the code. That pattern is what produced all seven
rows above. `DATABASE_DESIGN.md`, `AUTHENTICATION_ARCHITECTURE.md`,
`LINWAYS_INTEGRATION_ARCHITECTURE.md`, `RLS_POLICIES.md`, `JWT_AUTH_COMPATIBILITY.md`
and `ADR-004` now each carry a superseding banner naming the specific false claims.

Two real code gaps surfaced and are recorded in `ADR-001` §5:

- `admin.updateUserById` is specified but never called, so Linways email/name changes
  reach `profiles` but never `auth.users`.
- **Staff login is an unauthenticated email oracle** — branch selection is a bare
  `profiles` lookup and the response gives the answer away. Worth fixing before
  demonstrating.

---

## 7c. The RLS policies are now executable, not just documented

**The problem this fixes.** The project's headline security claim is 32 RLS
policies, and until now nothing in the repo could check it. All 258 Flutter tests
mock every repository, so no test ever reached Postgres; no staff account had ever
existed in a live database, so the staff policies had never run against real data.
Every claim in `RLS_POLICIES.md` rested on a human reading SQL correctly.

**What was added.** `supabase/tests/rls_policy_tests.sql` — ~1200 lines, pasted into
the Supabase SQL Editor. It asserts u1–u23 plus the lifecycle invariants the fixtures
reach — D1, D3, D5, D6, D8, D10 (**not** D2, D4, D7, D9; see `TESTING_STRATEGY.md` for
what those need) — and prints a pass/fail table. Nothing is persisted: fixtures and helper
objects are deleted
explicitly before and after the assertions, with a final `ROLLBACK` as belt and braces,
so an aborted run leaves nothing behind and re-running is safe.

**Two Supabase SQL Editor quirks already hit and worked around.** (1) Helpers are in an
ordinary schema `f1ce_rls`, not `pg_temp`, because the editor rejects
`create function pg_temp.…` with `3F000: schema "pg_temp" does not exist` even after a
temp table exists in the same session. (2) Answer **Run without RLS** when prompted — the
only table created is a scratch results table that is dropped again.

It needs no service-role key and no throwaway accounts. It impersonates each user
with `set local role authenticated` plus `request.jwt.claims`, which is exactly what
PostgREST does, so `auth.uid()` and `my_role()` resolve as they would in production.
Fixture `auth.users` rows exist only because `profiles.id` has an FK to them.

### First live run (2026-10-05) — it found a real bug

**Result: 91 assertions, 89 passed, 2 failed, 0 fixture problems.** Zero fixture
problems is the load-bearing number: it means all 8 users, 2 communities and 8 reports
built correctly, so both failures were real rather than harness noise.

| Requirement | Outcome |
|---|---|
| `u1` carol sees 1 report in her community | **Test bug, not a policy bug.** Community B deliberately holds two reports (`...27` carol's and `...24` alice's historical one). Isolation is per-*community*, so 2 was correct. Expectation corrected to 2 and split into a second assertion that carol sees nothing from community A. |
| `u8` alice may soft-delete her own pending report | **Real production bug.** `pgerror: new row violates row-level security policy for table "reports"`. |

Correcting `u1` added an assertion, so the suite is now **92**.

### The u8 bug — three attempts, and the first fix was wrong

This is the most valuable thing in this file, so it is written up in full. **If you
only read one part of §7c, read this.**

**Attempt 1 — a plausible reading that was wrong.** `can_update_report()` opened with

```sql
if not public.report_visible_to_caller(p_report_id) then return false; end if;
```

For a student that predicate demands `deleted_at is null` — but soft-deleting *is*
setting `deleted_at`, and RLS evaluates `WITH CHECK` against the post-update row. The
guard looked unsatisfiable, so `20261005140000` replaced post-update visibility with
ownership + the specific transition, on the reasoning that this was the whole defect.

**It was applied to the live database and u8 still failed, byte-identical error.**

**Attempt 2 — instrument instead of guessing.** Nine informational rows were added
(`u8-diag`) printing each term of the gate as alice, plus the suite's summary
aggregation was fixed (the failure count used a query-level `WHERE` instead of an
aggregate `FILTER`, so diag rows were being counted as failures). Live policies were
also dumped and compared against the repo.

The result ruled out most theories and left one very strange fact:

- the function called **directly** as alice returned `true`
- every individual term was correct — `my_role()` = `student`, `auth.uid()` set,
  alice owns `...20`, `...20` visible to alice, old state `pending / null`
- the policy text in the database **matched the repo exactly** — no drift, no
  restrictive policy, one UPDATE policy
- **admin soft-delete, same statement shape, succeeded**

So the function was right, the wiring was right, and the wiring demonstrably used
the right function. Correct function + correct wiring + still failing is
contradictory, which meant an assumption nobody had checked had to be wrong.

**Attempt 3 — read the function again instead of theorising.** The student branch
contained a clause that had been invisible in every previous reading:

```sql
and exists (
  select 1 from public.reports r
  where r.id = p_report_id and r.reporter_id = auth.uid()
)
```

**That is the bug.** It is a `SELECT` against `public.reports`, so `reports`' own
SELECT policy applies to it — and for a student that policy is

```sql
when 'student' then r.reporter_id = auth.uid() and p_deleted_at is null
```

It tests **the very column the UPDATE is setting**. Called standalone the row still
has `deleted_at = null`, so the read passes and the gate returns true — exactly what
the diagnostics recorded. Invoked as `WITH CHECK`, evaluated once the new tuple
exists, `deleted_at` is now non-null, the row is no longer visible to alice, `exists`
returns false, and the UPDATE is refused with `42501`.

**This finally explains the one asymmetry that survived every other theory.** Student
is the *only* role whose `SELECT` visibility depends on the column being changed, and
the only role whose branch contained a self-read. `report_visible_to_caller_row`
answers `when 'admin' then true` unconditionally, and the hod / technician /
operations branches delegate to `report_visible_to_staff()`, which never considers
`deleted_at`. So every staff path is immune and only alice breaks.

Same class of bug as `20260815103000`, where `report_visible_to_caller(id)` made
`INSERT ... RETURNING` fail for every student with the same `42501`. The precedent
there was explicit: take the row's own columns as arguments, do not re-read the table.

**The fix — `20261005150000_fix_policy_self_read.sql`.** Ownership and prior state move
into `USING`, which is evaluated against the pre-update row before any new tuple
exists, so nothing can be filtered:

```sql
using      (public.can_update_report_row(id, status, deleted_at, reporter_id))
with check (public.can_update_report(id, status, deleted_at))
```

The student branch of `can_update_report()` then validates only the incoming values
and performs **no table read at all**.

**Verified equivalent, not merely similar.** Each condition was mapped back to the
original — nothing loosened, nothing narrowed:

| Original condition | Now enforced by |
|---|---|
| `v_old_deleted_at is null` | `USING p_deleted_at is null` |
| `v_old_status = 'pending'` | `USING p_status = 'pending'` |
| `reporter_id = auth.uid()` | `USING p_reporter_id = auth.uid()` |
| `p_new_deleted_at is not null` | `WITH CHECK` |
| `p_new_status = 'pending'` | `WITH CHECK` |

Worth recording: **students were soft-delete-only by design all along** — the original
branch already required `p_new_deleted_at is not null`, so no legitimate student edit
is lost. A student still cannot double-delete (USING requires prior `deleted_at IS
NULL`), touch a non-pending report, touch anyone else's report, or smuggle a status
change out inside the same UPDATE (`'resolved'` fails `new_status = 'pending'`).
**F5** holds — `USING` is only evaluated for rows the UPDATE actually matched, so a
nonexistent report still cannot reach `WITH CHECK`. The staff branch is unchanged
byte-for-byte.

> **State: reasoned through and statically checked, NOT executed.** The migration and
> the suite edit are committed; the live database still has `20261005140000` applied
> and **not** `20261005150000`. Apply it, then re-run the suite. Expect 92/92. **If u8
> still fails, the remaining suspect is `my_role()` returning NULL inside the policy
> context** — the `u8-diag` rows now isolate it, and that would be a much narrower bug.

**Lesson worth not repeating.** Twice here the fix was written from a plausible
mechanism and the suite said no. What actually worked was stopping and reading the
function again with the specific question *"which subquery touches the column being
updated?"* A green suite does not prove the reasoning was right, but a red one
definitively disproves it — and the fix that landed came from re-reading, not from
another theory.

Two diagnostic helpers are committed alongside it and are safe to re-run:
`supabase/tests/probe_rls_flags.sql` (RLS flags, ownership, `BYPASSRLS`,
`SECURITY DEFINER`) and `supabase/tests/probe_live_policies.sql` (live policy dump vs
repo). The first was written to chase a `FORCE RLS` theory that turned out not to be
the cause; it is kept because it is the right tool if `u8` somehow survives.

**This is precisely the class of defect 258 mocked Flutter tests cannot reach**, and it
is the justification for having written the suite at all.

**Three design points worth keeping if this file is ever extended:**

1. **"Denied" does not mean "raised an error."** A `WHERE` clause matching only
   RLS-hidden rows updates **zero** rows and reports *success*. The obvious helper —
   run the statement, expect an exception — therefore reports `ALLOWED` for a
   perfectly correct policy and fails the suite. Every "must not change" test instead
   asserts the resulting **row state** through a `SECURITY DEFINER` probe, which
   holds whether the statement raised or was silently filtered, and which also
   catches the dangerous case where it succeeded and did change the row. The first
   draft of this file had this bug and would have produced four false failures.
2. **Allowed writes must be undone.** Each write test raises a private marker to
   unwind its own subtransaction, so a successful insert cannot perturb a later
   count. The result row is written outside that subtransaction, in the exception
   handler, which is why it survives.
3. **Fixture ids must not collide with real data.** `departments.code` is unique and
   `communities` is `UNIQUE (course_code, batch_year, semester, section)`, so a
   literal fixture id raises regardless of `ON CONFLICT (id)` — the seeded `GENERAL`
   department and any real `BCA 2024 S5 C` community already occupy those keys. Both
   are resolved by key and reused. Everything the suite owns carries the `f1ce0000`
   prefix and every count filters on it.

**Status: EXECUTED twice on 2026-10-05 — second run 92 assertions, 91 passing, 0 fixture
problems.** There is no Supabase CLI, `psql` or Docker in this environment, so it is run by
pasting it into the SQL Editor. First run: 2 failures — one (`u1` carol) a wrong test
expectation, since fixed; one (`u8`) a genuine policy defect. Second run: 1 failure, still
`u8`, because the first fix was wrong. **`20261005150000` is the third attempt and has not
been run — apply it and re-run to confirm 92/92.**

Three Supabase SQL Editor quirks, all hit and worked around:

1. `pg_temp` is unusable — `create function pg_temp.…` fails with
   `3F000: schema "pg_temp" does not exist` even after a temp table exists in the same
   session. Helpers therefore live in an ordinary schema `f1ce_rls`.
2. Answer **Run without RLS** when prompted; the only table created is a scratch
   results table that is dropped again.
3. Never rely on the trailing `ROLLBACK` alone. The script now deletes its own fixtures
   and helper objects explicitly, before *and* after the assertions, so an aborted run
   cannot pollute the database and re-running is always safe.

---

## 8. Invariants — do not break

- `auth.users.id = profiles.id = auth.uid()`.
- Community derived **server-side only**; the client never supplies
  course/year/semester/section/community_id.
- Linways passwords, `AUTH_SESSION`, access/refresh tokens: in-memory or
  device keychain only. Never in the DB, files, or logs.
- Passwords/tokens/cookies are never logged — server or client.
- AI is assistive only: never rejects a report, never overwrites student data.
- `report_type` is **community only** for both students and admins
  (`rls_security.sql:125,132`). The `private` enum value is unreachable. Do not
  add a "Visibility" field to any student flow.
- `priority` is the student's choice (u4); AI records a prediction separately.