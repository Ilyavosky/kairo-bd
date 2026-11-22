create function registro_tiempo_actualizar_resumen() returns trigger
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
    v_zona text;
    v_periodo text;
    v_unidad text;
    v_desde date;
begin
    select zona_horaria into v_zona from usuario where id = new.usuario_id;

    foreach v_periodo in array array['dia', 'semana', 'mes']
    loop
        v_unidad := case v_periodo when 'dia' then 'day' when 'semana' then 'week' else 'month' end;

        if tg_op = 'UPDATE' then
            v_desde := date_trunc(v_unidad, old.inicio at time zone v_zona)::date;
            update resumen_periodo
            set
                segundos = segundos - round(extract(epoch from old.fin - old.inicio))::bigint,
                registros = registros - 1,
                actualizado_en = now()
            where usuario_id = old.usuario_id
                and categoria_id = old.categoria_id
                and periodo = v_periodo
                and periodo_desde = v_desde;
        end if;

        v_desde := date_trunc(v_unidad, new.inicio at time zone v_zona)::date;
        insert into resumen_periodo (
            usuario_id, categoria_id, periodo, periodo_desde, segundos, registros
        )
        values (
            new.usuario_id,
            new.categoria_id,
            v_periodo,
            v_desde,
            round(extract(epoch from new.fin - new.inicio))::bigint,
            1
        )
        on conflict (usuario_id, categoria_id, periodo, periodo_desde)
        do update set
            segundos = resumen_periodo.segundos + excluded.segundos,
            registros = resumen_periodo.registros + 1,
            actualizado_en = now();
    end loop;

    return new;
end
$$;

comment on function registro_tiempo_actualizar_resumen() is
'Mantiene resumen_periodo al insertar o editar un registro de tiempo, en la zona del usuario.';

create trigger registro_tiempo_resumen
after insert or update of categoria_id, inicio, fin on registro_tiempo
for each row execute function registro_tiempo_actualizar_resumen();

create function registro_tiempo_registrar_cambios() returns trigger
language plpgsql security definer set search_path = public, pg_temp
as $$
begin
    insert into bitacora_cambios (
        usuario_id, registro_tiempo_id, campo, valor_anterior, valor_nuevo
    )
    select new.usuario_id, new.id, c.campo, c.anterior, c.nuevo
    from (
        values
        ('categoria_id', old.categoria_id::text, new.categoria_id::text),
        ('actividad_id', old.actividad_id::text, new.actividad_id::text),
        ('inicio', old.inicio::text, new.inicio::text),
        ('fin', old.fin::text, new.fin::text),
        ('nota', old.nota, new.nota)
    ) as c (campo, anterior, nuevo)
    where c.anterior is distinct from c.nuevo;
    return new;
end
$$;

comment on function registro_tiempo_registrar_cambios() is
'Anota en la bitacora cada campo editado de un registro de tiempo.';

create trigger registro_tiempo_bitacora
after update of categoria_id, actividad_id, inicio, fin, nota on registro_tiempo
for each row execute function registro_tiempo_registrar_cambios();

insert into resumen_periodo (usuario_id, categoria_id, periodo, periodo_desde, segundos, registros)
select
    t.usuario_id,
    t.categoria_id,
    t.periodo,
    t.periodo_desde,
    sum(t.segundos)::bigint as segundos,
    count(*)::integer as registros
from (
    select
        r.usuario_id,
        r.categoria_id,
        p.periodo,
        date_trunc(p.unidad, r.inicio at time zone u.zona_horaria)::date as periodo_desde,
        round(extract(epoch from r.fin - r.inicio)) as segundos
    from registro_tiempo as r
    inner join usuario as u on r.usuario_id = u.id
    cross join (values ('dia', 'day'), ('semana', 'week'), ('mes', 'month')) as p (periodo, unidad)
) as t
group by t.usuario_id, t.categoria_id, t.periodo, t.periodo_desde
on conflict (usuario_id, categoria_id, periodo, periodo_desde) do nothing;
