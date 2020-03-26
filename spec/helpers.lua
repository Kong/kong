------------------------------------------------------------------
-- Collection of utilities to help testing Kong features and plugins.
--
-- @copyright Copyright 2016-2020 Kong Inc. All rights reserved.
-- @license [Apache 2.0](https://opensource.org/licenses/Apache-2.0)
-- @module spec.helpers

local BIN_PATH = "bin/kong"
local TEST_CONF_PATH = os.getenv("KONG_SPEC_TEST_CONF_PATH") or "spec/kong_tests.conf"
local CUSTOM_PLUGIN_PATH = "./spec/fixtures/custom_plugins/?.lua"
local DNS_MOCK_LUA_PATH = "./spec/fixtures/mocks/lua-resty-dns/?.lua"
local GO_PLUGIN_PATH = "./spec/fixtures/go"
local MOCK_UPSTREAM_PROTOCOL = "http"
local MOCK_UPSTREAM_SSL_PROTOCOL = "https"
local MOCK_UPSTREAM_HOST = "127.0.0.1"
local MOCK_UPSTREAM_HOSTNAME = "localhost"
local MOCK_UPSTREAM_PORT = 15555
local MOCK_UPSTREAM_SSL_PORT = 15556
local MOCK_UPSTREAM_STREAM_PORT = 15557
local MOCK_UPSTREAM_STREAM_SSL_PORT = 15558
local MOCK_GRPC_UPSTREAM_PROTO_PATH = "./spec/fixtures/grpc/hello.proto"
local BLACKHOLE_HOST = "10.255.255.255"

local consumers_schema_def = require "kong.db.schema.entities.consumers"
local services_schema_def = require "kong.db.schema.entities.services"
local plugins_schema_def = require "kong.db.schema.entities.plugins"
local routes_schema_def = require "kong.db.schema.entities.routes"
local prefix_handler = require "kong.cmd.utils.prefix_handler"
local dc_blueprints = require "spec.fixtures.dc_blueprints"
local conf_loader = require "kong.conf_loader"
local kong_global = require "kong.global"
local Blueprints = require "spec.fixtures.blueprints"
local pl_stringx = require "pl.stringx"
local constants = require "kong.constants"
local pl_tablex = require "pl.tablex"
local pl_utils = require "pl.utils"
local pl_path = require "pl.path"
local pl_file = require "pl.file"
local version = require "version"
local pl_dir = require "pl.dir"
local pl_Set = require "pl.Set"
local Schema = require "kong.db.schema"
local Entity = require "kong.db.schema.entity"
local cjson = require "cjson.safe"
local utils = require "kong.tools.utils"
local http = require "resty.http"
local nginx_signals = require "kong.cmd.utils.nginx_signals"
local log = require "kong.cmd.utils.log"
local DB = require "kong.db"
local ffi = require "ffi"


ffi.cdef [[
  int setenv(const char *name, const char *value, int overwrite);
  int unsetenv(const char *name);
]]


log.set_lvl(log.levels.quiet) -- disable stdout logs in tests

-- Add to package path so dao helpers can insert custom plugins
-- (while running from the busted environment)
package.path = CUSTOM_PLUGIN_PATH .. ";" .. package.path

--- Returns the OpenResty version.
-- Extract the current OpenResty version in use and returns
-- a numerical representation of it.
-- Ex: `1.11.2.2` -> `11122`
-- @name openresty_ver_num
local function openresty_ver_num()
  local nginx_bin = assert(nginx_signals.find_nginx_bin())
  local _, _, _, stderr = pl_utils.executeex(string.format("%s -V", nginx_bin))

  local a, b, c, d = string.match(stderr or "", "openresty/(%d+)%.(%d+)%.(%d+)%.(%d+)")
  if not a then
    error("could not execute 'nginx -V': " .. stderr)
  end

  return tonumber(a .. b .. c .. d)
end

--- Unindent a multi-line string for proper indenting in
-- square brackets.
-- @name unindent
-- @usage
-- local u = helpers.unindent
--
-- u[[
--     hello world
--     foo bar
-- ]]
--
-- -- will return: "hello world\nfoo bar"
local function unindent(str, concat_newlines, spaced_newlines)
  str = string.match(str, "(.-%S*)%s*$")
  if not str then
    return ""
  end

  local level  = math.huge
  local prefix = ""
  local len

  str = str:match("^%s") and "\n" .. str or str
  for pref in str:gmatch("\n(%s+)") do
    len = #prefix

    if len < level then
      level  = len
      prefix = pref
    end
  end

  local repl = concat_newlines and "" or "\n"
  repl = spaced_newlines and " " or repl

  return (str:gsub("^\n%s*", ""):gsub("\n" .. prefix, repl):gsub("\n$", ""):gsub("\\r", "\r"))
end


--- Set an environment variable
-- @name setenv
-- @param env (string) name of the environment variable
-- @param value the value to set
-- @return true on success, false otherwise
local function setenv(env, value)
  return ffi.C.setenv(env, value, 1) == 0
end


--- Unset an environment variable
-- @name setenv
-- @param env (string) name of the environment variable
-- @return true on success, false otherwise
local function unsetenv(env)
  return ffi.C.unsetenv(env) == 0
end


--- Write a yaml file.
-- @name make_yaml_file
-- @param content (string) the yaml string to write to the file
-- @param filename (optional) if not provided, a temp name will be created
-- @return filename of the file written
local function make_yaml_file(content, filename)
  if not filename then
    filename = os.tmpname()
    os.rename(filename, filename .. ".yml")
    filename = filename .. ".yml"
  end
  local fd = assert(io.open(filename, "w"))
  assert(fd:write(unindent(content)))
  assert(fd:write("\n")) -- ensure last line ends in newline
  assert(fd:close())
  return filename
end


---------------
-- Conf and DAO
---------------
local conf = assert(conf_loader(TEST_CONF_PATH))

_G.kong = kong_global.new()
kong_global.init_pdk(_G.kong, conf, nil) -- nil: latest PDK
kong_global.set_phase(kong, kong_global.phases.access)

local db = assert(DB.new(conf))
assert(db:init_connector())
db.plugins:load_plugin_schemas(conf.loaded_plugins)
local blueprints = assert(Blueprints.new(db))
local dcbp
local config_yml

--- Iterator over DB strategies.
-- @name each_strategy
-- @param strategies (optional string array) explicit list of strategies to use,
-- defaults to `{ "postgres", "cassandra" }`.
-- @usage
-- -- repeat all tests for each strategy
-- for _, strategy_name in helpers.each_strategy() do
--   describe("my test set [#" .. strategy .. "]", function()
--
--     -- add your tests here
--
--   end)
-- end
local each_strategy do
  local default_strategies = {"postgres", "cassandra"}
  local env_var = os.getenv("KONG_DATABASE")
  if env_var then
    default_strategies = { env_var }
  end
  local available_strategies = pl_Set(default_strategies)

  local function iter(strategies, i)
    i = i + 1
    local strategy = strategies[i]
    if strategy then
      return i, strategy
    end
  end

  each_strategy = function(strategies)
    if not strategies then
      return iter, default_strategies, 0
    end

    for i = #strategies, 1, -1 do
      if not available_strategies[strategies[i]] then
        table.remove(strategies, i)
      end
    end
    return iter, strategies, 0
  end
end

local function truncate_tables(db, tables)
  if not tables then
    return
  end

  for _, t in ipairs(tables) do
    if db[t] and db[t].schema and not db[t].schema.legacy then
      db[t]:truncate()
    end
  end
end

local function bootstrap_database(db)
  local schema_state = assert(db:schema_state())
  if schema_state.needs_bootstrap then
    assert(db:schema_bootstrap())
  end

  if schema_state.new_migrations then
    assert(db:run_migrations(schema_state.new_migrations, {
      run_up = true,
      run_teardown = true,
    }))
  end
end

--- Gets the database utility helpers and prepares the database for a testrun.
-- This will a.o. bootstrap the datastore and truncate the existing data that
-- migth be in it. The BluePrint returned can be used to create test entities
-- in the database.
-- @name get_db_utils
-- @param strategy (optional) the database strategy to use, will default to the
-- strategy in the test configuration.
-- @param tables (optional) tables to truncate, this can be used to accelarate
-- tests if only a few tables are used. By default all tables will be truncated.
-- @param plugins (optional) array of plugins to mark as loaded. Since kong will load all the bundled plugins by default, this is useful for mostly for marking custom plugins as loaded.
-- @return BluePrint, DB
-- @usage
-- local PLUGIN_NAME = "my_fancy_plugin"
-- local bp = helpers.get_db_utils("postgres", nil, { PLUGIN_NAME })
--
-- -- Inject a test route. No need to create a service, there is a default
-- -- service which will echo the request.
-- local route1 = bp.routes:insert({
--   hosts = { "test1.com" },
-- })
-- -- add the plugin to test to the route we created
-- bp.plugins:insert {
--   name = PLUGIN_NAME,
--   route = { id = route1.id },
--   config = {},
-- }
local function get_db_utils(strategy, tables, plugins)
  strategy = strategy or conf.database
  if tables ~= nil and type(tables) ~= "table" then
    error("arg #2 must be a list of tables to truncate", 2)
  end
  if plugins ~= nil and type(plugins) ~= "table" then
    error("arg #3 must be a list of plugins to enable", 2)
  end

  if plugins then
    for _, plugin in ipairs(plugins) do
      conf.loaded_plugins[plugin] = true
    end
  end

  -- DAO (DB module)
  local db = assert(DB.new(conf, strategy))
  assert(db:init_connector())

  bootstrap_database(db)

  do
    local database = conf.database
    conf.database = strategy
    conf.database = database
  end

  db:truncate("plugins")
  assert(db.plugins:load_plugin_schemas(conf.loaded_plugins))

  -- cleanup the tags table, since it will be hacky and
  -- not necessary to implement "truncate trigger" in Cassandra
  db:truncate("tags")

  -- cleanup new DB tables
  if not tables then
    assert(db:truncate())

  else
    truncate_tables(db, tables)
  end

  -- blueprints
  local bp
  if strategy ~= "off" then
    bp = assert(Blueprints.new(db))
    dcbp = nil
  else
    bp = assert(dc_blueprints.new(db))
    dcbp = bp
  end

  if plugins then
    for _, plugin in ipairs(plugins) do
      conf.loaded_plugins[plugin] = false
    end
  end

  _G.kong.db = db

  return bp, db
end

--- Gets the ml_cache instance.
-- @name get_cache
-- @param db the database object
-- @return ml_cache instance
local function get_cache(db)
  local worker_events = assert(kong_global.init_worker_events())
  local cluster_events = assert(kong_global.init_cluster_events(conf, db))
  local cache = assert(kong_global.init_cache(conf,
                                              cluster_events,
                                              worker_events
                                              ))
  return cache
end

-----------------
-- Custom helpers
-----------------
local resty_http_proxy_mt = {}

local pack = function(...) return { n = select("#", ...), ... } end
local unpack = function(t) return unpack(t, 1, t.n) end

--- Prints all returned parameters.
-- Simple debugging aid, it will pass all received parameters, hence will not
-- influence the flow of the code. See also `fail`.
-- @name intercept
-- @see fail
-- @usage -- modify
-- local a,b = some_func(c,d)
-- -- into
-- local a,b = intercept(some_func(c,d))
local function intercept(...)
  local args = pack(...)
  print(require("pl.pretty").write(args))
  return unpack(args)
end


-- Prepopulate Schema's cache
Schema.new(consumers_schema_def)
Schema.new(services_schema_def)
Schema.new(routes_schema_def)

local plugins_schema = assert(Entity.new(plugins_schema_def))


--- Validate a plugin configuration against a plugin schema.
-- @name validate_plugin_config_schema
-- @param config The configuration to validate. This is not the full schema,
-- only the `config` sub-object needs to be passed.
-- @param schema_def The schema definition
-- @return the validated schema, or nil+error
local function validate_plugin_config_schema(config, schema_def)
  assert(plugins_schema:new_subschema(schema_def.name, schema_def))
  local entity = {
    id = utils.uuid(),
    name = schema_def.name,
    config = config
  }
  local entity_to_insert, err = plugins_schema:process_auto_fields(entity, "insert")
  if err then
    return nil, err
  end
  local _, err = plugins_schema:validate_insert(entity_to_insert)
  if err then return
    nil, err
  end
  return entity_to_insert
end


-- Case insensitive lookup function, returns the value and the original key. Or
-- if not found nil and the search key
-- @usage -- sample usage
-- local test = { SoMeKeY = 10 }
-- print(lookup(test, "somekey"))  --> 10, "SoMeKeY"
-- print(lookup(test, "NotFound")) --> nil, "NotFound"
local function lookup(t, k)
  local ok = k
  if type(k) ~= "string" then
    return t[k], k
  else
    k = k:lower()
  end
  for key, value in pairs(t) do
    if tostring(key):lower() == k then
      return value, key
    end
  end
  return nil, ok
end


--- Waits until a specific condition is met.
-- The check function will repeatedly be called (with a fixed interval), until
-- the condition is met, or the
-- timeout value is exceeded.
-- @name wait_until
-- @param f check function that should return `truthy` when the condition has
-- been met
-- @param timeout (optional) maximum time to wait after which an error is
-- thrown, defaults to 5.
-- @return nothing. It returns when the condition is met, or throws an error
-- when it times out.
-- @usage -- wait 10 seconds for a file "myfilename" to appear
-- helpers.wait_until(function() return file_exist("myfilename") end, 10)
local function wait_until(f, timeout, step)
  if type(f) ~= "function" then
    error("arg #1 must be a function", 2)
  end

  if timeout ~= nil and type(timeout) ~= "number" then
    error("arg #2 must be a number", 2)
  end

  if step ~= nil and type(step) ~= "number" then
    error("arg #3 must be a number", 2)
  end

  ngx.update_time()

  timeout = timeout or 5
  step = step or 0.05

  local tstart = ngx.time()
  local texp = tstart + timeout
  local ok, res, err

  repeat
    ok, res, err = pcall(f)
    ngx.sleep(step)
    ngx.update_time()
  until not ok or res or ngx.time() >= texp

  if not ok then
    -- report error from `f`, such as assert gone wrong
    error(tostring(res), 2)
  elseif not res and err then
    -- report a failure for `f` to meet its condition
    -- and eventually an error return value which could be the cause
    error("wait_until() timeout: " .. tostring(err) .. " (after delay: " .. timeout .. "s)", 2)
  elseif not res then
    -- report a failure for `f` to meet its condition
    error("wait_until() timeout (after delay " .. timeout .. "s)", 2)
  end
end


local admin_client -- forward declaration

--- Waits for invalidation of a cached key by polling the mgt-api
-- and waiting for a 404 response.
-- @name wait_for_invalidation
-- @param key (string) the cache-key to check
-- @param timeout (optional) in seconds (for default see `wait_until`).
local function wait_for_invalidation(key, timeout)
  -- TODO: this code is not used, but is duplicated all over the codebase!
  -- search codebase for "/cache/" endpoint
  local api_client = admin_client()
  wait_until(function()
    local res = api_client:get("/cache/" .. key)
    res:read_body()
    return res.status == 404
  end, timeout)
end


--- http_client.
-- An http-client class to perform requests.
--
-- * Based on [lua-resty-http](https://github.com/pintsized/lua-resty-http) but
-- with some modifications
--
-- * Additional convenience methods will be injected for the following methods;
-- "get", "post", "put", "patch", "delete". Each of these methods comes with a
-- built-in assert. The signature of the functions is `client:get(path, opts)`.
--
-- * Body will be formatted according to the "Content-Type" header, see `http_client:send`.
--
-- * Query parameters will be added, see `http_client:send`.
--
-- @section http_client
-- @usage
-- -- example usage of the client
-- local client = helpers.get_proxy_client()
-- -- no need to check for `nil+err` since it is already wrapped in an assert
--
-- local opts = {
--   headers = {
--     ["My-Header"] = "my header value"
--   }
-- }
-- local result = client:get("/services/foo", opts)
-- -- the 'get' is wrapped in an assert, so again no need to check for `nil+err`


--- Send a http request.
-- Based on [lua-resty-http](https://github.com/pintsized/lua-resty-http).
--
-- * If `opts.body` is a table and "Content-Type" header contains
-- `application/json`, `www-form-urlencoded`, or `multipart/form-data`, then it
-- will automatically encode the body according to the content type.
--
-- * If `opts.query` is a table, a query string will be constructed from it and
-- appended to the request path (assuming none is already present).
--
-- * instead of this generic function there are also shortcut functions available
-- for every method, eg. `client:get`, `client:post`, etc. See `http_client`.
--
-- @name http_client:send
-- @param opts table with options. See [lua-resty-http](https://github.com/pintsized/lua-resty-http)
function resty_http_proxy_mt:send(opts)
  local cjson = require "cjson"
  local utils = require "kong.tools.utils"

  opts = opts or {}

  -- build body
  local headers = opts.headers or {}
  local content_type, content_type_name = lookup(headers, "Content-Type")
  content_type = content_type or ""
  local t_body_table = type(opts.body) == "table"
  if string.find(content_type, "application/json") and t_body_table then
    opts.body = cjson.encode(opts.body)
  elseif string.find(content_type, "www-form-urlencoded", nil, true) and t_body_table then
    opts.body = utils.encode_args(opts.body, true, opts.no_array_indexes)
  elseif string.find(content_type, "multipart/form-data", nil, true) and t_body_table then
    local form = opts.body
    local boundary = "8fd84e9444e3946c"
    local body = ""

    for k, v in pairs(form) do
      body = body .. "--" .. boundary .. "\r\nContent-Disposition: form-data; name=\"" .. k .. "\"\r\n\r\n" .. tostring(v) .. "\r\n"
    end

    if body ~= "" then
      body = body .. "--" .. boundary .. "--\r\n"
    end

    local clength = lookup(headers, "content-length")
    if not clength then
      headers["content-length"] = #body
    end

    if not content_type:find("boundary=") then
      headers[content_type_name] = content_type .. "; boundary=" .. boundary
    end

    opts.body = body
  end

  -- build querystring (assumes none is currently in 'opts.path')
  if type(opts.query) == "table" then
    local qs = utils.encode_args(opts.query)
    opts.path = opts.path .. "?" .. qs
    opts.query = nil
  end

  local res, err = self:request(opts)
  if res then
    -- wrap the read_body() so it caches the result and can be called multiple
    -- times
    local reader = res.read_body
    res.read_body = function(self)
      if not self._cached_body and not self._cached_error then
        self._cached_body, self._cached_error = reader(self)
      end
      return self._cached_body, self._cached_error
    end
  end

  return res, err
end

-- Implements http_client:get("path", [options]), as well as post, put, etc.
-- These methods are equivalent to calling http_client:send, but are shorter
-- They also come with a built-in assert
for _, method_name in ipairs({"get", "post", "put", "patch", "delete"}) do
  resty_http_proxy_mt[method_name] = function(self, path, options)
    local full_options = kong.table.merge({ method = method_name:upper(), path = path}, options)
    return assert(self:send(full_options))
  end
end

function resty_http_proxy_mt:__index(k)
  local f = rawget(resty_http_proxy_mt, k)
  if f then
    return f
  end

  return self.client[k]
end


--- Creates a http client.
-- Instead of using this client, you'll probably want to use the pre-configured
-- clients available as `proxy_client`, `admin_client`, etc. because these come
-- pre-configured and connected to the underlying Kong test instance.
--
-- @name http_client
-- @param host hostname to connect to
-- @param port port to connect to
-- @param timeout in seconds
-- @return http client
-- @see http_client:send
-- @see proxy_client
-- @see proxy_ssl_client
-- @see admin_client
-- @see admin_ssl_client
local function http_client(host, port, timeout)
  timeout = timeout or 10000
  local client = assert(http.new())
  assert(client:connect(host, port), "Could not connect to " .. host .. ":" .. port)
  client:set_timeout(timeout)
  return setmetatable({
    client = client
  }, resty_http_proxy_mt)
end


--- Returns the proxy port.
-- @name get_proxy_port
-- @param ssl (boolean) if `true` returns the ssl port
-- @param http2 (boolean) if `true` returns the http2 port
local function get_proxy_port(ssl, http2)
  if ssl == nil then ssl = false end
  for _, entry in ipairs(conf.proxy_listeners) do
    if entry.ssl == ssl and (http2 == nil or entry.http2 == http2) then
      return entry.port
    end
  end
  error("No proxy port found for ssl=" .. tostring(ssl), 2)
end


--- Returns the proxy ip.
-- @name get_proxy_ip
-- @param ssl (boolean) if `true` returns the ssl ip address
-- @param http2 (boolean) if `true` returns the http2 ip address
local function get_proxy_ip(ssl, http2)
  if ssl == nil then ssl = false end
  for _, entry in ipairs(conf.proxy_listeners) do
    if entry.ssl == ssl and (http2 == nil or entry.http2 == http2) then
      return entry.ip
    end
  end
  error("No proxy ip found for ssl=" .. tostring(ssl), 2)
end


--- returns a pre-configured `http_client` for the Kong proxy port.
-- @name proxy_client
-- @param timeout (optional, number) the timeout to use
local function proxy_client(timeout)
  local proxy_ip = get_proxy_ip(false)
  local proxy_port = get_proxy_port(false)
  assert(proxy_ip, "No http-proxy found in the configuration")
  return http_client(proxy_ip, proxy_port, timeout or 60000)
end


--- returns a pre-configured `http_client` for the Kong SSL proxy port.
-- @name proxy_ssl_client
-- @param timeout (optional, number) the timeout to use
-- @param sni (optional, string) the sni to use
local function proxy_ssl_client(timeout, sni)
  local proxy_ip = get_proxy_ip(true, true)
  local proxy_port = get_proxy_port(true, true)
  assert(proxy_ip, "No https-proxy found in the configuration")
  local client = http_client(proxy_ip, proxy_port, timeout or 60000)
  assert(client:ssl_handshake(nil, sni, false)) -- explicit no-verify
  return client
end


--- returns a pre-configured `http_client` for the Kong admin port.
-- @name admin_client
-- @param timeout (optional, number) the timeout to use
-- @param forced_port (optional, number) if provided will override the port in
-- the Kong configuration with this port
function admin_client(timeout, forced_port)
  local admin_ip, admin_port
  for _, entry in ipairs(conf.admin_listeners) do
    if entry.ssl == false then
      admin_ip = entry.ip
      admin_port = entry.port
    end
  end
  assert(admin_ip, "No http-admin found in the configuration")
  return http_client(admin_ip, forced_port or admin_port, timeout or 60000)
end

--- returns a pre-configured `http_client` for the Kong admin SSL port.
-- @name admin_ssl_client
-- @param timeout (optional, number) the timeout to use
local function admin_ssl_client(timeout)
  local admin_ip, admin_port
  for _, entry in ipairs(conf.proxy_listeners) do
    if entry.ssl == true then
      admin_ip = entry.ip
      admin_port = entry.port
    end
  end
  assert(admin_ip, "No https-admin found in the configuration")
  local client = http_client(admin_ip, admin_port, timeout or 60000)
  assert(client:ssl_handshake())
  return client
end


----------------
-- HTTP2 and GRPC clients
-- @section Shell-helpers


-- Generate grpcurl flags from a table of `flag-value`. If `value` is not a
-- string, value is ignored and `flag` is passed as is.
local function gen_grpcurl_opts(opts_t)
  local opts_l = {}

  for opt, val in pairs(opts_t) do
    if val ~= false then
      opts_l[#opts_l + 1] = opt .. " " .. (type(val) == "string" and val or "")
    end
  end

  return table.concat(opts_l, " ")
end


--- Creates an HTTP/2 client, based on the lua-http library.
-- @name http2_client
-- @param host hostname to connect to
-- @param port port to connect to
-- @param tls boolean indicating whether to establish a tls session
-- @return http2 client
local function http2_client(host, port, tls)
  local host = assert(host)
  local port = assert(port)
  tls = tls or false

  local request = require "http.request"
  local req = request.new_from_uri({
    scheme = tls and "https" or "http",
    host = host,
    port = port,
  })
  req.version = 2
  req.tls = tls

  if tls then
    local http_tls = require "http.tls"
    local openssl_ctx = require "openssl.ssl.context"
    local n_ctx = http_tls.new_client_context()
    n_ctx:setVerify(openssl_ctx.VERIFY_NONE)
    req.ctx = n_ctx
  end

  local meta = getmetatable(req) or {}

  meta.__call = function(req, opts)
    local headers = opts and opts.headers
    local timeout = opts and opts.timeout

    for k, v in pairs(headers or {}) do
      req.headers:upsert(k, v)
    end

    local headers, stream = req:go(timeout)
    local body = stream:get_body_as_string()
    return body, headers
  end

  return setmetatable(req, meta)
end


--- returns a pre-configured cleartext `http2_client` for the Kong proxy port.
-- @name proxy_client_h2c
-- @return http2 client
local function proxy_client_h2c()
  local proxy_ip = get_proxy_ip(false, true)
  local proxy_port = get_proxy_port(false, true)
  assert(proxy_ip, "No http-proxy found in the configuration")
  return http2_client(proxy_ip, proxy_port)
end


--- returns a pre-configured TLS `http2_client` for the Kong SSL proxy port.
-- @name proxy_client_h2
-- @return http2 client
local function proxy_client_h2()
  local proxy_ip = get_proxy_ip(true, true)
  local proxy_port = get_proxy_port(true, true)
  assert(proxy_ip, "No https-proxy found in the configuration")
  return http2_client(proxy_ip, proxy_port, true)
end

local exec -- forward declaration

--- Creates a gRPC client, based on the grpcurl CLI.
-- @name grpc_client
-- @param host hostname to connect to
-- @param port port to connect to
-- @param opts table with options supported by grpcurl
-- @return grpc client
local function grpc_client(host, port, opts)
  local host = assert(host)
  local port = assert(tostring(port))

  opts = opts or {}
  if not opts["-proto"] then
    opts["-proto"] = MOCK_GRPC_UPSTREAM_PROTO_PATH
  end

  return setmetatable({
    opts = opts,
    cmd_template = string.format("bin/grpcurl %%s %s:%s %%s", host, port)

  }, {
    __call = function(t, args)
      local service = assert(args.service)
      local body = args.body

      local t_body = type(body)
      if t_body ~= "nil" then
        if t_body == "table" then
          body = cjson.encode(body)
        end

        args.opts["-d"] = string.format("'%s'", body)
      end

      local opts = gen_grpcurl_opts(pl_tablex.merge(t.opts, args.opts, true))
      local ok, err, out = exec(string.format(t.cmd_template, opts, service))

      if ok then
        return ok, out
      else
        return nil, err
      end
    end
  })
end


--- returns a pre-configured `grpc_client` for the Kong proxy port.
-- @name proxy_client_grpc
-- @param host hostname to connect to
-- @param port port to connect to
-- @return grpc client
local function proxy_client_grpc(host, port)
  local proxy_ip = host or get_proxy_ip(false, true)
  local proxy_port = port or get_proxy_port(false, true)
  assert(proxy_ip, "No http-proxy found in the configuration")
  return grpc_client(proxy_ip, proxy_port, {["-plaintext"] = true})
end

--- returns a pre-configured `grpc_client` for the Kong SSL proxy port.
-- @name proxy_client_grpcs
-- @param host hostname to connect to
-- @param port port to connect to
-- @return grpc client
local function proxy_client_grpcs(host, port)
  local proxy_ip = host or get_proxy_ip(true, true)
  local proxy_port = port or get_proxy_port(true, true)
  assert(proxy_ip, "No https-proxy found in the configuration")
  return grpc_client(proxy_ip, proxy_port, {["-insecure"] = true})
end


---
-- TCP/UDP server helpers
--
-- @section servers


--- Starts a local TCP server.
-- Accepts a single connection (or multiple, if given `opts.requests`)
-- and then closes, echoing what was received (last read, in case
-- of multiple requests).
--
--
-- Options:
--
-- * `opts.timeout`: time after which the server exits, defaults to 360 seconds.
--
-- * `opts.requests`: the number of requests to accept, before exiting. Default 1.
--
-- * `opts.tls`: boolean, make it a ssl server if truthy.
--
-- * `opts.prefix`: string, a prefix to add to the echoed data received.
-- @name tcp_server
-- @param port (number) The port where the server will be listening on
-- @param opts (table) options defining the server's behavior
-- @return A thread object (from the `llthreads2` Lua package)
-- @see kill_tcp_server
local function tcp_server(port, opts)
  local threads = require "llthreads2.ex"
  opts = opts or {}
  local thread = threads.new({
    function(port, opts)
      local socket = require "socket"
      local server = assert(socket.tcp())
      server:settimeout(opts.timeout or 360)
      assert(server:setoption("reuseaddr", true))
      assert(server:bind("*", port))
      assert(server:listen())
      local line
      local oks, fails = 0, 0
      local handshake_done = false
      local n = opts.requests or 1
      for _ = 1, n + 1 do
        local client, err
        if opts.timeout then
          client, err = server:accept()
          if err == "timeout" then
            line = "timeout"
            break

          else
            assert(client, err)
          end

        else
          client = assert(server:accept())
        end

        if opts.tls and handshake_done then
          local ssl = require "ssl"
          local params = {
            mode = "server",
            protocol = "any",
            key = "spec/fixtures/kong_spec.key",
            certificate = "spec/fixtures/kong_spec.crt",
          }

          client = ssl.wrap(client, params)
          client:dohandshake()
        end

        line, err = client:receive()
        if err == "closed" then
          fails = fails + 1

        else
          if not handshake_done then
            assert(line == "\\START")
            client:send("\\OK\n")
            handshake_done = true

          else
            if line == "@DIE@" then
              client:send(string.format("%d:%d\n", oks, fails))
              client:close()
              break
            end

            oks = oks + 1

            client:send((opts.prefix or "") .. line .. "\n")
          end

          client:close()
        end
      end
      server:close()
      return line
    end
  }, port, opts)

  local thr = thread:start()

  -- not necessary for correctness because we do the handshake,
  -- but avoids harmless "connection error" messages in the wait loop
  -- in case the client is ready before the server below.
  ngx.sleep(0.001)

  local sock = ngx.socket.tcp()
  sock:settimeout(0.01)
  while true do
    if sock:connect("localhost", port) then
      sock:send("\\START\n")
      local ok = sock:receive()
      sock:close()
      if ok == "\\OK" then
        break
      end
    end
  end
  sock:close()

  return thr
end


--- Stops a local TCP server.
-- A server previously created with `tcp_server` can be stopped prematurely by
-- calling this function.
-- @name kill_tcp_server
-- @param port the port the TCP server is listening on.
-- @return oks, fails; the number of successes and failures processed by the server
-- @see tcp_server
local function kill_tcp_server(port)
  local sock = ngx.socket.tcp()
  assert(sock:connect("localhost", port))
  assert(sock:send("@DIE@\n"))
  local str = assert(sock:receive())
  assert(sock:close())
  local oks, fails = str:match("(%d+):(%d+)")
  return tonumber(oks), tonumber(fails)
end


--- Starts a local HTTP server.
-- Accepts a single connection and then closes. Sends a 200 ok, 'Connection:
-- close' response.
-- If the request received has path `/delay` then the response will be delayed
-- by 2 seconds.
-- @name http_server
-- @param `port` The port the server will be listening on
-- @return A thread object (from the `llthreads2` Lua package)
local function http_server(port, ...)
  local threads = require "llthreads2.ex"
  local thread = threads.new({
    function(port)
      local socket = require "socket"
      local server = assert(socket.tcp())
      assert(server:setoption('reuseaddr', true))
      assert(server:bind("*", port))
      assert(server:listen())
      local client = assert(server:accept())

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
        ngx.sleep(2)
      end

      if err then
        server:close()
        error(err)
      end

      client:send("HTTP/1.1 200 OK\r\nConnection: close\r\n\r\n")
      client:close()
      server:close()
      return lines
    end
  }, port)

  return thread:start(...)
end


--- Starts a local UDP server.
-- Accepts a single connection, reading once and then closes
-- @name udp_server
-- @param `port` The port the server will be listening on
-- @param `n` The number of packets that will be read
-- @param `timeout` Timeout per read
-- @return A thread object (from the `llthreads2` Lua package)
local function udp_server(port, n, timeout)
  local threads = require "llthreads2.ex"

  local thread = threads.new({
    function(port, n, timeout)
      local socket = require "socket"
      local server = assert(socket.udp())
      server:settimeout(timeout or 360)
      server:setoption("reuseaddr", true)
      server:setsockname("127.0.0.1", port)
      local err
      local data = {}
      local handshake_done = false
      local i = 0
      while i < n do
        local pkt, rport
        pkt, err, rport = server:receivefrom()
        if not pkt then
          break
        end
        if pkt == "KONG_UDP_HELLO" then
          if not handshake_done then
            handshake_done = true
            server:sendto("KONG_UDP_READY", "127.0.0.1", rport)
          end
        else
          i = i + 1
          data[i] = pkt
        end
      end
      server:close()
      return (n > 1 and data or data[1]), err
    end
  }, port or MOCK_UPSTREAM_PORT, n or 1, timeout)
  thread:start()

  local socket = require "socket"
  local handshake = socket.udp()
  handshake:settimeout(0.01)
  handshake:setsockname("127.0.0.1", 0)
  while true do
    handshake:sendto("KONG_UDP_HELLO", "127.0.0.1", port)
    local data = handshake:receive()
    if data == "KONG_UDP_READY" then
      break
    end
  end
  handshake:close()

  return thread
end


local function mock_reports_server(opts)
  local localhost = "127.0.0.1"
  local threads = require "llthreads2.ex"
  local server_port = constants.REPORTS.STATS_PORT
  opts = opts or {}

  local thread = threads.new({
    function(port, host, opts)
      local socket = require "socket"
      local server = assert(socket.tcp())
      server:settimeout(360)
      assert(server:setoption("reuseaddr", true))
      local counter = 0
      while not server:bind(host, port) do
        counter = counter + 1
        if counter > 5 then
          error('could not bind successfully')
        end
        socket.sleep(1)
      end
      assert(server:listen())
      local data = {}
      local handshake_done = false
      local n = opts.requests or math.huge
      for _ = 1, n + 1 do
        local client = assert(server:accept())

        if opts.tls and handshake_done then
          local ssl = require "ssl"
          local params = {
            mode = "server",
            protocol = "any",
            key = "spec/fixtures/kong_spec.key",
            certificate = "spec/fixtures/kong_spec.crt",
          }

          client = ssl.wrap(client, params)
          client:dohandshake()
        end

        local line, err = client:receive()
        if err ~= "closed" then
          if not handshake_done then
            assert(line == "\\START")
            client:send("\\OK\n")
            handshake_done = true

          else
            if line == "@DIE@" then
              client:close()
              break
            end

            table.insert(data, line)
          end

          client:close()
        end
      end
      server:close()

      return data
    end
  }, server_port, localhost, opts)

  thread:start()

  -- not necessary for correctness because we do the handshake,
  -- but avoids harmless "connection error" messages in the wait loop
  -- in case the client is ready before the server below.
  ngx.sleep(0.001)

  local sock = ngx.socket.tcp()
  sock:settimeout(0.01)
  while true do
    if not thread:alive() then
      error('the reports thread died')
    elseif sock:connect(localhost, server_port) then
      sock:send("\\START\n")
      local ok = sock:receive()
      sock:close()
      if ok == "\\OK" then
        break
      end
    end
  end
  sock:close()

  return {
    stop = function()
      local skt = assert(ngx.socket.tcp())
      sock:settimeout(0.01)
      skt:connect(localhost, server_port)
      skt:send("@DIE@\n")
      skt:close()

      return thread:join()
    end
  }
end


--------------------
-- Custom assertions
--
-- @section assertions

local say = require "say"
local luassert = require "luassert.assert"


--- Generic modifier "response".
-- Will set a "response" value in the assertion state, so following
-- assertions will operate on the value set.
-- @name response
-- @param response_obj results from `http_client:send` function (or any of the
-- shortcuts `client:get`, `client:post`, etc).
-- @usage
-- local res = client:get("/request", { .. request options here ..})
-- local response_length = assert.response(res).has.header("Content-Length")
local function modifier_response(state, arguments, level)
  assert(arguments.n > 0,
        "response modifier requires a response object as argument")

  local res = arguments[1]

  assert(type(res) == "table" and type(res.read_body) == "function",
         "response modifier requires a response object as argument, got: " .. tostring(res))

  rawset(state, "kong_response", res)
  rawset(state, "kong_request", nil)

  return state
end
luassert:register("modifier", "response", modifier_response)


--- Generic modifier "request".
-- Will set a "request" value in the assertion state, so following
-- assertions will operate on the value set.
--
-- The request must be inside a 'response' from the `mock_upstream`. If a request
-- is send to the `mock_upstream` endpoint `"/request"`, it will echo the request
-- received in the body of the response.
-- @name request
-- @param response_obj results from `http_client:send` function (or any of the
-- shortcuts `client:get`, `client:post`, etc).
-- @usage
-- local res = client:post("/request", {
--               headers = { ["Content-Type"] = "application/json" },
--               body = { hello = "world" },
--             })
-- local request_length = assert.request(res).has.header("Content-Length")
local function modifier_request(state, arguments, level)
  local generic = "The assertion 'request' modifier takes a http response"
                .. " object as input to decode the json-body returned by"
                .. " mock_upstream, to retrieve the proxied request."

  local res = arguments[1]

  assert(type(res) == "table" and type(res.read_body) == "function",
         "Expected a http response object, got '" .. tostring(res) .. "'. " .. generic)

  local body, request, err
  body = assert(res:read_body())
  request, err = cjson.decode(body)

  assert(request, "Expected the http response object to have a json encoded body,"
                  .. " but decoding gave error '" .. tostring(err) .. "'. Obtained body: "
                  .. body .. "\n." .. generic)


  if lookup((res.headers or {}),"X-Powered-By") ~= "mock_upstream" then
    error("Could not determine the response to be from mock_upstream")
  end

  rawset(state, "kong_request", request)
  rawset(state, "kong_response", nil)

  return state
end
luassert:register("modifier", "request", modifier_request)


--- Generic fail assertion. A convenience function for debugging tests, always
-- fails. It will output the values it was called with as a table, with an `n`
-- field to indicate the number of arguments received. See also `intercept`.
-- @name fail
-- @param ... any set of parameters to be displayed with the failure
-- @see intercept
-- @usage
-- assert.fail(some, value)
local function fail(state, args)
  local out = {}
  for k,v in pairs(args) do out[k] = v end
  args[1] = out
  args.n = 1
  return false
end
say:set("assertion.fail.negative", [[
Fail assertion was called with the following parameters (formatted as a table);
%s
]])
luassert:register("assertion", "fail", fail,
                  "assertion.fail.negative",
                  "assertion.fail.negative")


--- Assertion to check whether a value lives in an array.
-- @name contains
-- @param expected The value to search for
-- @param array The array to search for the value
-- @param pattern (optional) If truthy, then `expected` is matched as a Lua string
-- pattern
-- @return the array index at which the value was found
-- @usage
-- local arr = { "one", "three" }
-- local i = assert.contains("one", arr)        --> passes; i == 1
-- local i = assert.contains("two", arr)        --> fails
-- local i = assert.contains("ee$", arr, true)  --> passes; i == 2
local function contains(state, args)
  local expected, arr, pattern = unpack(args)
  local found
  for i = 1, #arr do
    if (pattern and string.match(arr[i], expected)) or arr[i] == expected then
      found = i
      break
    end
  end
  return found ~= nil, {found}
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


--- Assertion to check the status-code of a http response.
-- @name status
-- @param expected the expected status code
-- @param response (optional) results from `http_client:send` function,
-- alternatively use `response`.
-- @return the response body as a string, for a json body see `jsonbody`.
-- @usage
-- local res = assert(client:send { .. your request params here .. })
-- local body = assert.has.status(200, res)             -- or alternativly
-- local body = assert.response(res).has.status(200)    -- does the same
local function res_status(state, args)
  assert(not rawget(state, "kong_request"),
         "Cannot check statuscode against a request object,"
       .. " only against a response object")

  local expected = args[1]
  local res = args[2] or rawget(state, "kong_response")

  assert(type(expected) == "number",
         "Expected response code must be a number value. Got: " .. tostring(expected))
  assert(type(res) == "table" and type(res.read_body) == "function",
         "Expected a http_client response. Got: " .. tostring(res))

  if expected ~= res.status then
    local body, err = res:read_body()
    if not body then body = "Error reading body: " .. err end
    table.insert(args, 1, pl_stringx.strip(body))
    table.insert(args, 1, res.status)
    table.insert(args, 1, expected)
    args.n = 3

    if res.status == 500 then
      -- on HTTP 500, we can try to read the server's error logs
      -- for debugging purposes (very useful for travis)
      local str = pl_file.read(conf.nginx_err_logs)
      if not str then
        return false -- no err logs to read in this prefix
      end

      local str_t = pl_stringx.splitlines(str)
      local first_line = #str_t - math.min(60, #str_t) + 1
      local msg_t = {"\nError logs (" .. conf.nginx_err_logs .. "):"}
      for i = first_line, #str_t do
        msg_t[#msg_t+1] = str_t[i]
      end

      table.insert(args, 4, table.concat(msg_t, "\n"))
      args.n = 4
    end

    return false
  else
    local body, err = res:read_body()
    local output = body
    if not output then output = "Error reading body: " .. err end
    output = pl_stringx.strip(output)
    table.insert(args, 1, output)
    table.insert(args, 1, res.status)
    table.insert(args, 1, expected)
    args.n = 3
    return true, {pl_stringx.strip(body)}
  end
end
say:set("assertion.res_status.negative", [[
Invalid response status code.
Status expected:
%s
Status received:
%s
Body:
%s
%s]])
say:set("assertion.res_status.positive", [[
Invalid response status code.
Status not expected:
%s
Status received:
%s
Body:
%s
%s]])
luassert:register("assertion", "status", res_status,
                  "assertion.res_status.negative", "assertion.res_status.positive")
luassert:register("assertion", "res_status", res_status,
                  "assertion.res_status.negative", "assertion.res_status.positive")


--- Checks and returns a json body of an http response/request. Only checks
-- validity of the json, does not check appropriate headers. Setting the target
-- to check can be done through the `request` and `response` modifiers.
--
-- For a non-json body, see the `status` assertion.
-- @name jsonbody
-- @return the decoded json as a table
-- @usage
-- local res = assert(client:send { .. your request params here .. })
-- local json_table = assert.response(res).has.jsonbody()
local function jsonbody(state, args)
  assert(args[1] == nil and rawget(state, "kong_request") or rawget(state, "kong_response"),
         "the `jsonbody` assertion does not take parameters. " ..
         "Use the `response`/`require` modifiers to set the target to operate on")

  if rawget(state, "kong_response") then
    local body = rawget(state, "kong_response"):read_body()
    local json, err = cjson.decode(body)
    if not json then
      table.insert(args, 1, "Error decoding: " .. tostring(err) .. "\nResponse body:" .. body)
      args.n = 1
      return false
    end
    return true, {json}

  else
    local r = rawget(state, "kong_request")
    if r.post_data
    and (r.post_data.kind == "json" or r.post_data.kind == "json (error)")
    and r.post_data.params
    then
      local pd = r.post_data
      return true, { { params = pd.params, data = pd.text, error = pd.error, kind = pd.kind } }

    else
      error("No json data found in the request")
    end
  end
end
say:set("assertion.jsonbody.negative", [[
Expected response body to contain valid json. Got:
%s
]])
say:set("assertion.jsonbody.positive", [[
Expected response body to not contain valid json. Got:
%s
]])
luassert:register("assertion", "jsonbody", jsonbody,
                  "assertion.jsonbody.negative",
                  "assertion.jsonbody.positive")


--- Asserts that a named header in a `headers` subtable exists.
-- Header name comparison is done case-insensitive.
-- @name header
-- @param name header name to look for (case insensitive).
-- @see response
-- @see request
-- @return value of the header
-- @usage
-- local res = client:get("/request", { .. request options here ..})
-- local resp_header_value = assert.response(res).has.header("Content-Length")
-- local req_header_value = assert.request(res).has.header("Content-Length")
local function res_header(state, args)
  local header = args[1]
  local res = args[2] or rawget(state, "kong_request") or rawget(state, "kong_response")
  assert(type(res) == "table" and type(res.headers) == "table",
         "'header' assertion input does not contain a 'headers' subtable")
  local value = lookup(res.headers, header)
  table.insert(args, 1, res.headers)
  table.insert(args, 1, header)
  args.n = 2
  if not value then
    return false
  end
  return true, {value}
end
say:set("assertion.res_header.negative", [[
Expected header:
%s
But it was not found in:
%s
]])
say:set("assertion.res_header.positive", [[
Did not expected header:
%s
But it was found in:
%s
]])
luassert:register("assertion", "header", res_header,
                  "assertion.res_header.negative",
                  "assertion.res_header.positive")


---
-- An assertion to look for a query parameter in a query string.
-- Parameter name comparison is done case-insensitive.
-- @name queryparam
-- @param name name of the query parameter to look up (case insensitive)
-- @return value of the parameter
-- @usage
-- local res = client:get("/request", {
--               query = { hello = "world" },
--             })
-- local param_value = assert.request(res).has.queryparam("hello")
local function req_query_param(state, args)
  local param = args[1]
  local req = rawget(state, "kong_request")
  assert(req, "'queryparam' assertion only works with a request object")
  local params
  if type(req.uri_args) == "table" then
    params = req.uri_args

  else
    error("No query parameters found in request object")
  end
  local value = lookup(params, param)
  table.insert(args, 1, params)
  table.insert(args, 1, param)
  args.n = 2
  if not value then
    return false
  end
  return true, {value}
end
say:set("assertion.req_query_param.negative", [[
Expected query parameter:
%s
But it was not found in:
%s
]])
say:set("assertion.req_query_param.positive", [[
Did not expected query parameter:
%s
But it was found in:
%s
]])
luassert:register("assertion", "queryparam", req_query_param,
                  "assertion.req_query_param.negative",
                  "assertion.req_query_param.positive")


---
-- Adds an assertion to look for a urlencoded form parameter in a request.
-- Parameter name comparison is done case-insensitive. Use the `request` modifier to set
-- the request to operate on.
-- @name formparam
-- @param name name of the form parameter to look up (case insensitive)
-- @return value of the parameter
-- @usage
-- local r = assert(proxy_client:post("/request", {
--   body    = {
--     hello = "world",
--   },
--   headers = {
--     host             = "mock_upstream",
--     ["Content-Type"] = "application/x-www-form-urlencoded",
--   },
-- })
-- local value = assert.request(r).has.formparam("hello")
-- assert.are.equal("world", value)
local function req_form_param(state, args)
  local param = args[1]
  local req = rawget(state, "kong_request")
  assert(req, "'formparam' assertion can only be used with a mock_upstream request object")

  local value
  if req.post_data
  and (req.post_data.kind == "form" or req.post_data.kind == "multipart-form")
  then
    value = lookup(req.post_data.params or {}, param)
  else
    error("Could not determine the request to be from either mock_upstream")
  end

  table.insert(args, 1, req)
  table.insert(args, 1, param)
  args.n = 2
  if not value then
    return false
  end
  return true, {value}
end
say:set("assertion.req_form_param.negative", [[
Expected url encoded form parameter:
%s
But it was not found in request:
%s
]])
say:set("assertion.req_form_param.positive", [[
Did not expected url encoded form parameter:
%s
But it was found in request:
%s
]])
luassert:register("assertion", "formparam", req_form_param,
                  "assertion.req_form_param.negative",
                  "assertion.req_form_param.positive")


---
-- Assertion to ensure a value is greater than a base value.
-- @name is_gt
-- @param base the base value to compare against
-- @param value the value that must be greater than the base value
local function is_gt(state, arguments)
  local expected = arguments[1]
  local value = arguments[2]

  arguments[1] = value
  arguments[2] = expected

  return value > expected
end
say:set("assertion.gt.negative", [[
Given value (%s) should be greater than expected value (%s)
]])
say:set("assertion.gt.positive", [[
Given value (%s) should not be greater than expected value (%s)
]])
luassert:register("assertion", "gt", is_gt,
                  "assertion.gt.negative",
                  "assertion.gt.positive")

--- Generic modifier "certificate".
-- Will set a "certificate" value in the assertion state, so following
-- assertions will operate on the value set.
-- @name certificate
-- @param cert The cert text
-- @see cn
-- @usage
-- assert.certificate(cert).has.cn("ssl-example.com")
local function modifier_certificate(state, arguments, level)
  local generic = "The assertion 'certficate' modifier takes a cert text"
                .. " as input to validate certificate parameters"
                .. " against."
  local cert = arguments[1]
  assert(type(cert) == "string",
         "Expected a certificate text, got '" .. tostring(cert) .. "'. " .. generic)
  rawset(state, "kong_certificate", cert)
  return state
end
luassert:register("modifier", "certificate", modifier_certificate)

--- Assertion to check whether a CN is matched in an SSL cert.
-- @name cn
-- @param expected The CN value
-- @param cert The cert text
-- @return the CN found in the cert
-- @see certificate
-- @usage
-- assert.cn("ssl-example.com", cert)
--
-- -- alternative:
-- assert.certificate(cert).has.cn("ssl-example.com")
local function assert_cn(state, args)
  local expected = args[1]
  if args[2] and rawget(state, "kong_certificate") then
    error("assertion 'cn' takes either a 'certificate' modifier, or 2 parameters, not both")
  end
  local cert = args[2] or rawget(state, "kong_certificate")
  local cn = string.match(cert, "CN%s*=%s*([^%s,]+)")
  args[2] = cn or "(CN not found in certificate)"
  args.n = 2
  return cn == expected
end
say:set("assertion.cn.negative", [[
Expected certificate to have the given CN value.
Expected CN:
%s
Got instead:
%s
]])
say:set("assertion.cn.positive", [[
Expected certificate to not have the given CN value.
Expected CN to not be:
%s
Got instead:
%s
]])
luassert:register("assertion", "cn", assert_cn,
                  "assertion.cn.negative",
                  "assertion.cn.positive")


----------------
-- DNS-record mocking.
-- These function allow to create mock dns records that the test Kong instance
-- will use to resolve names. The created mocks are injected by the `start_kong`
-- function.
-- @usage
-- -- Create a new DNS mock and add some DNS records
-- local fixtures = {
--   dns_mock = helpers.dns_mock.new()
-- }
--
-- fixtures.dns_mock:SRV {
--   name = "my.srv.test.com",
--   target = "a.my.srv.test.com",
--   port = 80,
-- }
-- fixtures.dns_mock:SRV {
--   name = "my.srv.test.com",     -- adding same name again: record gets 2 entries!
--   target = "b.my.srv.test.com", -- a.my.srv.test.com and b.my.srv.test.com
--   port = 80,
-- }
-- fixtures.dns_mock:A {
--   name = "a.my.srv.test.com",
--   address = "127.0.0.1",
-- }
-- @section DNS-mocks


local dns_mock = {}
do
  dns_mock.__index = dns_mock
  dns_mock.__tostring = function(self)
    -- fill array to prevent json encoding errors
    for i = 1, 33 do
      self[i] = self[i] or {}
    end
    local json = assert(cjson.encode(self))
    return json
  end


  local TYPE_A, TYPE_AAAA, TYPE_CNAME, TYPE_SRV = 1, 28, 5, 33


  --- Creates a new DNS mock.
  -- @name dns_mock.new
  -- @return dns_mock object
  function dns_mock.new()
    return setmetatable({}, dns_mock)
  end


  --- Adds an SRV record to the DNS mock.
  -- Fields `name`, `target`, and `port` are required. Other fields get defaults:
  --
  -- * `weight`; 20
  -- * `ttl`; 600
  -- * `priority`; 20
  -- @param rec the mock DNS record to insert
  -- @return true
  function dns_mock:SRV(rec)
    if self == dns_mock then
      error("can't operate on the class, you must create an instance", 2)
    end
    if getmetatable(self or {}) ~= dns_mock then
      error("SRV method must be called using the colon notation", 2)
    end
    assert(rec, "Missing record parameter")
    local name = assert(rec.name, "No name field in SRV record")

    self[TYPE_SRV] = self[TYPE_SRV] or {}
    local query_answer = self[TYPE_SRV][name]
    if not query_answer then
      query_answer = {}
      self[TYPE_SRV][name] = query_answer
    end

    table.insert(query_answer, {
      type = TYPE_SRV,
      name = name,
      target = assert(rec.target, "No target field in SRV record"),
      port = assert(rec.port, "No port field in SRV record"),
      weight = rec.weight or 10,
      ttl = rec.ttl or 600,
      priority = rec.priority or 20,
      class = rec.class or 1
    })
    return true
  end


  --- Adds an A record to the DNS mock.
  -- Fields `name` and `address` are required. Other fields get defaults:
  --
  -- * `ttl`; 600
  -- @param rec the mock DNS record to insert
  -- @return true
  function dns_mock:A(rec)
    if self == dns_mock then
      error("can't operate on the class, you must create an instance", 2)
    end
    if getmetatable(self or {}) ~= dns_mock then
      error("A method must be called using the colon notation", 2)
    end
    assert(rec, "Missing record parameter")
    local name = assert(rec.name, "No name field in A record")

    self[TYPE_A] = self[TYPE_A] or {}
    local query_answer = self[TYPE_A][name]
    if not query_answer then
      query_answer = {}
      self[TYPE_A][name] = query_answer
    end

    table.insert(query_answer, {
      type = TYPE_A,
      name = name,
      address = assert(rec.address, "No address field in A record"),
      ttl = rec.ttl or 600,
      class = rec.class or 1
    })
    return true
  end


  --- Adds an AAAA record to the DNS mock.
  -- Fields `name` and `address` are required. Other fields get defaults:
  --
  -- * `ttl`; 600
  -- @param rec the mock DNS record to insert
  -- @return true
  function dns_mock:AAAA(rec)
    if self == dns_mock then
      error("can't operate on the class, you must create an instance", 2)
    end
    if getmetatable(self or {}) ~= dns_mock then
      error("AAAA method must be called using the colon notation", 2)
    end
    assert(rec, "Missing record parameter")
    local name = assert(rec.name, "No name field in AAAA record")

    self[TYPE_AAAA] = self[TYPE_AAAA] or {}
    local query_answer = self[TYPE_AAAA][name]
    if not query_answer then
      query_answer = {}
      self[TYPE_AAAA][name] = query_answer
    end

    table.insert(query_answer, {
      type = TYPE_AAAA,
      name = name,
      address = assert(rec.address, "No address field in AAAA record"),
      ttl = rec.ttl or 600,
      class = rec.class or 1
    })
    return true
  end


  --- Adds a CNAME record to the DNS mock.
  -- Fields `name` and `cname` are required. Other fields get defaults:
  --
  -- * `ttl`; 600
  -- @param rec the mock DNS record to insert
  -- @return true
  function dns_mock:CNAME(rec)
    if self == dns_mock then
      error("can't operate on the class, you must create an instance", 2)
    end
    if getmetatable(self or {}) ~= dns_mock then
      error("CNAME method must be called using the colon notation", 2)
    end
    assert(rec, "Missing record parameter")
    local name = assert(rec.name, "No name field in CNAME record")

    self[TYPE_CNAME] = self[TYPE_CNAME] or {}
    local query_answer = self[TYPE_CNAME][name]
    if not query_answer then
      query_answer = {}
      self[TYPE_CNAME][name] = query_answer
    end

    table.insert(query_answer, {
      type = TYPE_CNAME,
      name = name,
      cname = assert(rec.cname, "No cname field in CNAME record"),
      ttl = rec.ttl or 600,
      class = rec.class or 1
    })
    return true
  end
end


----------------
-- Shell helpers
-- @section Shell-helpers

--- Execute a command.
-- Modified version of `pl.utils.executeex()` so the output can directly be
-- used on an assertion.
-- @name execute
-- @param cmd command string to execute
-- @param pl_returns (optional) boolean: if true, this function will
-- return the same values as Penlight's executeex.
-- @return if `pl_returns` is true, returns four return values
-- (ok, code, stdout, stderr); if `pl_returns` is false,
-- returns either (false, stderr) or (true, stderr, stdout).
function exec(cmd, pl_returns)
  local ok, code, stdout, stderr = pl_utils.executeex(cmd)
  if pl_returns then
    return ok, code, stdout, stderr
  end
  if not ok then
    stdout = nil -- don't return 3rd value if fail because of busted's `assert`
  end
  return ok, stderr, stdout
end


--- Execute a Kong command.
-- @name kong_exec
-- @param cmd Kong command to execute, eg. `start`, `stop`, etc.
-- @param env (optional) table with kong parameters to set as environment
-- variables, overriding the test config (each key will automatically be
-- prefixed with `KONG_` and be converted to uppercase)
-- @param pl_returns (optional) boolean: if true, this function will
-- return the same values as Penlight's `executeex`.
-- @param env_vars (optional) a string prepended to the command, so
-- that arbitrary environment variables may be passed
-- @return if `pl_returns` is true, returns four return values
-- (ok, code, stdout, stderr); if `pl_returns` is false,
-- returns either (false, stderr) or (true, stderr, stdout).
local function kong_exec(cmd, env, pl_returns, env_vars)
  cmd = cmd or ""
  env = env or {}

  -- Insert the Lua path to the custom-plugin fixtures
  do
    local function cleanup(t)
      if t then
        t = pl_stringx.strip(t)
        if t:sub(-1,-1) == ";" then
          t = t:sub(1, -2)
        end
      end
      return t ~= "" and t or nil
    end
    local paths = {}
    table.insert(paths, cleanup(CUSTOM_PLUGIN_PATH))
    table.insert(paths, cleanup(env.lua_package_path))
    table.insert(paths, cleanup(conf.lua_package_path))
    env.lua_package_path = table.concat(paths, ";")
    -- note; the nginx config template will add a final ";;", so no need to
    -- include that here
  end

  if not env.plugins then
    env.plugins = "bundled,dummy,cache,rewriter,error-handler-log," ..
                  "error-generator,error-generator-last," ..
                  "short-circuit"
  end

  -- build Kong environment variables
  env_vars = env_vars or ""
  for k, v in pairs(env) do
    env_vars = string.format("%s KONG_%s='%s'", env_vars, k:upper(), v)
  end

  return exec(env_vars .. " " .. BIN_PATH .. " " .. cmd, pl_returns)
end


--- Prepares the Kong environment.
-- Creates the working directory if it does not exist.
-- @param prefix (optional) path to the working directory, if omitted the test
-- configuration will be used
-- @name prepare_prefix
local function prepare_prefix(prefix)
  return pl_dir.makepath(prefix or conf.prefix)
end


--- Cleans the Kong environment.
-- Deletes the working directory if it exists.
-- @param prefix (optional) path to the working directory, if omitted the test
-- configuration will be used
-- @name clean_prefix
local function clean_prefix(prefix)
  prefix = prefix or conf.prefix
  if pl_path.exists(prefix) then
    pl_dir.rmtree(prefix)
  end
end


-- Reads the pid from a pid file and returns it, or nil + err
local function get_pid_from_file(pid_path)
  local pid
  local fd, err = io.open(pid_path)
  if not fd then
    return nil, err
  end

  pid = fd:read("*l")
  fd:close()

  return pid
end


-- Waits for the termination of a pid.
-- @param pid_path Filename of the pid file.
-- @param timeout (optional) in seconds, defaults to 10.
local function wait_pid(pid_path, timeout, is_retry)
  local pid = get_pid_from_file(pid_path)

  if pid then
    local max_time = ngx.now() + (timeout or 10)

    repeat
      if not pl_utils.execute("ps -p " .. pid .. " >/dev/null 2>&1") then
        return
      end
      -- still running, wait some more
      ngx.sleep(0.05)
    until ngx.now() >= max_time

    if is_retry then
      return
    end

    -- Timeout reached: kill with SIGKILL
    pl_utils.execute("kill -9 " .. pid .. " >/dev/null 2>&1")

    -- Sanity check: check pid again, but don't loop.
    wait_pid(pid_path, timeout, true)
  end
end


--- Return the actual configuration running at the given prefix.
-- It may differ from the default, as it may have been modified
-- by the `env` table given to start_kong.
-- @name get_running_conf
-- @param prefix The prefix path where the kong instance is running
-- @return The conf table of the running instance, or nil + error.
local function get_running_conf(prefix)
  local default_conf = conf_loader(nil, {prefix = prefix or conf.prefix})
  return conf_loader.load_config_file(default_conf.kong_env)
end


--- Return the actual Kong version the tests are running against.
-- See [version.lua](https://github.com/kong/version.lua) for the format. This
-- is mostly useful for testing plugins that should work with multiple Kong versions.
-- @name get_version
-- @return a `version` object
-- @usage
-- local version = require 'version'
-- if helpers.get_version() < version("0.15.0") then
--   -- do something
-- end
local function get_version()
  return version(select(3, assert(kong_exec("version"))))
end


local function render_fixtures(conf, env, prefix, fixtures)

  if fixtures and (fixtures.http_mock or fixtures.stream_mock) then
    -- prepare the prefix so we get the full config in the
    -- hidden `.kong_env` file, including test specified env vars etc
    assert(kong_exec("prepare --conf " .. conf, env))
    local render_config = assert(conf_loader(prefix .. "/.kong_env"))

    for _, mocktype in ipairs { "http_mock", "stream_mock" } do

      for filename, contents in pairs(fixtures[mocktype] or {}) do
        -- render the file using the full configuration
        contents = assert(prefix_handler.compile_conf(render_config, contents))

        -- write file to prefix
        filename = prefix .. "/" .. filename .. "." .. mocktype
        assert(pl_utils.writefile(filename, contents))
      end
    end
  end

  if fixtures and fixtures.dns_mock then
    -- write the mock records to the prefix
    assert(getmetatable(fixtures.dns_mock) == dns_mock,
           "expected dns_mock to be of a helpers.dns_mock class")
    assert(pl_utils.writefile(prefix .. "/dns_mock_records.json",
                              tostring(fixtures.dns_mock)))

    -- add the mock resolver to the path to ensure the records are loaded
    if env.lua_package_path then
      env.lua_package_path = DNS_MOCK_LUA_PATH .. ";" .. env.lua_package_path
    else
      env.lua_package_path = DNS_MOCK_LUA_PATH
    end
  else
    -- remove any old mocks if they exist
    os.remove(prefix .. "/dns_mock_records.json")
  end

  return true
end


local function build_go_plugins(path)
  for _, plugin_path in ipairs(pl_dir.getfiles(path, "*.go")) do
    local plugin_name = pl_path.basename(plugin_path):match("(.+).go")

    local ok, _, _, stderr = pl_utils.executeex(
      string.format("cd %s; go build -buildmode plugin -o %s %s",
      path, plugin_name .. ".so", plugin_name .. ".go")
    )
    assert(ok, stderr)
  end
end


--- Start the Kong instance to test against.
-- The fixtures passed to this function can be 3 types:
--
-- * DNS mocks
--
-- * Nginx server blocks to be inserted in the http module
--
-- * Nginx server blocks to be inserted in the stream module
-- @name start_kong
-- @param env table with Kong configuration parameters (and values)
-- @param tables list of database tables to truncate before starting
-- @param preserve_prefix (boolean) if truthy, the prefix will not be cleaned
-- before starting
-- @param fixtures tables with fixtures, dns, http and stream mocks.
-- @return return values from `execute`
-- @usage
-- -- example mocks
-- -- Create a new DNS mock and add some DNS records
-- local fixtures = {
--   http_mock = {},
--   stream_mock = {},
--   dns_mock = helpers.dns_mock.new()
-- }
--
-- fixtures.dns_mock:A {
--   name = "a.my.srv.test.com",
--   address = "127.0.0.1",
-- }
--
-- -- The blocks below will be rendered by the Kong template renderer, like other
-- -- custom Kong templates. Hence the `${{xxxx}}` values.
-- -- Multiple mocks can be added each under their own filename ("my_server_block" below)
-- fixtures.http_mock.my_server_block = [[
--      server {
--          server_name my_server;
--          listen 10001 ssl;
--
--          ssl_certificate ${{SSL_CERT}};
--          ssl_certificate_key ${{SSL_CERT_KEY}};
--          ssl_protocols TLSv1.1 TLSv1.2 TLSv1.3;
--
--          location ~ "/echobody" {
--            content_by_lua_block {
--              ngx.req.read_body()
--              local echo = ngx.req.get_body_data()
--              ngx.status = status
--              ngx.header["Content-Length"] = #echo + 1
--              ngx.say(echo)
--            }
--          }
--      }
--    ]]
--
-- fixtures.stream_mock.my_server_block = [[
--      server {
--        -- insert stream server config here
--      }
--    ]]
--
-- assert(helpers.start_kong( {database = "postgres"}, nil, nil, fixtures))
local function start_kong(env, tables, preserve_prefix, fixtures)
  if tables ~= nil and type(tables) ~= "table" then
    error("arg #2 must be a list of tables to truncate")
  end
  env = env or {}
  local prefix = env.prefix or conf.prefix

  -- go plugins are enabled
  --  set pluginserver dir (making sure it's in the PATH)
  --  compile fixture go plugins
  if env.go_plugins_dir then
    if env.go_plugins_dir == GO_PLUGIN_PATH then
      build_go_plugins(GO_PLUGIN_PATH)
    end

    if not env.go_pluginserver_exe and not os.getenv("KONG_GO_PLUGINSERVER_EXE") then
      local ok, _, pluginserver_path, _ = pl_utils.executeex(string.format("which go-pluginserver"))
      assert(ok, "did not find go-pluginserver in PATH")
      env.go_pluginserver_exe = pluginserver_path
    end
  end

  -- note: set env var "KONG_TEST_DONT_CLEAN" !! the "_TEST" will be dropped
  if not (preserve_prefix or os.getenv("KONG_DONT_CLEAN")) then
    clean_prefix(prefix)
  end

  local ok, err = prepare_prefix(prefix)
  if not ok then return nil, err end

  truncate_tables(db, tables)

  local nginx_conf = ""
  if env.nginx_conf then
    nginx_conf = " --nginx-conf " .. env.nginx_conf
  end

  if dcbp and not env.declarative_config then
    if not config_yml then
      config_yml = prefix .. "/config.yml"
      local cfg = dcbp.done()
      local declarative = require "kong.db.declarative"
      local ok, err = declarative.to_yaml_file(cfg, config_yml)
      if not ok then
        return nil, err
      end
    end
    env = utils.deep_copy(env)
    env.declarative_config = config_yml
  end

  assert(render_fixtures(TEST_CONF_PATH .. nginx_conf, env, prefix, fixtures))

  return kong_exec("start --conf " .. TEST_CONF_PATH .. nginx_conf, env)
end


-- Stop the Kong test instance.
-- @name stop_kong
-- @param prefix (optional) the prefix where the test instance runs, defaults to the test configuration.
-- @param preserve_prefix (boolean) if truthy, the prefix will not be deleted after stopping
-- @param preserve_dc
-- @return true or nil+err
local function stop_kong(prefix, preserve_prefix, preserve_dc)
  prefix = prefix or conf.prefix

  local running_conf, err = get_running_conf(prefix)
  if not running_conf then
    return nil, err
  end

  local pid, err = get_pid_from_file(running_conf.nginx_pid)
  if not pid then
    return nil, err
  end

  local ok, _, _, err = pl_utils.executeex("kill -TERM " .. pid)
  if not ok then
    return nil, err
  end

  wait_pid(running_conf.nginx_pid)

  -- note: set env var "KONG_TEST_DONT_CLEAN" !! the "_TEST" will be dropped
  if not (preserve_prefix or os.getenv("KONG_DONT_CLEAN")) then
    clean_prefix(prefix)
  end

  if not preserve_dc then
    config_yml = nil
  end

  return true
end


--- Restart Kong. Reusing declarative config when using `database=off`.
-- @name restart_kong
-- @param env see `start_kong`
-- @param tables see `start_kong`
-- @param fixtures see `start_kong`
-- @return true or nil+err
local function restart_kong(env, tables, fixtures)
  stop_kong(env.prefix, true, true)
  return start_kong(env, tables, true, fixtures)
end


----------------
-- Variables/constants
-- @section exported-fields


--- Below is a list of fields/constants exported on the `helpers` module table:
-- @table helpers
-- @field dir The [`pl.dir` module of Penlight](http://tieske.github.io/Penlight/libraries/pl.dir.html)
-- @field path The [`pl.path` module of Penlight](http://tieske.github.io/Penlight/libraries/pl.path.html)
-- @field file The [`pl.file` module of Penlight](http://tieske.github.io/Penlight/libraries/pl.file.html)
-- @field utils The [`pl.utils` module of Penlight](http://tieske.github.io/Penlight/libraries/pl.utils.html)
-- @field test_conf The Kong test configuration. See also `get_running_conf` which might be slightly different.
-- @field test_conf_path The configuration file in use.
-- @field mock_upstream_hostname
-- @field mock_upstream_protocol
-- @field mock_upstream_host
-- @field mock_upstream_port
-- @field mock_upstream_url Base url constructed from the components
-- @field mock_upstream_ssl_protocol
-- @field mock_upstream_ssl_host
-- @field mock_upstream_ssl_port
-- @field mock_upstream_ssl_url Base url constructed from the components
-- @field mock_upstream_stream_port
-- @field mock_upstream_stream_ssl_port
-- @field mock_grpc_upstream_proto_path
-- @field redis_host The hostname for a Redis instance if available. Port should be `6379`.

----------
-- Exposed
----------
-- @export
  return {
  -- Penlight
  dir = pl_dir,
  path = pl_path,
  file = pl_file,
  utils = pl_utils,

  -- Kong testing properties
  db = db,
  blueprints = blueprints,
  get_db_utils = get_db_utils,
  get_cache = get_cache,
  bootstrap_database = bootstrap_database,
  bin_path = BIN_PATH,
  test_conf = conf,
  test_conf_path = TEST_CONF_PATH,
  go_plugin_path = GO_PLUGIN_PATH,
  mock_upstream_hostname = MOCK_UPSTREAM_HOSTNAME,
  mock_upstream_protocol = MOCK_UPSTREAM_PROTOCOL,
  mock_upstream_host     = MOCK_UPSTREAM_HOST,
  mock_upstream_port     = MOCK_UPSTREAM_PORT,
  mock_upstream_url      = MOCK_UPSTREAM_PROTOCOL .. "://" ..
                           MOCK_UPSTREAM_HOST .. ':' ..
                           MOCK_UPSTREAM_PORT,

  mock_upstream_ssl_protocol = MOCK_UPSTREAM_SSL_PROTOCOL,
  mock_upstream_ssl_host     = MOCK_UPSTREAM_HOST,
  mock_upstream_ssl_port     = MOCK_UPSTREAM_SSL_PORT,
  mock_upstream_ssl_url      = MOCK_UPSTREAM_SSL_PROTOCOL .. "://" ..
                               MOCK_UPSTREAM_HOST .. ':' ..
                               MOCK_UPSTREAM_SSL_PORT,

  mock_upstream_stream_port     = MOCK_UPSTREAM_STREAM_PORT,
  mock_upstream_stream_ssl_port = MOCK_UPSTREAM_STREAM_SSL_PORT,
  mock_grpc_upstream_proto_path = MOCK_GRPC_UPSTREAM_PROTO_PATH,

  redis_host = os.getenv("KONG_SPEC_REDIS_HOST") or "127.0.0.1",

  blackhole_host = BLACKHOLE_HOST,

  -- Kong testing helpers
  execute = exec,
  dns_mock = dns_mock,
  kong_exec = kong_exec,
  get_version = get_version,
  get_running_conf = get_running_conf,
  http_client = http_client,
  grpc_client = grpc_client,
  http2_client = http2_client,
  wait_until = wait_until,
  wait_pid = wait_pid,
  tcp_server = tcp_server,
  udp_server = udp_server,
  kill_tcp_server = kill_tcp_server,
  http_server = http_server,
  mock_reports_server = mock_reports_server,
  get_proxy_ip = get_proxy_ip,
  get_proxy_port = get_proxy_port,
  proxy_client = proxy_client,
  proxy_client_grpc = proxy_client_grpc,
  proxy_client_grpcs = proxy_client_grpcs,
  proxy_client_h2c = proxy_client_h2c,
  proxy_client_h2 = proxy_client_h2,
  admin_client = admin_client,
  proxy_ssl_client = proxy_ssl_client,
  admin_ssl_client = admin_ssl_client,
  prepare_prefix = prepare_prefix,
  clean_prefix = clean_prefix,
  wait_for_invalidation = wait_for_invalidation,
  each_strategy = each_strategy,
  validate_plugin_config_schema = validate_plugin_config_schema,

  -- miscellaneous
  intercept = intercept,
  openresty_ver_num = openresty_ver_num(),
  unindent = unindent,
  make_yaml_file = make_yaml_file,
  setenv = setenv,
  unsetenv = unsetenv,

  -- launching Kong subprocesses
  start_kong = start_kong,
  stop_kong = stop_kong,
  restart_kong = restart_kong,

  -- Only use in CLI tests from spec/02-integration/01-cmd
  kill_all = function(prefix, timeout)
    local kill = require "kong.cmd.utils.kill"

    local running_conf = get_running_conf(prefix)
    if not running_conf then return end

    -- kill kong_tests.conf service
    local pid_path = running_conf.nginx_pid
    if pl_path.exists(pid_path) then
      kill.kill(pid_path, "-TERM")
      wait_pid(pid_path, timeout)
    end
  end,
  signal = function(prefix, signal, pid_path)
    local kill = require "kong.cmd.utils.kill"

    if not pid_path then
      local running_conf = get_running_conf(prefix)
      if not running_conf then
        error("no config file found at prefix: " .. prefix)
      end

      pid_path = running_conf.nginx_pid
    end

    return kill.kill(pid_path, signal)
  end,
}
