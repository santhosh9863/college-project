# Part 2 Final Report — Community Reports System (Student-Facing)

**Date:** 2026-08-15 · **Scope:** "college project" Flutter app (`flutter_app`) + Supabase (`supabase/`)
**Status:** ✅ Implemented in 4 approved parts (2-A backend → 2-B data layer → 2-C UI → 2-D validation).
`flutter analyze` clean, **168/168 tests passing** (93 Part 1 + 75 new), `flutter build apk --debug` successful.

---

## 1. Summary

Part 2 delivers a complete student-facing community reports system: students can **create** reports
(title/description/category/priority/photo evidence), **browse** their community's reports (status/category/
priority filters, title search, own-reports view), open a **detail** screen (status, priority, support,
comments, evidence, activity timeline), **support** community reports, and **cancel** their own pending report.
All reads/writes go through PostgREST and are enforced by database RLS — the client never sends identity
fields as user input. The Authority Panel, AI classification and notification inserts remain out of scope
(Part 3).

## 2. Scope & constraints honored

- Project name stays **"college project"** — no PULSE / SafeBunk / Campus Pulse branding.
- Part 1 (Linways screenshot import, `f4b7272`) untouched — all 93 Part 1 tests still pass.
- **No** AI/ML, dataset work, Authority Panel, private reports, or new backend tables/endpoints beyond the
  three approved migrations; no new Edge Functions (linways-login was *modified*, not added).
- RLS is the security boundary; there is **no** client-side community filtering. Identity snapshots
  (`reporter_id`, `community_id`, `department_id`) come only from the authenticated state.
- Initial status `pending`, type `community`; students can only soft-delete their own pending report.
- Categories come from the database (14 seeded), never hardcoded.
- Evidence lives in a **private** storage bucket (images + PDF, 20 MiB), never public.

## 3. Backend changes (Part 2-A) — 3 new migrations, 1 modified Edge Function

| Artifact | Purpose |
|---|---|
| `supabase/migrations/20260815100000_priority_critical.sql` | `alter type public.priority add value 'critical'` — 4-level priority |
| `supabase/migrations/20260815101000_seed_categories_departments.sql` | Seeds the **14 approved categories** + `GENERAL` department (idempotent, `on conflict do nothing`) |
| `supabase/migrations/20260815102000_evidence_storage.sql` | Private `evidence` bucket (20 MiB, `image/png,jpeg,webp,heic` + `application/pdf`); `public.storage_evidence_report_id(text)` (SECURITY DEFINER, fails closed); storage RLS policies `evidence_select_visible`, `evidence_insert_owner`, `evidence_delete_admin` |
| `supabase/functions/linways-login/index.ts` (modified) | `resolveDepartmentId()` maps the Linways course code → `departments.code` (fallback `GENERAL`); login upserts `profiles.department_id` and returns it |

Existing students receive their `department_id` on the **next login** (expected; `reports.department_id` is
NOT NULL, so create-report is blocked with a clear message until then).

## 4. Remote verification (Part 2-A)

All verified against the linked project `bvxuvkpmpufsbxvpdkht` after `supabase db push --linked`:

- All **22 migrations** recorded remotely (Local = Remote for each).
- `priority` enum includes `critical`; **14 categories** present; department `GENERAL` present.
- Bucket `evidence`: **private**, 20,971,520 bytes, image+PDF MIME allow-list; 3 storage policies live.
- `linways-login` Edge Function deployed (ACTIVE, v2).

## 5. Data layer — models (Part 2-B)

All under `flutter_app/lib/features/reports/data/models/`:

| Model | Notes |
|---|---|
| `Report` | Feed/detail core; `isMine`/`isSupported` are display-only computed against the authenticated user id; `supportCount` parsed from the `report_supports(count)` embed |
| `ReportStatus` | `pending → underReview → inProgress → resolved / rejected / closed` + `unknown`; `apiValue`/`label`/`fromApi` |
| `ReportPriority` | `low / medium / high / critical / unknown` |
| `ReportCategory`, `ReportComment` (`isMine`), `EvidenceFile` (`isMine`) | Simple JSON mappers |
| `ReportActivityItem` | Server-generated timeline row; `displayMessage` maps event → user-facing text (never leaks internal metadata) |
| `ReportDetail` | Composed report + comments + evidence + activity + `activeAssigneeId` (display only — staff names are not readable by students) |

