begin;

\ir ../../seeds/catalog/001_calendario_academico_2026.sql
\ir ../../seeds/catalog/001_calendario_academico_2026.sql

do $$
begin
    assert (
        select count(*) from calendario_academico where periodo = '2026-3'
    ) = 3, 'el seed del calendario es idempotente: tres fechas tras dos ejecuciones';
    assert exists (
        select 1 from calendario_academico
        where periodo = '2026-3' and tipo = 'inhabil' and fecha = date '2026-11-16'
    ), 'el lunes 16 de noviembre es inhabil';
end
$$;

rollback;
