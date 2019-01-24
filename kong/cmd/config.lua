local declarative_config = require "kong.db.schema.others.declarative_config"
local log = require "kong.cmd.utils.log"
local lyaml = require "lyaml"
local cjson = require "cjson.safe"
local pl_path = require "pl.path"
local conf_loader = require "kong.conf_loader"


local DeclarativeConfig


local function parse(filename)
  assert(type(filename) == "string")

  local fd = io.open(filename)
  if not fd then
    return nil, "could not open declarative configuration file: " .. filename
  end

  local dc_str, err = fd:read("*a")
  if not dc_str then
    return nil, "could not read declarative configuration file: " .. filename
  end

  assert(fd:close())

  local dc_table
  if filename:match("ya?ml$") then
    local pok
    pok, dc_table, err = pcall(lyaml.load, dc_str)
    if not pok then
      err = dc_table
      dc_table = nil
    end

  elseif filename:match("json$") then
    dc_table, err = cjson.decode(dc_str)

  elseif filename:match("lua$") then
    local chunk = loadstring(dc_str)
    setfenv(chunk, {})
    if chunk then
      local pok, dc_table = pcall(chunk)
      if not pok then
        err = dc_table
      end
    end

  else
    return nil, "unknown file extension (yml, yaml, json, lua are supported): " .. filename
  end

  if not dc_table then
    return nil, "failed parsing declarative configuration file " ..
        filename .. (err and ": " .. err or "")
  end

  local ok, err = DeclarativeConfig:validate(dc_table)
  if not ok then
    return nil, err
  end

print(require'inspect'(DeclarativeConfig:flatten_entities(dc_table)))

  dc_table = DeclarativeConfig:process_auto_fields(dc_table, "insert")

  ok, err = DeclarativeConfig:validate_references(dc_table)
  if not ok then
    return nil, err
  end

  return dc_table
end


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

  DeclarativeConfig = declarative_config.load(conf.loaded_plugins)

  if args.command == "parse" then
    if not args.file then
      log("expected a declarative declarative configuration file; see `kong config --help`")
      os.exit(1)
    end

    local dc_table, err = parse(args.file)
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
