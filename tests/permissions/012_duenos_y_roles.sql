begin;

do $$
declare
    v_lista text;
begin
    select string_agg(c.relname, ', ') into v_lista
    from pg_class as c
    where c.relnamespace = 'public'::regnamespace
        and c.relkind in ('r', 'p', 'v', 'm', 'S')
        and c.relowner <> 'kairo_owner'::regrole;
    assert v_lista is null, 'Relaciones que no son de kairo_owner: ' || v_lista;

    select string_agg(p.proname, ', ') into v_lista
    from pg_proc as p
    where p.pronamespace = 'public'::regnamespace and p.proowner <> 'kairo_owner'::regrole;
    assert v_lista is null, 'Funciones que no son de kairo_owner: ' || v_lista;

    select string_agg(c.relname, ', ') into v_lista
    from pg_class as c
    where c.relnamespace = 'public'::regnamespace
        and c.relkind in ('r', 'p')
        and not (c.relrowsecurity and c.relforcerowsecurity);
    assert v_lista is null, 'Tablas sin RLS habilitada y forzada: ' || v_lista;

    select string_agg(r.rolname, ', ') into v_lista
    from pg_roles as r
    where r.rolname in ('kairo_app', 'kairo_worker', 'kairo_lectura')
        and (r.rolsuper or r.rolbypassrls or r.rolcreaterole or r.rolcreatedb);
    assert v_lista is null, 'Roles de conexion con atributos de mas: ' || v_lista;

    select string_agg(r.rolname, ', ') into v_lista
    from pg_roles as r
    where pg_has_role(r.oid, 'kairo_owner', 'member')
        and r.rolname in ('kairo_app', 'kairo_worker', 'kairo_lectura');
    assert v_lista is null, 'Roles de conexion miembros de kairo_owner: ' || v_lista;

    assert (
        select not r.rolcanlogin and r.rolbypassrls from pg_roles as r
        where r.rolname = 'kairo_owner'
    ), 'kairo_owner debe ser NOLOGIN y BYPASSRLS';

    select string_agg(p.proname, ', ') into v_lista
    from pg_proc as p
    where p.pronamespace = 'public'::regnamespace
        and has_function_privilege('public', p.oid, 'execute')
        and (p.prosecdef or p.prorettype = 'trigger'::regtype);
    assert v_lista is null,
    'Funciones security definer o de trigger ejecutables por PUBLIC: ' || v_lista;

    select string_agg(p.proname, ', ') into v_lista
    from pg_proc as p
    where p.pronamespace = 'public'::regnamespace
        and not exists (
            select 1 from unnest(coalesce(p.proconfig, '{}')) as c (opcion)
            where c.opcion like 'search_path=%'
        );
    assert v_lista is null, 'Funciones sin search_path fijo: ' || v_lista;
end
$$;

rollback;
