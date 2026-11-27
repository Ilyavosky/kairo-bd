-- T38. Planes de las 5 consultas frecuentes de la API, con y sin los indices de la propuesta.
-- Requiere haber ejecutado t38_volumen.sql. Cada bloque corre en una transaccion que se revierte:
-- el bloque "sin indices" los borra dentro de la transaccion, asi que la base no cambia.
-- Las consultas son las de kairo-backend (app/modules/reportes, registros_tiempo y
-- recordatorios/despacho.py), con los parametros que usa la API sustituidos.

\set ON_ERROR_STOP on
\pset pager off

select id as usuario from usuario where email = 'volumen50@prueba.mx' \gset
select id as estudio from categoria_actividad where nombre = 'Estudio' and usuario_id is null \gset
-- La API manda el filtro de fecha como parametro con valor concreto; se fija aqui igual.
select (now() - interval '30 days')::text as desde \gset

\echo '############ CON INDICES'
begin;
\ir t38_consultas.sql
rollback;

\echo '############ SIN INDICES'
begin;
drop index actividad_usuario_vence_idx;
drop index registro_usuario_categoria_inicio_idx;
drop index recordatorio_pendientes_idx;
drop index evento_usuario_inicio_idx;
\ir t38_consultas.sql
rollback;
