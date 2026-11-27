-- Trabajos de pg_cron (solo Supabase). Requiere supabase/001_extensiones.sql y dos secretos en
-- Vault, creados a mano y fuera del repositorio (ver docs/despliegue-supabase.md):
--   kairo_api_url          URL base de la API, sin la ruta
--   kairo_interno_secret   el mismo INTERNO_SECRET que tiene Railway
-- cron.schedule con un nombre existente reemplaza el job, asi que el archivo es idempotente.
-- El despacho de recordatorios se programa aparte, en 002, cuando la API use su propio pool.

-- La funcion que lee Vault y llama a la API vive en un esquema propio que no expone la Data API,
-- y su dueno es postgres: kairo_owner no necesita acceso a vault ni a net.
create schema if not exists kairo_cron;
revoke all on schema kairo_cron from public;
grant usage on schema kairo_cron to kairo_worker;

create or replace function kairo_cron.despachar_recordatorios() returns bigint
language plpgsql security definer set search_path = pg_catalog, pg_temp
as $$
declare
    v_url text;
    v_secreto text;
begin
    select decrypted_secret into v_url
    from vault.decrypted_secrets where name = 'kairo_api_url';
    select decrypted_secret into v_secreto
    from vault.decrypted_secrets where name = 'kairo_interno_secret';

    if v_url is null or v_secreto is null then
        raise exception 'Faltan los secretos kairo_api_url o kairo_interno_secret en Vault';
    end if;

    return net.http_post(
        url := rtrim(v_url, '/') || '/api/v1/interno/recordatorios/despachar',
        body := '{}'::jsonb,
        headers := jsonb_build_object(
            'Authorization', 'Bearer ' || v_secreto,
            'Content-Type', 'application/json'
        ),
        timeout_milliseconds := 20000
    );
end
$$;

comment on function kairo_cron.despachar_recordatorios() is
'Pide a la API que despache los recordatorios vencidos. Lee la URL y el secreto de Vault.';

revoke all on function kairo_cron.despachar_recordatorios() from public;
grant execute on function kairo_cron.despachar_recordatorios() to kairo_worker;

-- Evaluacion de metas: a los 10 minutos de cada hora, como kairo_worker.
select cron.schedule(
    'kairo-evaluar-metas',
    '10 * * * *',
    $job$ set local role kairo_worker; select public.kairo_evaluar_metas(); $job$
);
