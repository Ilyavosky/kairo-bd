set role kairo_owner;

alter table evento_calendario
add column tipo text not null default 'personal',
add column actividad_id uuid,
add constraint evento_tipo_valido
check (tipo in ('clase', 'examen', 'entrega', 'reunion', 'personal')),
add constraint evento_actividad_del_usuario
foreign key (actividad_id, usuario_id) references actividad (id, usuario_id);

create index evento_actividad_idx on evento_calendario (actividad_id)
where actividad_id is not null;

comment on column evento_calendario.tipo is 'clase, examen, entrega, reunion o personal.';
comment on column evento_calendario.actividad_id is
'Actividad relacionada (por ejemplo, la entrega de un proyecto); nula si no aplica.
Debe ser del mismo usuario.';

reset role;
