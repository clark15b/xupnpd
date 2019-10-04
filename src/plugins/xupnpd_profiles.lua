function profile_change(user_agent,req)
    if not user_agent or user_agent=='' then return end

    for name,profile in pairs(profiles) do
        local match=profile.match

        if profile.disabled~=true and  match and match(user_agent,req) then

            local options=profile.options
            local mtypes=profile.mime_types

            if options then for i,j in pairs(options) do cfg[i]=j end end

            if mtypes then
                if profile.replace_mime_types==true then
                    mime=mtypes
                else
                    for i,j in pairs(mtypes) do mime[i]=j end
                end
            end
            plugins.profiles.current = name			
            return
        end
    end
    plugins.profiles.current = nil
end

local this = {
	disabled = false,
	name = 'profiles',
	desc = 'enables per-user-agent response customizations',
	apply_config = function()
		load_plugins(cfg.profiles or "./profiles/",'profile')
	end,
	http_handler = function(what,from,port,msg)
		profile_change(msg['user-agent'], msg)
	end,
	sendurl = function(url,range) end,
	ui_config_vars = {
		{ "input",  "profiles" }
	},
	ui_actions = {
		profiles_ui = { 'xupnpd - profiles ui action', function() end }        -- 'http://127.0.0.1:4044/ui/profiles_ui' for call
	},
	ui_vars = {}	-- use whatever ${key} in UI HTML templates
}

plugins[this.name] = this
