# ADR-001: Authentication Architecture

> Decision record for the authentication approach used in the college project system.
> **Status: ACCEPTED — records what is built and enforced.** Written from the deployed
> Edge Function and the applied migrations, not from the architecture drafts, which
> had drifted from the code in three material ways (§1.1).
> **Scope of this record: how a caller proves who they are.** It does not settle
> authorisation, which is `ADR-002` and `RLS_POLICIES.md`.

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

The project has no password of its own for students. Identity comes from **Linways**,
the college's existing management system, which already holds the academic facts the
project needs — programme, batch year, semester, section. Those facts are available
nowhere else, and a student must not be able to type them.

That produces one hard constraint and one hard requirement:

- **Constraint:** Supabase RLS resolves `auth.uid()` from a verified JWT `sub` claim.
  Linways knows nothing about JWTs. Something must bridge the two, and the database
  must be able to trust the result.
- **Requirement:** the caller's community is **never** chosen by the client. A student
  who could submit their own `community_id` could read another class's reports.

Two further facts shape the design. **Edge Functions run on Deno and are
per-isolate**, so an in-memory session map loses sessions arbitrarily. And the Linways
API has **no revocation endpoint**, so its session cannot be authoritatively ended
from our side.

### 1.1 What the documentation previously claimed

Preserved because the drift is what made the design look undecided. All three items
were wrong, and each was verifiable in one grep.

1. **The login response was documented as `{ campus_pulse_jwt, ... }`** in two
   sequence diagrams: `AUTHENTICATION_ARCHITECTURE.md:40` and
   `LINWAYS_INTEGRATION_ARCHITECTURE.md:100`. The field is `supabase_session`
   (`index.ts:668`). Separately, "Campus Pulse" is a **banned project name** —
   `MASTER_ARCHITECTURE.md:298` forbids it in code, docs and commit messages — so the
   docs broke their own naming rule while describing the most security-sensitive
   payload in the system.
2. **`JWT_AUTH_COMPATIBILITY.md:5` claimed "No implementation"**, repeated at `:125`
   ("no implementation, no schema changes, no RLS SQL"). It is fully implemented: the
   `verifyOtp` sequence it recommends runs at `index.ts:490-513`, and the RLS it was
   gating exists as 32 live policies (28 of them in `rls_security.sql`).
3. **Staff authentication was documented as out of scope** — "provisioning OUT OF MVP
   (locked decision 5)" at `AUTHENTICATION_ARCHITECTURE.md:49`, restated at
   `LINWAYS_INTEGRATION_ARCHITECTURE.md:205` and `MASTER_ARCHITECTURE.md:267`. A
   complete staff login branch exists at `index.ts:563-608`.

The root cause is identical in all three: an architecture doc was written,
implementation proceeded without updating it, and the doc kept its
`DECISIONS LOCKED` header. A locked header on a stale document is worse than no
header, because it reads as authoritative.

---

## 2. Decision

Tags: **[D]** = already enforced by shipped code. **[N]** = new proposal here, not
yet implemented.

### 2.1 Linways is the only authority on student identity **[D]**

A student authenticates by presenting Linways credentials to the auth Edge Function,
which forwards them to `student-login-credentials` (`index.ts:183-188`, 15 s timeout
at `:29`). The password reaches only that request body — never a table, file, log, or
commit.

Success is decided on `data.success === true` alone (`:203`); `validLogin` is never
read. The access token is read defensively from either `accessToken` or `token`
(`:205`), and the profile fetch sends **both** the captured `Cookie` header and
`Authorization: Bearer` (`:210-221`), because the Linways profile endpoint requires
both.

### 2.2 The app receives a real Supabase session, not a custom JWT **[D]**

This is the most consequential decision, and the one the docs described worst.

The Edge Function mints a genuine GoTrue session by generating a magic link and
redeeming it on an **anon-key** client (`index.ts:490-513`):

```
serviceDb.auth.admin.generateLink({ type: "magiclink", email })  -> email_otp
anonDb.auth.verifyOtp({ type: "email", email, token: otp })      -> session
```

No email is sent and no user-visible link exists. The one-time token is read straight
out of `properties.email_otp` and returned to the app **once**
(`index.ts:665-684`); the client calls `setSession(access_token, refresh_token)`.

The payoff is that `auth.uid()` works **natively**. `sub` *is* `auth.users.id`, and
`profiles.id` is a foreign key to `auth.users (id)`
(`20260811102300_profiles.sql:6`), so the chain
`auth.uid() = profiles.id = auth.users.id` holds by construction rather than by
convention. RLS needed no compatibility shim because there is nothing to be
compatible with.

### 2.3 Student provisioning is find-or-create, keyed on `student_id` **[D]**

Students have no password, so the Supabase user is created programmatically with a
**random server-only password that is generated, used once, and discarded**
(`index.ts:332-333`). The account is therefore effectively password-less: no
credential exists that could be used through the password path.

Existing users are found by `profiles.student_id` then `admin.getUserById`
(`:319-329`) — **not** by the deterministic email `MASTER_ARCHITECTURE.md:129`
describes. The email prefers the real Linways address and falls back to a synthetic
`@college-project.local` one (`:309-310`).

