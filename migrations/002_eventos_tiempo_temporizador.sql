alter table actividad
add constraint actividad_id_usuario_unico unique (id, usuario_id);

create function validar_categoria_del_usuario() returns trigger
language plpgsql
as $$
begin
    if not exists (
        select 1 from categoria_actividad as c
        where c.id = new.categoria_id
            and (c.usuario_id is null or c.usuario_id = new.usuario_id)
    ) then
        raise foreign_key_violation using message = 'categoria_id no es del sistema ni del usuario';
    end if;
    return new;
end
$$;

comment on function validar_categoria_del_usuario() is
'Trigger generico: la categoria debe ser del sistema o del mismo usuario que la fila.';

create table evento_calendario (
    id uuid primary key default gen_random_uuid(),
    usuario_id uuid not null references usuario (id),
    materia_id uuid,
    titulo text not null,
    descripcion text,
    lugar text,
    inicio timestamptz not null,
    fin timestamptz not null,
    creado_en timestamptz not null default now(),
    constraint evento_materia_del_usuario
    foreign key (materia_id, usuario_id) references materia (id, usuario_id),
    constraint evento_titulo_no_vacio check (length(btrim(titulo)) > 0),
    constraint evento_fin_posterior check (fin > inicio)
);

create index evento_usuario_inicio_idx on evento_calendario (usuario_id, inicio);

comment on table evento_calendario is 'Eventos con hora de inicio y fin: clases, examenes, citas.';
comment on column evento_calendario.usuario_id is 'Dueno del evento.';
comment on column evento_calendario.materia_id is
'Materia asociada; nula si no aplica. Debe ser del mismo usuario.';
comment on column evento_calendario.titulo is 'Titulo corto.';
comment on column evento_calendario.descripcion is 'Detalle libre.';
comment on column evento_calendario.lugar is 'Lugar o enlace de la reunion.';
comment on column evento_calendario.inicio is 'Inicio con zona horaria.';
comment on column evento_calendario.fin is 'Fin con zona horaria; siempre posterior al inicio.';
comment on column evento_calendario.creado_en is 'Momento de creacion.';

create table registro_tiempo (
    id uuid primary key default gen_random_uuid(),
    usuario_id uuid not null references usuario (id),
    categoria_id uuid not null references categoria_actividad (id),
    actividad_id uuid,
    inicio timestamptz not null,
    fin timestamptz not null,
    origen text not null default 'manual',
    nota text,
    creado_en timestamptz not null default now(),
    constraint registro_actividad_del_usuario
    foreign key (actividad_id, usuario_id) references actividad (id, usuario_id),
    constraint registro_origen_valido check (origen in ('temporizador', 'manual')),
    constraint registro_fin_posterior check (fin > inicio),
    constraint registro_id_usuario_unico unique (id, usuario_id)
);

create index registro_usuario_categoria_inicio_idx
on registro_tiempo (usuario_id, categoria_id, inicio);

create trigger registro_categoria_del_usuario
before insert or update of categoria_id, usuario_id on registro_tiempo
for each row execute function validar_categoria_del_usuario();

comment on table registro_tiempo is 'Tiempo dedicado a una categoria, medido o capturado a mano.';
comment on column registro_tiempo.usuario_id is 'Dueno del registro.';
comment on column registro_tiempo.categoria_id is 'Categoria del sistema o propia del usuario.';
comment on column registro_tiempo.actividad_id is
'Actividad a la que se dedico el tiempo; nula si no aplica. Debe ser del mismo usuario.';
comment on column registro_tiempo.inicio is 'Inicio con zona horaria.';
comment on column registro_tiempo.fin is 'Fin con zona horaria; siempre posterior al inicio.';
comment on column registro_tiempo.origen is 'temporizador o manual.';
comment on column registro_tiempo.nota is 'Comentario libre.';
comment on column registro_tiempo.creado_en is 'Momento de creacion.';

create table sesion_temporizador (
    id uuid primary key default gen_random_uuid(),
    usuario_id uuid not null references usuario (id),
    categoria_id uuid not null references categoria_actividad (id),
    actividad_id uuid,
    iniciada_en timestamptz not null default now(),
    estado text not null default 'en_curso',
    cerrada_en timestamptz,
    registro_tiempo_id uuid,
    constraint sesion_actividad_del_usuario
    foreign key (actividad_id, usuario_id) references actividad (id, usuario_id),
    constraint sesion_registro_del_usuario
    foreign key (registro_tiempo_id, usuario_id) references registro_tiempo (id, usuario_id),
    constraint sesion_estado_valido check (estado in ('en_curso', 'cerrada')),
    constraint sesion_cierre_coherente check ((estado = 'cerrada') = (cerrada_en is not null))
);

create unique index sesion_una_en_curso_por_usuario
on sesion_temporizador (usuario_id) where estado = 'en_curso';

create trigger sesion_categoria_del_usuario
before insert or update of categoria_id, usuario_id on sesion_temporizador
for each row execute function validar_categoria_del_usuario();

comment on table sesion_temporizador is
'Temporizador sin pausa: iniciar y detener. Una sola sesion en curso por usuario.';
comment on column sesion_temporizador.usuario_id is 'Dueno de la sesion.';
comment on column sesion_temporizador.categoria_id is
'Categoria a la que se contara el tiempo.';
comment on column sesion_temporizador.actividad_id is 'Actividad asociada; nula si no aplica.';
comment on column sesion_temporizador.iniciada_en is 'Momento en que arranco el temporizador.';
comment on column sesion_temporizador.estado is
'en_curso o cerrada. Se cierra con UPDATE porque kairo_app no tiene DELETE.';
comment on column sesion_temporizador.cerrada_en is
'Momento de cierre; nulo mientras esta en curso.';
comment on column sesion_temporizador.registro_tiempo_id is
'Registro que se genero al detener la sesion.';

alter table evento_calendario enable row level security;
alter table registro_tiempo enable row level security;
alter table sesion_temporizador enable row level security;

create policy evento_propio on evento_calendario for all to kairo_app
using (usuario_id = app_usuario_id()) with check (usuario_id = app_usuario_id());

create policy registro_propio on registro_tiempo for all to kairo_app
using (usuario_id = app_usuario_id()) with check (usuario_id = app_usuario_id());

create policy sesion_propia on sesion_temporizador for all to kairo_app
using (usuario_id = app_usuario_id()) with check (usuario_id = app_usuario_id());

grant select, insert, update on evento_calendario, registro_tiempo, sesion_temporizador
to kairo_app;
