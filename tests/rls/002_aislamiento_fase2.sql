begin;

do $$
declare
    v_a uuid;
    v_b uuid;
    v_categoria uuid;
    v_propia_a uuid;
    v_actividad uuid;
    v_etiqueta uuid;
    v_etiqueta_b uuid;
    v_actividad_b uuid;
    v_registro uuid;
    v_meta uuid;
    v_n integer;
begin
    v_a := kairo_registrar_usuario('a_' || gen_random_uuid() || '@prueba.mx', 'hash', 'A', 'America/Mexico_City');
    v_b := kairo_registrar_usuario('b_' || gen_random_uuid() || '@prueba.mx', 'hash', 'B', 'America/Mexico_City');
    select id into v_categoria from categoria_actividad where nombre = 'Estudio' and usuario_id is null;

    set local role kairo_app;

    perform set_config('app.usuario_id', v_a::text, true);
    insert into categoria_actividad (usuario_id, nombre, ambito) values (v_a, 'Solo de A', 'personal')
    returning id into v_propia_a;
    insert into actividad (usuario_id, categoria_id, titulo) values (v_a, v_categoria, 'Tarea de A')
    returning id into v_actividad;
    insert into evento_calendario (usuario_id, titulo, inicio, fin)
    values (v_a, 'Clase', now(), now() + interval '1 hour');
    insert into registro_tiempo (usuario_id, categoria_id, actividad_id, inicio, fin)
    values (v_a, v_categoria, v_actividad, now() - interval '1 hour', now())
    returning id into v_registro;
    insert into sesion_temporizador (usuario_id, categoria_id) values (v_a, v_categoria);
    insert into meta (usuario_id, categoria_id, tipo, periodo, objetivo)
    values (v_a, v_categoria, 'tiempo_acumulado', 'semana', 300)
    returning id into v_meta;
    insert into etiqueta (usuario_id, nombre) values (v_a, 'Urgente') returning id into v_etiqueta;
    insert into actividad_etiqueta (actividad_id, etiqueta_id, usuario_id)
    values (v_actividad, v_etiqueta, v_a);

    perform set_config('app.usuario_id', v_b::text, true);
    select count(*) into v_n from evento_calendario;
    assert v_n = 0, 'B no debe ver eventos de A';
    select count(*) into v_n from registro_tiempo;
    assert v_n = 0, 'B no debe ver registros de A';
    select count(*) into v_n from sesion_temporizador;
    assert v_n = 0, 'B no debe ver sesiones de A';
    select count(*) into v_n from meta;
    assert v_n = 0, 'B no debe ver metas de A';
    select count(*) into v_n from etiqueta;
    assert v_n = 0, 'B no debe ver etiquetas de A';
    select count(*) into v_n from actividad_etiqueta;
    assert v_n = 0, 'B no debe ver las etiquetas aplicadas por A';
    select count(*) into v_n from bitacora_cambios;
    assert v_n = 0, 'B no debe ver la bitacora de A';

    update registro_tiempo set nota = 'robado' where id = v_registro;
    get diagnostics v_n = row_count;
    assert v_n = 0, 'B no debe editar registros de A';
    update meta set objetivo = 1 where id = v_meta;
    get diagnostics v_n = row_count;
    assert v_n = 0, 'B no debe editar metas de A';
    delete from actividad_etiqueta;
    get diagnostics v_n = row_count;
    assert v_n = 0, 'B no debe quitar etiquetas de A';

    begin
        insert into registro_tiempo (usuario_id, categoria_id, inicio, fin)
        values (v_a, v_categoria, now() - interval '1 hour', now());
        assert false, 'B no debe insertar registros a nombre de A';
    exception when insufficient_privilege then
        null;
    end;

    begin
        insert into registro_tiempo (usuario_id, categoria_id, inicio, fin)
        values (v_b, v_propia_a, now() - interval '1 hour', now());
        assert false, 'B no debe usar la categoria propia de A';
    exception when foreign_key_violation then
        null;
    end;

    begin
        insert into registro_tiempo (usuario_id, categoria_id, actividad_id, inicio, fin)
        values (v_b, v_categoria, v_actividad, now() - interval '1 hour', now());
        assert false, 'B no debe registrar tiempo sobre una actividad de A';
    exception when foreign_key_violation then
        null;
    end;

    insert into etiqueta (usuario_id, nombre) values (v_b, 'De B') returning id into v_etiqueta_b;
    insert into actividad (usuario_id, categoria_id, titulo) values (v_b, v_categoria, 'Tarea de B')
    returning id into v_actividad_b;
    begin
        insert into actividad_etiqueta (actividad_id, etiqueta_id, usuario_id)
        values (v_actividad, v_etiqueta_b, v_b);
        assert false, 'B no debe etiquetar actividades de A';
    exception when foreign_key_violation then
        null;
    end;
    begin
        insert into actividad_etiqueta (actividad_id, etiqueta_id, usuario_id)
        values (v_actividad_b, v_etiqueta, v_b);
        assert false, 'B no debe usar etiquetas de A';
    exception when foreign_key_violation then
        null;
    end;

    perform set_config('app.usuario_id', '', true);
    select count(*) into v_n from registro_tiempo;
    assert v_n = 0, 'sin sesion no se ve nada';

    perform set_config('app.usuario_id', v_a::text, true);
    begin
        insert into sesion_temporizador (usuario_id, categoria_id) values (v_a, v_categoria);
        assert false, 'no debe haber dos sesiones en curso para el mismo usuario';
    exception when unique_violation then
        null;
    end;

    begin
        insert into registro_tiempo (usuario_id, categoria_id, inicio, fin)
        values (v_a, v_categoria, now(), now());
        assert false, 'fin debe ser posterior a inicio';
    exception when check_violation then
        null;
    end;

    begin
        insert into meta (usuario_id, categoria_id, tipo, periodo, objetivo)
        values (v_a, v_categoria, 'tiempo_acumulado', 'semana', 100);
        assert false, 'no debe haber dos metas activas iguales';
    exception when unique_violation then
        null;
    end;

    update sesion_temporizador set estado = 'cerrada', cerrada_en = now() where usuario_id = v_a;
    insert into sesion_temporizador (usuario_id, categoria_id) values (v_a, v_categoria);

    begin
        insert into evaluacion_meta (meta_id, usuario_id, periodo_desde, periodo_hasta, objetivo, valor_logrado, cumplida)
        values (v_meta, v_a, now() - interval '7 days', now(), 300, 0, false);
        assert false, 'kairo_app no escribe evaluaciones de meta';
    exception when insufficient_privilege then
        null;
    end;

    reset role;
end
$$;

rollback;
