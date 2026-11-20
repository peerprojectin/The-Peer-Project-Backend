create table public.login_attempts (
  email text primary key,
  failures smallint not null default 0,
  first_failed_at timestamptz not null default now(),
  locked_until timestamptz,
  last_ip text,
  updated_at timestamptz not null default now()
);

alter table public.login_attempts enable row level security;
revoke all on public.login_attempts from anon, authenticated;
grant select, insert, update, delete on public.login_attempts to service_role;

create or replace function public.record_login_failure(attempt_email text, attempt_ip text)
returns table (attempt_count smallint, lock_expires_at timestamptz, just_locked boolean)
language plpgsql
set search_path = ''
as $$
declare
  entry public.login_attempts;
begin
  insert into public.login_attempts as la (email, failures, first_failed_at, last_ip)
  values (attempt_email, 1, now(), attempt_ip)
  on conflict (email) do update set
    failures = case
      when la.first_failed_at < now() - interval '1 hour' or la.locked_until <= now() then 1
      else la.failures + 1
    end,
    first_failed_at = case
      when la.first_failed_at < now() - interval '1 hour' or la.locked_until <= now() then now()
      else la.first_failed_at
    end,
    locked_until = case
      when la.locked_until <= now() then null
      else la.locked_until
    end,
    last_ip = excluded.last_ip,
    updated_at = now()
  returning * into entry;

  if entry.failures >= 3 and entry.locked_until is null then
    update public.login_attempts
    set locked_until = now() + interval '1 hour'
    where email = attempt_email
    returning * into entry;
    return query select entry.failures, entry.locked_until, true;
  else
    return query select entry.failures, entry.locked_until, false;
  end if;
end;
$$;

revoke execute on function public.record_login_failure from public, anon, authenticated;
grant execute on function public.record_login_failure to service_role;

create or replace function public.custom_access_token_hook(event jsonb)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
begin
  if exists (
    select 1 from public.login_attempts
    where email = lower(event -> 'claims' ->> 'email') and locked_until > now()
  ) then
    return jsonb_build_object(
      'error', jsonb_build_object('http_code', 403, 'message', 'This account is locked for now. Try again later.')
    );
  end if;
  return jsonb_build_object('claims', event -> 'claims');
end;
$$;

grant usage on schema public to supabase_auth_admin;
grant execute on function public.custom_access_token_hook to supabase_auth_admin;
revoke execute on function public.custom_access_token_hook from public, anon, authenticated;
grant select on public.login_attempts to supabase_auth_admin;

create policy login_attempts_auth_admin_read on public.login_attempts
  for select to supabase_auth_admin using (true);
