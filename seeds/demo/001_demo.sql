-- Datos de demostracion: dos estudiantes ficticios con cuatro semanas de historia y lo que viene.
-- La historia cubre las cuatro semanas anteriores a la actual (zona America/Mexico_City) y lo que
-- va de esta; lo pendiente se fecha a partir de hoy. Asi, cargada cualquier dia, la demo muestra
-- historia, agenda proxima y recordatorios en el futuro. La semana de hace dos semanas es la
-- "semana pesada": mas entregas, menos sueno y menos ejercicio.
--
-- Uso (la contrasena y su hash nunca van en el repositorio):
--   psql "$DATABASE_URL" -v hash_demo='<hash argon2 de pwdlib>' -f seeds/demo/001_demo.sql
-- Si los usuarios de la demo ya existen, no hace nada.

\set ON_ERROR_STOP on

\if :{?hash_demo}
\else
\echo 'Falta -v hash_demo=<hash>. Ver docs/demo.md.'
\quit
\endif

select set_config('kairo.hash_demo', :'hash_demo', false) \g /dev/null

do $$
declare
    v_zona constant text := 'America/Mexico_City';
    v_hash text := current_setting('kairo.hash_demo');
    v_hoy date := (now() at time zone 'America/Mexico_City')::date;
    v_lunes date := date_trunc('week', now() at time zone 'America/Mexico_City')::date;
    v_inicio date := v_lunes - 28;
    v_pesada date := v_lunes - 14;
    v_ana uuid;
    v_luis uuid;
    v_u uuid;
    v_es_ana boolean;
    v_dia date;
    v_semana date;
    v_pesada_semana boolean;
    v_dow integer;
    v_dormir timestamptz;
    v_despertar timestamptz;
    v_cat jsonb;
    v_mat uuid[];
    v_act uuid;
    v_act_proyecto uuid;
    v_msg uuid;
    v_ext uuid;
    v_reg uuid;
    v_etq_urgente uuid;
    v_etq_equipo uuid;
    v_meta uuid;
