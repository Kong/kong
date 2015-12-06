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

  return config_path
end

-- Checks if a port is available to bind a server to on localhost
-- @param `port`  The port to check
-- @return `open` Truthy if available, falsy + error otherwise
local function is_port_bindable(port)
  local server, success, err
  server = require("socket").tcp()
  server:setoption('reuseaddr', true)
  success, err = server:bind("*", port)
  if success then 
    success, err = server:listen()
  end
  server:close()
  return success, err
end

return {
  colors = colors,
  logger = logger,
  get_kong_infos = get_kong_infos,
  get_kong_config_path = get_kong_config_path,
  get_luarocks_install_dir = get_luarocks_install_dir,
  is_port_bindable = is_port_bindable
}
