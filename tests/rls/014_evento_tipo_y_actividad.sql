begin;

do $$
declare
    v_a uuid;
    v_b uuid;
    v_tarea uuid;
    v_actividad_a uuid;
    v_actividad_b uuid;
    v_tipo text;
begin
    v_a := kairo_registrar_usuario('a_' || gen_random_uuid() || '@prueba.mx', 'hash', 'A', 'America/Mexico_City');
    v_b := kairo_registrar_usuario('b_' || gen_random_uuid() || '@prueba.mx', 'hash', 'B', 'America/Mexico_City');
    select id into v_tarea from categoria_actividad where nombre = 'Tarea' and usuario_id is null;

    set local role kairo_app;

    perform set_config('app.usuario_id', v_b::text, true);
    insert into actividad (usuario_id, categoria_id, titulo)
    values (v_b, v_tarea, 'Proyecto de B') returning id into v_actividad_b;

    perform set_config('app.usuario_id', v_a::text, true);
    insert into actividad (usuario_id, categoria_id, titulo)
    values (v_a, v_tarea, 'Proyecto de A') returning id into v_actividad_a;

    insert into evento_calendario (usuario_id, titulo, inicio, fin)
    values (v_a, 'Cita', '2026-11-26 10:00-06', '2026-11-26 11:00-06')
    returning tipo into v_tipo;
    assert v_tipo = 'personal', 'el tipo por defecto es personal';

    insert into evento_calendario (usuario_id, actividad_id, tipo, titulo, inicio, fin)
    values (v_a, v_actividad_a, 'entrega', 'Entrega', '2026-11-27 09:00-06', '2026-11-27 09:30-06');

    begin
        insert into evento_calendario (usuario_id, tipo, titulo, inicio, fin)
        values (v_a, 'fiesta', 'X', '2026-11-27 09:00-06', '2026-11-27 10:00-06');
        raise exception 'un tipo fuera del dominio debio fallar';
    exception when check_violation then null;
    end;

    begin
        insert into evento_calendario (usuario_id, actividad_id, titulo, inicio, fin)
        values (v_a, v_actividad_b, 'Ajeno', '2026-11-27 09:00-06', '2026-11-27 10:00-06');
        raise exception 'un evento no debe apuntar a la actividad de otro usuario';
    exception when foreign_key_violation then null;
    end;
end
$$;

rollback;
