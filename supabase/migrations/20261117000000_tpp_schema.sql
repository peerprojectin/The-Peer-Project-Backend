create extension if not exists vector with schema extensions;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table public.cohorts (
  id bigint generated always as identity primary key,
  name text not null unique,
  mentee_opens_at timestamptz,
  mentee_closes_at timestamptz,
  mentor_opens_at timestamptz,
  mentor_closes_at timestamptz,
  created_at timestamptz not null default now(),
  constraint cohorts_mentee_window check (mentee_closes_at is null or mentee_opens_at is null or mentee_closes_at > mentee_opens_at),
  constraint cohorts_mentor_window check (mentor_closes_at is null or mentor_opens_at is null or mentor_closes_at > mentor_opens_at)
);

create table public.admins (
  id bigint generated always as identity primary key,
  username text not null unique,
  password_hash text not null,
  role text not null default 'admin' check (role in ('admin', 'reviewer')),
  email text not null,
  discord_id text unique,
  created_at timestamptz not null default now()
);

create table public.help_area_options (
  track text not null check (track in ('boards', 'jee', 'neet', 'cuet', 'clat_ipmat', 'iat', 'abroad', 'other')),
  area text not null,
  label text not null,
  position smallint not null,
  primary key (track, area)
);

insert into public.help_area_options (track, area, label, position) values
  ('boards', 'english', 'English', 1),
  ('boards', 'physics', 'Physics', 2),
  ('boards', 'chemistry', 'Chemistry', 3),
  ('boards', 'mathematics', 'Mathematics', 4),
  ('boards', 'biology', 'Biology', 5),
  ('boards', 'computer_science', 'Computer Science', 6),
  ('boards', 'accountancy', 'Accountancy', 7),
  ('boards', 'business_studies', 'Business Studies', 8),
  ('boards', 'economics', 'Economics', 9),
  ('boards', 'history', 'History', 10),
  ('boards', 'political_science', 'Political Science', 11),
  ('boards', 'geography', 'Geography', 12),
  ('boards', 'psychology', 'Psychology', 13),
  ('boards', 'answer_writing', 'Answer writing / presentation', 14),
  ('boards', 'time_management', 'Time management / study habits', 15),
  ('boards', 'other', 'Other', 16),

  ('jee', 'mathematics', 'Mathematics', 1),
  ('jee', 'physics', 'Physics', 2),
  ('jee', 'chemistry', 'Chemistry', 3),
  ('jee', 'mock_tests', 'Mock tests / exam strategy', 4),
  ('jee', 'counselling', 'Counselling / college choice', 5),
  ('jee', 'time_management', 'Time management / study habits', 6),
  ('jee', 'other', 'Other', 7),

  ('neet', 'biology', 'Biology', 1),
  ('neet', 'physics', 'Physics', 2),
  ('neet', 'chemistry', 'Chemistry', 3),
  ('neet', 'mock_tests', 'Mock tests / exam strategy', 4),
  ('neet', 'counselling', 'Counselling / college choice', 5),
  ('neet', 'time_management', 'Time management / study habits', 6),
  ('neet', 'other', 'Other', 7),

  ('cuet', 'domain_subjects', 'Domain subjects', 1),
  ('cuet', 'general_test', 'General test', 2),
  ('cuet', 'language', 'Language section', 3),
  ('cuet', 'time_management', 'Time management / study habits', 4),
  ('cuet', 'other', 'Other', 5),

  ('clat_ipmat', 'legal_reasoning', 'Legal reasoning', 1),
  ('clat_ipmat', 'logical_reasoning', 'Logical reasoning', 2),
  ('clat_ipmat', 'quantitative', 'Quantitative', 3),
  ('clat_ipmat', 'english_rc', 'English / reading comprehension', 4),
  ('clat_ipmat', 'current_affairs', 'Current affairs / GK', 5),
  ('clat_ipmat', 'time_management', 'Time management / study habits', 6),
  ('clat_ipmat', 'other', 'Other', 7),

  ('iat', 'physics', 'Physics', 1),
  ('iat', 'chemistry', 'Chemistry', 2),
  ('iat', 'mathematics', 'Mathematics', 3),
  ('iat', 'biology', 'Biology', 4),
  ('iat', 'time_management', 'Time management / study habits', 5),
  ('iat', 'other', 'Other', 6),

  ('abroad', 'choosing_universities', 'Choosing countries / universities', 1),
  ('abroad', 'sat_act', 'SAT / ACT', 2),
  ('abroad', 'essays_sop', 'Essays / SOP', 3),
  ('abroad', 'applications_lors', 'Applications and recommendation letters', 4),
  ('abroad', 'financial_aid', 'Financial aid / scholarships', 5),
  ('abroad', 'visa', 'Visa', 6),
  ('abroad', 'other', 'Other', 7),

  ('other', 'other', 'Other', 1);

