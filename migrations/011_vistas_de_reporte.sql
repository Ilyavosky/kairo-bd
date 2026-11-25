revoke create on schema public from public;

create view v_agenda_proxima with (security_barrier = true) as
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
    a.estado
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
    null::text as estado
from evento_calendario as e
left join materia as m on e.materia_id = m.id
where
    e.usuario_id = app_usuario_id()
    and e.fin >= now();

create view v_carga_semanal_materia with (security_barrier = true) as
with base as (
    select
        a.usuario_id,
        a.materia_id,
        date_trunc('week', a.vence_en at time zone u.zona_horaria)::date as semana_desde,
        1 as con_vencimiento,
        case when a.estado in ('pendiente', 'en_progreso') then 1 else 0 end as pendientes,
        0::numeric as segundos
    from actividad as a
    inner join usuario as u on a.usuario_id = u.id
    where a.usuario_id = app_usuario_id() and a.vence_en is not null
    union all
    select
        r.usuario_id,
        a.materia_id,
        date_trunc('week', r.inicio at time zone u.zona_horaria)::date as semana_desde,
        0 as con_vencimiento,
        0 as pendientes,
        extract(epoch from r.fin - r.inicio) as segundos
    from registro_tiempo as r
    inner join actividad as a on r.actividad_id = a.id
    inner join usuario as u on r.usuario_id = u.id
    where r.usuario_id = app_usuario_id()
)

select
    b.usuario_id,
    b.semana_desde,
    b.materia_id,
    m.nombre as materia,
    sum(b.con_vencimiento)::integer as actividades_con_vencimiento,
    sum(b.pendientes)::integer as actividades_pendientes,
    round(sum(b.segundos) / 60, 1) as minutos_registrados
from base as b
left join materia as m on b.materia_id = m.id
group by b.usuario_id, b.semana_desde, b.materia_id, m.nombre;

create view v_progreso_metas with (security_barrier = true) as
select
    m.usuario_id,
    m.id as meta_id,
    m.categoria_id,
    c.nombre as categoria,
    m.tipo,
    m.periodo,
    m.objetivo,
    v.desde as periodo_desde,
    v.hasta as periodo_hasta,
    case m.tipo
        when 'tiempo_acumulado' then coalesce(a.minutos, 0)
        else coalesce(a.sesiones, 0)
    end as progreso,
    case m.tipo
        when 'tiempo_acumulado' then coalesce(a.minutos, 0) >= m.objetivo
        else coalesce(a.sesiones, 0) >= m.objetivo
    end as cumplida
from meta as m
inner join usuario as u on m.usuario_id = u.id
inner join categoria_actividad as c on m.categoria_id = c.id
cross join
    lateral (
        select
            l.inicio at time zone u.zona_horaria as desde,
            (
                l.inicio + case m.periodo
                    when 'dia' then interval '1 day'
                    when 'semana' then interval '1 week'
                    else interval '1 month'
                end
            ) at time zone u.zona_horaria as hasta
        from (
            select date_trunc(
                case m.periodo when 'dia' then 'day' when 'semana' then 'week' else 'month' end,
                now() at time zone u.zona_horaria
            ) as inicio
        ) as l
    ) as v
left join lateral (
    select
        round(sum(extract(epoch from r.fin - r.inicio)) / 60, 1) as minutos,
        count(*) as sesiones
    from registro_tiempo as r
    where
        r.usuario_id = m.usuario_id
        and r.categoria_id = m.categoria_id
        and r.inicio >= v.desde
        and r.inicio < v.hasta
) as a on true
where m.usuario_id = app_usuario_id() and m.activa;

create view v_desempeno_pipeline with (security_barrier = true) as
select
    t.entidad_tipo,
    count(e.id)::integer as total,
    (count(e.id) filter (where e.estado = 'pendiente'))::integer as pendientes,
    (count(e.id) filter (where e.estado = 'aceptada'))::integer as aceptadas,
    (count(e.id) filter (where e.estado = 'corregida'))::integer as corregidas,
    (count(e.id) filter (where e.estado = 'descartada'))::integer as descartadas,
    round(
        100.0 * count(e.id) filter (where e.estado = 'aceptada')
        / nullif(count(e.id) filter (where e.estado <> 'pendiente'), 0),
        1
    ) as porcentaje_sin_correccion,
    round(
        avg(c.n) filter (where e.estado in ('aceptada', 'corregida')), 2
    ) as promedio_campos_corregidos
from (values ('actividad'), ('registro_tiempo'), ('meta')) as t (entidad_tipo)
left join extraccion as e
    on t.entidad_tipo = e.entidad_tipo and e.usuario_id = app_usuario_id()
left join lateral (
    select count(*) as n from correccion_campo as cc
    where cc.extraccion_id = e.id
) as c on true
group by t.entidad_tipo;

create view v_carga_vs_descanso with (security_barrier = true) as
with semanas as (
    select
        r.usuario_id,
        date_trunc('week', r.inicio at time zone u.zona_horaria)::date as semana_desde,
        sum(extract(epoch from r.fin - r.inicio)) filter (
            where c.ambito in ('academica', 'ambas')
        ) as seg_academico,
        sum(extract(epoch from r.fin - r.inicio)) filter (
            where c.nombre = 'Sueno' and c.usuario_id is null
        ) as seg_sueno,
        sum(extract(epoch from r.fin - r.inicio)) filter (
            where c.nombre = 'Ejercicio' and c.usuario_id is null
        ) as seg_ejercicio
    from registro_tiempo as r
    inner join usuario as u on r.usuario_id = u.id
    inner join categoria_actividad as c on r.categoria_id = c.id
    where r.usuario_id = app_usuario_id()
    group by r.usuario_id, date_trunc('week', r.inicio at time zone u.zona_horaria)::date
)

select
    s.usuario_id,
    s.semana_desde,
    q.estado_animo,
    q.satisfaccion,
    round(coalesce(s.seg_academico, 0) / 60, 1) as minutos_academicos,
    round(coalesce(s.seg_sueno, 0) / 60, 1) as minutos_sueno,
    round(coalesce(s.seg_ejercicio, 0) / 60, 1) as minutos_ejercicio
from semanas as s
left join autoevaluacion_semanal as q
    on s.usuario_id = q.usuario_id and s.semana_desde = q.semana_desde;

comment on view v_agenda_proxima is
'Actividades abiertas con vencimiento futuro y eventos que no han terminado.';
comment on view v_carga_semanal_materia is
'Por semana y materia: actividades que vencen, pendientes y minutos registrados en ellas.';
comment on view v_progreso_metas is
'Progreso de las metas activas en su periodo actual, calculado en la zona del usuario.';
comment on view v_desempeno_pipeline is
'Extracciones por tipo y estado, porcentaje aceptado sin correccion y campos corregidos.';
comment on view v_carga_vs_descanso is
'Por semana: minutos academicos contra sueno y ejercicio, con la autoevaluacion si existe.';

grant select on
v_agenda_proxima, v_carga_semanal_materia, v_progreso_metas,
v_desempeno_pipeline, v_carga_vs_descanso
to kairo_app, kairo_lectura;
