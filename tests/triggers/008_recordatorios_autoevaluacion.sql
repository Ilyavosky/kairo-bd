begin;

do $$
declare
    v_a uuid;
    v_categoria uuid;
    v_actividad uuid;
    v_evento uuid;
    v_recordatorio uuid;
    v_creada timestamptz;
    v_n integer;
    v_estado text;
begin
    v_a := kairo_registrar_usuario('a_' || gen_random_uuid() || '@prueba.mx', 'hash', 'A', 'America/Mexico_City');
    select id into v_categoria from categoria_actividad where nombre = 'Tarea' and usuario_id is null;

    set local role kairo_app;
    perform set_config('app.usuario_id', v_a::text, true);

    insert into actividad (usuario_id, categoria_id, titulo) values (v_a, v_categoria, 'X')
    returning id into v_actividad;
    insert into evento_calendario (usuario_id, titulo, inicio, fin)
    values (v_a, 'Clase', now() + interval '1 day', now() + interval '1 day 1 hour')
    returning id into v_evento;

    begin
        insert into recordatorio (usuario_id, momento) values (v_a, now());
        assert false, 'debe tener un objetivo';
    exception when check_violation then
        null;
    end;

    begin
        insert into recordatorio (usuario_id, actividad_id, evento_id, momento)
        values (v_a, v_actividad, v_evento, now());
        assert false, 'los objetivos son excluyentes';
    exception when check_violation then
        null;
    end;

    insert into recordatorio (usuario_id, evento_id, momento)
    values (v_a, v_evento, now() + interval '1 hour') returning id into v_recordatorio;

    update recordatorio set estado_envio = 'cancelado' where id = v_recordatorio;
    select estado_envio into v_estado from recordatorio where id = v_recordatorio;
    assert v_estado = 'cancelado', 'el usuario puede cancelar un pendiente';

    update recordatorio set momento = now() where id = v_recordatorio;
    get diagnostics v_n = row_count;
    assert v_n = 0, 'un recordatorio cancelado ya no se edita';

    begin
        insert into autoevaluacion_semanal (usuario_id, semana_desde, estado_animo, satisfaccion)
        values (v_a, date '2026-11-17', 3, 3);
        assert false, 'la semana empieza en lunes';
    exception when check_violation then
        null;
    end;

    begin
        insert into autoevaluacion_semanal (usuario_id, semana_desde, estado_animo, satisfaccion)
        values (v_a, date '2026-11-16', 6, 3);
        assert false, 'el animo va de 1 a 5';
    exception when check_violation then
        null;
    end;

    insert into autoevaluacion_semanal (usuario_id, semana_desde, estado_animo, satisfaccion)
    values (v_a, date '2026-11-16', 3, 3);

    begin
        insert into autoevaluacion_semanal (usuario_id, semana_desde, estado_animo, satisfaccion)
        values (v_a, date '2026-11-16', 4, 4);
        assert false, 'una por semana';
    exception when unique_violation then
        null;
    end;

    select creada_en into v_creada from autoevaluacion_semanal where semana_desde = date '2026-11-16';
    perform pg_sleep(0.01);
    update autoevaluacion_semanal set satisfaccion = 5 where semana_desde = date '2026-11-16';
    assert (select actualizada_en from autoevaluacion_semanal where semana_desde = date '2026-11-16') > v_creada,
    'actualizada_en avanza al editar';
end
$$;

rollback;
