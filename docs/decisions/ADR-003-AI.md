# ADR-003: AI Module Architecture

> Decision record for the AI classification, priority prediction, and duplicate detection approach.
> **Status: ACCEPTED — Part 1 (duplicate detection).** Classification and priority prediction remain **proposed, not built**.
> **Scope of this record: settling the duplicate-detection method (AI-0).** It does not authorise the classification or priority phases.

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

`MASTER_ARCHITECTURE.md` commits the project to AI-assisted classification,
priority prediction, and duplicate detection. The **persistence and
authorisation layer for all three is already built and enforced**:

| Asset | Location |
|---|---|
| `reports.ai_confidence float`, `reports.duplicate_of uuid` | `20260811102400_reports.sql:24-25` |
| `ai_classification_log` with fixed jsonb shapes | `20260811103000_ai_classification_log.sql` |
| `can_create_report()` requires `ai_confidence IS NULL` **and** `duplicate_of IS NULL` for students | `20260811103300_rls_security.sql:101-127` |
| Log is server-write-only, admin-only read | `20260811103300_rls_security.sql:481`, `:669-671` |
| `duplicate_of` and `report_id` indexes | `20260811103200_indexes.sql:21`, `:48` |

**Zero intelligence exists.** No AI Edge Function (`supabase/functions/` contains
only `linways-login`), no `ai/` directory, no dataset, no training code.

Two facts make the obvious implementation path unavailable:

- **`can_create_report()` forbids classifying before insert.** A student cannot
  set `duplicate_of` or `ai_confidence` at creation time — the database rejects
  it. Any design that classifies first must change an enforced invariant.
  Detection must therefore run *after* the row exists.
- **Edge Functions run on Deno.** scikit-learn and pandas are unavailable
  server-side. A learned model must be exported to JSON and evaluated in
  TypeScript, or inference must move into Postgres.

This record settles **which method** duplicate detection uses, because that
choice determines whether AI-1 needs a model, a dataset, and an inference
service — or nothing but a migration.

### 1.1 A note on what was previously claimed

An earlier draft plan asserted that **TF-IDF, cosine similarity, and logistic
regression were "explicitly proposed by the project documentation."** They were
not. Those terms appear nowhere in `docs/`. They are recorded below as **[N]**
(new proposal), never as prior decisions. This correction is preserved because
the misattribution is what made the ML path look mandatory.

---

## 2. Decision

### 2.1 Duplicate detection uses Postgres `pg_trgm`, not machine learning

**Accepted.** Similarity is computed by `pg_trgm` inside the database, via an
`AFTER INSERT` trigger on `public.reports`. No model, no dataset, no Edge
Function, no training pipeline.

### 2.2 Detection runs after creation, never before

**[D] invariant, honoured.** The trigger fires `AFTER INSERT`. Nothing is
classified or linked at insert time, so `can_create_report()`'s
`p_ai_confidence is null and p_duplicate_of is null` requirement is satisfied by
construction and no invariant is relaxed.

### 2.3 Comparison is scoped to the reporter's own community

**[N]** Candidate matching requires `candidate.community_id =
new.community_id`. A student's report text is never compared against another
community's. This is the narrowest scope that still finds the real problem —
the same fault reported by many students in one community — and it keeps
detection inside the visibility boundary the project already enforces.

Additional candidate filters: `deleted_at IS NULL`, `created_at <= new.created_at`
(never match forward), and `duplicate_of IS NULL` (see §2.6).

### 2.4 Candidates are pre-filtered by category, then scored on text

**[N]** Trigram similarity is computed on the concatenated `title || ' ' ||
description`. Because a GIN trigram index is used, the candidate set is narrowed
to the same `category_id` first, then scored. Two effects: the index is actually
used (a bare `similarity()` scan over all reports would not), and the score
reflects genuine text overlap rather than a shared word like "urgent".

### 2.5 Threshold starts at 0.85 and is a parameter, not a global

**[N]** `similarity(a, b) >= 0.85` initially. The threshold is an explicit
function argument rather than `pg_trgm.similarity_threshold`, because that GUC is
global and would silently change any other trigram use in the database.

**False positives are the real risk.** Over-flagging destroys trust in an
assistive feature far faster than under-flagging. The threshold is expected to be
tuned against a hand-labelled pair set before the report quotes any accuracy
figure.

### 2.6 `duplicate_of` always points at a canonical root

**[N]** Candidates that are themselves duplicates are excluded, and ties break
on `(created_at, id)`. Therefore `duplicate_of` can never point at another
duplicate, and chains like `C → B → A` cannot form.

This is why the schema's nullable self-reference is usable as-is: every row
either is canonical or points directly at a canonical report.

### 2.7 Detection can never fail a submission

**[D]** The trigger body catches all exceptions and returns `NEW`. A broken
trigram extension, a full disk, or a bug leaves `duplicate_of IS NULL` and the
report fully usable — which is precisely the state `can_create_report()` expects,
so a failed run leaves no invalid state and nothing needs repair.

