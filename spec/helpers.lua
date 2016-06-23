local BIN_PATH = "bin/kong"
local TEST_CONF_PATH = "spec/kong_tests.conf"

local conf_loader = require "kong.conf_loader"
local DAOFactory = require "kong.dao.factory"
local pl_stringx = require "pl.stringx"
local pl_utils = require "pl.utils"
local pl_path = require "pl.path"
local pl_file = require "pl.file"
local pl_dir = require "pl.dir"
local http = require "resty.http"
local log = require "kong.cmd.utils.log"

log.set_lvl(log.levels.quiet) -- disable stdout logs in tests

---------------
-- Conf and DAO
---------------
local conf = assert(conf_loader(TEST_CONF_PATH))
local dao = DAOFactory(conf)
-- make sure migrations are up-to-date
--assert(dao:run_migrations())

-----------------
-- Custom helpers
-----------------
local resty_http_proxy_mt = {}

function resty_http_proxy_mt:send(opts)
  local cjson = require "cjson"
  local utils = require "kong.tools.utils"

  opts = opts or {}

  -- build body
  local headers = opts.headers or {}
  local content_type = headers["Content-Type"] or ""
  local t_body_table = type(opts.body) == "table"
  if string.find(content_type, "application/json") and t_body_table then
    opts.body = cjson.encode(opts.body)
  elseif string.find(content_type, "www-form-urlencoded", nil, true) and t_body_table then
    opts.body = utils.encode_args(opts.body, true) -- true: not % encoded
  end

  -- build querystring (assumes none is currently in 'opts.path')
  if type(opts.query) == "table" then
    local qs = utils.encode_args(opts.query)
    opts.path = opts.path.."?"..qs
    opts.query = nil
  end

  return self:request(opts)
end

function resty_http_proxy_mt:__index(k)
  local f = rawget(resty_http_proxy_mt, k)
  if f then
    return f
  end

  return self.client[k]
end

local function http_client(host, port, timeout)
  timeout = timeout or 10000
  local client = assert(http.new())
  assert(client:connect(host, port))
  client:set_timeout(timeout)
  return setmetatable({
    client = client
  }, resty_http_proxy_mt)
end

local function wait_until(f, timeout)
  if type(f) ~= "function" then
    error("arg #1 must be a function", 2)
  end

  timeout = timeout or 2
  local tstart = ngx.time()
  local texp, ok = tstart + timeout

  repeat
    ngx.sleep(0.2)
    ok = f()
  until ok or ngx.time() >= texp

  if not ok then
    error("wait_until() timeout", 2)
  end
end

local function udp_server(port)
  local threads = require "llthreads2.ex"

  local thread = threads.new({
    function(port)
      local socket = require "socket"
      local server = assert(socket.udp())
      server:settimeout(1)
      server:setoption("reuseaddr", true)
      server:setsockname("127.0.0.1", port)
      local data = server:receive()
      server:close()
      return data
    end
  }, port or 9999)

  thread:start()

  ngx.sleep(0.1)

  return thread
end

--------------------
-- Custom assertions
--------------------
local say = require "say"
local luassert = require "luassert.assert"

local function fail(state, args)
  args[1] = table.concat(args, " ")
  return false
end
say:set("assertion.fail.negative", "%s")
luassert:register("assertion", "fail", fail,
                  "assertion.fail.negative",
                  "assertion.fail.negative")

local function contains(state, args)
  local expected, arr = unpack(args)
  local found
  for i = 1, #arr do
    if arr[i] == expected then
      found = true
      break
    end
  end
  return found
end
say:set("assertion.contains.negative", [[
Expected array to contain element.
Expected to contain:
%s
]])
say:set("assertion.contains.positive", [[
Expected array to not contain element.
Expected to not contain:
%s
]])
luassert:register("assertion", "contains", contains,
                  "assertion.contains.negative",
                  "assertion.contains.positive")

local function res_status(state, args)
  local expected, res = unpack(args)
  if not res then
    table.insert(args, 1, "")
    table.insert(args, 1, "no response")
    table.insert(args, 1, expected)
    return false
  elseif expected ~= res.status then
    table.insert(args, 1, res:read_body())
    table.insert(args, 1, res.status)
    table.insert(args, 1, expected)
    return false
  end
  local body = pl_stringx.strip(res:read_body())
  return true, {body}
end
say:set("assertion.res_status.negative", [[
Invalid response status code.
Status expected:
%s
Status received:
%s
Body:
%s
]])
luassert:register("assertion", "res_status", res_status,
                  "assertion.res_status.negative")

----------------
-- Shell helpers
----------------
local function exec(...)
  local ok, _, stdout, stderr = pl_utils.executeex(...)
  if not ok then
    stdout = nil -- don't return 3rd value if fail because of busted's `assert`
  end
  return ok, stderr, stdout
end

local function kong_exec(cmd, env)
  cmd = cmd or ""
  env = env or {}

  local env_vars = ""
  for k, v in pairs(env) do
    env_vars = string.format("%s KONG_%s=%s", env_vars, k:upper(), v)
  end

  return exec(env_vars.." "..BIN_PATH.." "..cmd)
end

----------
-- Exposed
----------
return {
  -- Penlight
  dir = pl_dir,
  path = pl_path,
  file = pl_file,
  utils = pl_utils,

  -- Kong testing properties
  dao = dao,
  bin_path = BIN_PATH,
  test_conf = conf,
  test_conf_path = TEST_CONF_PATH,

  -- Kong testing helpers
  execute = exec,
  kong_exec = kong_exec,
  http_client = http_client,
  wait_until = wait_until,
  udp_server = udp_server,

  prepare_prefix = function(prefix)
    prefix = prefix or conf.prefix
    return pl_dir.makepath(prefix)
  end,
  clean_prefix = function(prefix)
    prefix = prefix or conf.prefix
    if pl_path.exists(prefix) then
      pl_dir.rmtree(prefix)
    end
  end,
  start_kong = function()
    return kong_exec("start --conf "..TEST_CONF_PATH)
  end,
  stop_kong = function()
    return kong_exec("stop --conf "..TEST_CONF_PATH)
  end,
  kill_all = function()
    dao:truncate_tables() -- truncate nodes table too
    return exec "pkill nginx; pkill serf; pkill dnsmasq"
  end
}
