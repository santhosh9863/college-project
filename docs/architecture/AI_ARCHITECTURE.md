# AI Architecture

> AI module architecture for complaint classification, priority prediction, and
> duplicate detection.

**Status: PROPOSED — nothing implemented.** No AI code exists in this repository
as of 2026-10-04. The database and RLS contracts are in place; there is no
writer, no model, and no dataset.

> **Provenance note (read before citing).**
> Sections marked **[D]** are existing, approved project decisions already
> recorded in `MASTER_ARCHITECTURE.md`, `RLS_POLICIES.md`, `DATABASE_DESIGN.md`
> and the applied migrations. Sections marked **[N]** are **new proposals made
> in this document** — they are *not* prior project decisions.
>
> An earlier draft of this plan attributed TF-IDF, cosine similarity and
> logistic regression to "the project documentation". That was incorrect: those
> terms appear nowhere in `docs/`. No ML method has ever been prescribed by this
> project. They are recorded below as **[N]** proposals requiring sign-off, and
> belong in `docs/decisions/ADR-003-AI.md` (currently an empty skeleton) once
> accepted.

---

## Table of Contents

1. [Position and constraints](#1-position-and-constraints)
2. [What is already built](#2-what-is-already-built)
3. [Complaint Classification](#3-complaint-classification)
4. [Priority Prediction](#4-priority-prediction)
5. [Duplicate Detection](#5-duplicate-detection)
6. [Model Training & Data](#6-model-training--data)
7. [Edge Function Implementation](#7-edge-function-implementation)
8. [Failure Behaviour](#8-failure-behaviour)
9. [Delivery Phases](#9-delivery-phases)
10. [Performance Considerations](#10-performance-considerations)

---

## 1. Position and constraints

**[D]** The AI layer is **assistive only**. It never replaces the authority
workflow, never rejects a complaint, and never overwrites student-submitted
data.

> "AI classification/priority/duplicate detection (assistive only)"
> — `MASTER_ARCHITECTURE.md:87`
>
> "AI never replaces the authority workflow or overrides the student's data."
> — `MASTER_ARCHITECTURE.md:211`
>
> "AI assists classification/priority/duplicate detection; it does not replace
> the authority workflow or override student data."
> — `MASTER_ARCHITECTURE.md:293`

**[D]** AI runs **after** report creation and is logged **append-only** in
`ai_classification_log`, readable by **admin only** (u18), written only by the
AI Edge Function via `service_role`.

**[D]** Priority integrity (u4): the student chooses `priority`; the AI records
a *prediction* and **must not silently overwrite** the student's value.

**[D]** A student's `report_type` is **community only** (u3). The `private`
enum value is currently unreachable — students and admins are both constrained
to `community` by `can_create_report()`. Visibility is therefore **not** a
student-facing field, and must not appear as one in any UI or flow diagram.

Operational constraints that materially affect this design:

- **Free-tier project auto-pauses after ~7 days of inactivity.** Confirmed
  live on 2026-10-03: the project returned `540 project paused` and all login
  failed until it was restored. Any AI phase that sits idle for a week will
  break the same way.
- **The Supabase CLI is not installed** on the development machine. Nothing in
  this plan can be deployed until it is.
- Edge Functions run on Deno. scikit-learn / pandas are **not** available
  server-side. Any model must be exported to plain JSON and evaluated in
  TypeScript, or inference must move to Postgres.

---

## 2. What is already built

The persistence and authorisation layer is **complete**. Only the intelligence
is missing.

| Asset | Location | State |
|---|---|---|
| `reports.ai_confidence float` | `20260811102400_reports.sql:25` | column exists, never written |
| `reports.duplicate_of uuid` → self-FK | `20260811102400_reports.sql:24` | column exists, never written |
| `ai_classification_log` (jsonb contract) | `20260811103000_ai_classification_log.sql` | table exists, no writer |
| "AI runs after creation" enforced | `20260811103300_rls_security.sql:127` — `can_create_report()` requires `p_ai_confidence is null and p_duplicate_of is null` | enforced |
| Log is server-write-only | `20260811103300_rls_security.sql:481` — `revoke insert, update, delete … from authenticated` | enforced |
| Admin-only read, append-only | `20260811103300_rls_security.sql:669-671` | enforced |
| `reports(duplicate_of)` index | `20260811103200_indexes.sql:21` | exists |
| `ai_classification_log(report_id)` index | `20260811103200_indexes.sql:48` | exists |
| `priority` enum incl. `critical` | `20260815100000_priority_critical.sql` | exists |
| 14 seeded categories | `20260815101000_seed_categories_departments.sql` | exists |

Consequence: `can_create_report()` **actively forbids** a student from setting
`ai_confidence` or `duplicate_of` at insert time. Any implementation that tries
to classify *before* insertion will be rejected by the database. This is a
deliberate invariant, not an obstacle to work around.

---

## 3. Complaint Classification

**[N] Proposed.** Predict the most appropriate category from title +
description.

Input: `title`, `description`
Output: `{ "category": "<category name>", "confidence": 0.0, "reasoning": "..." }`

The `classification` jsonb shape is **[D]** — fixed by the applied migration
comment at `20260811103000_ai_classification_log.sql:3`:

```
classification:    { "category": "...", "confidence": 0.0, "reasoning": "..." }
```

Labels **[D]**: the 14 categories seeded by
`20260815101000_seed_categories_departments.sql` — Academic, Infrastructure,
IT & Network, Facilities, Harassment & Discrimination, Ragging & Bullying,
Mental Health & Counselling, Safety & Security, Human Rights, Anti-Drug /
Substance Abuse, Sexual Harassment, Grievance, Emergency / Fire Safety, Other.

`Other` must remain a real predicted class, not a fallback for errors.

**[D]** Routing is unchanged by any prediction: category → `category_routes` →
authority. The AI never routes anything itself.

---

## 4. Priority Prediction

**[N] Proposed.** Estimate a priority across the **[D]** enum
`low | medium | high | critical`.

Output shape **[D]** (`20260811103000_ai_classification_log.sql:4`):

```
priority_prediction: { "priority": "...", "confidence": 0.0 }
```

Signals **[N]**: report text, predicted category, urgency phrasing, and a
rule-based baseline (electrical sparks, fire, gas, medical → `critical`).

**[D] Constraint:** the prediction is advisory. `reports.priority` remains the
student's value. A separate AI-read surface is required for staff to see the
prediction; there is no column for it on `reports`.

**Build this last.** For a dataset of this size a transparent rule baseline may
outperform a trained model. Reporting that outcome honestly is a stronger result
than assuming ML wins.

---

## 5. Duplicate Detection

Output shape **[D]** (`20260811103000_ai_classification_log.sql:5`):

```
duplicate_check: { "is_duplicate": false, "similar_report_id": null, "similarity_score": 0.0 }
```

`reports.duplicate_of` **[D]** is a nullable self-reference — the schema
anticipates *linking* a duplicate to a canonical report, distinct from merely
*flagging* it.

**[N] Recommended implementation: Postgres text search, not ML.**

Start with `pg_trgm` (`similarity()` / `%`) or `tsvector` + `ts_rank`, scoped to
the reporter's own community. Rationale:

- It runs **inside the database**, which is the only component with reliable
  access to report text under the project's RLS model. An Edge Function would
  need `service_role` to read reports broadly, widening the blast radius of a
  bug for no benefit.
- No model artifact, no training, no Python toolchain, no Edge Function cold
  start, no extra inference service to operate.
- It is deterministic and explainable, which suits an assistive feature that a
  human must be able to overrule.

TF-IDF + cosine similarity remains a reasonable **later** comparison, and would
make a defensible "we tried the learned approach and Postgres n-grams matched
it" entry in the report — provided it is measured, not assumed.

Threshold **[N]**: start at `similarity >= 0.85`, then tune against a
hand-labelled set. Measure false positives explicitly; over-flagging destroys
trust in the feature faster than under-flagging.

**Never reject.** Flag for human review only.

---

## 6. Model Training & Data

**[N] Proposed.**

```
ai/
├── dataset/        category_dataset.csv, priority_dataset.csv, duplicate_pairs.csv
├── preprocessing/  shared text-normalisation, used by every feature
├── training/       offline Python; not shipped to production
├── evaluation/     metrics + confusion matrix
├── models/         exported JSON artifacts (versioned)
└── inference/      TypeScript, consumed by the Edge Function
```

Dataset schema — category:

```
title, description, category
```

Dataset schema — priority:

```
title, description, category, priority
```

Dataset schema — duplicate pairs:

```
report_a_text, report_b_text, is_duplicate
```

**One shared preprocessing pipeline** for every feature: normalise →
lowercase → strip punctuation/numbers noise → collapse whitespace → tokenise.

**[N] Classifier:** TF-IDF → multinomial logistic regression, trained offline,
coefficients exported to JSON. Inference in TypeScript is then a sparse
dot-product — no sklearn at runtime.

**[N] Dataset honesty.** Synthetic/seeded data must be labelled as synthetic.
Accuracy figures must come from an actual train/validation/test run. A confusion
matrix is expected to expose confusable pairs (Infrastructure ↔ Facilities,
Safety & Security ↔ Emergency / Fire Safety, Academic ↔ Grievance); those are
the highest-value labelling fixes.

**[D] Privacy.** Training on real student report text is constrained by the
project's privacy and RLS posture. Dataset V1 must be synthetic or
consented. Anonymised harvesting is a V2 question, not a V1 assumption.

---

## 7. Edge Function Implementation

**[D]** Target: a new Edge Function alongside `linways-login`, running on Deno
via `service_role`, writing only to `ai_classification_log`.

```
POST /functions/v1/ai-classify      (service_role only)
{ "report_id": "<uuid>" }
```

Flow: load report → preprocess → classify → predict priority → duplicate check
→ insert one `ai_classification_log` row → return summary. Never called by the
client with student-supplied text; always keyed on `report_id` so the text is
read under server authority.

Model loading **[N]**: embed the JSON artifact in the function bundle, or fetch
it once per cold start. Bundling is simpler and has no network dependency.

**Deployment status: not started.** The CLI is not installed.

---

## 8. Failure Behaviour

**[N]** AI must never be able to fail a student's submission.

```
Report created  ──▶  AI invoked (async)
                        │
                        ├── ok ──▶ one ai_classification_log row
                        └── fail ──▶ log it; report unaffected; retry later
```

- The client must not block report creation on AI completion.
- A failed AI run is recorded as an attempt; the report remains fully usable.
- `reports.ai_confidence` stays `NULL` on failure — which is exactly what
  `can_create_report()` expects, so a failed run leaves no invalid state.

---

## 9. Delivery Phases

**[N] Proposed order.** Each phase is independently demonstrable.

| Phase | Deliverable | Gate |
|---|---|---|
| AI-0 | Populate `docs/decisions/ADR-003-AI.md`; settle duplicate-detection method | ADR accepted |
| AI-1 | `pg_trgm` duplicate detection writing `duplicate_of` + log | real duplicate correctly flagged |
| AI-2 | AI Edge Function skeleton: auth, validation, error handling, log write | bad input cannot write a log row |
| AI-3 | Synthetic category dataset + preprocessing pipeline | labels validated |
| AI-4 | TF-IDF + logistic regression, exported JSON | metrics measured, not guessed |
| AI-5 | Classification wired into the function; staff read surface | admin-only read verified |
| AI-6 | Priority prediction + rule baseline comparison | both measured |
| AI-7 | Failure/retry behaviour tests | AI outage cannot block submission |
| AI-8 | Evaluation + documentation | report contains real numbers |

**Start at AI-1.** It needs no model, no dataset and no training, and it
exercises the entire database contract that already exists.

**Prerequisite for everything:** install the Supabase CLI, and re-check the
project is unpaused before each session.

---

## 10. Performance Considerations

**[N]**

- Postgres similarity over a community-scoped candidate set is fast enough;
  index on `(community_id, deleted_at)` and pre-filter before scoring.
- Classification is a single sparse dot-product — negligible.
- AI runs post-creation and off the student's critical path.
- `ai_classification_log` is append-only and will grow without bound; plan
  retention before it becomes a production concern.