Login is idempotent by construction: repeat logins converge on one row. A
3-iteration retry loop absorbs the concurrent-first-login race where two requests both
fail to find the user and both try to create it (`:304-353`).

### 2.4 Community is derived server-side, never accepted from the client **[D]**

`deriveCommunity` maps `batchName` + `currentSem` to a community using regex rules
with a `programme` fallback (`index.ts:264-298`). The client sends no community
identifier. This is locked decision 7, and it is the basis of the isolation model in
`ADR-002`.

When mapping fails, `deriveCommunity` returns `null` (`:295`), no community or
membership row is created (`:652-657`), and the response carries `community: null`
(`:681`). No persisted `community_pending` state exists — see §5.

### 2.5 The auth service holds no session state **[D]**

Every request is self-contained. Linways cookies are forwarded in memory and handed to
the client (`:190-194`, `:682`); they are never persisted server-side. Locked
decisions 9 and 10 hold.

### 2.6 Staff authenticate with a Supabase password on the same endpoint **[D]**

Staff are not Linways users, so the function branches before the handshake. A
`profiles` row matching `email = username.trim().toLowerCase()` whose role is in
`{hod, technician, operations, admin}` triggers `anonDb.auth.signInWithPassword`
(`:570-608`). No Linways call is made, `community` is `null`, and
`linways_session_cookies` is `[]`.

Branch selection is by email match alone, so an unauthenticated caller can learn
which emails are staff accounts by observing whether the Linways path is taken. See
§5.3 — this should not ship as-is.

### 2.7 Rate limiting is DB-backed, IP-keyed, and fails open **[D]**

5 failures per 15 minutes per IP, with a 24-hour retention prune
(`index.ts:31-33`, enforced at `:535-548` before the body is even parsed). State
lives in `public.login_attempts`, which has RLS enabled with **zero** policies plus
explicit `revoke all` from `anon`/`authenticated`, making it `service_role`-write-only
(`20260811103500_login_rate_limit.sql:7-22`).

Only credential failures count; Linways outages and provisioning errors do not
(`:614-623`). IP comes from the last regex-validated `X-Forwarded-For` entry;
`X-Real-IP` is explicitly untrusted (`:110-122`). With no usable IP the limiter
**fails open** (`:138`) — deliberately, so a proxy quirk can never lock out a whole
campus, but it also means the limit is bypassable by header spoofing.

### 2.8 The endpoint is unauthenticated by necessity, closed by CORS **[D]**

`verify_jwt = false` (`supabase/config.toml:420`) — the function must accept
credentials from callers who have no session yet. Mitigations: `ALLOWED_ORIGINS` is
an **empty list** (`index.ts:38`), so no browser origin is echoed; every response
carries `Cache-Control: no-store` (`:44`); non-POST is 405 (`:523-525`). None of this
is documented in `docs/architecture/` — it appears only in `CURRENT_STATE.md`.

### 2.9 Role is database-controlled, never read from the token **[D]**

Every JWT carries `role: 'authenticated'`, which selects the **Postgres** role, not
the application `user_role`. Authorisation reads `profiles.role` through the
`SECURITY DEFINER` helper `my_role()`
(`20260811103300_rls_security.sql:24-31`). `user_metadata` is never used for
authorisation, because it is a user-modifiable claim space.

### 2.10 Logout clears both credentials **[D]**

`signOut()` revokes the refresh token server-side; the access token remains valid only
until its short `exp`. Linways cookies are discarded on-device only, since Linways
offers no revocation (`auth_repository.dart:43-46`). The Linways session therefore
cannot be ended authoritatively — a documented, accepted limitation.

---

## 3. Consequences

- **RLS became straightforward.** Because the session is genuine, no policy ever had
  to parse or trust a custom claim. The one dependency that gated all RLS work (u22)
  resolved without a shim.
- **Two credentials live on the device, not one.** The Supabase session is persisted
  through the SDK's `LocalStorage` hook under `college_project_sb_session`, stored as
  stringified session JSON because GoTrue decodes it
  (`secure_local_storage.dart:8-38`). Linways cookies sit in `FlutterSecureStorage`
  (`secure_store.dart:12-19`) and are used for direct attendance calls. Each has a
  different lifetime, so they can disagree.
- **The password path is unusable for students by design**, which means no
  self-service password reset, and a lost Linways password is the only recoverable
  case.
- **Auth depends on Linways uptime at login only.** After the handshake, Supabase
  sessions refresh without touching Linways. A Linways outage blocks new logins but
  not active sessions.
- **Staff authentication is real but unseeded.** `20261005120000` has never been
  applied, so today every staff login falls through to the Linways handshake
  (`index.ts:576`) and fails. Staff panels have consequently never been exercised
  against a live database.
- **Rate limiting is weaker than it looks.** Fail-open plus spoofable
  `X-Forwarded-For` means the 5-per-15-minutes limit deters casual abuse only.
- **Demo credentials are committed.** The staff seed contains four well-known
  plaintext passwords (`20261005120000:40-44`), against the "passwords in repo:
  prohibited" rule at `LINWAYS_INTEGRATION_ARCHITECTURE.md:314`. Mitigated by
  explicit demo-only labelling and removal instructions (`:16-21`).

