create function app_usuario_id() returns uuid
language sql stable
as $$ select nullif(current_setting('app.usuario_id', true), '')::uuid $$;

comment on function app_usuario_id() is
'Usuario de la sesion, fijado por la API con set_config dentro de la transaccion.';

grant execute on function app_usuario_id() to kairo_app, kairo_worker, kairo_lectura;

create table usuario (
    id uuid primary key default gen_random_uuid(),
    email text not null,
    password_hash text not null,
    telegram_id bigint,
    nombre text not null,
    zona_horaria text not null default 'America/Mexico_City',
    fecha_registro timestamptz not null default now(),
    activo boolean not null default true,
    constraint usuario_email_unico unique (email),
    constraint usuario_telegram_id_unico unique (telegram_id),
    constraint usuario_email_formato check (email = lower(email) and email like '%_@_%'),
    constraint usuario_nombre_no_vacio check (length(btrim(nombre)) > 0)
);

comment on table usuario is 'Estudiante registrado; punto de aislamiento de todos los datos.';
comment on column usuario.id is 'Identidad del usuario; es el sub del token de acceso.';
comment on column usuario.email is 'Correo en minusculas; es el identificador de inicio de sesion.';
comment on column usuario.password_hash is
'Hash argon2 de la contrasena; nunca se expone por SELECT.';
comment on column usuario.telegram_id is
'Identificador de Telegram, opcional hasta vincular el bot.';
comment on column usuario.nombre is 'Nombre para mostrar.';
comment on column usuario.zona_horaria is
'Zona horaria IANA con la que se resuelven fechas relativas.';
comment on column usuario.fecha_registro is 'Momento del registro.';
comment on column usuario.activo is 'Falso cuando la cuenta esta dada de baja.';

create table materia (
    id uuid primary key default gen_random_uuid(),
    usuario_id uuid not null references usuario (id),
    nombre text not null,
    docente text,
    clave text,
    periodo text not null,
    activa boolean not null default true,
    constraint materia_nombre_unico unique (usuario_id, nombre),
    constraint materia_id_usuario_unico unique (id, usuario_id),
    constraint materia_nombre_no_vacio check (length(btrim(nombre)) > 0)
);

comment on table materia is 'Materias del periodo de cada estudiante.';
comment on column materia.usuario_id is 'Dueno de la materia.';
comment on column materia.nombre is 'Nombre de la materia, unico por usuario.';
comment on column materia.docente is 'Docente que la imparte.';
comment on column materia.clave is 'Clave institucional.';
comment on column materia.periodo is 'Periodo escolar, por ejemplo 2026-3.';
comment on column materia.activa is 'Baja logica: falso cuando la materia ya no se cursa.';

create table categoria_actividad (
    id uuid primary key default gen_random_uuid(),
    usuario_id uuid references usuario (id),
    nombre text not null,
    ambito text not null,
    peso_default numeric(4, 2) not null default 1,
    constraint categoria_ambito_valido check (ambito in ('academica', 'personal', 'ambas')),
    constraint categoria_peso_positivo check (peso_default > 0),
    constraint categoria_nombre_no_vacio check (length(btrim(nombre)) > 0)
);

create unique index categoria_nombre_usuario_unico
on categoria_actividad (usuario_id, nombre) where usuario_id is not null;
create unique index categoria_nombre_sistema_unico
on categoria_actividad (nombre) where usuario_id is null;

comment on table categoria_actividad is
'Catalogo mixto: categorias del sistema y propias de cada usuario.';
comment on column categoria_actividad.usuario_id is 'Nulo para categorias del sistema.';
comment on column categoria_actividad.nombre is
'Nombre, unico por usuario y unico entre las del sistema.';
comment on column categoria_actividad.ambito is 'academica, personal o ambas.';
comment on column categoria_actividad.peso_default is
'Peso de carga que se asigna por defecto a las actividades.';

insert into categoria_actividad (nombre, ambito, peso_default) values
('Tarea', 'academica', 1),
('Examen', 'academica', 3),
('Proyecto', 'academica', 3),
('Exposicion', 'academica', 2),
('Lectura', 'academica', 1),
('Estudio', 'ambas', 1),
('Sueno', 'personal', 1),
('Ejercicio', 'personal', 1),
('Meditacion', 'personal', 1),
('Videojuegos', 'personal', 1);

create table actividad (
    id uuid primary key default gen_random_uuid(),
    usuario_id uuid not null references usuario (id),
    materia_id uuid,
    categoria_id uuid not null references categoria_actividad (id),
    titulo text not null,
    descripcion text,
    vence_en timestamptz,
    prioridad smallint not null default 3,
    modalidad text not null default 'presencial',
    estado text not null default 'pendiente',
    creada_en timestamptz not null default now(),
    completada_en timestamptz,
    constraint actividad_materia_del_usuario
    foreign key (materia_id, usuario_id) references materia (id, usuario_id),
    constraint actividad_titulo_no_vacio check (length(btrim(titulo)) > 0),
    constraint actividad_prioridad_valida check (prioridad between 1 and 5),
    constraint actividad_modalidad_valida check (modalidad in ('presencial', 'en_linea', 'mixta')),
    constraint actividad_estado_valido
    check (estado in ('pendiente', 'en_progreso', 'completada', 'cancelada')),
    constraint actividad_completada_coherente
    check ((estado = 'completada') = (completada_en is not null))
);

