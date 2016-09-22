local log = require "kong.cmd.utils.log"
local kill = require "kong.cmd.utils.kill"
local pl_path = require "pl.path"
local pl_tablex = require "pl.tablex"
local pl_stringx = require "pl.stringx"
local conf_loader = require "kong.conf_loader"

local function execute(args)
  -- retrieve default prefix or use given one
  local default_conf = assert(conf_loader(nil, {
    prefix = args.prefix
  }))
  assert(pl_path.exists(default_conf.prefix),
         "no such prefix: "..default_conf.prefix)
  assert(pl_path.exists(default_conf.kong_conf),
         "Kong is not running at "..default_conf.prefix)

  -- load <PREFIX>/kong.conf containing running node's config
  local conf = assert(conf_loader(default_conf.kong_conf))

  local pids = {
    serf = conf.serf_pid,
    nginx = conf.nginx_pid,
    dnsmasq = conf.dnsmasq and conf.dnsmasq_pid or nil
  }

  local count = 0
  for k, v in pairs(pids) do
    local running = kill.is_running(v)
    local msg = pl_stringx.ljust(k, 12, ".")..(running and "running" or "not running")
    if running then
      count = count + 1
    end
    log(msg)
  end

  log("") -- line jump

  assert(count > 0, "Kong is not running at "..conf.prefix)
  assert(count == pl_tablex.size(pids), "some services are not running at "..conf.prefix)

  log("Kong is healthy at %s", conf.prefix)
end

local lapp = [[
Usage: kong health [OPTIONS]

Check if the necessary services are running for this node.

Options:
 -p,--prefix (optional string) prefix at which Kong should be running
]]

return {
  lapp = lapp,
  execute = execute
}