## 6. Data layer — repositories (Part 2-B)

- **`ReportsRepository`** (client injected; `currentUserId` for display flags):
  `fetchFeed` (status/category/priority `eq`, `ilike` title search, `mineOnly`, `order created_at desc`,
  limit 50), `fetchMySupportedIds`, `fetchDetail` (throws `ReportNotFoundException` when RLS hides the row),
  `fetchMyCommunityId` (`communities` via `maybeSingle` — RLS guarantees own community), `createReport`
  (sends `report_type: community`, `status: pending`, department/community/reporter from authenticated state),
  `addSupport`/`withdrawSupport`, `addComment`/`deleteComment`, `cancelReport` (PATCH own row: `deleted_at` +
  `updated_at`, status untouched), `uploadEvidence` (private-bucket `uploadBinary` + `evidence_files` insert),
  `signedEvidenceUrl` (`createSignedUrl` for display only).
- **`CategoriesRepository`** — ordered `SELECT id, name` from the database.
- **`evidence_mime.dart`** — extension → MIME mapping (octet-stream fallback is rejected server-side).

## 7. Data layer — controllers (Part 2-B)

- **`ReportsController`** — feed state machine (loading/ready/error), filter state, `hasActiveFilters`,
  `clearFilters`, category loading (isolated from feed failures), factories
  `detailControllerFor(reportId)` and `createReportController(profile, community)`.
- **`ReportDetailController`** — optimistic support toggle **with revert on failure**, comment add/delete,
  own-pending `cancelReport`, `uploadEvidence`, `signedUrlFor`.
- **`CreateReportController`** — form validation (`validationMessage`/`canSubmit`), evidence drafts (max 5),
  submit pipeline: `fetchMyCommunityId()` → `profile.departmentId` → create → upload evidence; clear errors
  for "community not assigned" / "missing department".

## 8. UI — Reports home (Part 2-C)

`reports_screen.dart` rewritten: search field, status chips, priority chips, category dropdown +
"My reports" filter chip, "Clear filters" when active, distinct empty states (no reports vs no matches),
pull-to-refresh, `New report` FAB, report tiles with priority icon, status badge, description preview,
support count and generic author label ("You" / "Community member"). Returning from create/detail reloads
the feed.

## 9. UI — Create report (Part 2-C)

`create_report_screen.dart` (new): title (200), description (2000), category dropdown fed by the
repository, 4-way priority `SegmentedButton`, photo evidence via `image_picker` (up to 5, thumbnails with
remove, MIME-gated), inline first-error hints after a submit attempt, friendly error banner, submit button
with busy state. Identity fields are never inputs.

## 10. UI — Report detail (Part 2-C)

`report_detail_screen.dart` (new): header (status/priority/assignee badges, title, category, author label,
timestamps), description, activity timeline ("Updates"), evidence grid (private-bucket signed-URL thumbnails
with full-screen viewer; PDFs show a file tile — no external opener in scope), comments (add, delete own
with confirmation), support card (hidden for own reports), "Cancel my report" for own pending reports with
confirmation dialog, dedicated "no longer visible" state for `ReportNotFoundException`.

## 11. UI — Notifications badge (Part 2-C)

`home_shell.dart`: the Notifications destination shows a Material `Badge.count` bound to
`NotificationsController.unreadCount` (listens via `AnimatedBuilder`); the shell now passes the authenticated
`profile`/`community` snapshots into the reports tab for the create flow.

## 12. Client security posture

- All writes send only the approved columns; `reporter_id`/`supporter_id`/`author_id`/`uploaded_by` are set
  from `currentUserId`, `community_id`/`department_id` from the authenticated session — asserted **payload-
  level in tests** (`createReport` test asserts `report_type: community`, `status: pending`, etc.).
- No service-role key anywhere in the app (`AppConfig` holds only the anon key).
- Errors are never fatal leaks: optimistic support reverts, deletion requires confirmation, generic errors
  shown to the user.
- Generic identity labels only — students never see other students' names.

## 13. Live security verification (Part 2-D, external)

Without a DB password/psql available on this host, verification combined the applied-migration record, the
PostgREST/storage API surface, and the reviewed policy source:

