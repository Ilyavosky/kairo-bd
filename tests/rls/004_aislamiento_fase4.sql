begin;

do $$
declare
    v_a uuid;
    v_b uuid;
    v_categoria uuid;
    v_actividad uuid;
    v_actividad_b uuid;
    v_recordatorio uuid;
    v_n integer;
begin
    v_a := kairo_registrar_usuario('a_' || gen_random_uuid() || '@prueba.mx', 'hash', 'A', 'America/Mexico_City');
    v_b := kairo_registrar_usuario('b_' || gen_random_uuid() || '@prueba.mx', 'hash', 'B', 'America/Mexico_City');
    select id into v_categoria from categoria_actividad where nombre = 'Tarea' and usuario_id is null;

    set local role kairo_app;

    perform set_config('app.usuario_id', v_b::text, true);
    insert into actividad (usuario_id, categoria_id, titulo) values (v_b, v_categoria, 'De B')
    returning id into v_actividad_b;

    perform set_config('app.usuario_id', v_a::text, true);
    insert into actividad (usuario_id, categoria_id, titulo) values (v_a, v_categoria, 'De A')
    returning id into v_actividad;
    insert into recordatorio (usuario_id, actividad_id, momento)
    values (v_a, v_actividad, now() + interval '1 hour') returning id into v_recordatorio;
    insert into autoevaluacion_semanal (usuario_id, semana_desde, estado_animo, satisfaccion)
    values (v_a, date '2026-11-16', 4, 3);
    insert into vinculo_telegram (usuario_id, codigo_hash, expira_en)
    values (v_a, 'hash-a', now() + interval '10 minutes');

    begin
        insert into recordatorio (usuario_id, actividad_id, momento)
        values (v_a, v_actividad_b, now() + interval '1 hour');
        assert false, 'A no debe apuntar a la actividad de B';
    exception when foreign_key_violation then
        null;
    end;

    begin
        insert into recordatorio (usuario_id, actividad_id, momento, estado_envio)
        values (v_a, v_actividad, now() + interval '1 hour', 'enviado');
        assert false, 'el usuario no fija el estado de envio';
    exception when insufficient_privilege then
        null;
    end;

    perform set_config('app.usuario_id', v_b::text, true);
    select count(*) into v_n from recordatorio;
    assert v_n = 0, 'B no debe ver recordatorios de A';
    select count(*) into v_n from autoevaluacion_semanal;
    assert v_n = 0, 'B no debe ver autoevaluaciones de A';
    select count(*) into v_n from vinculo_telegram;
    assert v_n = 0, 'B no debe ver codigos de A';
    update recordatorio set estado_envio = 'cancelado' where id = v_recordatorio;
    get diagnostics v_n = row_count;
    assert v_n = 0, 'B no debe cancelar recordatorios de A';

    begin
        insert into autoevaluacion_semanal (usuario_id, semana_desde, estado_animo, satisfaccion)
        values (v_a, date '2026-11-23', 3, 3);
        assert false, 'B no debe escribir como A';
    exception when insufficient_privilege then
        null;
    end;
end
$$;

rollback;
