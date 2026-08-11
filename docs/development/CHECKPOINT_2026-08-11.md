# Checkpoint — College Project

> Status snapshot after the Authentication + Linways Integration phase.
> Date: 2026-08-11. All items verified during the session.

---

## 1. Project State (verified)

| Item | State |
|---|---|
| Supabase project | `college_project` (ref `bvxuvkpmpufsbxvpdkht`), linked via CLI |
| Applied migrations (remote) | **18/18 in sync** (16 foundation + RLS + server-generated events) |
| Local-pending migration | `20260811103500_login_rate_limit.sql` (NOT applied, NOT pushed) |
| Edge Function | `linways-login` written locally (NOT deployed) |
| Flutter app | `flutter_app/` empty scaffolding (Flutter phase NOT started) |
| AI / dataset / training | NOT started (out of scope) |
| Docs | Approved: MASTER_ARCHITECTURE, RLS_POLICIES (u1–u23), REPORT_LIFECYCLE (D1–D10), JWT_AUTH_COMPATIBILITY (u22), AUTHENTICATION_ARCHITECTURE, LINWAYS_INTEGRATION_ARCHITECTURE (decisions 1–10) |

---

## 2. Completed Work

### 2.1 Database foundation — 18 applied migrations
- 16 foundation migrations: enums, departments, categories, category_routes, profiles, **communities**, **community_members**, reports (incl. `community_id` NOT NULL), report_assignments, report_supports, report_comments, report_activity, evidence_files, ai_classification_log, notifications, indexes (incl. partial unique indexes: one-active-assignment-per-report, one-active-membership-per-profile).
- `20260811103300_rls_security.sql` — **REVISION 2**: 99 statements, 9 helper functions (`my_role`, `my_community_id`, `report_visible_to_staff`, `report_visible_to_caller`, `can_create_report`, `can_transition_status`, `can_update_report_row`, `can_update_report`, `can_manage_assignment`); TOCTOU-safe `FOR UPDATE` guards; F1–F9 fixes; policy set u1–u23. **Applied & verified remote.**
- `20260811103400_server_generated_events.sql` — F4 triggers: 7 triggers / 9 functions (`SECURITY DEFINER`, `search_path=''`, revoked from PUBLIC); report_activity + notifications + assignment deactivation side effects per REPORT_LIFECYCLE §7–§8. **Applied & verified remote.**

### 2.2 Authentication + Linways Integration — written locally, not deployed
- `supabase/functions/linways-login/index.ts` — stateless login handshake Edge Function:
  - Linways `student-login-credentials` → `get-my-profile-details` (confirmed endpoints, defensive parsing, 15 s timeouts)
  - Server-side community derivation (versioned rules: batchName `BCA 2024 C` + currentSem `S5`; programme fallback; unparseable → `community: null` / community_pending)
  - Native Supabase Auth provisioning (Approach A): find via `profiles.student_id` → `admin.createUser` (synthetic email `<registerNo>@college-project.local` fallback) → profile upsert → get-or-create community (UNIQUE key, race-safe) → deactivate-then-activate membership (respects partial unique index) → `generateLink(magiclink)` → `verifyOtp` → real session handed to app once
  - Idempotent: repeated logins reuse identity; community change deactivates old membership; F9 race retried once
  - Rate limiting: 5 failures / 15 min / IP → 429; only credential failures count; best-effort; stores no secrets
  - No logging of credentials/tokens/cookies (grep-verified zero `console.*`)
- `supabase/functions/linways-login/deno.json` — pinned `jsr:@supabase/supabase-js@2`
- `supabase/config.toml` — `[functions.linways-login] verify_jwt = false`
- `supabase/migrations/20260811103500_login_rate_limit.sql` — `login_attempts` table (ip, outcome, attempted_at; RLS deny-all + revokes; isolated, no existing migration modified)

---

## 3. Validation Results (this session)

| Check | Result |
|---|---|
| sqlglot (19 migrations incl. rate limit) | FATAL: 0, WARNINGS: 0 |
| `deno check` (Deno 2.9.5, supabase-js 2.112.2) | PASSED |
| `deno lint` | PASSED |
| Community derivation unit tests | 6/6 PASSED |
| config.toml parse | OK |
| Remote migration sync | 18/18, verified after push |

---

## 4. Key Architecture Invariants (must not be broken)

- `auth.users.id = profiles.id = auth.uid()` by construction.
- Community derived server-side only; client never supplies course/year/semester/section/community_id.
- Linways session (`AUTH_SESSION`, accessToken, refresh_token) and passwords: in-memory only, device-held via FlutterSecureStorage in the Flutter phase; never in DB/files/logs.
- Reports/communities/comments/supports/evidence/notifications/assignments/AI belong to the college project — not Linways.
- The project is always called "college project" (never PULSE/SafeBunk/Campus Pulse).

---

## 5. Pending / Next Steps

1. **Review this checkpoint** and approve.
2. **Apply rate-limit migration**: `npx --yes supabase db push --linked` (only `20260811103500` is pending).
3. **Deploy function**: `npx --yes supabase functions deploy linways-login --no-verify-jwt`.
4. Live e2e smoke test with a real student Linways account (optional, requires credentials; validates login → profile → community → session).
5. Next roadmap phases: Flutter auth & onboarding (Phase 6), then community report CRUD, Realtime, AI, notifications, attendance dashboard, authority panel.

---

## 6. Constraints Honored

- 18 applied migrations: NOT modified.
- No Flutter code, no AI/dataset/training, no private-report semantics, no staff panels.
- No credentials/tokens/cookies logged or stored server-side.
- Nothing deployed or pushed without explicit instruction.
