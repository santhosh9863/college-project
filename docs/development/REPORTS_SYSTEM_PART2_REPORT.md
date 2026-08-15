# Part 2 Final Report — Community Reports System (Student-Facing)

**Date:** 2026-08-15 · **Scope:** "college project" Flutter app (`flutter_app`) + Supabase (`supabase/`)
**Status:** ✅ Implemented in 4 approved parts (2-A backend → 2-B data layer → 2-C UI → 2-D validation)
**plus a post-review fix round (§17)** — the report-creation and evidence-upload bugs found in live
verification are root-caused, fixed (5 new migrations) and verified end-to-end with a real student JWT.
`flutter analyze` clean, **171/171 tests passing** (93 Part 1 + 78 new), `flutter build apk --debug` successful.

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

- All **27 migrations** recorded remotely (Local = Remote for each; 22 original + 5 fix-round, §17).
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
  for "community not assigned" / "missing department". Failures are logged with `debugPrint`, kept on
  `lastSubmitError` (testable), and surfaced verbatim in debug builds (generic message in release) — the
  post-review fix that made the real cause of creation failures visible.

## 8. UI — Reports home (Part 2-C)

`reports_screen.dart` rewritten: search field, status chips, priority chips, category dropdown +
"My reports" filter chip, "Clear filters" when active, distinct empty states (no reports vs no matches),
pull-to-refresh, `New report` FAB, report tiles with priority icon, status badge, description preview,
support count and generic author label ("You" / "Community member"). Returning from create/detail reloads
the feed. The category + "My reports" row is **responsive** (post-review fix): below 520 px the field and
chip stack vertically instead of overflowing, and the dropdown sizes intrinsically on narrow screens.

## 9. UI — Create report (Part 2-C)

`create_report_screen.dart` (new): title (200), description (2000), category picker opening a
**scrollable bottom sheet** with the selected category marked (post-review fix, replaces the dropdown),
4-way priority `SegmentedButton` inside a horizontal scroll view so labels never wrap on narrow screens
(post-review fix), photo evidence via `image_picker` (up to 5, thumbnails with remove, MIME-gated), inline
first-error hints after a submit attempt, friendly error banner, submit button with busy state. Identity
fields are never inputs.

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
| Migration state (`supabase migration list --linked`) | 27/27 applied, Local = Remote |
| `GET /rest/v1/{reports,report_comments,report_supports,evidence_files,report_activity,report_assignments,categories,profiles,communities,notifications}` with **anon** key | **401** on all 10 |
| `GET /storage/v1/bucket/evidence` with anon key | **404 NoSuchBucket** (bucket hidden from anonymous) |
| `GET /storage/v1/object/info/evidence/...` with anon key | **404** (objects not enumerable) |
| `linways-login` function | ACTIVE v2 (deployed) |
| Policy logic (`20260811103300_rls_security.sql` reviewed) | students: own-community + own-history reads, own pending-only updates, own-community support with open-status + not-own-report checks, own comments delete; anon: no table privileges; server-generated tables: no client writes |
| Storage policies (from `20260815102000_evidence_storage.sql` as fixed in §17) | select = visible report, insert = own report (path + owner + report checks), delete = admin |

Policy behavior was exercised **as an `authenticated` session** through the Management API SQL endpoint
(claims set, `my_role()`/`auth.uid()` live): create-report gate, the `INSERT … RETURNING` visibility
failure, the storage `exists(...)` check, and the full create→upload→evidence→sign→activity flow (§17).
The anon surface stays 401/404.

## 14. Test summary

78 new tests under `flutter_app/test/features/reports/` (+93 Part 1, all passing; +3 over the 2-D baseline
from the fix round):

- `report_models_test.dart` — enum parsing (incl. `critical`), Report/`ReportDetail` parsing, support-count
  embed, `copyWith`, comment/evidence ownership flags, `displayMessage` mapping, MIME mapping.
- `reports_repository_test.dart` — MockClient-based PostgREST contract tests: feed selects/embeds, filter
  query params (`eq`/`ilike`/order/limit), `.single()`/`.maybeSingle()` semantics, exact create payload,
  support/comment/cancel writes, storage upload + signed URL, error propagation.
- `categories_repository_test.dart` — parse + error paths.
- `reports_controller_test.dart` / `report_detail_controller_test.dart` / `create_report_controller_test.dart`
  — fake-repo controller tests: states, filter propagation, optimistic toggle + revert, comment lifecycle,
  cancel, community/department gating, validation ordering, `lastSubmitError`/debug-error surfacing.
- `reports_screens_test.dart` — widget tests for all three screens (tiles, empty/filtered states, clear
  filters, validation hints, category bottom sheet with selected marking, priority options present at
  narrow widths, debug error card, detail sections, own-report support-card hiding, no-overflow filter bar
  at 320 px).

