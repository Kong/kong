local nginx_signals = require "kong.cmd.utils.nginx_signals"
local conf_loader = require "kong.conf_loader"
local pl_path = require "pl.path"
local log = require "kong.cmd.utils.log"

local function execute(args, opts)
  opts = opts or {}

  log.disable()
  -- only to retrieve the default prefix or use given one
  local default_conf = assert(conf_loader(nil, {
    prefix = args.prefix
  }))
  log.enable()
  assert(pl_path.exists(default_conf.prefix),
         "no such prefix: " .. default_conf.prefix)

  if opts.quiet then
    log.disable()
  end

  -- load <PREFIX>/kong.conf containing running node's config
  local conf = assert(conf_loader(default_conf.kong_env))
  assert(nginx_signals.stop(conf))

  if opts.quiet then
    log.enable()
  end

  log("Kong stopped")
end

local lapp = [[
Usage: kong stop [OPTIONS]

Stop a running Kong node (Nginx and other configured services) in given
prefix directory.

This command sends a SIGTERM signal to Nginx.

Options:
 -p,--prefix      (optional string) prefix Kong is running at
]]

return {
  lapp = lapp,
  execute = execute
}
