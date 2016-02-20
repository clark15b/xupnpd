function ui_api_v_2_call(args)

    res = nil
	
    if args.action=='status' then
        res = json.encode(http_vars)
    end
    if res then
        http_send_headers(200,'json')
		http.send(res)
    else
        http_send_headers(404)
    end
end
