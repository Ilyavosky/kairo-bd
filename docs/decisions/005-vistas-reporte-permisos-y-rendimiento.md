# 005. Vistas de reporte, permisos por rol y revision de indices

Fecha: 2026-11-24. Migracion 011.

## Vistas

`v_agenda_proxima`, `v_carga_semanal_materia`, `v_progreso_metas`, `v_desempeno_pipeline` y
`v_carga_vs_descanso`. Las cifras de los reportes y del resumen salen de aqui; el LLM nunca las calcula.

- Pertenecen al rol de migraciones (no son `security_invoker`) y llevan `security_barrier = true`.
  Cada una filtra explicitamente con `where usuario_id = app_usuario_id()`.
- Sin `app.usuario_id` en la sesion devuelven cero filas.
- Las semanas empiezan el lunes en la zona horaria del usuario.

## Permisos

- `kairo_app` y `kairo_lectura` reciben `select` sobre las cinco vistas y nada mas para `kairo_lectura`:
  no tiene acceso a las tablas base.
- `kairo_app` no tiene `delete` salvo en `actividad_etiqueta`, ni DDL.
- `revoke create on schema public from public`.
- `tests/permissions/011_permisos_por_rol.sql` recorre `pg_class` con `has_table_privilege` y falla
  si aparece un permiso de mas.

## Indices

`tests/performance/011_planes_con_indices.sql` ejecuta EXPLAIN con `enable_seqscan = off` y exige
`actividad_usuario_vence_idx`, `registro_usuario_categoria_inicio_idx` y `recordatorio_pendientes_idx`.
Con el volumen de la entrega el planificador puede preferir un recorrido secuencial; la prueba solo
confirma que cada indice es utilizable por su consulta.
