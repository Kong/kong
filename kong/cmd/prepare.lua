-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local prefix_handler = require "kong.cmd.utils.prefix_handler"
local conf_loader    = require "kong.conf_loader"


local function execute(args)
  local conf = assert(conf_loader(args.conf, {
    prefix = args.prefix
  }))

  local ok, err = prefix_handler.prepare_prefix(conf, args.nginx_conf)
  if not ok then
    error("could not prepare Kong prefix at " .. conf.prefix .. ": " .. err)
  end
end


local lapp = [[
Usage: kong prepare [OPTIONS]

Prepare the Kong prefix in the configured prefix directory. This command can
be used to start Kong from the nginx binary without using the 'kong start'
command.

Example usage:
 kong migrations up
 kong prepare -p /usr/local/kong -c kong.conf
 nginx -p /usr/local/kong -c /usr/local/kong/nginx.conf

Options:
 -c,--conf       (optional string) configuration file
 -p,--prefix     (optional string) override prefix directory
 --nginx-conf    (optional string) custom Nginx configuration template
]]


return {
  lapp    = lapp,
  execute = execute,
}
