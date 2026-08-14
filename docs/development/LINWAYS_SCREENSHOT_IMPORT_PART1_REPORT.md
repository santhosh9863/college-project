# Part 1 Final Report — Linways Screenshot/Image Import (On-Device OCR)

**Date:** 2026-08-14 · **Scope:** "college project" Flutter app (`flutter_app`) · **Backend:** untouched
**Status:** ✅ Implemented, `flutter analyze` clean, 93/93 tests passing, `flutter build apk --debug` successful.

---

## 1. Summary

Part 1 delivers a complete on-device Linways screenshot import pipeline into the existing Flutter app:
**gallery pick → pre-validation → on-device OCR → structured parser → validation → preview/confirm → use as an
"IMPORT" attendance source in the existing attendance experience.** No network calls, no Supabase involvement, no
uploads, no storage. Live attendance (Linways login + `LinwaysAttendanceRepository`, 30-minute cache) is untouched
and both sources coexist clearly labelled. Per the constraints: no new tables, no Edge Function changes, no storage,
no reports/authority panel, no AI/ML, and the project keeps the name "college project".

## 2. OCR approach

- **Engine:** `google_mlkit_text_recognition` 0.16.0 (ML Kit v2, **Latin script**, text recognition).
  Selected because: 100 % on-device (privacy requirement), free, actively maintained, and its Latin-text mode
  produces stable tokenization for the table layouts. The ~25 MB model is downloaded once on first use and
  cached by ML Kit.
