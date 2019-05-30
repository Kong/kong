local DB = require "kong.db"
local log = require "kong.cmd.utils.log"
local pl_path = require "pl.path"
local pl_file = require "pl.file"
local kong_global = require "kong.global"
local declarative = require "kong.db.declarative"
local conf_loader = require "kong.conf_loader"
local kong_yml = require "kong.templates.kong_yml"


local INIT_FILE = "kong.yml"


local accepted_formats = {
  yaml = true,
  json = true,
  lua = true,
}


local function generate_init()
  if pl_file.access_time(INIT_FILE) then
    error(INIT_FILE .. " already exists in the current directory.\n" ..
          "Will not overwrite it.")
  end

  pl_file.write(INIT_FILE, kong_yml)
end


local function execute(args)
  if args.command == "init" then
    generate_init()
    os.exit(0)
  end

  log.disable()
  -- retrieve default prefix or use given one
  local conf = assert(conf_loader(args.conf, {
    prefix = args.prefix
  }))
  log.enable()

  if pl_path.exists(conf.kong_env) then
    -- load <PREFIX>/kong.conf containing running node's config
    conf = assert(conf_loader(conf.kong_env))
  end

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

    local dc_table, err, _, vers = dc:parse_file(filename, accepted_formats)
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

      -- send anonymous report if reporting is not disabled
      if conf.anonymous_reports then
        local kong_reports = require "kong.reports"
        kong_reports.configure_ping(conf)
        kong_reports.toggle(true)

        local report = { decl_fmt_version = vers }
        kong_reports.send("config-db-import", report)
      end

    else -- parse
      log("parse successful")
    end

    os.exit(0)
  end

  error("unknown command '" .. args.command .. "'")
end

local lapp = [[
Usage: kong config COMMAND [OPTIONS]

Use declarative configuration files with Kong.

The available commands are:
  init                                Generate an example config file to
                                      get you started.

  db_import <file>                    Import a declarative config file into
                                      the Kong database.

  parse <file>                        Parse a declarative config file (check
                                      its syntax) but do not load it into Kong.

Options:
 -c,--conf        (optional string)   Configuration file.
 -p,--prefix      (optional string)   Override prefix directory.
]]

return {
  lapp = lapp,
  execute = execute,
  sub_commands = {
    init = true,
    db_import = true,
    parse = true,
  },
}
