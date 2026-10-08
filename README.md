# kairo-bd

Base de datos de Kairo (PostgreSQL en Supabase): migraciones, seeds, pruebas SQL y documentación del esquema.

## Reglas de las migraciones

- Nombre: `NNN_descripcion_en_snake_case.sql`, con tres dígitos consecutivos. Ejemplo: `001_crear_usuario.sql`.
- Solo hacia adelante: no hay rollbacks. Un cambio posterior es una migración nueva.
- Una migración ya mergeada nunca se edita.
- Toda tabla nueva lleva RLS habilitado, sus políticas, los `GRANT` por rol y `COMMENT` en tabla y columnas.
- Las reglas de integridad viven en la base: `NOT NULL`, `CHECK`, `UNIQUE` y claves foráneas. Las fechas son `timestamptz`.
- Nadie cambia el esquema a mano en Supabase; todo entra por migración.

## CI

El workflow `CI` (job `migraciones`) corre en cada pull request y en cada push a `main`:

1. Levanta un Postgres 17 desechable, siempre desde cero.
2. Revisa las migraciones con `sqlfluff`.
3. Aplica `migrations/*.sql` en orden con `psql`.
4. Ejecuta las pruebas de `tests/**/*.sql`.


## Probar en local

```
docker run --rm -d --name kairo-pg -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=kairo_test -p 5432:5432 postgres:17
for f in migrations/*.sql; do psql postgresql://postgres:postgres@localhost:5432/kairo_test -v ON_ERROR_STOP=1 -f "$f"; done
```

## Flujo de trabajo

Ramas de feature desde `develop`, commits convencionales, un PR pequeño por issue enlazado con `Closes #n`.
