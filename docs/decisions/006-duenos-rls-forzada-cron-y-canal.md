# 006. Dueno del esquema, RLS forzada, rol de pg_cron y canal de recordatorios

Fecha: 2026-11-25. Migracion 012. Acordado por Moises e Ilya (opciones 1A, 2A y 3B).

## D1. kairo_owner es dueno de todo, con BYPASSRLS y NOLOGIN

- Todas las tablas, vistas y funciones de `public` pasan de `postgres` a `kairo_owner`.
- `kairo_owner` es `NOLOGIN` y `BYPASSRLS`. Las funciones `security definer` (credenciales, alta
  de usuario, Telegram, evaluacion de metas, triggers de bitacora y resumen) y las vistas de
  reporte se ejecutan como su dueno y siguen funcionando igual.
- Todas las tablas tienen RLS habilitada y **forzada** (`force row level security`), como pide T09.
  Un rol con `BYPASSRLS` ignora las politicas incluso con `FORCE`, asi que la regla es formal para
  el dueno y no cambia su comportamiento.
- El aislamiento real descansa en que ningun rol de conexion (`kairo_app`, `kairo_worker`,
  `kairo_lectura`) es dueno, superusuario, miembro de `kairo_owner` ni tiene `BYPASSRLS`.
  `tests/permissions/012_duenos_y_roles.sql` lo verifica con `pg_roles` y `pg_class`.
- `postgres` recibe `kairo_owner` con `inherit true, set true`. `set` porque Postgres 16+ no se lo da al
  creador del rol y sin el no puede transferir la propiedad; `inherit` porque en Supabase
  `postgres` no es superusuario y sin heredar perderia acceso a las tablas (dashboard, MCP).

### Regla para las migraciones siguientes

Toda migracion nueva empieza con `set role kairo_owner;`, para que los objetos nazcan con el dueno
correcto. La prueba 012 falla si aparece una tabla, vista o funcion de otro dueno.

### Endurecimiento incluido en la 012

- `search_path` fijo en las cinco funciones que no lo tenian (aviso 0011 del linter de Supabase).
- `revoke execute ... from public` en las siete funciones de trigger. Los triggers siguen
  disparando: el permiso solo se revisa al crear el trigger.
- `alter default privileges for role kairo_owner ... revoke execute on functions from public`: las
  funciones nuevas no quedan ejecutables por `PUBLIC`; cada migracion concede `execute` explicito.

## D2. pg_cron corre como kairo_worker

- Los jobs ejecutan `set local role kairo_worker; select kairo_<tarea>();`. Requiere
  `grant kairo_worker to postgres with set true` (va con T32).
- La funcion que lee Vault (URL de la API e `INTERNO_SECRET`) y llama a `net.http_post` queda con
  `postgres` como dueno, para que `kairo_owner` no necesite acceso a `vault` ni a `net`.
  `kairo_worker` recibe `execute` sobre ella; sobre `kairo_evaluar_metas` ya lo tiene desde la 010.
- `schedule_in_database(..., username)` se descarto: pg_cron lo reserva a superusuarios.
- La URL de la API es `https://kairo-backend-production-1a994ed5.up.railway.app` (Railway, no
  Render). `cron/001_programar_tareas.sql` se reemplaza en el trabajo de T32.

## D3. recordatorio sin columna canal en v1

En v1 todo recordatorio se envia por Telegram. No se agrega `canal` (pedido en T18) porque el valor
`app` no tendria consumidor: un recordatorio con ese canal nunca se entregaria, y la app no tiene
notificaciones previstas. Se agregara con una migracion cuando exista ese consumidor.
