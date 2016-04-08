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
  -c,--config  (default %s) path to configuration file
  -o,--output  (default .)                  output directory
  -e,--env     (default DEVELOPMENT)        environment name
  -d,--database (default cassandra)         database to use
  -s,--suffix  (default DEVELOPMENT)        suffix name
]], constants.CLI.GLOBAL_KONG_CONF))

args.env = args.env:upper()
local CONFIG_FILENAME = string.format("kong_%s.yml", args.suffix)
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
      ["postgres"] = {
        ["database"] = "kong_tests"
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
      ["postgres"] = {
        ["database"] = "kong_development"
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

local configuration = config_loader.load_default(args.config)
local new_nginx_config = configuration.nginx
local new_yaml_config = {}

if DEFAULT_ENV_VALUES[args.env] ~= nil then
  -- Populate with overriden values
  for k, v in pairs(DEFAULT_ENV_VALUES[args.env].yaml) do
    new_yaml_config[k] = v
  end
end

if args.database ~= "" then
  new_yaml_config.database = args.database
end

-- Dump into a string
local new_config_content = yaml.dump(new_yaml_config)

-- Workaround for https://github.com/lubyk/yaml/issues/2
-- This workaround is in two places. To remove it "Find and replace" in the code
new_config_content = string.gsub(new_config_content, "(%w+:%s*)([%w%.]+:%d+)", "%1\"%2\"")

if DEFAULT_ENV_VALUES[args.env] ~= nil then
  -- Replace nginx directives
  for k, v in pairs(DEFAULT_ENV_VALUES[args.env].nginx) do
    new_nginx_config = new_nginx_config:gsub(k, v)
  end
end

-- Indent nginx configuration
new_nginx_config = new_nginx_config:gsub("[^\r\n]+", function(line)
  return "  "..line
end)

-- Manually add the string (can't do that before yaml.dump as it messes the formatting)
new_config_content = new_config_content..[[
nginx: |
]]..new_nginx_config

local ok, err = IO.write_to_file(IO.path:join(args.output, CONFIG_FILENAME), new_config_content)
if not ok then
  logger:error(err)
  os.exit(1)
end
