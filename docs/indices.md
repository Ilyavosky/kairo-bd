# Indices y planes de consulta (T38)

Fecha: 2026-11-27. Base: `develop` con las migraciones 000 a 017.

## Objetivo

Comprobar con evidencia que los indices de la propuesta existen, que el planificador los elige
con un volumen realista sin forzarlo, y que las consultas frecuentes de la API responden en menos
de 50 ms sin recorridos secuenciales (`Seq Scan`) sobre las tablas grandes.

## Indices verificados

Los tres indices que pide T38 ya existen; no hizo falta crear ninguno.

| Indice | Definicion | Migracion | Lo usan |
|---|---|---|---|
| `actividad_usuario_vence_idx` | `actividad (usuario_id, vence_en)` | 001 | Agenda, carga semanal |
| `registro_usuario_categoria_inicio_idx` | `registro_tiempo (usuario_id, categoria_id, inicio)` | 002 | Registros por categoria, carga semanal, progreso de metas |
| `recordatorio_pendientes_idx` | `recordatorio (momento) where estado_envio = 'pendiente'` (parcial) | 008 | Despacho de recordatorios |

Tambien se midio `evento_usuario_inicio_idx` (`evento_calendario (usuario_id, inicio)`, migracion
002), que usa la agenda.

## Metodo

- **Volumen** (`scripts/rendimiento/t38_volumen.sql`): 100 usuarios ficticios, 10 000 actividades,
  50 000 registros de tiempo, 3 000 eventos, 20 000 recordatorios (60 pendientes vencidos),
  300 metas y 600 materias. Los triggers generaron ademas 69 600 filas de `resumen_periodo` y
  10 000 de `bitacora_cambios`. Despues, `analyze`.
- **Consultas** (`scripts/rendimiento/t38_consultas.sql`): las mismas que ejecuta `kairo-backend`
  (`app/modules/reportes/repository.py`, `registros_tiempo/repository.py` y
  `recordatorios/despacho.py`), con los parametros que usa la API.
- **Rol y sesion reales:** las cuatro primeras corren como `kairo_app` con `app.usuario_id` fijado,
  asi que pasan por la RLS y por las vistas con `security_invoker`. El despacho corre como
  `kairo_worker`, con `for update skip locked`.
- **Sin forzar el planificador:** no se usa `enable_seqscan = off`; el plan es el que Postgres elige.
- **Antes y despues** (`scripts/rendimiento/t38_planes.sql`): el bloque "sin indices" borra los
  cuatro indices dentro de una transaccion que se revierte.
- **Medicion:** `explain (analyze, buffers)`, mediana de 5 corridas. Las paginas leidas
  (`shared hit`) son identicas en las 5 corridas y no dependen de la maquina.
- **Entorno:** PostgreSQL 16 local. Supabase usa PostgreSQL 17; el planificador decide igual para
  estas consultas. Supabase no tiene datos de volumen y no debe tenerlos, por eso la medicion es local.

## Resultados

Tiempo total = planificacion + ejecucion, en milisegundos (mediana de 5 corridas).

| # | Consulta | Con indices | Sin indices | Paginas con / sin | Seq Scan en tablas grandes (con indices) |
|---|---|---|---|---|---|
| 1 | Agenda proxima (14 dias, 50 filas) | 1.81 ms | 1.27 ms | 61 / 262 | Ninguno |
| 2 | Carga semanal por materia (9 semanas) | 3.44 ms | 3.60 ms | 630 / 1 118 | Ninguno |
| 3 | Registros por categoria (30 dias, 50 filas) | 0.22 ms | 1.70 ms | 17 / 913 | Ninguno |
| 4 | Progreso de metas | 1.09 ms | 4.23 ms | 20 / 2 747 | Ninguno |
| 5 | Recordatorios vencidos (lote de 20) | 2.53 ms | 5.58 ms | 323 / 710 | Ninguno |

El unico `Seq Scan` con indices es sobre `categoria_actividad`, que tiene 10 filas: para una tabla
de ese tamano es lo mas barato y no es un problema.

