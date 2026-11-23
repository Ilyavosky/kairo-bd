create policy recordatorio_worker_select on recordatorio for select to kairo_worker
using (true);
create policy recordatorio_worker_update on recordatorio for update to kairo_worker
using (true) with check (true);
create policy usuario_worker_select on usuario for select to kairo_worker using (true);
create policy actividad_worker_select on actividad for select to kairo_worker using (true);
create policy evento_worker_select on evento_calendario for select to kairo_worker using (true);
create policy meta_worker_select on meta for select to kairo_worker using (true);
create policy categoria_worker_select on categoria_actividad for select to kairo_worker
using (true);

grant select on recordatorio to kairo_worker;
grant update (estado_envio, intentos, enviado_en, ultimo_error) on recordatorio to kairo_worker;
grant select (id, telegram_id, zona_horaria, activo) on usuario to kairo_worker;
grant select (id, usuario_id, titulo, vence_en) on actividad to kairo_worker;
grant select (id, usuario_id, titulo, inicio) on evento_calendario to kairo_worker;
grant select (id, usuario_id, categoria_id, tipo, periodo, objetivo) on meta to kairo_worker;
grant select (id, nombre) on categoria_actividad to kairo_worker;

create function kairo_evaluar_metas(p_ahora timestamptz default now()) returns integer
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
    v_n integer;
begin
    insert into evaluacion_meta (
        meta_id, usuario_id, periodo_desde, periodo_hasta, objetivo, valor_logrado, cumplida
    )
    select
        p.meta_id,
        p.usuario_id,
        p.desde_local at time zone p.zona_horaria,
        p.hasta_local at time zone p.zona_horaria,
        p.objetivo,
        a.valor,
        a.valor >= p.objetivo
    from (
        select
            m.id as meta_id,
            m.usuario_id,
            m.categoria_id,
            m.tipo,
            m.objetivo,
            m.vigente_desde,
            m.vigente_hasta,
            u.zona_horaria,
            l.hasta_local,
            l.hasta_local - (l.unidad_texto)::interval as desde_local
        from meta as m
        inner join usuario as u on m.usuario_id = u.id
        cross join lateral (
            select
                '1 ' || case m.periodo when 'dia' then 'day' when 'semana' then 'week' else 'month' end
                    as unidad_texto,
                date_trunc(
                    case m.periodo when 'dia' then 'day' when 'semana' then 'week' else 'month' end,
                    p_ahora at time zone u.zona_horaria
                ) as hasta_local
        ) as l
        where m.activa
    ) as p
    cross join lateral (
        select
            case p.tipo
                when 'tiempo_acumulado'
                    then coalesce(sum(extract(epoch from r.fin - r.inicio)) / 60, 0)
                else count(*)
            end as valor
        from registro_tiempo as r
        where r.usuario_id = p.usuario_id
            and r.categoria_id = p.categoria_id
            and r.inicio >= p.desde_local at time zone p.zona_horaria
            and r.inicio < p.hasta_local at time zone p.zona_horaria
    ) as a
    where p.desde_local::date >= p.vigente_desde
        and (p.vigente_hasta is null or p.desde_local::date <= p.vigente_hasta)
    on conflict (meta_id, periodo_desde) do nothing;

    get diagnostics v_n = row_count;
    return v_n;
end
$$;

comment on function kairo_evaluar_metas(timestamptz) is
'Evalua el ultimo periodo cerrado de cada meta activa; idempotente. Lo llama pg_cron cada hora.';

revoke all on function kairo_evaluar_metas(timestamptz) from public;
grant execute on function kairo_evaluar_metas(timestamptz) to kairo_worker;
