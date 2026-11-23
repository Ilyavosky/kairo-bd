begin;

do $$
declare
    v_a uuid;
    v_b uuid;
    v_resultado uuid;
    v_telegram bigint;
begin
    v_a := kairo_registrar_usuario('a_' || gen_random_uuid() || '@prueba.mx', 'hash', 'A', 'America/Mexico_City');
    v_b := kairo_registrar_usuario('b_' || gen_random_uuid() || '@prueba.mx', 'hash', 'B', 'America/Mexico_City');

    set local role kairo_app;
    perform set_config('app.usuario_id', v_a::text, true);
    insert into vinculo_telegram (usuario_id, codigo_hash, expira_en)
    values (v_a, 'vigente', now() + interval '10 minutes');

    perform set_config('app.usuario_id', v_b::text, true);
    insert into vinculo_telegram (usuario_id, codigo_hash, expira_en)
    values (v_b, 'de-b', now() + interval '10 minutes');

    reset role;
    insert into vinculo_telegram (usuario_id, codigo_hash, expira_en, creado_en)
    values (v_a, 'vencido', now() - interval '1 minute', now() - interval '11 minutes');

    set local role kairo_app;
    perform set_config('app.usuario_id', '', true);

    assert kairo_vincular_telegram('vencido', 111) is null, 'un codigo vencido no vincula';
    assert kairo_vincular_telegram('inexistente', 111) is null, 'un codigo desconocido no vincula';

    v_resultado := kairo_vincular_telegram('vigente', 111);
    assert v_resultado = v_a, 'un codigo vigente devuelve al usuario';
    assert kairo_usuario_por_telegram(111) = v_a, 'el telegram_id queda resuelto';
    assert kairo_vincular_telegram('vigente', 222) is null, 'un codigo se usa una sola vez';

    assert kairo_vincular_telegram('de-b', 111) is null, 'un Telegram no puede estar en dos cuentas';
    reset role;
    assert (select usado_en from vinculo_telegram where codigo_hash = 'de-b') is null,
    'el codigo no se consume si el vinculo falla';
    assert (select telegram_id from usuario where id = v_b) is null, 'B sigue sin Telegram';

    set local role kairo_app;
    begin
        update usuario set telegram_id = 999 where id = v_b;
        assert false, 'kairo_app no fija telegram_id directo';
    exception when insufficient_privilege then
        null;
    end;
end
$$;

rollback;
