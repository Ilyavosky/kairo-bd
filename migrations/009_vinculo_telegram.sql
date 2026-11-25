create table vinculo_telegram (
    id uuid primary key default gen_random_uuid(),
    usuario_id uuid not null references usuario (id),
    codigo_hash text not null,
    expira_en timestamptz not null,
    usado_en timestamptz,
    creado_en timestamptz not null default now(),
    constraint vinculo_codigo_unico unique (codigo_hash),
    constraint vinculo_expiracion_valida check (expira_en > creado_en)
);

create index vinculo_usuario_creado_idx on vinculo_telegram (usuario_id, creado_en desc);

comment on table vinculo_telegram is
'Codigos de un solo uso y corta duracion para vincular el Telegram de un usuario.';
comment on column vinculo_telegram.usuario_id is 'Usuario que genero el codigo.';
comment on column vinculo_telegram.codigo_hash is
'SHA-256 del codigo; el codigo en claro nunca se guarda.';
comment on column vinculo_telegram.expira_en is 'Momento a partir del cual el codigo ya no sirve.';
comment on column vinculo_telegram.usado_en is
'Momento en que se canjeo; nulo si sigue disponible.';
comment on column vinculo_telegram.creado_en is 'Momento de creacion.';

create function kairo_vincular_telegram(p_codigo_hash text, p_telegram_id bigint)
returns uuid
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
    v_usuario uuid;
begin
    begin
        update vinculo_telegram
        set usado_en = now()
        where codigo_hash = p_codigo_hash and usado_en is null and expira_en > now()
        returning usuario_id into v_usuario;

        if v_usuario is null then
            return null;
        end if;

        update usuario set telegram_id = p_telegram_id where id = v_usuario;
        return v_usuario;
    exception when unique_violation then
        return null;
    end;
end
$$;

create function kairo_usuario_por_telegram(p_telegram_id bigint) returns uuid
language sql stable security definer set search_path = public, pg_temp
as $$
    select u.id from usuario as u where u.telegram_id = p_telegram_id and u.activo
$$;

comment on function kairo_vincular_telegram(text, bigint) is
'Canjea un codigo vigente y fija el telegram_id.
Si ese Telegram ya es de otra cuenta, no consume el codigo.';
comment on function kairo_usuario_por_telegram(bigint) is
'Resuelve el usuario de un mensaje del bot antes de que exista sesion; evita una politica abierta.';

revoke update (telegram_id) on usuario from kairo_app;

revoke all on function kairo_vincular_telegram(text, bigint) from public;
revoke all on function kairo_usuario_por_telegram(bigint) from public;
grant execute on function kairo_vincular_telegram(text, bigint) to kairo_app;
grant execute on function kairo_usuario_por_telegram(bigint) to kairo_app;

alter table vinculo_telegram enable row level security;

create policy vinculo_select_propio on vinculo_telegram for select to kairo_app
using (usuario_id = app_usuario_id());

create policy vinculo_insert_propio on vinculo_telegram for insert to kairo_app
with check (usuario_id = app_usuario_id());

grant select on vinculo_telegram to kairo_app;
grant insert (usuario_id, codigo_hash, expira_en) on vinculo_telegram to kairo_app;
