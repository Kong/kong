local prefix_handler = require "kong.cmd.utils.prefix_handler"
local nginx_signals = require "kong.cmd.utils.nginx_signals"
local conf_loader = require "kong.conf_loader"
local pl_path = require "pl.path"
local pl_file = require "pl.file"
local log = require "kong.cmd.utils.log"

local function execute(args)
  log.disable()
  -- retrieve prefix or use given one
  local new_config = assert(conf_loader(args.conf, {
    prefix = args.prefix
  }))
  log.enable()
  assert(pl_path.exists(new_config.prefix),
         "no such prefix: " .. new_config.prefix)

  -- write a combined config file
  if args.conf and pl_path.exists(args.conf) then
    local kong_env = assert(pl_file.read(args.conf))
    if pl_path.exists(new_config.kong_env) then
      kong_env = assert(pl_file.read(new_config.kong_env)) .. "\n" .. kong_env
    end

    assert(prefix_handler.write_env_file(new_config.kong_env, kong_env))
  end

  local conf = assert(conf_loader(new_config.kong_env, {
    prefix = args.prefix
  }))

  if not new_config.declarative_config then
    conf.declarative_config = nil
  end

  assert(prefix_handler.prepare_prefix(conf, args.nginx_conf, nil, true))
  assert(nginx_signals.reload(conf))

  log("Kong reloaded")
end

local lapp = [[
Usage: kong reload [OPTIONS]

Reload a Kong node (and start other configured services
if necessary) in given prefix directory.

This command sends a HUP signal to Nginx, which will spawn
new workers (taking configuration changes into account),
and stop the old ones when they have finished processing
current requests.

Options:
 -c,--conf        (optional string) configuration file
 -p,--prefix      (optional string) prefix Kong is running at
 --nginx-conf     (optional string) custom Nginx configuration template
]]

return {
  lapp = lapp,
  execute = execute
}
