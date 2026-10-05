# Storage Design

> Supabase Storage architecture for evidence files, attachments, and user-uploaded content.
> **Status: ACCEPTED — records the model as applied.** This file was six empty sections
> while the entire storage design existed only as migration comments. Written from the
> five storage migrations and the client upload path.
> **Scope: evidence only.** Attendance screenshots are imported and parsed
> client-side and never reach Storage (`features/attendance/import/`).

---

## Table of Contents

1. [Storage Architecture](#1-storage-architecture)
2. [Bucket Structure](#2-bucket-structure)
3. [File Upload Flow](#3-file-upload-flow)
4. [Access Control](#4-access-control)
5. [File Types & Limits](#5-file-types--limits)
6. [Cleanup Strategy](#6-cleanup-strategy)
7. [What Went Wrong](#7-what-went-wrong)

---

## 1. Storage Architecture

One private bucket, `evidence`, holding every user-uploaded file in the project. It was
deliberately kept to a single bucket rather than one per feature.

There is no separate bucket for avatars, chat attachments, or attendance screenshots,
because none of those exist. Attendance import is a **client-side flow**: a screenshot
is parsed by `ocr_service.dart` on-device and only the extracted text is used
(`features/attendance/import/`), so no image is ever stored.

Storage RLS is **not** optional here in the way it usually is. The bucket is private, so
every object read requires a signed URL, and issuing that URL requires passing a
`storage.objects` select policy. Storage access is therefore gated in exactly the same
place, and by exactly the same helpers, as database row access — see §4.

The design goal is one sentence: **an object is visible to precisely the people who can
see its report, with no second authorisation system to keep in sync.**

---

## 2. Bucket Structure

Defined by migration insert, not by the dashboard
(`20260815102000_evidence_storage.sql:15-23`):

| Attribute | Value |
|---|---|
| `id` / `name` | `evidence` |
| `public` | **`false`** — private |
| `file_size_limit` | `20971520` (20 MiB) |
| `allowed_mime_types` | `image/png`, `image/jpeg`, `image/webp`, `image/heic`, `application/pdf` |

**Path convention:** `<report_id>/<file>`, where the first folder is the report's UUID.

There is no `evidence/` prefix inside `name`, because `storage.objects.name` holds only
the path *below* the bucket root. The bucket is selected by the API call
(`.from('evidence')`), not by the path.

Two details the migrations had wrong and then corrected — see §7:

- The convention was originally documented as `evidence/<report_id>/<file_id>_<name>`.
  The `<file_id>` part is not derivable client-side: `evidence_files.id` is a database
  default (`20260811102900_evidence_files.sql:5`) and the object is uploaded *before*
  the row exists. The client uses a millisecond timestamp for uniqueness instead
  (`reports_repository.dart:277`).
- The leading `evidence/` folder the client actually sends is stripped by
  `storage_evidence_report_id` (`20261005130000`).

---

## 3. File Upload Flow

Upload is a **two-step, non-transactional** sequence, and the ordering is forced by the
policies (`reports_repository.dart:269-297`):

1. **Create the report first.** The upload policy does an `exists()` check against
   `public.reports`, so a report row must exist before any object can be attached.
2. `storage.from('evidence').uploadBinary(objectPath, bytes, contentType: ...)`
3. **Then insert the `evidence_files` row**, which is separately RLS-gated by
   `evidence_files_insert` (`20260811103300_rls_security.sql:649-662`).

`create_report_controller._uploadEvidence` attempts **each file independently** and
counts failures rather than aborting (`create_report_controller.dart:188-199`). A file
the bucket rejects does not lose the report: the report is created and `pending`, and
`failedEvidenceCount` tells the UI to say so. This was deliberate — a 20 MiB or
format rejection should never discard a student's complaint.

### Known gap: orphaned objects

Because steps 2 and 3 are not atomic, an object can be uploaded with its
`evidence_files` row failing to insert, leaving a storage object with no metadata row.
Nothing reaps these. See §6.

### Filename sanitisation

`safeName` takes the last path segment and replaces any remaining `/` or `\` with `_`
(`reports_repository.dart:275`). This prevents a crafted filename from injecting extra
path segments. It does not strip other characters — `..` cannot escape because the
folder segment is a UUID and the file segment is a single path segment.

---

## 4. Access Control

Four policies total: three on `storage.objects`, one on `storage.buckets`.

### Object policies (`20260815102000`, amended by `20260815107000`)

| Policy | Op | Predicate |
|---|---|---|
| `evidence_select_visible` | select | `bucket_id = 'evidence'` **and** `report_visible_to_caller(storage_evidence_report_id(name))` |
| `evidence_insert_owner` | insert | `bucket_id = 'evidence'` **and** `owner = auth.uid()` **and** `exists(reports … deleted_at is null and (student-owned or staff-visible))` |
| `evidence_delete_admin` | delete | `bucket_id = 'evidence'` **and** `my_role() = 'admin'` |

Three properties are deliberate:

- **Reads reuse `report_visible_to_caller`**, the same helper eight database policies
  use (`20260811103300_rls_security.sql:568,590,617,640,647`). Object visibility is
  therefore identical to row visibility by construction, not by parallel maintenance.
- **There is no UPDATE policy.** Evidence is immutable; correcting a file means
  uploading a new object (`20260815102000:8`). This also means `storage.objects` UPDATE
  is denied to every client role.
- **`deleted_at is null` is required to upload**, so a soft-deleted report accepts no
  new attachments, while still allowing reads for staff.

### Bucket policy (`20260815106000`)

`bucket_select_authenticated` on `storage.buckets`, `using (true)`. This is
deliberately permissive: it exposes only the *existence* of buckets to authenticated
users, and object access remains fully gated by the three policies above. Without it
every upload 403s — see §7.

### Path parsing fails closed

`storage_evidence_report_id(p_name text)` extracts the report UUID from the object name
as a `SECURITY DEFINER` function with `set search_path = ''`
(`20261005130000`). Any path whose first folder is not a UUID returns NULL, and every
policy rejects NULL. It never returns a wrong answer.

---

## 5. File Types & Limits

| Constraint | Value | Enforced by |
|---|---|---|
| Max size | 20 MiB | bucket `file_size_limit` |
| Types | PNG, JPEG, WebP, HEIC, PDF | bucket `allowed_mime_types` |

The client maps extensions to MIME types in `evidence_mime.dart`, and **unknown
extensions deliberately resolve to `application/octet-stream`** rather than being
guessed. That type is not on the allow-list, so the bucket rejects the upload
server-side. Failing closed in the client keeps the authoritative check in the bucket,
where it cannot be bypassed by a modified client.

Both limits are enforced by Supabase Storage, not by the Flutter app. The app performs
no size check of its own, which is correct: a client-side limit is advisory.

---

## 6. Cleanup Strategy

**There is none.** This is the weakest part of the design and is stated plainly rather
than described aspirationally.

- **Soft-deleting a report does not touch Storage.** `reports.deleted_at` hides the row
  from students, but every object stays, and stays reachable by staff who can see the
  report. `evidence_files_delete_admin` exists, so an admin can remove an individual
  file, but nothing cascades from report deletion.
- **Orphaned objects are never reaped** (§3).
- **No lifecycle policy is configured.** Supabase supports expiring objects after N
  days; none is set.
- **Deleting an `evidence_files` row leaves the object behind**, because nothing deletes
  from `storage.objects` in response.

The security posture is acceptable — objects are never publicly reachable, and deletion
is admin-only — but this is a **cost and retention** problem, not an access problem. A
college project that stores student photos and PDFs indefinitely should decide a
retention period deliberately rather than by omission. See §7 and `ADR-002` §5.

---

## 7. What Went Wrong

Three live bugs hit this subsystem, all reproduced on 2026-08-15 and all fixed by new
migrations. They are recorded because the third was caused by misdiagnosing the second,
which is the lesson worth keeping.

### 7.1 The owner conjunct was removed on a wrong diagnosis

`evidence_insert_owner` originally required `owner = auth.uid()`. Every student upload
returned 403. Debug inserts showed that with `owner = null` the upload was rejected
`42501` while with `owner = auth.uid()` it succeeded, so `20260815104000` concluded the
storage service does not populate `owner` and **removed the check as redundant**.

That conclusion was wrong. The 403s were caused by the two bugs below. Once those were
fixed, `20260815107000` **restored** the owner conjunct as the defence-in-depth check it
was always meant to be.

The intermediate migration therefore looks like a security weakening that later got
reverted. In the final schema `owner = auth.uid()` is present and load-bearing.

### 7.2 `storage.objects.name` does not include the bucket

The parser required a leading `evidence/` folder and read the report id from `[2]`. But
`name` holds only the path below the bucket root, so for a real upload `[2]` was
undefined and every read and write was denied. `20260815105000` changed it to `[1]`.

### 7.3 …and `[1]` is not the report id either, because the client sends the prefix

The client has always uploaded to `evidence/$reportId/<file>`
(`reports_repository.dart:276-277`). This predates `20260815105000` and was not changed
by the commit that introduced it — `8b94a11` did not touch `reports_repository.dart`.
So after 7.2, `foldername()` returned `{evidence, <report_id>}`, `[1]` was the literal
string `evidence`, and `'evidence'::uuid` **threw**:

```
ERROR: invalid input syntax for type uuid: "evidence"
```

So `20260815105000` fixed one mismatch by introducing another. It also broke its own
stated guarantee: the comment claims a bad cast "resolves to NULL and every policy
rejects it", but a failing `::uuid` cast raises an exception rather than returning NULL.

`20261005130000` resolves this without guessing which side is right: it strips an
optional leading `evidence/` segment, takes the first remaining folder, and admits it
only if it matches a UUID pattern. Both shapes work, and anything else returns NULL.

### Why this is recorded

Two of the three bugs came from reasoning about what the storage service does instead
of observing it, and the third from fixing a symptom before the cause. §7.1 is the
clearest case: a security control was removed on the strength of a debug observation
that turned out to be explained by something else entirely.

---

## 8. References

- `supabase/migrations/20260815102000_evidence_storage.sql` — bucket + 3 object policies
- `supabase/migrations/20260811102900_evidence_files.sql` — metadata table
- `supabase/migrations/20260811103300_rls_security.sql` — `evidence_files` policies (`:644-667`)
- `supabase/migrations/20260815104000_fix_evidence_owner.sql` — the wrong fix (§7.1)
- `supabase/migrations/20260815105000_fix_evidence_path.sql` — bucket-name fix (§7.2)
- `supabase/migrations/20260815106000_fix_storage_bucket_policy.sql` — missing bucket policy
- `supabase/migrations/20260815107000_restore_evidence_owner.sql` — owner restored (§7.1)
- `supabase/migrations/20261005130000_fix_evidence_path_prefix.sql` — both shapes, fail closed (§7.3)
- `flutter_app/lib/features/reports/data/reports_repository.dart:269-297` — upload path
- `flutter_app/lib/features/reports/data/evidence_mime.dart` — extension → MIME mapping
- `flutter_app/lib/features/reports/create_report_controller.dart:188-199` — per-file failure handling
- `docs/development/REPORTS_SYSTEM_PART2_REPORT.md` — original report, BLOCKER 4
- `docs/decisions/ADR-002-Database.md` — §2.12 storage as applied; §5.2 this doc was empty
