local log = require "kong.cmd.utils.log"
local kill = require "kong.cmd.utils.kill"
local pl_config = require "pl.config"
local pl_file = require "pl.file"
local pl_path = require "pl.path"
local pl_tablex = require "pl.tablex"
local pl_stringio = require "pl.stringio"
local pl_stringx = require "pl.stringx"
local conf_loader = require "kong.conf_loader"


local function get_kong_prefix(args)
  local prefix = args.prefix or os.getenv("KONG_PREFIX")

  if not prefix then
    local default_paths = conf_loader.get_default_paths()
    local path
    for _, default_path in ipairs(default_paths) do
      if pl_path.exists(default_path) then
        path = default_path
        break
      end
    end

    if path then
      local f = pl_file.read(path)
      assert(f, "could not load config file at " .. path)

      local s = pl_stringio.open(f)
      local conf = pl_config.read(s, {
        smart = false,
        list_delim = "_blank_" -- mandatory but we want to ignore it
      })
      s:close()
      if conf then
        prefix = conf.prefix
      end
    end
  end

  return prefix
end


local function get_node_pids(prefix)
  local pids = {}
  local prefix_paths = conf_loader.get_prefix_paths()
  local kong_env = pl_path.join(prefix, unpack(prefix_paths["kong_env"]))
  assert(pl_path.exists(kong_env), "Kong is not running at " .. prefix)

  pids["nginx"] = pl_path.join(prefix, unpack(prefix_paths["nginx_pid"]))

  return pids
end

local function execute(args)
  local prefix = get_kong_prefix(args)
  assert(prefix, "could not get Kong prefix")
  assert(pl_path.exists(prefix),
         "no such prefix: " .. prefix)

  local pids = get_node_pids(prefix)

  local count = 0
  for k, v in pairs(pids) do
    local running = kill.is_running(v)
    local msg = pl_stringx.ljust(k, 12, ".") .. (running and "running" or "not running")
    if running then
      count = count + 1
    end
    log(msg)
  end

  log("") -- line jump

  assert(count > 0, "Kong is not running at " .. prefix)
  assert(count == pl_tablex.size(pids), "some services are not running at " .. prefix)

  log("Kong is healthy at %s", prefix)
end

local lapp = [[
Usage: kong health [OPTIONS]

Check if the necessary services are running for this node.

Options:
 -p,--prefix      (optional string) prefix at which Kong should be running
]]

return {
  lapp = lapp,
  execute = execute
}
