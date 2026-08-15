-- Phase 2 — Reports System (Part 2-A): seed reference data.
-- 1. departments: 'General' fallback (code GENERAL) + code-mapping mechanism —
--    the linways-login function maps course_code -> departments.code, falling
--    back to GENERAL. Additional departments can be added any time without
--    code changes (code = course prefix, e.g. BCA).
-- 2. categories: the 14 APPROVED categories (college project, no PULSE naming).
-- Idempotent: safe to run repeatedly. No applied migration is modified.
-- category_routes seeds are intentionally DEFERRED to the authority-panel
-- phase (approved decision).

insert into public.departments (name, code)
values ('General', 'GENERAL')
on conflict (code) do nothing;

insert into public.categories (name)
select 'Academic'
where not exists (select 1 from public.categories where name = 'Academic');

insert into public.categories (name)
select 'Infrastructure'
where not exists (select 1 from public.categories where name = 'Infrastructure');

insert into public.categories (name)
select 'IT & Network'
where not exists (select 1 from public.categories where name = 'IT & Network');

insert into public.categories (name)
select 'Facilities'
where not exists (select 1 from public.categories where name = 'Facilities');

insert into public.categories (name)
select 'Harassment & Discrimination'
where not exists (select 1 from public.categories where name = 'Harassment & Discrimination');

insert into public.categories (name)
select 'Ragging & Bullying'
where not exists (select 1 from public.categories where name = 'Ragging & Bullying');

insert into public.categories (name)
select 'Mental Health & Counselling'
where not exists (select 1 from public.categories where name = 'Mental Health & Counselling');

insert into public.categories (name)
select 'Safety & Security'
where not exists (select 1 from public.categories where name = 'Safety & Security');

insert into public.categories (name)
select 'Human Rights'
where not exists (select 1 from public.categories where name = 'Human Rights');

insert into public.categories (name)
select 'Anti-Drug / Substance Abuse'
where not exists (select 1 from public.categories where name = 'Anti-Drug / Substance Abuse');

insert into public.categories (name)
select 'Sexual Harassment'
where not exists (select 1 from public.categories where name = 'Sexual Harassment');

insert into public.categories (name)
select 'Grievance'
where not exists (select 1 from public.categories where name = 'Grievance');

insert into public.categories (name)
select 'Emergency / Fire Safety'
where not exists (select 1 from public.categories where name = 'Emergency / Fire Safety');

insert into public.categories (name)
select 'Other'
where not exists (select 1 from public.categories where name = 'Other');
