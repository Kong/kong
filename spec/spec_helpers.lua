-- This file offers helpers for dao and integration tests (migrate, start kong, stop, faker...)
-- It is built so that it only needs to be required at the beginning of any spec file.
-- It supports other environments by passing a configuration file.

local utils = require "kong.tools.utils"
local Faker = require "kong.tools.faker"
local Migrations = require "kong.tools.migrations"

-- Constants
local KONG_BIN = "bin/kong"
local TEST_CONF_FILE = "kong_TEST.yml"
local TEST_PROXY_URL = "http://localhost:8100"
local TEST_API_URL = "http://localhost:8101"

local _M = {}

_M.KONG_BIN = KONG_BIN
_M.PROXY_URL = TEST_PROXY_URL
_M.API_URL = TEST_API_URL
_M.STUB_GET_URL = TEST_PROXY_URL.."/request"
_M.STUB_POST_URL = TEST_PROXY_URL.."/request"
_M.envs = {}

-- When dealing with another configuration file for a few tests, this allows to add
-- a factory/migrations/faker that are environment-specific to this new config.
function _M.add_env(conf_file)
  local env_configuration, env_factory = utils.load_configuration_and_dao(conf_file)
  _M.envs[conf_file] = {
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
function _M.os_execute(command)
  local n = os.tmpname() -- get a temporary file name to store output
  local exit_code = os.execute(command.." > "..n.." 2>&1")
  local result = utils.read_file(n)
  os.remove(n)

  return result, exit_code / 256
end

function _M.start_kong(conf_file, skip_wait)
  local conf_file = conf_file and conf_file or TEST_CONF_FILE
  local result, exit_code = _M.os_execute(KONG_BIN.." -c "..conf_file.." start")

  if exit_code ~= 0 then
    error("spec_helper cannot start kong: "..result)
  end

  if not skip_wait then
    os.execute("while ! [ `pgrep nginx | grep -c -v grep` -gt 0 ]; do sleep 1; done")
  end

  return result, exit_code
end

function _M.stop_kong(conf_file)
  local conf_file = conf_file and conf_file or TEST_CONF_FILE
  local result, exit_code = _M.os_execute(KONG_BIN.." -c "..conf_file.." stop")

  if exit_code ~= 0 then
    error("spec_helper cannot stop kong: "..result)
  end

  os.execute("while [ `pgrep nginx | grep -c -v grep` -gt 0 ]; do sleep 1; done")
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

  -- 2. Prepare statements
  local err = env.dao_factory:prepare()
  if err then
    error(err)
  end

  -- 3. Seed DB with our default data. This will throw any necessary error
  env.faker:seed()
end

function _M.drop_db()
  local env = _M.get_env(conf_file)
  local err = env.dao_factory:drop()
  if err then
    error(err)
  end
end

function _M.seed_db(random_amount)
  local env = _M.get_env(conf_file)
  env.faker:seed(random_amount)
end

function _M.reset_db()
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