create index actividad_usuario_vence_idx on actividad (usuario_id, vence_en);

comment on table actividad is 'Tareas, examenes y compromisos del estudiante.';
comment on column actividad.usuario_id is 'Dueno de la actividad.';
comment on column actividad.materia_id is
'Materia asociada; nula para actividades sin materia. Debe ser del mismo usuario.';
comment on column actividad.categoria_id is 'Categoria del sistema o propia del usuario.';
comment on column actividad.titulo is 'Titulo corto.';
comment on column actividad.descripcion is 'Detalle libre.';
comment on column actividad.vence_en is 'Vencimiento con zona horaria.';
comment on column actividad.prioridad is 'De 1 (baja) a 5 (alta).';
comment on column actividad.modalidad is 'presencial, en_linea o mixta.';
comment on column actividad.estado is
'pendiente, en_progreso, completada o cancelada (baja logica).';
comment on column actividad.creada_en is 'Momento de creacion.';
comment on column actividad.completada_en is 'Lo fija el trigger al pasar a completada.';

create function actividad_fijar_completada_en() returns trigger
language plpgsql
as $$
begin
    if new.estado = 'completada' then
        if tg_op = 'INSERT' or old.estado is distinct from 'completada' then
            new.completada_en := now();
        end if;
    else
        new.completada_en := null;
    end if;
    return new;
end
$$;

create trigger actividad_completada_en
before insert or update on actividad
for each row execute function actividad_fijar_completada_en();

create function actividad_validar_categoria() returns trigger
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

create trigger actividad_categoria_del_usuario
before insert or update of categoria_id, usuario_id on actividad
for each row execute function actividad_validar_categoria();

create table calendario_academico (
    id uuid primary key default gen_random_uuid(),
    periodo text not null,
    tipo text not null,
    fecha date not null,
    fecha_fin date,
    descripcion text not null,
    constraint calendario_tipo_valido
    check (tipo in ('inicio_periodo', 'fin_periodo', 'inhabil', 'examen', 'institucional')),
    constraint calendario_rango_valido check (fecha_fin is null or fecha_fin >= fecha),
    constraint calendario_fecha_unica unique (periodo, tipo, fecha)
);

comment on table calendario_academico is
'Fechas institucionales compartidas por todos los usuarios.';
comment on column calendario_academico.periodo is 'Periodo escolar al que pertenece.';
comment on column calendario_academico.tipo is
'inicio_periodo, fin_periodo, inhabil, examen o institucional.';
comment on column calendario_academico.fecha is 'Fecha, o inicio del rango.';
comment on column calendario_academico.fecha_fin is 'Fin del rango; nulo si es un solo dia.';
comment on column calendario_academico.descripcion is 'Descripcion visible.';

create function kairo_registrar_usuario(
    p_email text, p_password_hash text, p_nombre text, p_zona_horaria text
) returns uuid
language sql security definer set search_path = public, pg_temp
as $$
    insert into usuario (email, password_hash, nombre, zona_horaria)
    values (p_email, p_password_hash, p_nombre, p_zona_horaria)
    returning id
$$;

create function kairo_buscar_credenciales(p_email text)
returns table (id uuid, password_hash text, activo boolean)
language sql stable security definer set search_path = public, pg_temp
as $$
    select u.id, u.password_hash, u.activo from usuario as u where u.email = p_email
$$;

comment on function kairo_registrar_usuario(text, text, text, text) is
'Alta de usuario sin sesion; evita una politica de INSERT abierta.';
comment on function kairo_buscar_credenciales(text) is
'Busca el hash por correo antes de que exista sesion; evita una politica de SELECT abierta.';

revoke all on function kairo_registrar_usuario(text, text, text, text) from public;
revoke all on function kairo_buscar_credenciales(text) from public;
grant execute on function kairo_registrar_usuario(text, text, text, text) to kairo_app;
grant execute on function kairo_buscar_credenciales(text) to kairo_app;

alter table usuario enable row level security;
alter table materia enable row level security;
alter table categoria_actividad enable row level security;
alter table actividad enable row level security;
alter table calendario_academico enable row level security;

create policy usuario_select_propio on usuario for select to kairo_app
using (id = app_usuario_id());
create policy usuario_update_propio on usuario for update to kairo_app
using (id = app_usuario_id()) with check (id = app_usuario_id());

create policy materia_propia on materia for all to kairo_app
using (usuario_id = app_usuario_id()) with check (usuario_id = app_usuario_id());

create policy categoria_select on categoria_actividad for select to kairo_app
using (usuario_id is null or usuario_id = app_usuario_id());
create policy categoria_insert_propia on categoria_actividad for insert to kairo_app
with check (usuario_id = app_usuario_id());
create policy categoria_update_propia on categoria_actividad for update to kairo_app
using (usuario_id = app_usuario_id()) with check (usuario_id = app_usuario_id());

create policy actividad_propia on actividad for all to kairo_app
using (usuario_id = app_usuario_id()) with check (usuario_id = app_usuario_id());

create policy calendario_select on calendario_academico for select to kairo_app
using (true);

grant select (id, email, telegram_id, nombre, zona_horaria, fecha_registro, activo),
update (nombre, zona_horaria, telegram_id) on usuario to kairo_app;
grant select, insert, update on materia, categoria_actividad, actividad to kairo_app;
grant select on calendario_academico to kairo_app;
