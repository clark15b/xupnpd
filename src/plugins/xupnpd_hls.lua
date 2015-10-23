-- Copyright (C) 2011-2013 Anton Burdinuk
-- clark15b@gmail.com
-- https://tsdemuxer.googlecode.com/svn/trunk/xupnpd

function hls_sendurl(url,range)

    while true do
        local pls_data=plugin_download(url)

        if not pls_data then break

        local pls=m3u.parse(pls_data)

        if not pls or pls.size<1 then break

        for n,location in ipairs(pls.elements) do

            for i=1,5,1 do
                rc,location=http.sendurl(location,1)

                if not location then
                    break
                else
                    if cfg.debug>0 then print('Redirect #'..i..' to: '..location) end
                end
            end
        end
    end

end

plugins['hls']={}
plugins.hls.name="HTTP Live Streaming"
plugins.hls.desc="<i>m3u_url</i>"
plugins.hls.sendurl=hls_sendurl
