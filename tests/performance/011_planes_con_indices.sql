begin;

create function pg_temp.plan(p_consulta text) returns text
language plpgsql
as $$
declare
    v_linea text;
    v_plan text := '';
begin
    for v_linea in execute 'explain ' || p_consulta loop
        v_plan := v_plan || v_linea || E'\n';
    end loop;
    return v_plan;
end
$$;

do $$
declare
    v_a uuid;
    v_tarea uuid;
    v_estudio uuid;
    v_plan text;
begin
    v_a := kairo_registrar_usuario('a_' || gen_random_uuid() || '@prueba.mx', 'hash', 'A', 'America/Mexico_City');
    select id into v_tarea from categoria_actividad where nombre = 'Tarea' and usuario_id is null;
    select id into v_estudio from categoria_actividad where nombre = 'Estudio' and usuario_id is null;

    insert into actividad (usuario_id, categoria_id, titulo, vence_en)
    select v_a, v_tarea, 'a' || g, now() + (g || ' hours')::interval from generate_series(1, 2000) as g;
    insert into registro_tiempo (usuario_id, categoria_id, inicio, fin)
    select v_a, v_estudio, now() - (g || ' hours')::interval, now() - (g || ' hours')::interval + interval '30 minutes'
    from generate_series(1, 2000) as g;
    insert into recordatorio (usuario_id, actividad_id, momento, estado_envio)
    select v_a, id, now() - interval '1 minute', 'pendiente' from actividad where usuario_id = v_a limit 200;
    update recordatorio set estado_envio = 'enviado', enviado_en = now() where usuario_id = v_a and id in (
        select id from recordatorio where usuario_id = v_a limit 190);

    analyze actividad;
    analyze registro_tiempo;
    analyze recordatorio;
    set local enable_seqscan = off;

    v_plan := pg_temp.plan(format(
        'select titulo from actividad where usuario_id = %L and vence_en between now() and now() + interval ''7 days''', v_a));
    assert v_plan like '%actividad_usuario_vence_idx%', 'la agenda usa el indice de vencimiento: ' || v_plan;

    v_plan := pg_temp.plan(format(
        'select sum(fin - inicio) from registro_tiempo where usuario_id = %L and categoria_id = %L and inicio >= now() - interval ''7 days''',
        v_a, v_estudio));
    assert v_plan like '%registro_usuario_categoria_inicio_idx%', 'las metas usan el indice de registros: ' || v_plan;

    v_plan := pg_temp.plan(
        'select id from recordatorio where estado_envio = ''pendiente'' and momento <= now() order by momento limit 20');
    assert v_plan like '%recordatorio_pendientes_idx%', 'el despacho usa el indice parcial de pendientes: ' || v_plan;
end
$$;

rollback;
