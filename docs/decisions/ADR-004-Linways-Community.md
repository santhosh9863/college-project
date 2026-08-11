# ADR-004: Linways Integration & Community Model

> Decision record for integrating college project with Linways authentication and the academic community model.
> **Status: DECISIONS LOCKED (items 1–10 approved conceptually). Awaiting final approval of the documented schema + authentication architecture. No implementation.**

---

## Table of Contents

1. [Context](#1-context)
2. [Decision](#2-decision)
3. [Consequences](#3-consequences)
4. [Alternatives Considered](#4-alternatives-considered)
5. [Investigation: Edge Function Session Continuity](#5-investigation-edge-function-session-continuity)
6. [Open Questions](#6-open-questions)
7. [References](#7-references)

---

## 1. Context

The Linways investigation confirmed the student login endpoint, the profile endpoint (`get-my-profile-details`), and the overall attendance endpoint (`get-my-attendance-summary`). college project is a **college community platform**: students authenticate with Linways/UUCMS credentials, their academic class (course, batch, semester, section) is derived from Linways data, and reports are scoped to that community. The approved v1.0 database schema (checkpoint `e11b88a`, migrations not yet applied) does not model communities; it must be revised before the first cloud apply.

## 2. Decision

Locked decisions (approved conceptually):

1. **Community lifetime:** a separate community per semester + section + batch. `BCA 2024 S5 C` ≠ `BCA 2024 S6 C`. Modeled by `communities` keyed `UNIQUE(course_code, batch_year, semester, section)`.
2. **`reports.community_id`:** NOT NULL, snapshot of the reporter's community at report creation.
3. **`community_members`:** history preserved with `is_active`, `joined_at`, `left_at`; `UNIQUE(community_id, profile_id)`.
4. **Attendance:** dashboard-only for MVP; `get-my-attendance-summary`, display `attendancePercentage` only; no subject-wise attendance; no attendance tables.
5. **Staff (HOD/technician/operations/admin):** provisioning OUT OF MVP; role architecture retained untouched.
6. **Profile:** no `rollNo`/`phone`/`image`; existing approved fields only (`full_name`, `email`, `student_id`, role, semester/section/student fields).
7. **`community_pending`:** fallback kept — the client never chooses its own class; admin handles unmappable cases.
8. **`course_code`:** independent from `departments` for MVP; no new FK.
9. **Authentication:** Edge Function **in-memory** session rejected. Recommended: **split-token — stateless server login handshake + client-held Linways session** (see §5 and `LINWAYS_INTEGRATION_ARCHITECTURE.md` §A).
10. **Linways secrets:** never store the password; never commit or store `AUTH_SESSION`, `accessToken`, `refreshToken`; never expose in logs or documentation.

## 3. Consequences

- The v1.0 migrations for `reports` and `indexes` must change; two new migration files (`communities`, `community_members`) are added; nothing is applied until approval.
- Community isolation prevents cross-class visibility by design (RLS later).
- The auth service is stateless — no session continuity or affinity requirements; scales horizontally.
- The Linways session lives on the device (encrypted); device compromise exposes it (same exposure as the existing PULSE app).

## 4. Alternatives Considered

- **Client-only Linways session (legacy PULSE style):** the *session* half of the adopted design; the login handshake keeps credential validation and community derivation server-side.
- **Edge Function in-memory session:** rejected — stateless platform (§5).
- **Server-side persistent session storage (DB/KV/S3):** rejected for MVP — stores Linways secrets server-side, violating decision 10; revisit only if central control becomes a hard requirement.
- **Community as enum or plain column:** rejected — open-ended class set, no integrity, no history.
- **Denormalized `profiles.community_id`:** deferred — membership table is the single source of truth for MVP.

## 5. Investigation: Edge Function Session Continuity

**Question (decision 9):** do Supabase Edge Functions provide reliable session continuity across requests/instances?

**Finding: No — Edge Functions are stateless by design.**
- Official docs: *"No persistent state; each run is stateless, ideal for ephemeral tasks."* Each request runs in a new V8 isolate with its own memory heap.
- In-memory state is per-isolate only; isolates are evicted after idle periods; the edge proxy routes each request independently — consecutive requests from one user can hit different isolates, regions, or instances (globally distributed).
- Warm-start worker reuse is best-effort only; production deployments frequently boot fresh workers even at low sequential concurrency; in-memory caches inside workers are documented as unreliable optimizations.
- Persistent storage added in 2025 is S3-backed file storage (sessions there would still violate decision 10).

**Comparison:**

| Option | Reliability | Security | Complexity | Verdict |
|---|---|---|---|---|
| Edge Function in-memory session | None (per-isolate, eviction, multi-instance) | Medium | Low | Rejected |
| Server-side persistent session store | High | Stores Linways secrets server-side — violates decision 10 | Medium | Rejected for MVP (revisit if central control needed) |
| **Split-token: stateless login handshake + client-held Linways session** | **High** | **Medium (device-encrypted; legacy precedent)** | **Lowest** | **Recommended** |
| Hybrid (server proxy + client-held) | High | Same as above + extra hop | Medium | Rejected — no benefit |

**Recommendation: split-token.** The auth service is a stateless Edge Function that performs a one-time login handshake (Linways login → profile → community derivation → profile/membership upsert → college project JWT + Linways cookie handoff) and retains nothing. The app holds the Linways session in FlutterSecureStorage for direct attendance calls (the college's existing PULSE app already runs this pattern in production) and the college project JWT for Supabase APIs.

## 6. Open Questions

1. **Staff provisioning timing** — deferred by decision 5; mechanism decided in a future phase.
2. **`refresh_token` behavior in the Flutter app** — device-side implementation detail for the Flutter phase.
3. **Observed Linways session TTL on-device** — confirm during the Flutter phase; 401 → re-login fallback.

## 7. References

- `docs/architecture/LINWAYS_INTEGRATION_ARCHITECTURE.md` (full proposal)
- `docs/architecture/DATABASE_DESIGN.md` §9 (proposed schema v2)
- `docs/architecture/AUTHENTICATION_ARCHITECTURE.md`
- `docs/architecture/SYSTEM_ARCHITECTURE.md`
- `docs/development/DEVELOPMENT_ROADMAP.md`
- `docs/references/PULSE_AUTHENTICATION_ARCHITECTURE.md` (legacy reference only)
