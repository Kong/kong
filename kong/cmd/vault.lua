local kong_global = require "kong.global"
local conf_loader = require "kong.conf_loader"
local pl_path = require "pl.path"
local pl_utils = require "pl.utils"
local pl_stringx = require "pl.stringx"
local log = require "kong.cmd.utils.log"
local kill = require "kong.cmd.utils.kill"
local prefix_handler = require "kong.cmd.utils.prefix_handler"
local compile_kong_lmdb_conf = prefix_handler.compile_kong_lmdb_conf


local DB = require "kong.db"


local assert = assert
local error = error
local print = print
local exit = os.exit
local fmt = string.format


local function init_db(args)
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

  package.path = conf.lua_package_path .. ";" .. package.path

  _G.kong = kong_global.new()
  kong_global.init_pdk(_G.kong, conf)

  local db = assert(DB.new(conf))
  assert(db:init_connector())
  assert(db:connect())
  assert(db.vaults:load_vault_schemas(conf.loaded_vaults))

  _G.kong.db = db

  return conf
end


-- convert relative path to absolute path
-- as resty will run a temporary nginx instance
local function to_absolute_path(kong_conf, lmdb_conf)
  local patterns = {
    "(lmdb_environment_path) (.+);",
  }
  local new_conf = lmdb_conf
  local prefix = kong_conf.prefix

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

local function get_with_lmdb(conf, args)
  -- Ensure that Kong is running and LMDB is initialized
  if not kill.is_running(conf.nginx_pid) then
    error("Kong is not running in " .. conf.prefix)
  end

  local nginx_kong_lmdb_conf, err = compile_kong_lmdb_conf(conf)
  if not nginx_kong_lmdb_conf then
    error(err)
  end

  local converted_lmdb_conf, err = to_absolute_path(conf, nginx_kong_lmdb_conf)
  if not converted_lmdb_conf then
    error(err)
  end

  local kong_path
  local ok, code, stdout, stderr = pl_utils.executeex("command -v kong")
  if ok and code == 0 then
    kong_path = pl_stringx.strip(stdout)

  else
    error("could not find kong absolute path:" .. stderr)
  end

  local cmd = fmt("resty --main-conf '%s' %s vault get %s %s %s %s",
    converted_lmdb_conf, kong_path, args[1], args.v or args.vv or "",
    args.conf and "-c " .. args.conf or "",
    args.prefix and "-p " .. args.prefix or "-p " .. conf.prefix)

  local ok, code, stdout, stderr = pl_utils.executeex(cmd)
  if ok and code == 0 then
    print(stdout)

  else
    error(stderr)
  end
end


local function get(args)
  if args.command == "get" then
    local reference = args[1]
    if not reference then
      return error("the 'get' command needs a <reference> argument \nkong vault get <reference>")
    end

    local conf = init_db(args)

    local vault = kong.vault

    if not vault.is_reference(reference) then
      -- assuming short form: <name>/<resource>[/<key>]
      reference = fmt("{vault://%s}", reference)
    end

    local opts, err = vault.parse_reference(reference)
    if not opts then
      return error(err)
    end

    local res, err = vault.get(reference)
    if err then
      -- add the lmdb-related directives into nginx.conf
      -- so that it will initialize the lmdb nginx module
      if err:find("no LMDB environment defined", 1, true) then
        return get_with_lmdb(conf, args)
      end
      return error(err)
    end

    print(res)
  end
end


local function execute(args)
  if args.command == "" then
    exit(0)
  end

  if args.command == "get" then
    get(args)
  end
end


local lapp = [[
Usage: kong vault COMMAND [OPTIONS]

Vault utilities for Kong.

Example usage:
 TEST=hello kong vault get env/test

The available commands are:
  get <reference>  Retrieves a value for <reference>

Options:
 -c,--conf    (optional string)  configuration file
 -p,--prefix  (optional string)  override prefix directory
]]


return {
  lapp = lapp,
  execute = execute,
  sub_commands = {
    get = true,
  },
}
