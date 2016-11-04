local prefix_handler = require "kong.cmd.utils.prefix_handler"
local conf_loader = require "kong.conf_loader"

local function execute(args)
  local conf = assert(conf_loader(args.conf))
  local kong_nginx_conf = assert(prefix_handler.compile_kong_conf(conf))
  print(kong_nginx_conf)
end

local lapp = [[
Usage: kong compile [OPTIONS]

Compile the Nginx configuration file containing Kong's servers
contexts from a given Kong configuration file.

Example usage:
 kong compile -c kong.conf > /usr/local/openresty/nginx-kong.conf

 This file can then be included in an OpenResty configuration:

 http {
     # ...
     include 'nginx-kong.conf';
 }

Note:
 Third-party services such as Serf need to be properly configured
 and started for Kong to be fully compatible while embedded.

Options:
 -c,--conf (optional string) configuration file
]]

return {
  lapp = lapp,
  execute = execute
}
