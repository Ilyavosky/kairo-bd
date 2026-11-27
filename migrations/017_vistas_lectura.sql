set role kairo_owner;

-- Vistas por usuario (kairo_app): ademas del filtro por app_usuario_id(), se evaluan con los
-- permisos y la RLS de quien consulta. Un error en el filtro ya no expone datos de otros usuarios.
alter view v_agenda_proxima set (security_invoker = true);
alter view v_carga_semanal_materia set (security_invoker = true);
alter view v_progreso_metas set (security_invoker = true);
alter view v_desempeno_pipeline set (security_invoker = true);
alter view v_carga_vs_descanso set (security_invoker = true);

-- kairo_lectura deja de ver las vistas por usuario: solo consulta las vistas agregadas vl_*.
revoke select on
v_agenda_proxima, v_carga_semanal_materia, v_progreso_metas,
v_desempeno_pipeline, v_carga_vs_descanso
from kairo_lectura;

-- Vistas agregadas (kairo_lectura). Son de kairo_owner y no usan security_invoker: leen a todos
-- los usuarios, pero solo devuelven totales y promedios, nunca identificadores ni textos.
create view vl_desempeno_pipeline with (security_barrier = true) as
select
    t.entidad_tipo,
    count(e.id)::integer as total,
    count(distinct e.usuario_id)::integer as usuarios,
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
    ) as promedio_campos_corregidos,
    round(avg(e.confianza), 3) as confianza_promedio
from (values ('actividad'), ('registro_tiempo'), ('meta')) as t (entidad_tipo)
left join extraccion as e on t.entidad_tipo = e.entidad_tipo
left join lateral (
    select count(*) as n from correccion_campo as cc
    where cc.extraccion_id = e.id
) as c on true
group by t.entidad_tipo;

create view vl_cruce_carga_descanso with (security_barrier = true) as
with por_usuario as (
    select
        r.usuario_id,
        date_trunc('week', r.inicio at time zone u.zona_horaria)::date as semana_desde,
        coalesce(sum(extract(epoch from r.fin - r.inicio)) filter (
            where c.ambito in ('academica', 'ambas')
        ), 0) as seg_academico,
        coalesce(sum(extract(epoch from r.fin - r.inicio)) filter (
            where c.nombre = 'Sueno' and c.usuario_id is null
        ), 0) as seg_sueno,
        coalesce(sum(extract(epoch from r.fin - r.inicio)) filter (
            where c.nombre = 'Ejercicio' and c.usuario_id is null
        ), 0) as seg_ejercicio,
        0 as entregas
    from registro_tiempo as r
    inner join usuario as u on r.usuario_id = u.id
    inner join categoria_actividad as c on r.categoria_id = c.id
    group by r.usuario_id, date_trunc('week', r.inicio at time zone u.zona_horaria)::date
    union all
    select
        a.usuario_id,
        date_trunc('week', a.vence_en at time zone u.zona_horaria)::date as semana_desde,
        0 as seg_academico,
        0 as seg_sueno,
        0 as seg_ejercicio,
        count(*) as entregas
    from actividad as a
    inner join usuario as u on a.usuario_id = u.id
    where a.vence_en is not null and a.estado <> 'cancelada'
    group by a.usuario_id, date_trunc('week', a.vence_en at time zone u.zona_horaria)::date
),

semana_usuario as (
    select
        p.usuario_id,
        p.semana_desde,
        sum(p.seg_academico) as seg_academico,
        sum(p.seg_sueno) as seg_sueno,
        sum(p.seg_ejercicio) as seg_ejercicio,
        sum(p.entregas) as entregas
    from por_usuario as p
    group by p.usuario_id, p.semana_desde
)

select
    s.semana_desde,
    count(*)::integer as usuarios,
    sum(s.entregas)::integer as entregas_que_vencen,
    round(avg(s.entregas), 2) as entregas_por_usuario,
    round(avg(s.seg_academico) / 60, 1) as minutos_academicos_por_usuario,
    round(avg(s.seg_sueno) / 60, 1) as minutos_sueno_por_usuario,
    round(avg(s.seg_ejercicio) / 60, 1) as minutos_ejercicio_por_usuario,
    round(avg(q.estado_animo), 2) as estado_animo_promedio,
    round(avg(q.satisfaccion), 2) as satisfaccion_promedio
from semana_usuario as s
left join autoevaluacion_semanal as q
    on s.usuario_id = q.usuario_id and s.semana_desde = q.semana_desde
group by s.semana_desde;

create view vl_uso_por_categoria with (security_barrier = true) as
select
    date_trunc('week', r.inicio at time zone u.zona_horaria)::date as semana_desde,
    case when c.usuario_id is null then c.nombre else 'Propias' end as categoria,
    count(distinct r.usuario_id)::integer as usuarios,
    count(*)::integer as registros,
    round(sum(extract(epoch from r.fin - r.inicio)) / 60, 1) as minutos
from registro_tiempo as r
inner join usuario as u on r.usuario_id = u.id
inner join categoria_actividad as c on r.categoria_id = c.id
group by
    date_trunc('week', r.inicio at time zone u.zona_horaria)::date,
    case when c.usuario_id is null then c.nombre else 'Propias' end;

comment on view vl_desempeno_pipeline is
'Agregado de todos los usuarios: extracciones por tipo y estado, porcentaje aceptado sin
correccion, campos corregidos y confianza promedio. Solo para kairo_lectura.';
comment on view vl_cruce_carga_descanso is
'Agregado por semana: entregas que vencen contra minutos academicos, de sueno y de ejercicio
por usuario, con el animo y la satisfaccion promedio. Solo para kairo_lectura.';
comment on view vl_uso_por_categoria is
'Agregado por semana y categoria del sistema (las propias se agrupan como Propias): usuarios,
registros y minutos. Solo para kairo_lectura.';

grant select on vl_desempeno_pipeline, vl_cruce_carga_descanso, vl_uso_por_categoria
to kairo_lectura;

reset role;
