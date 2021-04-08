table.pack = table.pack or function(...) return { n = select("#", ...), ... } end  -- support Lua 5.1
table.unpack = table.unpack or function(t) return unpack(t) end  -- support Lua 5.1

function recent_shell(cmd, ...)  -- space/apostrophe/ampersand-safe replacement of os.execute(cmd)
  local args = table.pack(...)
  local h = io.popen("xargs -t0n " .. (3 + args.n) .. " sh", 'w')
  if h then
    h:write("-c\0")
    h:write(cmd .. "\0")
    h:write("recent_shell\0") -- $0 for sh
    for i = 1, args.n do
      h:write(tostring(args[i] or "nil") .. "\0")
    end
    h:close()
  end
end

function recent_popen_next(pipe, bytes)
  while bytes do
    local start, stop, name = string.find(bytes, "([^%z]*)%z")
    if name then
      return name, bytes:sub(stop + 1)
    end
    local more = pipe:read(1024)
    if not more then
      return #bytes > 0 and bytes or nil
    end
    bytes = bytes .. more
  end
end

function recent_popen(cmd, ...)
  local args = {...}
  local pipe_path = os.tmpname()
  recent_shell('rm -f "$1" && mkfifo "$1"', pipe_path) -- rm since above creates file :-(
  local pipe = io.popen('cat "'.. pipe_path .. '"', 'r') -- both io.open(pipe_path, 'r') & io.open(pipe_path, 'a') block
  if pipe then
    local task = coroutine.create(recent_shell)
    table.insert(args, pipe_path)
    if coroutine.resume(task, cmd .. string.format(' > "$%d" ; rm -f "$%d"', #args, #args), table.unpack(args)) then
      local bytes = ""
      return function()
        local name = nil
        name, bytes = recent_popen_next(pipe, bytes)
        if not bytes then
          pipe:close()
        end
        return name
      end
    else
      recent_invoke("Removed", os.remove, pipe_path)
    end
    pipe:close()
  end
  return function() end
end

function recent_invoke(when_done, f, ...)
  local status, msg = f(...)
  if cfg.debug>0 or msg then print(status and (when_done .. " " .. table.concat({...}, " ")) or msg) end
end

function recent_unique_name(pls) -- do not assume globally-unique pls.name (S02E03 -> SerieName-S02-S02E03)
  for i, t in ipairs(playlist) do
    if pls.path:sub(1, #t[1]) == t[1] then
      local name, count = pls.path:sub(#t[1] + 1):gsub("^[.]?/+" , "", 1):gsub("/+", "-")
      if t[2] == plugins.recent.name then -- caller will provide new index prefix
        name, count = name:gsub("^%d+-", "")
      end
      return name
    end
  end
  return pls.name .. "." .. pls.type
end

function recent_keep_only_remaining(count, name)
  if count <= 0 then
    recent_invoke("Removed", os.remove, name)
  elseif cfg.debug>0 then
    print("Retaining " .. name)
  end
end

function recent_rename_with(index, width, path)
  local dir, name = path:match("^(.*/)%d+-([^/]+)$") -- using minus separator as it sorts before any digit, zero-prefixed to make string sort same as number
  recent_invoke("Renamed", os.rename, path, string.format("%s%0" .. width .. "d-%s", dir, index, name))
end

function recent_manage_symlinks(pls, recent) -- recent is NOT /-terminated
  recent_shell('exec mkdir -p "$1"', recent) -- searching for broken links since busybox' find has no -lname switch
  recent_shell('F="$(readlink -f "$1")" && mv $4 "$F" "$F.moved" && find -L "$2" -maxdepth 1 -type l -exec rm $4 -f {} "+" ; ' ..
    'mv $4 "$F.moved" "$F" ; ln $4 -fs "$F" "$2/0-$3"', pls.path, recent, recent_unique_name(pls), cfg.debug>0 and "-v" or "") -- keep single existing link to pls.path
  local remaining = recent_count()
  for name in recent_popen('find "$1" -type l -print0 | LC_ALL=C sort -z', recent) do
    recent_keep_only_remaining(remaining, name)
    remaining = remaining - 1
  end
  local index, width = 1, #("" .. recent_count()) + 1
  for name in recent_popen('find "$1" -type l -print0 | LC_ALL=C sort -z', recent) do
    recent_rename_with(index, width, name)
    index = index + 1
  end
end

function recent_playlist_exists(from)
  for i, pls in ipairs(playlist) do
    if #pls > 2 and pls[2] == plugins.recent.name and pls[3] == from then
      return pls
    end
  end
end

function recent_path()  -- always /-terminated
  return cfg.recent_path and #cfg.recent_path > 0 and string.gsub(cfg.recent_path, "([^/])$", "%1/", 1) or "./recent/"
end

function recent_count()
  return cfg.recent_count and tonumber(cfg.recent_count) and tonumber(cfg.recent_count) > 0 and cfg.recent_count or 5
end

function recent_force_sort_files(recent_dir)
  local f = io.open(cfg.config_path .. "recent.lua", 'w')
  if f then
    f:write('cfg.sort_files = true\ncfg.recent_path_old = "' .. recent_dir .. '"\nprint("Forcing sort_file = true")\n')
    f:close()
    core.sendevent("config")
  end
end

function recent_apply_config()
  local dir = recent_path()
  local sendevents = nil
  if cfg.recent_path_old and dir ~= cfg.recent_path_old then
    recent_shell('exec mv $3 "$1"* "$2"', cfg.recent_path_old, dir, cfg.debug>0 and "-v" or "")
    recent_shell('exec rmdir "$1"', cfg.recent_path_old)
    sendevents = function() core.sendevent("reload") end
  end
  for i, from in ipairs(dir and util.dir(dir) or {}) do
    local recent = recent_playlist_exists(from)
    if not recent then
      recent = { dir .. from, plugins.recent.name, from }
      playlist[#playlist + 1] = recent -- not enough as we're in forked child process
      sendevents = sendevents or {}
      table.insert(sendevents, function() core.sendevent("update_playlist", dir .. from, dir .. from, plugins.recent.name, from) end)
    elseif recent[1] ~= (dir .. from) then
      local old = recent[1]
      recent[1] = dir .. from
      sendevents = sendevents or {}
      table.insert(sendevents, function() core.sendevent("update_playlist", dir .. from, old, plugins.recent.name, from) end)
    end
  end
  sendevents = type(sendevents) == "function" and {sendevents} or sendevents or {}
  if not cfg.sort_files or (cfg.recent_path_old and dir ~= cfg.recent_path_old) then
    table.insert(sendevents, function() recent_force_sort_files(dir) end)
  end
  cfg.recent_path_old = dir
  for i, sendevent in ipairs(sendevents) do
    sendevent()
  end
end

function recent_http_handler(what, from, port, msg)
  from = string.match(from,'^[.%d]+')
  local f = util.geturlinfo(cfg.www_root, msg.reqline[2])
  if f and f.url then
    local url, object = http_get_action(f.url)
    local pls = url == "stream" and find_playlist_object(object)
    if pls and pls.path then
      local recent = recent_playlist_exists(from)
      local dir = recent_path() .. from
      local sendevent = function() core.sendevent("reload") end
      if not recent then
        recent = { dir, plugins.recent.name, from }
        table.insert(playlist, recent) -- not enough as we're in forked child process
        sendevent = function() core.sendevent("update_playlist", dir, dir, plugins.recent.name, from) end
      elseif recent[1] ~= dir then
        sendevent = function() core.sendevent("update_playlist", dir, table.unpack(recent)) end
        recent[1] = dir
      end
      recent_manage_symlinks(pls, recent[1])
      if pls.path:sub(1, #dir) == dir then
        dir = util.dir(recent[1])
        table.sort(dir, function(a,b) return string.lower(a) < string.lower(b) end)
        for i, f in ipairs(dir) do
          pls.parent.elements[i].path = recent[1] .. "/" .. f
        end
        local req = msg.reqline[2]:gsub("_%d([.]%w+)$", "_1%1", 1)
        if cfg.debug>0 then print("Replacing " .. msg.reqline[2] .. " with " .. req) end
        msg.reqline[2] = req
      end
      sendevent() -- symlink changes are reason why this is invoked unconditionally
    end
  end
end

plugins['recent']={}
plugins.recent.disabled=false
plugins.recent.name="Recent"
plugins.recent.desc="enables per-host viewing history"
plugins.recent.apply_config=recent_apply_config
plugins.recent.http_handler=recent_http_handler
plugins.recent.sendurl=function() end

plugins.recent.ui_config_vars=
{
    { "input",  "recent_path" },
    { "input",  "recent_count", "int" }
}

plugins.recent.ui_actions=
{
    recent_ui={ 'xupnpd - recent ui action', function() end }       -- 'http://127.0.0.1:4044/ui/recent_ui' for call
}

plugins.recent.ui_vars={}                                             -- use whatever ${key} in UI HTML templates

cfg.sort_files = true -- recent_apply_config is called only after change