Notable test-infra findings fixed along the way: MockClient responses need `request` attached (postgrest
dereferences it), `.single()` on POST expects a JSON object (not array), `order` emits `.nullslast`, and
gotrue's auto-refresh timer must be disabled in widget tests.

## 15. Validation results

| Check | Command | Result |
|---|---|---|
| Static analysis | `flutter analyze` | **No issues found** |
| Tests | `flutter test` | **171/171 passing** |
| Debug build | `flutter build apk --debug` | **√ Built `build/app/outputs/flutter-apk/app-debug.apk`** (52 s) |
| Migrations | `supabase migration list --linked` (fix round) | **27/27 applied**, Local = Remote for each |
| Edge Function | `supabase functions deploy linways-login` (2-A) | Deployed, ACTIVE v2 |
| TS syntax | `tsc --noEmit` (2-A) | Only pre-existing Deno/module-type environment errors (no deno binary on host) |

## 16. Known limitations & pending validation

- **Device manual pass**: the flow is verified end-to-end through the live PostgREST/storage API with a real
  student JWT (§17), but a hand-held manual pass on a device remains pending: login → create report with
  photos → visible to second test student → support → comment → cancel own pending report → notification
  badge reflects new events.
- Students who logged in before the departments seed get `department_id` at their **next login** — the app
  shows a clear "sign out and sign back in" error until then.
- Evidence viewer is in-app image preview only (no external PDF opener — no `url_launcher` dependency added).
- `category_routes` seeding (routing staff roles) is deliberately deferred to the Authority Panel phase —
  until then the server creates the report's activity row but no notification rows.
- iOS build not verified (Windows host).

**Part 3 readiness:** the activity timeline, notifications and assignment tables are already live and
RLS-gated; Part 3 (Authority Panel, staff lifecycle actions, AI classification, `category_routes` seeding,
notification generation) plugs into the existing policies, `report_activity` display and the storage helper
functions without schema changes.

---

## 17. Fix round (2026-08-15, post-review) — creation & evidence bugs root-caused and fixed

Live verification found and fixed **two independent backend bugs** plus a visibility gap, all reproduced
with a real student JWT against `bvxuvkpmpufsbxvpdkht` and confirmed after the fix. No applied migration was
modified; five new migrations were added and pushed (27/27 recorded, Local = Remote).

### 17.1 Root cause 1 — report creation failed with a generic error (RLS `42501`)

**Symptom:** `POST /rest/v1/reports` with the app's payload (`Prefer: return=representation` +
`select=id` — exactly what `.insert(...).select('id').single()` produces) returned
`42501 new row violates row-level security policy for table "reports"`.

**Root cause:** the `reports_select_visible` policy used
`report_visible_to_caller(id)`, which re-reads `public.reports` in a subquery. PostgREST applies the
SELECT policy to the **returned** row of `INSERT … RETURNING`; the subquery runs in the same statement's
snapshot and cannot see the just-inserted row, so the policy evaluated to false and the insert was
rejected. A plain insert without `RETURNING` succeeded — which is why the failure only appeared in the app
(`.select('id')`).

**Fix — `20260815103000_fix_returning_visibility.sql`:** added
`public.report_visible_to_caller_row(p_report_id, p_community_id, p_reporter_id, p_deleted_at)` — the
student branch uses the **row's own columns** (no self-reference); staff/admin branches delegate to
`report_visible_to_staff` — and redefined `reports_select_visible` as
`using (public.report_visible_to_caller_row(id, community_id, reporter_id, deleted_at))`.

**Verified live:** the app-shaped insert now returns **201 + the row** (`id`, `status`, `priority`);
plain inserts unchanged; student detail reads of the created report return 200.

### 17.2 Root cause 2 — evidence uploads rejected with `403 AccessDenied`

**Symptom:** `POST /storage/v1/object/evidence/<reportId>/<ts>_x.png` with the student JWT returned
`403 new row violates row-level security policy` even though the report existed and the SQL-level check
of the policy's `exists(...)` was TRUE.

**Root cause (two bugs, found by diagnostic policy + inspecting the stored row):**
1. **Wrong path parsing** — the storage service stores `storage.objects.name` **without** the bucket
   prefix (`8b46…/file.png`, not `evidence/8b46…/file.png`). `storage_evidence_report_id` required the
   `evidence/` prefix, so it resolved to NULL for every real upload. (The stored-object inspection also
   proved the service **does** set `owner = auth.uid()` — the `owner` clause was never the problem.)
