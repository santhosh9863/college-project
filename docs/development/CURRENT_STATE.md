# Current State — read this first

> Handover doc. **Last updated 2026-10-05.**
> Purpose: whoever picks this up next (including an AI assistant with no memory
> of previous sessions) should be able to orient in under a minute.
>
> Supersedes `CHECKPOINT_2026-08-11.md` for day-to-day work; that file remains
> the record of the auth/Linways phase.

---

## TL;DR

Two things must be run in the Supabase SQL Editor, in this order:

1. **`supabase/migrations/20261005120000_seed_staff_demo_accounts.sql`** —
   creates the four staff demo accounts. They do not exist right now, so **all
   staff login and all four panel demos are dead** until it runs. Written and
   syntax-checked; never executed.
2. **The one query in §3.1** — decides the evidence-upload fix. The diagnosis
   previously recorded in this file was wrong (§3.0); the project is *not*
   paused, and the anon storage probe cannot distinguish a missing bucket from
   an RLS-hidden one.

Student login works. Submitting a report works **if you attach nothing** —
evidence upload is the one open bug. AI/ML is specified but not started.

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
| Notifications / analytics | ✅ Built (phases 2.8, 2.9) |
| Attendance + OCR import | ✅ Built (ML Kit, separate from reports) |
| AI / ML | 🟡 AI-0 + AI-1 written, **not applied** — duplicate detection only (§6) |
| Storage / evidence | ❌ Broken |
| `flutter analyze` | ✅ Clean (re-run 2026-10-05) |
| `flutter test` | ✅ 241/241 pass (re-run 2026-10-05) |
| Supabase CLI | ❌ **Not installed** — nothing can be deployed |
| Uncommitted changes | ✅ None — all work committed (this file still untracked) |

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
cd flutter_app; flutter run        # no Android device? check `flutter devices`
```

`flutter analyze` and `flutter test` were both clean at last run (241 tests).

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

### 5.4 Only Windows + Chrome/Edge devices are connected
`flutter devices` shows no Android device/emulator. The app has Android build
artifacts, so it has been run on Android before — start an emulator first.

### 5.5 The project must be called "college project"
Never PULSE / SafeBunk / "Campus Pulse" — in code, docs, commit messages, or
the report. `docs/references/PULSE_AUTHENTICATION_ARCHITECTURE.md` is a
reference doc only. (A draft AI plan repeatedly called it "Campus Pulse".)

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

**Biggest gap:** `duplicate_of` is written but **displayed nowhere**. Staff have
no "similar to report X" hint yet, so AI-1's value is currently invisible to the
people it helps. That's ADR-003 §5.1 and the natural next task.

Also still open: the `0.85` threshold is a **guess, not measured** (ADR-003
§5.2), and pre-existing reports are **not backfilled** (§5.3).

---

## 7. Parked / not started

- **Run `20261005120000_seed_staff_demo_accounts.sql`** — written + syntax
  checked, never executed. Blocks all staff login and all four panel demos.
- **Run `20261005123000_ai1_duplicate_detection.sql`** — written, never executed.
- Run the §3.1 type query — blocks the evidence upload fix
- Staff-facing duplicate hint — `duplicate_of` is written but shown nowhere
- AI-2+ (Edge Function, dataset, classification, priority)
- Install the Supabase CLI — every migration is currently hand-applied
- Real checkpoint doc for this phase (this file serves as it for now)

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