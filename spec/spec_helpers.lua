-- This file offers helpers for dao and integration tests (migrate, start kong, stop, faker...)
-- It is built so that it only needs to be required at the beginning of any spec file.
-- It supports other environments by passing a configuration file.

local IO = require "kong.tools.io"
local Faker = require "kong.tools.faker"
local Migrations = require "kong.tools.migrations"

-- Constants
local KONG_BIN = "bin/kong"
local DEFAULT_CONF_FILE = "kong.yml"
local TEST_CONF_FILE = "kong_TEST.yml"
local TEST_PROXY_URL = "http://localhost:8100"
local TEST_API_URL = "http://localhost:8101"

local _M = {}

_M.API_URL = TEST_API_URL
_M.KONG_BIN = KONG_BIN
_M.PROXY_URL = TEST_PROXY_URL
_M.STUB_GET_URL = TEST_PROXY_URL.."/request"
_M.STUB_POST_URL = TEST_PROXY_URL.."/request"
_M.DEFAULT_CONF_FILE = DEFAULT_CONF_FILE
_M.envs = {}

-- When dealing with another configuration file for a few tests, this allows to add
-- a factory/migrations/faker that are environment-specific to this new config.
function _M.add_env(conf_file)
  local env_configuration, env_factory = IO.load_configuration_and_dao(conf_file)
  _M.envs[conf_file] = {
    conf_file = conf_file,
    configuration = env_configuration,
    migrations = Migrations(env_factory),
    faker = Faker(env_factory),
    dao_factory = env_factory
  }
end

-- Retrieve environment-specific tools. If no conf_file passed,
-- default environment is TEST_CONF_FILE
function _M.get_env(conf_file)
  return _M.envs[conf_file] and _M.envs[conf_file] or _M.envs[TEST_CONF_FILE]
end

function _M.remove_env(conf_file)
  _M.envs[conf_file] = nil
end

--
-- OS and bin/kong helpers
--
function _M.start_kong(conf_file, skip_wait)
  local env = _M.get_env(conf_file)
  local result, exit_code = IO.os_execute(KONG_BIN.." start -c "..env.conf_file)

  if exit_code ~= 0 then
    error("spec_helper cannot start kong: "..result)
  end

  if not skip_wait then
    os.execute("while ! [ -f "..env.configuration.pid_file.." ]; do sleep 1; done")
  end

  return result, exit_code
end

function _M.stop_kong(conf_file)
  local env = _M.get_env(conf_file)
  local result, exit_code = IO.os_execute(KONG_BIN.." stop -c "..env.conf_file)

  if exit_code ~= 0 then
    error("spec_helper cannot stop kong: "..result)
  end

  os.execute("while [ -f "..env.configuration.pid_file.." ]; do sleep 1; done")

  return result, exit_code
end

--
-- DAO helpers
--
function _M.prepare_db(conf_file)
  local env = _M.get_env(conf_file)

  -- 1. Migrate our keyspace
  env.migrations:migrate(function(_, err)
    if err then
      error(err)
    end
  end)

  -- 2. Drop just to be sure if the test suite previously crashed for ex
  --    Otherwise we might try to insert already existing data.
  local err = env.dao_factory:drop()
  if err then
    error(err)
  end

  -- 3. Prepare
  local err = env.dao_factory:prepare()
  if err then
    error(err)
  end

  -- 4. Seed DB with our default data. This will throw any necessary error
  env.faker:seed()
end

function _M.drop_db(conf_file)
  local env = _M.get_env(conf_file)
  local err = env.dao_factory:drop()
  if err then
    error(err)
  end
end

function _M.seed_db(conf_file, random_amount)
  local env = _M.get_env(conf_file)
  env.faker:seed(random_amount)
end

function _M.reset_db(conf_file)
  local env = _M.get_env(conf_file)
  env.migrations:reset(function(_, err)
    if err then
      error(err)
    end
  end)
end

-- Add the default env to our spec_helper
_M.add_env(TEST_CONF_FILE)

return _M
