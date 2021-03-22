local cjson = require "cjson.safe"
local pl_path = require "pl.path"
local raw_log = require "ngx.errlog".raw_log
local msgpack = require "MessagePack"

local _, ngx_pipe = pcall(require, "ngx.pipe")


local kong = kong
local ngx_INFO = ngx.INFO
local cjson_decode = cjson.decode

local proc_mgmt = {}

local _servers
local _plugin_infos

--[[

Configuration

We require three settings to communicate with each pluginserver.  To make it
fit in the config structure, use a dynamic namespace and generous defaults.

- pluginserver_names: a list of names, one for each pluginserver.

- pluginserver_XXX_socket: unix socket to communicate with the pluginserver.
- pluginserver_XXX_start_cmd: command line to strat the pluginserver.
- pluginserver_XXX_query_cmd: command line to query the pluginserver.

Note: the `_start_cmd` and `_query_cmd` are set to the defaults only if
they exist on the filesystem.  If omitted and the default doesn't exist,
they're disabled.

A disabled `_start_cmd` (unset and the default doesn't exist in the filesystem)
means this process isn't managed by Kong.  It's expected that the socket
still works, supposedly handled by an externally-managed process.

A disable `_query_cmd` means it won't be queried and so the corresponding
socket wouldn't be used, even if the process is managed (if the `_start_cmd`
is valid).  Currently this has no use, but it could eventually be added via
other means, perhaps dynamically.

--]]

local function ifexists(path)
  if pl_path.exists(path) then
    return path
  end
end


local function get_server_defs()
  local config = kong.configuration

  if not _servers then
    _servers = {}

    if config.pluginserver_names then
      for i, name in ipairs(config.pluginserver_names) do
        kong.log.debug("search config for pluginserver named: ", name)
        local env_prefix = "pluginserver_" .. name:gsub("-", "_")
        _servers[i] = {
          name = name,
          socket = config[env_prefix .. "_socket"] or "/usr/local/kong/" .. name .. ".socket",
          start_command = config[env_prefix .. "_start_cmd"] or ifexists("/usr/local/bin/"..name),
          query_command = config[env_prefix .. "_query_cmd"] or ifexists("/usr/local/bin/query_"..name),
        }
      end

    elseif config.go_plugins_dir ~= "off" then
      kong.log.info("old go_pluginserver style")
      _servers[1] = {
        name = "go-pluginserver",
        socket = config.prefix .. "/go_pluginserver.sock",
        start_command = ("%s -kong-prefix %q -plugins-directory %q"):format(
            config.go_pluginserver_exe, config.prefix, config.go_plugins_dir),
        info_command = ("%s -plugins-directory %q -dump-plugin-info %%q"):format(
            config.go_pluginserver_exe, config.go_plugins_dir),
      }
    end
  end

  return _servers
end

proc_mgmt.get_server_defs = get_server_defs

--[[

Plugin info requests

Disclaimer:  The best way to do it is to have "ListPlugins()" and "GetInfo(plugin)"
RPC methods; but Kong would like to have all the plugin schemas at initialization time,
before full cosocket is available.  At one time, we used blocking I/O to do RPC at
non-yielding phases, but was considered dangerous.  The alternative is to use
`io.popen(cmd)` to ask fot that info.

The pluginserver_XXX_query_cmd contains a string to be executed as a command line.
The output should be a JSON string that decodes as an array of objects, each
defining the name, priority, version,  schema and phases of one plugin.

    [{
      "name": ... ,
      "priority": ... ,
      "version": ... ,
      "schema": ... ,
      "phases": [ phase_names ... ],
    },
    {
      ...
    },
    ...
    ]

This array should describe all plugins currently available through this server,
no matter if actually enabled in Kong's configuration or not.

--]]


local function register_plugin_info(server_def, plugin_info)
  if _plugin_infos[plugin_info.Name] then
    kong.log.err(string.format("Duplicate plugin name [%s] by %s and %s",
      plugin_info.Name, _plugin_infos[plugin_info.Name].server_def.name, server_def.name))
    return
  end

  _plugin_infos[plugin_info.Name] = {
    server_def = server_def,
    --rpc = server_def.rpc,
    name = plugin_info.Name,
    PRIORITY = plugin_info.Priority,
    VERSION = plugin_info.Version,
    schema = plugin_info.Schema,
    phases = plugin_info.Phases,
  }
end

local function ask_info(server_def)
  if not server_def.query_command then
    kong.log.info(string.format("No info query for %s", server_def.name))
    return
  end

  local fd, err = io.popen(server_def.query_command)
  if not fd then
    local msg = string.format("loading plugins info from [%s]:\n", server_def.name)
    kong.log.err(msg, err)
    return
  end

  local infos_dump = fd:read("*a")
  fd:close()
  local infos = cjson_decode(infos_dump)
  if type(infos) ~= "table" then
    error(string.format("Not a plugin info table: \n%s\n%s",
      server_def.query_command, infos_dump))
    return
  end

  for _, plugin_info in ipairs(infos) do
    register_plugin_info(server_def, plugin_info)
  end
end

local function ask_info_plugin(server_def, plugin_name)
  if not server_def.info_command then
    return
  end

  local fd, err = io.popen(server_def.info_command:format(plugin_name))
  if not fd then
    local msg = string.format("asking [%s] info of [%s", server_def.name, plugin_name)
    kong.log.err(msg, err)
    return
  end

  local info_dump = fd:read("*a")
  fd:close()
  local info = assert(msgpack.unpack(info_dump))
  register_plugin_info(server_def, info)
end

function proc_mgmt.get_plugin_info(plugin_name)
  if not _plugin_infos then
    _plugin_infos = {}

    for _, server_def in ipairs(get_server_defs()) do
      ask_info(server_def)
    end
  end

  if not _plugin_infos[plugin_name] then
    for _, server_def in ipairs(get_server_defs()) do
      ask_info_plugin(server_def, plugin_name)
    end
  end

  return _plugin_infos[plugin_name]
end


--[[

Process management

Pluginservers with a corresponding `pluginserver_XXX_start_cmd` field are managed
by Kong.  Stdout and stderr are joined and logged, if it dies, Kong logs the
event and respawns the server.

If the `_start_cmd` is unset (and the default doesn't exist in the filesystem)
it's assumed the process is managed externally.

--]]

local function grab_logs(proc, name)
  local prefix = string.format("[%s:%d] ", name, proc:pid())

  while true do
    local data, err, partial = proc:stdout_read_line()
    local line = data or partial
    if line and line ~= "" then
      raw_log(ngx_INFO, prefix .. line)
    end

    if not data and err == "closed" then
      return
    end
  end
end

function proc_mgmt.pluginserver_timer(premature, server_def)
  if premature then
    return
  end

  if ngx.config.subsystem ~= "http" then
    return
  end

  while not ngx.worker.exiting() do
    kong.log.notice("Starting " .. server_def.name or "")
    server_def.proc = assert(ngx_pipe.spawn("exec " .. server_def.start_command, {
      merge_stderr = true,
    }))
    server_def.proc:set_timeouts(nil, nil, nil, 0)     -- block until something actually happens

    while true do
      grab_logs(server_def.proc, server_def.name)
      local ok, reason, status = server_def.proc:wait()
      if ok ~= nil or reason == "exited" then
        kong.log.notice("external pluginserver '", server_def.name, "' terminated: ", tostring(reason), " ", tostring(status))
        break
      end
    end
  end
  kong.log.notice("Exiting: pluginserver '", server_def.name, "' not respawned.")
end



return proc_mgmt
