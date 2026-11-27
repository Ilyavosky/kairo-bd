set role kairo_owner;

-- La vista ya usa "tipo" para distinguir actividad de evento; el tipo del evento va en una
-- columna nueva al final, porque create or replace view solo permite agregar columnas al final.
create or replace view v_agenda_proxima with (security_barrier = true) as
select
    'actividad'::text as tipo,
    a.usuario_id,
    a.id,
    a.titulo,
    a.materia_id,
    m.nombre as materia,
    c.nombre as categoria,
    a.vence_en as cuando,
    a.prioridad::integer as prioridad,
    a.estado,
    null::text as subtipo
from actividad as a
inner join categoria_actividad as c on a.categoria_id = c.id
left join materia as m on a.materia_id = m.id
where
    a.usuario_id = app_usuario_id()
    and a.estado in ('pendiente', 'en_progreso')
    and a.vence_en >= now()
union all
select
    'evento'::text as tipo,
    e.usuario_id,
    e.id,
    e.titulo,
    e.materia_id,
    m.nombre as materia,
    null::text as categoria,
    e.inicio as cuando,
    null::integer as prioridad,
    null::text as estado,
    e.tipo as subtipo
from evento_calendario as e
left join materia as m on e.materia_id = m.id
where
    e.usuario_id = app_usuario_id()
    and e.fin >= now();

comment on column v_agenda_proxima.subtipo is
'Tipo del evento (clase, examen, entrega, reunion o personal); nulo para actividades.';

grant select (tipo) on evento_calendario to kairo_worker;

reset role;
