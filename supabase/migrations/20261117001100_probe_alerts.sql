create table public.alert_log (
  kind text primary key,
  last_sent_at timestamptz not null
);

alter table public.alert_log enable row level security;
revoke all on public.alert_log from anon, authenticated;
grant select, insert, update, delete on public.alert_log to service_role;

create or replace function public.claim_alert(alert_kind text, cooldown interval)
returns boolean
language plpgsql
set search_path = ''
as $$
declare
  claimed boolean;
begin
  insert into public.alert_log as log (kind, last_sent_at)
  values (alert_kind, now())
  on conflict (kind) do update set last_sent_at = now()
  where log.last_sent_at < now() - cooldown
  returning true into claimed;
  return coalesce(claimed, false);
end;
$$;

revoke execute on function public.claim_alert from public, anon, authenticated;
grant execute on function public.claim_alert to service_role;
