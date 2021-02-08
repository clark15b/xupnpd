table.pack = table.pack or function(...) return { n = select("#", ...), ... } end  -- support Lua 5.1

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

function recent_unique_name(pls) -- do not assume globally-unique pls.name (S02E03 -> SerieName-S02-S02E03)
  for i, t in ipairs(playlist) do
    if pls.path:sub(1, #t[1]) == t[1] then
      local name, count = pls.path:sub(#t[1] + 1):gsub("^[.]?/+" , "", 1):gsub("/+", "-")
      return name
    end
  end
  return pls.name .. "." .. pls.type
end

function recent_keep_only_remaining(count, bytes, stop, name)
  if count <= 0 then
    os.remove(name)
  end
  return bytes and bytes:sub(stop + 1)
end

function recent_keep_only(count, bytes, pipe)
  local start, stop, name = string.find(bytes, "([^%z]*)%z")
  if name then
    return recent_keep_only_remaining(count, bytes, stop, name)
  end
  local more = pipe:read(1024)
  if more then
    bytes = bytes .. more
  elseif bytes == "" then
    return
  end
  local start, stop, name = string.find(bytes, "([^%z]*)%z")
  return recent_keep_only_remaining(count, start and bytes, stop, name or bytes)
end

function recent_manage_symlinks(pls, recent) -- recent is NOT /-terminated
  recent_shell('exec mkdir -p "$1"', recent)
  recent_shell('exec mv -v "$1" "$1.moved"', pls.path) -- searching for broken links since busybox' find has no -lname switch
  recent_shell('exec find -L "$1" -maxdepth 1 -type l -exec rm -vf {} "+"', recent)
  recent_shell('exec mv -v "$1.moved" "$1"', pls.path)                                                              -- make next line create
  recent_shell('exec ln -fsv "$(readlink -f "$1")" "$2/$(date +%s)-$3"', pls.path, recent, recent_unique_name(pls)) -- single existing link to pls.path
  local pipe_path = os.tmpname() 
  recent_shell('rm -f "$1" && mkfifo "$1"', pipe_path) -- rm since above creates file :-(
  local pipe = io.popen('cat "'.. pipe_path .. '"', 'r') -- both io.open(pipe_path, 'r') & io.open(pipe_path, 'a') block
  if pipe then
    local task = coroutine.create(recent_shell) -- skip first N, remove rest until pipe is closed
    if coroutine.resume(task, 'find "$1" -type l -print0 | sort -rz > "$2" ; rm -f "$2"', recent, pipe_path) then
      local count = recent_count()
      local bytes, remaining = "", count
      while bytes do
        bytes = recent_keep_only(remaining, bytes, pipe)
        remaining = remaining - 1
      end
      count = #("" .. count) + 1 -- using minus separator as it sorts before any digit, zero-prefixed to make string sort same as number
      recent_shell('find "$1" -type l | sort | cat -n | ( while read -r I P; do N="${P##*/}"; mv -nv "$P" "${P%/*}/$(printf "%0$2d" "$I")-${N#*-}" ; done )', recent, count)
      pipe:close()
    else
      pipe:close()
      os.remove(pipe_path)
    end
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

function recent_apply_config()
  local dir = recent_path()
  local sendevent = function(e) end
  if cfg.recent_path_old and dir ~= cfg.recent_path_old then
    recent_shell('exec mv -v "$1"* "$2"', cfg.recent_path_old, dir)
    recent_shell('exec rmdir "$1"', cfg.recent_path_old)
    sendevent = core.sendevent
  end
  cfg.recent_path_old = dir
  for i, from in ipairs(dir and util.dir(dir) or {}) do
    local recent = recent_playlist_exists(from)
    if not recent then
      recent = { dir .. from, plugins.recent.name, from }
      playlist[#playlist + 1] = recent
      sendevent = core.sendevent
    elseif recent[1] ~= (dir .. from) then
      recent[1] = dir .. from
      sendevent = core.sendevent
    end
  end
  sendevent("reload")
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
      if not recent then
        recent = { dir, plugins.recent.name, from }
        playlist[#playlist + 1] = recent
      elseif recent[1] ~= dir then
        recent[1] = dir
      end
      recent_manage_symlinks(pls, recent[1])
      core.sendevent("reload")  -- symlink changes are reason why this is invoked unconditionally
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
