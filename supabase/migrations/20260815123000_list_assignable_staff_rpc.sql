-- Phase 2.6: staff directory RPC for the operations/admin assignment picker.
--
-- The client cannot enumerate staff via `profiles` (RLS: own row or admin
-- only). Ops/Admin need a picker for `report_assignments.assigned_to`, so
-- this SECURITY DEFINER RPC exposes a minimal staff directory, gated to the
-- two roles that may assign (u9 / F6: target must be staff, role <> student).
-- Callers in other roles get an empty result set; no RLS bypass for anyone.

create or replace function public.list_assignable_staff()
returns table (
  id uuid,
  full_name text,
  role public.user_role,
  department_code text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if public.my_role() not in ('operations', 'admin') then
    return;
  end if;

  return query
    select p.id, p.full_name, p.role, d.code
    from public.profiles p
    left join public.departments d on d.id = p.department_id
    where p.role <> 'student'
    order by p.full_name;
end;
$$;

revoke all on function public.list_assignable_staff() from public;
grant execute on function public.list_assignable_staff() to authenticated;