# 004. Recordatorios, autoevaluacion, vinculo de Telegram y rol worker

Fecha: 2026-11-24. Migraciones 008, 009 y 010 y `cron/001_programar_tareas.sql`.

## Recordatorio

- Apunta a una actividad, un evento o una meta con llaves foraneas compuestas `(id, usuario_id)` y
  un `CHECK` con `num_nonnulls(...) = 1`: exactamente un objetivo. Para eso `evento_calendario`
  gana `unique (id, usuario_id)`.
- `estado_envio` (`pendiente`, `enviado`, `fallido`, `cancelado`), `intentos`, `enviado_en` y
  `ultimo_error` los escribe el despachador. Un `CHECK` liga `enviado` con `enviado_en` no nulo.
- `kairo_app` inserta solo los campos del usuario (la politica exige estado `pendiente`) y puede
  actualizar `momento` y `estado_envio`, pero la politica solo deja pasar de `pendiente` a
  `pendiente` o `cancelado`. Un recordatorio cerrado ya no se edita.
- Indice parcial sobre `momento` donde `estado_envio = 'pendiente'` para la consulta del despacho.

## autoevaluacion_semanal

Una por usuario y semana (`semana_desde` es el lunes, con `CHECK` de `isodow = 1`). Animo y
satisfaccion de 1 a 5. Un trigger actualiza `actualizada_en` con `clock_timestamp()`, porque
`now()` no avanza dentro de una transaccion.

## Vinculo de Telegram

- `vinculo_telegram` guarda el SHA-256 del codigo, su expiracion y cuando se uso. El codigo en
  claro no se almacena.
- `kairo_vincular_telegram(hash, telegram_id)` es `security definer`: canjea un codigo vigente y
  fija `usuario.telegram_id`. Si ese Telegram ya pertenece a otra cuenta, la violacion de unico
  se captura y el codigo no se consume. `kairo_usuario_por_telegram` resuelve al usuario de un
  mensaje del bot antes de que exista sesion, igual que `kairo_buscar_credenciales` en el login.
- Se revoca `update (telegram_id)` a `kairo_app`. Antes un usuario podia escribir cualquier
  Telegram en su cuenta sin demostrar que lo controlaba, y bloquear que su dueno real se vinculara.

## Rol worker

`kairo_worker` ya existia desde la migracion 000 sin permisos. La 010 le da lectura por columna de
lo minimo para armar el aviso (usuario: id, telegram_id, zona horaria, activo; actividad: titulo y
vencimiento; evento: titulo e inicio; meta; nombre de categoria) y actualizacion solo de las
columnas de estado del recordatorio. No lee descripciones, registros de tiempo ni capturas. Cada
politica `to kairo_worker` es de solo lectura salvo la del recordatorio.

## kairo_evaluar_metas

Funcion `security definer` que evalua el ultimo periodo cerrado de cada meta activa, en la zona de
su usuario, y lo inserta en `evaluacion_meta` con `on conflict do nothing`, de modo que correrla
dos veces no duplica. `pg_cron` la llama cada hora. El valor es minutos para `tiempo_acumulado` y
numero de registros para `numero_eventos`, igual que el progreso que calcula la API.

## pg_cron

`cron/001_programar_tareas.sql` programa el despacho cada 5 minutos con `pg_net` (POST al backend
con el secreto interno; hay que sustituir la URL y el secreto antes de ejecutarlo) y la evaluacion
de metas. La llamada periodica mantiene despierto el servicio gratuito de Render.
