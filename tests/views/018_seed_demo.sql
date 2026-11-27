begin;

\set hash_demo 'hash-solo-para-pruebas'
\ir ../../seeds/demo/001_demo.sql
create temporary table _conteo as
select
    (select count(*) from actividad) as actividades,
    (select count(*) from registro_tiempo) as registros,
    (select count(*) from evaluacion_meta) as evaluaciones;
\ir ../../seeds/demo/001_demo.sql

do $$
declare
    v_ana uuid;
    v_luis uuid;
    v_pesada date := date_trunc('week', now() at time zone 'America/Mexico_City')::date - 14;
    v_normal date := date_trunc('week', now() at time zone 'America/Mexico_City')::date - 28;
    v_n integer;
    v_r record;
    v_s record;
begin
    select id into v_ana from usuario where email = 'ana.demo@kairo.mx';
    select id into v_luis from usuario where email = 'luis.demo@kairo.mx';
    assert v_ana is not null and v_luis is not null, 'existen los dos usuarios de la demo';

    assert (select count(*) from _conteo as c where
        c.actividades = (select count(*) from actividad)
        and c.registros = (select count(*) from registro_tiempo)
        and c.evaluaciones = (select count(*) from evaluacion_meta)) = 1,
    'ejecutar el seed dos veces no duplica datos';

    assert not exists (
        select 1 from recordatorio
        where usuario_id in (v_ana, v_luis) and estado_envio = 'pendiente' and momento <= now()
    ), 'ningun recordatorio pendiente queda en el pasado';
    assert not exists (
        select 1 from registro_tiempo where usuario_id in (v_ana, v_luis) and fin > now()
    ), 'ningun registro de tiempo termina en el futuro';

    set local role kairo_app;
    perform set_config('app.usuario_id', v_ana::text, true);

    assert (select count(distinct usuario_id) from actividad) = 1,
    'con la sesion de Ana solo se ven sus actividades';
    select count(*) into v_n from v_agenda_proxima where cuando <= now() + interval '14 days';
    assert v_n >= 8, 'la agenda de 14 dias tiene actividades y eventos: ' || v_n;
    assert exists (select 1 from v_agenda_proxima where subtipo = 'entrega'),
    'la agenda muestra la entrega ligada a su actividad';
    select count(*) into v_n from v_progreso_metas;
    assert v_n = 3, 'Ana tiene tres metas activas';

    select * into v_r from v_carga_vs_descanso where semana_desde = v_pesada;
    select * into v_s from v_carga_vs_descanso where semana_desde = v_normal;
    assert v_r.minutos_sueno < v_s.minutos_sueno and v_r.minutos_academicos > v_s.minutos_academicos
    and v_r.estado_animo < v_s.estado_animo,
    'en la semana pesada sube el estudio y bajan el sueno y el animo';

    select * into v_r from v_desempeno_pipeline where entidad_tipo = 'actividad';
    assert v_r.total = 4 and v_r.porcentaje_sin_correccion = 75.0,
    'Ana: 4 extracciones, 3 aceptadas sin correccion';

    select count(*) into v_n from evaluacion_meta where cumplida;
    assert v_n > 0, 'hay metas cumplidas en el historial';
    select count(*) into v_n from evaluacion_meta where not cumplida;
    assert v_n > 0, 'hay metas no cumplidas en el historial';

    reset role;
    set local role kairo_lectura;

    select * into v_r from vl_cruce_carga_descanso where semana_desde = v_pesada;
    assert v_r.usuarios = 2 and v_r.entregas_que_vencen = 8,
    'la vista agregada ve la semana pesada de ambos usuarios';
    select * into v_r from vl_desempeno_pipeline where entidad_tipo = 'actividad';
    assert v_r.total = 9 and v_r.usuarios = 2 and v_r.descartadas = 1,
    'el pipeline agregado cuenta las 8 capturas confirmadas y la descartada de Luis';
    select * into v_r from vl_desempeno_pipeline where entidad_tipo = 'meta';
    assert v_r.pendientes = 1, 'la captura de meta de Luis sigue pendiente';
end
$$;

rollback;