create table public.mentees (
  id bigint generated always as identity primary key,
  cohort_id bigint not null references public.cohorts (id),
  status text not null default 'pending' check (status in ('pending', 'accepted', 'waitlisted', 'rejected', 'withdrawn')),

  display_name text not null check (char_length(display_name) between 1 and 40),
  age smallint not null check (age between 10 and 25),
  class_level text not null check (class_level in ('9', '10', '11', '12', 'gap_year')),
  board text not null check (board in ('cbse', 'icse_isc', 'state', 'ib', 'cambridge', 'other')),
  board_other text,
  subjects text[] not null default '{}' check (subjects <@ array[
    'english', 'physics', 'chemistry', 'mathematics', 'biology', 'computer_science', 'accountancy',
    'business_studies', 'economics', 'history', 'political_science', 'geography', 'psychology'
  ]::text[]),
  subjects_other text,
  tracks text[] not null check (
    cardinality(tracks) > 0
    and tracks <@ array['boards', 'jee', 'neet', 'cuet', 'clat_ipmat', 'iat', 'abroad', 'other']::text[]
  ),
  target_year smallint not null check (target_year between 2026 and 2035),
  help_in text not null check (char_length(help_in) between 1 and 4000),
  availability text not null check (availability in ('1_2', '3_4', 'flexible')),
  language_preferences text[] not null check (
    cardinality(language_preferences) > 0
    and language_preferences <@ array['english', 'hindi', 'hinglish', 'other']::text[]
  ),
  language_other text,

  discord_username text not null,
  discord_id text,
  reddit_username text,
  email text not null,

  heard_from text[] not null default '{}' check (heard_from <@ array[
    'reddit_cbse', 'reddit_icse', 'reddit_jee', 'reddit_indiancolleges', 'discord', 'twitter', 'word_of_mouth', 'other'
  ]::text[]),
  additional_info text check (char_length(additional_info) <= 4000),
  is_returning boolean not null default false,

  has_guardian_consent boolean not null default false,
  has_data_consent boolean not null check (has_data_consent),
  is_verified boolean not null default false,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint mentees_guardian_consent check (age >= 18 or has_guardian_consent),
  constraint mentees_subjects_senior_only check (
    class_level in ('11', '12', 'gap_year') or (subjects = '{}' and subjects_other is null)
  ),
  constraint mentees_subjects_required check (
    class_level not in ('11', '12', 'gap_year') or cardinality(subjects) > 0 or subjects_other is not null
  ),
  constraint mentees_board_other check ((board = 'other') = (board_other is not null))
);

create unique index mentees_cohort_email_key on public.mentees (cohort_id, lower(email));
create unique index mentees_cohort_discord_username_key on public.mentees (cohort_id, lower(discord_username));
create unique index mentees_cohort_discord_id_key on public.mentees (cohort_id, discord_id) where discord_id is not null;
create index mentees_cohort_status_idx on public.mentees (cohort_id, status);

create trigger mentees_set_updated_at before update on public.mentees
  for each row execute function public.set_updated_at();

create table public.mentee_help_areas (
  id bigint generated always as identity primary key,
  mentee_id bigint not null references public.mentees (id) on delete cascade,
  track text not null,
  area text not null,
  area_other text check (char_length(area_other) <= 200),
  foreign key (track, area) references public.help_area_options (track, area),
  unique (mentee_id, track, area),
  constraint mentee_help_areas_other check ((area = 'other') = (area_other is not null))
);

