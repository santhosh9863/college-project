# ADR-005: Linways Screenshot Import (Part 1)

> Decision record for importing attendance from Linways screenshots via on-device OCR.
> **Status: ACCEPTED (Part 1).**
> **Scope: screenshot/image import only. No API changes, no database changes, no storage uploads.**

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

The live Linways attendance API (`get-my-attendance-summary`) returns an overall attendance percentage only. Students in the college also view subject-wise attendance, profile information, and other academic screens inside Linways. Importing screenshots gives students a local way to capture and review their attendance without expanding the Linways API surface.

Part 1 must:

- Import a Linways screenshot from the device gallery.
- Recognize text **on-device** (no cloud OCR, no uploads, no Edge Functions).
- Parse the text into a typed, provenance-annotated snapshot.
- Validate the result and let the student review it before it is used.
- Never change the authenticated identity, the community, or the database.

## 2. Decision

### 2.1 Scope

- **In scope:** gallery image selection, on-device OCR, structural parsing (overall attendance, subject-wise attendance, student/profile information), validation, provenance, preview UI, and in-memory use of the imported attendance.
- **Explicitly out of scope (Part 1):** camera capture (deferred — see §5), Linways API changes, Supabase database changes, Supabase Storage, notifications, reports, authority panel, AI/ML, marks/exams/timetable parsing (P2 fields are captured only when clearly visible, never required).

### 2.2 OCR engine

**Selected: `google_mlkit_text_recognition` (Google ML Kit Text Recognition v2, Latin script) on Android/iOS.**

- On-device recognition; image pixels never leave the device.
- The Latin recognition model is downloaded once by ML Kit on first use and then runs locally.
- Actively maintained Flutter plugin (verified publisher `flutter-ml.dev`), compatible with the project's Flutter 3.41 / Dart 3.11 / Android compileSdk 37 / minSdk ≥ 21.
- The OCR service is behind an interface so the parser/controller stay fully unit-testable without a device.

### 2.3 Supported screen types

| Type | Content |
|---|---|
| A. Overall attendance | Overall percentage, total/conducted/attended/absent counts |
| B. Subject-wise attendance | Table of subjects with counts and percentages |
| C. Student/profile information | Name, register number, department, semester, section, batch, academic year |

Detection is **text + label based** (no pixel coordinates). If the screen type is uncertain the parser continues where possible and reports the uncertainty.

### 2.4 Extraction & provenance

Every important field carries a provenance:

- `EXTRACTED` — read directly from the OCR text (with optional confidence).
- `DERIVED` — calculated from visible values (e.g. absent = conducted − attended; percentage = attended ÷ conducted × 100).
- `MISSING` — not visible; stays `null`. **Nothing is ever guessed or inferred.**

If a visible value conflicts with a calculation, the visible value is preserved and a validation warning is generated. Example: visible absent = 9 while conducted − attended = 8 → keep 9, warn.

### 2.5 Identity authority

The authenticated Linways profile (server-derived, from the auth handshake) remains the **only authority** for identity, community, semester, and section. Screenshot-derived identity fields are **corroborative/display-only**. If they differ (e.g. screenshot says section A, registered profile says C), the community is unchanged and a warning is shown: "Screenshot information differs from your registered profile."

### 2.6 Storage & privacy

- Parsed snapshots exist **in memory only** (controller state). No database tables, no Supabase Storage, no files.
- The picked image is a temporary cache file created by the picker; it is deleted after processing.
- No console logging of OCR text, no analytics containing OCR data, no network calls from the import path.

### 2.7 Validation

Severity levels:

- **ERROR** — invalid data (attended > conducted, absent > conducted, percentage outside 0–100, nothing extractable). Import can still be reviewed but confirmed use is blocked only when the data is invalid; optional fields never block.
- **WARNING** — inconsistencies (percentage ≠ calculated, absent ≠ conducted − attended, identity mismatch, duplicate subject rows).
- **INFO** — informational (e.g. "Subject code was not visible in the screenshot").

## 3. Consequences

- The app now conceptually supports two attendance sources: **LIVE** (Linways API, unchanged, 30-minute cache) and **IMPORT** (screenshot-derived, memory-only). The UI clearly labels which is shown.
- The existing `LinwaysAttendanceRepository`, `AttendanceController`, and the linways-login Edge Function are **unchanged**.
- No existing Supabase migration is modified; no new migration is created.
- First use of OCR requires the ML Kit model download (on-device, one-time); without network the first recognition fails and the flow reports the error cleanly.

## 4. Alternatives Considered

| Option | Verdict |
|---|---|
| `google_mlkit_text_recognition` (ML Kit v2, Latin) | **Selected** — maintained, on-device, high accuracy, structured blocks/lines for parsing |
| `flutter_tesseract_ocr` / `tesseract_ocr` (Tesseract) | Rejected — weakly maintained, requires bundling traineddata, lower accuracy on UI text |
| Cloud OCR (Google Cloud Vision, etc.) | Rejected — violates on-device/privacy constraint; uploads sensitive student data |
| OCR inside a Supabase Edge Function | Rejected — requires uploading screenshots to the server; violates local-only privacy |
| Pixel-coordinate templates | Rejected — fragile across devices, resolutions, and Linways versions; text+labels chosen instead |

## 5. Open Questions

1. **Real screenshot validation** — the parser is built and tested against representative OCR-text fixtures. Validation against the actual Linways screenshots (user-provided) is pending and is the first Part 2 task. Screenshots needed: overall attendance screen, subject-wise attendance screen, profile screen.
2. **Camera capture** — deferred. The image-pick service interface leaves room to add `pickFromCamera()` without changing the rest of the flow.
3. **Persistence of imported snapshots** — out of scope for Part 1 (mirrors locked decision 4: attendance is not stored). Revisit only via a new ADR.

## 6. References

- `docs/architecture/LINWAYS_SCREENSHOT_IMPORT.md` (architecture)
- `docs/architecture/LINWAYS_INTEGRATION_ARCHITECTURE.md` (live API integration — unchanged)
- `docs/decisions/ADR-004-Linways-Community.md` (decision 4: attendance not stored)
- `docs/development/DEVELOPMENT_ROADMAP.md`
