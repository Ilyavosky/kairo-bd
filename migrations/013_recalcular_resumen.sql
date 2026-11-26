set role kairo_owner;

create function kairo_recalcular_resumen(p_usuario uuid)
returns table (
    categoria_id uuid,
    periodo text,
    periodo_desde date,
    segundos_calculados bigint,
    registros_calculados integer,
    segundos_resumen bigint,
    registros_resumen integer,
    coincide boolean
)
language sql stable security invoker set search_path = public, pg_temp
as $$
    with calculado as (
        select
            r.categoria_id,
            p.periodo,
            date_trunc(p.unidad, r.inicio at time zone u.zona_horaria)::date as periodo_desde,
            sum(round(extract(epoch from r.fin - r.inicio)))::bigint as segundos,
            count(*)::integer as registros
        from registro_tiempo as r
        inner join usuario as u on r.usuario_id = u.id
        cross join (values ('dia', 'day'), ('semana', 'week'), ('mes', 'month')) as p (periodo, unidad)
        where r.usuario_id = p_usuario
        group by r.categoria_id, p.periodo, 3
    ),

    guardado as (
        select s.categoria_id, s.periodo, s.periodo_desde, s.segundos, s.registros
        from resumen_periodo as s
        where s.usuario_id = p_usuario
    )

    select
        coalesce(c.categoria_id, g.categoria_id) as categoria_id,
        coalesce(c.periodo, g.periodo) as periodo,
        coalesce(c.periodo_desde, g.periodo_desde) as periodo_desde,
        coalesce(c.segundos, 0) as segundos_calculados,
        coalesce(c.registros, 0) as registros_calculados,
        coalesce(g.segundos, 0) as segundos_resumen,
        coalesce(g.registros, 0) as registros_resumen,
        coalesce(c.segundos, 0) = coalesce(g.segundos, 0)
        and coalesce(c.registros, 0) = coalesce(g.registros, 0) as coincide
    from calculado as c
    full join guardado as g
        on c.categoria_id = g.categoria_id
        and c.periodo = g.periodo
        and c.periodo_desde = g.periodo_desde
$$;

comment on function kairo_recalcular_resumen(uuid) is
'Recalcula desde registro_tiempo los totales por categoria y periodo de un usuario y los compara
con resumen_periodo. Usa la zona horaria actual del usuario; si cambio despues de registrar,
las cubetas anteriores pueden no coincidir (ver decision 003).';

grant execute on function kairo_recalcular_resumen(uuid) to kairo_app;

reset role;
