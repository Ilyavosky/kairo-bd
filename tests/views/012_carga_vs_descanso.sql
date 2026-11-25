begin;

do $$
declare
    v_a uuid;
    v_estudio uuid;
    v_sueno uuid;
    v_ejercicio uuid;
    v_juegos uuid;
    v_academico numeric;
    v_dormido numeric;
    v_ejercitado numeric;
    v_animo integer;
    v_n integer;
begin
    v_a := kairo_registrar_usuario('a_' || gen_random_uuid() || '@prueba.mx', 'hash', 'A', 'America/Mexico_City');
    select id into v_estudio from categoria_actividad where nombre = 'Estudio' and usuario_id is null;
    select id into v_sueno from categoria_actividad where nombre = 'Sueno' and usuario_id is null;
    select id into v_ejercicio from categoria_actividad where nombre = 'Ejercicio' and usuario_id is null;
    select id into v_juegos from categoria_actividad where nombre = 'Videojuegos' and usuario_id is null;

    set local role kairo_app;
    perform set_config('app.usuario_id', v_a::text, true);

    insert into registro_tiempo (usuario_id, categoria_id, inicio, fin) values
    (v_a, v_estudio, '2026-11-17 09:00:00-06', '2026-11-17 11:00:00-06'),
    (v_a, v_sueno, '2026-11-17 23:00:00-06', '2026-11-18 06:00:00-06'),
    (v_a, v_ejercicio, '2026-11-19 07:00:00-06', '2026-11-19 07:45:00-06'),
    (v_a, v_juegos, '2026-11-19 20:00:00-06', '2026-11-19 22:00:00-06'),
    (v_a, v_estudio, '2026-11-24 09:00:00-06', '2026-11-24 10:00:00-06');
    insert into autoevaluacion_semanal (usuario_id, semana_desde, estado_animo, satisfaccion)
    values (v_a, date '2026-11-16', 4, 3);

    select minutos_academicos, minutos_sueno, minutos_ejercicio, estado_animo
    into v_academico, v_dormido, v_ejercitado, v_animo
    from v_carga_vs_descanso where semana_desde = date '2026-11-16';
    assert v_academico = 120, 'solo cuenta categorias academicas o ambas';
    assert v_dormido = 420, 'suma el sueno de la semana';
    assert v_ejercitado = 45, 'suma el ejercicio de la semana';
    assert v_animo = 4, 'trae la autoevaluacion de esa semana';

    select estado_animo into v_animo from v_carga_vs_descanso where semana_desde = date '2026-11-23';
    assert v_animo is null, 'una semana sin autoevaluacion la deja en nulo';
    select count(*) into v_n from v_carga_vs_descanso;
    assert v_n = 2, 'una fila por semana con registros';
end
$$;

rollback;
