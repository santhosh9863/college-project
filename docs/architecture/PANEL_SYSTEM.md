# Panel System — Part 2 Design (Phase 2.1, LOCKED)

**Status:** APPROVED design decisions (2026-08-15). Source of truth for the staff panels
(HOD / Technician / Operations / Admin) and for the routing prerequisite work (Phase 2.2).
Complements `MASTER_ARCHITECTURE.md` §8–§11 and `RLS_POLICIES.md`; where this document
disagrees with an earlier note, **this document wins** (decisions D1–D6 below were locked
explicitly by the product owner).

---

## 1. One app, five role-based panels

Single Flutter app + shared Supabase backend. The authenticated role (from `profiles.role`,
via `public.my_role()`) selects the panel. No separate apps, no hardcoded routing in Flutter —
routing lives in `category_routes`.

| Panel | Role | Home content |
|---|---|---|
| Student | `student` | My Reports (status tabs), Community Reports (support/comment/status), Notifications — **implemented and verified** |
| HOD | `hod` | Department-routed reports; review, comment, view evidence, change status, resolve/reject |
| Technician | `technician` | Assigned-to-me + department-routed technical reports; in-progress, comment, add work evidence, resolve |
| Operations | `operations` | Operational/facility reports; assign (with admin), update status, comment, evidence, resolve/reject |
| Admin | `admin` | Everything (read) + moderation (restore/delete) + analytics; structural management via Supabase dashboard (D5) |

## 2. Locked decisions (D1–D6)

| # | Question | Decision |
|---|---|---|
| D1 | Staff routing scope | **Department-scoped.** A staff member sees category-routed reports only when `reports.department_id = profiles.department_id`. The assignment branch is NOT department-scoped (explicit assignment always grants visibility). Admin sees all. |
| D2 | Who assigns | **Operations/Admin only** (RLS `can_manage_assignment` unchanged, u9/F7). HOD reviews and manages their queue but does not assign. |
| D3 | Assignment acceptance | **Push-only.** Assignment is active immediately; no accept step. "Assigned to me" = active `report_assignments.assigned_to = me`. |
| D4 | Technician/Operations scope | **Routed visibility.** Category-routed reports are visible without assignment (matches D1 scope); assignment adds visibility regardless of department. |
| D5 | Admin management surface | **Dashboard-managed.** In-app admin = read-all + moderation (restore/soft-delete) + analytics. User/role/department/category/category_routes management stays in the Supabase dashboard (service role). No new admin CRUD policies. |
| D6 | Analytics | **View-gated SECURITY DEFINER RPCs** — aggregates computed in SQL over exactly the rows the caller may see (reuse `report_visible_to_caller`/department scope). No client-side aggregation over the 50-row feed cap. |

## 3. Report visibility matrix (final)

Visibility = `report_visible_to_staff(report_id)` (staff) with D1 department scope on the
routing branch; students unchanged (`report_visible_to_caller`).

| Report | Student | HOD | Technician | Operations | Admin |
|---|---|---|---|---|---|
| Own report (student) | ✅ | ✅* | ✅* | ✅* | ✅ |
| Community report (own community) | ✅ | ✅* | ❌ | ❌ | ✅ |
| Department report (routed category, same dept) | ❌ | ✅ | ✅* | ✅* | ✅ |
| Department report (routed category, other dept) | ❌ | ❌ | ❌ | ❌ | ✅ |
| Assigned to me (any dept) | ❌ | ✅ | ✅ | ✅ | ✅ |
| All reports | ❌ | ❌ | ❌ | ❌ | ✅ |

\* only when routed (D1) or assigned (never for community reports — no routing/assignment → ❌ for
technician/operations). `*` cells marked ✅ in the original draft are resolved as: routed-or-assigned.

## 4. Category → primary panel routing (`category_routes` seed)

Seeded in Phase 2.2 (idempotent, unique `(category_id, role)`). Multiple roles per category
are allowed and seeded where a secondary panel exists.

| Category | Routed roles (priority 1) |
|---|---|
| Academic | hod |
| Infrastructure | operations, technician |
| IT & Network | technician |
| Facilities | operations |
| Harassment & Discrimination | hod |
| Ragging & Bullying | hod |
| Mental Health & Counselling | hod |
| Safety & Security | operations |
| Human Rights | hod |
| Anti-Drug / Substance Abuse | hod |
| Sexual Harassment | hod |
| Grievance | hod |
| Emergency / Fire Safety | operations |
| Other | hod, operations |

## 5. Capability matrix (actions)

| Action | Student | HOD | Technician | Operations | Admin |
|---|---|---|---|---|---|
| Create report (community, pending) | ✅ | ❌ | ❌ | ❌ | ✅ (test data) |
| Support / withdraw support | ✅ | ❌ | ❌ | ❌ | ❌ |
| Comment | ✅ (visible reports) | ✅ | ✅ | ✅ | ✅ |
| Add evidence | ✅ (own reports) | ✅ (visible) | ✅ (visible) | ✅ (visible) | ✅ |
| Change status (lifecycle matrix) | ❌ (cancel only) | ✅ (visible) | ✅ (visible) | ✅ (visible) | ✅ |
| Reopen (resolved/rejected) | ❌ | ❌ | ❌ | ✅ | ✅ |
| Assign / reassign | ❌ | ❌ | ❌ | ✅ | ✅ |
| Cancel own pending report (soft-delete) | ✅ | ❌ | ❌ | ❌ | ❌ |
| Restore / moderation soft-delete | ❌ | ❌ | ❌ | ❌ | ✅ |
| Read everything | ❌ | ❌ | ❌ | ❌ | ✅ |
| Manage users/roles/departments/categories | ❌ | ❌ | ❌ | ❌ | dashboard (D5) |

Status transitions are enforced by `can_transition_status` (pending → under_review/in_progress/
rejected/closed(admin); in_progress → resolved/rejected; reopen O/A-only; closed terminal; entering
in_progress requires an active assignment). No change needed for the panels.

## 6. Notification recipients (server triggers)

All generated by DB triggers (already implemented, `server_generated_events.sql`):

| Event | Recipients |
|---|---|
| Report created | Routed staff of the report's category **and department** (D1-scoped), minus reporter |
| Status change | Reporter always; active assignee when entering in_progress; routed staff (D1-scoped) on reopen |
| Assigned / unassigned | The assignee / former assignee |
| Resolved/rejected/closed | (via the above: reporter + active assignment deactivation) |
| Student self-cancel | No notifications (by design) |

## 7. Phase plan (agreed order)

1. **2.1 Finalize panels + routing matrix** ← LOCKED (this document)
2. **2.2 Database/routing prerequisites** — seed `category_routes`; D1 department scope in
   `report_visible_to_staff` + notification recipient sets
3. **2.3 Student reporting flow** — ✅ DONE (verified end-to-end live, `8b94a11`)
4. **2.4 HOD panel** — department queue, review/comment/evidence/status, resolve/reject
5. **2.5 Technician panel** — assigned-to-me + routed technical reports, in-progress/comment/evidence/resolve
6. **2.6 Operations panel** — operational queue, assign, status, evidence, resolve/reject
7. **2.7 Admin panel** — read-all, moderation, management readouts
8. **2.8 Notifications** — unread badge + inbox (client-side consumption of server-generated rows)
9. **2.9 Reports/analytics** — view-gated aggregate RPCs (D6) + dashboard screens
10. **2.10 Security + RLS audit + testing**
