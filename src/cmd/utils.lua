--[[
Kong CLI utilities
 - Logging
 - Colorization
 - Disk I/O utils
 - nginx path/initialization
]]

local path = require("path").new("/")
local utils = require "kong.tools.utils"
local Object = require "classic"
local colors = require "ansicolors"

local CLI_CONSTANTS = {
  GLOBAL_KONG_CONF = "/etc/kong/kong.yml",
  NGINX_CONFIG = "nginx.conf",
  NGINX_PID = "kong.pid"
}

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
  self:log(colors("%{green}[SUCCESS]%{reset} ")..str)
end

function Logger:warn(str)
  self:log(colors("%{yellow}[WARNING]%{reset} ")..str)
end

function Logger:error(str)
  self:log(colors("%{red}[ERROR]%{reset} ")..str)
end

local function get_infos()
  local constants = require "kong.constants"
  return { name = constants.NAME, version = constants.VERSION }
end

local function is_openresty(path_to_check)
  local cmd = tostring(path_to_check).." -v 2>&1"
  local handle = io.popen(cmd)
  local out = handle:read()
  handle:close()
  local matched = out:match("^nginx version: ngx_openresty/") or out:match("^nginx version: openresty/")
  if matched then
    return path_to_check
  end
end

local function find_nginx()
  local nginx_bin = "nginx"
  local nginx_search_paths = {
    "/usr/local/openresty/nginx/sbin/",
    "/usr/local/opt/openresty/bin/",
    "/usr/local/bin/",
    "/usr/sbin/",
    ""
  }

  for i = 1, #nginx_search_paths do
    local prefix = nginx_search_paths[i]
    local to_check = tostring(prefix)..tostring(nginx_bin)
    if is_openresty(to_check) then
      nginx_path = to_check
      return nginx_path
    end
  end
end

local function prepare_nginx_working_dir(kong_config)
  if kong_config.send_anonymous_reports then
    kong_config.nginx = "error_log syslog:server=kong-hf.mashape.com:61828 error;\n"..kong_config.nginx
  end

  -- Create nginx folder if needed
  path:mkdir(path:join(kong_config.nginx_working_dir, "logs"))
  os.execute("touch "..path:join(kong_config.nginx_working_dir, "logs", "error.log"))
  os.execute("touch "..path:join(kong_config.nginx_working_dir, "logs", "access.log"))

  -- Extract nginx config to nginx folder
  utils.write_to_file(path:join(kong_config.nginx_working_dir, CLI_CONSTANTS.NGINX_CONFIG), kong_config.nginx)

  return kong_config.nginx_working_dir
end

local function file_exists(name)
   local f = io.open(name, "r")
   if f ~= nil then
    io.close(f)
    return true
  else
    return false
  end
end

local function get_luarocks_config_dir()
  local cfg = require "luarocks.cfg"
  local lpath = require "luarocks.path"
  local search = require "luarocks.search"
  local infos = get_infos()

  local conf_dir
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

  local repo = tree_map[results.kong[version][1].repo]
  return lpath.conf_dir(infos.name:lower(), infos.version, repo)
end

local function get_kong_config(args_config)
  local yaml = require "yaml"
  local logger = Logger()

  -- Use the rock's config if no config at default location
  if not file_exists(args_config) then
    local kong_rocks_conf = path:join(get_luarocks_config_dir(), "kong.yml")
    logger:warn("No config at: "..args_config.." using default config instead.")
    args_config = kong_rocks_conf
  end

  -- Make sure the configuration file really exists
  if not file_exists(args_config) then
    logger:warn("No config at: "..args_config)
    logger:error("Could not find a configuration file.")
    os.exit(1)
  end

  -- Load and parse config
  local config_content = utils.read_file(args_config)
  local config = yaml.load(config_content)

  logger:log("Using config: "..args_config)

  -- TODO: validate configuration

  return args_config, config
end

return {
  CONSTANTS = CLI_CONSTANTS,

  path = path,
  colors = colors,
  logger = Logger(),

  get_infos = get_infos,
  find_nginx = find_nginx,
  file_exists = file_exists,
  is_openresty = is_openresty,
  get_kong_config = get_kong_config,
  prepare_nginx_working_dir = prepare_nginx_working_dir
}
