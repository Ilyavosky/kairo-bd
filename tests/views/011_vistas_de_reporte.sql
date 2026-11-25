begin;

do $$
declare
    v_a uuid;
    v_b uuid;
    v_tarea uuid;
    v_estudio uuid;
    v_ejercicio uuid;
    v_materia uuid;
    v_actividad uuid;
    v_mes_local timestamptz;
    v_n integer;
    v_minutos numeric;
    v_pendientes integer;
    v_vencen integer;
    v_progreso numeric;
    v_cumplida boolean;
    v_semana date;
    v_pct numeric;
begin
    v_a := kairo_registrar_usuario('a_' || gen_random_uuid() || '@prueba.mx', 'hash', 'A', 'America/Mexico_City');
    v_b := kairo_registrar_usuario('b_' || gen_random_uuid() || '@prueba.mx', 'hash', 'B', 'America/Mexico_City');
    select id into v_tarea from categoria_actividad where nombre = 'Tarea' and usuario_id is null;
    select id into v_estudio from categoria_actividad where nombre = 'Estudio' and usuario_id is null;
    select id into v_ejercicio from categoria_actividad where nombre = 'Ejercicio' and usuario_id is null;
    v_mes_local := date_trunc('month', now() at time zone 'America/Mexico_City') at time zone 'America/Mexico_City';

    set local role kairo_app;
    perform set_config('app.usuario_id', v_a::text, true);

    insert into materia (usuario_id, nombre, periodo) values (v_a, 'Redes', '2026-3') returning id into v_materia;
    insert into actividad (usuario_id, categoria_id, materia_id, titulo, vence_en)
    values (v_a, v_tarea, v_materia, 'Futura', now() + interval '400 days');
    insert into actividad (usuario_id, categoria_id, materia_id, titulo, vence_en)
    values (v_a, v_tarea, v_materia, 'Pasada', now() - interval '200 days');
    insert into actividad (usuario_id, categoria_id, titulo, vence_en, estado)
    values (v_a, v_tarea, 'Cancelada', now() + interval '401 days', 'cancelada');
    insert into actividad (usuario_id, categoria_id, titulo) values (v_a, v_tarea, 'Sin fecha');
    insert into evento_calendario (usuario_id, titulo, inicio, fin)
    values (v_a, 'Clase', now() + interval '1 day', now() + interval '1 day 1 hour');
    insert into evento_calendario (usuario_id, titulo, inicio, fin)
    values (v_a, 'Clase vieja', now() - interval '3 days', now() - interval '3 days' + interval '1 hour');

    select count(*) into v_n from v_agenda_proxima;
    assert v_n = 2, 'la agenda solo trae la actividad abierta futura y el evento que no termino';
    select count(*) into v_n from v_agenda_proxima where tipo = 'actividad' and titulo = 'Futura' and materia = 'Redes';
    assert v_n = 1, 'la actividad trae el nombre de su materia';

    insert into actividad (usuario_id, categoria_id, materia_id, titulo, vence_en)
    values (v_a, v_tarea, v_materia, 'Entrega miercoles', '2026-11-18 10:00:00-06')
    returning id into v_actividad;
    insert into registro_tiempo (usuario_id, categoria_id, actividad_id, inicio, fin)
    values (v_a, v_estudio, v_actividad, '2026-11-17 10:00:00-06', '2026-11-17 11:30:00-06');

    select semana_desde, actividades_con_vencimiento, actividades_pendientes, minutos_registrados
    into v_semana, v_vencen, v_pendientes, v_minutos
    from v_carga_semanal_materia where materia = 'Redes' and semana_desde = date '2026-11-16';
    assert v_semana = date '2026-11-16', 'la semana empieza en lunes';
    assert v_vencen = 1 and v_pendientes = 1, 'cuenta la actividad que vence esa semana';
    assert v_minutos = 90, 'suma los minutos registrados en actividades de la materia';

    insert into meta (usuario_id, categoria_id, tipo, periodo, objetivo, vigente_desde)
    values (v_a, v_ejercicio, 'tiempo_acumulado', 'mes', 60, date '2020-01-01');
    insert into registro_tiempo (usuario_id, categoria_id, inicio, fin)
    values (v_a, v_ejercicio, v_mes_local, v_mes_local + interval '60 minutes');
    select progreso, cumplida into v_progreso, v_cumplida from v_progreso_metas where categoria = 'Ejercicio';
    assert v_progreso = 60 and v_cumplida, 'el progreso del mes cumple una meta de 60 minutos';

    select count(*) into v_n from v_desempeno_pipeline;
    assert v_n = 3, 'siempre hay una fila por tipo de entidad';
    select porcentaje_sin_correccion into v_pct from v_desempeno_pipeline where entidad_tipo = 'actividad';
    assert v_pct is null, 'sin extracciones cerradas no hay porcentaje';

    perform set_config('app.usuario_id', v_b::text, true);
    select count(*) into v_n from v_agenda_proxima;
    assert v_n = 0, 'B no ve la agenda de A';
    select count(*) into v_n from v_carga_semanal_materia;
    assert v_n = 0, 'B no ve la carga de A';
    select count(*) into v_n from v_progreso_metas;
    assert v_n = 0, 'B no ve las metas de A';
    select count(*) into v_n from v_carga_vs_descanso;
    assert v_n = 0, 'B no ve la carga de A contra el descanso';
end
$$;

rollback;
