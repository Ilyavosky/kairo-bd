-- Calendario academico del periodo septiembre-diciembre 2026 (periodo '2026-3').
-- Idempotente: on conflict do nothing sobre (periodo, tipo, fecha).
-- Pendiente: las fechas oficiales de la UPCH (inicio y fin del cuatrimestre, evaluaciones y
-- vacaciones) no estaban publicadas al escribir el seed; por ahora solo van los descansos
-- obligatorios del articulo 74 de la Ley Federal del Trabajo que caen en el periodo.
insert into calendario_academico (periodo, tipo, fecha, fecha_fin, descripcion) values
('2026-3', 'inhabil', date '2026-09-16', null, 'Dia de la Independencia'),
('2026-3', 'inhabil', date '2026-11-16', null, 'Conmemoracion del 20 de noviembre'),
('2026-3', 'inhabil', date '2026-12-25', null, 'Navidad')
on conflict (periodo, tipo, fecha) do nothing;