| Check | Result |
|---|---|
| Migration state (`supabase migration list --linked`) | 22/22 applied, Local = Remote |
| `GET /rest/v1/{reports,report_comments,report_supports,evidence_files,report_activity,report_assignments,categories,profiles,communities,notifications}` with **anon** key | **401** on all 10 |
| `GET /storage/v1/bucket/evidence` with anon key | **404 NoSuchBucket** (bucket hidden from anonymous) |
| `GET /storage/v1/object/info/evidence/...` with anon key | **404** (objects not enumerable) |
| `linways-login` function | ACTIVE v2 (deployed) |
| Policy logic (`20260811103300_rls_security.sql` reviewed) | students: own-community + own-history reads, own pending-only updates, own-community support with open-status + not-own-report checks, own comments delete; anon: no table privileges; server-generated tables: no client writes |
| Storage policies (from `20260815102000_evidence_storage.sql`) | select = visible report, insert = own report, delete = admin |

Policy *simulation* as an `authenticated` role (e.g. cross-community reads, supporting own report) requires a
DB session and is listed as pending in §16.

## 14. Test summary

75 new tests under `flutter_app/test/features/reports/` (+93 Part 1, all passing):

- `report_models_test.dart` — enum parsing (incl. `critical`), Report/`ReportDetail` parsing, support-count
  embed, `copyWith`, comment/evidence ownership flags, `displayMessage` mapping, MIME mapping.
- `reports_repository_test.dart` — MockClient-based PostgREST contract tests: feed selects/embeds, filter
  query params (`eq`/`ilike`/order/limit), `.single()`/`.maybeSingle()` semantics, exact create payload,
  support/comment/cancel writes, storage upload + signed URL, error propagation.
- `categories_repository_test.dart` — parse + error paths.
- `reports_controller_test.dart` / `report_detail_controller_test.dart` / `create_report_controller_test.dart`
  — fake-repo controller tests: states, filter propagation, optimistic toggle + revert, comment lifecycle,
  cancel, community/department gating, validation ordering.
- `reports_screens_test.dart` — widget tests for all three screens (tiles, empty/filtered states, clear
  filters, validation hints, category options, detail sections, own-report support-card hiding).

Notable test-infra findings fixed along the way: MockClient responses need `request` attached (postgrest
dereferences it), `.single()` on POST expects a JSON object (not array), `order` emits `.nullslast`, and
gotrue's auto-refresh timer must be disabled in widget tests.

## 15. Validation results

| Check | Command | Result |
|---|---|---|
| Static analysis | `flutter analyze` | **No issues found** |
| Tests | `flutter test` | **168/168 passing** |
| Debug build | `flutter build apk --debug` | **√ Built `build/app/outputs/flutter-apk/app-debug.apk`** (31 s) |
| Migrations | `supabase db push --linked` (2-A) | Applied cleanly; the one `alter table storage.objects enable row level security` statement was removed (SQLSTATE 42501 — RLS is already on by default) |
| Edge Function | `supabase functions deploy linways-login` (2-A) | Deployed, ACTIVE v2 |
| TS syntax | `tsc --noEmit` (2-A) | Only pre-existing Deno/module-type environment errors (no deno binary on host) |

## 16. Known limitations & pending validation

- **Policy simulation as `authenticated`** (cross-community read attempt, supporting own report, deleting
  others' comments, cancelling a non-pending report) requires a DB session (psql/Docker) — pending a machine
  where that is available; the 401/404 surface checks and policy source review are complete.
- **Real-user e2e**: the flow has not been exercised on a device with a real student login; pending manual
  pass: login → create report with photos → visible to second test student → support → comment → cancel own
  pending report → notification badge reflects new events.
- Students who logged in before the departments seed get `department_id` at their **next login** — the app
  shows a clear "sign out and sign back in" error until then.
- Evidence viewer is in-app image preview only (no external PDF opener — no `url_launcher` dependency added).
- `category_routes` seeding (routing staff roles) is deliberately deferred to the Authority Panel phase.
- iOS build not verified (Windows host).

**Part 3 readiness:** the activity timeline, notifications and assignment tables are already live and
RLS-gated; Part 3 (Authority Panel, staff lifecycle actions, AI classification, `category_routes` seeding,
notification generation) plugs into the existing policies, `report_activity` display and the storage helper
functions without schema changes.