- **Fallback/error surface:** OCR throws are mapped to user-readable errors ("Couldn't read the text in this image.
  Try a clearer screenshot."), empty results and unsupported screens get dedicated messages.
- **Image pipeline:** `image_picker` (gallery only; the user reads screenshots from Photos) → format check by
  magic bytes (JPEG/PNG/BMP/GIF/WEBP) + 50 MB guard → OCR. Picked files are copied to a temp path, always deleted
  after processing (success or failure).

## 3. Architecture & file layout

All new code lives under `flutter_app/lib/features/attendance/import/`:

| Layer | Files |
|---|---|
| Models | `models/provenance.dart`, `models/validation_issue.dart`, `models/parsed_linways_snapshot.dart` |
| Image | `image/image_pick_service.dart`, `image/image_validator.dart` |
| OCR | `ocr/ocr_service.dart` (interface + `OcrException`), `ocr/mlkit_ocr_service.dart` |
| Parser | `parser/ocr_text.dart`, `parser/pattern_helpers.dart`, `parser/linways_screen_detector.dart`, `parser/attendance_table_parser.dart`, `parser/linways_ocr_parser.dart` |
| Validator | `validator/snapshot_validator.dart` |
| Controller | `import_controller.dart` (`ImportStep`: idle → picking → processing → preview → error) |
| UI | `screens/import_flow_screen.dart`, `widgets/provenance_badge.dart`, `widgets/value_row.dart`, `widgets/validation_panel.dart` |

Wiring (modified files): `attendance_controller.dart` (imported snapshot state), `widgets/attendance_card.dart`
(IMPORT banner + "Import Linways Screenshot" button), `home/home_shell.dart` (controller + flow launcher).
Docs: `docs/decisions/ADR-005-Linways-Screenshot-Import.md`, `docs/architecture/LINWAYS_SCREENSHOT_IMPORT.md`.

## 4. Data model & provenance

- **`ParsedLinwaysSnapshot`** holds `source`, `identity`, `overall`, `subjects`, `attendanceDate`, `optional`,
  `warnings` — memory-only, never persisted.
- **`ProvenanceValue<T>`** — every field carries exactly one of:
  - `EXTRACTED` — visibly read from the screenshot (UI badge EXTRACTED).
  - `CALCULATED` — derived by math only (e.g. absent = conducted − attended; UI badge CALCULATED).
  - `UNAVAILABLE` — not visible; shown greyed out (UI badge UNAVAILABLE).
- **No guessing:** nothing is inferred from other fields except arithmetic; a conflicting visible value is always
  preserved with a warning (never overwritten). Missing subject code/register number are NEVER fabricated from
  other numbers (regex guards reject digits glued to letters like `CS201`).

## 5. Supported screenshot types

Detected by `LinwaysScreenDetector` (keyword/row scoring → type + confidence; ambiguity lowers confidence, never
guesses):

| Type | Content |
|---|---|
| `overallAttendance` | Classes Conducted/Attended/Absent, Attendance Percentage, As-on date |
| `subjectWiseAttendance` | Subject table (Subject/Code/Faculty/Conducted/Attended/Absent/Percentage), with or without header row |
| `studentProfile` | Name, Register No, Programme, Sem, Section, Batch, Academic Year |
| `unknown` | Anything else → "no attendance data" error, flow stops |

## 6. Field extraction coverage

| Field | Class | Provenance | Notes |
|---|---|---|---|
| Overall conducted / attended | P0 | EXTRACTED | labelled values only |
| Overall absent | P0 | EXTRACTED or CALCULATED | visible wins; else derived from counts |
| Overall percentage | P0 | EXTRACTED | visible wins; `status` derived from it |
| Attendance date ("As on …") | P1 | EXTRACTED | |
| Subject name / code / faculty | P0 | EXTRACTED | code only if clearly code-shaped |
| Per-subject conducted/attended/absent/percentage | P0 | EXTRACTED / CALCULATED | absent derived only if not visible |
| Identity: name, register no | P0 | EXTRACTED | corroborative only (profile is authoritative) |
| Department / semester / section / batch / academic year | P1 | EXTRACTED | |
| Timetable / exam info / marks / period / classroom | P2 | EXTRACTED when clearly labelled | never blocks P0/P1; typically UNAVAILABLE |

**Suspicious OCR (O/I/L vs 0/1):** a row containing an ambiguous token (e.g. `4O`) is treated as *not read* — all
its numeric values are UNAVAILABLE with a `suspiciousOcrNumber` warning; values are never "corrected" or shifted.

## 7. Derivation & conflict rules

- absent = conducted − attended (only when both visible; otherwise UNAVAILABLE).
- status = derived category from percentage (e.g. SAFE/CRITICAL display only).
- Visible absent ≠ calculation → `absentMismatch` WARNING, visible value kept.
- Visible percentage ≠ count-based calculation → `percentageMismatch` WARNING, visible value kept.
- Percentage duplicated (header column + `%` token) → used once, never double-counted.

## 8. Validation rules (`SnapshotValidator`)

- **ERROR (blocks confirm):** no attendance data; attended > conducted; absent > conducted; percentage outside 0–100.
- **WARNING (allowed with attention):** identity mismatches (name/section/department/semester vs authenticated
  profile — profile remains authoritative), percentage/absent conflicts, duplicate subject rows, suspicious OCR.
- **INFO:** e.g. missing subject code.
- Issues are sorted errors-first and deduplicated; the preview shows them in a panel with severity icons.

## 9. UI flow

1. Attendance card → **Import Linways Screenshot** → photo picker.
2. Processing state (OCR on-device, animated).
3. **Preview screen:** screen-type badge + confidence, identity header, overall figures, subject table, each value
   with EXTRACTED/CALCULATED/UNAVAILABLE badge, warnings panel.
4. **Confirm** (disabled while ERRORs exist) → snapshot applied to the attendance experience; or back/cancel → idle.
5. Inline errors for invalid images, OCR failure, empty text, and unsupported screenshots.

## 10. Live vs Import integration

- `AttendanceController` now has `useImported(…)` / `clearImported()` / `importedSnapshot`.
- The attendance card shows a clear **IMPORT** chip + banner; live fetch/refresh and the 30-min cache are unchanged.
- Source labels ("Live" / "Import") are explicit in the UI; values always remain attributable to their source.

## 11. Privacy & security

- 100 % on-device OCR — pixels never leave the device; no network requests in the import path.
- Snapshot lives in memory only; temp image file deleted after processing in all outcomes.
- No logging of screenshot content; no persistence; nothing written to Supabase.
- `ImageValidator` guards format (magic bytes) and size (50 MB) before any processing.

## 12. Dependency & config changes

- `pubspec.yaml`: added `google_mlkit_text_recognition: ^0.16.0`, `image_picker: ^1.2.3`.
- `android/app/build.gradle.kts`: `isCoreLibraryDesugaringEnabled = true` +
  `coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")` (ML Kit requirement).
- `ios/Runner/Info.plist`: `NSPhotoLibraryUsageDescription`.
- No backend, Supabase, or migration changes.

## 13. Test summary

52 new tests added under `flutter_app/test/features/attendance/import/` (+41 pre-existing):

- `linways_ocr_parser_test.dart` — screen detection (all types + unknown + empty), overall parsing, derivation,
  conflicts, suspicious OCR, identity extraction, subject tables (header/no-header/duplicates/invalid counts).
- `snapshot_validator_test.dart` — errors, warnings, identity mismatch vs registered profile, sorting, no-attendance.
- `import_controller_test.dart` — full flow with fake OCR/picker: success, cancel, invalid image, OCR failure,
  empty text, unsupported screen, permission denial, dispose, temp-file cleanup.
- `image_validator_test.dart` — JPEG/PNG/WEBP accepted, text/empty/missing/huge rejected.

## 14. Validation results

| Check | Command | Result |
|---|---|---|
| Static analysis | `flutter analyze` | **No issues found** |
| Tests | `flutter test` | **93/93 passing** |
| Debug build | `flutter build apk --debug` | **√ Built `build/app/outputs/flutter-apk/app-debug.apk`** (259 s; Kotlin daemon cache warnings are non-fatal Windows noise) |

## 15. Known limitations & pending real-screenshot validation

- **No real Linways screenshots exist in the repo** — the parser is validated against representative fixtures
  (`test/features/attendance/import/fixtures/linways_fixtures.dart`), not the user's actual screens.
  Please provide **three screenshots** to close this gap (they were not included):
  1. **Overall attendance screen** (Classes Conducted/Attended/Absent + Attendance Percentage).
  2. **Subject-wise attendance screen** (full table with headers).
  3. **Student profile screen**.
  Expected: parse each via the flow and verify the preview shows EXTRACTED values matching the screens, and that
  name/register/section match the registered profile (warnings appear only if they genuinely differ).
- OCR accuracy on unusual layouts, fonts, or light text depends on ML Kit; low-confidence detections still extract
  but mark the screen type as uncertain in the UI.
- `attendanceDate` supports the documented date shapes (DD-MM-YYYY, DD/MM/YYYY, YYYY-MM-DD, "12 Aug 2026").
- iOS build not verified in this session (Windows host) — plist key added; verify with a macOS build.

## 16. Part 2 readiness

The importer is isolated behind `OcrService` / `ImagePickService` interfaces and a single `LinwaysImportController`,
so Part 2 can extend without touching Part 1: any additional fields = new parser slots in
`ParsedOptionalInfo`/`ParsedIdentity`; authority-panel/report features build on `importedSnapshot` state; new
screenshot layouts = new detector branches. Per instructions, **Part 2 and AI/ML work have NOT been started**.
