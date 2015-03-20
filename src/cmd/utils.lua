local Object = require "classic"
local yaml = require "yaml"
local path = require("path").new("/")
local utils = require "kong.tools.utils"

local colorize = {}
local colors = {
  -- attributes
  reset = 0,
  clear = 0,
  bright = 1,
  dim = 2,
  underscore = 4,
  blink = 5,
  reverse = 7,
  hidden = 8,
  -- foreground
  black = 30,
  red = 31,
  green = 32,
  yellow = 33,
  blue = 34,
  magenta = 35,
  cyan = 36,
  white = 37,
  -- background
  onblack = 40,
  onred = 41,
  ongreen = 42,
  onyellow = 43,
  onblue = 44,
  onmagenta = 45,
  oncyan = 46,
  onwhite = 47
}

local colormt = {}
colormt.__metatable = {}

function colormt:__tostring()
  return self.value
end

function colormt:__concat(other)
  return tostring(self) .. tostring(other)
end

function colormt:__call(s)
  return self .. s .. colorize.reset
end

local function makecolor(value)
  return setmetatable({ value = string.char(27) .. '[' .. tostring(value) .. 'm' }, colormt)
end

for c, v in pairs(colors) do
  colorize[c] = makecolor(v)
end


local logger = Object:extend()
function logger:new(silent)
  self.silent = silent
end
function logger:log(str)
  if not self.silent then
    print(str)
  end
end
function logger:success(str)
  self:log(colorize.green("✔ ")..str)
end
function logger:error_exit(str)
  self:log(colorize.red("✘ ")..str)
  os.exit(1)
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

local function prepare_nginx_output(kong_config_path, nginx_output_path)
  local nginx_config = "nginx.conf"
  local config_content = utils.read_file(kong_config_path)
  local config = yaml.load(config_content)

  if config.send_anonymous_reports then
    config.nginx = "error_log syslog:server=kong-hf.mashape.com:61828 error;\n"..config.nginx
  end

  utils.write_to_file(path:join(nginx_output_path, nginx_config), config.nginx)

  path:mkdir(path:join(nginx_output_path, "logs"))
  os.execute("touch "..path:join("logs", "error.log"))
  os.execute("touch "..path:join("logs", "access.log"))

  return nginx_config
end

local function script_path()
  local handle = io.popen("pwd")
  local pwd = handle:read()
  handle:close()
  local script_path = debug.getinfo(2, "S").source:sub(2):match("(.*/)")
  if script_path:match("^/") then
    return script_path
  else
    return pwd.."/"..script_path
  end
end

local function file_exists(name)
   local f = io.open(name,"r")
   if f ~= nil then
    io.close(f)
    return true
  else
    return false
  end
end

return {
  path = path,
  file_exists = file_exists,
  logger = logger(),
  find_nginx = find_nginx,
  script_path = script_path,
  is_openresty = is_openresty,
  prepare_nginx_output = prepare_nginx_output
}
