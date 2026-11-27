# 007. Roles de conexion para la API y el despacho

Fecha: 2026-11-26. Migracion 015. Acordado por Moises e Ilya.

## Contexto

La API se conectaba a Supabase como `postgres` por el Session pooler (5432) y ejecutaba
`set role kairo_app` al abrir cada conexion del pool. Funcionaba porque `postgres` recibio a mano,
fuera de las migraciones, los roles `kairo_app` y `kairo_worker` con `set` e `inherit`.

Debilidades:

- La sesion nace como `postgres`, que tiene `BYPASSRLS`; un `reset role` basta para volver a el.
- Con el Transaction pooler (6543) el `set role` de sesion se pierde entre transacciones y algunas
  consultas correrian como `postgres`, sin RLS y sin ningun error visible.

## Decision

Los roles de permisos (`kairo_app`, `kairo_worker`, `kairo_lectura`) siguen siendo `NOLOGIN`. Cada
servicio se conecta con un rol propio que solo hereda el rol de permisos que necesita:

| Rol con login | Hereda | Lo usa | statement_timeout |
|---|---|---|---|
| `kairo_api` | `kairo_app` | Peticiones de la API y del bot (pooler en modo transaccion, 6543) | 15 s |
| `kairo_despachador` | `kairo_worker` | Solo el endpoint interno de despacho de recordatorios | 30 s |

- Ninguno es superusuario, dueno de objetos, miembro de `kairo_owner` ni tiene `BYPASSRLS`
  (`tests/permissions/015_roles_de_conexion.sql`).
- `kairo_api` no puede hacer `set role kairo_worker`: el despacho usa su propia conexion
  (`DATABASE_URL_WORKER`). Se descarto una funcion `security definer` para el despacho porque
  tendria que leer datos de todos los usuarios y quedaria al alcance de cualquier consulta de la API.
- La API fija `app.usuario_id` con `set_config(..., true)` en cada transaccion, compatible con el
  Transaction pooler.

## Contrasenas

La migracion no define contrasenas. Las asigna Moises directamente en Supabase, de preferencia con
`\password kairo_api` desde `psql` (envia el hash, no el texto plano), y se guardan solo en Railway.
Mientras no tengan contrasena, los roles no pueden iniciar sesion.

Cadena de la API (usuario con el sufijo del proyecto que exige Supavisor):
`postgresql://kairo_api.uqiozvdagfouwzsbggla:<contrasena>@aws-0-us-east-1.pooler.supabase.com:6543/postgres?sslmode=require`,
con `DB_ROLE` vacio.

## Pendiente despues del cambio

Cuando la API y el despacho usen los roles nuevos, revocar los permisos dados a mano a `postgres`:
`revoke kairo_app from postgres`. `kairo_worker` se conserva mientras `pg_cron` ejecute
`set local role kairo_worker` (decision 006, D2).