**No report is ever rejected, merged, hidden, or closed by detection.** Flagging
is advisory; a human decides.

### 2.8 Classification and priority prediction are NOT authorised here

**[N]** Both remain proposals in `AI_ARCHITECTURE.md` §3 and §4. They require a
dataset whose provenance is honest (synthetic or consented — real student report
text is constrained by the project's privacy posture) and, for priority, a
demonstrated win over a transparent rule baseline. **A rule-based baseline
outperforming a trained model is an acceptable and reportable outcome.**

Per `AI_ARCHITECTURE.md` §4, build priority prediction **last**.

---

## 3. Consequences

- The largest body of AI value ships as **one migration**. No new service to
  deploy, monitor, or keep warm, and no failure mode that can affect students.
- `pg_trgm` is added as a database extension.
- The full database contract for AI is now exercised end-to-end:
  `duplicate_of` written, `ai_classification_log` appended, append-only and
  admin-only enforced.
- **Detected duplicates still surface nowhere useful.** Detection writes
  `duplicate_of`, but the staff read surface that would show "similar to
  report X" does not exist yet. Until it does, this decision is correct but
  largely invisible — see §5.1.
- `ai_classification_log` grows on every report insert and is append-only with
  no retention policy. Harmless at college-project volume; must be addressed
  before any production concern.
- `AI_ARCHITECTURE.md` §9's phase AI-0 is satisfied by this record; AI-1 is
  implemented by `20261005123000_ai1_duplicate_detection.sql`.
- **Deploying anything still requires the Supabase CLI**, which is not
  installed. Migrations are currently applied by hand in the dashboard.

---

## 4. Alternatives Considered

| Option | Verdict |
|---|---|
| **`pg_trgm` similarity in Postgres, `AFTER INSERT` trigger** | **Selected** — no model/dataset/service; runs where RLS already governs report text; deterministic and explainable, which suits a feature a human must overrule |
| TF-IDF + cosine similarity, compared against `pg_trgm` as a baseline | Deferred — defensible later as "we measured the learned approach", but only **if measured**. Not now; would require the dataset and Python toolchain for no proven gain |
| Embeddings (sentence-transformers) | Rejected for now — needs a hosted model, an inference service, and network access to a third party. Disproportionate for detecting near-identical short texts, which trigrams handle well |
| Classify inside the client before insert | **Rejected — blocked by an enforced invariant.** `can_create_report()` rejects a non-null `duplicate_of`/`ai_confidence` at insert |
| Edge Function doing duplicate detection | Deferred to AI-2 — viable for the learned features later. Requires `service_role` to read reports broadly, widening the blast radius of a bug for no benefit at this stage |
| `tsvector` + `ts_rank` instead of trigrams | Rejected — good for keyword retrieval, weaker on short near-duplicate text and typos, where trigram similarity is the better fit |
| A trained duplicate classifier | Rejected — the hard problem is a labelled pair set, not a model. With no dataset, a classifier cannot be honestly evaluated |

---

## 5. Open Questions

1. **The staff read surface.** `duplicate_of` is written but not displayed.
   Without it, AI-1's value is invisible to the people it helps. Decide whether
   the duplicate hint appears in the staff queue, the report detail header, or
   only in the admin analytics view.
2. **Threshold validation.** 0.85 is a starting guess, not a measured value.
   Needs a hand-labelled duplicate/non-duplicate pair set before any accuracy
   figure enters the report.
3. **Backfill.** Existing reports were never checked. Duplicates submitted
   before this migration stay unflagged unless a backfill is written; that
   backfill must respect the community scoping in §2.3 and must not rewrite
   `duplicate_of` for reports a student has since had moderated.
4. **When a duplicate is found.** Linking is advisory, but should the UI ever
   offer the student "add your support to the existing report?" That is a
   product decision with real privacy weight and is **not** covered here.
5. **`ai_classification_log` retention.** Unbounded append-only growth.
6. **Tooling.** Supabase CLI install would make migrations reproducible
   instead of hand-applied; it is the prerequisite for AI-2 onward.

---

## 6. References

- `docs/architecture/AI_ARCHITECTURE.md` (§1 constraints, §2 built assets, §5 duplicate detection, §8 failure behaviour, §9 phases)
- `docs/architecture/MASTER_ARCHITECTURE.md:87`, `:211`, `:293` — AI is assistive only
- `docs/architecture/RLS_POLICIES.md`
- `docs/architecture/REPORT_LIFECYCLE.md`
- `supabase/migrations/20261005123000_ai1_duplicate_detection.sql` — the implementation of §2
- `supabase/migrations/20260811103300_rls_security.sql:101-127` — `can_create_report()`
- `supabase/migrations/20260811103000_ai_classification_log.sql` — fixed jsonb shapes
- `docs/development/CURRENT_STATE.md` §6, §8 — AI invariants
