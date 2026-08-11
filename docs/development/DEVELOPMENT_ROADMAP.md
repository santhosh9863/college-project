# Development Roadmap

> Phased development plan for the college project system from foundation through launch.
> **Status: DECISIONS LOCKED — revised after the Linways investigation (communities + Linways integration). Awaiting final approval.**
> Supabase project `college_project` is linked; database foundation migrations exist but are **not applied** until the revised schema is approved.

---

## Table of Contents

1. [Revised Phase Plan](#1-revised-phase-plan)
2. [Phase 1: Database Schema v2](#2-phase-1-database-schema-v2)
3. [Phase 2: Linways Authentication Integration](#3-phase-2-linways-authentication-integration)
4. [Phase 3: Community Provisioning & Mapping](#4-phase-3-community-provisioning--mapping)
5. [Phase 4: RLS Policies](#5-phase-4-rls-policies)
6. [Phase 5: Seed Data](#6-phase-5-seed-data)
7. [Phase 6: Flutter Auth & Onboarding](#7-phase-6-flutter-auth--onboarding)
8. [Phase 7: Report CRUD](#8-phase-7-report-crud)
9. [Phase 8: Realtime](#9-phase-8-realtime)
10. [Phase 9: AI Integration](#10-phase-9-ai-integration)
11. [Phase 10: Notifications](#11-phase-10-notifications)
12. [Phase 11: Attendance Dashboard](#12-phase-11-attendance-dashboard)
13. [Phase 12: UI Polish & Launch](#13-phase-12-ui-polish--launch)
14. [Milestones](#14-milestones)
15. [Dependencies](#15-dependencies)

---

## 1. Revised Phase Plan

The approved development order (schema → auth → RLS → seed → Flutter auth → report CRUD → realtime → AI → notifications → polish) is retained, with new phases inserted for the Linways/community findings:

| # | Phase | Note |
|---|-------|------|
| 1 | Database schema v2 | communities + community_members + reports.community_id — **before first apply** |
| 2 | Linways authentication integration | **Stateless** auth Edge Function: login handshake, session handoff, college project JWT |
| 3 | Community provisioning & mapping | derivation rules + auto-provision + `community_pending` fallback |
| 4 | RLS policies | incl. community isolation |
| 5 | Seed data | |
| 6 | Flutter auth & onboarding | login → profile → community → dashboard |
| 7 | Report CRUD | community-scoped |
| 8 | Realtime | |
| 9 | AI Edge Functions | |
| 10 | Notifications | |
| 11 | Attendance dashboard | overall % via direct Linways call (device-held session) |
| 12 | UI polish & launch | |

## 2. Phase 1: Database Schema v2

- Add `communities`, `community_members`; add `reports.community_id` (NOT NULL); extend indexes.
- Revise migrations in place (nothing applied yet) per `DATABASE_DESIGN.md` §9.
- Gate: schema approved → first cloud apply.

## 3. Phase 2: Linways Authentication Integration

- **Stateless** auth Edge Function: `POST /auth/linways/login` → Linways `student-login-credentials` → profile proxy → community derivation → profile/membership upsert → returns college project JWT + Linways cookies to the app (handoff). Server retains nothing.
- **No in-memory session** — Edge Functions are stateless (investigation: `LINWAYS_INTEGRATION_ARCHITECTURE.md` §A.2).
- Confirmed Linways endpoints only. No token/credential persistence. See `LINWAYS_INTEGRATION_ARCHITECTURE.md` §A.

## 4. Phase 3: Community Provisioning & Mapping

- Server-side derivation from `batchName` + `currentSem` (course, batch_year, semester, section).
- Idempotent get-or-create; `community_pending` fallback for unparseable classes (never client-chosen).

## 5. Phase 4: RLS Policies

- Community isolation: student sees reports where `reports.community_id` = active community.
- Staff access via role + routing (staff provisioning deferred — OUT OF MVP). Details deferred to the RLS phase.

## 6. Phase 5: Seed Data

- As approved in the seed phase (unchanged scope).

## 7. Phase 6: Flutter Auth & Onboarding

- Login screen → auth service handshake → store college project JWT + Linways session in FlutterSecureStorage → community join → dashboard.

## 8. Phase 7: Report CRUD

- Create/list/view reports scoped to the student's community (snapshot `community_id`).

## 9. Phase 8: Realtime

- Live updates for community reports/comments/activity.

## 10. Phase 9: AI Integration

- Classification, priority prediction, duplicate detection (uses `ai_classification_log`).

## 11. Phase 10: Notifications

- In-app notifications (`notifications` table).

## 12. Phase 11: Attendance Dashboard

- Overall attendance % via `get-my-attendance-summary` called directly from the app with the device-held Linways session; in-memory cache ~10–30 min. No attendance tables.

## 13. Phase 12: UI Polish & Launch

- Final styling, testing, deployment.

## 14. Milestones

- M1: Schema v2 approved and applied (first cloud apply).
- M2: Linways login works end-to-end with community join.
- M3: Community report CRUD live.
- M4: MVP launch (auth + dashboard + reports).

## 15. Dependencies

- Linways integration depends on: approved architecture, Supabase access, confirmed endpoints (done).
- AI phase depends on: real report data.
- Notifications depend on: Realtime.
