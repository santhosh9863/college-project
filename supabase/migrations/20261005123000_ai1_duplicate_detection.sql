-- AI-1 — Duplicate detection (ADR-003 §2, AI_ARCHITECTURE.md §5).
--
-- Settles the first AI feature with no model, no dataset, and no Edge Function:
-- similarity is computed by pg_trgm inside the database, from an AFTER INSERT
-- trigger. Zero code runs on the student's critical path.
--
-- HONOURS AN ENFORCED INVARIANT (the whole reason this is a trigger):
-- can_create_report() (rls_security.sql:101-127) requires p_ai_confidence is
-- null AND p_duplicate_of is null for students, so nothing may be classified or
-- linked at insert time. AFTER INSERT is the earliest legal point.
--
-- NEVER FAILS A SUBMISSION (§2.7): the body catches all exceptions and returns
-- NEW, so a broken extension or a bug leaves duplicate_of IS NULL - which is
-- exactly the state can_create_report() expects, so a failed run leaves no
-- invalid state. Detection only ever flags; no report is rejected, merged,
-- hidden, or closed.
--
-- This is the one AI feature that can ship today without the Supabase CLI being
-- installed - it is a migration and nothing else. Apply in the SQL Editor.

-- 1. Trigram support. similarity() has no meaning without it.
create extension if not exists pg_trgm;

-- 2. Expression index. The score is computed on title||' '||description
--    (§2.4), so the index must be on that same expression or the planner cannot
--    use it. gin_trgm_ops is what makes similarity()/ILIKE index-backed.
--    Column order is irrelevant here: one column, one operator class.
create index if not exists reports_text_trgm_idx
  on public.reports using gin ((title || ' ' || description) gin_trgm_ops);

-- 3. Best-match search. Returns the most similar earlier report in the same
--    community, or NULL.
--
--    SECURITY DEFINER (AI_ARCHITECTURE §5): the database is the only component
--    with reliable access to report text under the RLS model. This widens
--    privilege, so the function takes only a report id and re-derives
--    everything from reports - it never accepts caller-supplied text, and its
--    output is a single uuid that reveals nothing beyond "a similar report
--    exists in your own community".
--
--    Candidate filters, each earning its place:
--      deleted_at is null        - skip moderated reports
--      same community_id (§2.3)   - never compare across communities; this is
--                                   the privacy boundary
--      same category_id  (§2.4)   - narrows the candidate set so the index is
--                                   used, and score reflects real overlap
--                                   rather than one shared word
--      created_at <= new         - no forward matching; a report cannot be a
--                                   duplicate of one that does not exist yet
--      duplicate_of is null (§2.6)- keeps duplicate_of pointing at a canonical
--                                   root, so chains (C -> B -> A) cannot form
--    Ties break on (created_at, id) so the oldest match is deterministic and
--    repeated runs never disagree.
--
--    Threshold is a parameter, NOT pg_trgm.similarity_threshold (§2.5): that GUC
--    is global and would silently change every other trigram use.
create or replace function public.find_duplicate_report(
  p_report_id uuid,
  p_threshold real default 0.85
)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select c.id
  from public.reports n
  join public.reports c
    on c.community_id = n.community_id
   and c.category_id = n.category_id
   and c.deleted_at is null
   and c.duplicate_of is null
   and (c.created_at, c.id) <= (n.created_at, n.id)
   and c.id <> n.id
   and similarity(c.title || ' ' || c.description,
                  n.title || ' ' || n.description) >= p_threshold
  where n.id = p_report_id
    and n.deleted_at is null
  order by c.created_at, c.id
  limit 1;
$$;

-- Owner-only, like every other server helper (rls_security.sql, phase 2.10).
-- No client role may call this: the trigger is the only intended path.
revoke all on function public.find_duplicate_report(uuid, real) from public;

-- 4. Trigger body. Appends exactly one log row per insert (§2.7: a failed run
--    is invisible, not half-written).
--
--    ai_classification_log requires classification/priority_prediction to be
--    NOT NULL, but AI-1 produces neither - ADR-003 §2.8 keeps those phases
--    unauthorised. Empty objects record "not attempted" honestly, which is
--    preferable to a fabricated 0.0 confidence that would read as a real
--    prediction. model_version names the method, not a model: 'pg_trgm' is a
--    database function, and calling it a model version would imply training
--    that does not exist (ADR-003 §1.1).
create or replace function public.trg_flag_duplicate_report()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_match uuid;
begin
  v_match := public.find_duplicate_report(new.id);

  if v_match is not null then
    -- Safe to UPDATE from a trigger: all three existing UPDATE triggers on
    -- reports are guarded by when (OLD.status is distinct from NEW.status) or
    -- when (OLD.deleted_at is distinct from NEW.deleted_at)
    -- (server_generated_events.sql), and this touches neither column - so
    -- flagging a duplicate cannot emit a spurious activity-log row, status
    -- notification, or terminal-state guard.
    update public.reports
       set duplicate_of = v_match,
           updated_at = now()
     where id = new.id;
  end if;

  insert into public.ai_classification_log (
    report_id, raw_input, classification, priority_prediction,
    duplicate_check, model_version
  ) values (
    new.id,
    left(new.title || ' ' || new.description, 2000),
    '{}'::jsonb,
    '{}'::jsonb,
    jsonb_build_object(
      'is_duplicate', v_match is not null,
      'similar_report_id', v_match,
      'similarity_score',
        case when v_match is null then 0.0
             else round((similarity(
               (select title || ' ' || description from public.reports where id = v_match),
               new.title || ' ' || new.description))::numeric, 4)
        end
    ),
    'pg_trgm/ai1'
  );

  return new;
exception
  when others then
    -- Swallow deliberately. The report is already inserted and must remain
    -- fully usable; a raised error here would roll back a student's submission.
    return new;
end;
$$;

-- AFTER, not BEFORE: BEFORE cannot write duplicate_of on a row that does not
-- exist yet, and classification before insert is forbidden outright (§2.2).
drop trigger if exists reports_after_insert_flag_duplicate on public.reports;

create trigger reports_after_insert_flag_duplicate
  after insert on public.reports
  for each row execute function public.trg_flag_duplicate_report();

-- ---------------------------------------------------------------------------
-- Verify after applying. Expect two rows, similarity well above 0.85:
--
--   select r.title, r.duplicate_of is not null as flagged,
--          l.duplicate_check
--     from public.reports r
--     join public.ai_classification_log l on l.report_id = r.id
--    where r.created_at > now() - interval '10 minutes'
--    order by r.created_at;
--
-- The SECOND insert of a near-identical report is the one that must flag.
--
-- To disable without dropping the migration (e.g. false positives in testing):
--   alter table public.reports disable trigger reports_after_insert_flag_duplicate;
-- ---------------------------------------------------------------------------
