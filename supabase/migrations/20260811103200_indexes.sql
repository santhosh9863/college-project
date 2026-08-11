-- Phase 1.2 — Database Foundation
-- Migration 14: Indexes
-- Foreign-key lookup indexes per DATABASE_DESIGN.md section 5.
-- (Uniqueness constraints were created inline in their table migrations.)

create index if not exists profiles_department_id_idx
  on public.profiles (department_id);

create index if not exists category_routes_category_id_idx
  on public.category_routes (category_id);

create index if not exists reports_reporter_id_idx
  on public.reports (reporter_id);

create index if not exists reports_category_id_idx
  on public.reports (category_id);

create index if not exists reports_department_id_idx
  on public.reports (department_id);

create index if not exists reports_duplicate_of_idx
  on public.reports (duplicate_of);

create index if not exists report_assignments_report_id_idx
  on public.report_assignments (report_id);

create index if not exists report_assignments_assigned_to_idx
  on public.report_assignments (assigned_to);

create index if not exists report_supports_report_id_idx
  on public.report_supports (report_id);

create index if not exists report_comments_report_id_idx
  on public.report_comments (report_id);

create index if not exists report_activity_report_id_idx
  on public.report_activity (report_id);

create index if not exists evidence_files_report_id_idx
  on public.evidence_files (report_id);

create index if not exists ai_classification_log_report_id_idx
  on public.ai_classification_log (report_id);

create index if not exists notifications_user_id_idx
  on public.notifications (user_id);