Los planes completos de una corrida estan en `docs/indices-planes.txt`.

## Analisis por consulta

1. **Agenda proxima.** Usa `actividad_usuario_vence_idx` con las dos condiciones (`usuario_id` y el
   rango de `vence_en`) y `evento_usuario_inicio_idx` para los eventos. Lee 61 paginas contra 262.
   Sin los indices tarda casi lo mismo porque el planificador recorre completo el indice unico
   `(id, usuario_id)`; ese recorrido crece con el tamano total de la tabla, no con el del usuario.
   El tiempo de planificacion es un poco mayor con indices porque hay mas planes que evaluar.
2. **Carga semanal.** Usa `actividad_usuario_vence_idx` y `registro_usuario_categoria_inicio_idx`,
   pero lee todo el historial del usuario (500 registros) y despues filtra por semana: la vista
   agrega primero y el filtro de `semana_desde` llega despues de agrupar. Con 3.4 ms esta lejos
   del limite; ver la observacion 2.
3. **Registros por categoria.** Usa las tres columnas de `registro_usuario_categoria_inicio_idx`
   (`usuario_id`, `categoria_id` y el rango de `inicio`) y solo lee las 14 filas que devuelve:
   17 paginas contra 913, 54 veces menos. Sin el indice lee los 500 registros del usuario y
   descarta 486. El filtro `(%s is null or inicio >= %s)` de la API no estorba: como la fecha llega
   como parametro con valor, el planificador simplifica la condicion y usa el indice completo.
4. **Progreso de metas.** Para cada meta hace un `Index Scan` sobre
   `registro_usuario_categoria_inicio_idx` con las tres columnas, incluido el rango del periodo en
   la zona horaria del usuario. Lee 20 paginas contra 2 747: 137 veces menos.
5. **Recordatorios vencidos.** Usa el indice parcial `recordatorio_pendientes_idx` y solo toca los
   60 pendientes vencidos; los 19 940 restantes no se leen. Sin el indice recorre `recordatorio` y
   `actividad` completas (`Seq Scan`).

## Conclusion

- **Criterio "ninguna consulta de la API supera 50 ms": se cumple.** La mas lenta tarda 3.4 ms.
- **Criterio "sin Seq Scan sobre las tablas grandes en las 5 consultas": se cumple.**
- Los tres indices de la propuesta se usan sin forzar el planificador. Su efecto principal es en
  las paginas leidas, que bajan entre 2 y 137 veces. Esa diferencia crece con el volumen: los
  planes sin indices recorren estructuras que escalan con la tabla completa, mientras que los
  planes con indices escalan con los datos de un solo usuario.
- Ningun indice nuevo se justifica: cada uno cuesta en escritura (cada registro de tiempo ya
  actualiza tres filas de `resumen_periodo`) y las cinco consultas ya estan muy por debajo del
  limite.

## Observaciones

1. **Indices unicos `(id, usuario_id)` como respaldo.** Existen para las llaves foraneas
   compuestas que impiden mezclar usuarios. Cuando falta el indice por usuario, el planificador
   los usa recorriendolos completos, por eso el escenario "sin indices" no cae en `Seq Scan` en
   cuatro de las cinco consultas. No sustituyen a los indices de la propuesta.
2. **Carga semanal.** Si el historial de un usuario creciera mucho (varios anos), convendria filtrar
   por fecha dentro de la vista, antes de agrupar. Con el volumen de un cuatrimestre no hace falta.

## Como reproducirlo

Sobre una base local vacia con todas las migraciones aplicadas, nunca sobre Supabase:

```
psql "$DATABASE_URL_LOCAL" -f scripts/rendimiento/t38_volumen.sql
psql "$DATABASE_URL_LOCAL" -f scripts/rendimiento/t38_planes.sql
```

Los scripts no estan en `tests/` porque la CI ejecuta todo lo que hay ahi y la carga de volumen
tarda. La prueba rapida de que los indices siguen existiendo y son elegibles es
`tests/performance/011_planes_con_indices.sql`.
