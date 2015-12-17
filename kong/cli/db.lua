#!/usr/bin/env luajit

local Faker = require "kong.tools.faker"
local constants = require "kong.constants"
local cutils = require "kong.cli.utils"
local config = require "kong.tools.config_loader"
local dao = require "kong.tools.dao_loader"
local lapp = require("lapp")

local args = lapp(string.format([[
For development purposes only.

Seed the database with random data or drop it.

Usage: kong db <command> [options]

Commands:
  <command> (string) where <command> is one of:
                       seed, drop

Options:
  -c,--config (default %s) path to configuration file
  -r,--random                              flag to also insert random entities
  -n,--number (default 1000)               number of random entities to insert if --random
]], constants.CLI.GLOBAL_KONG_CONF))

-- $ kong db
if args.command == "db" then
  lapp.quit("Missing required <command>.")
end

local config_path = cutils.get_kong_config_path(args.config)
local config = config.load(config_path)
local dao_factory = dao.load(config)

if args.command == "seed" then

  -- Drop if exists
  local err = dao_factory:drop()
  if err then
    cutils.logger:error_exit(err)
  end

  local faker = Faker(dao_factory)
  faker:seed(args.random and args.number or nil)
  cutils.logger:success("Populated")

elseif args.command == "drop" then

  local err = dao_factory:drop()
  if err then
    cutils.logger:error_exit(err)
  end

  cutils.logger:success("Dropped")

else
  lapp.quit("Invalid command: "..args.command)
end
