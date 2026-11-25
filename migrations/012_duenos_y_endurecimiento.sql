-- Decision 006 (D1, opcion A): kairo_owner es dueno de todo el esquema, con BYPASSRLS y NOLOGIN.
-- Ningun rol de conexion es dueno ni tiene BYPASSRLS; por eso FORCE no cambia el comportamiento
-- de las funciones security definer ni de las vistas, y deja la regla explicita en cada tabla.

alter role kairo_owner nologin bypassrls;

-- Postgres 16+ no da SET ni INHERIT al creador del rol. SET permite transferir la propiedad y
-- aplicar migraciones con "set role kairo_owner"; INHERIT mantiene el acceso del rol que
-- administra el proyecto (en Supabase, postgres no es superusuario).
-- Va en execute porque sqlfluff no reconoce la sintaxis "with ... true".
do $$
begin
    execute format('grant kairo_owner to %I with inherit true, set true', current_user);
end
$$;

grant usage, create on schema public to kairo_owner;

do $$
declare
    v_obj record;
begin
    for v_obj in
        select format('alter %s %s owner to kairo_owner',
            case c.relkind when 'v' then 'view' when 'S' then 'sequence' else 'table' end,
            c.oid::regclass) as sql
        from pg_class as c
        where c.relnamespace = 'public'::regnamespace
            and c.relkind in ('r', 'p', 'v', 'S')
            and c.relowner <> 'kairo_owner'::regrole
        union all
        select format('alter function %s owner to kairo_owner', p.oid::regprocedure) as sql
        from pg_proc as p
        where p.pronamespace = 'public'::regnamespace
            and p.proowner <> 'kairo_owner'::regrole
    loop
        execute v_obj.sql;
    end loop;
end
$$;

do $$
declare
    v_tabla regclass;
begin
    for v_tabla in
        select c.oid::regclass from pg_class as c
        where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'p')
    loop
        execute format('alter table %s enable row level security', v_tabla);
        execute format('alter table %s force row level security', v_tabla);
    end loop;
end
$$;

-- Fija search_path en las funciones que no lo tienen (aviso 0011 del linter de Supabase):
-- app_usuario_id, actividad_fijar_completada_en, actividad_validar_categoria,
-- validar_categoria_del_usuario y autoevaluacion_marcar_actualizada.
do $$
declare
    v_funcion regprocedure;
begin
    for v_funcion in
        select p.oid::regprocedure from pg_proc as p
        where p.pronamespace = 'public'::regnamespace
            and not exists (
                select 1 from unnest(coalesce(p.proconfig, '{}')) as c (opcion)
                where c.opcion like 'search_path=%'
            )
    loop
        execute format('alter function %s set search_path = public, pg_temp', v_funcion);
    end loop;
end
$$;

revoke execute on function
actividad_fijar_completada_en(),
actividad_validar_categoria(),
validar_categoria_del_usuario(),
actividad_registrar_estado(),
registro_tiempo_actualizar_resumen(),
registro_tiempo_registrar_cambios(),
autoevaluacion_marcar_actualizada()
from public;

alter default privileges for role kairo_owner in schema public
revoke execute on functions from public;

comment on role kairo_owner is
'Dueno del esquema; solo para migraciones. NOLOGIN y BYPASSRLS.';
