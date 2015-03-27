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
for _, v in ipairs({"red", "green", "yellow"}) do
  colors[v] = function(str) return ansicolors("%{"..v.."}"..str.."%{reset}") end
end

--
-- Logging
--
local Logger = Object:extend()

function Logger:new(silent)
  self.silent = silent
end

function Logger:log(str)
  if not self.silent then
    print(str)
  end
end

function Logger:success(str)
  self:log(colors.green("[SUCCESS] ")..str)
end

function Logger:warn(str)
  self:log(colors.yellow("[WARNING] ")..str)
end

function Logger:error(str)
  self:log(colors.red("[ERROR] ")..str)
end

function Logger:error_exit(str)
  self:error(str)
  os.exit(1)
end

local logger = Logger()

--
-- Luarocks
--
local function get_infos()
  return { name = constants.NAME, version = constants.VERSION }
end

local function get_luarocks_dir()
  local cfg = require "luarocks.cfg"
  local search = require "luarocks.search"
  local infos = get_infos()

  local tree_map = {}
  local results = {}

  for _, tree in ipairs(cfg.rocks_trees) do
    local rocks_dir = lpath.rocks_dir(tree)
    tree_map[rocks_dir] = tree
    search.manifest_search(results, rocks_dir, search.make_query(infos.name:lower(), nil))
  end

  local version
  for k, _ in pairs(results.kong) do
    version = k
  end

  return tree_map[results.kong[version][1].repo]
end

local function get_luarocks_config_dir()
  local repo = get_luarocks_dir()
  local infos = get_infos()
  return lpath.conf_dir(infos.name:lower(), infos.version, repo)
end

local function get_luarocks_install_dir()
  local repo = get_luarocks_dir()
  local infos = get_infos()
  return lpath.install_dir(infos.name:lower(), infos.version, repo)
end

local function get_kong_config_path(args_config)
  -- Use the rock's config if no config at default location
  if not IO.file_exists(args_config) then
    logger:warn("No config at: "..args_config.." using default config instead.")
    args_config = IO.path:join(get_luarocks_config_dir(), "kong.yml")
  end

  -- Make sure the configuration file really exists
  if not IO.file_exists(args_config) then
    logger:warn("No config at: "..args_config)
    logger:error_exit("Could not find a configuration file.")
  end

  logger:log("Using config: "..args_config)

  -- TODO: validate configuration
  --[[local status, res = pcall(require, "kong.dao."..config.database..".factory")
    if not status then
      logger:error("Wrong config")
      os.exit(1)
    end]]

  return args_config
end

return {
  colors = colors,
  logger = logger,
  get_infos = get_infos,
  get_kong_config_path = get_kong_config_path,
  get_luarocks_install_dir = get_luarocks_install_dir
}
