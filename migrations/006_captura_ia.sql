create table mensaje_origen (
    id uuid primary key default gen_random_uuid(),
    usuario_id uuid not null references usuario (id),
    canal text not null default 'app',
    texto text not null,
    recibido_en timestamptz not null default now(),
    constraint mensaje_canal_valido check (canal in ('app', 'telegram')),
    constraint mensaje_texto_valido check (length(btrim(texto)) between 1 and 2000),
    constraint mensaje_id_usuario_unico unique (id, usuario_id)
);

create index mensaje_usuario_recibido_idx on mensaje_origen (usuario_id, recibido_en desc);

comment on table mensaje_origen is 'Texto libre recibido del usuario; origen de cada captura.';
comment on column mensaje_origen.usuario_id is 'Dueno del mensaje.';
comment on column mensaje_origen.canal is 'app o telegram.';
comment on column mensaje_origen.texto is 'Texto tal como lo escribio el usuario.';
comment on column mensaje_origen.recibido_en is 'Momento de recepcion.';

create table extraccion (
    id uuid primary key default gen_random_uuid(),
    usuario_id uuid not null references usuario (id),
    mensaje_origen_id uuid not null,
    entidad_tipo text not null,
    propuesta jsonb not null,
    resuelta jsonb not null,
    pendientes text[] not null default '{}',
    modelo text not null,
    confianza numeric(4, 3),
    estado text not null default 'pendiente',
    actividad_id uuid,
    registro_tiempo_id uuid,
    meta_id uuid,
    creada_en timestamptz not null default now(),
    resuelta_en timestamptz,
    constraint extraccion_mensaje_del_usuario
    foreign key (mensaje_origen_id, usuario_id) references mensaje_origen (id, usuario_id),
    constraint extraccion_actividad_del_usuario
    foreign key (actividad_id, usuario_id) references actividad (id, usuario_id),
    constraint extraccion_registro_del_usuario
    foreign key (registro_tiempo_id, usuario_id) references registro_tiempo (id, usuario_id),
    constraint extraccion_meta_del_usuario
    foreign key (meta_id, usuario_id) references meta (id, usuario_id),
    constraint extraccion_entidad_valida
    check (entidad_tipo in ('actividad', 'registro_tiempo', 'meta')),
    constraint extraccion_estado_valido
    check (estado in ('pendiente', 'aceptada', 'corregida', 'descartada')),
    constraint extraccion_confianza_valida check (confianza is null or confianza between 0 and 1),
    constraint extraccion_destino_coherente check (
        (entidad_tipo = 'actividad' or actividad_id is null)
        and (entidad_tipo = 'registro_tiempo' or registro_tiempo_id is null)
        and (entidad_tipo = 'meta' or meta_id is null)
    ),
    constraint extraccion_resultado_coherente check (
        (estado in ('aceptada', 'corregida'))
        = (num_nonnulls(actividad_id, registro_tiempo_id, meta_id) = 1)
    ),
    constraint extraccion_cierre_coherente check ((estado = 'pendiente') = (resuelta_en is null)),
    constraint extraccion_id_usuario_unico unique (id, usuario_id)
);

create index extraccion_usuario_estado_idx on extraccion (usuario_id, estado, creada_en desc);
create index extraccion_mensaje_idx on extraccion (mensaje_origen_id);

comment on table extraccion is
'Propuesta del modelo para un mensaje, con su resolucion contra la base y su desenlace.';
comment on column extraccion.usuario_id is 'Dueno de la extraccion.';
comment on column extraccion.mensaje_origen_id is 'Mensaje del que sale la propuesta.';
comment on column extraccion.entidad_tipo is 'actividad, registro_tiempo o meta.';
comment on column extraccion.propuesta is 'Salida del modelo sin modificar.';
comment on column extraccion.resuelta is
'Propuesta ya resuelta contra la base: referencias por id y fechas absolutas.';
comment on column extraccion.pendientes is
'Campos que el sistema no pudo resolver y el usuario debe completar.';
comment on column extraccion.modelo is 'Identificador del modelo que produjo la propuesta.';
comment on column extraccion.confianza is 'Confianza declarada por el modelo, de 0 a 1.';
comment on column extraccion.estado is 'pendiente, aceptada, corregida o descartada.';
comment on column extraccion.actividad_id is
'Fila creada al confirmar; excluyente con las otras dos.';
comment on column extraccion.registro_tiempo_id is
'Fila creada al confirmar; excluyente con las otras dos.';
comment on column extraccion.meta_id is 'Fila creada al confirmar; excluyente con las otras dos.';
comment on column extraccion.creada_en is 'Momento en que se creo la propuesta.';
comment on column extraccion.resuelta_en is
'Momento en que el usuario la cerro; nulo mientras pendiente.';

