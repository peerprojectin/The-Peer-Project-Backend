alter table public.interview_questions rename to questionnaire_questions;
alter table public.interview_invites rename to questionnaire_invites;
alter table public.interview_answers rename to questionnaire_answers;

do $$
declare
  item record;
begin
  for item in
    select c.conname, t.relname
    from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = 'public' and c.conname like 'interview\_%'
  loop
    execute format(
      'alter table public.%I rename constraint %I to %I',
      item.relname, item.conname, replace(item.conname, 'interview_', 'questionnaire_')
    );
  end loop;

  for item in
    select s.relname, case s.relkind when 'S' then 'sequence' else 'index' end as kind
    from pg_class s
    join pg_namespace n on n.oid = s.relnamespace
    where n.nspname = 'public' and s.relkind in ('S', 'i') and s.relname like 'interview\_%'
  loop
    execute format(
      'alter %s public.%I rename to %I',
      item.kind, item.relname, replace(item.relname, 'interview_', 'questionnaire_')
    );
  end loop;
end;
$$;

drop function public.submit_interview(text, jsonb);

create or replace function public.submit_mentor(application jsonb, proof text, invite_hash text)
returns bigint
language plpgsql
set search_path = ''
as $$
declare
  cohort bigint := public.open_cohort('mentor');
  new_id bigint;
  tracks text[] := public.text_array(application -> 'tracks');
begin
  if cohort is null then
    raise exception 'applications_closed';
  end if;

  if exists (
    select 1 from jsonb_array_elements(coalesce(application -> 'help_areas', '[]')) h
    where not (h ->> 'track' = any (tracks))
  ) then
    raise exception 'help_area_track';
  end if;

  insert into public.mentors (
    cohort_id, display_name, current_status, tracks, exam_results, board, board_other, subjects,
    subjects_other, abroad_details, availability, mentor_capacity, language_preferences,
    language_other, discord_username, reddit_username, email, other_profiles, heard_from,
    additional_info, is_returning, has_verification_consent, has_data_consent,
    proof_path, proof_uploaded_at
  ) values (
    cohort,
    application ->> 'display_name',
    application ->> 'current_status',
    tracks,
    application ->> 'exam_results',
    application ->> 'board',
    nullif(application ->> 'board_other', ''),
    public.text_array(application -> 'subjects'),
    nullif(application ->> 'subjects_other', ''),
    nullif(application ->> 'abroad_details', ''),
    application ->> 'availability',
    (application ->> 'mentor_capacity')::smallint,
    public.text_array(application -> 'language_preferences'),
    nullif(application ->> 'language_other', ''),
    application ->> 'discord_username',
    nullif(application ->> 'reddit_username', ''),
    application ->> 'email',
    public.text_array(application -> 'other_profiles'),
    public.text_array(application -> 'heard_from'),
    nullif(application ->> 'additional_info', ''),
    coalesce((application ->> 'is_returning')::boolean, false),
    coalesce((application ->> 'has_verification_consent')::boolean, false),
    coalesce((application ->> 'has_data_consent')::boolean, false),
    proof,
    now()
  )
  returning id into new_id;

  insert into public.mentor_help_areas (mentor_id, track, area, area_other)
  select new_id, h ->> 'track', h ->> 'area', nullif(h ->> 'area_other', '')
  from jsonb_array_elements(coalesce(application -> 'help_areas', '[]')) h;

  insert into public.questionnaire_invites (mentor_id, token_hash, expires_at)
  values (new_id, invite_hash, now() + interval '7 days');

  return new_id;
end;
$$;

create or replace function public.submit_questionnaire(invite_hash text, answers jsonb)
returns void
language plpgsql
set search_path = ''
as $$
declare
  invite public.questionnaire_invites;
  cohort bigint;
begin
  select * into invite from public.questionnaire_invites where token_hash = invite_hash for update;

  if invite.id is null then
    raise exception 'invite_invalid';
  end if;
  if invite.submitted_at is not null then
    raise exception 'questionnaire_submitted';
  end if;
  if invite.expires_at <= now() then
    raise exception 'invite_expired';
  end if;

  select cohort_id into cohort from public.mentors where id = invite.mentor_id;

  if exists (
    select 1 from public.questionnaire_questions q
    where q.cohort_id = cohort and q.is_active
      and not exists (
        select 1 from jsonb_array_elements(answers) a
        where (a ->> 'question_id')::bigint = q.id and char_length(btrim(a ->> 'answer')) > 0
      )
  ) then
    raise exception 'answers_incomplete';
  end if;

  insert into public.questionnaire_answers (mentor_id, question_id, answer)
  select invite.mentor_id, q.id, btrim(a ->> 'answer')
  from jsonb_array_elements(answers) a
  join public.questionnaire_questions q on q.id = (a ->> 'question_id')::bigint
  where q.cohort_id = cohort and q.is_active;

  update public.questionnaire_invites set submitted_at = now() where id = invite.id;
end;
$$;

revoke execute on function public.submit_questionnaire from public, anon, authenticated;
grant execute on function public.submit_questionnaire to service_role;
