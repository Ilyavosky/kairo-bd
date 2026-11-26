begin;

do $$
declare
    v_a uuid;
    v_b uuid;
    v_estudio uuid;
    v_ejercicio uuid;
    v_registro uuid;
    v_total integer;
    v_distintos integer;
    v_segundos bigint;
begin
    v_a := kairo_registrar_usuario('a_' || gen_random_uuid() || '@prueba.mx', 'hash', 'A', 'America/Mexico_City');
    v_b := kairo_registrar_usuario('b_' || gen_random_uuid() || '@prueba.mx', 'hash', 'B', 'America/Mexico_City');
    select id into v_estudio from categoria_actividad where nombre = 'Estudio' and usuario_id is null;
    select id into v_ejercicio from categoria_actividad where nombre = 'Ejercicio' and usuario_id is null;

    set local role kairo_app;

    perform set_config('app.usuario_id', v_b::text, true);
    insert into registro_tiempo (usuario_id, categoria_id, inicio, fin)
    values (v_b, v_estudio, '2026-11-18 09:00:00-06', '2026-11-18 10:00:00-06');

    perform set_config('app.usuario_id', v_a::text, true);
    insert into registro_tiempo (usuario_id, categoria_id, inicio, fin)
    values (v_a, v_estudio, '2026-11-20 22:00:00-06', '2026-11-20 23:00:00-06')
    returning id into v_registro;
    insert into registro_tiempo (usuario_id, categoria_id, inicio, fin) values
    (v_a, v_estudio, '2026-11-20 10:00:00-06', '2026-11-20 10:30:00-06'),
    (v_a, v_ejercicio, '2026-11-23 07:00:00-06', '2026-11-23 07:45:00-06');

    select count(*), count(*) filter (where not coincide) into v_total, v_distintos
    from kairo_recalcular_resumen(v_a);
    assert v_total = 6,
    'dos registros de estudio el mismo dia y uno de ejercicio producen 6 cubetas, hay ' || v_total;
    assert v_distintos = 0, 'tras insertar, el recalculo coincide con el trigger';

    select segundos_calculados into v_segundos from kairo_recalcular_resumen(v_a)
    where categoria_id = v_estudio and periodo = 'semana' and periodo_desde = date '2026-11-16';
    assert v_segundos = 5400, 'la semana del 16 suma 90 minutos de estudio';

    update registro_tiempo set fin = '2026-11-21 00:00:00-06' where id = v_registro;
    update registro_tiempo
    set inicio = '2026-11-10 08:00:00-06', fin = '2026-11-10 09:00:00-06'
    where id = v_registro;
    select count(*) filter (where not coincide) into v_distintos from kairo_recalcular_resumen(v_a);
    assert v_distintos = 0, 'tras editar y mover de semana, el recalculo coincide con el trigger';

    perform set_config('app.usuario_id', v_b::text, true);
    select count(*) into v_total from kairo_recalcular_resumen(v_a);
    assert v_total = 0, 'con RLS, B no ve los totales de A';
end
$$;

rollback;
