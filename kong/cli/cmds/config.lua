#!/usr/bin/env luajit

local constants = require "kong.constants"
local logger = require "kong.cli.utils.logger"
local IO = require "kong.tools.io"
local yaml = require "yaml"
local config_loader = require "kong.tools.config_loader"
local args = require("lapp")(string.format([[
For development purposes only.

Duplicate an existing configuration for given environment.

Usage: kong config [options]

Options:
  -c,--config (default %s) path to configuration file
  -o,--output (default .)                  output
  -e,--env    (string)                     environment name
]], constants.CLI.GLOBAL_KONG_CONF))

local CONFIG_FILENAME = string.format("kong%s.yml", args.env ~= "" and "_"..args.env or "")

local configuration = config_loader.load_default(args.config)
local env = args.env:upper()

local DEFAULT_ENV_VALUES = {
  TEST = {
    yaml = {
      ["nginx_working_dir"] = "nginx_tmp",
      ["send_anonymous_reports"] = false,
      ["proxy_listen"] = "0.0.0.0:8100",
      ["proxy_listen_ssl"] = "0.0.0.0:8543",
      ["admin_api_listen"] = "0.0.0.0:8101",
      ["cluster_listen"] = "0.0.0.0:9100",
      ["cluster_listen_rpc"] = "0.0.0.0:9101",
      ["cassandra"] = {
        ["keyspace"] = "kong_tests"
      },
      ["cluster"] = {
        ["profile"] = "local"
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
      ["cassandra"] = {
        ["keyspace"] = "kong_development"
      },
      ["cluster"] = {
        ["profile"] = "local"
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
  logger:error(string.format("Unregistered environment '%s'", args.env:upper()))
  os.exit(1)
end

-- Create the new configuration as a new blank object
local new_config = {}

-- Populate with overriden values
for k, v in pairs(DEFAULT_ENV_VALUES[env].yaml) do
  new_config[k] = v
end

-- Dump into a string
local new_config_content = yaml.dump(new_config)

-- Workaround for https://github.com/lubyk/yaml/issues/2
-- This workaround is in two places. To remove it "Find and replace" in the code
new_config_content = string.gsub(new_config_content, "(%w+:%s*)([%w%.]+:%d+)", "%1\"%2\"")

-- Replace nginx directives
local nginx_config = configuration.nginx
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
  logger:error(err)
  os.exit(1)
end
