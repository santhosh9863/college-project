# JWT / Auth Compatibility Investigation

> How the college project's Linways-based login produces the token that Supabase RLS will enforce against.
> **Purpose:** clears dependency **u22** in `docs/architecture/RLS_POLICIES.md` — RLS SQL must NOT be written until this recommendation is approved.
> **Status: ACCEPTED — APPROACH A IMPLEMENTED.** This document was originally an
> investigation ("recommendation pending owner approval", "no implementation"). That
> status is stale: Approach A is shipped at
> `supabase/functions/linways-login/index.ts:490-513`, and the RLS it gated exists as
> 28 policies in `20260811103300_rls_security.sql`. The decision it reached is now
> recorded in `docs/decisions/ADR-001-Authentication.md` §2.2, which supersedes this
> document. **Two claims below are known to be wrong and are preserved as-written:**
> `admin.updateUserById` on repeat logins (§2.2) is not implemented, and the identity
> lookup is by `profiles.student_id`, not by deterministic email (§2.2).
> Sources: official Supabase documentation (JWT guide, JWT claims reference, Row Level Security, Auth Admin API, Custom Access Token Hooks, JWT Signing Keys, Edge Functions auth) plus current community reports on `auth.uid()` behavior.

---

## 1. Background

The approved authentication architecture (see `AUTHENTICATION_ARCHITECTURE.md`, `LINWAYS_INTEGRATION_ARCHITECTURE.md`, `ADR-004`) is:

