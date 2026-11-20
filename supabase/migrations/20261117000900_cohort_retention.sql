alter table public.cohorts
  add column ends_at timestamptz;

create or replace function public.purge_expired_cohorts()
returns void
language plpgsql
set search_path = ''
as $$
declare
  expired bigint[];
begin
  select coalesce(array_agg(id), '{}') into expired
  from public.cohorts
  where ends_at is not null and ends_at + interval '3 months' < now();

  if cardinality(expired) = 0 then
    return;
  end if;

  delete from public.assignments where cohort_id = any (expired);
  delete from public.mentees where cohort_id = any (expired);
  delete from public.mentors
  where cohort_id = any (expired)
    and (proof_path is null or proof_deleted_at is not null);
end;
$$;

revoke execute on function public.purge_expired_cohorts from public, anon, authenticated;

select cron.schedule('purge-expired-cohorts', '45 20 * * *', 'select public.purge_expired_cohorts()');