create table public.mentors (
  id bigint generated always as identity primary key,
  cohort_id bigint not null references public.cohorts (id),
  status text not null default 'pending' check (status in ('pending', 'shortlisted', 'accepted', 'rejected', 'withdrawn')),

  display_name text not null check (char_length(display_name) between 1 and 40),
  current_status text not null check (char_length(current_status) between 1 and 200),
  tracks text[] not null check (
    cardinality(tracks) > 0
    and tracks <@ array['boards', 'jee', 'neet', 'cuet', 'clat_ipmat', 'iat', 'abroad', 'other']::text[]
  ),
  exam_results text not null check (char_length(exam_results) between 1 and 2000),
  board text not null check (board in ('cbse', 'icse_isc', 'state', 'ib', 'cambridge', 'other')),
  board_other text,
  subjects text[] not null default '{}' check (subjects <@ array[
    'english', 'physics', 'chemistry', 'mathematics', 'biology', 'computer_science', 'accountancy',
    'business_studies', 'economics', 'history', 'political_science', 'geography', 'psychology'
  ]::text[]),
  subjects_other text,
  abroad_details text check (char_length(abroad_details) <= 2000),
  availability text not null check (availability in ('1_2', '3_4', 'flexible')),
  mentor_capacity smallint not null check (mentor_capacity between 1 and 3),
  language_preferences text[] not null check (
    cardinality(language_preferences) > 0
    and language_preferences <@ array['english', 'hindi', 'hinglish', 'other']::text[]
  ),
  language_other text,

  discord_username text not null,
  discord_id text,
  reddit_username text,
  email text not null,
  other_profiles text[] not null default '{}' check (cardinality(other_profiles) <= 3),

  heard_from text[] not null default '{}' check (heard_from <@ array[
    'reddit_cbse', 'reddit_icse', 'reddit_jee', 'reddit_indiancolleges', 'discord', 'twitter', 'word_of_mouth', 'other'
  ]::text[]),
  additional_info text check (char_length(additional_info) <= 4000),
  is_returning boolean not null default false,

  has_verification_consent boolean not null check (has_verification_consent),
  has_data_consent boolean not null check (has_data_consent),
  proof_path text,
  proof_uploaded_at timestamptz,
  proof_deleted_at timestamptz,
  is_verified boolean not null default false,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint mentors_subjects_required check (cardinality(subjects) > 0 or subjects_other is not null),
  constraint mentors_abroad_details check (not ('abroad' = any (tracks)) or abroad_details is not null),
  constraint mentors_board_other check ((board = 'other') = (board_other is not null))
);

create unique index mentors_cohort_email_key on public.mentors (cohort_id, lower(email));
create unique index mentors_cohort_discord_username_key on public.mentors (cohort_id, lower(discord_username));
create unique index mentors_cohort_discord_id_key on public.mentors (cohort_id, discord_id) where discord_id is not null;
create index mentors_cohort_status_idx on public.mentors (cohort_id, status);
create index mentors_proof_pending_idx on public.mentors (proof_uploaded_at)
  where proof_path is not null and proof_deleted_at is null;

create trigger mentors_set_updated_at before update on public.mentors
  for each row execute function public.set_updated_at();

create table public.mentor_help_areas (
  id bigint generated always as identity primary key,
  mentor_id bigint not null references public.mentors (id) on delete cascade,
  track text not null,
  area text not null,
  area_other text check (char_length(area_other) <= 200),
  foreign key (track, area) references public.help_area_options (track, area),
  unique (mentor_id, track, area),
  constraint mentor_help_areas_other check ((area = 'other') = (area_other is not null))
);

create index mentee_help_areas_track_area_idx on public.mentee_help_areas (track, area);
create index mentor_help_areas_track_area_idx on public.mentor_help_areas (track, area);

create table public.interview_questions (
  id bigint generated always as identity primary key,
  cohort_id bigint not null references public.cohorts (id),
  position smallint not null,
  prompt text not null,
  is_active boolean not null default true,
  unique (cohort_id, position)
);

