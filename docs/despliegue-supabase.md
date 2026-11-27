# Despliegue en Supabase

Proyecto: `uqiozvdagfouwzsbggla` (Postgres 17).

## Orden

1. Una sola vez, antes de cualquier migracion: `supabase/000_preparar_privilegios.sql`. Retira los
   privilegios que Supabase concede por defecto a `anon` y `authenticated` en `public`. Sin esto,
   la anon key podria ejecutar `kairo_buscar_credenciales` por `/rest/v1/rpc`.
2. `migrations/*.sql` en orden, **de una en una**. Si se aplican en paralelo, chocan por la version
   (marca de tiempo) del historial de migraciones.
3. Los jobs de `cron/` (solo Supabase; requieren `pg_cron`, `pg_net` y Vault).

Cada migracion queda registrada con el nombre del archivo sin extension
(`list_migrations` debe coincidir con `migrations/`).

## Verificacion despues de desplegar

- Comparar las huellas (md5 de columnas, restricciones, indices, politicas, funciones, vistas,
  triggers y permisos de los roles `kairo_*`) entre Supabase y un Postgres limpio con las mismas
  migraciones. Deben ser identicas.
- Linter de seguridad de Supabase sin hallazgos nuevos.
- `anon` y `authenticated` sin acceso a tablas, vistas ni funciones de `public`.

## Historial

| Fecha | Cambio |
|---|---|
| 2026-11-24 | `supabase/000` y migraciones 000-011 aplicadas; huellas identicas a la CI |
| 2026-11-25 | 012 aplicada tras validar la suite de la API; huellas identicas y linter de seguridad sin hallazgos |
| 2026-11-25 | 013, 014 y seed del calendario aplicados; huellas identicas y linter de seguridad sin hallazgos |
| 2026-11-25 | Fuera de migraciones (para la API): `grant kairo_app, kairo_worker to postgres` con set e inherit. Se revoca `kairo_app` al pasar a `kairo_api` (decision 007) |
| 2026-11-27 | 015 y 016 aplicadas; huellas identicas (incluidos roles y membresias) y linter de seguridad sin hallazgos |
| 2026-11-27 | 017 aplicada; huellas identicas (incluidas opciones de vistas) y linter de seguridad sin hallazgos |

## Trabajos de pg_cron

1. `supabase/001_extensiones.sql`: activa `pg_cron` y `pg_net` y da a `postgres` el `SET` sobre
   `kairo_worker` que necesitan los jobs.
2. Crear los dos secretos en Vault, a mano y fuera del repositorio. Desde `psql` como `postgres`:
   ```sql
   select vault.create_secret('https://kairo-backend-production-1a994ed5.up.railway.app', 'kairo_api_url', 'URL base de la API');
   select vault.create_secret('<INTERNO_SECRET de Railway>', 'kairo_interno_secret', 'Secreto del endpoint interno');
   ```
   El segundo valor es el mismo `INTERNO_SECRET` de Railway; no se escribe en ningun archivo.
3. `cron/001_programar_tareas.sql`: esquema `kairo_cron`, la funcion que llama a la API y el job de
   evaluacion de metas (minuto 10 de cada hora).
4. `cron/002_programar_despacho.sql`: el job de despacho cada 5 minutos. Se aplica solo cuando la API
   ya tiene desplegado el pool de `kairo_despachador`.

Verificacion: `select * from cron.job_run_details order by start_time desc limit 10;` y, para el
despacho, `select status_code, error_msg from net._http_response order by created desc limit 5;`.

## Seeds

Despues de las migraciones, `seeds/catalog/*.sql` en orden. Son idempotentes. Los seeds no se
registran en el historial de migraciones.

Los datos de demostracion (`seeds/demo/`) se cargan aparte, el dia de la defensa o la noche
anterior, siguiendo `docs/demo.md`.
