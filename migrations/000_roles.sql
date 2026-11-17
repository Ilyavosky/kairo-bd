do $$
declare
    v_rol text;
begin
    foreach v_rol in array array['kairo_owner', 'kairo_app', 'kairo_worker', 'kairo_lectura']
    loop
        if not exists (select 1 from pg_roles where rolname = v_rol) then
            execute format('create role %I nologin', v_rol);
        end if;
    end loop;
end
$$;

grant usage on schema public to kairo_app, kairo_worker, kairo_lectura;
