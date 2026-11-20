drop function public.submit_mentee(jsonb);
drop function public.submit_mentor(jsonb, text, text);

create or replace function public.submit_mentee(application jsonb, force_cohort bigint default null)
returns bigint
language plpgsql
set search_path = ''
as $$
declare
  cohort bigint := coalesce(force_cohort, public.open_cohort('mentee'));
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

  insert into public.mentees (
    cohort_id, display_name, age, class_level, board, board_other, subjects, subjects_other,
    tracks, target_year, help_in, availability, availability_other, language_preferences, language_other,
    discord_username, reddit_username, email, heard_from, additional_info, is_returning,
    has_guardian_consent, has_data_consent
  ) values (
    cohort,
    application ->> 'display_name',
    (application ->> 'age')::smallint,
    application ->> 'class_level',
    application ->> 'board',
    nullif(application ->> 'board_other', ''),
    public.text_array(application -> 'subjects'),
    nullif(application ->> 'subjects_other', ''),
    tracks,
    (application ->> 'target_year')::smallint,
    application ->> 'help_in',
    application ->> 'availability',
    nullif(application ->> 'availability_other', ''),
    public.text_array(application -> 'language_preferences'),
    nullif(application ->> 'language_other', ''),
    application ->> 'discord_username',
    nullif(application ->> 'reddit_username', ''),
    application ->> 'email',
    public.text_array(application -> 'heard_from'),
    nullif(application ->> 'additional_info', ''),
    coalesce((application ->> 'is_returning')::boolean, false),
    coalesce((application ->> 'has_guardian_consent')::boolean, false),
    coalesce((application ->> 'has_data_consent')::boolean, false)
  )
  returning id into new_id;

  insert into public.mentee_help_areas (mentee_id, track, area, area_other)
  select new_id, h ->> 'track', h ->> 'area', nullif(h ->> 'area_other', '')
  from jsonb_array_elements(coalesce(application -> 'help_areas', '[]')) h;

  return new_id;
end;
$$;

create or replace function public.submit_mentor(application jsonb, proof text, invite_hash text, force_cohort bigint default null)
returns bigint
language plpgsql
set search_path = ''
as $$
declare
  cohort bigint := coalesce(force_cohort, public.open_cohort('mentor'));
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
    subjects_other, abroad_details, availability, availability_other, mentor_capacity, language_preferences,
    language_other, discord_username, reddit_username, email, other_profiles, heard_from,
    additional_info, is_returning, has_data_consent,
    proof_path, proof_uploaded_at
  ) values (
    cohort,
    application ->> 'display_name',
    application ->> 'current_status',
    tracks,
    public.text_array(application -> 'mentee_levels'),
    nullif(application ->> 'exam_results', ''),
    application ->> 'board',
    nullif(application ->> 'board_other', ''),
    public.text_array(application -> 'subjects'),
    nullif(application ->> 'subjects_other', ''),
    nullif(application ->> 'abroad_details', ''),
    application ->> 'availability',
    nullif(application ->> 'availability_other', ''),
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

revoke execute on function public.submit_mentee, public.submit_mentor from public, anon, authenticated;
grant execute on function public.submit_mentee, public.submit_mentor to service_role;
