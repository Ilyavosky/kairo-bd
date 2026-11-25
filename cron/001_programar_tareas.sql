select cron.schedule(
    'kairo-despachar-recordatorios',
    '*/5 * * * *',
    $job$
    select net.http_post(
        url := 'https://REEMPLAZAR-API.onrender.com/api/v1/interno/recordatorios/despachar',
        headers := jsonb_build_object(
            'Authorization', 'Bearer REEMPLAZAR-INTERNO-SECRET',
            'Content-Type', 'application/json'
        ),
        body := '{}'::jsonb,
        timeout_milliseconds := 20000
    );
    $job$
);

select cron.schedule(
    'kairo-evaluar-metas',
    '10 * * * *',
    $job$ select kairo_evaluar_metas(); $job$
);
