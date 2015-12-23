#!/usr/bin/env luajit

local constants = require "kong.constants"
local cutils = require "kong.cli.utils"
local IO = require "kong.tools.io"
local yaml = require "yaml"
local args = require("lapp")(string.format([[
For development purposes only.

Duplicate an existing configuration for given environment.

Usage: kong config [options]

Options:
  -c,--config (default %s) path to configuration file
  -o,--output (default .)                  ouput
  -e,--env    (string)                     environment name
]], constants.CLI.GLOBAL_KONG_CONF))

local CONFIG_FILENAME = string.format("kong%s.yml", args.env ~= "" and "_"..args.env or "")

local config_path = cutils.get_kong_config_path(args.config)
local config_content = IO.read_file(config_path)
local default_config = yaml.load(config_content)
local env = args.env:upper()

local DEFAULT_ENV_VALUES = {
  TEST = {
    yaml = {
      ["nginx_working_dir"] = "nginx_tmp",
      ["send_anonymous_reports"] = false,
      ["proxy_port"] = 8100,
      ["proxy_ssl_port"] = 8543,
      ["admin_api_port"] = 8101,
      ["dnsmasq_port"] = 8153,
      ["databases_available"] = {
        ["cassandra"] = {
          ["keyspace"] = "kong_tests"
        }
      }
    },
    nginx = {
      ["error_log logs/error.log error"] = "error_log logs/error.log debug",
      ["lua_package_path ';;'"] = "lua_package_path './kong/?.lua;;'",
      ["access_log off"] = "access_log on"
    }
  },
  DEVELOPMENT = {
    yaml = {
      ["databases_available"] = {
        ["cassandra"] = {
          ["keyspace"] = "kong_development"
        }
      }
    },
    nginx = {
      ["nginx_working_dir: /usr/local/kong/"] = "nginx_working_dir: nginx_tmp",
      ["send_anonymous_reports: true"] = "send_anonymous_reports: false",
      ["lua_package_path ';;'"] = "lua_package_path './kong/?.lua;;'",
      ["error_log logs/error.log error"] = "error_log logs/error.log debug",
      ["lua_code_cache on"] = "lua_code_cache off",
      ["access_log off"] = "access_log on"
    }
  }
}

if not DEFAULT_ENV_VALUES[args.env:upper()] then
  cutils.error_exit(string.format("Unregistered environment '%s'", args.env:upper()))
end

-- Create the new configuration as a new blank object
local new_config = {}

-- Populate with overriden values
for k, v in pairs(DEFAULT_ENV_VALUES[env].yaml) do
  new_config[k] = v
end

-- Dump into a string
local new_config_content = yaml.dump(new_config)

-- Replace nginx directives
local nginx_config = default_config.nginx
for k, v in pairs(DEFAULT_ENV_VALUES[env].nginx) do
  nginx_config = nginx_config:gsub(k, v)
end

-- Indent nginx configuration
nginx_config = nginx_config:gsub("[^\r\n]+", function(line)
  return "  "..line
end)

-- Manually add the string (can't do that before yaml.dump as it messes the formatting)
new_config_content = new_config_content..[[
nginx: |
]]..nginx_config

local ok, err = IO.write_to_file(IO.path:join(args.output, CONFIG_FILENAME), new_config_content)
if not ok then
  cutils.error_exit(err)
end
