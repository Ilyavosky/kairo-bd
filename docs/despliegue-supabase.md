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

## Seeds

Despues de las migraciones, `seeds/catalog/*.sql` en orden. Son idempotentes. Los seeds no se
registran en el historial de migraciones.
