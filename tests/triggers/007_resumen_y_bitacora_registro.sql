begin;

do $$
declare
    v_a uuid;
    v_categoria uuid;
    v_otra uuid;
    v_registro uuid;
    v_segundos bigint;
    v_registros integer;
    v_n integer;
begin
    v_a := kairo_registrar_usuario('a_' || gen_random_uuid() || '@prueba.mx', 'hash', 'A', 'America/Mexico_City');
    select id into v_categoria from categoria_actividad where nombre = 'Estudio' and usuario_id is null;
    select id into v_otra from categoria_actividad where nombre = 'Ejercicio' and usuario_id is null;

    set local role kairo_app;
    perform set_config('app.usuario_id', v_a::text, true);

    insert into registro_tiempo (usuario_id, categoria_id, inicio, fin)
    values (v_a, v_categoria, '2026-11-20 22:00:00-06', '2026-11-20 23:00:00-06')
    returning id into v_registro;

    select segundos, registros into v_segundos, v_registros from resumen_periodo
    where categoria_id = v_categoria and periodo = 'dia' and periodo_desde = date '2026-11-20';
    assert v_segundos = 3600 and v_registros = 1, 'el dia se calcula en la zona del usuario, no en UTC';

    select segundos into v_segundos from resumen_periodo
    where categoria_id = v_categoria and periodo = 'semana' and periodo_desde = date '2026-11-16';
    assert v_segundos = 3600, 'la semana empieza en lunes';

    select segundos into v_segundos from resumen_periodo
    where categoria_id = v_categoria and periodo = 'mes' and periodo_desde = date '2026-11-01';
    assert v_segundos = 3600, 'el mes empieza el primer dia';

    insert into registro_tiempo (usuario_id, categoria_id, inicio, fin)
    values (v_a, v_categoria, '2026-11-20 10:00:00-06', '2026-11-20 10:30:00-06');
    select segundos, registros into v_segundos, v_registros from resumen_periodo
    where categoria_id = v_categoria and periodo = 'dia' and periodo_desde = date '2026-11-20';
    assert v_segundos = 5400 and v_registros = 2, 'un segundo registro del dia se suma';

    update registro_tiempo set fin = '2026-11-21 00:00:00-06' where id = v_registro;
    select segundos into v_segundos from resumen_periodo
    where categoria_id = v_categoria and periodo = 'dia' and periodo_desde = date '2026-11-20';
    assert v_segundos = 1800 + 7200, 'ampliar un registro ajusta el resumen por la diferencia';

    update registro_tiempo
    set inicio = '2026-11-10 08:00:00-06', fin = '2026-11-10 09:00:00-06'
    where id = v_registro;
    select segundos, registros into v_segundos, v_registros from resumen_periodo
    where categoria_id = v_categoria and periodo = 'dia' and periodo_desde = date '2026-11-20';
    assert v_segundos = 1800 and v_registros = 1, 'mover un registro lo quita del dia anterior';
    select segundos, registros into v_segundos, v_registros from resumen_periodo
    where categoria_id = v_categoria and periodo = 'dia' and periodo_desde = date '2026-11-10';
    assert v_segundos = 3600 and v_registros = 1, 'mover un registro lo suma en el dia nuevo';
    select segundos into v_segundos from resumen_periodo
    where categoria_id = v_categoria and periodo = 'semana' and periodo_desde = date '2026-11-09';
    assert v_segundos = 3600, 'mover un registro cambia tambien la semana';

    update registro_tiempo set categoria_id = v_otra where id = v_registro;
    select segundos into v_segundos from resumen_periodo
    where categoria_id = v_otra and periodo = 'dia' and periodo_desde = date '2026-11-10';
    assert v_segundos = 3600, 'cambiar la categoria mueve el tiempo a la nueva';
    select segundos into v_segundos from resumen_periodo
    where categoria_id = v_categoria and periodo = 'dia' and periodo_desde = date '2026-11-10';
    assert v_segundos = 0, 'cambiar la categoria deja en cero la anterior';

    select count(*) into v_n from bitacora_cambios where registro_tiempo_id = v_registro;
    assert v_n = 4, 'fin, inicio, fin y categoria: cuatro cambios registrados hasta ahora';

    update registro_tiempo set nota = 'Repaso de redes' where id = v_registro;
    select count(*) into v_n from bitacora_cambios
    where registro_tiempo_id = v_registro and campo = 'nota' and valor_anterior is null
        and valor_nuevo = 'Repaso de redes';
    assert v_n = 1, 'editar la nota se registra con su valor anterior y el nuevo';

    select count(*) into v_n from resumen_periodo
    where categoria_id = v_otra and periodo = 'dia' and periodo_desde = date '2026-11-10'
        and segundos = 3600;
    assert v_n = 1, 'editar solo la nota no toca el resumen';

    update registro_tiempo set nota = 'Repaso de redes' where id = v_registro;
    select count(*) into v_n from bitacora_cambios where registro_tiempo_id = v_registro;
    assert v_n = 5, 'una edicion sin cambios no escribe en la bitacora';

    reset role;
end
$$;

rollback;
