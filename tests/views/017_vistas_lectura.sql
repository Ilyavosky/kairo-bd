begin;

do $$
declare
    v_lista text;
begin
    select string_agg(c.relname, ', ') into v_lista
    from pg_class as c
    where c.relnamespace = 'public'::regnamespace and c.relkind = 'v'
        and (c.relname like 'vl\_%') = coalesce('security_invoker=true' = any(c.reloptions), false);
    assert v_lista is null,
    'Las vistas v_* deben usar security_invoker y las vl_* no: ' || v_lista;
end
$$;

do $$
declare
    v_a uuid;
    v_b uuid;
    v_tarea uuid;
    v_estudio uuid;
    v_sueno uuid;
    v_mensaje uuid;
    v_ext uuid;
    v_act uuid;
    v_r record;
    v_n integer;
begin
    v_a := kairo_registrar_usuario('a_' || gen_random_uuid() || '@prueba.mx', 'h', 'A', 'America/Mexico_City');
    v_b := kairo_registrar_usuario('b_' || gen_random_uuid() || '@prueba.mx', 'h', 'B', 'America/Mexico_City');
    select id into v_tarea from categoria_actividad where nombre = 'Tarea' and usuario_id is null;
    select id into v_estudio from categoria_actividad where nombre = 'Estudio' and usuario_id is null;
    select id into v_sueno from categoria_actividad where nombre = 'Sueno' and usuario_id is null;

    -- Semana del lunes 16 de noviembre de 2026.
    -- A: 2 h de estudio, 8 h de sueno, 2 entregas. B: 1 h de estudio, 6 h de sueno, 1 entrega.
    insert into registro_tiempo (usuario_id, categoria_id, inicio, fin) values
    (v_a, v_estudio, '2026-11-17 10:00-06', '2026-11-17 12:00-06'),
    (v_a, v_sueno, '2026-11-17 23:00-06', '2026-11-18 07:00-06'),
    (v_b, v_estudio, '2026-11-18 10:00-06', '2026-11-18 11:00-06'),
    (v_b, v_sueno, '2026-11-18 00:00-06', '2026-11-18 06:00-06');
    insert into actividad (usuario_id, categoria_id, titulo, vence_en) values
    (v_a, v_tarea, 'Entrega 1', '2026-11-19 23:59-06'),
    (v_a, v_tarea, 'Entrega 2', '2026-11-20 23:59-06'),
    (v_b, v_tarea, 'Entrega 3', '2026-11-20 23:59-06');
    insert into autoevaluacion_semanal (usuario_id, semana_desde, estado_animo, satisfaccion) values
    (v_a, '2026-11-16', 4, 5),
    (v_b, '2026-11-16', 2, 3);

    -- Pipeline: A acepta una actividad sin corregir; B corrige dos campos de otra.
    insert into mensaje_origen (usuario_id, texto) values (v_a, 'tarea') returning id into v_mensaje;
    select id into v_act from actividad where usuario_id = v_a and titulo = 'Entrega 1';
    insert into extraccion (
        usuario_id, mensaje_origen_id, entidad_tipo, propuesta, resuelta, modelo, confianza,
        estado, actividad_id, resuelta_en
    ) values (v_a, v_mensaje, 'actividad', '{}', '{}', 'm', 0.9, 'aceptada', v_act, now());
    insert into mensaje_origen (usuario_id, texto) values (v_b, 'tarea') returning id into v_mensaje;
    select id into v_act from actividad where usuario_id = v_b;
    insert into extraccion (
        usuario_id, mensaje_origen_id, entidad_tipo, propuesta, resuelta, modelo, confianza,
        estado, actividad_id, resuelta_en
    ) values (v_b, v_mensaje, 'actividad', '{}', '{}', 'm', 0.7, 'corregida', v_act, now())
    returning id into v_ext;
    insert into correccion_campo (usuario_id, extraccion_id, campo, valor_propuesto, valor_final) values
    (v_b, v_ext, 'titulo', '"a"', '"b"'),
    (v_b, v_ext, 'vence_en', '"c"', '"d"');

    set local role kairo_lectura;

    select * into v_r from vl_cruce_carga_descanso where semana_desde = date '2026-11-16';
    assert v_r.usuarios = 2, 'dos usuarios con datos en la semana';
    assert v_r.entregas_que_vencen = 3, 'tres entregas vencen en la semana';
    assert v_r.minutos_academicos_por_usuario = 90.0, 'promedio de (120 + 60) minutos academicos';
    assert v_r.minutos_sueno_por_usuario = 420.0, 'promedio de (480 + 360) minutos de sueno';
    assert v_r.estado_animo_promedio = 3.00 and v_r.satisfaccion_promedio = 4.00,
    'promedios de la autoevaluacion';

    select * into v_r from vl_desempeno_pipeline where entidad_tipo = 'actividad';
    assert v_r.total = 2 and v_r.usuarios = 2, 'dos extracciones de dos usuarios';
    assert v_r.porcentaje_sin_correccion = 50.0, 'una de dos se acepto sin correccion';
    assert v_r.promedio_campos_corregidos = 1.00, 'promedio de (0 + 2) campos corregidos';
    assert v_r.confianza_promedio = 0.800, 'promedio de 0.9 y 0.7';

    select * into v_r from vl_uso_por_categoria
    where semana_desde = date '2026-11-16' and categoria = 'Estudio';
    assert v_r.usuarios = 2 and v_r.registros = 2 and v_r.minutos = 180.0,
    'estudio agregado de ambos usuarios';

    select count(*) into v_n from information_schema.columns
    where table_name like 'vl\_%' and column_name in ('usuario_id', 'id', 'titulo', 'texto');
    assert v_n = 0, 'las vistas agregadas no exponen identificadores ni textos';

    begin
        perform 1 from actividad;
        raise exception 'kairo_lectura no debe leer tablas base';
    exception when insufficient_privilege then null;
    end;

    begin
        perform 1 from v_agenda_proxima;
        raise exception 'kairo_lectura no debe leer vistas por usuario';
    exception when insufficient_privilege then null;
    end;

    reset role;
    set local role kairo_app;
    perform set_config('app.usuario_id', v_a::text, true);

    begin
        perform 1 from vl_desempeno_pipeline;
        raise exception 'kairo_app no debe leer vistas agregadas';
    exception when insufficient_privilege then null;
    end;

    select count(*) into v_n from v_desempeno_pipeline where total > 0;
    assert v_n = 1, 'kairo_app sigue viendo su propio desempeno';
    select total into v_n from v_desempeno_pipeline where entidad_tipo = 'actividad';
    assert v_n = 1, 'con security_invoker, A solo cuenta su extraccion';
end
$$;

rollback;