2. **`storage.buckets` visibility** — the migration created the bucket row directly, but `storage.buckets`
   has RLS enabled with **no select policy**, so the storage service (evaluating as the user) reported the
   bucket as missing (`GET /bucket` → `[]`, `/bucket/evidence` → 404) for every authenticated request.

**Fix:**
- `20260815105000_fix_evidence_path.sql` — `storage_evidence_report_id` now parses the **first folder**
  (`(storage.foldername(p_name))[1]::uuid`), matching the service's prefix-free names.
- `20260815106000_fix_storage_bucket_policy.sql` — `select` policy on `storage.buckets` for
  `authenticated` (object-level access stays fully gated by the `storage.objects` policies; bucket names
  are not sensitive).
- `20260815107000_restore_evidence_owner.sql` — restores the `owner = auth.uid()` conjunct that was
  removed while the path bug masked the real cause (defense-in-depth, owner provenance).

**Verified live (full E2E, student JWT):** create report → upload evidence → **200 + key** →
`evidence_files` insert → **201** → `createSignedUrl` → **200 with token** → server `report_activity`
row created → student detail reads of report/evidence/activity → **200**. The final upload also passes
with the restored `owner` conjunct.

### 17.3 Root cause 3 — the client hid the real failure

**Fix:** `CreateReportController.submit()` now logs the failure with `debugPrint`, keeps it on
`lastSubmitError`, and debug builds show `Could not create the report. Details (debug): <error>` while
release builds keep the generic message.

### 17.4 UI polish in the same round

- Category picker → **scrollable bottom sheet** with the chosen category visually marked (check icon +
  selected tile).
- Priority `SegmentedButton` wrapped in a horizontal scroll view — labels no longer wrap on narrow screens.
- Filter bar category + "My reports" row is **responsive** (stacks below 520 px; dropdown sizes
  intrinsically; overflow regression-tested at 320 px).

### 17.5 Test delta & cleanup

- 3 new tests (net): debug error surfacing (controller + widget), category sheet selection, priority
  options at narrow widths, no-overflow filter bar at 320 px → **171/171 passing**, analyze clean.
- All repro artifacts removed from the linked project (test users, probe reports, storage test objects —
  via `storage.allow_delete_query` for the trigger-protected orphan, the repro community, diagnostic
  tables); the 14 seeded categories and the original seeded communities are untouched.

---

## 18. Phase 2.4 — HOD panel (2026-08-15)

Panel-system prerequisites (Phase 2.2) are committed (`92a7228`): `category_routes` seeded (16 rows) and
`report_visible_to_staff` + notification recipients department-scoped (D1), verified live with claims-based
simulation and a real-role matrix check; a latent trigger bug (`setof uuid` helper + `s.id` reference) was
caught by the simulation and fixed in `20260815122000_fix_routed_staff_helper.sql`.

### 18.1 Delivered (Flutter, role-branched shell)

- `HomeShell` now branches on `profiles.role`; non-students get `StaffHomeShell` (Queue / Notifications /
  Profile). HOD panel implemented; technician/operations/admin show a "later phase" placeholder.
- New `features/staff/`: `StaffReportsRepository` (D1-scoped queue read via RLS + `updateStatus` PATCH),
  `HodQueueController` (status/search filters), `HodDetailController` (lifecycle actions), `HodQueueScreen`,
  `HodDetailScreen` (bottom action bar: Start review / Mark in progress (only with active assignment) /
  Mark resolved / Reject with optional reason comment), `StaffHomeShell`.
- Shared detail widgets extracted to `features/reports/widgets/report_detail_widgets.dart` (header, section,
  activity, evidence, comment, badges, error body) — reused by both student and staff detail screens; the
  student screen keeps its support card and own-pending cancel, unchanged behavior.
- No client-side permission logic: the app only renders actions the HOD may legally take; the database
  (`can_transition_status`, D8) is the authority and server rejection is surfaced.

### 18.2 Verification

- **197/197 tests passing** (26 new: staff repository HTTP-mocked, queue controller, detail controller with
  shared fake server state exercising the reload path, screen widgets), `flutter analyze` clean, APK built.
- **Live E2E with a real HOD JWT** (admin-created auth user + profile in the General department, Academic
  probe report): queue returns exactly the department-routed report; `pending -> under_review` → **200**;
  `under_review -> resolved` → **403** (D2); `under_review -> in_progress` → **403** (D8, no assignment);
  backwards `-> pending` → **403** (matrix). All probe artifacts removed afterwards.

### 18.3 Migration/status

- 30/30 migrations recorded, Local = Remote (committed `92a7228`; this phase is client-only).
- Next: Phase 2.5 Technician panel, 2.6 Operations panel (assignment), 2.7 Admin, 2.8 Notifications inbox
  polish, 2.9 analytics RPCs (D6), 2.10 security/test audit.

---

