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
    insert into materia (usuario_id, nombre, periodo) values (v_a, 'Redes', '2026-3');
    insert into actividad (usuario_id, categoria_id, titulo) values (v_a, v_categoria, 'Tarea de A')
    returning id into v_actividad;

    perform set_config('app.usuario_id', v_b::text, true);
    select count(*) into v_n from materia;
    assert v_n = 0, 'B no debe ver materias de A';
    select count(*) into v_n from actividad;
    assert v_n = 0, 'B no debe ver actividades de A';
    update actividad set titulo = 'robada' where id = v_actividad;
    get diagnostics v_n = row_count;
    assert v_n = 0, 'B no debe editar actividades de A';

    begin
        insert into actividad (usuario_id, categoria_id, titulo) values (v_a, v_categoria, 'suplantada');
        assert false, 'B no debe insertar a nombre de A';
    exception when insufficient_privilege then
        null;
    end;

    perform set_config('app.usuario_id', '', true);
    select count(*) into v_n from actividad;
    assert v_n = 0, 'sin sesion no se ve nada';

    perform set_config('app.usuario_id', v_a::text, true);
    update actividad set estado = 'completada' where id = v_actividad;
    select count(*) into v_n from actividad where completada_en is not null;
    assert v_n = 1, 'el trigger debe fijar completada_en';

    begin
        select password_hash into v_n from usuario;
        assert false, 'password_hash no debe poder leerse';
    exception when insufficient_privilege then
        null;
    end;

    reset role;
end
$$;

rollback;
