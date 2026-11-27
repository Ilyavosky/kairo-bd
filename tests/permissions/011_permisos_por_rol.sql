begin;

do $$
declare
    v_tabla text;
    v_n integer;
    v_con_delete text[];
    v_a uuid;
begin
    v_con_delete := array[]::text[];
    for v_tabla in
        select c.relname::text from pg_class as c
        inner join pg_namespace as n on c.relnamespace = n.oid
        where n.nspname = 'public' and c.relkind in ('r', 'p')
        order by c.relname
    loop
        if has_table_privilege('kairo_app', 'public.' || v_tabla, 'delete') then
            v_con_delete := array_append(v_con_delete, v_tabla);
        end if;
        assert not has_table_privilege('kairo_worker', 'public.' || v_tabla, 'delete'),
        'kairo_worker no debe borrar en ' || v_tabla;
        assert not has_table_privilege('kairo_lectura', 'public.' || v_tabla, 'select'),
        'kairo_lectura no debe leer la tabla ' || v_tabla;
        assert not has_table_privilege('kairo_lectura', 'public.' || v_tabla, 'insert, update, delete'),
        'kairo_lectura no debe escribir en ' || v_tabla;
        assert not has_table_privilege('kairo_app', 'public.' || v_tabla, 'truncate'),
        'kairo_app no debe truncar ' || v_tabla;
    end loop;
    assert v_con_delete = array['actividad_etiqueta'],
    'kairo_app solo borra en la tabla puente de etiquetas: ' || v_con_delete::text;

    for v_tabla in
        select c.relname::text from pg_class as c
        inner join pg_namespace as n on c.relnamespace = n.oid
        where n.nspname = 'public' and c.relkind = 'v'
    loop
        -- Desde la migracion 017: kairo_lectura lee solo las vistas agregadas (vl_*) y
        -- kairo_app solo las vistas por usuario (v_*).
        assert has_table_privilege('kairo_lectura', 'public.' || v_tabla, 'select')
        = (v_tabla like 'vl\_%'),
        'kairo_lectura lee solo las vistas agregadas: ' || v_tabla;
        assert has_table_privilege('kairo_app', 'public.' || v_tabla, 'select')
        = (v_tabla not like 'vl\_%'),
        'kairo_app lee solo las vistas por usuario: ' || v_tabla;
        assert not has_table_privilege('kairo_lectura', 'public.' || v_tabla, 'insert, update, delete'),
        'kairo_lectura no debe escribir en la vista ' || v_tabla;
    end loop;

    assert not has_schema_privilege('kairo_app', 'public', 'create'), 'kairo_app no crea objetos';
    assert not has_schema_privilege('kairo_worker', 'public', 'create'), 'kairo_worker no crea objetos';
    assert not has_schema_privilege('kairo_lectura', 'public', 'create'), 'kairo_lectura no crea objetos';

    v_a := kairo_registrar_usuario('a_' || gen_random_uuid() || '@prueba.mx', 'hash', 'A', 'America/Mexico_City');

    set local role kairo_app;
    begin
        create table intruso (id integer);
        assert false, 'kairo_app no ejecuta DDL';
    exception when insufficient_privilege then
        null;
    end;
    begin
        delete from materia;
        assert false, 'kairo_app no borra materias';
    exception when insufficient_privilege then
        null;
    end;
    reset role;

    set local role kairo_lectura;
    begin
        perform 1 from actividad;
        assert false, 'kairo_lectura no lee tablas base';
    exception when insufficient_privilege then
        null;
    end;
    perform set_config('app.usuario_id', v_a::text, true);
    begin
        perform 1 from v_agenda_proxima;
        assert false, 'kairo_lectura no lee vistas por usuario (desde la migracion 017)';
    exception when insufficient_privilege then
        null;
    end;
    perform 1 from vl_desempeno_pipeline;
    begin
        insert into materia (usuario_id, nombre, periodo) values (v_a, 'X', '2026-3');
        assert false, 'kairo_lectura no escribe';
    exception when insufficient_privilege then
        null;
    end;
    reset role;

    perform set_config('app.usuario_id', '', true);
    set local role kairo_app;
    select count(*) into v_n from v_desempeno_pipeline where total > 0;
    assert v_n = 0, 'sin usuario en la sesion las vistas no devuelven datos';
end
$$;

rollback;
