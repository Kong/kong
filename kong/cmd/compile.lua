local nginx_conf_compiler = require "kong.cmd.utils.nginx_conf_compiler"
local conf_loader = require "kong.conf_loader"

local function execute(args)
  local conf = assert(conf_loader(args.conf))
  local kong_nginx_conf = assert(nginx_conf_compiler.compile_kong_conf(conf))
  print(kong_nginx_conf)
end

local lapp = [[
Usage: kong compile [OPTIONS]

Options:
 -c,--conf (optional string) configuration file
]]

return {
  lapp = lapp,
  execute = execute
}
