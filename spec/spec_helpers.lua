-- This file offers helpers for dao and integration tests (migrate, start kong, stop, faker...)
-- It is built so that it only needs to be required at the beginning of any spec file.
-- It supports other environments by passing a configuration file.

local IO = require "kong.tools.io"
local dao = require "kong.tools.dao_loader"
local Faker = require "kong.tools.faker"
local config = require "kong.tools.config_loader"
local Threads = require "llthreads2.ex"
local Migrations = require "kong.tools.migrations"

require "kong.tools.ngx_stub"

local _M = {}

-- Constants
local TEST_PROXY_PORT = 8100
local TEST_PROXY_URL = "http://localhost:"..tostring(TEST_PROXY_PORT)
local TEST_PROXY_SSL_URL = "https://localhost:8543"
_M.API_URL = "http://localhost:8101"
_M.KONG_BIN = "bin/kong"
_M.PROXY_URL = TEST_PROXY_URL
_M.PROXY_SSL_URL = TEST_PROXY_SSL_URL
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
  local env_configuration = config.load(conf_file)
  local env_factory = dao.load(env_configuration)
  _M.envs[conf_file] = {
    configuration = env_configuration,
    dao_factory = env_factory,
    migrations = Migrations(env_factory, env_configuration),
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
local function kong_bin(signal, conf_file, skip_wait)
  local env = _M.get_env(conf_file)
  local result, exit_code = IO.os_execute(_M.KONG_BIN.." "..signal.." -c "..env.conf_file)

  if exit_code ~= 0 then
    error("spec_helper cannot "..signal.." kong: \n"..result)
  end

  if signal == "start" and not skip_wait then
    os.execute("while ! [ -f "..env.configuration.pid_file.." ]; do sleep 0; done")
  elseif signal == "quit" or signal == "stop" then
    os.execute("while [ -f "..env.configuration.pid_file.." ]; do sleep 0; done")
  end

  return result, exit_code
end

for _, signal in ipairs({ "start", "stop", "restart", "reload", "quit" }) do
  _M[signal.."_kong"] = function(conf_file, skip_wait)
    return kong_bin(signal, conf_file, skip_wait)
  end
end

--
-- TCP/UDP server helpers
--

-- Finds an available port on the system
-- @param `exclude` An array with the ports to exclude
-- @return `number` The port number
function _M.find_port(exclude)
  local socket = require "socket"

  if not exclude then exclude = {} end

  -- Reserving ports to exclude
  local servers = {}
  for _, v in ipairs(exclude) do
    table.insert(servers, assert(socket.bind("*", v)))
  end

  -- Finding an available port
  local handle = io.popen([[(netstat  -atn | awk '{printf "%s\n%s\n", $4, $4}' | grep -oE '[0-9]*$'; seq 32768 61000) | sort -n | uniq -u]])
  local result = (handle:read("*a") .. "\n"):match("^(.-)\n")
  handle:close()

  -- Closing the opened servers
  for _, v in ipairs(servers) do
    v:close()
  end

  return tonumber(result)
end

-- Starts a TCP server, accepting a single connection and then closes
-- @param `port`    The port where the server will be listening to
-- @return `thread` A thread object
function _M.start_tcp_server(port, ...)
  local thread = Threads.new({
    function(port)
      local socket = require "socket"
      local server = assert(socket.tcp())
      assert(server:setoption('reuseaddr', true))
      assert(server:bind("*", port))
      assert(server:listen())
      local client = server:accept()
      local line, err = client:receive()
      if not err then client:send(line .. "\n") end
      client:close()
      server:close()
      return line
    end;
  }, port)

  return thread:start(...)
end


-- Starts a HTTP server, accepting a single connection and then closes
-- @param `port`    The port where the server will be listening to
-- @return `thread` A thread object
function _M.start_http_server(port, ...)
  local thread = Threads.new({
    function(port)
      local socket = require "socket"
      local server = assert(socket.tcp())
      assert(server:setoption('reuseaddr', true))
      assert(server:bind("*", port))
      assert(server:listen())
      local client = server:accept()

      local lines = {}
      local line, err
      while #lines < 7 do
        line, err = client:receive()
        if err then
          break
        else
          table.insert(lines, line)
        end
      end

      if #lines > 0 and lines[1] == "GET /delay HTTP/1.0" then
        os.execute("sleep 2")
      end

      if err then
        server:close()
        error(err)
      end

      client:send("HTTP/1.1 200 OK\r\nConnection: close\r\n\r\n")
      client:close()
      server:close()
      return lines
    end;
  }, port)

  return thread:start(...)
end

-- Starts a UDP server, accepting a single connection and then closes
-- @param `port`    The port where the server will be listening to
-- @return `thread` A thread object
function _M.start_udp_server(port, ...)
  local thread = Threads.new({
    function(port)
      local socket = require("socket")
      local udp = socket.udp()
      udp:setoption('reuseaddr', true)
      udp:setsockname("*", port)
      local data = udp:receivefrom()
      udp:close()
      return data
    end;
  }, port)

  return thread:start(...)
end

--
-- DAO helpers
--
function _M.prepare_db(conf_file)
  local env = _M.get_env(conf_file)

  -- 1. Migrate our keyspace
  local err = env.migrations:run_all_migrations()
  if err then
    error(err)
  end

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

function _M.seed_db(amount, conf_file)
  local env = _M.get_env(conf_file)
  return env.faker:seed(amount)
end

function _M.insert_fixtures(fixtures, conf_file)
  local env = _M.get_env(conf_file)
  return env.faker:insert_from_table(fixtures)
end

-- Add the default env to our spec_helper
_M.add_env(_M.TEST_CONF_FILE)

return _M
