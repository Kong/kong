--[[
Kong CLI utilities
 - Logging
 - Luarocks helpers
]]

local ansicolors = require "ansicolors"
local constants = require "kong.constants"
local Object = require "classic"
local lpath = require "luarocks.path"
local IO = require "kong.tools.io"

--
-- Colors
--
local colors = {}
for _, v in ipairs({"red", "green", "yellow", "blue"}) do
  colors[v] = function(str) return ansicolors("%{"..v.."}"..str.."%{reset}") end
end

local function trim(s)
  return (s:gsub("^%s*(.-)%s*$", "%1"))
end

--
-- Logging
--
local Logger = Object:extend()

function Logger:new(silent)
  self.silent = silent
end

function Logger:print(str)
  if not self.silent then
    print(trim(str))
  end
end

function Logger:info(str)
  self:print(colors.blue("[INFO] ")..str)
end

function Logger:success(str)
  self:print(colors.green("[OK] ")..str)
end

function Logger:warn(str)
  self:print(colors.yellow("[WARN] ")..str)
end

function Logger:error(str)
  self:print(colors.red("[ERR] ")..str)
end

function Logger:error_exit(str)
  self:error(str)
  -- Optional stacktrace
  --print("")
  --error("", 2)
  os.exit(1)
end

local logger = Logger()

--
-- Luarocks
--
local function get_kong_infos()
  return { name = constants.NAME, version = constants.ROCK_VERSION }
end

local function get_luarocks_dir()
  local cfg = require "luarocks.cfg"
  local search = require "luarocks.search"
  local infos = get_kong_infos()

  local tree_map = {}
  local results = {}

  for _, tree in ipairs(cfg.rocks_trees) do
    local rocks_dir = lpath.rocks_dir(tree)
    tree_map[rocks_dir] = tree
    search.manifest_search(results, rocks_dir, search.make_query(infos.name:lower(), infos.version))
  end

  local version
  for k, _ in pairs(results.kong) do
    version = k
  end

  return tree_map[results.kong[version][1].repo]
end

local function get_luarocks_config_dir()
  local repo = get_luarocks_dir()
  local infos = get_kong_infos()
  return lpath.conf_dir(infos.name:lower(), infos.version, repo)
end

local function get_luarocks_install_dir()
  local repo = get_luarocks_dir()
  local infos = get_kong_infos()
  return lpath.install_dir(infos.name:lower(), infos.version, repo)
end

local function get_kong_config_path(args_config)
  local config_path = args_config

  -- Use the rock's config if no config at default location
  if not IO.file_exists(config_path) then
    logger:warn("No configuration at: "..config_path.." using default config instead.")
    config_path = IO.path:join(get_luarocks_config_dir(), "kong.yml")
  end

  -- Make sure the configuration file really exists
  if not IO.file_exists(config_path) then
    logger:warn("No configuration at: "..config_path)
    logger:error_exit("Could not find a configuration file.")
  end

  logger:info("Using configuration: "..config_path)

  return config_path
end

local function get_ssl_cert_and_key(kong_config)
  local ssl_cert_path, ssl_key_path

  if (kong_config.ssl_cert and not kong_config.ssl_key) or
    (kong_config.ssl_key and not kong_config.ssl_cert) then
    logger:error_exit("Both \"ssl_cert_path\" and \"ssl_key_path\" need to be specified in the configuration, or none of them")
  elseif kong_config.ssl_cert and kong_config.ssl_key then
    ssl_cert_path = kong_config.ssl_cert_path
    ssl_key_path = kong_config.ssl_key_path
  else
    ssl_cert_path = IO.path:join(get_luarocks_install_dir(), "ssl", "kong-default.crt")
    ssl_key_path = IO.path:join(get_luarocks_install_dir(), "ssl", "kong-default.key")
  end

  -- Check that the file exists
  if ssl_cert_path and not IO.file_exists(ssl_cert_path) then
    logger:error_exit("Can't find default Kong SSL certificate at: "..ssl_cert_path)
  end
  if ssl_key_path and not IO.file_exists(ssl_key_path) then
    logger:error_exit("Can't find default Kong SSL key at: "..ssl_key_path)
  end

  return ssl_cert_path, ssl_key_path
end

-- Checks if a port is open on localhost
-- @param `port`  The port to check
-- @return `open` True if open, false otherwise
local function is_port_open(port)
  local _, code = IO.os_execute("nc -w 5 -z 127.0.0.1 "..tostring(port))
  return code == 0
end

return {
  colors = colors,
  logger = logger,
  get_kong_infos = get_kong_infos,
  get_kong_config_path = get_kong_config_path,
  get_ssl_cert_and_key = get_ssl_cert_and_key,
  get_luarocks_install_dir = get_luarocks_install_dir,
  is_port_open = is_port_open
}
