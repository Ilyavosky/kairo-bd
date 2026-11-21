create table meta (
    id uuid primary key default gen_random_uuid(),
    usuario_id uuid not null references usuario (id),
    categoria_id uuid not null references categoria_actividad (id),
    tipo text not null,
    periodo text not null,
    objetivo integer not null,
    vigente_desde date not null default current_date,
    vigente_hasta date,
    activa boolean not null default true,
    creada_en timestamptz not null default now(),
    constraint meta_tipo_valido check (tipo in ('tiempo_acumulado', 'numero_eventos')),
    constraint meta_periodo_valido check (periodo in ('dia', 'semana', 'mes')),
    constraint meta_objetivo_positivo check (objetivo > 0),
    constraint meta_vigencia_valida
    check (vigente_hasta is null or vigente_hasta >= vigente_desde),
    constraint meta_id_usuario_unico unique (id, usuario_id)
);

create unique index meta_activa_unica
on meta (usuario_id, categoria_id, tipo, periodo) where activa;

create trigger meta_categoria_del_usuario
before insert or update of categoria_id, usuario_id on meta
for each row execute function validar_categoria_del_usuario();

comment on table meta is 'Objetivo minimo por categoria y periodo; sin tope en v1.';
comment on column meta.usuario_id is 'Dueno de la meta.';
comment on column meta.categoria_id is 'Categoria que se mide.';
comment on column meta.tipo is
'tiempo_acumulado (objetivo en minutos) o numero_eventos (objetivo en registros de tiempo).';
comment on column meta.periodo is
'dia, semana (desde el lunes) o mes, en la zona horaria del usuario.';
comment on column meta.objetivo is 'Minimo a alcanzar en cada periodo; entero positivo.';
comment on column meta.vigente_desde is 'Primer dia en que la meta aplica.';
comment on column meta.vigente_hasta is 'Ultimo dia en que la meta aplica; nulo si no vence.';
comment on column meta.activa is
'Falso al darla de baja. Solo una meta activa por categoria, tipo y periodo.';
comment on column meta.creada_en is 'Momento de creacion.';

create table evaluacion_meta (
    id uuid primary key default gen_random_uuid(),
    meta_id uuid not null,
    usuario_id uuid not null,
    periodo_desde timestamptz not null,
    periodo_hasta timestamptz not null,
    objetivo integer not null,
    valor_logrado numeric(10, 2) not null,
    cumplida boolean not null,
    evaluada_en timestamptz not null default now(),
    constraint evaluacion_meta_del_usuario
    foreign key (meta_id, usuario_id) references meta (id, usuario_id),
    constraint evaluacion_rango_valido check (periodo_hasta > periodo_desde),
    constraint evaluacion_valor_no_negativo check (valor_logrado >= 0),
    constraint evaluacion_periodo_unico unique (meta_id, periodo_desde)
);

create index evaluacion_usuario_periodo_idx on evaluacion_meta (usuario_id, periodo_desde desc);

comment on table evaluacion_meta is
'Resultado de cada periodo cerrado de una meta; lo escribe el proceso programado.';
comment on column evaluacion_meta.meta_id is 'Meta evaluada.';
comment on column evaluacion_meta.usuario_id is 'Dueno de la meta; permite filtrar con RLS.';
comment on column evaluacion_meta.periodo_desde is 'Inicio del periodo evaluado.';
comment on column evaluacion_meta.periodo_hasta is 'Fin del periodo evaluado.';
comment on column evaluacion_meta.objetivo is 'Objetivo vigente al evaluar.';
comment on column evaluacion_meta.valor_logrado is
'Minutos o numero de registros alcanzados en el periodo.';
comment on column evaluacion_meta.cumplida is 'Verdadero si valor_logrado alcanzo el objetivo.';
comment on column evaluacion_meta.evaluada_en is 'Momento en que se evaluo.';

alter table meta enable row level security;
alter table evaluacion_meta enable row level security;

create policy meta_propia on meta for all to kairo_app
using (usuario_id = app_usuario_id()) with check (usuario_id = app_usuario_id());

create policy evaluacion_select_propia on evaluacion_meta for select to kairo_app
using (usuario_id = app_usuario_id());

grant select, insert, update on meta to kairo_app;
grant select on evaluacion_meta to kairo_app;
