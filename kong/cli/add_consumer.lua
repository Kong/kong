#!/usr/bin/env lua

local printable_mt = require "kong.tools.printable"
local constants = require "kong.constants"
local cutils = require "kong.cli.utils"
local IO = require "kong.tools.io"

local args = require("lapp")(string.format([[
Usage: kong add-consumer [options]

Options:
  -c,--config     (default %s) path to configuration file
  -n,--username  (default none)                     username
  -p,--custom-id (default none)                     custom id
]], constants.CLI.GLOBAL_KONG_CONF))

local config_path = cutils.get_kong_config_path(args.config)
local _, dao_factory = IO.load_configuration_and_dao(config_path)

local res, err = dao_factory.consumers:insert {
  username = args.username ~= "none" and args.username or nil,
  custom_id = args["custom-id"] ~= "none" and args["custom-id"] or nil
}

if err then
  cutils.logger:error_exit("Cannot insert consumer: "..err)
elseif res then
  setmetatable(res, printable_mt)
  cutils.logger:success("Consumer added to Kong: "..res)
end
