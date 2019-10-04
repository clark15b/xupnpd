for n,plugin in pairs(plugins) do
	if plugin.apply_config and not plugin.disabled then
		plugin.apply_config()
	end
end