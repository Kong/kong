local nginx_signals = require "kong.cmd.utils.nginx_signals"
local conf_loader = require "kong.conf_loader"
local pl_path = require "pl.path"
local kill = require "kong.cmd.utils.kill"
local log = require "kong.cmd.utils.log"

local function execute(args)
  log.disable()
  -- retrieve default prefix or use given one
  local default_conf = assert(conf_loader(nil, {
    prefix = args.prefix
  }))
  log.enable()
  assert(pl_path.exists(default_conf.prefix),
         "no such prefix: " .. default_conf.prefix)

  -- load <PREFIX>/kong.conf containing running node's config
  local conf = assert(conf_loader(default_conf.kong_env))

  -- wait before initiating the shutdown
  ngx.update_time()
  local twait = ngx.now() + math.max(args.wait, 0)
  if twait > ngx.now() then
    log.verbose("waiting %s seconds before quitting", args.wait)
    while twait > ngx.now() do
      ngx.sleep(0.2)
      if not kill.is_running(conf.nginx_pid) then
        log.error("Kong stopped while waiting (unexpected)")
        return
      end
    end
    ngx.update_time()
  end

  -- try graceful shutdown (QUIT)
  assert(nginx_signals.quit(conf))

  log.verbose("waiting for nginx to finish processing requests")

  local tstart = ngx.now()
  local texp, running = tstart + math.max(args.timeout, 1) -- min 1s timeout
  repeat
    ngx.sleep(0.2)
    running = kill.is_running(conf.nginx_pid)
    ngx.update_time()
  until not running or ngx.now() >= texp

  if running then
    log.verbose("nginx is still running at %s, forcing shutdown", conf.prefix)
    assert(nginx_signals.stop(conf))
    log("Timeout, Kong stopped forcefully")
    return
  end

  log("Kong stopped (gracefully)")
end

local lapp = [[
Usage: kong quit [OPTIONS]

Gracefully quit a running Kong node (Nginx and other
configured services) in given prefix directory.

This command sends a SIGQUIT signal to Nginx, meaning all
requests will finish processing before shutting down.
If the timeout delay is reached, the node will be forcefully
stopped (SIGTERM).

Options:
 -p,--prefix      (optional string) prefix Kong is running at
 -t,--timeout     (default 10) timeout before forced shutdown
 -w,--wait        (default 0) wait time before initiating the shutdown
]]

return {
  lapp = lapp,
  execute = execute
}