- A **stateless auth Edge Function** performs a one-time Linways login handshake (`student-login-credentials` → `get-my-profile-details`), derives the community server-side, and writes `profiles` / `communities` / `community_members` via `service_role`.
- The app receives a **college project JWT** (per the docs' term) + Linways session cookies, both stored in FlutterSecureStorage.
- RLS (this phase) will enforce `auth.uid()`-based policies, assuming `auth.uid()` = `profiles.id`.

The gap: the approved architecture says "the auth service issues a short-lived college project JWT" but does **not** specify how that JWT is produced, how `auth.users` rows are created, or how the token interoperates with Supabase's RLS gateway. This document closes that gap against current official Supabase behavior.

---

## 2. Investigation findings (the nine points)

### 2.1 How the college project's Linways authentication creates/identifies the Supabase user

- Linways authenticates the student and returns the Linways profile (`name`, `registerNo`, `email`, `batchName`, `currentSem`).
- The **Supabase user identity** is the `auth.users.id` (UUID), not the Linways `registerNo`. `profiles.id` is a 1:1 copy of `auth.users.id` (`profiles.id uuid primary key references auth.users(id) on delete cascade`).
- The student has no college project password. Identification into Supabase must therefore be **programmatic** (created by the Edge Function), not password-based signup.
- Linways identity (`registerNo`) is stored as `profiles.student_id` (unique) for audit/linking, but is **not** a Supabase key.

### 2.2 How the Supabase user is created/maintained in `auth.users`

- Use the **Auth Admin API** from the Edge Function with the service role key: `supabase.auth.admin.createUser({ email, password, email_confirm: true, user_metadata })` — confirmed available in Deno Edge Functions.
  - `email`: the Linways email when present; otherwise a deterministic synthetic email built from `registerNo` (e.g. `<registerNo>@college-project.local`) so the flow is idempotent (login → find-or-create).
  - `password`: a **random, server-generated secret** that is never shown to the student (used only so GoTrue accepts the user record).
  - `user_metadata`: non-authoritative mirrors only (e.g. `full_name`, `linways_register_no`). **Never** authorization data (user-modifiable claim space).
- Maintenance: `admin.updateUserById` on subsequent logins (name/email changes); existing users are found by the deterministic email (`admin.listUsers` / `admin.getUserById`).
- The Edge Function then inserts `profiles` with `id = <auth.users.id>` (the returned user id), same transaction context, so `profiles.id ≡ auth.users.id` by construction.

### 2.3 How the token presented to PostgREST / Supabase Data API is issued

Two supported families (current official docs):

| Approach | How the token is issued | Status |
|---|---|---|
| **A. Supabase Auth session** | A real GoTrue session (`access_token` + `refresh_token`) obtained by redeeming a one-time link: `admin.generateLink({ type: 'magiclink', email })` → `supabase.auth.verifyOtp({ email, token: <email_otp>, type: 'email' })`. No email is actually sent; the token is returned to the Edge Function and handed to the app exactly once. | ✅ Fully supported; real session semantics |
| **B. Self-minted custom JWT** | The Edge Function signs a JWT itself (HS256 with the project JWT secret, or an imported JWT signing key) with claims `{ iss, aud, exp, iat, sub, role: 'authenticated', aal, session_id, ... }` and the app sends it via the SDK's `accessToken` option. | ⚠️ Officially supported only via **Third-Party Auth** or **imported JWT Signing Keys**; legacy HS256-with-JWT-secret works but is discouraged (see §2.5) |

**Recommendation: Approach A** (details in §3).

### 2.4 How `auth.uid()` resolves to `profiles.id`

- Official docs: `auth.uid()` returns the JWT `sub` claim from the request context. Cloud implementation: `coalesce(current_setting('request.jwt.claim.sub', true), current_setting('request.jwt.claims', true)::jsonb ->> 'sub')::uuid`.
- PostgREST populates `request.jwt.claims` **only when a verified user access token arrives in `Authorization: Bearer <token>`** (`role` claim = `authenticated`). The `apikey` header alone is insufficient; an unverified/absent token silently falls back to the `anon` role and `auth.uid()` = NULL.
- Since the user is provisioned via §2.2, `sub` = `auth.users.id` = `profiles.id`, so `auth.uid() = profiles.id` holds **by construction** for Supabase-issued tokens (Approach A).
- Type note: `auth.uid()` returns `uuid`; `profiles.id` is `uuid`. No cast issues.

### 2.5 How the JWT is signed and verified

- **Supabase-issued tokens (Approach A):** signed by GoTrue (HS256 with the project secret, or ES256 under newer signing-key configurations) and verified by the platform (GoTrue `/auth/v1/user` endpoint / JWKS). Verification is automatic — no custom code. Revocation and rotation are handled by Supabase.
- **Self-minted tokens (Approach B):** the JWT must be signed with a key Supabase trusts: either a key imported under **JWT Signing Keys** (preferred; asymmetric) or the shared project JWT secret (HS256). Official guidance explicitly **recommends against verifying/trusting HS256 shared-secret tokens on the client** and prefers Auth-server verification; community reports (2026) show verification drift issues (ES256 vs HS256) on some hosted projects, and `getClaims()` is only guaranteed for GoTrue-issued tokens.
- **Conclusion:** Approach B adds a custom verification surface with no benefit for this project.

### 2.6 Architecture choice (Supabase Auth sessions vs custom/third-party JWT)

| Criterion | A. Supabase Auth session (admin provision + link redeem) | B. Self-minted JWT (project secret / imported key) | C. Third-Party Auth provider |
|---|---|---|---|
| RLS `auth.uid()` native | ✅ | ✅ (if claims correct) | ✅ (but non-UUID `sub` requires text comparisons — N/A here) |
| Refresh token / auto-renewal | ✅ | ❌ (token expiry = re-login) | ✅ (provider-managed) |
| Server-side revocation (logout) | ✅ (GoTrue revokes refresh token) | ❌ (stateless; valid until `exp`) | ✅ |
| Fit with stateless Edge Function | ✅ (no server session state; one-time handoff like the Linways cookie handoff) | ✅ but needs re-mint flow | ❌ heavy: an external IdP is not warranted when the college project's identity source is Linways |
| Operational complexity | Low (standard admin API calls) | Medium (custom minting, no refresh) | High |
| **Verdict** | **Recommended** | Not recommended for MVP | Rejected |

### 2.7 How role information remains database-controlled

- The JWT's `role` claim selects the **Postgres role** (`authenticated` / `anon` / `service_role`) — it is **not** the application `user_role` (`student`/`hod`/`technician`/`operations`/`admin`).
- Every user's JWT carries `role: 'authenticated'`. Application roles come exclusively from `profiles.role`, read through a `SECURITY DEFINER` helper (`my_role()`), used by policies.
- **Never** use JWT `user_metadata` for authorization (user-modifiable per official docs). `app_metadata`/custom claims are tamper-resistant but still *cached* — the database remains the source of truth.
- Optional optimization (later): a **Custom Access Token Hook** (`custom_access_token_hook`) can mirror `profiles.role` into the issued token's claims. This is safe (hook runs before issuance) but is a cache only; policies must keep reading the database. **Not required for MVP.**

### 2.8 Token expiry / renewal

- Approach A: access tokens are short-lived (~1 h); the SDK (`supabase_flutter`) automatically refreshes using the `refresh_token` (long-lived) — standard Supabase session semantics. Renewal is transparent and reuses the existing device-held session; a refresh-token failure degrades to a Linways re-login (already the architecture's fallback on Linways 401).
- Approach B: a self-minted JWT has no refresh mechanism; every expiry requires re-authentication (re-running the handshake) — a worse UX than Approach A and an extra attack surface.

### 2.9 Logout / revocation

- Approach A: `supabase.auth.signOut()` revokes the refresh token server-side; the access token remains valid only until its short `exp`. Linways cookies are discarded on-device (no Linways server revocation — documented, accepted). This matches the architecture's "logout clears both credentials" behavior.
- Approach B: no server-side revocation at all — only client-side discarding; a stolen custom JWT stays valid until `exp`.

---

## 3. Recommendation

**Use native Supabase Auth sessions (Approach A).** The college project login flow becomes:

1. App → auth Edge Function: Linways login handshake (unchanged).
2. Edge Function (service role):
   a. `admin.createUser` (or `updateUserById`) — deterministic synthetic email from `registerNo`, random server-only password, `email_confirm: true`, non-authoritative `user_metadata`.
   b. Insert/upsert `profiles` with `id = auth.users.id`.
   c. Get-or-create `communities` + `community_members` (unchanged).
   d. `admin.generateLink({ type: 'magiclink', email })` → `verifyOtp({ email, token, type: 'email' })` → real `{ access_token, refresh_token }`.
3. Edge Function returns `{ supabase_session, profile, community, linways_session_cookies }` to the app **once**.
4. App stores both in FlutterSecureStorage; initializes `supabase_flutter` with `setSession(access_token, refresh_token)`; RLS + `auth.uid()` work natively; auto-refresh and `signOut()` revocation work out of the box.

This keeps the auth service **stateless** (no server session state), satisfies all locked decisions (no Linways secrets server-side, password in-memory only, one-time handoff), and eliminates the u22 uncertainty: the token presented to PostgREST is a first-class Supabase session, so `auth.uid()` = `profiles.id` by construction.

**Rejected alternatives:**
- Self-minted JWT (project JWT secret HS256): works in principle (community-verified claim sets) but — no refresh, no server-side revocation, official guidance discourages HS256 trust, and 2026 platform drift (ES256/keyset changes) makes it the risky option.
- Third-Party Auth provider: unnecessary complexity; the identity source is Linways, and Supabase Auth is already the platform's native layer.

**Decision needed from owner:** approve Approach A (native Supabase Auth sessions via admin provisioning + magiclink redemption). On approval, update `AUTHENTICATION_ARCHITECTURE.md`'s login flow diagram, then unblock RLS implementation.

---

## 4. Open questions (non-blocking)

| Question | Note |
|---|---|
| Synthetic email policy | Recommend `<registerNo>@college-project.local`; confirm format |
| Custom Access Token Hook mirroring `profiles.role` | Optional later optimization; not required for MVP |
| Token lifetime tuning | Supabase defaults; no change needed for MVP |

*Originally investigation only. Approach A has since been approved and implemented;
see the status header and `docs/decisions/ADR-001-Authentication.md`.*
