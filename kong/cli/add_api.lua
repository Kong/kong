#!/usr/bin/env lua

local printable_mt = require "kong.tools.printable"
local constants = require "kong.constants"
local cutils = require "kong.cli.utils"
local IO = require "kong.tools.io"

local args = require("lapp")(string.format([[
Usage: kong add-api [options]

Options:
  -c,--config     (default %s) path to configuration file
  -n,--name       (string)                     name
  -p,--public-dns (string)                     public DNS
  -t,--target-url (string)                     target URL
]], constants.CLI.GLOBAL_KONG_CONF))

local config_path = cutils.get_kong_config_path(args.config)
local _, dao_factory = IO.load_configuration_and_dao(config_path)

local res, err = dao_factory.apis:insert {
  name = args.name,
  public_dns = args["public-dns"],
  target_url = args["target-url"]
}

if err then
  cutils.logger:error_exit("Cannot insert API: "..err)
elseif res then
  setmetatable(res, printable_mt)
  cutils.logger:success("API added to Kong: "..res)
end
