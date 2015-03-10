local utils = require "kong.tools.utils"
local Faker = require "kong.tools.faker"
local Migrations = require "kong.tools.migrations"

-- Constants
local KONG_BIN = "bin/kong"
local TEST_CONF_FILE = "kong_TEST.yml"
local PROXY_URL = "http://localhost:8100"
local API_URL = "http://localhost:8101"

-- DB objects
local configuration, dao_factory = utils.load_configuration_and_dao(TEST_CONF_FILE)
local migrations = Migrations(dao_factory)
local faker = Faker(dao_factory)

local _M = {}

_M.CONF_FILE = TEST_CONF_FILE
_M.PROXY_URL = PROXY_URL
_M.API_URL = API_URL
_M.configuration = configuration
_M.dao_factory = dao_factory
_M.faker = faker

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
    os.execute("while ! [ `ps aux | grep nginx | grep -c -v grep` -gt 0 ]; do sleep 1; done")
  end

  return result, exit_code
end

function _M.stop_kong(conf_file)
  local conf_file = conf_file and conf_file or TEST_CONF_FILE
  local result, exit_code = _M.os_execute(KONG_BIN.." -c "..conf_file.." stop")

  if exit_code ~= 0 then
    error("spec_helper cannot stop kong: "..result)
  end

  os.execute("while [ `ps aux | grep nginx | grep -c -v grep` -gt 0 ]; do sleep 1; done")
end

function _M.prepare_db()
  -- 1. Migrate our keyspace
  migrations:migrate(function(_, err)
    if err then
      error(err)
    end
  end)

  -- 2. Prepare statements
  local err = dao_factory:prepare()
  if err then
    error(err)
  end

  -- 3. Seed DB with our default data. This will throw any necessary error
  faker:seed()
end

function _M.drop_db()
  local err = dao_factory:drop()
  if err then
    error(err)
  end
end

function _M.seed_db(random_amount)
  faker:seed(random_amount)
end

function _M.reset_db()
  migrations:reset(function(_, err)
    if err then
      error(err)
    end
  end)
end

return _M
