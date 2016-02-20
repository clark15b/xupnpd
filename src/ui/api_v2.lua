function ui_api_v_2_call(args)

    res = nil
    http_send_headers(200,'txt')

    if args.action=='status' then
        res = json.encode(http_vars)
    end
    if not res then
        http_send_headers(200,'json')
    else
        http_send_headers(404)
    end
end