---

## 4. Alternatives Considered

| Option | Verdict |
|---|---|
| **A. Native Supabase session** via `generateLink` + `verifyOtp` on an anon client | **Accepted.** Real refresh, real revocation, `auth.uid()` native, no custom signing, and it keeps the function stateless. `JWT_AUTH_COMPATIBILITY.md:46`, `:96-107`; implemented at `index.ts:490-513`. |
| **B. Self-minted JWT** signed with the project secret | **Rejected.** No refresh token, so every expiry forces a full Linways handshake; no server-side revocation, so a stolen token stays valid until `exp`; and it adds a hand-rolled signing and verification surface for no gain (`JWT_AUTH_COMPATIBILITY.md:47`, `:85`, `:90`, `:110`). |
| **C. Third-Party Auth provider** | **Rejected.** An external IdP adds high operational complexity when the identity source is already Linways, which is not an OIDC provider anyway (`JWT_AUTH_COMPATIBILITY.md:111`). |
| **D. In-memory session map inside the Edge Function** | **Rejected** as locked decision 9. Edge Functions are per-isolate; sessions would evaporate at random (`LINWAYS_INTEGRATION_ARCHITECTURE.md:396`). |
| **E. Persistent server-side Linways session store** | **Rejected** as locked decision 10. Violates the rule that Linways secrets never touch our server (`LINWAYS_INTEGRATION_ARCHITECTURE.md:397`). |
| **F. Separate `/auth/staff-login` endpoint** | **Rejected.** One endpoint keeps the rate limiter and audit trail in a single place. The cost is the staff-enumeration side effect in §2.6. |

---

## 5. Open Questions

1. **`community_pending` is documented but not implemented.** Six docs describe a
   persisted pending state for students whose `batchName` will not parse —
   `AUTHENTICATION_ARCHITECTURE.md:89`, `SYSTEM_ARCHITECTURE.md:36`,
   `RLS_POLICIES.md:74`, and locked decision 7 at
   `LINWAYS_INTEGRATION_ARCHITECTURE.md:394`. The code instead returns
   `community: null` and creates nothing. `public.profiles` has **no status column** to
   hold such a marker (`20260811102300_profiles.sql:5-15`), so the admin
   "assign a pending student" workflow these docs rely on has no target. Decide:
   add the column, or delete the capability from the docs.
2. **`admin.updateUserById` on repeat logins is specified but missing.**
   `JWT_AUTH_COMPATIBILITY.md:37` and `:100` both require refreshing `auth.users` so
   name and email changes propagate from Linways. `findOrCreateAuthUser` returns as
   soon as `profiles.student_id` resolves (`index.ts:319-329`), so only
   `public.profiles` is ever updated. Linways email changes are silently ignored.
3. **Staff login is an unauthenticated email oracle.** See §2.6. Worth fixing before
   this is demonstrated: either a second endpoint (option F) or an opaque
   "unrecognised username" response that makes both paths look identical.
4. **The rate limiter should stop failing open on a spoofed IP.** Consider keying on
   the platform-provided IP or treating a missing IP as a failure, accepting that a
   proxy misconfiguration would then lock users out.
5. **`linways_session_cookies` has two incompatible types** — `string` for students
   (`index.ts:682`), `[]` for staff (`:605`), and the client expects `String`, silently
   coercing `[]` to `''` (`login_result.dart:67-70`).
6. **`JWT_AUTH_COMPATIBILITY.md` needs its status header rewritten.** It still reads
   "RECOMMENDATION PENDING OWNER APPROVAL" and "No implementation" while
   `RLS_POLICIES.md:5` describes the same work as approved with no implementation.
   The doc set currently disagrees with itself about whether the project ships.
7. **The committed demo passwords need a retirement path.** Fine for a defence demo,
   not for anything deployed. Worth a documented "delete after seeding" step that
   someone actually performs.

---

## 6. References

- `supabase/functions/linways-login/index.ts` — the entire implementation
- `supabase/config.toml:419-420` — `verify_jwt = false`
- `supabase/migrations/20260811102300_profiles.sql` — `profiles.id` → `auth.users.id`
- `supabase/migrations/20260811103300_rls_security.sql` — `my_role()`, identity chain
- `supabase/migrations/20260811103500_login_rate_limit.sql` — `login_attempts`
- `supabase/migrations/20261005120000_seed_staff_demo_accounts.sql` — staff seed
- `docs/architecture/JWT_AUTH_COMPATIBILITY.md` — the Approach A/B/C analysis
- `docs/architecture/AUTHENTICATION_ARCHITECTURE.md` — stale; see §1.1
- `docs/architecture/LINWAYS_INTEGRATION_ARCHITECTURE.md` — locked decisions 1–10
- `docs/architecture/MASTER_ARCHITECTURE.md` — 20 non-negotiable rules
- `ADR-002-Database.md` — authorisation and community isolation
- `ADR-003-AI.md` — sibling record; same doc-vs-code discipline
- `docs/development/CURRENT_STATE.md` — authoritative current status
