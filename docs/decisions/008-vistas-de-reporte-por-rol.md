# 008. Vistas de reporte por rol

Fecha: 2026-11-27. Migracion 017. Cierra T37 (opcion B acordada para `kairo_lectura`).

## Contexto

La migracion 011 creo cinco vistas por usuario (`v_*`) que filtran con `app_usuario_id()` y se
ejecutan como su dueno. Se concedieron a `kairo_app` y a `kairo_lectura`, pero `kairo_lectura` no
fija `app.usuario_id`, asi que siempre recibia cero filas. T37 pide ademas que el desempeno del
pipeline se vea agregado de todos los usuarios, solo para `kairo_lectura`.

## Decision

- **Vistas por usuario (`v_*`), para `kairo_app`:** pasan a `security_invoker = true`. Ademas del
  filtro por `app_usuario_id()`, se evaluan con los permisos y la RLS de quien consulta, asi que un
  error en el filtro ya no expone datos de otro usuario. `kairo_lectura` deja de tener acceso.
- **Vistas agregadas (`vl_*`), solo para `kairo_lectura`:** son de `kairo_owner` y no usan
  `security_invoker`, para leer a todos los usuarios sin dar a `kairo_lectura` acceso a las tablas
  base. Solo devuelven totales y promedios; ninguna columna identifica a un usuario ni contiene
  texto escrito por el.

| Vista | Que muestra |
|---|---|
| `vl_desempeno_pipeline` | Por tipo de entidad: extracciones, usuarios, estados, % aceptado sin correccion, campos corregidos y confianza promedio |
| `vl_cruce_carga_descanso` | Por semana: entregas que vencen contra minutos academicos, de sueno y de ejercicio por usuario, con animo y satisfaccion promedio |
| `vl_uso_por_categoria` | Por semana y categoria del sistema (las propias se agrupan como `Propias`): usuarios, registros y minutos |

## Notas

- Con pocos usuarios (por ejemplo, la demo con dos), un promedio puede revelar el dato de una
  persona. Es aceptable para el proyecto; en produccion convendria exigir un minimo de usuarios por
  grupo antes de mostrarlo.
- `tests/permissions/011_permisos_por_rol.sql` se actualizo al nuevo reparto de vistas por rol.
