-- Las 5 consultas medidas por t38_planes.sql. Se ejecutan con el rol y la sesion de la API.

set local role kairo_app;
select set_config('app.usuario_id', :'usuario', true) \g /dev/null

\echo '=== 1. Agenda proxima (GET /reportes/agenda, 14 dias, 50 filas)'
explain (analyze, buffers)
select tipo, id, titulo, materia_id, materia, categoria, cuando, prioridad, estado
from v_agenda_proxima
where cuando <= now() + make_interval(days => 14)
order by cuando, tipo, id limit 50;

\echo '=== 2. Carga semanal por materia (GET /reportes/carga-semanal, 4 semanas atras y 4 adelante)'
explain (analyze, buffers)
select semana_desde, materia_id, materia, actividades_con_vencimiento,
    actividades_pendientes, minutos_registrados
from v_carga_semanal_materia
where semana_desde between
    date_trunc('week', now() at time zone
        (select zona_horaria from usuario where id = app_usuario_id()))::date - 4 * 7
    and date_trunc('week', now() at time zone
        (select zona_horaria from usuario where id = app_usuario_id()))::date + 4 * 7
order by semana_desde, materia nulls last, materia_id;

\echo '=== 3. Registros por categoria (GET /registros-tiempo?categoria_id=...&desde=-30d, 50 filas)'
explain (analyze, buffers)
select id, categoria_id, actividad_id, inicio, fin, origen, nota
from registro_tiempo
where (:'desde'::timestamptz is null or inicio >= :'desde'::timestamptz)
    and (null::timestamptz is null or inicio <= null::timestamptz)
    and (:'estudio'::uuid is null or categoria_id = :'estudio'::uuid)
    and (null::uuid is null or actividad_id = null::uuid)
order by inicio desc, id
limit 50 offset 0;

\echo '=== 4. Progreso de metas (GET /reportes/metas)'
explain (analyze, buffers)
select meta_id, categoria_id, categoria, tipo, periodo, objetivo,
    periodo_desde, periodo_hasta, progreso, cumplida
from v_progreso_metas
order by categoria, periodo, meta_id;

reset role;
set local role kairo_worker;

\echo '=== 5. Recordatorios vencidos (despacho, lote de 20, como kairo_worker)'
explain (analyze, buffers)
select
    r.id,
    r.intentos,
    u.telegram_id,
    u.zona_horaria,
    u.activo,
    case
        when r.actividad_id is not null then 'actividad'
        when r.evento_id is not null then 'evento'
        else 'meta'
    end as tipo,
    coalesce(a.titulo, e.titulo, c.nombre) as titulo,
    coalesce(a.vence_en, e.inicio) as cuando
from recordatorio as r
inner join usuario as u on r.usuario_id = u.id
left join actividad as a on r.actividad_id = a.id
left join evento_calendario as e on r.evento_id = e.id
left join meta as m on r.meta_id = m.id
left join categoria_actividad as c on m.categoria_id = c.id
where r.estado_envio = 'pendiente' and r.momento <= now() and r.intentos < 3
order by r.momento, r.id
limit 20
for update of r skip locked;

reset role;
