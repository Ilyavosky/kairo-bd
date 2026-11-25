-- Preparacion unica del proyecto Supabase, antes de aplicar migrations/.
-- Supabase concede por defecto ALL en tablas y EXECUTE en funciones de public a anon y
-- authenticated. Kairo no usa Supabase Auth ni la Data API con esas llaves: el acceso es por
-- roles propios (kairo_app, kairo_worker, kairo_lectura). Se retiran esos privilegios por
-- defecto para que ninguna tabla, vista o funcion nueva quede expuesta a la anon key.
-- Es idempotente y no hace nada en un Postgres sin los roles de Supabase (CI).
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon')
        and exists (select 1 from pg_roles where rolname = 'authenticated') then
        alter default privileges for role postgres in schema public
        revoke all on tables from anon, authenticated;
        alter default privileges for role postgres in schema public
        revoke all on sequences from anon, authenticated;
        alter default privileges for role postgres in schema public
        revoke all on functions from anon, authenticated;
    end if;
end
$$;
