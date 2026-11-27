-- Despacho de recordatorios cada 5 minutos, como kairo_worker (solo Supabase).
-- Se aplica cuando la API ya tiene desplegado el pool de kairo_despachador
-- (DATABASE_URL_WORKER) y despues de cron/001_programar_tareas.sql.
select cron.schedule(
    'kairo-despachar-recordatorios',
    '*/5 * * * *',
    $job$ set local role kairo_worker; select kairo_cron.despachar_recordatorios(); $job$
);