create table public.interview_invites (
  id bigint generated always as identity primary key,
  mentor_id bigint not null unique references public.mentors (id) on delete cascade,
  token_hash text not null unique,
  expires_at timestamptz not null,
  email_sends smallint not null default 0 check (email_sends between 0 and 3),
  last_emailed_at timestamptz,
  started_at timestamptz,
  submitted_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.interview_answers (
  id bigint generated always as identity primary key,
  mentor_id bigint not null references public.mentors (id) on delete cascade,
  question_id bigint not null references public.interview_questions (id),
  answer text not null check (char_length(answer) between 1 and 4000),
  created_at timestamptz not null default now(),
  unique (mentor_id, question_id)
);

create table public.mentor_reviews (
  id bigint generated always as identity primary key,
  mentor_id bigint not null references public.mentors (id) on delete cascade,
  reviewer_id bigint references public.admins (id) on delete set null,
  empathy smallint check (empathy between 1 and 5),
  boundaries smallint check (boundaries between 1 and 5),
  practicality smallint check (practicality between 1 and 5),
  honesty smallint check (honesty between 1 and 5),
  notes text,
  decision text not null check (decision in ('shortlist', 'reject', 'follow_up')),
  created_at timestamptz not null default now(),
  unique (mentor_id, reviewer_id)
);

create table public.proof_access_log (
  id bigint generated always as identity primary key,
  mentor_id bigint references public.mentors (id) on delete set null,
  admin_id bigint references public.admins (id) on delete set null,
  accessed_at timestamptz not null default now()
);

create table public.assignments (
  id bigint generated always as identity primary key,
  cohort_id bigint not null references public.cohorts (id),
  mentee_id bigint not null references public.mentees (id),
  mentor_id bigint not null references public.mentors (id),
  status text not null default 'pending' check (status in ('pending', 'active', 'completed', 'cancelled')),
  confidence_score real check (confidence_score between 0 and 1),
  reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index assignments_one_live_per_mentee on public.assignments (mentee_id)
  where status in ('pending', 'active');
create index assignments_mentor_idx on public.assignments (mentor_id);

create trigger assignments_set_updated_at before update on public.assignments
  for each row execute function public.set_updated_at();

create table public.mentee_embeddings (
  mentee_id bigint primary key references public.mentees (id) on delete cascade,
  embedding extensions.halfvec(2048) not null,
  model text not null,
  created_at timestamptz not null default now()
);

create table public.mentor_embeddings (
  mentor_id bigint primary key references public.mentors (id) on delete cascade,
  embedding extensions.halfvec(2048) not null,
  model text not null,
  created_at timestamptz not null default now()
);

create index mentee_embeddings_hnsw on public.mentee_embeddings
  using hnsw (embedding extensions.halfvec_cosine_ops);
create index mentor_embeddings_hnsw on public.mentor_embeddings
  using hnsw (embedding extensions.halfvec_cosine_ops);

create or replace function public.match_mentors(
  query_embedding extensions.halfvec(2048),
  match_cohort_id bigint,
  match_count integer default 10
)
returns table (mentor_id bigint, similarity double precision)
language sql
stable
set search_path = ''
as $$
  select me.mentor_id, 1 - (me.embedding operator(extensions.<=>) query_embedding) as similarity
  from public.mentor_embeddings me
  join public.mentors m on m.id = me.mentor_id
  where m.is_verified and m.status = 'accepted' and m.cohort_id = match_cohort_id
  order by me.embedding operator(extensions.<=>) query_embedding
  limit match_count;
$$;

create or replace function public.match_mentees(
  query_embedding extensions.halfvec(2048),
  match_cohort_id bigint,
  match_count integer default 10
)
returns table (mentee_id bigint, similarity double precision)
language sql
stable
set search_path = ''
as $$
  select me.mentee_id, 1 - (me.embedding operator(extensions.<=>) query_embedding) as similarity
  from public.mentee_embeddings me
  join public.mentees m on m.id = me.mentee_id
  where m.is_verified and m.status = 'accepted' and m.cohort_id = match_cohort_id
  order by me.embedding operator(extensions.<=>) query_embedding
  limit match_count;
$$;

alter table public.cohorts enable row level security;
alter table public.admins enable row level security;
alter table public.help_area_options enable row level security;
alter table public.mentees enable row level security;
alter table public.mentee_help_areas enable row level security;
alter table public.mentors enable row level security;
alter table public.mentor_help_areas enable row level security;
alter table public.interview_questions enable row level security;
alter table public.interview_invites enable row level security;
alter table public.interview_answers enable row level security;
alter table public.mentor_reviews enable row level security;
alter table public.proof_access_log enable row level security;
alter table public.assignments enable row level security;
alter table public.mentee_embeddings enable row level security;
alter table public.mentor_embeddings enable row level security;

revoke all on all tables in schema public from anon, authenticated;
revoke execute on function public.match_mentors, public.match_mentees, public.set_updated_at from public, anon, authenticated;

grant select, insert, update, delete on all tables in schema public to service_role;
grant usage, select on all sequences in schema public to service_role;
grant execute on function public.match_mentors, public.match_mentees to service_role;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('proofs', 'proofs', false, 5242880, array['image/jpeg', 'image/png', 'application/pdf'])
on conflict (id) do nothing;
