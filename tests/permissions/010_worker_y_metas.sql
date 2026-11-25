begin;

do $$
declare
    v_a uuid;
    v_categoria uuid;
    v_actividad uuid;
    v_recordatorio uuid;
    v_meta uuid;
    v_n integer;
    v_estado text;
    v_logrado numeric;
    v_cumplida boolean;
begin
    v_a := kairo_registrar_usuario('a_' || gen_random_uuid() || '@prueba.mx', 'hash', 'A', 'America/Mexico_City');
    select id into v_categoria from categoria_actividad where nombre = 'Estudio' and usuario_id is null;

    set local role kairo_app;
    perform set_config('app.usuario_id', v_a::text, true);

    insert into actividad (usuario_id, categoria_id, titulo) values (v_a, v_categoria, 'X')
    returning id into v_actividad;
    insert into recordatorio (usuario_id, actividad_id, momento)
    values (v_a, v_actividad, now() - interval '1 minute') returning id into v_recordatorio;
    insert into meta (usuario_id, categoria_id, tipo, periodo, objetivo, vigente_desde)
    values (v_a, v_categoria, 'tiempo_acumulado', 'semana', 60, date '2026-11-01')
    returning id into v_meta;
    insert into registro_tiempo (usuario_id, categoria_id, inicio, fin)
    values (v_a, v_categoria, '2026-11-17 10:00:00-06', '2026-11-17 11:30:00-06');

    reset role;
    set local role kairo_worker;

    select count(*) into v_n from recordatorio where estado_envio = 'pendiente' and momento <= now();
    assert v_n = 1, 'el worker ve los pendientes de todos los usuarios';

    update recordatorio set estado_envio = 'enviado', enviado_en = now(), intentos = 1
    where id = v_recordatorio;
    select estado_envio into v_estado from recordatorio where id = v_recordatorio;
    assert v_estado = 'enviado', 'el worker marca el envio';

    begin
        update recordatorio set momento = now() where id = v_recordatorio;
        assert false, 'el worker no cambia el momento';
    exception when insufficient_privilege then
        null;
    end;

    begin
        perform titulo from actividad;
        perform descripcion from actividad;
        assert false, 'el worker no lee la descripcion';
    exception when insufficient_privilege then
        null;
    end;

    begin
        select count(*) into v_n from registro_tiempo;
        assert false, 'el worker no lee registros de tiempo';
    exception when insufficient_privilege then
        null;
    end;

    reset role;
    set local role kairo_worker;
    v_n := kairo_evaluar_metas('2026-11-24 12:00:00-06');
    assert v_n = 1, 'evalua la semana cerrada';
    v_n := kairo_evaluar_metas('2026-11-24 12:00:00-06');
    assert v_n = 0, 'es idempotente';

    reset role;
    select valor_logrado, cumplida into v_logrado, v_cumplida from evaluacion_meta where meta_id = v_meta;
    assert v_logrado = 90 and v_cumplida, '90 minutos cumplen la meta de 60';
    assert (select periodo_desde from evaluacion_meta where meta_id = v_meta) = '2026-11-16 00:00:00-06'::timestamptz,
    'la semana empieza el lunes en la zona del usuario';
end
$$;

rollback;
