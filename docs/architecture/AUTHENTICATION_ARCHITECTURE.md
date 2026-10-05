# Authentication Architecture

> Authentication and authorization architecture for the college project system, including role-based access control.
> **Status: DECISIONS LOCKED. Split-token architecture (server login handshake + client-held Linways session). Awaiting final approval.**
> Full details: `docs/architecture/LINWAYS_INTEGRATION_ARCHITECTURE.md`.

---

## Table of Contents

1. [Authentication Flow](#1-authentication-flow)
2. [User Roles & Permissions](#2-user-roles--permissions)
3. [Session Management](#3-session-management)
4. [Login Implementation](#4-login-implementation)
5. [Security Considerations](#5-security-considerations)
6. [Error Handling](#6-error-handling)

---

## 1. Authentication Flow

college project authenticates students through their **Linways / UUCMS credentials**. The student does **not** create a college project password.

The auth service (Supabase Edge Function) is **stateless** — it performs a one-time login handshake and retains nothing. The Linways session is held **on the device** (the pattern the college's existing PULSE app already uses).

```mermaid
sequenceDiagram
    participant App as Flutter App
    participant AUTH as Auth Service (Edge Function, stateless)
    participant LIN as Linways API
    participant DB as Supabase (service_role)

    App->>AUTH: login(username, password)
    AUTH->>LIN: POST /auth/student-login-credentials
    LIN-->>AUTH: { accessToken, validLogin } + cookies (AUTH_SESSION, refresh_token)
    AUTH->>LIN: GET /student/get-my-profile-details
    LIN-->>AUTH: name, registerNo, programme, batchName, currentSem, email
    AUTH->>AUTH: derive community from batchName + currentSem
    AUTH->>DB: upsert profile; get-or-create community + active membership
    AUTH-->>App: { supabase_session { access_token, refresh_token }, linways_session_cookies, profile, community }
    App->>App: store both in FlutterSecureStorage; server retains nothing
```

**Why not an in-memory Edge Function session:** Supabase Edge Functions are stateless — each request runs in a new V8 isolate, in-memory state is per-isolate only, isolates are evicted on idle, and consecutive requests can hit different instances/regions. An in-memory session map would lose sessions arbitrarily (investigation: `LINWAYS_INTEGRATION_ARCHITECTURE.md` §A.2).

## 2. User Roles & Permissions

- **`student`** — the only self-registering role; created from a successful Linways login.
- **`hod` / `technician` / `operations` / `admin`** — staff roles. Staff login is
  **implemented** (`supabase/functions/linways-login/index.ts:563-608`): a Supabase
  email+password check that returns a normal session. Locked decision 5 has since been
  superseded — see `docs/decisions/ADR-001-Authentication.md` §2.6. The accounts are
  seeded by `supabase/migrations/20261005120000_seed_staff_demo_accounts.sql`, which
  **has not been applied yet**, so staff login does not currently work.

## 3. Session Management

Two independent credentials:

| Credential | Where held | Used for | Lifetime |
|---|---|---|---|
| **Linways session** (`AUTH_SESSION`, `refresh_token`) | Device — FlutterSecureStorage (encrypted) | Direct Linways calls (attendance dashboard) | Controlled by Linways; 401 → re-login |
| **Supabase session** (`access_token`, `refresh_token`) | Device — FlutterSecureStorage via the SDK's `LocalStorage` hook | college project APIs (Supabase, RLS) | Access token ~1 h, auto-refreshed from the long-lived refresh token |

- **The Supabase token is a real GoTrue session, not a self-signed JWT.** It is minted
  by `generateLink` + `verifyOtp` (`index.ts:490-513`) so that `auth.uid()` resolves
  natively. See `ADR-001-Authentication.md` §2.2.
- **Server side:** nothing persisted; the auth service is stateless.
- Logout clears both credentials from the device. There is no server-side Linways revocation (Linways expiry applies).

## 4. Login Implementation

- Endpoint (proposal): `POST /auth/linways/login` on a Supabase Edge Function.
- Request: `{ username, password }` — password used in-memory only, never stored or logged.
- Confirmed Linways request shape: `{ username, password, next: "", userType: "STUDENT" }` → `POST https://sfcv4.linways.com/academics/api/v1/auth/student-login-credentials`.
- On success the service fetches the profile, derives the community (server-side only), persists profile/membership, and hands the Linways cookies back to the app exactly once.

## 5. Security Considerations

- Password: in-memory only, discarded after login.
- Linways session secrets: device-only (encrypted storage); never in DB, files, logs, or commits (locked decision 10).
- App stores the college project JWT alongside; both in FlutterSecureStorage.
- All traffic over TLS; no credential logging.
- Rate limiting on login; community derivation never trusts client input.
- RLS (later phase) enforces community isolation (`reports.community_id` vs active membership).
- Accepted risk: device compromise exposes the Linways session — identical to the existing PULSE app.

## 6. Error Handling

| Failure | Behavior |
|---|---|
| Invalid Linways credentials | Login rejected; no session created |
| Linways unavailable/timeout | Login fails; retryable; no partial state |
| Linways session expired (401) | App drops Linways session; re-login prompt |
| Profile fetch fails after auth | Abort login (no profile → no community → no join) |
| Community parsing fails | Login succeeds but student is `community_pending`; admin assigns (never client-chosen) |
