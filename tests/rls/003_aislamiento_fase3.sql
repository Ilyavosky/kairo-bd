begin;

do $$
declare
    v_a uuid;
    v_b uuid;
    v_categoria uuid;
    v_mensaje_a uuid;
    v_mensaje_b uuid;
    v_extraccion_a uuid;
    v_extraccion_b uuid;
    v_actividad uuid;
    v_n integer;
begin
    v_a := kairo_registrar_usuario('a_' || gen_random_uuid() || '@prueba.mx', 'hash', 'A', 'America/Mexico_City');
    v_b := kairo_registrar_usuario('b_' || gen_random_uuid() || '@prueba.mx', 'hash', 'B', 'America/Mexico_City');
    select id into v_categoria from categoria_actividad where nombre = 'Tarea' and usuario_id is null;

    set local role kairo_app;

    perform set_config('app.usuario_id', v_a::text, true);
    insert into mensaje_origen (usuario_id, texto) values (v_a, 'entregar el reporte de redes el viernes')
    returning id into v_mensaje_a;
    insert into extraccion (usuario_id, mensaje_origen_id, entidad_tipo, propuesta, resuelta, modelo)
    values (v_a, v_mensaje_a, 'actividad', '{"titulo": "Reporte"}', '{"titulo": "Reporte"}', 'modelo-prueba')
    returning id into v_extraccion_a;
    insert into actividad (usuario_id, categoria_id, titulo) values (v_a, v_categoria, 'Reporte')
    returning id into v_actividad;
    insert into registro_tiempo (usuario_id, categoria_id, inicio, fin)
    values (v_a, v_categoria, now() - interval '1 hour', now());

    update extraccion
    set estado = 'corregida', actividad_id = v_actividad, resuelta_en = now()
    where id = v_extraccion_a;
    insert into correccion_campo (usuario_id, extraccion_id, campo, valor_propuesto, valor_final)
    values (v_a, v_extraccion_a, 'titulo', '"Reporte"', '"Reporte de redes"');

    select count(*) into v_n from resumen_periodo;
    assert v_n = 3, 'A debe ver su resumen por dia, semana y mes';

    perform set_config('app.usuario_id', v_b::text, true);
    select count(*) into v_n from mensaje_origen;
    assert v_n = 0, 'B no debe ver mensajes de A';
    select count(*) into v_n from extraccion;
    assert v_n = 0, 'B no debe ver extracciones de A';
    select count(*) into v_n from correccion_campo;
    assert v_n = 0, 'B no debe ver correcciones de A';
    select count(*) into v_n from resumen_periodo;
    assert v_n = 0, 'B no debe ver el resumen de A';

    update extraccion set estado = 'descartada', resuelta_en = now() where id = v_extraccion_a;
    get diagnostics v_n = row_count;
    assert v_n = 0, 'B no debe poder cerrar extracciones de A';

    insert into mensaje_origen (usuario_id, texto) values (v_b, 'estudie dos horas')
    returning id into v_mensaje_b;

    begin
        insert into extraccion (usuario_id, mensaje_origen_id, entidad_tipo, propuesta, resuelta, modelo)
        values (v_b, v_mensaje_a, 'actividad', '{}', '{}', 'modelo-prueba');
        assert false, 'B no debe poder colgar una extraccion de un mensaje de A';
    exception when foreign_key_violation then
        null;
    end;

    begin
        insert into mensaje_origen (usuario_id, texto) values (v_a, 'suplantacion');
        assert false, 'B no debe poder crear mensajes a nombre de A';
    exception when insufficient_privilege then
        null;
    end;

    insert into extraccion (usuario_id, mensaje_origen_id, entidad_tipo, propuesta, resuelta, modelo)
    values (v_b, v_mensaje_b, 'actividad', '{}', '{}', 'modelo-prueba')
    returning id into v_extraccion_b;

    begin
        update extraccion set actividad_id = v_actividad, estado = 'aceptada', resuelta_en = now()
        where id = v_extraccion_b;
        assert false, 'una extraccion no debe apuntar a una actividad de otro usuario';
    exception when foreign_key_violation then
        null;
    end;

    begin
        update extraccion set estado = 'aceptada', resuelta_en = now() where id = v_extraccion_b;
        assert false, 'aceptar sin fila creada viola el CHECK';
    exception when check_violation then
        null;
    end;

    begin
        update extraccion set propuesta = '{"titulo": "otra cosa"}' where id = v_extraccion_b;
        assert false, 'la propuesta del modelo no se reescribe';
    exception when insufficient_privilege then
        null;
    end;

    begin
        update resumen_periodo set segundos = 0;
        assert false, 'kairo_app no escribe el resumen directamente';
    exception when insufficient_privilege then
        null;
    end;

    reset role;
end
$$;

rollback;
