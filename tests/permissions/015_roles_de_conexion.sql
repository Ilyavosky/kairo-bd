begin;

do $$
declare
    v_lista text;
begin
    select string_agg(r.rolname, ', ') into v_lista
    from pg_roles as r
    where r.rolname in ('kairo_api', 'kairo_despachador')
        and (
            not r.rolcanlogin or r.rolsuper or r.rolbypassrls
            or r.rolcreaterole or r.rolcreatedb or r.rolreplication
        );
    assert v_lista is null, 'Roles de conexion con atributos incorrectos: ' || v_lista;

    assert (
        select string_agg(pg_get_userbyid(m.roleid), ',' order by 1)
        from pg_auth_members as m where m.member = 'kairo_api'::regrole
    ) = 'kairo_app', 'kairo_api solo debe pertenecer a kairo_app';

    assert (
        select string_agg(pg_get_userbyid(m.roleid), ',' order by 1)
        from pg_auth_members as m where m.member = 'kairo_despachador'::regrole
    ) = 'kairo_worker', 'kairo_despachador solo debe pertenecer a kairo_worker';

    assert not exists (
        select 1 from pg_class
        where relowner in ('kairo_api'::regrole, 'kairo_despachador'::regrole)
        union all
        select 1 from pg_proc
        where proowner in ('kairo_api'::regrole, 'kairo_despachador'::regrole)
    ), 'Los roles de conexion no deben ser duenos de objetos';

    assert not pg_has_role('kairo_api', 'kairo_worker', 'member')
    and not pg_has_role('kairo_api', 'kairo_owner', 'member')
    and not pg_has_role('kairo_despachador', 'kairo_app', 'member')
    and not pg_has_role('kairo_despachador', 'kairo_owner', 'member'),
    'Los roles de conexion no deben cruzarse ni llegar a kairo_owner';
end
$$;

-- Aislamiento real con kairo_api como usuario de la sesion.
create temporary table _ids (a uuid, b uuid, tarea uuid) on commit drop;
insert into _ids
select
    kairo_registrar_usuario('a_' || gen_random_uuid() || '@prueba.mx', 'h', 'A', 'America/Mexico_City'),
    kairo_registrar_usuario('b_' || gen_random_uuid() || '@prueba.mx', 'h', 'B', 'America/Mexico_City'),
    (select id from categoria_actividad where nombre = 'Tarea' and usuario_id is null);
grant select on _ids to kairo_api;

set local session authorization kairo_api;

do $$
declare
    v_a uuid;
    v_b uuid;
    v_tarea uuid;
    v_n integer;
begin
    select a, b, tarea into v_a, v_b, v_tarea from _ids;

    perform set_config('app.usuario_id', v_b::text, true);
    insert into actividad (usuario_id, categoria_id, titulo) values (v_b, v_tarea, 'De B');

    perform set_config('app.usuario_id', v_a::text, true);
    insert into actividad (usuario_id, categoria_id, titulo) values (v_a, v_tarea, 'De A');
    select count(*) into v_n from actividad;
    assert v_n = 1, 'kairo_api con la sesion de A solo ve la actividad de A';

    begin
        insert into actividad (usuario_id, categoria_id, titulo) values (v_b, v_tarea, 'Intruso');
        raise exception 'kairo_api no debe insertar filas de otro usuario';
    exception when insufficient_privilege then null;
    end;

    begin
        delete from actividad;
        raise exception 'kairo_api no debe poder borrar actividades';
    exception when insufficient_privilege then null;
    end;

    begin
        set local role kairo_worker;
        raise exception 'kairo_api no debe poder cambiar a kairo_worker';
    exception when insufficient_privilege then null;
    end;
end
$$;

rollback;
