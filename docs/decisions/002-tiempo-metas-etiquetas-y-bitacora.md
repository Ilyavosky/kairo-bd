# 002. Tiempo, metas, etiquetas y bitacora de la fase 2

Fecha: 2026-11-20. Migraciones 002 a 005.

## Temporizador sin pausa

La v1 solo tiene iniciar y detener. `sesion_temporizador` no guarda tiempo acumulado ni
reanudacion. Si la app necesita pausa, se agrega en una migracion posterior.

`kairo_app` no tiene `DELETE`, asi que la sesion se cierra con `UPDATE` a `cerrada`. El indice unico
parcial `sesion_una_en_curso_por_usuario` (`where estado = 'en_curso'`) impide dos sesiones en curso
para el mismo usuario. Al detener, la API inserta el `registro_tiempo` con `origen = 'temporizador'`
y deja su id en `sesion_temporizador.registro_tiempo_id`.

## Integridad entre usuarios

Mismo patron que la fase 1: `actividad` gana `unique (id, usuario_id)` y las tablas que la
referencian usan llave compuesta `(actividad_id, usuario_id)`. Lo mismo para `materia`, `etiqueta`,
`meta` y `registro_tiempo`. La categoria se valida con `validar_categoria_del_usuario()`, version
generica del trigger de `actividad`, en `registro_tiempo`, `sesion_temporizador` y `meta`.

## Metas

- `objetivo` es un entero positivo. En `tiempo_acumulado` son minutos; en `numero_eventos` es el
  numero de registros de tiempo de la categoria en el periodo. **Interpretacion de "numero de
  eventos" por confirmar con el equipo**: `evento_calendario` no tiene categoria, asi que no puede
  contarse por categoria.
- Solo minimos, sin tope.
- El indice unico parcial de meta activa incluye `tipo`: una meta de tiempo y una de numero de
  eventos para la misma categoria y periodo pueden convivir. La propuesta decia categoria y
  periodo; se agrego `tipo` para no bloquear esa combinacion.
- El periodo es `dia`, `semana` (desde el lunes, como `date_trunc`) o `mes`, en la zona horaria
  del usuario. Los registros cuentan por su `inicio`.
- `evaluacion_meta` se crea ahora pero `kairo_app` solo puede leerla. La escritura la hace
  `kairo_worker` con `pg_cron`, que se configura en la fase de recordatorios.

## Etiquetas

`etiqueta` es unica por usuario sin distinguir mayusculas (`lower(nombre)`). `actividad_etiqueta`
es la tabla puente y es la unica donde `kairo_app` tiene `DELETE`, para poder quitar una etiqueta.

## Bitacora

`bitacora_cambios` gana `usuario_id` para que la RLS pueda filtrarla, y referencia a una actividad
o a un registro de tiempo (`num_nonnulls = 1`). `kairo_app` solo la lee: la escribe el trigger
`actividad_registrar_estado`, `security definer`, que anota el estado inicial y cada cambio de
estado. No se reemplazo `actividad_fijar_completada_en`; son dos triggers independientes.
La bitacora de ediciones de `registro_tiempo` queda para la migracion 007.

## Pendiente

- `recordatorio` y `autoevaluacion_semanal` (resto de la migracion 004 del plan) no entran en la
  fase 2.
- Los roles `kairo_worker` y `kairo_lectura` no tienen grants sobre las tablas nuevas todavia.