## 19. Phase 2.5 — Technician panel (2026-08-15)

### 19.1 Delivered (client-only; shared staff panel generalization)

- The Phase 2.4 staff components were role-agnostic already (D7: H/T share the same forward-transition
  set). They were renamed to shared names — `StaffQueueController`/`StaffQueueScreen`,
  `StaffDetailController`/`StaffDetailScreen` (`lib/features/staff/`, `git mv` tracked) — and
  `StaffHomeShell` now routes **both** `hod` and `technician` to the queue; operations/admin keep the
  placeholder until their phases.
- Technician behavior on the shared panel: D1-scoped routed queue (e.g. IT & Network) + assigned reports;
  actions per matrix: `pending -> under_review`, `pending -> in_progress` (only with active assignment,
  D8), `pending -> rejected`, `under_review -> in_progress/rejected`, `in_progress -> resolved/rejected`.

### 19.2 Verification

- **197/197 tests passing**, `flutter analyze` clean (rename-only refactor; controller/screen logic
  unchanged).
- **Live E2E with a real technician JWT** (admin-created auth user + profile, General department, IT &
  Network probe): queue returns exactly the routed IT & Network reports; `pending -> under_review` → 200;
  `under_review -> in_progress` without assignment → **403** (D8). Assignment created as the ops actor
  (claims-simulated): `assignment` notification delivered to the assignee (D9), then
  `under_review -> in_progress` → 200 and `in_progress -> resolved` → 200 with the assignment
  auto-deactivated (`unassigned` activity, metadata `assigned_to`). Full server trail observed:
  `created -> status_change -> assigned -> status_change -> status_change -> unassigned` — matches
  REPORT_LIFECYCLE.md §7 exactly. Probe report, activity, notifications, and the test user removed
  afterwards (baseline: 1 report, 0 notifications, 0 assignments).

### 19.3 Status

- Still 30/30 migrations (client-only phase). Next: Phase 2.6 Operations panel (assignment management,
  D2/D8 enforcement UI, reopen for O/A).

---

## 20. Phase 2.6 — Operations panel (2026-08-15)

### 20.1 Backend (one new migration, 31/31 recorded, Local = Remote)

`20260815123000_list_assignable_staff_rpc.sql` — `profiles` RLS allows only own-row
reads (or admin), so the assignment picker needed a staff directory:
`public.list_assignable_staff()` is a SECURITY DEFINER RPC returning id/full_name/role/
department_code of all non-student profiles, gated in-body to `operations`/`admin`
(everyone else gets an empty set — no RLS bypass).

### 20.2 Delivered (Flutter)

- `StaffReportsRepository`: `listAssignableStaff` (RPC), `assign` (POST
  `report_assignments`, push-only D3), `unassign` (PATCH active=false). New model
  `AssignableStaff`.
- `StaffDetailController` (role-aware): `canManageAssignments`/`canReopen` (ops/admin),
  staff directory loaded on open, `assignTo`/`unassign` with reload, `assigneeName`
  resolution, and reopen transitions — **offered only when a new active assignment
  exists (D8), matching the backend rule that reopen to ANY target requires an active
  assignment** (caught by reading `can_transition_status` before implementing; the
  client mirrors the DB exactly).
- `StaffDetailScreen`: `_AssignmentCard` (ops/admin only — current assignee, Assign/
  Change/Unassign) + `_AssignDialog` (staff picker with role/department labels);
  action bar gains "Reopen review"/"Reopen work" for resolved/rejected.
- `StaffHomeShell` routes `operations` to the shared queue.

### 20.3 Verification

- **209/209 tests passing** (12 new: reopen gating incl. D8, assignment flows, RPC
  directory gating, picker dialog, assignment card visibility), `flutter analyze`
  clean, APK built.
- **Live E2E with real ops JWT** (General dept, Infrastructure probe): queue = exactly
  the routed ops report; `list_assignable_staff` returns the directory for ops and
  **[]** for a technician JWT; `pending -> under_review` → 200; assignment POST as ops
  → 201 and as technician → **403** (D2); `-> in_progress`/`-> resolved` → 200;
  `resolved -> under_review` without a fresh assignment → **403** (D8); reassign → 201;
  reopen `-> under_review` → 200 (D5); unassign PATCH → 200. Assignee notification
  trail observed per D9 (`assignment` on assign/reassign/deactivate, `status_change`
  on progress/reopen, `report_new` on creation). All artifacts and test users removed
  afterwards (baseline: 1 report, 0 notifications, 0 assignments).

### 20.4 Status

Next: Phase 2.7 Admin panel (read-all queue, moderation soft-delete/restore), 2.8
notifications inbox polish, 2.9 analytics RPCs (D6), 2.10 security/test audit.
