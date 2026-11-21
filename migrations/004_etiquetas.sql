create table etiqueta (
    id uuid primary key default gen_random_uuid(),
    usuario_id uuid not null references usuario (id),
    nombre text not null,
    constraint etiqueta_nombre_no_vacio check (length(btrim(nombre)) > 0),
    constraint etiqueta_id_usuario_unico unique (id, usuario_id)
);

create unique index etiqueta_nombre_usuario_unico on etiqueta (usuario_id, lower(nombre));

create table actividad_etiqueta (
    actividad_id uuid not null,
    etiqueta_id uuid not null,
    usuario_id uuid not null,
    primary key (actividad_id, etiqueta_id),
    constraint actividad_etiqueta_actividad_del_usuario
    foreign key (actividad_id, usuario_id) references actividad (id, usuario_id),
    constraint actividad_etiqueta_etiqueta_del_usuario
    foreign key (etiqueta_id, usuario_id) references etiqueta (id, usuario_id)
);

create index actividad_etiqueta_etiqueta_idx on actividad_etiqueta (etiqueta_id);

comment on table etiqueta is 'Etiquetas libres de cada usuario.';
comment on column etiqueta.usuario_id is 'Dueno de la etiqueta.';
comment on column etiqueta.nombre is 'Nombre; unico por usuario sin distinguir mayusculas.';
comment on table actividad_etiqueta is
'Tabla puente entre actividades y etiquetas del mismo usuario.';
comment on column actividad_etiqueta.actividad_id is 'Actividad etiquetada.';
comment on column actividad_etiqueta.etiqueta_id is 'Etiqueta aplicada.';
comment on column actividad_etiqueta.usuario_id is
'Dueno de ambas; las llaves compuestas impiden mezclar usuarios.';

alter table etiqueta enable row level security;
alter table actividad_etiqueta enable row level security;

create policy etiqueta_propia on etiqueta for all to kairo_app
using (usuario_id = app_usuario_id()) with check (usuario_id = app_usuario_id());

create policy actividad_etiqueta_propia on actividad_etiqueta for all to kairo_app
using (usuario_id = app_usuario_id()) with check (usuario_id = app_usuario_id());

grant select, insert on etiqueta to kairo_app;
grant select, insert, delete on actividad_etiqueta to kairo_app;
