local cjson   = require "cjson.safe"
local log     = require "kong.cmd.utils.log"
local meta    = require "kong.meta"
local pl_file = require "pl.file"
local pl_path = require "pl.path"


local _M = {}


local function get_license_string()
  local license_data_env = os.getenv("KONG_LICENSE_DATA")
  if license_data_env then
    return license_data_env
  end

  local license_path = os.getenv("KONG_LICENSE_PATH")
  if not license_path then
    ngx.log(ngx.ERR, "KONG_LICENSE_PATH is not set")
    return nil
  end

  local license_file = io.open(license_path, "r")
  if not license_file then
    ngx.log(ngx.ERR, "could not open license file")
    return nil
  end

  local license_data = license_file:read("*a")
  if not license_data then
    ngx.log(ngx.ERR, "could not read license file contents")
    return nil
  end

  license_file:close()

  return license_data
end


local function read_license_info()
  local license_data = get_license_string()
  if not license_data then
    return nil
  end

  local license, err = cjson.decode(license_data)
  if err then
    ngx.log(ngx.ERR, "could not decode license JSON: " .. err)
    return nil
  end

  return license
end
_M.read_license_info = read_license_info


local function prepare_admin(kong_config)
  local ADMIN_GUI_PATH = kong_config.prefix .. "/gui"

  -- if the gui directory does not exist, we needn't bother attempting
  -- to update a non-existant template. this occurs in development
  -- environments where the gui does not exist (it is bundled at build
  -- time), so this effectively serves to quiet useless warnings in kong-ee
  -- development
  if not pl_path.exists(ADMIN_GUI_PATH) then
    return
  end

  local compile_env = {
    ADMIN_API_PORT = tostring(kong_config.admin_port),
    ADMIN_API_SSL_PORT = tostring(kong_config.admin_ssl_port),
    RBAC_ENFORCED = tostring(kong_config.enforce_rbac),
    RBAC_HEADER = tostring(kong_config.rbac_auth_header),
  }

  local idx_filename = ADMIN_GUI_PATH .. "/index.html"
  local tp_filename  = ADMIN_GUI_PATH .. "/index.html.tp-" ..
                       meta._VERSION

  -- make the template if it doesn't exit
  if not pl_path.isfile(tp_filename) then
    if not pl_file.copy(idx_filename, tp_filename) then
      log.warn("Could not copy index to template")
    end
  end

  -- load the template, do our substitutions, and write it out
  local index = pl_file.read(tp_filename)

  if not index then
    log.warn("Could not read GUI index template")
    return
  end

  local _, err
  index, _, err = ngx.re.gsub(index, "{{(.*?)}}", function(m)
          return compile_env[m[1]] end)
  if err then
    log.warn("Error replacing templated values: " .. err)
  end

  pl_file.write(idx_filename, index)
end
_M.prepare_admin = prepare_admin


return _M
