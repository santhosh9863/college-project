# Linways Screenshot Import — Architecture

> On-device screenshot import for attendance. Part 1: gallery → on-device OCR → structured parser → validation → preview → confirm → use in the attendance experience.
> **Companion decision record: `docs/decisions/ADR-005-Linways-Screenshot-Import.md`.**
> The live Linways API integration (`LINWAYS_INTEGRATION_ARCHITECTURE.md`) is unchanged by this design.

---

## Table of Contents

1. [Purpose](#1-purpose)
2. [Pipeline Overview](#2-pipeline-overview)
3. [Supported Screenshot Types](#3-supported-screenshot-types)
4. [OCR Architecture](#4-ocr-architecture)
5. [Extraction Schema](#5-extraction-schema)
6. [Parsing Strategy](#6-parsing-strategy)
7. [Validation](#7-validation)
8. [Provenance](#8-provenance)
9. [Identity Authority Rules](#9-identity-authority-rules)
10. [Privacy & Local-Only Storage](#10-privacy--local-only-storage)
11. [Two Attendance Sources](#11-two-attendance-sources)
12. [Limitations](#12-limitations)
13. [Future Extension Points](#13-future-extension-points)

---

## 1. Purpose

Students currently see only the overall attendance percentage from the live Linways API. Screenshot import lets a student bring subject-wise attendance, overall counts, and profile information from a Linways screenshot into the app for review — **locally, on-device, without uploading anything**.

Part 1 is strictly additive: it must not modify the live attendance API path, the linways-login Edge Function, the 19 Supabase migrations, or any database storage behavior.

## 2. Pipeline Overview

```
Linways screenshot
→ gallery pick (image_picker)
→ image validation (format + size)
→ on-device OCR (Google ML Kit Text Recognition v2, Latin)
→ OCR text (normalized lines)
→ screen type detection (text + labels)
→ structured parser (identity / overall / subject-wise / P2)
→ validation & cross-checking
→ ParsedLinwaysSnapshot (typed, provenance-annotated)
→ preview UI (values + provenance + issues)
→ user confirms
→ imported attendance used in the attendance card (IMPORT source)
```

Layers (each unit-testable, no OCR/parser logic inside widgets):

```
image acquisition  →  OCR service  →  parser  →  validator  →  models  →  controller  →  UI
```

## 3. Supported Screenshot Types

| Type | Recognized by | Example content |
|---|---|---|
| **A. Overall attendance** | "attendance percentage" / "overall attendance" / "attendance %" labels, standalone percentage | `Attendance Percentage 89.11%`, `Classes Conducted 40 Attended 32` |
| **B. Subject-wise attendance** | table header (subject/conducted/attended/absent/percentage) or ≥2 rows of subject text + numbers | `Operating Systems 40 32 8 80%` |
| **C. Student/profile information** | name/register no/USN/programme/batch/semester labels | `Student Name: Santhosh Kumar`, `Register No: 9538111909`, `BCA 2024 S5 C` |

Detection is label-based, not pixel-based. Multiple types can appear on one screen (e.g. profile header + subject table). An uncertain screen type is reported in the snapshot (`screenConfidence`) and the parser still extracts whatever is present.

## 4. OCR Architecture

- **Engine:** Google ML Kit Text Recognition v2 (Latin script) via `google_mlkit_text_recognition`.
- **Location:** on-device. Image pixels never leave the device; no OCR API, no cloud vision, no Edge Function involvement.
- **Model:** the Latin model is downloaded once by ML Kit on first use, then runs locally. Offline first use fails cleanly with a retryable error.
- **Interface:** `OcrService.recognizeImage(path) → text`. The ML Kit implementation is swappable; tests use a fake service with fixture text.
- **Output:** raw text is split into normalized lines (`OcrLine{text}`) for parsing.

## 5. Extraction Schema

Typed Dart model `ParsedLinwaysSnapshot` (no `Map<String, dynamic>` as the application model):

```
ParsedLinwaysSnapshot
├── source: { screenType, screenConfidence, capturedAt }
├── identity: { studentName, studentId, department, semester, section, batch, academicYear }
├── overall: { conducted, attended, absent, percentage, status }
├── subjects: [ { name, code, faculty, conducted, attended, absent, percentage } ]
├── attendanceDate
├── optional (P2, only when clearly visible): timetable, period, classroom, dateTime, examInfo, marks
├── provenance (per field): source = EXTRACTED | DERIVED | MISSING, value, confidence?
└── warnings: [ ValidationIssue ]
```

Every value is a `ProvenanceValue<T>`.

## 6. Parsing Strategy

### 6.1 No guessing

- Extract **only** what is visible.
- `DERIVED` is allowed only when mathematically supported by visible values: `absent = conducted − attended`, `percentage = attended ÷ conducted × 100`.
- A visible value that conflicts with a derived one is **preserved**, and a warning is generated.
- Never infer a subject code, faculty name, register number, section, semester, department, or any count.

### 6.2 Field rules

| Field | Source | Notes |
|---|---|---|
| student name | EXTRACTED | label `name`/`student name` |
| register number / USN / student ID | EXTRACTED | label `register`/`usn`/`student id`/`admission no` |
| department / programme / course | EXTRACTED | corroborative only — never authoritative |
| semester | EXTRACTED | e.g. `S5`, `5`, `V` |
| section / batch | EXTRACTED | corroborative only |
| academic year | EXTRACTED | `2024-2025` style ranges |
| conducted / total | EXTRACTED | label `conducted`/`total classes` |
| attended | EXTRACTED | label `attended`/`present` |
| absent | EXTRACTED or DERIVED | prefer visible; else conducted − attended |
| percentage | EXTRACTED or DERIVED | prefer visible `NN.NN%`; else computed |
| status | DERIVED | from percentage, display-only |
| subject name / code / faculty | EXTRACTED (code & faculty only if visible) | |
| attendance date | EXTRACTED | date formats `DD/MM/YYYY`, `DD-MM-YY`, `DD Mon YYYY`, `YYYY-MM-DD` |
| P2 (timetable/period/classroom/exam/marks) | EXTRACTED, only when clearly labelled | never blocks extraction |

### 6.3 Subject rows

- A candidate row = one OCR line with ≥2 integer tokens and ≥1 text token, excluding lines recognized as labels/identity/date.
- Column semantics from a visible header (subject / conducted / attended / absent / percentage); without a header the trailing integers are assumed conducted → attended → absent, plus percentage if the last token is `%`.
- Row rejected when numbers are contradictory (attended > conducted, etc.) — flagged, not fixed.
- Duplicate rows (same normalized name/code) keep the first and warn.

### 6.4 OCR noise

Suspicious numeric tokens (letters mixed into digits, e.g. `8O`) are **not** corrected — they are flagged with a warning and treated as missing for that field.

## 7. Validation

| Severity | Rule | Example |
|---|---|---|
| ERROR | attended > conducted | "Attendance counts are invalid." |
| ERROR | absent > conducted | same |
| ERROR | percentage outside 0–100 | same |
| ERROR | nothing extractable | "No attendance data could be read from this screenshot." |
| WARNING | visible percentage ≠ calculated | "Attendance percentage differs from calculated percentage." |
| WARNING | visible absent ≠ conducted − attended | conflict preserved |
| WARNING | identity fields differ from registered profile | "Screenshot information differs from your registered profile." |
| WARNING | duplicate subject rows | |
| INFO | optional field not visible | "Subject code was not visible in the screenshot." |
| INFO | screen type uncertain | |

A missing optional field never blocks import. Invalid counts produce errors that prevent confirming the import.

## 8. Provenance

Every parsed field is one of:

- **EXTRACTED** — direct OCR read. Confidence attached when the OCR engine provides it.
- **DERIVED** — computed from extracted values (absent, percentage, status).
- **MISSING** — absent from the screenshot; value is `null`.

The UI renders a badge per value (EXTRACTED / CALCULATED / UNAVAILABLE) so the student understands the origin of every number.

## 9. Identity Authority Rules

1. The authenticated Linways profile (server-derived at login) is the **only authority** for identity, community, semester, section, and role.
2. Screenshot identity data is corroborative/display-only.
3. A mismatch (e.g. screenshot `BCA 2024 S5 A` vs registered `BCA 2024 S5 C`) never changes the community or profile — it produces a warning.
4. The imported attendance can still be reviewed and used locally; it is never written to the database.

## 10. Privacy & Local-Only Storage

- No console logging of screenshots, OCR text, or parsed data.
- No screenshot upload; no OCR cloud service; no Supabase Storage; no Edge Function calls in the import path.
- No analytics events containing OCR data.
- The picker's temporary image file is deleted after processing.
- Parsed snapshots live only in controller memory and are lost on app restart (mirrors locked decision 4: attendance is never stored).

## 11. Two Attendance Sources

| Source | Origin | Persistence | Cache |
|---|---|---|---|
| **LIVE** | `get-my-attendance-summary` via device-held Linways session | none (memory) | 30-min in-memory TTL (unchanged) |
| **IMPORT** | screenshot OCR + parsing | none (memory) | until replaced/cleared |

The attendance card labels the active source. Imported data is shown only after the student confirms the preview; the student can switch back to LIVE at any time.

## 12. Limitations

- **Real-screenshot validation pending:** the parser is validated against representative OCR-text fixtures derived from documented Linways layouts. Validation against the actual Linways screenshots requires the user-provided screenshots (see §13). Until then, screen-variant coverage is provisional.
- OCR accuracy depends on screenshot quality (resolution, contrast, rotation); low-quality screenshots may produce MISSING fields or errors.
- Subject rows that wrap across OCR lines or use unusual column orders may be mis-read; conflicting rows are rejected, never guessed.
- First OCR use requires the one-time ML Kit model download (on-device).
- Camera capture is not implemented in Part 1.

## 13. Future Extension Points

- **Camera capture** — add `pickFromCamera()` to the pick service; flow unchanged.
- **Real screenshot test corpus** — the user should provide: (1) overall attendance screen, (2) subject-wise attendance screen, (3) profile screen; fixtures and parser are adjusted from them.
- **P2 screens** (timetable, marks) — parser already stores clearly-visible P2 values; dedicated layouts can be added without touching P0/P1.
- **Persistence decision** — if imported snapshots should persist, a new ADR + migration is required (currently prohibited by locked decision 4).
- **Multiple screens per import** — a student could import several screenshots; Part 1 supports one screen per import.

---

**File:** `docs/architecture/LINWAYS_SCREENSHOT_IMPORT.md` (new)
**Status:** ACCEPTED (Part 1). No database, API, or existing-behavior changes.
