# Datos de demostracion

`seeds/demo/001_demo.sql` carga dos estudiantes ficticios para la defensa. No contiene datos reales
ni la contrasena: recibe su hash como parametro.

## Que carga

| | Ana (demo) | Luis (demo) |
|---|---|---|
| Correo | `ana.demo@kairo.mx` | `luis.demo@kairo.mx` |
| Materias | 4 (Bases de Datos en la Nube, Ciberseguridad, Fundamentos de IA, Gestion de Proyectos) | Las mismas 4 |
| Actividades | 13: 8 pasadas (completadas) y 5 proximas | 13: igual, con una lectura cancelada |
| Registros de tiempo | Sueno 7.5 h, estudio 2 h entre semana, ejercicio lunes, miercoles y viernes, meditacion los domingos | Sueno 6.5 h, estudio 1.5 h, ejercicio martes y jueves, videojuegos viernes y sabado |
| Metas | Sueno 420 min/dia, estudio 600 min/semana, ejercicio 3/semana | Sueno 420 min/dia, estudio 480 min/semana, ejercicio 2/semana |
| Capturas de IA | 4 actividades: 3 aceptadas sin correccion y 1 corregida | 4 corregidas, 1 descartada y 1 meta pendiente |

Ademas: clases de lunes a jueves, un examen, una reunion, una cita personal, la entrega del proyecto
ligada a su actividad, autoevaluaciones semanales, etiquetas, recordatorios (uno enviado y tres
pendientes en el futuro), una sesion de temporizador cerrada y las evaluaciones de metas de los
periodos ya cerrados, como las dejaria `pg_cron`.

**Fechas relativas.** La historia cubre las cuatro semanas anteriores a la actual y lo que va de esta;
lo pendiente se fecha a partir del dia de carga. Cargada cualquier dia, la demo tiene historia,
agenda proxima y recordatorios en el futuro.

**La semana pesada** (hace dos semanas) concentra 8 entregas: el estudio sube a 1 200 min por
usuario, el sueno baja de unas 49 h a 37 h, el ejercicio casi desaparece y el animo baja de 3.5 a 2.
Es lo que muestra el reporte de carga contra descanso.

## Como cargarla en Supabase

1. Elegir una contrasena para la demo (la misma para ambos usuarios) y generar su hash con la misma
   libreria y configuracion que la API (`pwdlib`, `PasswordHash.recommended()`):

   ```powershell
   py -m pip install "pwdlib[argon2]"
   py -c "from pwdlib import PasswordHash; import getpass; print(PasswordHash.recommended().hash(getpass.getpass('Contrasena de la demo: ')))"
   ```

   Imprime algo como `$argon2id$v=19$m=65536,t=3,p=4$...`. La contrasena se comparte con el equipo
   solo por un canal privado; ni ella ni el hash van en el repositorio.

2. Cargar con `psql` como `postgres` (Session pooler), pasando el hash entre comillas simples:

   ```powershell
   psql "postgresql://postgres.uqiozvdagfouwzsbggla@<host>:5432/postgres?sslmode=require" -v hash_demo='<hash>' -f seeds/demo/001_demo.sql
   ```

   Debe terminar con `NOTICE: Demo cargada: ...`. Si los usuarios ya existen, no cambia nada.

## Guion sugerido para la defensa

1. **Iniciar sesion como Ana.** La agenda muestra la entrega del proyecto, el examen final, la
   reunion y la cita, cada una con su `tipo`.
2. **Progreso de metas.** Tres metas con su avance del periodo actual.
3. **Carga contra descanso.** La semana pesada contra las demas.
4. **Aislamiento.** Iniciar sesion como Luis: no aparece nada de Ana. La misma consulta con otro
   usuario devuelve otros datos porque la RLS filtra en la base, no en la API.
5. **Reporte agregado** (rol `kairo_lectura`): `vl_cruce_carga_descanso` y `vl_desempeno_pipeline`
   muestran totales de ambos usuarios sin identificar a ninguno.

El bot de Telegram no queda vinculado: para mostrarlo, vincular una cuenta con el codigo de la app.

## Pruebas

`tests/views/018_seed_demo.sql` carga la demo dos veces dentro de una transaccion y comprueba:
- que no se duplica;
- que no quedan recordatorios pendientes en el pasado ni registros que terminen en el futuro;
- el aislamiento entre Ana y Luis;
- el contenido de la agenda, las metas, la semana pesada y el pipeline, por usuario y agregados.
