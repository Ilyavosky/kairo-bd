# 003. Captura con IA, resumen por periodo y bitacora de registros

Fecha: 2026-11-21. Migraciones 006 y 007.

## Captura: tres tablas y una propuesta inmutable

- `mensaje_origen` guarda el texto tal como llego (`app` o `telegram`, de 1 a 2000 caracteres).
- `extraccion` guarda dos versiones de la propuesta. `propuesta` es la salida del modelo sin tocar.
  `resuelta` es la misma propuesta ya resuelta contra la base: referencias por id y fechas
  absolutas. `pendientes` lista los campos que el sistema no pudo resolver.
- `kairo_app` solo puede actualizar `estado`, `actividad_id`, `registro_tiempo_id`, `meta_id` y
  `resuelta_en` (permiso por columna), de modo que la propuesta del modelo no se reescribe nunca.
- Un `CHECK` liga el estado con el resultado: `aceptada` y `corregida` tienen exactamente una fila
  destino y del tipo que corresponde a `entidad_tipo`; `pendiente` y `descartada` no tienen
  ninguna. `resuelta_en` es nulo solo mientras la extraccion esta `pendiente`.
- Las llaves foraneas son compuestas `(id, usuario_id)`, igual que en las fases anteriores, para
  que una extraccion no apunte a mensajes ni a filas de otro usuario.
- `correccion_campo` guarda, por extraccion y campo, el valor propuesto y el valor final (JSONB).
  Un `CHECK` exige que ambos sean distintos: solo se registra lo que cambio de verdad.

## Metricas del pipeline

El porcentaje aceptado sin correccion se calcula como `aceptadas / (aceptadas + corregidas +
descartadas)`: una propuesta descartada cuenta como fallo del pipeline. Las pendientes no entran.
El promedio de campos corregidos se calcula sobre las extracciones aceptadas y corregidas, con 0
para las aceptadas. Ambas cifras salen de `GET /capturas/metricas`, por usuario. La vista agregada
del equipo queda para la fase de reportes.

## resumen_periodo

- Cache de segundos y numero de registros por usuario, categoria y periodo (`dia`, `semana` desde
  el lunes, `mes`). Se guarda en segundos y no en minutos para no perder precision al sumar.
- Lo mantiene el trigger `registro_tiempo_resumen` (`security definer`) al insertar un registro o
  al editar `categoria_id`, `inicio` o `fin`: resta el registro viejo de su cubeta y suma el
  nuevo. Una edicion que mueve el registro de dia o de categoria deja la cubeta anterior en 0
  en lugar de borrarla.
- El periodo se calcula con la zona horaria que tiene el usuario **al escribir el registro**. Si
  cambia su zona despues, los resumenes anteriores no se recalculan.
- `kairo_app` solo lee la tabla. La migracion rellena el resumen con los registros que ya existan.

## Bitacora de ediciones de registro_tiempo

El trigger `registro_tiempo_bitacora` escribe una fila en `bitacora_cambios` por cada campo que
cambia (`categoria_id`, `actividad_id`, `inicio`, `fin`, `nota`). Los valores se guardan como
texto; las fechas con la zona horaria de la sesion que hizo el cambio. Una edicion que deja el
valor igual no escribe nada. El alta no se registra: la fila misma es el valor inicial.

## Pendiente

- Permisos de `kairo_worker` y `kairo_lectura` sobre las tablas nuevas (se definen junto con
  `pg_cron` en la fase de recordatorios).
- `correccion_campo` y `extraccion` no tienen `DELETE`: la limpieza, si hace falta, va por un
  proceso administrativo.
