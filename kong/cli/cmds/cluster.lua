#!/usr/bin/env luajit

local constants = require "kong.constants"
local logger = require "kong.cli.utils.logger"
local utils = require "kong.tools.utils"
local config_loader = require "kong.tools.config_loader"
local Serf = require "kong.cli.services.serf"
local lapp = require("lapp")
local args = lapp(string.format([[
Kong cluster operations.

Usage: kong cluster <command> <args> [options]

Commands:
  <command> (string) where <command> is one of:
                       members, force-leave, reachability, keygen

Options:
  -c,--config (default %s) path to configuration file

]], constants.CLI.GLOBAL_KONG_CONF))

local KEYGEN = "keygen"
local FORCE_LEAVE = "force-leave"
local SUPPORTED_COMMANDS = {"members", KEYGEN, "reachability", FORCE_LEAVE}

if not utils.table_contains(SUPPORTED_COMMANDS, args.command) then
  lapp.quit("Invalid cluster command. Supported commands are: "..table.concat(SUPPORTED_COMMANDS, ", "))
end

local configuration = config_loader.load_default(args.config)

local signal = args.command
args.command = nil
args.config = nil

local skip_running_check

if signal == FORCE_LEAVE and utils.table_size(args) ~= 1 then
  logger:error("You must specify a node name")
  os.exit(1)
elseif signal == KEYGEN then
  skip_running_check = true
end

local res, err = Serf(configuration):invoke_signal(signal, args, false, skip_running_check)
if err then
  logger:error(err)
  os.exit(1)
end

logger:print(res)