create table correccion_campo (
    id uuid primary key default gen_random_uuid(),
    usuario_id uuid not null references usuario (id),
    extraccion_id uuid not null,
    campo text not null,
    valor_propuesto jsonb,
    valor_final jsonb,
    corregido_en timestamptz not null default now(),
    constraint correccion_extraccion_del_usuario
    foreign key (extraccion_id, usuario_id) references extraccion (id, usuario_id),
    constraint correccion_campo_no_vacio check (length(btrim(campo)) > 0),
    constraint correccion_campo_unico unique (extraccion_id, campo),
    constraint correccion_cambia check (valor_propuesto is distinct from valor_final)
);

comment on table correccion_campo is
'Campos que el usuario cambio respecto de la propuesta; insumo para medir y mejorar el modelo.';
comment on column correccion_campo.usuario_id is 'Dueno de la correccion.';
comment on column correccion_campo.extraccion_id is 'Extraccion corregida.';
comment on column correccion_campo.campo is 'Nombre del campo corregido.';
comment on column correccion_campo.valor_propuesto is 'Valor resuelto antes de corregir.';
comment on column correccion_campo.valor_final is 'Valor con el que se creo la fila.';
comment on column correccion_campo.corregido_en is 'Momento de la correccion.';

create table resumen_periodo (
    usuario_id uuid not null references usuario (id),
    categoria_id uuid not null references categoria_actividad (id),
    periodo text not null,
    periodo_desde date not null,
    segundos bigint not null default 0,
    registros integer not null default 0,
    actualizado_en timestamptz not null default now(),
    constraint resumen_pk primary key (usuario_id, categoria_id, periodo, periodo_desde),
    constraint resumen_periodo_valido check (periodo in ('dia', 'semana', 'mes')),
    constraint resumen_no_negativo check (segundos >= 0 and registros >= 0)
);

comment on table resumen_periodo is
'Cache de tiempo registrado por categoria y periodo; lo mantiene un trigger de registro_tiempo.';
comment on column resumen_periodo.usuario_id is 'Dueno del resumen.';
comment on column resumen_periodo.categoria_id is 'Categoria agregada.';
comment on column resumen_periodo.periodo is 'dia, semana (inicia en lunes) o mes.';
comment on column resumen_periodo.periodo_desde is
'Primer dia del periodo en la zona horaria del usuario.';
comment on column resumen_periodo.segundos is 'Segundos registrados en el periodo.';
comment on column resumen_periodo.registros is
'Cantidad de registros de tiempo en el periodo.';
comment on column resumen_periodo.actualizado_en is 'Ultima actualizacion.';

alter table mensaje_origen enable row level security;
alter table extraccion enable row level security;
alter table correccion_campo enable row level security;
alter table resumen_periodo enable row level security;

create policy mensaje_propio on mensaje_origen for all to kairo_app
using (usuario_id = app_usuario_id()) with check (usuario_id = app_usuario_id());

create policy extraccion_propia on extraccion for all to kairo_app
using (usuario_id = app_usuario_id()) with check (usuario_id = app_usuario_id());

create policy correccion_propia on correccion_campo for all to kairo_app
using (usuario_id = app_usuario_id()) with check (usuario_id = app_usuario_id());

create policy resumen_select_propio on resumen_periodo for select to kairo_app
using (usuario_id = app_usuario_id());

grant select, insert on mensaje_origen to kairo_app;
grant select, insert on extraccion to kairo_app;
grant update (estado, actividad_id, registro_tiempo_id, meta_id, resuelta_en)
on extraccion to kairo_app;
grant select, insert on correccion_campo to kairo_app;
grant select on resumen_periodo to kairo_app;
