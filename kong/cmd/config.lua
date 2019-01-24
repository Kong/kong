local log = require "kong.cmd.utils.log"
local pl_path = require "pl.path"
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

  package.path = conf.lua_package_path .. ";" .. package.path

  local dc, err = declarative.init(conf)
  if not dc then
    log(err)
    os.exit(1)
  end

  if args.command == "parse" then
    if not args.file then
      log("expected a declarative declarative configuration file; see `kong config --help`")
      os.exit(1)
    end

    local dc_table, err = dc:parse_file(args.file, accepted_formats)
    if not dc_table then
      log("Failed parsing:")
      log(require'inspect'(err))
      os.exit(1)
    end

    log("parse successful:")
    log(require'inspect'(dc_table))

    os.exit(0)
  end

  log("unknown command '" .. args.command .. "'")
  os.exit(1)
end

local lapp = [[
Usage: kong config COMMAND [OPTIONS]

Use declarative configuration files with Kong.

The available commands are:
  parse <file>                  Parse a declarative config file (check
                                its syntax) but do not load it into Kong.

Options:
 -c,--conf        (optional string)   Configuration file.
 -p,--prefix      (optional string)   Override prefix directory.
 <command>        (string)            Which command to perform
 <file>           (string)            Declarative config file name (.yaml, .json or .lua)
]]

return {
  lapp = lapp,
  execute = execute
}
