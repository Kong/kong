-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

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
  kong_global.init_pdk(_G.kong, conf, nil) -- nil: latest PDK

  local db = assert(DB.new(conf))
  assert(db:init_connector())
  assert(db:connect())
  assert(db.vaults_beta:load_vault_schemas(conf.loaded_vaults))

  _G.kong.db = db

  return db
end


local function get(args)
  local vault = require "kong.pdk.vault".new()
  if args.command == "get" then
    local reference = args[1]
    if not reference then
      return error("the 'get' command needs a <reference> argument \nkong vault get <reference>")
    end

    local db = init_db(args)

    if not vault.is_reference(reference) then
      -- assuming short form: <name>/<resource>[/<key>]
      reference = fmt("{vault://%s}", reference)
    end

    local opts, err = vault.parse_reference(reference)
    if not opts then
      return error(err)
    end

    local name = opts.name
    local res

    local vaults = db.vaults_beta
    if vaults.strategies[name] then
      res, err = vault.get(reference)

    elseif vaults:select_by_prefix(name) then
      ngx.IS_CLI = false
      res, err = vault.get(reference)
      ngx.IS_CLI = true
    else
      error(fmt("vault '%s' was not found", name, name, args[1]))
    end

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
]]


return {
  lapp = lapp,
  execute = execute,
  sub_commands = {
    get = true,
  },
}
