local kong_global = require "kong.global"
local conf_loader = require "kong.conf_loader"
local pl_path = require "pl.path"
local log = require "kong.cmd.utils.log"


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
end


local function get(args)
  if args.command == "get" then
    local reference = args[1]
    if not reference then
      return error("the 'get' command needs a <reference> argument \nkong vault get <reference>")
    end

    init_db(args)

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
