-- This file offers helpers for dao and integration tests (migrate, start kong, stop, faker...)
-- It is built so that it only needs to be required at the beginning of any spec file.
-- It supports other environments by passing a configuration file.

local IO = require "kong.tools.io"
local Faker = require "kong.tools.faker"
local Migrations = require "kong.tools.migrations"
local Threads = require "llthreads2.ex"

require "kong.tools.ngx_stub"

local _M = {}

-- Constants
local TEST_PROXY_PORT=8100
local TEST_PROXY_URL = "http://localhost:"..tostring(TEST_PROXY_PORT)
local TEST_PROXY_SSL_URL = "https://localhost:8543"
_M.API_URL = "http://localhost:8101"
_M.KONG_BIN = "bin/kong"
_M.PROXY_URL = TEST_PROXY_URL
_M.STUB_GET_URL = TEST_PROXY_URL.."/request"
_M.STUB_GET_SSL_URL = TEST_PROXY_SSL_URL.."/request"
_M.STUB_POST_URL = TEST_PROXY_URL.."/request"
_M.TEST_CONF_FILE = "kong_TEST.yml"
_M.DEFAULT_CONF_FILE = "kong.yml"
_M.TEST_PROXY_PORT = TEST_PROXY_PORT
_M.envs = {}

-- When dealing with another configuration file for a few tests, this allows to add
-- a factory/migrations/faker that are environment-specific to this new config.
function _M.add_env(conf_file)
  local env_configuration, env_factory = IO.load_configuration_and_dao(conf_file)
  _M.envs[conf_file] = {
    configuration = env_configuration,
    dao_factory = env_factory,
    migrations = Migrations(env_factory),
    conf_file = conf_file,
    faker = Faker(env_factory)
  }
end

-- Retrieve environment-specific tools. If no conf_file passed,
-- default environment is TEST_CONF_FILE
function _M.get_env(conf_file)
  return _M.envs[conf_file] and _M.envs[conf_file] or _M.envs[_M.TEST_CONF_FILE]
end

function _M.remove_env(conf_file)
  _M.envs[conf_file] = nil
end

--
-- OS and bin/kong helpers
--
local function kong_bin(signal, conf_file)
  local env = _M.get_env(conf_file)
  local result, exit_code = IO.os_execute(_M.KONG_BIN.." "..signal.." -c "..env.conf_file)

  if exit_code ~= 0 then
    error("spec_helper cannot "..signal.." kong: \n"..result)
  end

  return result, exit_code
end


function _M.start_kong(conf_file, skip_wait)
  local result, exit_code = kong_bin("start", conf_file, skip_wait)
  if not skip_wait then
    local env = _M.get_env(conf_file)
    os.execute("while ! [ -f "..env.configuration.pid_file.." ]; do sleep 0.5; done")
  end
  return result, exit_code
end

function _M.stop_kong(conf_file)
  return kong_bin("stop", conf_file)
end

function _M.restart_kong(conf_file)
  return kong_bin("restart", conf_file)
end

function _M.reload_kong(conf_file)
  return kong_bin("reload", conf_file)
end

function _M.quit_kong(conf_file)
  return kong_bin("quit", conf_file)
end

--
-- TCP/UDP server helpers
--

-- Starts a TCP server
-- @param `port`    The port where the server will be listening to
-- @return `thread` A thread object
function _M.start_tcp_server(port, ...)
  local thread = Threads.new({
    function(port)
      local socket = require "socket"
      local server = assert(socket.bind("*", port))
      local client = server:accept()
      local line, err = client:receive()
      if not err then client:send(line .. "\n") end
      client:close()
      return line
    end;
  }, port)

  thread:start(...)
  return thread
end


-- Starts a HTTP server
-- @param `port`    The port where the server will be listening to
-- @return `thread` A thread object
function _M.start_http_server(port, ...)
  local thread = Threads.new({
    function(port)
      local socket = require "socket"
      local server = assert(socket.bind("*", port))
      local client = server:accept()
      local lines = {}
      local count = 1
      local line, err = nil, nil
      while true do
        line, err = client:receive()
        if not err then
          lines[count] = line
          line = nil
          if count == 7 then
            client:send("ok" .. "\n")
            break
          end
          count = count + 1;
        end
       end
       client:close()
       return lines
      end;
  }, port)

  thread:start(...)
  return thread
end

-- Starts a UDP server
-- @param `port`    The port where the server will be listening to
-- @return `thread` A thread object
function _M.start_udp_server(port, ...)
  local thread = Threads.new({
    function(port)
      local socket = require("socket")
      local udp = socket.udp()
      udp:setsockname("*", port)
      local data = udp:receivefrom()
      return data
    end;
  }, port)

  thread:start(...)
  return thread
end

--
-- General Utils
--

-- Parses an SSL certificate returned by LuaSec
function _M.parse_cert(cert)
  local result = {}
  for _,v in ipairs(cert:issuer()) do
    result[v.name] = v.value
  end
  return result
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

  -- 2. Drop to run tests on a clean DB
  _M.drop_db(conf_file)
end

function _M.drop_db(conf_file)
  local env = _M.get_env(conf_file)
  local err = env.dao_factory:drop()
  if err then
    error(err)
  end
end

function _M.seed_db(random_amount, conf_file)
  local env = _M.get_env(conf_file)
  return env.faker:seed(random_amount)
end

function _M.insert_fixtures(fixtures, conf_file)
  local env = _M.get_env(conf_file)
  return env.faker:insert_from_table(fixtures)
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
_M.add_env(_M.TEST_CONF_FILE)

return _M
