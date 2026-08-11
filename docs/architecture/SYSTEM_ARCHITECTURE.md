# System Architecture

> High-level system architecture for the AI-Powered Smart Campus Issue Reporting and Resolution System.
> **Status: DECISIONS LOCKED (Linways + community). Awaiting final approval.**

---

## Table of Contents

1. [System Overview](#1-system-overview)
2. [Architecture Principles](#2-architecture-principles)
3. [Technology Stack](#3-technology-stack)
4. [High-Level Architecture Diagram](#4-high-level-architecture-diagram)
5. [Component Architecture](#5-component-architecture)
6. [Data Flow](#6-data-flow)
7. [Security Architecture](#7-security-architecture)
8. [Scalability Considerations](#8-scalability-considerations)
9. [Deployment Architecture](#9-deployment-architecture)

---

## 1. System Overview

college project is a **college community platform**. Students authenticate with their Linways/UUCMS credentials; the system fetches their Linways profile, derives their **academic community** (course, batch, semester, section), and joins them to it. The app shows the student's **overall attendance percentage** and community-scoped **issue reports**.

```
Linways → student authentication → fetch profile → determine academic community
        → student joins community → college project dashboard
        → overall attendance + community reports
```

## 2. Architecture Principles

- Students authenticate with Linways credentials; college project never persists passwords or Linways session secrets (device-held only).
- Edge Functions are treated as **stateless** — no in-memory session architecture (investigation: `LINWAYS_INTEGRATION_ARCHITECTURE.md` §A.2).
- The community is derived from reliable Linways academic data, never chosen by the student (`community_pending` fallback).
- Reports are community-scoped (`reports.community_id` NOT NULL snapshot).
- Attendance is a dashboard feature (overall percentage only); no attendance tables.
- Staff provisioning is out of MVP; the role architecture is retained.
- The existing report architecture (categories, routing, assignments, activity, notifications, AI) is preserved.

## 3. Technology Stack

| Layer | Choice |
|---|---|
| Client | Flutter (existing `flutter_app/` scaffolding, empty) |
| Backend | Supabase (Postgres 17, Auth, Realtime, Storage) |
| Server logic | Supabase Edge Functions (stateless login handshake, AI classification) |
| Identity source | Linways (`sfcv4.linways.com`) — confirmed endpoints only |
| Credential storage | FlutterSecureStorage (college project JWT + Linways session cookies) |

## 4. High-Level Architecture Diagram

```mermaid
graph TD
    APP[Flutter App] -->|college project JWT| DB[(Supabase Postgres)]
    APP -->|Linways session (device-held)| LIN[Linways API]
    APP -->|login handshake| AUTH[Auth Service / Edge Function]
    AUTH -->|Linways login + profile (one request)| LIN
    AUTH -->|service_role| DB
    DB -->|Realtime| APP
    AI[AI Edge Functions] --> DB
    subgraph Linways confirmed endpoints
        L1[POST /auth/student-login-credentials]
        L2[GET /student/get-my-profile-details]
        L3[GET /student/get-my-attendance-summary]
    end
    LIN --> L1
    LIN --> L2
    LIN --> L3
```

## 5. Component Architecture

| Component | Responsibility |
|---|---|
| Auth Service (Edge Function, **stateless**) | One-time login handshake: Linways login + profile fetch, community derivation, profile/membership upsert, college project JWT issuance, Linways cookie handoff |
| Profiles / Communities (DB) | `profiles`, `communities`, `community_members` (v2 proposal) |
| Reports (DB) | community-scoped reports, assignments, supports, comments, activity, evidence |
| AI Edge Functions (future phase) | classification, priority prediction, duplicate detection |
| Notifications (future phase) | in-app notifications via Realtime |
| Flutter app | login/onboarding, dashboard (attendance + community reports), report CRUD; holds Linways session for direct attendance calls |

## 6. Data Flow

1. **Login:** App → Auth Service (handshake) → Linways → profile → community → app receives college project JWT + Linways cookies (stored in FlutterSecureStorage; server retains nothing).
2. **Dashboard:** App → Linways directly (device-held session) → `get-my-attendance-summary` → percentage displayed (in-memory cache ~10–30 min).
3. **Reports:** App ↔ Supabase with college project JWT (RLS-scoped to the caller's community).

## 7. Security Architecture

- Secrets (password, Linways tokens/cookies): password is in-memory only; Linways session lives only in the device's encrypted storage — never in DB, files, logs, or commits.
- App: college project JWT in FlutterSecureStorage.
- Community isolation enforced by RLS (later phase).
- TLS everywhere; rate-limited login; server-side community derivation; no credential logging.

## 8. Scalability Considerations

- No server session state ⇒ auth service scales horizontally with zero session affinity requirements.
- Community isolation makes report reads naturally partitionable by community.
- `communities` unique key enables idempotent provisioning under concurrency.
- Device-held Linways sessions shift attendance load to the client → Linways, avoiding a server bottleneck.

## 9. Deployment Architecture

- Supabase project `college_project` (linked, migrations **not yet applied**).
- Edge Functions deployed via Supabase CLI (`npx supabase`).
- Flutter app on student devices (Android/iOS).
