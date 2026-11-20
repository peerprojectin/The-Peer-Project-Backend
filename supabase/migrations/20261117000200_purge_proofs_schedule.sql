create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net with schema extensions;

select cron.schedule(
  'purge-expired-proofs',
  '30 20 * * *',
  $$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/purge-proofs',
    headers := jsonb_build_object(
      'content-type', 'application/json',
      'x-purge-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'purge_secret')
    ),
    body := '{}'::jsonb
  );
  $$
);
