begin;

do $$
declare
    v_a uuid;
    v_tarea uuid;
    v_subtipo text;
    v_n integer;
begin
    v_a := kairo_registrar_usuario('a_' || gen_random_uuid() || '@prueba.mx', 'h', 'A', 'America/Mexico_City');
    select id into v_tarea from categoria_actividad where nombre = 'Tarea' and usuario_id is null;

    set local role kairo_app;
    perform set_config('app.usuario_id', v_a::text, true);

    insert into actividad (usuario_id, categoria_id, titulo, vence_en)
    values (v_a, v_tarea, 'Reporte', now() + interval '2 days');
    insert into evento_calendario (usuario_id, tipo, titulo, inicio, fin)
    values (v_a, 'examen', 'Parcial', now() + interval '1 day', now() + interval '1 day 2 hours');

    select subtipo into v_subtipo from v_agenda_proxima where tipo = 'evento';
    assert v_subtipo = 'examen', 'el evento expone su tipo en subtipo';

    select count(*) into v_n from v_agenda_proxima where tipo = 'actividad' and subtipo is null;
    assert v_n = 1, 'las actividades tienen subtipo nulo';

    reset role;
    set local role kairo_worker;
    perform tipo from evento_calendario limit 1;

    begin
        perform lugar from evento_calendario limit 1;
        raise exception 'kairo_worker solo lee las columnas concedidas de evento_calendario';
    exception when insufficient_privilege then null;
    end;
end
$$;

rollback;
