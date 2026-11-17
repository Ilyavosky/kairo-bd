# 001. Autenticacion propia y valores de dominio de la fase 1

Fecha: 2026-11-16. Migraciones 000 y 001.

## Autenticacion

La API autentica con correo y contrasena (argon2) y emite su propio JWT. Por eso `usuario`
tiene `email` y `password_hash` y no tiene `auth_id`: la identidad es `usuario.id`, que va como
`sub` del token. `telegram_id` es opcional y unico.

`password_hash` no se concede por `SELECT` a `kairo_app`. El alta y la busqueda de credenciales
pasan por dos funciones `security definer` (`kairo_registrar_usuario`, `kairo_buscar_credenciales`),
para no abrir una politica de `INSERT` o `SELECT` sin sesion.

## Aislamiento

La API fija `app.usuario_id` con `set_config(..., true)` dentro de cada transaccion. Las politicas
comparan `usuario_id` contra `app_usuario_id()`. Sin sesion, `app_usuario_id()` es nulo y no se ve
ninguna fila. El superusuario y el propietario de las tablas no pasan por RLS: las pruebas de
aislamiento deben correr con `set role kairo_app`.

## Integridad entre usuarios

- `actividad (materia_id, usuario_id)` referencia `materia (id, usuario_id)`: una actividad no puede
  apuntar a la materia de otro usuario.
- La categoria debe ser del sistema o del mismo usuario; lo valida el trigger
  `actividad_categoria_del_usuario`, porque una llave foranea simple no lo distingue.

## Valores de dominio elegidos (confirmar con el equipo)

La propuesta nombra los CHECK sin listar valores. Se eligieron estos:

| Columna | Valores |
|---|---|
| `actividad.estado` | `pendiente`, `en_progreso`, `completada`, `cancelada` |
| `actividad.modalidad` | `presencial`, `en_linea`, `mixta` |
| `actividad.prioridad` | de 1 a 5 |
| `categoria_actividad.ambito` | `academica`, `personal`, `ambas` |
| `calendario_academico.tipo` | `inicio_periodo`, `fin_periodo`, `inhabil`, `examen`, `institucional` |

Cambiarlos despues exige una migracion nueva. La baja logica de una actividad es el estado
`cancelada`; la de una materia es `activa = false`.

## Pendiente para migraciones posteriores

- `actividad_fijar_completada_en` se reemplaza con `create or replace` en la migracion de
  bitacora para sumar el registro de cambios de estado.
- Las categorias del sistema se insertan en 001. El calendario academico de 2026 no tiene seed.
