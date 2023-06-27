local conf_loader = require "kong.conf_loader"
local pl_path = require "pl.path"
local pl_stringx = require "pl.stringx"
local pl_utils = require "pl.utils"
local prefix_handler = require "kong.cmd.utils.prefix_handler"
local log = require "kong.cmd.utils.log"
local fmt = string.format

local compile_nginx_main_inject_conf = prefix_handler.compile_nginx_main_inject_conf
local compile_nginx_http_inject_conf = prefix_handler.compile_nginx_http_inject_conf
local compile_nginx_stream_inject_conf = prefix_handler.compile_nginx_stream_inject_conf
local prepare_prefix = prefix_handler.prepare_prefix

local function load_conf(args)
  -- retrieve default prefix or use given one
  log.disable()
  local conf = assert(conf_loader(args.conf, {
    prefix = args.prefix
  }))
  log.enable()

  if pl_path.exists(conf.kong_env) then
    -- load <PREFIX>/kong.conf containing running node's config
    conf = assert(conf_loader(conf.kong_env))
  end

  -- make sure necessary files like `.ca_combined` exist
  -- but skip_write to avoid overwriting the existing nginx configurations
  if not pl_path.exists(conf.lua_ssl_trusted_certificate_combined) then
    assert(prepare_prefix(conf, nil, true))
  end

  return conf
end

-- convert relative path to absolute path
-- as resty will run a temporary nginx instance
local function convert_directive_path_to_absolute(prefix, nginx_conf, paths)
  local new_conf = nginx_conf

  for _, path in ipairs(paths) do
    local pattern = fmt("(%s) (.+);", path)
    local m, err = ngx.re.match(new_conf, pattern)
    if err then
      return nil, err

    elseif m then
      local path = pl_stringx.strip(m[2])

      if path:sub(1, 1) ~= '/' then
        local absolute_path = prefix .. "/" .. path
        local replace = "$1 " .. absolute_path .. ";"
        local _, err
        new_conf, _, err = ngx.re.sub(new_conf, pattern, replace)

        if not new_conf then
          return nil, err
        end
      end
    end
  end

  return new_conf, nil
end

local function compile_main_inject(conf)
  local nginx_main_inject_conf, err = compile_nginx_main_inject_conf(conf)
  if not nginx_main_inject_conf then
    return nil, err
  end

  -- path directives that needs to be converted
  local paths = {
    "lmdb_environment_path",
  }
  return convert_directive_path_to_absolute(conf.prefix, nginx_main_inject_conf, paths)
end

local function compile_http_inject(conf)
  return compile_nginx_http_inject_conf(conf)
end

local function compile_stream_inject(conf)
  return compile_nginx_stream_inject_conf(conf)
end

local function construct_cmd(conf)
  local main_conf, err = compile_main_inject(conf)
  if err then
    return nil, err
  end

  local http_conf, err = compile_http_inject(conf)
  if err then
    return nil, err
  end

  local stream_conf, err = compile_stream_inject(conf)
  if err then
    return nil, err
  end
end

local function compile_confs(args)
  local conf = load_conf(args)
  local main_conf, err = compile_main_inject(conf)
  if err then
    return nil, err
  end

  local http_conf, err = compile_http_inject(conf)
  if err then
    return nil, err
  end

  local stream_conf, err = compile_stream_inject(conf)
  if err then
    return nil, err
  end

  return { main_conf = main_conf, http_conf = http_conf, stream_conf = stream_conf, }, nil
end

return {
  compile_confs = compile_confs,
}
