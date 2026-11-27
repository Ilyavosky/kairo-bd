-- T38. Genera el volumen del issue sobre una base local con todas las migraciones aplicadas.
-- No es una prueba de la CI: se ejecuta a mano con psql y despues t38_planes.sql.
-- Nunca contra Supabase: inserta 100 usuarios ficticios y decenas de miles de filas.
--
-- Volumen: 100 usuarios, 10 000 actividades, 50 000 registros de tiempo, 3 000 eventos,
-- 20 000 recordatorios (60 pendientes vencidos), 300 metas, 600 materias.

\set ON_ERROR_STOP on
\timing on

insert into usuario (email, password_hash, nombre, zona_horaria)
select 'volumen' || g || '@prueba.mx', 'x', 'Usuario ' || g, 'America/Mexico_City'
from generate_series(1, 100) as g;

create temporary table vol_usuario as
select id, row_number() over (order by email) as n
from usuario where email like 'volumen%@prueba.mx';

insert into materia (usuario_id, nombre, periodo)
select u.id, 'Materia ' || g, '2026-3'
from vol_usuario as u cross join generate_series(1, 6) as g;

-- 100 actividades por usuario, con vencimientos entre hace 90 dias y dentro de 60.
insert into actividad (usuario_id, materia_id, categoria_id, titulo, vence_en, prioridad, estado)
select
    u.id,
    (select m.id from materia as m where m.usuario_id = u.id order by m.nombre offset (g % 6) limit 1),
    (select c.id from categoria_actividad as c
        where c.usuario_id is null and c.ambito = 'academica' order by c.nombre offset (g % 5) limit 1),
    'Actividad ' || g,
    now() - interval '90 days' + (g * interval '1 day' * 1.5),
    1 + (g % 5),
    case when g % 3 = 0 then 'completada' else 'pendiente' end
from vol_usuario as u cross join generate_series(1, 100) as g;

-- 500 registros de tiempo por usuario en los ultimos 180 dias, repartidos en 6 categorias.
insert into registro_tiempo (usuario_id, categoria_id, inicio, fin, origen)
select
    u.id,
    (select c.id from categoria_actividad as c
        where c.usuario_id is null
            and c.nombre in ('Estudio', 'Tarea', 'Sueno', 'Ejercicio', 'Lectura', 'Videojuegos')
        order by c.nombre offset (g % 6) limit 1),
    now() - (g * interval '8 hours 37 minutes'),
    now() - (g * interval '8 hours 37 minutes') + interval '45 minutes',
    case when g % 2 = 0 then 'temporizador' else 'manual' end
from vol_usuario as u cross join generate_series(1, 500) as g;

-- 30 eventos por usuario.
insert into evento_calendario (usuario_id, titulo, inicio, fin, tipo)
select
    u.id,
    'Evento ' || g,
    now() - interval '30 days' + (g * interval '2 days'),
    now() - interval '30 days' + (g * interval '2 days') + interval '1 hour',
    (array['clase', 'examen', 'entrega', 'reunion', 'personal'])[1 + g % 5]
from vol_usuario as u cross join generate_series(1, 30) as g;

-- 3 metas activas por usuario.
insert into meta (usuario_id, categoria_id, tipo, periodo, objetivo)
select
    u.id,
    c.id,
    case when c.nombre = 'Ejercicio' then 'numero_eventos' else 'tiempo_acumulado' end,
    case when c.nombre = 'Sueno' then 'dia' else 'semana' end,
    case when c.nombre = 'Ejercicio' then 3 when c.nombre = 'Sueno' then 420 else 600 end
from vol_usuario as u
cross join categoria_actividad as c
where c.usuario_id is null and c.nombre in ('Estudio', 'Sueno', 'Ejercicio');

-- 200 recordatorios por usuario: casi todos ya enviados, y 60 pendientes vencidos en total.
insert into recordatorio (usuario_id, actividad_id, momento, estado_envio, enviado_en)
select
    a.usuario_id,
    a.id,
    a.vence_en - interval '1 day',
    'enviado',
    a.vence_en - interval '1 day'
from actividad as a
where a.usuario_id in (select id from vol_usuario);
insert into recordatorio (usuario_id, actividad_id, momento)
select a.usuario_id, a.id, a.vence_en - interval '2 hours'
from actividad as a
where a.usuario_id in (select id from vol_usuario);
update recordatorio set momento = now() - interval '5 minutes'
where id in (
    select id from recordatorio
    where estado_envio = 'pendiente' and usuario_id in (select id from vol_usuario)
    order by id limit 60
);
update recordatorio set momento = now() + interval '7 days'
where estado_envio = 'pendiente' and momento <= now() - interval '5 minutes' - interval '1 second'
    and usuario_id in (select id from vol_usuario);

analyze;

select 'usuarios' as tabla, count(*) from vol_usuario
union all select 'actividad', count(*) from actividad
union all select 'registro_tiempo', count(*) from registro_tiempo
union all select 'evento_calendario', count(*) from evento_calendario
union all select 'recordatorio', count(*) from recordatorio
union all select 'recordatorio pendiente vencido', count(*) from recordatorio
where estado_envio = 'pendiente' and momento <= now()
union all select 'meta', count(*) from meta
union all select 'resumen_periodo', count(*) from resumen_periodo
union all select 'bitacora_cambios', count(*) from bitacora_cambios;
