local conf_loader = require "kong.conf_loader"
local pl_path = require "pl.path"
local pl_stringx = require "pl.stringx"
local pl_utils = require "pl.utils"
local prefix_handler = require "kong.cmd.utils.prefix_handler"
local log = require "kong.cmd.utils.log"
local gsub = string.gsub
local fmt = string.format

local compile_nginx_main_inject_conf = prefix_handler.compile_nginx_main_inject_conf
local compile_nginx_http_inject_conf = prefix_handler.compile_nginx_http_inject_conf
local compile_nginx_stream_inject_conf = prefix_handler.compile_nginx_stream_inject_conf

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
    assert(prefix_handler.prepare_prefix(conf, nil, true))
  end

  return conf
end

-- convert relative path to absolute path
-- as resty will run a temporary nginx instance
local function convert_to_absolute_path(prefix, nginx_conf, patterns)
  local new_conf = nginx_conf

  for _, pattern in ipairs(patterns) do
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
  local patterns = {
    "(lmdb_environment_path) (.+);",
  }

  return convert_to_absolute_path(conf.prefix, nginx_main_inject_conf, patterns)
end

local function compile_http_inject(conf)
  return compile_nginx_http_inject_conf(conf)
end

local function compile_stream_inject(conf)
  return compile_nginx_stream_inject_conf(conf)
end

local function construct_args(args)
  local positional_args = ""
  local named_args = ""

  -- put the subcommand back to the first positional argument
  if args.command then
    table.insert(args, 1, args.command)
    args.command = nil
  end

  -- construct positional arguments
  while #args > 0 do
    local arg =  table.remove(args, 1)
    positional_args = positional_args .. arg .. " "
  end

  -- construct named arguments
  for k, v in pairs(args) do
    if type(v) == "boolean" then
      if v then
        named_args = named_args .. "--" .. gsub(k, "_", "-") .. " "
      end
    else
      named_args = named_args .. "--" .. gsub(k, "_", "-") .. " " .. v .. " "
    end
  end

  -- add `--no-inject` to terminate the recursion
  named_args = named_args .. "--no-inject"

  return positional_args .. named_args
end

local function construct_cmd(conf, cmd_name, args)
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

  local kong_path
  local ok, code, stdout, stderr = pl_utils.executeex("command -v kong")
  if ok and code == 0 then
    kong_path = pl_stringx.strip(stdout)

  else
    return nil, "could not find kong absolute path:" .. stderr
  end

  local cmd_args = construct_args(args)

  local cmd = fmt("resty --main-conf \"%s\" --http-conf \"%s\" --stream-conf \"%s\" %s %s %s",
    main_conf, http_conf, stream_conf, kong_path, cmd_name, cmd_args)

  return cmd, nil
end

local function respawn(cmd_name, args)
  local conf = load_conf(args)
  local cmd, err = construct_cmd(conf, cmd_name, args)

  if err then
    error(err)
  end

  log.verbose("respawn: %s", cmd)

  local ok, code, stdout, stderr = pl_utils.executeex(cmd)
  if ok and code == 0 then
    print(stdout)

  else
    error(stderr)
  end
end

return {
  respawn = respawn,
}
