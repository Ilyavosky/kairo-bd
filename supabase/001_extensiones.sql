-- Preparacion de Supabase para los trabajos de cron/ (decision 006, D2). Solo Supabase: la CI no
-- tiene estas extensiones. Idempotente.

create extension if not exists pg_cron;
create extension if not exists pg_net;

-- Los jobs ejecutan "set local role kairo_worker"; postgres necesita SET sobre ese rol.
-- Postgres 16+ no se lo da al creador del rol.
do $$
begin
    execute format('grant kairo_worker to %I with set true', current_user);
end
$$;
