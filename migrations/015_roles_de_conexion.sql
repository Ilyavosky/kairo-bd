-- Decision 007: roles con login para los servicios. Los roles de permisos (kairo_app,
-- kairo_worker, kairo_lectura) siguen siendo NOLOGIN; cada servicio se conecta con un rol propio
-- que solo hereda el rol de permisos que necesita. Sin contrasena aqui: se define en el dashboard
-- de Supabase y se guarda en Railway. Mientras no tengan contrasena, no pueden iniciar sesion.
do $$
begin
    if not exists (select 1 from pg_roles where rolname = 'kairo_api') then
        create role kairo_api login in role kairo_app;
    end if;
    if not exists (select 1 from pg_roles where rolname = 'kairo_despachador') then
        create role kairo_despachador login in role kairo_worker;
    end if;
end
$$;

-- Si el rol ya existia, se le quitan atributos de mas. SUPERUSER y REPLICATION no se mencionan:
-- en Supabase postgres no es superusuario y no puede tocarlos; create role ya los deja en "no"
-- y la prueba 015 los verifica.
alter role kairo_api nocreatedb nocreaterole nobypassrls;
alter role kairo_despachador nocreatedb nocreaterole nobypassrls;

alter role kairo_api set statement_timeout = '15s';
alter role kairo_despachador set statement_timeout = '30s';

comment on role kairo_api is
'Conexion de la API (pooler en modo transaccion). Hereda solo kairo_app.';
comment on role kairo_despachador is
'Conexion del endpoint interno de despacho de recordatorios. Hereda solo kairo_worker.';
