# kairo-bd

Base de datos de Kairo (PostgreSQL en Supabase): migraciones, seeds, pruebas SQL y documentación del esquema.

## Estructura

| Carpeta | Contenido |
|---|---|
| `migrations/` | Esquema, roles, RLS, vistas y permisos, en orden (`000` a `017`) |
| `seeds/catalog/` | Catálogos compartidos (calendario académico); idempotentes |
| `seeds/demo/` | Datos de demostración con dos usuarios ficticios; ver `docs/demo.md` |
| `tests/` | Pruebas SQL que corre la CI: permisos, RLS, triggers, vistas y rendimiento |
| `supabase/` | Preparación única del proyecto Supabase, antes de las migraciones |
| `cron/` | Trabajos de `pg_cron` (solo Supabase) |
| `scripts/rendimiento/` | Volumen y planes de consulta de T38; se ejecutan a mano, nunca en Supabase |
| `docs/` | Decisiones, despliegue, índices y demo |

## Roles

Los roles de permisos no inician sesión; cada servicio se conecta con un rol propio que solo hereda el que necesita.

| Rol | Login | Para qué |
|---|---|---|
| `kairo_owner` | No | Dueño de todo el esquema, con `BYPASSRLS`; solo para migraciones |
| `kairo_app` | No | Permisos de la API: lectura y escritura de los datos del usuario de la sesión, con RLS |
| `kairo_worker` | No | Permisos del despacho de recordatorios y la evaluación de metas |
| `kairo_lectura` | No | Solo las vistas agregadas `vl_*` |
| `kairo_api` | Sí | Conexión de la API (pooler en modo transacción); hereda `kairo_app` |
| `kairo_despachador` | Sí | Conexión del despacho de recordatorios; hereda `kairo_worker` |

Las contraseñas de los roles con login no están en el repositorio: se asignan en Supabase y se guardan en Railway. Detalle en las decisiones 006 y 007.

## Reglas de las migraciones

- Nombre: `NNN_descripcion_en_snake_case.sql`, con tres dígitos consecutivos. Ejemplo: `001_crear_usuario.sql`.
- Solo hacia adelante: no hay rollbacks. Un cambio posterior es una migración nueva.
- Una migración ya mergeada nunca se edita.
- Desde la 013, cada migración empieza con `set role kairo_owner;` y termina con `reset role;`, para que los objetos nazcan con el dueño correcto. `tests/permissions/012_duenos_y_roles.sql` falla si aparece un objeto de otro dueño.
- Toda tabla nueva lleva RLS habilitada y forzada, sus políticas, los `GRANT` por rol y `COMMENT` en tabla y columnas.
- Las reglas de integridad viven en la base: `NOT NULL`, `CHECK`, `UNIQUE` y claves foráneas. Las fechas son `timestamptz`.
- Nadie cambia el esquema a mano en Supabase; todo entra por migración.

## CI

El workflow `CI` (job `migraciones`) corre en cada pull request y en cada push a `main`:

1. Levanta un Postgres 17 desechable, siempre desde cero.
2. Revisa las migraciones con `sqlfluff`.
3. Aplica `migrations/*.sql` en orden con `psql`.
4. Ejecuta las pruebas de `tests/**/*.sql`.

## Probar en local

```
docker run --rm -d --name kairo-pg -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=kairo_test -p 5432:5432 postgres:17
for f in migrations/*.sql; do psql postgresql://postgres:postgres@localhost:5432/kairo_test -v ON_ERROR_STOP=1 -f "$f"; done
shopt -s globstar; for f in tests/**/*.sql; do psql postgresql://postgres:postgres@localhost:5432/kairo_test -v ON_ERROR_STOP=1 -f "$f"; done
```

## Despliegue en Supabase

Orden, verificación e historial en `docs/despliegue-supabase.md`. Resumen: `supabase/000_preparar_privilegios.sql` una sola vez, después las migraciones de una en una y por último los seeds de `seeds/catalog/`.

## Documentación

| Documento | Tema |
|---|---|
| `docs/decisions/001` a `008` | Decisiones de diseño y desviaciones respecto a la propuesta |
| `docs/despliegue-supabase.md` | Orden de despliegue, verificación e historial |
| `docs/indices.md` | Evidencia de índices con `EXPLAIN ANALYZE` (T38) |
| `docs/demo.md` | Datos y guion de la demostración |

## Aplazado para después de v1

| Tema | Estado en v1 | Referencia |
|---|---|---|
| Fechas oficiales de la UPCH en el calendario | Solo los feriados federales de sep-dic 2026; no estaban publicadas | T06, `seeds/catalog/001_calendario_academico_2026.sql` |
| Columna `recordatorio.canal` | No existe: todo recordatorio se envía por Telegram; el valor `app` no tendría consumidor | T18, decisión 006 (D3) |
| `tipo` de evento propuesto por la IA | El extractor no lo propone; los eventos capturados quedan como `personal` | Para no invalidar la medición de T35 |
| Umbral mínimo de usuarios en las vistas agregadas | Con pocos usuarios, un promedio puede revelar el dato de una persona | Decisión 008 |
| Filtro por fecha dentro de `v_carga_semanal_materia` | Lee todo el historial del usuario y filtra después de agrupar; 3.4 ms con volumen de prueba | `docs/indices.md` |
| Retención limitada de `mensaje_origen` | Se conserva sin fecha de expiración, para historial y trazabilidad completos (acordado el 24 nov) | T25 |

## Flujo de trabajo

Ramas de feature desde `develop`, commits convencionales, un PR pequeño por issue enlazado con `Closes #n`.
