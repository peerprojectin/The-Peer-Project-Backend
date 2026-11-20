alter table public.mentors
  add column mentee_levels text[] not null default '{}' check (
    mentee_levels <@ array['9', '10', '11', '12', 'gap_year']::text[]
  );

alter table public.mentors
  add constraint mentors_mentee_levels_required check (cardinality(mentee_levels) > 0);

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
    cohort_id, display_name, current_status, tracks, mentee_levels, exam_results, board, board_other, subjects,
    subjects_other, abroad_details, availability, mentor_capacity, language_preferences,
    language_other, discord_username, reddit_username, email, other_profiles, heard_from,
    additional_info, is_returning, has_verification_consent, has_data_consent,
    proof_path, proof_uploaded_at
  ) values (
    cohort,
    application ->> 'display_name',
    application ->> 'current_status',
    tracks,
    public.text_array(application -> 'mentee_levels'),
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
