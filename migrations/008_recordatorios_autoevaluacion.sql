alter table evento_calendario
add constraint evento_id_usuario_unico unique (id, usuario_id);

create table recordatorio (
    id uuid primary key default gen_random_uuid(),
    usuario_id uuid not null references usuario (id),
    actividad_id uuid,
    evento_id uuid,
    meta_id uuid,
    momento timestamptz not null,
    estado_envio text not null default 'pendiente',
    intentos smallint not null default 0,
    enviado_en timestamptz,
    ultimo_error text,
    creado_en timestamptz not null default now(),
    constraint recordatorio_actividad_del_usuario
    foreign key (actividad_id, usuario_id) references actividad (id, usuario_id),
    constraint recordatorio_evento_del_usuario
    foreign key (evento_id, usuario_id) references evento_calendario (id, usuario_id),
    constraint recordatorio_meta_del_usuario
    foreign key (meta_id, usuario_id) references meta (id, usuario_id),
    constraint recordatorio_un_solo_objetivo
    check (num_nonnulls(actividad_id, evento_id, meta_id) = 1),
    constraint recordatorio_estado_valido
    check (estado_envio in ('pendiente', 'enviado', 'fallido', 'cancelado')),
    constraint recordatorio_intentos_validos check (intentos >= 0),
    constraint recordatorio_enviado_coherente
    check ((estado_envio = 'enviado') = (enviado_en is not null))
);

create index recordatorio_pendientes_idx on recordatorio (momento) where estado_envio = 'pendiente';
create index recordatorio_usuario_momento_idx on recordatorio (usuario_id, momento desc);

comment on table recordatorio is
'Aviso programado sobre una actividad, un evento o una meta; se envia por Telegram.';
comment on column recordatorio.usuario_id is 'Dueno del recordatorio.';
comment on column recordatorio.actividad_id is 'Objetivo; excluyente con evento_id y meta_id.';
comment on column recordatorio.evento_id is 'Objetivo; excluyente con actividad_id y meta_id.';
comment on column recordatorio.meta_id is 'Objetivo; excluyente con actividad_id y evento_id.';
comment on column recordatorio.momento is 'Cuando debe enviarse.';
comment on column recordatorio.estado_envio is 'pendiente, enviado, fallido o cancelado.';
comment on column recordatorio.intentos is 'Intentos de envio hechos por el despachador.';
comment on column recordatorio.enviado_en is 'Momento del envio; nulo si no se envio.';
comment on column recordatorio.ultimo_error is 'Motivo del ultimo intento fallido.';
comment on column recordatorio.creado_en is 'Momento de creacion.';

create table autoevaluacion_semanal (
    id uuid primary key default gen_random_uuid(),
    usuario_id uuid not null references usuario (id),
    semana_desde date not null,
    estado_animo smallint not null,
    satisfaccion smallint not null,
    nota text,
    creada_en timestamptz not null default now(),
    actualizada_en timestamptz not null default now(),
    constraint autoevaluacion_semana_unica unique (usuario_id, semana_desde),
    constraint autoevaluacion_lunes check (extract(isodow from semana_desde) = 1),
    constraint autoevaluacion_animo_valido check (estado_animo between 1 and 5),
    constraint autoevaluacion_satisfaccion_valida check (satisfaccion between 1 and 5)
);

comment on table autoevaluacion_semanal is
'Estado de animo y satisfaccion de la semana; una por usuario y semana.';
comment on column autoevaluacion_semanal.usuario_id is 'Dueno de la autoevaluacion.';
comment on column autoevaluacion_semanal.semana_desde is 'Lunes de la semana evaluada.';
comment on column autoevaluacion_semanal.estado_animo is 'De 1 (muy bajo) a 5 (muy alto).';
comment on column autoevaluacion_semanal.satisfaccion is
'De 1 (muy baja) a 5 (muy alta) con lo logrado en la semana.';
comment on column autoevaluacion_semanal.nota is 'Comentario libre.';
comment on column autoevaluacion_semanal.creada_en is 'Momento de creacion.';
comment on column autoevaluacion_semanal.actualizada_en is 'Ultima modificacion.';

create function autoevaluacion_marcar_actualizada() returns trigger
language plpgsql
as $$
begin
    new.actualizada_en := clock_timestamp();
    return new;
end
$$;

create trigger autoevaluacion_actualizada
before update on autoevaluacion_semanal
for each row execute function autoevaluacion_marcar_actualizada();

alter table recordatorio enable row level security;
alter table autoevaluacion_semanal enable row level security;

create policy recordatorio_select_propio on recordatorio for select to kairo_app
using (usuario_id = app_usuario_id());

create policy recordatorio_insert_propio on recordatorio for insert to kairo_app
with check (usuario_id = app_usuario_id() and estado_envio = 'pendiente');

create policy recordatorio_update_propio on recordatorio for update to kairo_app
using (usuario_id = app_usuario_id() and estado_envio = 'pendiente')
with check (usuario_id = app_usuario_id() and estado_envio in ('pendiente', 'cancelado'));

create policy autoevaluacion_propia on autoevaluacion_semanal for all to kairo_app
using (usuario_id = app_usuario_id()) with check (usuario_id = app_usuario_id());

grant select on recordatorio to kairo_app;
grant insert (usuario_id, actividad_id, evento_id, meta_id, momento) on recordatorio to kairo_app;
grant update (momento, estado_envio) on recordatorio to kairo_app;
grant select, insert on autoevaluacion_semanal to kairo_app;
grant update (estado_animo, satisfaccion, nota) on autoevaluacion_semanal to kairo_app;
