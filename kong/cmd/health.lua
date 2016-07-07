local conf_loader = require "kong.conf_loader"
local log = require "kong.cmd.utils.log"
local kill = require "kong.cmd.utils.kill"
local pl_stringx = require "pl.stringx"
local pl_path = require "pl.path"
local pl_tablex = require "pl.tablex"

local function is_running(pid_path)
  if not pl_path.exists(pid_path) then return nil end
  local code = kill(pid_path, "-0")
  return code == 0
end

local function execute(args)
  local default_conf = assert(conf_loader(args.conf, {
    prefix = args.prefix
  }))
  assert(pl_path.exists(default_conf.prefix),
    "no such prefix: "..default_conf.prefix)

  local pids = {
    nginx = default_conf.nginx_pid,
    serf = default_conf.serf_pid,
    dnsmasq = default_conf.dnsmasq and default_conf.dnsmasq_pid or nil
  }

  local count = 0
  for k, v in pairs(pids) do
    local running = is_running(v)
    local msg = pl_stringx.ljust(k, 10, ".")..(running and "running" or "not running")
    if running then
      count = count + 1
      log(msg)
    else
      log.warn(msg)
    end
  end
  
  assert(count > 0, "Kong is not running")
  assert(count == pl_tablex.size(pids), "Some services are not running")
end

local lapp = [[
Usage: kong health [OPTIONS]

Options:
 -c,--conf (optional string) configuration file
 --prefix  (optional string) override prefix directory
]]

return {
  lapp = lapp,
  execute = execute
}