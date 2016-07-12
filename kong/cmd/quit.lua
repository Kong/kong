local dnsmasq_signals = require "kong.cmd.utils.dnsmasq_signals"
local nginx_signals = require "kong.cmd.utils.nginx_signals"
local serf_signals = require "kong.cmd.utils.serf_signals"
local conf_loader = require "kong.conf_loader"
local DAOFactory = require "kong.dao.factory"
local pl_path = require "pl.path"
local kill = require "kong.cmd.utils.kill"
local log = require "kong.cmd.utils.log"

local function execute(args)
  -- retrieve default prefix or use given one
  local default_conf = assert(conf_loader(nil, {
    prefix = args.prefix
  }))
  assert(pl_path.exists(default_conf.prefix),
         "no such prefix: "..default_conf.prefix)

  -- load <PREFIX>/kong.conf containing running node's config
  local conf = assert(conf_loader(default_conf.kong_conf))

  -- try graceful shutdown (QUIT)
  assert(nginx_signals.quit(conf))

  log.verbose("waiting for Nginx to finish processing requests...")

  local tstart = ngx.time()
  local texp, running = tstart + math.max(args.timeout, 1) -- min 1s timeout
  repeat
    ngx.sleep(0.2)
    running = kill.is_running(conf.nginx_pid)
  until not running or ngx.time() >= texp

  if running then
    log.verbose("Nginx is still running at %s, forcing shutdown", conf.prefix)
    assert(nginx_signals.stop(conf))
  end

  assert(serf_signals.stop(conf, DAOFactory(conf)))

  if conf.dnsmasq then
    assert(dnsmasq_signals.stop(conf))
  end

  log("Stopped (gracefully)")
end

local lapp = [[
Usage: kong quit [OPTIONS]

Options:
 -p,--prefix  (optional string) prefix Kong is running at
 -t,--timeout (default 10) timeout before forced shutdown
]]

return {
  lapp = lapp,
  execute = execute
}
