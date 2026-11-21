create table bitacora_cambios (
    id uuid primary key default gen_random_uuid(),
    usuario_id uuid not null references usuario (id),
    actividad_id uuid,
    registro_tiempo_id uuid,
    campo text not null,
    valor_anterior text,
    valor_nuevo text,
    cambiado_en timestamptz not null default now(),
    constraint bitacora_actividad_del_usuario
    foreign key (actividad_id, usuario_id) references actividad (id, usuario_id),
    constraint bitacora_registro_del_usuario
    foreign key (registro_tiempo_id, usuario_id) references registro_tiempo (id, usuario_id),
    constraint bitacora_un_solo_objetivo check (num_nonnulls(actividad_id, registro_tiempo_id) = 1)
);

create index bitacora_usuario_cambiado_idx on bitacora_cambios (usuario_id, cambiado_en desc);
create index bitacora_actividad_idx on bitacora_cambios (actividad_id, cambiado_en);

comment on table bitacora_cambios is
'Historial de cambios de actividad y registro de tiempo; lo escriben los triggers.';
comment on column bitacora_cambios.usuario_id is 'Dueno del dato; permite filtrar con RLS.';
comment on column bitacora_cambios.actividad_id is
'Actividad modificada; excluyente con registro_tiempo_id.';
comment on column bitacora_cambios.registro_tiempo_id is
'Registro de tiempo modificado; excluyente con actividad_id.';
comment on column bitacora_cambios.campo is 'Nombre de la columna que cambio.';
comment on column bitacora_cambios.valor_anterior is 'Valor previo como texto; nulo en el alta.';
comment on column bitacora_cambios.valor_nuevo is 'Valor nuevo como texto.';
comment on column bitacora_cambios.cambiado_en is 'Momento del cambio.';

create function actividad_registrar_estado() returns trigger
language plpgsql security definer set search_path = public, pg_temp
as $$
begin
    if tg_op = 'INSERT' or old.estado is distinct from new.estado then
        insert into bitacora_cambios (usuario_id, actividad_id, campo, valor_anterior, valor_nuevo)
        values (
            new.usuario_id,
            new.id,
            'estado',
            case when tg_op = 'UPDATE' then old.estado end,
            new.estado
        );
    end if;
    return new;
end
$$;

comment on function actividad_registrar_estado() is
'Anota en la bitacora el estado inicial y cada cambio de estado de una actividad.';

create trigger actividad_bitacora_estado
after insert or update of estado on actividad
for each row execute function actividad_registrar_estado();

alter table bitacora_cambios enable row level security;

create policy bitacora_select_propia on bitacora_cambios for select to kairo_app
using (usuario_id = app_usuario_id());

grant select on bitacora_cambios to kairo_app;
