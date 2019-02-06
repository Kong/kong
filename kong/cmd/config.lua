local DB = require "kong.db"
local log = require "kong.cmd.utils.log"
local pl_path = require "pl.path"
local kong_global = require "kong.global"
local declarative = require "kong.db.declarative"
local conf_loader = require "kong.conf_loader"


local accepted_formats = {
  yaml = true,
  json = true,
  lua = true,
}


local function execute(args)
  log.disable()
  -- retrieve default prefix or use given one
  local default_conf = assert(conf_loader(args.conf, {
    prefix = args.prefix
  }))
  log.enable()

  assert(pl_path.exists(default_conf.prefix),
         "no such prefix: " .. default_conf.prefix)
  assert(pl_path.exists(default_conf.kong_env),
         "Kong is not running at " .. default_conf.prefix)

  -- load <PREFIX>/kong.conf containing running node's config
  local conf = assert(conf_loader(default_conf.kong_env))

  if args.command == "db-import" then
    args.command = "db_import"
  end

  if args.command == "db_import" and conf.database == "off" then
    error("'kong config db_import' only works with a database.\n" ..
          "When using database=off, reload your declarative configuration\n" ..
          "using the /config endpoint.")
  end

  package.path = conf.lua_package_path .. ";" .. package.path

  local dc, err = declarative.new_config(conf)
  if not dc then
    error(err)
  end

  if args.command == "db_import" or args.command == "parse" then
    local filename = args[1]
    if not filename then
      error("expected a declarative configuration file; see `kong config --help`")
    end

    local dc_table, err = dc:parse_file(filename, accepted_formats)
    if not dc_table then
      error("Failed parsing:\n" .. err)
    end

    if args.command == "db_import" then
      log("parse successful, beginning import")

      _G.kong = kong_global.new()
      kong_global.init_pdk(_G.kong, conf, nil) -- nil: latest PDK

      local db = assert(DB.new(conf))
      assert(db:init_connector())
      assert(db:connect())
      assert(db.plugins:load_plugin_schemas(conf.loaded_plugins))

      _G.kong.db = db

      local ok, err = declarative.load_into_db(dc_table)
      if not ok then
        error("Failed importing:\n" .. err)
      end

      log("import successful")

    else -- parse
      log("parse successful:")
      log(declarative.to_yaml_string(dc_table))
    end

    os.exit(0)
  end

  error("unknown command '" .. args.command .. "'")
end

local lapp = [[
Usage: kong config COMMAND [OPTIONS]

Use declarative configuration files with Kong.

The available commands are:
  db_import <file>              Import a declarative config file into
                                the Kong database.

  parse <file>                  Parse a declarative config file (check
                                its syntax) but do not load it into Kong.

Options:
 -c,--conf        (optional string)   Configuration file.
 -p,--prefix      (optional string)   Override prefix directory.
]]

return {
  lapp = lapp,
  execute = execute,
  sub_commands = {
    db_import = true,
    parse = true,
  },
}
