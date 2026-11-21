begin;

do $$
declare
    v_a uuid;
    v_b uuid;
    v_categoria uuid;
    v_actividad uuid;
    v_n integer;
begin
    v_a := kairo_registrar_usuario('a_' || gen_random_uuid() || '@prueba.mx', 'hash', 'A', 'America/Mexico_City');
    v_b := kairo_registrar_usuario('b_' || gen_random_uuid() || '@prueba.mx', 'hash', 'B', 'America/Mexico_City');
    select id into v_categoria from categoria_actividad where nombre = 'Tarea' and usuario_id is null;

    set local role kairo_app;

    perform set_config('app.usuario_id', v_a::text, true);
    insert into actividad (usuario_id, categoria_id, titulo) values (v_a, v_categoria, 'Tarea de A')
    returning id into v_actividad;
    select count(*) into v_n from bitacora_cambios where actividad_id = v_actividad;
    assert v_n = 1, 'el alta debe registrar el estado inicial';

    update actividad set titulo = 'Otro titulo' where id = v_actividad;
    select count(*) into v_n from bitacora_cambios where actividad_id = v_actividad;
    assert v_n = 1, 'un cambio que no toca el estado no se registra';

    update actividad set estado = 'completada' where id = v_actividad;
    select count(*) into v_n from bitacora_cambios where actividad_id = v_actividad;
    assert v_n = 2, 'el cambio de estado debe registrarse';
    select count(*) into v_n from bitacora_cambios
    where actividad_id = v_actividad and valor_anterior = 'pendiente' and valor_nuevo = 'completada';
    assert v_n = 1, 'la bitacora debe guardar el estado anterior y el nuevo';

    perform set_config('app.usuario_id', v_b::text, true);
    select count(*) into v_n from bitacora_cambios;
    assert v_n = 0, 'B no debe ver la bitacora de A';

    begin
        insert into bitacora_cambios (usuario_id, actividad_id, campo, valor_nuevo)
        values (v_b, v_actividad, 'estado', 'cancelada');
        assert false, 'kairo_app no escribe la bitacora directamente';
    exception when insufficient_privilege then
        null;
    end;

    reset role;
end
$$;

rollback;