begin
    if exists (select 1 from usuario where email in ('ana.demo@kairo.mx', 'luis.demo@kairo.mx')) then
        raise notice 'Los usuarios de la demo ya existen; no se cambia nada.';
        return;
    end if;

    select jsonb_object_agg(nombre, id) into v_cat
    from categoria_actividad where usuario_id is null;

    insert into usuario (email, password_hash, nombre, zona_horaria)
    values ('ana.demo@kairo.mx', v_hash, 'Ana (demo)', v_zona) returning id into v_ana;
    insert into usuario (email, password_hash, nombre, zona_horaria)
    values ('luis.demo@kairo.mx', v_hash, 'Luis (demo)', v_zona) returning id into v_luis;

    foreach v_u in array array[v_ana, v_luis] loop
        v_es_ana := v_u = v_ana;

        -- Materias
        insert into materia (usuario_id, nombre, docente, clave, periodo) values
        (v_u, 'Bases de Datos en la Nube', 'Docente A', 'BDN-701', '2026-3'),
        (v_u, 'Ciberseguridad', 'Docente B', 'CIB-702', '2026-3'),
        (v_u, 'Fundamentos de IA', 'Docente C', 'FIA-703', '2026-3'),
        (v_u, 'Gestion de Proyectos', 'Docente D', 'GPT-704', '2026-3');
        select array_agg(id order by nombre) into v_mat from materia where usuario_id = v_u;
        -- v_mat: 1 Bases de Datos, 2 Ciberseguridad, 3 Fundamentos de IA, 4 Gestion de Proyectos

        -- Etiquetas
        insert into etiqueta (usuario_id, nombre) values (v_u, 'urgente') returning id into v_etq_urgente;
        insert into etiqueta (usuario_id, nombre) values (v_u, 'en equipo') returning id into v_etq_equipo;

        -- Actividades pasadas: se crean pendientes y se completan, para que quede la bitacora.
        -- La semana pesada concentra cuatro entregas.
        insert into actividad (usuario_id, materia_id, categoria_id, titulo, vence_en, prioridad, modalidad)
        values
        (v_u, v_mat[1], (v_cat ->> 'Tarea')::uuid, 'Modelo entidad-relacion',
            (v_inicio + 3 + time '23:59') at time zone v_zona, 3, 'en_linea'),
        (v_u, v_mat[2], (v_cat ->> 'Lectura')::uuid, 'Lectura: OWASP Top 10',
            (v_inicio + 8 + time '09:00') at time zone v_zona, 2, 'en_linea'),
        (v_u, v_mat[3], (v_cat ->> 'Tarea')::uuid, 'Ejercicios de busqueda A*',
            (v_inicio + 11 + time '23:59') at time zone v_zona, 3, 'en_linea'),
        (v_u, v_mat[1], (v_cat ->> 'Proyecto')::uuid, 'Avance 2 del proyecto',
            (v_pesada + 1 + time '23:59') at time zone v_zona, 5, 'mixta'),
        (v_u, v_mat[2], (v_cat ->> 'Examen')::uuid, 'Examen parcial',
            (v_pesada + 2 + time '10:00') at time zone v_zona, 5, 'presencial'),
        (v_u, v_mat[3], (v_cat ->> 'Tarea')::uuid, 'Algoritmo genetico',
            (v_pesada + 3 + time '23:59') at time zone v_zona, 4, 'en_linea'),
        (v_u, v_mat[4], (v_cat ->> 'Exposicion')::uuid, 'Exposicion de riesgos',
            (v_pesada + 4 + time '12:00') at time zone v_zona, 4, 'presencial'),
        (v_u, v_mat[4], (v_cat ->> 'Tarea')::uuid, 'Matriz de riesgos',
            (v_lunes - 4 + time '23:59') at time zone v_zona, 3, 'en_linea');

        update actividad set estado = 'en_progreso'
        where usuario_id = v_u and vence_en < (v_lunes + time '00:00') at time zone v_zona;
        update actividad set estado = 'completada'
        where usuario_id = v_u and vence_en < (v_lunes + time '00:00') at time zone v_zona
            and (v_es_ana or titulo <> 'Lectura: OWASP Top 10');
        update actividad set estado = 'cancelada'
        where usuario_id = v_u and titulo = 'Lectura: OWASP Top 10' and not v_es_ana;

        -- Actividades proximas (semana actual y siguiente): alimentan la agenda.
        insert into actividad (usuario_id, materia_id, categoria_id, titulo, vence_en, prioridad, modalidad)
        values
        (v_u, v_mat[1], (v_cat ->> 'Proyecto')::uuid, 'Entrega final del proyecto',
            (v_hoy + 5 + time '23:59') at time zone v_zona, 5, 'mixta')
        returning id into v_act_proyecto;
        insert into actividad (usuario_id, materia_id, categoria_id, titulo, vence_en, prioridad, modalidad, estado)
        values
        (v_u, v_mat[2], (v_cat ->> 'Tarea')::uuid, 'Reporte de analisis de vulnerabilidades',
            (v_hoy + 2 + time '23:59') at time zone v_zona, 4, 'en_linea', 'en_progreso'),
        (v_u, v_mat[3], (v_cat ->> 'Examen')::uuid, 'Examen final',
            (v_hoy + 7 + time '10:00') at time zone v_zona, 5, 'presencial', 'pendiente'),
        (v_u, v_mat[4], (v_cat ->> 'Exposicion')::uuid, 'Presentacion del proyecto',
            (v_hoy + 8 + time '12:00') at time zone v_zona, 4, 'presencial', 'pendiente'),
        (v_u, null, (v_cat ->> 'Estudio')::uuid, 'Repasar para el examen final',
            (v_hoy + 6 + time '20:00') at time zone v_zona, 3, 'en_linea', 'pendiente');

        insert into actividad_etiqueta (actividad_id, etiqueta_id, usuario_id)
        select a.id, v_etq_urgente, v_u from actividad as a
        where a.usuario_id = v_u and a.prioridad = 5 and a.estado <> 'completada';
        insert into actividad_etiqueta (actividad_id, etiqueta_id, usuario_id)
        select a.id, v_etq_equipo, v_u from actividad as a
        where a.usuario_id = v_u and a.modalidad = 'mixta';

        -- Eventos: clases semanales, el examen, la entrega ligada a su actividad y una reunion.
        insert into evento_calendario (usuario_id, materia_id, titulo, tipo, lugar, inicio, fin)
        select v_u, v_mat[1 + (s % 4)], 'Clase', 'clase', 'Aula ' || (101 + s % 4),
            (d + time '08:00') at time zone v_zona, (d + time '10:00') at time zone v_zona
        from generate_series(v_inicio, v_hoy + 13, interval '1 day') as g (dd)
        cross join lateral (select g.dd::date as d, extract(isodow from g.dd)::integer as s) as x
        where x.s between 1 and 4;
        insert into evento_calendario (usuario_id, materia_id, titulo, tipo, lugar, inicio, fin)
        values
        (v_u, v_mat[3], 'Examen final de Fundamentos de IA', 'examen', 'Aula 103',
            (v_hoy + 7 + time '10:00') at time zone v_zona, (v_hoy + 7 + time '12:00') at time zone v_zona),
        (v_u, v_mat[4], 'Reunion del equipo del proyecto', 'reunion', 'Biblioteca',
            (v_hoy + 1 + time '17:00') at time zone v_zona, (v_hoy + 1 + time '18:00') at time zone v_zona),
        (v_u, null, 'Consulta medica', 'personal', null,
            (v_hoy + 3 + time '09:00') at time zone v_zona, (v_hoy + 3 + time '10:00') at time zone v_zona);
        insert into evento_calendario (usuario_id, materia_id, actividad_id, titulo, tipo, inicio, fin)
        values (v_u, v_mat[1], v_act_proyecto, 'Entrega del proyecto final', 'entrega',
            (v_hoy + 5 + time '23:00') at time zone v_zona, (v_hoy + 5 + time '23:59') at time zone v_zona);

        -- Registros de tiempo de las cuatro semanas pasadas y de la actual hasta ayer.
        -- Empieza un dia antes para que la primera semana tenga sus siete noches de sueno.
        for v_dia in select g::date from generate_series(v_inicio - 1, v_hoy - 1, interval '1 day') as g loop
            v_semana := date_trunc('week', v_dia)::date;
            v_pesada_semana := v_semana = v_pesada;
            v_dow := extract(isodow from v_dia)::integer;

            -- Sueno: la noche de v_dia empieza despues de medianoche, asi cada noche cae en una
            -- sola semana. Ana 7.5 h (5.5 h en la semana pesada); Luis 6.5 h (4.5 h).
            v_dormir := case
                when v_es_ana and not v_pesada_semana then (v_dia + 1 + time '00:00') at time zone v_zona
                when v_es_ana then (v_dia + 1 + time '01:30') at time zone v_zona
                when not v_pesada_semana then (v_dia + 1 + time '00:30') at time zone v_zona
                else (v_dia + 1 + time '02:30') at time zone v_zona
            end;
            v_despertar := (v_dia + 1 + case when v_es_ana and not v_pesada_semana
                then time '07:30' else time '07:00' end) at time zone v_zona;
            if v_despertar <= now() and v_dormir >= (v_inicio + time '00:00') at time zone v_zona then
                insert into registro_tiempo (usuario_id, categoria_id, inicio, fin, origen)
                values (v_u, (v_cat ->> 'Sueno')::uuid, v_dormir, v_despertar, 'manual');
            end if;

            continue when v_dia < v_inicio;

            -- Estudio entre semana; mas horas en la semana pesada.
            if v_dow <= 5 then
                insert into registro_tiempo (usuario_id, categoria_id, actividad_id, inicio, fin, origen)
                values (
                    v_u, (v_cat ->> 'Estudio')::uuid, null,
                    (v_dia + time '16:00') at time zone v_zona,
                    (v_dia + time '16:00' + case
                        when v_pesada_semana then interval '4 hours'
                        when v_es_ana then interval '2 hours'
                        else interval '90 minutes' end) at time zone v_zona,
                    'temporizador'
                );
            end if;

            -- Ejercicio: Ana lunes, miercoles y viernes; Luis martes y jueves. En la semana pesada, casi nada.
            if (v_es_ana and v_dow in (1, 3, 5) and (not v_pesada_semana or v_dow = 1))
                or (not v_es_ana and v_dow in (2, 4) and not v_pesada_semana) then
                insert into registro_tiempo (usuario_id, categoria_id, inicio, fin, origen)
                values (v_u, (v_cat ->> 'Ejercicio')::uuid,
                    (v_dia + time '07:30') at time zone v_zona,
                    (v_dia + time '08:15') at time zone v_zona, 'temporizador');
            end if;

            -- Ocio: Luis juega algunas noches.
            if not v_es_ana and v_dow in (5, 6) then
                insert into registro_tiempo (usuario_id, categoria_id, inicio, fin, origen)
                values (v_u, (v_cat ->> 'Videojuegos')::uuid,
                    (v_dia + time '21:00') at time zone v_zona,
                    (v_dia + time '23:00') at time zone v_zona, 'manual');
            end if;

            -- Meditacion: Ana los domingos.
            if v_es_ana and v_dow = 7 then
                insert into registro_tiempo (usuario_id, categoria_id, inicio, fin, origen)
                values (v_u, (v_cat ->> 'Meditacion')::uuid,
                    (v_dia + time '09:00') at time zone v_zona,
                    (v_dia + time '09:20') at time zone v_zona, 'temporizador');
            end if;
        end loop;

        -- Un registro ligado a una actividad, con su sesion de temporizador ya cerrada.
        select id into v_act from actividad
        where usuario_id = v_u and titulo = 'Reporte de analisis de vulnerabilidades';
        insert into registro_tiempo (usuario_id, categoria_id, actividad_id, inicio, fin, origen, nota)
        values (v_u, (v_cat ->> 'Tarea')::uuid, v_act,
            (v_hoy - 1 + time '19:00') at time zone v_zona,
            (v_hoy - 1 + time '20:30') at time zone v_zona, 'temporizador', 'Primer borrador')
        returning id into v_reg;
        insert into sesion_temporizador (
            usuario_id, categoria_id, actividad_id, iniciada_en, estado, cerrada_en, registro_tiempo_id
        )
        values (v_u, (v_cat ->> 'Tarea')::uuid, v_act,
            (v_hoy - 1 + time '19:00') at time zone v_zona, 'cerrada',
            (v_hoy - 1 + time '20:30') at time zone v_zona, v_reg);

        -- Metas vigentes desde el inicio de la historia.
        insert into meta (usuario_id, categoria_id, tipo, periodo, objetivo, vigente_desde) values
        (v_u, (v_cat ->> 'Sueno')::uuid, 'tiempo_acumulado', 'dia', 420, v_inicio),
        (v_u, (v_cat ->> 'Estudio')::uuid, 'tiempo_acumulado', 'semana', case when v_es_ana then 600 else 480 end, v_inicio),
        (v_u, (v_cat ->> 'Ejercicio')::uuid, 'numero_eventos', 'semana', case when v_es_ana then 3 else 2 end, v_inicio);

        -- Autoevaluaciones semanales: bajan en la semana pesada.
        insert into autoevaluacion_semanal (usuario_id, semana_desde, estado_animo, satisfaccion, nota)
        select v_u, s::date,
            case when s::date = v_pesada then 2 when v_es_ana then 4 else 3 end,
            case when s::date = v_pesada then 2 when v_es_ana then 4 else 3 end,
            case when s::date = v_pesada then 'Semana de muchas entregas' end
        from generate_series(v_inicio, v_lunes - 7, interval '1 week') as s;

        -- Recordatorios: uno ya enviado y tres pendientes, siempre en el futuro.
        select id into v_act from actividad where usuario_id = v_u and titulo = 'Examen parcial';
        insert into recordatorio (usuario_id, actividad_id, momento, estado_envio, intentos, enviado_en)
        values (v_u, v_act, (v_pesada + 1 + time '20:00') at time zone v_zona, 'enviado', 1,
            (v_pesada + 1 + time '20:00') at time zone v_zona);
        insert into recordatorio (usuario_id, actividad_id, momento)
        values (v_u, v_act_proyecto, (v_hoy + 4 + time '20:00') at time zone v_zona);
        insert into recordatorio (usuario_id, evento_id, momento)
        select v_u, e.id, e.inicio - interval '1 day' from evento_calendario as e
        where e.usuario_id = v_u and e.tipo = 'examen';
        select id into v_meta from meta where usuario_id = v_u and categoria_id = (v_cat ->> 'Ejercicio')::uuid;
        insert into recordatorio (usuario_id, meta_id, momento)
        values (v_u, v_meta, (v_hoy + 2 + time '18:00') at time zone v_zona);
    end loop;

    -- Capturas por texto libre, para el reporte del pipeline de IA.
    -- Ana: tres aceptadas sin correccion y una corregida (1 campo).
    -- Luis: cuatro corregidas (2 campos cada una), una descartada y una pendiente.
    for v_u, v_act, v_es_ana in
        select a.usuario_id, a.id, a.usuario_id = v_ana from actividad as a
        where a.usuario_id in (v_ana, v_luis)
            and a.titulo in ('Algoritmo genetico', 'Matriz de riesgos', 'Exposicion de riesgos',
                'Reporte de analisis de vulnerabilidades')
        order by a.usuario_id = v_ana desc, a.titulo
    loop
        insert into mensaje_origen (usuario_id, canal, texto)
        select v_u, 'telegram', 'Recordatorio: ' || lower(titulo) || ' para el ' || to_char(vence_en at time zone v_zona, 'DD/MM')
        from actividad where id = v_act
        returning id into v_msg;
        insert into extraccion (
            usuario_id, mensaje_origen_id, entidad_tipo, propuesta, resuelta, modelo, confianza,
            estado, actividad_id, resuelta_en
        )
        select v_u, v_msg, 'actividad',
            jsonb_build_object('titulo', titulo, 'vence_en', vence_en),
            jsonb_build_object('titulo', titulo, 'vence_en', vence_en, 'categoria_id', categoria_id),
            'modelo-demo', case when v_es_ana then 0.92 else 0.71 end,
            case
                when v_es_ana and titulo <> 'Matriz de riesgos' then 'aceptada'
                else 'corregida'
            end,
            id, now()
        from actividad where id = v_act
        returning id into v_ext;

        if not v_es_ana or (select titulo from actividad where id = v_act) = 'Matriz de riesgos' then
            insert into correccion_campo (usuario_id, extraccion_id, campo, valor_propuesto, valor_final)
            values (v_u, v_ext, 'prioridad', '3', '4');
            if not v_es_ana then
                insert into correccion_campo (usuario_id, extraccion_id, campo, valor_propuesto, valor_final)
                values (v_u, v_ext, 'materia', '"Gestion de Proyectos"', '"Ciberseguridad"');
            end if;
        end if;
    end loop;

    insert into mensaje_origen (usuario_id, canal, texto)
    values (v_luis, 'app', 'mañana fiesta de cumpleaños de mi primo') returning id into v_msg;
    insert into extraccion (usuario_id, mensaje_origen_id, entidad_tipo, propuesta, resuelta, modelo, confianza, estado, resuelta_en)
    values (v_luis, v_msg, 'actividad', '{"titulo": "Fiesta"}', '{"titulo": "Fiesta"}', 'modelo-demo', 0.35, 'descartada', now());
    insert into mensaje_origen (usuario_id, canal, texto)
    values (v_luis, 'telegram', 'estudiar 2 horas diarias de redes') returning id into v_msg;
    insert into extraccion (usuario_id, mensaje_origen_id, entidad_tipo, propuesta, resuelta, pendientes, modelo, confianza)
    values (v_luis, v_msg, 'meta', '{"objetivo": 120}', '{"objetivo": 120}', '{categoria_id}', 'modelo-demo', 0.64);

    -- Evaluaciones de metas de los periodos ya cerrados, como las dejaria pg_cron.
    for v_dia in select g::date from generate_series(v_inicio + 1, (now() at time zone v_zona)::date, interval '1 day') as g loop
        perform kairo_evaluar_metas((v_dia + time '00:30') at time zone v_zona);
    end loop;

    raise notice 'Demo cargada: Ana % y Luis %.', v_ana, v_luis;
end
$$;

select set_config('kairo.hash_demo', '', false) \g /dev/null
