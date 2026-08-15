-- Phase 2 — Panel System (Phase 2.2): seed category_routes.
--
-- LOCKED design (docs/architecture/PANEL_SYSTEM.md §4): category -> primary panel
-- routing. The seed is idempotent (unique per category+role, on conflict do
-- nothing) and references categories by NAME, so it stays correct regardless of
-- the generated ids. Multiple roles per category are allowed and seeded where a
-- secondary panel exists (PANEL_SYSTEM.md §4); priority 1 for all seeded rows
-- (priority orders recipients later, if ever needed).
--
-- This supersedes the "deferred to authority-panel phase" note in
-- 20260815101000_seed_categories_departments.sql: with the panel design locked,
-- the routing rows are a Phase 2.2 prerequisite (PANEL_SYSTEM.md §7).

-- Idempotency guard: one routing row per (category, role).
create unique index if not exists category_routes_category_role_uidx
  on public.category_routes (category_id, role);

insert into public.category_routes (category_id, role, priority)
select c.id, v.role::public.user_role, v.priority
from (values
  ('Academic',                        'hod',         1),
  ('Infrastructure',                  'operations',  1),
  ('Infrastructure',                  'technician',  1),
  ('IT & Network',                    'technician',  1),
  ('Facilities',                      'operations',  1),
  ('Harassment & Discrimination',     'hod',         1),
  ('Ragging & Bullying',              'hod',         1),
  ('Mental Health & Counselling',     'hod',         1),
  ('Safety & Security',               'operations',  1),
  ('Human Rights',                    'hod',         1),
  ('Anti-Drug / Substance Abuse',     'hod',         1),
  ('Sexual Harassment',               'hod',         1),
  ('Grievance',                       'hod',         1),
  ('Emergency / Fire Safety',         'operations',  1),
  ('Other',                           'hod',         1),
  ('Other',                           'operations',  1)
) as v(name, role, priority)
join public.categories c on c.name = v.name
on conflict (category_id, role) do nothing;
