-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

------------------------------------------------------------------
-- Collection of utilities to help testing Kong features and plugins.
--
-- @copyright Copyright 2016-2022 Kong Inc. All rights reserved.
-- @license [Apache 2.0](https://opensource.org/licenses/Apache-2.0)
-- @module spec.helpers


local PLUGINS_LIST


local consumers_schema_def = require "kong.db.schema.entities.consumers"
local services_schema_def = require "kong.db.schema.entities.services"
local plugins_schema_def = require "kong.db.schema.entities.plugins"
local routes_schema_def = require "kong.db.schema.entities.routes"
local prefix_handler = require "kong.cmd.utils.prefix_handler"
local dc_blueprints = require "spec.fixtures.dc_blueprints"
local conf_loader = require "kong.conf_loader"
local kong_global = require "kong.global"
local Blueprints = require "spec.fixtures.blueprints"
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
local kong_table = require "kong.tools.table"
local http = require "resty.http"
local log = require "kong.cmd.utils.log"
local DB = require "kong.db"
local invoke_plugin = require "kong.enterprise_edition.invoke_plugin"
local portal_router = require "kong.portal.router"
local rbac = require "kong.rbac"
local ssl = require "ngx.ssl"
local ws_client = require "resty.websocket.client"
local table_clone = require "table.clone"
local https_server = require "spec.fixtures.https_server"
local stress_generator = require "spec.fixtures.stress_generator"
local lfs = require "lfs"
local luassert = require "luassert.assert"
local uuid = require("kong.tools.uuid").uuid

-- XXX EE
local dist_constants = require "kong.enterprise_edition.distributions_constants"
local kong_vitals = require "kong.vitals"
-- EE

local http_new = http.new


local reload_module = require("spec.details.module").reload


-- reload some modules when env or _G changes
local CONSTANTS = reload_module("spec.details.constants")
local shell = reload_module("spec.details.shell")
local misc = reload_module("spec.details.misc")
local grpc = reload_module("spec.details.grpc")
local dns_mock = reload_module("spec.details.dns")
local asserts = reload_module("spec.details.asserts") -- luacheck: ignore
local server = reload_module("spec.details.server")


local conf = shell.conf
local exec = shell.exec
local kong_exec = shell.kong_exec


log.set_lvl(log.levels.quiet) -- disable stdout logs in tests

-- Add to package path so dao helpers can insert custom plugins
-- (while running from the busted environment)
do
  local paths = {}
  table.insert(paths, os.getenv("KONG_LUA_PACKAGE_PATH"))
  table.insert(paths, CONSTANTS.CUSTOM_PLUGIN_PATH)
  -- XXX EE custom plugins for enterprise tests
  table.insert(paths, CONSTANTS.CUSTOM_EE_PLUGIN_PATH)
  table.insert(paths, CONSTANTS.CUSTOM_VAULT_PATH)
  table.insert(paths, package.path)
  package.path = table.concat(paths, ";")
end


local get_available_port
do
  local USED_PORTS = {}

  function get_available_port()
    for _i = 1, 10 do
      local port = math.random(10000, 30000)

      if not USED_PORTS[port] then
          USED_PORTS[port] = true

          local ok = shell.run("netstat -lnt | grep \":" .. port .. "\" > /dev/null", nil, 0)

          if not ok then
            -- return code of 1 means `grep` did not found the listening port
            return port

          else
            print("Port " .. port .. " is occupied, trying another one")
          end
      end
    end

    error("Could not find an available port after 10 tries")
  end
end


---------------
-- Conf and DAO
---------------
_G.kong = kong_global.new()
kong_global.init_pdk(_G.kong, conf)
ngx.ctx.KONG_PHASE = kong_global.phases.access
_G.kong.core_cache = {
  get = function(self, key, opts, func, ...)
    if key == constants.CLUSTER_ID_PARAM_KEY then
      return "123e4567-e89b-12d3-a456-426655440000"
    end

    return func(...)
  end
}

local db = assert(DB.new(conf))
assert(db:init_connector())
db.vaults:load_vault_schemas(conf.loaded_vaults)
db.plugins:load_plugin_schemas(conf.loaded_plugins)
local blueprints = assert(Blueprints.new(db))
local dcbp
local config_yml


kong.db = db


local cache

--- Gets the ml_cache instance.
-- @function get_cache
-- @param db the database object
-- @return ml_cache instance
local function get_cache(db)
  if not cache then
    local worker_events = require "resty.events.compat"
    worker_events.configure({
      listening = "unix:",
      testing = true,
    })

    local cluster_events = assert(kong_global.init_cluster_events(conf, db))
    cache = assert(kong_global.init_cache(conf,
                                          cluster_events,
                                          worker_events
                                          ))
  end

  return cache
end


kong.cache = get_cache(db)

cache._busted_hooked = false

local function clear_cache_on_file_end(file)
  if _G.kong and
    _G.kong.cache and
    _G.kong.cache.mlcache and
    _G.kong.cache.mlcache.lru and
    _G.kong.cache.mlcache.lru.free_queue and
    _G.kong.cache.mlcache.lru.cache_queue
  then
    _G.kong.cache.mlcache.lru.free_queue = nil
    _G.kong.cache.mlcache.lru.cache_queue = nil
    _G.kong.cache.mlcache.lru = nil
    collectgarbage()
  end
end

local function register_busted_hook(opts)
  local busted = require("busted")
  if not cache or cache._busted_hooked then
      return
  end

  cache._busted_hooked = true

  busted.subscribe({'file', 'end' }, clear_cache_on_file_end)
end

register_busted_hook()

local vitals
local function get_vitals(db)
  if not vitals then
    vitals = kong_vitals.new({
      db = db,
      ttl_seconds = 3600,
      ttl_minutes = 24 * 60,
      ttl_days = 30,
    })
  end

  return vitals
end

kong.vitals = get_vitals(db)

local analytics
local function get_analytics()
  if not analytics then
    local kong_analytics = require "kong.analytics"
    analytics = kong_analytics.new({})
  end

  return analytics
end

kong.analytics = get_analytics()

--- Iterator over DB strategies.
-- @function each_strategy
-- @param strategies (optional string array) explicit list of strategies to use,
-- defaults to `{ "postgres", }`.
-- @see all_strategies
-- @usage
-- -- repeat all tests for each strategy
-- for _, strategy_name in helpers.each_strategy() do
--   describe("my test set [#" .. strategy .. "]", function()
--
--     -- add your tests here
--
--   end)
-- end
local function each_strategy() -- luacheck: ignore   -- required to trick ldoc into processing for docs
end

--- Iterator over all strategies, the DB ones and the DB-less one.
-- To test with DB-less, check the example.
-- @function all_strategies
-- @param strategies (optional string array) explicit list of strategies to use,
-- defaults to `{ "postgres", "off" }`.
-- @see each_strategy
-- @see make_yaml_file
-- @usage
-- -- example of using DB-less testing
--
-- -- use "all_strategies" to iterate over; "postgres", "off"
-- for _, strategy in helpers.all_strategies() do
--   describe(PLUGIN_NAME .. ": (access) [#" .. strategy .. "]", function()
--
--     lazy_setup(function()
--
--       -- when calling "get_db_utils" with "strategy=off", we still use
--       -- "postgres" so we can write the test setup to the database.
--       local bp = helpers.get_db_utils(
--                      strategy == "off" and "postgres" or strategy,
--                      nil, { PLUGIN_NAME })
--
--       -- Inject a test route, when "strategy=off" it will still be written
--       -- to Postgres.
--       local route1 = bp.routes:insert({
--         hosts = { "test1.com" },
--       })
--
--       -- start kong
--       assert(helpers.start_kong({
--         -- set the strategy
--         database   = strategy,
--         nginx_conf = "spec/fixtures/custom_nginx.template",
--         plugins = "bundled," .. PLUGIN_NAME,
--
--         -- The call to "make_yaml_file" will write the contents of
--         -- the database to a temporary file, which filename is returned.
--         -- But only when "strategy=off".
--         declarative_config = strategy == "off" and helpers.make_yaml_file() or nil,
--
--         -- the below lines can be omitted, but are just to prove that the test
--         -- really runs DB-less despite that Postgres was used as intermediary
--         -- storage.
--         pg_host = strategy == "off" and "unknownhost.konghq.com" or nil,
--       }))
--     end)
--
--     ... rest of your test file
local function all_strategies() -- luacheck: ignore   -- required to trick ldoc into processing for docs
end

do
  local def_db_strategies = {"postgres"}
  local def_all_strategies = {"postgres", "off"}
  local env_var = os.getenv("KONG_DATABASE")
  if env_var then
    def_db_strategies = { env_var }
    def_all_strategies = { env_var }
  end
  local db_available_strategies = pl_Set(def_db_strategies)
  local all_available_strategies = pl_Set(def_all_strategies)

  local function iter(strategies, i)
    i = i + 1
    local strategy = strategies[i]
    if strategy then
      return i, strategy
    end
  end

  each_strategy = function(strategies)
    if not strategies then
      return iter, def_db_strategies, 0
    end

    for i = #strategies, 1, -1 do
      if not db_available_strategies[strategies[i]] then
        table.remove(strategies, i)
      end
    end
    return iter, strategies, 0
  end

  all_strategies = function(strategies)
    if not strategies then
      return iter, def_all_strategies, 0
    end

    for i = #strategies, 1, -1 do
      if not all_available_strategies[strategies[i]] then
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
    if db[t] and db[t].schema then
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
-- migth be in it. The BluePrint and DB objects returned can be used to create
-- test entities in the database.
--
-- So the difference between the `db` and `bp` is small. The `db` one allows access
-- to the datastore for creating entities and inserting data. The `bp` one is a
-- wrapper around the `db` one. It will auto-insert some stuff and check for errors;
--
-- - if you create a route using `bp`, it will automatically attach it to the
--   default service that it already created, without you having to specify that
--   service.
-- - any errors returned by `db`, which will be `nil + error` in Lua, will be
--   wrapped in an assertion by `bp` so if something is wrong it will throw a hard
--   error which is convenient when testing. When using `db` you have to manually
--   check for errors.
--
-- Since `bp` is a wrapper around `db` it will only know about the Kong standard
-- entities in the database. Hence the `db` one should be used when working with
-- custom DAO's for which no `bp` entry is available.
-- @function get_db_utils
-- @param strategy (optional) the database strategy to use, will default to the
-- strategy in the test configuration.
-- @param tables (optional) tables to truncate, this can be used to accelarate
-- tests if only a few tables are used. By default all tables will be truncated.
-- @param plugins (optional) array of plugins to mark as loaded. Since kong will
-- load all the bundled plugins by default, this is useful mostly for marking
-- custom plugins as loaded.
-- @param vaults (optional) vault configuration to use.
-- @param skip_migrations (optional) if true, migrations will not be run.
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
local function get_db_utils(strategy, tables, plugins, vaults, skip_migrations)
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

  if vaults ~= nil and type(vaults) ~= "table" then
    error("arg #4 must be a list of vaults to enable", 2)
  end

  if vaults then
    for _, vault in ipairs(vaults) do
      conf.loaded_vaults[vault] = true
    end
  end

  -- Clean workspaces from the context - otherwise, migrations will fail,
  -- as some of them have dao calls
  -- If `no_truncate` is falsey, `dao:truncate` and `db:truncate` are called,
  -- and these set the workspace back again to the new `default` workspace
  ngx.ctx.workspace = nil

  -- DAO (DB module)
  local db = assert(DB.new(conf, strategy))
  assert(db:init_connector())

  if not skip_migrations then
    bootstrap_database(db)
  end

  do
    local database = conf.database
    conf.database = strategy
    conf.database = database
  end

  db:truncate("plugins")
  assert(db.vaults:load_vault_schemas(conf.loaded_vaults))
  assert(db.plugins:load_plugin_schemas(conf.loaded_plugins))

  -- XXX EE
  kong.invoke_plugin = invoke_plugin.new {
    loaded_plugins = db.plugins:get_handlers(),
    kong_global = kong_global,
  }

  db:truncate("tags")

  -- initialize portal router
  kong.portal_router = portal_router.new(db)

  _G.kong.db = db

  -- cleanup tables
  if not tables then
    assert(db:truncate())

  else
    tables[#tables + 1] = "workspaces"
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

  rbac.register_dao_hooks(db)
  if vaults then
    for _, vault in ipairs(vaults) do
      conf.loaded_vaults[vault] = false
    end
  end

  if strategy ~= "off" then
    local workspaces = require "kong.workspaces"
    workspaces.upsert_default(db)
  end

  -- calculation can only happen here because this function
  -- initializes the kong.db instance
  PLUGINS_LIST = assert(kong.db.plugins:get_handlers())
  table.sort(PLUGINS_LIST, function(a, b)
    return a.name:lower() < b.name:lower()
  end)

  PLUGINS_LIST = pl_tablex.map(function(p)
    return { name = p.name, version = p.handler.VERSION, }
  end, PLUGINS_LIST)

  return bp, db
end

-----------------
-- Custom helpers
-----------------
local resty_http_proxy_mt = setmetatable({}, { __index = http })
resty_http_proxy_mt.__index = resty_http_proxy_mt

-- Prepopulate Schema's cache
Schema.new(consumers_schema_def)
Schema.new(services_schema_def)
Schema.new(routes_schema_def)

local plugins_schema = assert(Entity.new(plugins_schema_def))


--- Validate a plugin configuration against a plugin schema.
-- @function validate_plugin_config_schema
-- @param config The configuration to validate. This is not the full schema,
-- only the `config` sub-object needs to be passed.
-- @param schema_def The schema definition
-- @return the validated schema, or nil+error
local function validate_plugin_config_schema(config, schema_def, extra_fields)
  assert(plugins_schema:new_subschema(schema_def.name, schema_def))
  local entity = {
    id = uuid(),
    name = schema_def.name,
    config = config
  }

  if extra_fields then
    for k, v in pairs(extra_fields) do
      entity[k] = v
    end
  end

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


--- Check if a request can be retried in the case of a closed connection
--
-- For now this is limited to "safe" methods as defined by:
-- https://datatracker.ietf.org/doc/html/rfc7231#section-4.2.1
--
-- XXX Since this strictly applies to closed connections, it might be okay to
-- open this up to include idempotent methods like PUT and DELETE if we do
-- some more testing first
local function can_reopen(method)
  method = string.upper(method or "GET")
  return method == "GET"
      or method == "HEAD"
      or method == "OPTIONS"
      or method == "TRACE"
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
-- local client = helpers.proxy_client()
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
-- @function http_client:send
-- @param opts table with options. See [lua-resty-http](https://github.com/pintsized/lua-resty-http)
function resty_http_proxy_mt:send(opts, is_reopen)
  local cjson = require "cjson"
  local encode_args = require("kong.tools.http").encode_args

  opts = opts or {}

  -- build body
  local headers = opts.headers or {}
  local content_type, content_type_name = misc.lookup(headers, "Content-Type")
  content_type = content_type or ""
  local t_body_table = type(opts.body) == "table"

  if string.find(content_type, "application/json") and t_body_table then
    opts.body = cjson.encode(opts.body)

  elseif string.find(content_type, "www-form-urlencoded", nil, true) and t_body_table then
    opts.body = encode_args(opts.body, true, opts.no_array_indexes)

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

    local clength = misc.lookup(headers, "content-length")
    if not clength and not opts.dont_add_content_length then
      headers["content-length"] = #body
    end

    if not content_type:find("boundary=") then
      headers[content_type_name] = content_type .. "; boundary=" .. boundary
    end

    opts.body = body
  end

  -- build querystring (assumes none is currently in 'opts.path')
  if type(opts.query) == "table" then
    local qs = encode_args(opts.query)
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

  elseif (err == "closed" or err == "connection reset by peer")
     and not is_reopen
     and self.reopen
     and can_reopen(opts.method)
  then
    ngx.log(ngx.INFO, "Re-opening connection to ", self.options.scheme, "://",
                      self.options.host, ":", self.options.port)

    self:_connect()
    return self:send(opts, true)
  end

  return res, err
end


--- Open or re-open the client TCP connection
function resty_http_proxy_mt:_connect()
  local opts = self.options

  if CONSTANTS.TEST_COVERAGE_MODE == "true" then
    opts.connect_timeout = CONSTANTS.TEST_COVERAGE_TIMEOUT * 1000
    opts.send_timeout    = CONSTANTS.TEST_COVERAGE_TIMEOUT * 1000
    opts.read_timeout    = CONSTANTS.TEST_COVERAGE_TIMEOUT * 1000
  end

  local _, err = self:connect(opts)
  if err then
    error("Could not connect to " ..
          (opts.host or "unknown") .. ":" .. (opts.port or "unknown") ..
          ": " .. err)
  end

  if opts.connect_timeout and
     opts.send_timeout    and
     opts.read_timeout
  then
    self:set_timeouts(opts.connect_timeout, opts.send_timeout, opts.read_timeout)
  else
    self:set_timeout(opts.timeout or 10000)
  end
end


-- Implements http_client:get("path", [options]), as well as post, put, etc.
-- These methods are equivalent to calling http_client:send, but are shorter
-- They also come with a built-in assert
for _, method_name in ipairs({"get", "post", "put", "patch", "delete", "head", "options"}) do
  resty_http_proxy_mt[method_name] = function(self, path, options)
    local full_options = kong.table.merge({ method = method_name:upper(), path = path}, options)
    return assert(self:send(full_options))
  end
end


--- Creates a http client from options.
-- Instead of using this client, you'll probably want to use the pre-configured
-- clients available as `proxy_client`, `admin_client`, etc. because these come
-- pre-configured and connected to the underlying Kong test instance.
--
-- @function http_client_opts
-- @param options connection and other options
-- @return http client
-- @see http_client:send
-- @see proxy_client
-- @see proxy_ssl_client
-- @see admin_client
-- @see admin_ssl_client
local function http_client_opts(options)
  if not options.scheme then
    options = kong_table.cycle_aware_deep_copy(options)
    options.scheme = "http"
    if options.port == 443 then
      options.scheme = "https"
    else
      options.scheme = "http"
    end
  end

  local self = setmetatable(assert(http_new()), resty_http_proxy_mt)

  self.options = options

  if options.reopen ~= nil then
    self.reopen = options.reopen
  end

  self:_connect()

  return self
end


--- Creates a http client.
-- Instead of using this client, you'll probably want to use the pre-configured
-- clients available as `proxy_client`, `admin_client`, etc. because these come
-- pre-configured and connected to the underlying Kong test instance.
--
-- @function http_client
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
  if type(host) == "table" then
    return http_client_opts(host)
  end

  if CONSTANTS.TEST_COVERAGE_MODE == "true" then
    timeout = CONSTANTS.TEST_COVERAGE_TIMEOUT * 1000
  end

  return http_client_opts({
    host = host,
    port = port,
    timeout = timeout,
  })
end


--- Returns the proxy port.
-- @function get_proxy_port
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
-- @function get_proxy_ip
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
-- @function proxy_client
-- @param timeout (optional, number) the timeout to use
-- @param forced_port (optional, number) if provided will override the port in
-- the Kong configuration with this port
local function proxy_client(timeout, forced_port, forced_ip)
  local proxy_ip = get_proxy_ip(false)
  local proxy_port = get_proxy_port(false)
  assert(proxy_ip, "No http-proxy found in the configuration")
  return http_client_opts({
    scheme = "http",
    host = forced_ip or proxy_ip,
    port = forced_port or proxy_port,
    timeout = timeout or 60000,
  })
end


--- returns a pre-configured `http_client` for the Kong SSL proxy port.
-- @function proxy_ssl_client
-- @param timeout (optional, number) the timeout to use
-- @param sni (optional, string) the sni to use
local function proxy_ssl_client(timeout, sni)
  local proxy_ip = get_proxy_ip(true, true)
  local proxy_port = get_proxy_port(true, true)
  assert(proxy_ip, "No https-proxy found in the configuration")
  local client = http_client_opts({
    scheme = "https",
    host = proxy_ip,
    port = proxy_port,
    timeout = timeout or 60000,
    ssl_verify = false,
    ssl_server_name = sni,
  })
    return client
end


--- returns a pre-configured `http_client` for the Kong admin port.
-- @function admin_client
-- @param timeout (optional, number) the timeout to use
-- @param forced_port (optional, number) if provided will override the port in
-- the Kong configuration with this port
local function admin_client(timeout, forced_port)
  local admin_ip, admin_port
  for _, entry in ipairs(conf.admin_listeners) do
    if entry.ssl == false then
      admin_ip = entry.ip
      admin_port = entry.port
    end
  end
  assert(admin_ip, "No http-admin found in the configuration")
  return http_client_opts({
    scheme = "http",
    host = admin_ip,
    port = forced_port or admin_port,
    timeout = timeout or 60000,
    reopen = true,
  })
end

--- returns a pre-configured `http_client` for the Kong admin SSL port.
-- @function admin_ssl_client
-- @param timeout (optional, number) the timeout to use
local function admin_ssl_client(timeout)
  if CONSTANTS.TEST_COVERAGE_MODE == "true" then
    timeout = CONSTANTS.TEST_COVERAGE_TIMEOUT * 1000
  end

  local admin_ip, admin_port
  for _, entry in ipairs(conf.proxy_listeners) do
    if entry.ssl == true then
      admin_ip = entry.ip
      admin_port = entry.port
    end
  end
  assert(admin_ip, "No https-admin found in the configuration")
  local client = http_client_opts({
    scheme = "https",
    host = admin_ip,
    port = admin_port,
    timeout = timeout or 60000,
    reopen = true,
  })
  return client
end

--- returns a pre-configured `http_client` for the Kong Admin GUI.
-- @function admin_gui_client
-- @tparam[opt=60000] number timeout the timeout to use
-- @tparam[opt] number forced_port if provided will override the port in
-- the Kong configuration with this port
-- @return http-client, see `spec.helpers.http_client`.
local function admin_gui_client(timeout, forced_port)
  local admin_ip = "127.0.0.1"
  local admin_port
  for _, entry in ipairs(conf.admin_gui_listeners) do
    if entry.ssl == false then
      admin_ip = entry.ip
      admin_port = entry.port
    end
  end
  admin_port = forced_port or admin_port
  assert(admin_port, "No http-admin found in the configuration")
  return http_client_opts({
    scheme = "http",
    host = admin_ip,
    port = admin_port,
    timeout = timeout or 60000,
    reopen = true,
  })
end

--- returns a pre-configured `http_client` for the Kong admin GUI SSL port.
-- @function admin_gui_ssl_client
-- @tparam[opt=60000] number timeout the timeout to use
-- @tparam[opt] number forced_port if provided will override the port in
-- the Kong configuration with this port
-- @return http-client, see `spec.helpers.http_client`.
local function admin_gui_ssl_client(timeout, forced_port)
  local admin_ip = "127.0.0.1"
  local admin_port
  for _, entry in ipairs(conf.admin_gui_listeners) do
    if entry.ssl == true then
      admin_ip = entry.ip
      admin_port = entry.port
    end
  end
  admin_port = forced_port or admin_port
  assert(admin_port, "No https-admin found in the configuration")
  return http_client_opts({
    scheme = "https",
    host = admin_ip,
    port = admin_port,
    timeout = timeout or 60000,
    reopen = true,
  })
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


--- Creates an HTTP/2 client using golang's http2 package.
--- Sets `KONG_TEST_DEBUG_HTTP2=1` env var to print debug messages.
-- @function http2_client
-- @param host hostname to connect to
-- @param port port to connect to
local function http2_client(host, port, tls)
  local port = assert(port)
  tls = tls or false

  -- Note: set `GODEBUG=http2debug=1` is helpful if you are debugging this go program
  local tool_path = "bin/h2client"
  local http2_debug
  -- note: set env var "KONG_TEST_DEBUG_HTTP2" !! the "_TEST" will be dropped
  if os.getenv("KONG_DEBUG_HTTP2") then
    http2_debug = true
    tool_path = "GODEBUG=http2debug=1 bin/h2client"
  end


  local meta = {}
  meta.__call = function(_, opts)
    local headers = opts and opts.headers
    local timeout = opts and opts.timeout
    local body = opts and opts.body
    local path = opts and opts.path or ""
    local http1 = opts and opts.http_version == "HTTP/1.1"

    local url = (tls and "https" or "http") .. "://" .. host .. ":" .. port .. path

    local cmd = string.format("%s -url %s -skip-verify", tool_path, url)

    if headers then
      local h = {}
      for k, v in pairs(headers) do
        table.insert(h, string.format("%s=%s", k, v))
      end
      cmd = cmd .. " -headers " .. table.concat(h, ",")
    end

    if timeout then
      cmd = cmd .. " -timeout " .. timeout
    end

    if http1 then
      cmd = cmd .. " -http1"
    end

    --shell.run does not support '<'
    if body then
      cmd = cmd .. " -post"
    end

    if http2_debug then
      print("HTTP/2 cmd:\n" .. cmd)
    end

    --100MB for retrieving stdout & stderr
    local ok, stdout, stderr = shell.run(cmd, body, 0, 1024*1024*100)
    assert(ok, stderr)

    if http2_debug then
      print("HTTP/2 debug:\n")
      print(stderr)
    end

    local stdout_decoded = cjson.decode(stdout)
    if not stdout_decoded then
      error("Failed to decode h2client output: " .. stdout)
    end

    local headers = stdout_decoded.headers
    headers.get = function(_, key)
      if string.sub(key, 1, 1) == ":" then
        key = string.sub(key, 2)
      end
      return headers[key]
    end
    setmetatable(headers, {
      __index = function(headers, key)
        for k, v in pairs(headers) do
          if key:lower() == k:lower() then
            return v
          end
        end
      end
    })
    return stdout_decoded.body, headers
  end

  return setmetatable({}, meta)
end

--- returns a pre-configured cleartext `http2_client` for the Kong proxy port.
-- @function proxy_client_h2c
-- @return http2 client
local function proxy_client_h2c()
  local proxy_ip = get_proxy_ip(false, true)
  local proxy_port = get_proxy_port(false, true)
  assert(proxy_ip, "No http-proxy found in the configuration")
  return http2_client(proxy_ip, proxy_port)
end


--- returns a pre-configured TLS `http2_client` for the Kong SSL proxy port.
-- @function proxy_client_h2
-- @return http2 client
local function proxy_client_h2()
  local proxy_ip = get_proxy_ip(true, true)
  local proxy_port = get_proxy_port(true, true)
  assert(proxy_ip, "No https-proxy found in the configuration")
  return http2_client(proxy_ip, proxy_port, true)
end

--- Creates a gRPC client, based on the grpcurl CLI.
-- @function grpc_client
-- @param host hostname to connect to
-- @param port port to connect to
-- @param opts table with options supported by grpcurl
-- @return grpc client
local function grpc_client(host, port, opts)
  local host = assert(host)
  local port = assert(tostring(port))

  opts = opts or {}
  if not opts["-proto"] then
    opts["-proto"] = CONSTANTS.MOCK_GRPC_UPSTREAM_PROTO_PATH
  end

  return setmetatable({
    opts = opts,
    cmd_template = string.format("bin/grpcurl %%s %s:%s %%s", host, port)

  }, {
    __call = function(t, args)
      local service = assert(args.service)
      local body = args.body
      local arg_opts = args.opts or {}

      local t_body = type(body)
      if t_body ~= "nil" then
        if t_body == "table" then
          body = cjson.encode(body)
        end

        arg_opts["-d"] = string.format("'%s'", body)
      end

      local cmd_opts = gen_grpcurl_opts(pl_tablex.merge(t.opts, arg_opts, true))
      local cmd = string.format(t.cmd_template, cmd_opts, service)
      local ok, _, out, err = exec(cmd, true)

      if ok then
        return ok, ("%s%s"):format(out or "", err or "")
      else
        return nil, ("%s%s"):format(out or "", err or "")
      end
    end
  })
end


--- returns a pre-configured `grpc_client` for the Kong proxy port.
-- @function proxy_client_grpc
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
-- @function proxy_client_grpcs
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
-- Reconfiguration completion detection helpers
--

local MAX_RETRY_TIME = 10

--- Set up admin client and proxy client to so that interactions with the proxy client
-- wait for preceding admin API client changes to have completed.

-- @function make_synchronized_clients
-- @param clients table with admin_client and proxy_client fields (both optional)
-- @return admin_client, proxy_client

local function make_synchronized_clients(clients)
  clients = clients or {}
  local synchronized_proxy_client = clients.proxy_client or proxy_client()
  local synchronized_admin_client = clients.admin_client or admin_client()

  -- Install the reconfiguration completion detection plugin
  local res = synchronized_admin_client:post("/plugins", {
    headers = { ["Content-Type"] = "application/json" },
    body = {
      name = "reconfiguration-completion",
      config = {
        version = "0",
      }
    },
  })
  local body = luassert.res_status(201, res)
  local plugin = cjson.decode(body)
  local plugin_id = plugin.id

  -- Wait until the plugin is active on the proxy path, indicated by the presence of the X-Kong-Reconfiguration-Status header
  luassert.eventually(function()
    res = synchronized_proxy_client:get("/non-existent-proxy-path")
    luassert.res_status(404, res)
    luassert.equals("unknown", res.headers['x-kong-reconfiguration-status'])
  end)
          .has_no_error()

  -- Save the original request functions for the admin and proxy client
  local proxy_request = synchronized_proxy_client.request
  local admin_request = synchronized_admin_client.request

  local current_version = 0 -- incremented whenever a configuration change is made through the admin API
  local last_configured_version = 0 -- current version of the reconfiguration-completion plugin's configuration

  -- Wrap the admin API client request
  function synchronized_admin_client.request(client, opts)
    -- Whenever the configuration is changed through the admin API, increment the current version number
    if opts.method == "POST" or opts.method == "PUT" or opts.method == "PATCH" or opts.method == "DELETE" then
      current_version = current_version + 1
    end
    return admin_request(client, opts)
  end

  function synchronized_admin_client.synchronize_sibling(self, sibling)
    sibling.request = self.request
  end

  -- Wrap the proxy client request
  function synchronized_proxy_client.request(client, opts)
    -- If the configuration has been changed through the admin API, update the version number in the
    -- reconfiguration-completion plugin.
    if current_version > last_configured_version then
      last_configured_version = current_version
      res = admin_request(synchronized_admin_client, {
        method = "PATCH",
        path = "/plugins/" .. plugin_id,
        headers = { ["Content-Type"] = "application/json" },
        body = cjson.encode({
          config = {
            version = tostring(current_version),
          }
        }),
      })
      luassert.res_status(200, res)
    end

    -- Retry the request until the reconfiguration is complete and the reconfiguration completion
    -- plugin on the database has been updated to the current version.
    if not opts.headers then
      opts.headers = {}
    end
    opts.headers["If-Kong-Configuration-Version"] = tostring(current_version)
    local retry_until = ngx.now() + MAX_RETRY_TIME
    local err
    :: retry ::
    res, err = proxy_request(client, opts)
    if err then
      return res, err
    end
    if res.headers['x-kong-reconfiguration-status'] ~= "complete" then
      res:read_body()
      ngx.sleep(res.headers['retry-after'] or 1)
      if ngx.now() < retry_until then
        goto retry
      end
      return nil, "reconfiguration did not occur within " .. MAX_RETRY_TIME .. " seconds"
    end
    return res, err
  end

  function synchronized_proxy_client.synchronize_sibling(self, sibling)
    sibling.request = self.request
  end

  return synchronized_proxy_client, synchronized_admin_client
end

--------------------
-- Custom assertions
--
-- @section assertions

require("spec.helpers.wait")

--- Waits until a specific condition is met.
-- The check function will repeatedly be called (with a fixed interval), until
-- the condition is met. Throws an error on timeout.
--
-- NOTE: this is a regular Lua function, not a Luassert assertion.
-- @function wait_until
-- @param f check function that should return `truthy` when the condition has
-- been met
-- @param timeout (optional) maximum time to wait after which an error is
-- thrown, defaults to 5.
-- @param step (optional) interval between checks, defaults to 0.05.
-- @return nothing. It returns when the condition is met, or throws an error
-- when it times out.
-- @usage
-- -- wait 10 seconds for a file "myfilename" to appear
-- helpers.wait_until(function() return file_exist("myfilename") end, 10)
local function wait_until(f, timeout, step)
  if CONSTANTS.TEST_COVERAGE_MODE == "true" then
    timeout = CONSTANTS.TEST_COVERAGE_TIMEOUT
  end

  luassert.wait_until({
    condition = "truthy",
    fn = f,
    timeout = timeout,
    step = step,
  })
end


--- Waits until no Lua error occurred
-- The check function will repeatedly be called (with a fixed interval), until
-- there is no Lua error occurred
--
-- NOTE: this is a regular Lua function, not a Luassert assertion.
-- @function pwait_until
-- @param f check function
-- @param timeout (optional) maximum time to wait after which an error is
-- thrown, defaults to 5.
-- @param step (optional) interval between checks, defaults to 0.05.
-- @return nothing. It returns when the condition is met, or throws an error
-- when it times out.
local function pwait_until(f, timeout, step)
  if CONSTANTS.TEST_COVERAGE_MODE == "true" then
    timeout = CONSTANTS.TEST_COVERAGE_TIMEOUT
  end

  luassert.wait_until({
    condition = "no_error",
    fn = f,
    timeout = timeout,
    step = step,
  })
end


--- Wait for some timers, throws an error on timeout.
--
-- NOTE: this is a regular Lua function, not a Luassert assertion.
-- @function wait_timer
-- @tparam string timer_name_pattern the call will apply to all timers matching this string
-- @tparam boolean plain if truthy, the `timer_name_pattern` will be matched plain, so without pattern matching
-- @tparam string mode one of: "all-finish", "all-running", "any-finish", "any-running", or "worker-wide-all-finish"
--
-- any-finish: At least one of the timers that were matched finished
--
-- all-finish: All timers that were matched finished
--
-- any-running: At least one of the timers that were matched is running
--
-- all-running: All timers that were matched are running
--
-- worker-wide-all-finish: All the timers in the worker that were matched finished
-- @tparam number timeout maximum time to wait (optional, default: 2)
-- @tparam number admin_client_timeout, to override the default timeout setting (optional)
-- @tparam number forced_admin_port to override the default port of admin API (optional)
-- @usage helpers.wait_timer("rate-limiting", true, "all-finish", 10)
local function wait_timer(timer_name_pattern, plain,
                          mode, timeout,
                          admin_client_timeout, forced_admin_port)
  if not timeout then
    timeout = 2
  end

  local _admin_client

  local all_running_each_worker = nil
  local all_finish_each_worker = nil
  local any_running_each_worker = nil
  local any_finish_each_worker = nil

  wait_until(function ()
    if _admin_client then
      _admin_client:close()
    end

    _admin_client = admin_client(admin_client_timeout, forced_admin_port)
    local res = assert(_admin_client:get("/timers"))
    local body = luassert.res_status(200, res)
    local json = assert(cjson.decode(body))
    local worker_id = json.worker.id
    local worker_count = json.worker.count

    if not all_running_each_worker then
      all_running_each_worker = {}
      all_finish_each_worker = {}
      any_running_each_worker = {}
      any_finish_each_worker = {}

      for i = 0, worker_count - 1 do
        all_running_each_worker[i] = false
        all_finish_each_worker[i] = false
        any_running_each_worker[i] = false
        any_finish_each_worker[i] = false
      end
    end

    local is_matched = false

    for timer_name, timer in pairs(json.stats.timers) do
      if string.find(timer_name, timer_name_pattern, 1, plain) then
        is_matched = true

        all_finish_each_worker[worker_id] = false

        if timer.is_running then
          all_running_each_worker[worker_id] = true
          any_running_each_worker[worker_id] = true
          goto continue
        end

        all_running_each_worker[worker_id] = false

        goto continue
      end

      ::continue::
    end

    if not is_matched then
      any_finish_each_worker[worker_id] = true
      all_finish_each_worker[worker_id] = true
    end

    local all_running = false

    local all_finish = false
    local all_finish_worker_wide = true

    local any_running = false
    local any_finish = false

    for _, v in pairs(all_running_each_worker) do
      all_running = all_running or v
    end

    for _, v in pairs(all_finish_each_worker) do
      all_finish = all_finish or v
      all_finish_worker_wide = all_finish_worker_wide and v
    end

    for _, v in pairs(any_running_each_worker) do
      any_running = any_running or v
    end

    for _, v in pairs(any_finish_each_worker) do
      any_finish = any_finish or v
    end

    if mode == "all-running" then
      return all_running
    end

    if mode == "all-finish" then
      return all_finish
    end

    if mode == "worker-wide-all-finish" then
      return all_finish_worker_wide
    end

    if mode == "any-finish" then
      return any_finish
    end

    if mode == "any-running" then
      return any_running
    end

    error("unexpected error")
  end, timeout)
end


--- Waits for invalidation of a cached key by polling the mgt-api
-- and waiting for a 404 response. Throws an error on timeout.
--
-- NOTE: this is a regular Lua function, not a Luassert assertion.
-- @function wait_for_invalidation
-- @param key (string) the cache-key to check
-- @param timeout (optional) in seconds (for default see `wait_until`).
-- @return nothing. It returns when the key is invalidated, or throws an error
-- when it times out.
-- @usage
-- local cache_key = "abc123"
-- helpers.wait_for_invalidation(cache_key, 10)
local function wait_for_invalidation(key, timeout)
  -- TODO: this code is duplicated all over the codebase,
  -- search codebase for "/cache/" endpoint
  local api_client = admin_client()
  wait_until(function()
    local res = api_client:get("/cache/" .. key)
    res:read_body()
    return res.status == 404
  end, timeout)
end


--- Wait for all targets, upstreams, services, and routes update
--
-- NOTE: this function is not available for DBless-mode
-- @function wait_for_all_config_update
-- @tparam[opt] table opts a table contains params
-- @tparam[opt=30] number opts.timeout maximum seconds to wait, defatuls is 30
-- @tparam[opt] number opts.admin_client_timeout to override the default timeout setting
-- @tparam[opt] number opts.forced_admin_port to override the default Admin API port
-- @tparam[opt] bollean opts.stream_enabled to enable stream module
-- @tparam[opt] number opts.proxy_client_timeout to override the default timeout setting
-- @tparam[opt] number opts.forced_proxy_port to override the default proxy port
-- @tparam[opt] number opts.stream_port to set the stream port
-- @tparam[opt] string opts.stream_ip to set the stream ip
-- @tparam[opt=false] boolean opts.override_global_rate_limiting_plugin to override the global rate-limiting plugin in waiting
-- @tparam[opt=false] boolean opts.override_global_key_auth_plugin to override the global key-auth plugin in waiting
local function wait_for_all_config_update(opts)
  opts = opts or {}
  if CONSTANTS.TEST_COVERAGE_MODE == "true" then
    opts.timeout = CONSTANTS.TEST_COVERAGE_TIMEOUT
  end
  local timeout = opts.timeout or 30
  local admin_client_timeout = opts.admin_client_timeout
  local forced_admin_port = opts.forced_admin_port
  local proxy_client_timeout = opts.proxy_client_timeout
  local forced_proxy_port = opts.forced_proxy_port
  local stream_port = opts.stream_port
  local stream_ip = opts.stream_ip
  local stream_enabled = opts.stream_enabled or false
  local override_rl = opts.override_global_rate_limiting_plugin or false
  local override_auth = opts.override_global_key_auth_plugin or false
  local headers = opts.override_default_headers or { ["Content-Type"] = "application/json" }
  local disable_ipv6 = opts.disable_ipv6 or false

  local function call_admin_api(method, path, body, expected_status, headers)
    local client = admin_client(admin_client_timeout, forced_admin_port)

    local res

    if string.upper(method) == "POST" then
      res = client:post(path, {
        headers = headers,
        body = body,
      })

    elseif string.upper(method) == "DELETE" then
      res = client:delete(path, {
        headers = headers
      })
    end

    local ok, json_or_nil_or_err = pcall(function ()
      assert(res.status == expected_status, "unexpected response code: " .. res.status)

      if string.upper(method) == "DELETE" then
        return
      end

      local json = cjson.decode((res:read_body()))
      assert(json ~= nil, "unexpected response body")
      return json
    end)

    client:close()

    assert(ok, json_or_nil_or_err)

    return json_or_nil_or_err
  end

  local upstream_id, target_id, service_id, route_id
  local stream_upstream_id, stream_target_id, stream_service_id, stream_route_id
  local consumer_id, rl_plugin_id, key_auth_plugin_id, credential_id
  local upstream_name = "really.really.really.really.really.really.really.mocking.upstream.test"
  local service_name = "really-really-really-really-really-really-really-mocking-service"
  local stream_upstream_name = "stream-really.really.really.really.really.really.really.mocking.upstream.test"
  local stream_service_name = "stream-really-really-really-really-really-really-really-mocking-service"
  local route_path = "/really-really-really-really-really-really-really-mocking-route"
  local key_header_name = "really-really-really-really-really-really-really-mocking-key"
  local consumer_name = "really-really-really-really-really-really-really-mocking-consumer"
  local test_credentials = "really-really-really-really-really-really-really-mocking-credentials"

  local host = "127.0.0.1"
  local port = get_available_port()

  local server = https_server.new(port, host, "http", nil, 1, nil, disable_ipv6)

  server:start()

  -- create mocking upstream
  local res = assert(call_admin_api("POST",
                             "/upstreams",
                             { name = upstream_name },
                             201, headers))
  upstream_id = res.id

  -- create mocking target to mocking upstream
  res = assert(call_admin_api("POST",
                       string.format("/upstreams/%s/targets", upstream_id),
                       { target = host .. ":" .. port },
                       201, headers))
  target_id = res.id

  -- create mocking service to mocking upstream
  res = assert(call_admin_api("POST",
                       "/services",
                       { name = service_name, url = "http://" .. upstream_name .. "/always_200" },
                       201, headers))
  service_id = res.id

  -- create mocking route to mocking service
  res = assert(call_admin_api("POST",
                       string.format("/services/%s/routes", service_id),
                       { paths = { route_path }, strip_path = true, path_handling = "v0",},
                       201, headers))
  route_id = res.id

  if override_rl then
    -- create rate-limiting plugin to mocking mocking service
    res = assert(call_admin_api("POST",
                                string.format("/services/%s/plugins", service_id),
                                { name = "rate-limiting", config = { minute = 999999, policy = "local" } },
                                201, headers))
    rl_plugin_id = res.id
  end

  if override_auth then
    -- create key-auth plugin to mocking mocking service
    res = assert(call_admin_api("POST",
                                string.format("/services/%s/plugins", service_id),
                                { name = "key-auth", config = { key_names = { key_header_name } } },
                                201, headers))
    key_auth_plugin_id = res.id

    -- create consumer
    res = assert(call_admin_api("POST",
                                "/consumers",
                                { username = consumer_name },
                                201, headers))
      consumer_id = res.id

    -- create credential to key-auth plugin
    res = assert(call_admin_api("POST",
                                string.format("/consumers/%s/key-auth", consumer_id),
                                { key = test_credentials },
                                201, headers))
    credential_id = res.id
  end

  if stream_enabled then
      -- create mocking upstream
    local res = assert(call_admin_api("POST",
                              "/upstreams",
                              { name = stream_upstream_name },
                              201, headers))
    stream_upstream_id = res.id

    -- create mocking target to mocking upstream
    res = assert(call_admin_api("POST",
                        string.format("/upstreams/%s/targets", stream_upstream_id),
                        { target = host .. ":" .. port },
                        201, headers))
    stream_target_id = res.id

    -- create mocking service to mocking upstream
    res = assert(call_admin_api("POST",
                        "/services",
                        { name = stream_service_name, url = "tcp://" .. stream_upstream_name },
                        201, headers))
    stream_service_id = res.id

    -- create mocking route to mocking service
    res = assert(call_admin_api("POST",
                        string.format("/services/%s/routes", stream_service_id),
                        { destinations = { { port = stream_port }, }, protocols = { "tcp" },},
                        201, headers))
    stream_route_id = res.id
  end

  local ok, err = pcall(function ()
    -- wait for mocking route ready
    pwait_until(function ()
      local proxy = proxy_client(proxy_client_timeout, forced_proxy_port)

      if override_auth then
        res = proxy:get(route_path, { headers = { [key_header_name] = test_credentials } })

      else
        res = proxy:get(route_path)
      end

      local ok, err = pcall(assert, res.status == 200)
      proxy:close()
      assert(ok, err)
    end, timeout / 2)

    if stream_enabled then
      pwait_until(function ()
        local proxy = proxy_client(proxy_client_timeout, stream_port, stream_ip)

        res = proxy:get("/always_200")
        local ok, err = pcall(assert, res.status == 200)
        proxy:close()
        assert(ok, err)
      end, timeout)
    end
  end)
  if not ok then
    server:shutdown()
    error(err)
  end

  -- delete mocking configurations
  if override_auth then
    call_admin_api("DELETE", string.format("/consumers/%s/key-auth/%s", consumer_id, credential_id), nil, 204, headers)
    call_admin_api("DELETE", string.format("/consumers/%s", consumer_id), nil, 204, headers)
    call_admin_api("DELETE", "/plugins/" .. key_auth_plugin_id, nil, 204, headers)
  end

  if override_rl then
    call_admin_api("DELETE", "/plugins/" .. rl_plugin_id, nil, 204, headers)
  end

  call_admin_api("DELETE", "/routes/" .. route_id, nil, 204, headers)
  call_admin_api("DELETE", "/services/" .. service_id, nil, 204, headers)
  call_admin_api("DELETE", string.format("/upstreams/%s/targets/%s", upstream_id, target_id), nil, 204, headers)
  call_admin_api("DELETE", "/upstreams/" .. upstream_id, nil, 204, headers)

  if stream_enabled then
    call_admin_api("DELETE", "/routes/" .. stream_route_id, nil, 204, headers)
    call_admin_api("DELETE", "/services/" .. stream_service_id, nil, 204, headers)
    call_admin_api("DELETE", string.format("/upstreams/%s/targets/%s", stream_upstream_id, stream_target_id), nil, 204, headers)
    call_admin_api("DELETE", "/upstreams/" .. stream_upstream_id, nil, 204, headers)
  end

  ok, err = pcall(function ()
    -- wait for mocking configurations to be deleted
    pwait_until(function ()
      local proxy = proxy_client(proxy_client_timeout, forced_proxy_port)
      res  = proxy:get(route_path)
      local ok, err = pcall(assert, res.status == 404)
      proxy:close()
      assert(ok, err)
    end, timeout / 2)
  end)

  server:shutdown()

  if not ok then
    error(err)
  end

end


--- Waits for a file to meet a certain condition
-- The check function will repeatedly be called (with a fixed interval), until
-- there is no Lua error occurred
--
-- NOTE: this is a regular Lua function, not a Luassert assertion.
-- @function wait_for_file
-- @tparam string mode one of:
--
-- "file", "directory", "link", "socket", "named pipe", "char device", "block device", "other"
--
-- @tparam string path the file path
-- @tparam[opt=10] number timeout maximum seconds to wait
local function wait_for_file(mode, path, timeout)
  pwait_until(function()
    local result, err = lfs.attributes(path, "mode")
    local msg = string.format("failed to wait for the mode (%s) of '%s': %s",
                              mode, path, tostring(err))
    assert(result == mode, msg)
  end, timeout or 10)
end


local wait_for_file_contents
do
  --- Wait until a file exists and is non-empty.
  --
  -- If, after the timeout is reached, the file does not exist, is not
  -- readable, or is empty, an assertion error will be raised.
  --
  -- @function wait_for_file_contents
  -- @param fname the filename to wait for
  -- @param timeout (optional) maximum time to wait after which an error is
  -- thrown, defaults to 10.
  -- @return contents the file contents, as a string
  function wait_for_file_contents(fname, timeout)
    assert(type(fname) == "string",
           "filename must be a string")

    timeout = timeout or 10
    assert(type(timeout) == "number" and timeout >= 0,
           "timeout must be nil or a number >= 0")

    local data = pl_file.read(fname)
    if data and #data > 0 then
      return data
    end

    pcall(wait_until, function()
      data = pl_file.read(fname)
      return data and #data > 0
    end, timeout)

    assert(data, "file (" .. fname .. ") does not exist or is not readable"
                 .. " after " .. tostring(timeout) .. " seconds")

    assert(#data > 0, "file (" .. fname .. ") exists but is empty after " ..
                      tostring(timeout) .. " seconds")

    return data
  end
end


--- Prepares the Kong environment.
-- Creates the working directory if it does not exist.
-- @param prefix (optional) path to the working directory, if omitted the test
-- configuration will be used
-- @function prepare_prefix
local function prepare_prefix(prefix)
  return pl_dir.makepath(prefix or conf.prefix)
end


--- Cleans the Kong environment.
-- Deletes the working directory if it exists.
-- @param prefix (optional) path to the working directory, if omitted the test
-- configuration will be used
-- @function clean_prefix
local function clean_prefix(prefix)

  -- like pl_dir.rmtree, but ignore mount points
  local function rmtree(fullpath)
    if pl_path.islink(fullpath) then return false,'will not follow symlink' end
    for root,dirs,files in pl_dir.walk(fullpath,true) do
      if pl_path.islink(root) then
        -- sub dir is a link, remove link, do not follow
        local res, err = os.remove(root)
        if not res then
          return nil, err .. ": " .. root
        end

      else
        for i,f in ipairs(files) do
          f = pl_path.join(root,f)
          local res, err = os.remove(f)
          if not res then
            return nil,err .. ": " .. f
          end
        end

        local res, err = pl_path.rmdir(root)
        -- skip errors when trying to remove mount points
        if not res and shell.run("findmnt " .. root .. " 2>&1 >/dev/null", nil, 0) == 0 then
          return nil, err .. ": " .. root
        end
      end
    end
    return true
  end

  prefix = prefix or conf.prefix
  if pl_path.exists(prefix) then
    local _, err = rmtree(prefix)
    if err then
      error(err)
    end
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


local function pid_dead(pid, timeout)
  local max_time = ngx.now() + (timeout or 10)

  repeat
    if not shell.run("ps -p " .. pid .. " >/dev/null 2>&1", nil, 0) then
      return true
    end
    -- still running, wait some more
    ngx.sleep(0.05)
  until ngx.now() >= max_time

  return false
end

-- Waits for the termination of a pid.
-- @param pid_path Filename of the pid file.
-- @param timeout (optional) in seconds, defaults to 10.
local function wait_pid(pid_path, timeout, is_retry)
  local pid = get_pid_from_file(pid_path)

  if CONSTANTS.TEST_COVERAGE_MODE == "true" then
    timeout = CONSTANTS.TEST_COVERAGE_TIMEOUT
  end

  if pid then
    if pid_dead(pid, timeout) then
      return
    end

    if is_retry then
      return
    end

    -- Timeout reached: kill with SIGKILL
    shell.run("kill -9 " .. pid .. " >/dev/null 2>&1", nil, 0)

    -- Sanity check: check pid again, but don't loop.
    wait_pid(pid_path, timeout, true)
  end
end


--- Return the actual configuration running at the given prefix.
-- It may differ from the default, as it may have been modified
-- by the `env` table given to start_kong.
-- @function get_running_conf
-- @param prefix (optional) The prefix path where the kong instance is running,
-- defaults to the prefix in the default config.
-- @return The conf table of the running instance, or nil + error.
local function get_running_conf(prefix)
  local default_conf = conf_loader(nil, {prefix = prefix or conf.prefix})
  return conf_loader.load_config_file(default_conf.kong_env)
end


--- Clears the logfile. Will overwrite the logfile with an empty file.
-- @function clean_logfile
-- @param logfile (optional) filename to clear, defaults to the current
-- error-log file
-- @return nothing
-- @see line
local function clean_logfile(logfile)
  logfile = logfile or (get_running_conf() or conf).nginx_err_logs

  assert(type(logfile) == "string", "'logfile' must be a string")

  local fh, err, errno = io.open(logfile, "w+")

  if fh then
    fh:close()
    return

  elseif errno == 2 then -- ENOENT
    return
  end

  error("failed to truncate logfile: " .. tostring(err))
end


--- Return the actual Kong version the tests are running against.
-- See [version.lua](https://github.com/kong/version.lua) for the format. This
-- is mostly useful for testing plugins that should work with multiple Kong versions.
-- @function get_version
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
    local render_config = assert(conf_loader(prefix .. "/.kong_env", nil,
                                             { from_kong_env = true }))

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
      env.lua_package_path = CONSTANTS.DNS_MOCK_LUA_PATH .. ";" .. env.lua_package_path
    else
      env.lua_package_path = CONSTANTS.DNS_MOCK_LUA_PATH
    end
  else
    -- remove any old mocks if they exist
    os.remove(prefix .. "/dns_mock_records.json")
  end

  return true
end


local function build_go_plugins(path)
  if pl_path.exists(pl_path.join(path, "go.mod")) then
    local ok, _, stderr = shell.run(string.format(
            "cd %s; go mod tidy; go mod download", path), nil, 0)
    assert(ok, stderr)
  end
  for _, go_source in ipairs(pl_dir.getfiles(path, "*.go")) do
    local ok, _, stderr = shell.run(string.format(
            "cd %s; go build %s",
            path, pl_path.basename(go_source)
    ), nil, 0)
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
-- @function start_kong
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
-- **DEPRECATED**: http_mock fixture is deprecated. Please use `spec.helpers.http_mock` instead.
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
--          ssl_protocols TLSv1.2 TLSv1.3;
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
  --  compile fixture go plugins if any setting mentions it
  for _,v in pairs(env) do
    if type(v) == "string" and v:find(CONSTANTS.GO_PLUGIN_PATH) then
      build_go_plugins(CONSTANTS.GO_PLUGIN_PATH)
      break
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
  local nginx_conf_flags = { "test" }
  if env.nginx_conf then
    nginx_conf = " --nginx-conf " .. env.nginx_conf
  end

  if CONSTANTS.TEST_COVERAGE_MODE == "true" then
    -- render `coverage` blocks in the templates
    nginx_conf_flags[#nginx_conf_flags + 1] = 'coverage'
  end

  if next(nginx_conf_flags) then
    nginx_conf_flags = " --nginx-conf-flags " .. table.concat(nginx_conf_flags, ",")
  else
    nginx_conf_flags = ""
  end

  if dcbp and not env.declarative_config and not env.declarative_config_string then
    if not config_yml then
      config_yml = prefix .. "/config.yml"
      local cfg = dcbp.done()
      local declarative = require "kong.db.declarative"
      local ok, err = declarative.to_yaml_file(cfg, config_yml)
      if not ok then
        return nil, err
      end
    end
    env = kong_table.cycle_aware_deep_copy(env)
    env.declarative_config = config_yml
  end

  assert(render_fixtures(CONSTANTS.TEST_CONF_PATH .. nginx_conf, env, prefix, fixtures))
  return kong_exec("start --conf " .. CONSTANTS.TEST_CONF_PATH .. nginx_conf .. nginx_conf_flags, env)
end


-- Cleanup after kong test instance, should be called if start_kong was invoked with the nowait flag
-- @function cleanup_kong
-- @param prefix (optional) the prefix where the test instance runs, defaults to the test configuration.
-- @param preserve_prefix (boolean) if truthy, the prefix will not be deleted after stopping
-- @param preserve_dc ???
local function cleanup_kong(prefix, preserve_prefix, preserve_dc)
  -- remove socket files to ensure `pl.dir.rmtree()` ok
  prefix = prefix or conf.prefix
  local socket_path = pl_path.join(prefix, constants.SOCKET_DIRECTORY)
  for child in lfs.dir(socket_path) do
    local path = pl_path.join(socket_path, child)
    if lfs.attributes(path, "mode") == "socket" then
      os.remove(path)
    end
  end

  -- note: set env var "KONG_TEST_DONT_CLEAN" !! the "_TEST" will be dropped
  if not (preserve_prefix or os.getenv("KONG_DONT_CLEAN")) then
    clean_prefix(prefix)
  end

  if not preserve_dc then
    config_yml = nil
  end
  ngx.ctx.workspace = nil
end


-- Stop the Kong test instance.
-- @function stop_kong
-- @param prefix (optional) the prefix where the test instance runs, defaults to the test configuration.
-- @param preserve_prefix (boolean) if truthy, the prefix will not be deleted after stopping
-- @param preserve_dc ???
-- @param signal (optional string) signal name to send to kong, defaults to TERM
-- @param nowait (optional) if truthy, don't wait for kong to terminate.  caller needs to wait and call cleanup_kong
-- @return true or nil+err
local function stop_kong(prefix, preserve_prefix, preserve_dc, signal, nowait)
  prefix = prefix or conf.prefix
  signal = signal or "TERM"

  local running_conf, err = get_running_conf(prefix)
  if not running_conf then
    return nil, err
  end

  local pid, err = get_pid_from_file(running_conf.nginx_pid)
  if not pid then
    return nil, err
  end

  local ok, _, err = shell.run(string.format("kill -%s %d", signal, pid), nil, 0)
  if not ok then
    return nil, err
  end

  if nowait then
    return running_conf.nginx_pid
  end

  wait_pid(running_conf.nginx_pid)

  cleanup_kong(prefix, preserve_prefix, preserve_dc)

  return true
end

--- Restart Kong. Reusing declarative config when using `database=off`.
-- @function restart_kong
-- @param env see `start_kong`
-- @param tables see `start_kong`
-- @param fixtures see `start_kong`
-- @return true or nil+err
local function restart_kong(env, tables, fixtures)
  stop_kong(env.prefix, true, true)
  return start_kong(env, tables, true, fixtures)
end

--- Wait until no common workers.
-- This will wait until all the worker PID's listed have gone (others may have appeared). If an `expected_total` is specified, it will also wait until the new workers have reached this number.
-- @function wait_until_no_common_workers
-- @tparam table workers an array of worker PID's (the return value of `get_kong_workers`)
-- @tparam[opt] number expected_total the expected total workers count
-- @tparam[opt] table wait_opts options to use, the available fields are:
-- @tparam[opt] number wait_opts.timeout timeout passed to `wait_until`
-- @tparam[opt] number wait_opts.step step passed to `wait_until`
local function wait_until_no_common_workers(workers, expected_total, wait_opts)
  wait_opts = wait_opts or {}
  wait_until(function()
    local pok, admin_client = pcall(admin_client)
    if not pok then
      return false
    end
    local res = assert(admin_client:send {
      method = "GET",
      path = "/",
    })
    luassert.res_status(200, res)
    local json = cjson.decode(luassert.res_status(200, res))
    admin_client:close()

    local new_workers = json.pids.workers
    local total = 0
    local common = 0
    if new_workers then
      for _, v in ipairs(new_workers) do
        total = total + 1
        for _, v_old in ipairs(workers) do
          if v == v_old then
            common = common + 1
            break
          end
        end
      end
    end
    return common == 0 and total == (expected_total or total)
  end, wait_opts.timeout, wait_opts.step)
end


--- Gets the Kong workers PID's.
-- Will wait for a successful call to the admin-api for a maximum of 10 seconds,
-- before returning a timeout.
-- @function get_kong_workers
-- @tparam[opt] number expected_total the expected total workers count
-- @return array of worker PID's
local function get_kong_workers(expected_total)
  local workers

  wait_until(function()
    local pok, admin_client = pcall(admin_client)
    if not pok then
      return false
    end
    local res = admin_client:send {
      method = "GET",
      path = "/",
    }
    if not res or res.status ~= 200 then
      return false
    end
    local body = luassert.res_status(200, res)
    local json = cjson.decode(body)

    admin_client:close()

    workers = {}

    for _, item in ipairs(json.pids.workers) do
      if item ~= ngx.null then
        table.insert(workers, item)
      end
    end

    if expected_total and #workers ~= expected_total then
      return nil, ("expected %s worker pids, got %s"):format(expected_total,
                                                             #workers)

    elseif #workers == 0 then
      return nil, "GET / returned no worker pids"
    end

    return true
  end, 10)
  return workers
end


--- Reload Kong and wait all workers are restarted.
local function reload_kong(...)
  local workers = get_kong_workers()
  local ok, err = kong_exec(...)
  if ok then
    local opts = { ... }
    wait_until_no_common_workers(workers, 1, opts[2])
  end
  return ok, err
end

local is_echo_server_ready, get_echo_server_received_data, echo_server_reset
do
  -- Message id is maintained within echo server context and not
  -- needed for echo server user.
  -- This id is extracted from the number in nginx error.log at each
  -- line of log. i.e.:
  --  2023/12/15 14:10:12 [info] 718291#0: *303 stream [lua] content_by_lua ...
  -- in above case, the id is 303.
  local msg_id = -1
  local prefix_dir = "servroot"

  --- Check if echo server is ready.
  --
  -- @function is_echo_server_ready
  -- @return boolean
  function is_echo_server_ready()
    -- ensure server is ready.
    local sock = ngx.socket.tcp()
    sock:settimeout(0.1)
    local retry = 0
    local test_port = 8188

    while true do
      if sock:connect("localhost", test_port) then
        sock:send("START\n")
        local ok = sock:receive()
        sock:close()
        if ok == "START" then
          return true
        end
      else
        retry = retry + 1
        if retry > 10 then
          return false
        end
      end
    end
  end

  --- Get the echo server's received data.
  -- This function check the part of expected data with a timeout.
  --
  -- @function get_echo_server_received_data
  -- @param expected part of the data expected.
  -- @param timeout (optional) timeout in seconds, default is 0.5.
  -- @return  the data the echo server received. If timeouts, return "timeout".
  function get_echo_server_received_data(expected, timeout)
    if timeout == nil then
      timeout = 0.5
    end

    local extract_cmd = "grep content_by_lua "..prefix_dir.."/logs/error.log | tail -1"
    local _, _, log = assert(exec(extract_cmd))
    local pattern = "%*(%d+)%s.*received data: (.*)"
    local cur_msg_id, data = string.match(log, pattern)

    -- unit is second.
    local t = 0.1
    local time_acc = 0

    -- retry it when data is not available. because sometime,
    -- the error.log has not been flushed yet.
    while string.find(data, expected) == nil or cur_msg_id == msg_id  do
      ngx.sleep(t)
      time_acc = time_acc + t
      if time_acc >= timeout then
        return "timeout"
      end

      _, _, log = assert(exec(extract_cmd))
      cur_msg_id, data = string.match(log, pattern)
    end

    -- update the msg_id, it persists during a cycle from echo server
    -- start to stop.
    msg_id = cur_msg_id

    return data
  end

  function echo_server_reset()
    stop_kong(prefix_dir)
    msg_id = -1
  end
end

--- Simulate a Hybrid mode DP and connect to the CP specified in `opts`.
-- @function clustering_client
-- @param opts Options to use, the `host`, `port`, `cert` and `cert_key` fields
-- are required.
-- Other fields that can be overwritten are:
-- `node_hostname`, `node_id`, `node_version`, `node_plugins_list`. If absent,
-- they are automatically filled.
-- @return msg if handshake succeeded and initial message received from CP or nil, err
local function clustering_client(opts)
  assert(opts.host)
  assert(opts.port)
  assert(opts.cert)
  assert(opts.cert_key)

  local inflate_gzip = require("kong.tools.gzip").inflate_gzip

  local c = assert(ws_client:new())
  local uri = "wss://" .. opts.host .. ":" .. opts.port ..
              "/v1/outlet?node_id=" .. (opts.node_id or uuid()) ..
              "&node_hostname=" .. (opts.node_hostname or kong.node.get_hostname()) ..
              "&node_version=" .. (opts.node_version or CONSTANTS.KONG_VERSION)

  local conn_opts = {
    ssl_verify = false, -- needed for busted tests as CP certs are not trusted by the CLI
    client_cert = assert(ssl.parse_pem_cert(assert(pl_file.read(opts.cert)))),
    client_priv_key = assert(ssl.parse_pem_priv_key(assert(pl_file.read(opts.cert_key)))),
    server_name = opts.server_name or "kong_clustering",
  }

  local res, err = c:connect(uri, conn_opts)
  if not res then
    return nil, err
  end
  local payload = assert(cjson.encode({ type = "basic_info",
                                        plugins = opts.node_plugins_list or
                                                  PLUGINS_LIST,
                                        labels = opts.node_labels,
                                        process_conf = opts.node_process_conf,
                                      }))
  assert(c:send_binary(payload))

  assert(c:send_ping(string.rep("0", 32)))

  local data, typ, err
  data, typ, err = c:recv_frame()
  c:close()

  if typ == "binary" then
    local odata = assert(inflate_gzip(data))
    local msg = assert(cjson.decode(odata))
    return msg

  elseif typ == "pong" then
    return "PONG"
  end

  return nil, "unknown frame from CP: " .. (typ or err)
end


--- Create a temporary directory, and return its path.
-- @function tmpdir
-- @return string path to the temporary directory
local function tmpdir()
  local handle = assert(io.popen("mktemp -d"))
  local path = handle:read("*a")
  handle:close()
  return path:sub(1, #path - 1)
end

--- Gets the path to the fixtures directory calculating from the calling script.
--- Useful for plugins-ee tests where `spec/fixtures` is not bundled for each plugin.
-- @function get_fixtures_path
-- @return string path to the fixtures directory
local function get_fixtures_path()
  local str = debug.getinfo(2, "S").source:sub(2)
  local path = str:match("(.*/)") .. "fixtures/"
  if path:sub(1, 1) ~= "/" then -- relative path
    return lfs.currentdir() .. "/" .. path
  end

  return path
end


local make_temp_dir
do
  local seeded = false

  function make_temp_dir()
    if not seeded then
      ngx.update_time()
      math.randomseed(ngx.worker.pid() + ngx.now())
      seeded = true
    end

    local tmp
    local ok, err

    local tries = 1000
    for _ = 1, tries do
      local name = "/tmp/.kong-test" .. math.random()

      ok, err = pl_path.mkdir(name)

      if ok then
        tmp = name
        break
      end
    end

    assert(tmp ~= nil, "failed to create temporary directory " ..
                       "after " .. tostring(tries) .. " tries, " ..
                       "last error: " .. tostring(err))

    return tmp, function() pl_dir.rmtree(tmp) end
  end
end

-- This function is used for plugin compatibility test.
-- It will use the old version plugin by including the path of the old plugin
-- at the first of LUA_PATH.
-- The return value is a function which when called will recover the original
-- LUA_PATH and remove the temporary directory if it exists.
-- For an example of how to use it, please see:
-- plugins-ee/rate-limiting-advanced/spec/06-old-plugin-compatibility_spec.lua
-- spec/03-plugins/03-http-log/05-old-plugin-compatibility_spec.lua
local function use_old_plugin(name)
  assert(type(name) == "string", "must specify the plugin name")

  local old_plugin_path
  local temp_dir
  if pl_path.exists(CONSTANTS.OLD_VERSION_KONG_PATH .. "/kong/plugins/" .. name) then
    -- only include the path of the specified plugin into LUA_PATH
    -- and keep the directory structure 'kong/plugins/...'
    temp_dir = make_temp_dir()
    old_plugin_path = temp_dir
    local dest_dir = old_plugin_path .. "/kong/plugins"
    assert(pl_dir.makepath(dest_dir), "failed to makepath " .. dest_dir)
    assert(shell.run("cp -r " .. CONSTANTS.OLD_VERSION_KONG_PATH .. "/kong/plugins/" .. name .. " " .. dest_dir), "failed to copy the plugin directory")

  -- XXX EE
  elseif pl_path.exists(CONSTANTS.OLD_VERSION_KONG_PATH .. "/plugins-ee/" .. name) then
    old_plugin_path = CONSTANTS.OLD_VERSION_KONG_PATH .. "/plugins-ee/" .. name
  -- EE

  else
    error("the specified plugin " .. name .. " doesn't exist")
  end

  local plugin_include_path = old_plugin_path .. "/?.lua;" .. old_plugin_path .. "/?/init.lua;"

  -- put the old plugin path at first
  local origin_lua_path = os.getenv("LUA_PATH")
  assert(misc.setenv("LUA_PATH", plugin_include_path .. origin_lua_path), "failed to set LUA_PATH env")

  -- LUA_PATH is used by "kong commands" like "kong start", "kong config" etc.
  -- but for busted tests that are already running (since this is spec/helpers.lua) in order to use old plugin we need to update `package.path`
  local origin_package_path = package.path
  package.path = plugin_include_path .. origin_package_path

  return function ()
    misc.setenv("LUA_PATH", origin_lua_path)
    package.path = origin_package_path
    if temp_dir then
      pl_dir.rmtree(temp_dir)
    end
  end
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
-- @field grpcbin_host The host for grpcbin service, it can be set by env KONG_SPEC_TEST_GRPCBIN_HOST.
-- @field grpcbin_port The port (SSL disabled) for grpcbin service, it can be set by env KONG_SPEC_TEST_GRPCBIN_PORT.
-- @field grpcbin_ssl_port The port (SSL enabled) for grpcbin service it can be set by env KONG_SPEC_TEST_GRPCBIN_SSL_PORT.
-- @field grpcbin_url The URL (SSL disabled) for grpcbin service
-- @field grpcbin_ssl_url The URL (SSL enabled) for grpcbin service
-- @field redis_host The host for Redis, it can be set by env KONG_SPEC_TEST_REDIS_HOST.
-- @field redis_port The port (SSL disabled) for Redis, it can be set by env KONG_SPEC_TEST_REDIS_PORT.
-- @field redis_ssl_port The port (SSL enabled) for Redis, it can be set by env KONG_SPEC_TEST_REDIS_SSL_PORT.
-- @field redis_ssl_sni The server name for Redis, it can be set by env KONG_SPEC_TEST_REDIS_SSL_SNI.
-- @field zipkin_host The host for Zipkin service, it can be set by env KONG_SPEC_TEST_ZIPKIN_HOST.
-- @field zipkin_port the port for Zipkin service, it can be set by env KONG_SPEC_TEST_ZIPKIN_PORT.
-- @field otelcol_host The host for OpenTelemetry Collector service, it can be set by env KONG_SPEC_TEST_OTELCOL_HOST.
-- @field otelcol_http_port the port for OpenTelemetry Collector service, it can be set by env KONG_SPEC_TEST_OTELCOL_HTTP_PORT.
-- @field old_version_kong_path the path for the old version kong source code, it can be set by env KONG_SPEC_TEST_OLD_VERSION_KONG_PATH.
-- @field otelcol_zpages_port the port for OpenTelemetry Collector Zpages service, it can be set by env KONG_SPEC_TEST_OTELCOL_ZPAGES_PORT.
-- @field otelcol_file_exporter_path the path of for OpenTelemetry Collector's file exporter, it can be set by env KONG_SPEC_TEST_OTELCOL_FILE_EXPORTER_PATH.

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
  bin_path = CONSTANTS.BIN_PATH,
  test_conf = conf,
  test_conf_path = CONSTANTS.TEST_CONF_PATH,
  go_plugin_path = CONSTANTS.GO_PLUGIN_PATH,
  mock_upstream_hostname = CONSTANTS.MOCK_UPSTREAM_HOSTNAME,
  mock_upstream_protocol = CONSTANTS.MOCK_UPSTREAM_PROTOCOL,
  mock_upstream_host     = CONSTANTS.MOCK_UPSTREAM_HOST,
  mock_upstream_port     = CONSTANTS.MOCK_UPSTREAM_PORT,
  mock_upstream_url      = CONSTANTS.MOCK_UPSTREAM_PROTOCOL .. "://" ..
                           CONSTANTS.MOCK_UPSTREAM_HOST .. ':' ..
                           CONSTANTS.MOCK_UPSTREAM_PORT,

  mock_upstream_ssl_protocol = CONSTANTS.MOCK_UPSTREAM_SSL_PROTOCOL,
  mock_upstream_ssl_host     = CONSTANTS.MOCK_UPSTREAM_HOST,
  mock_upstream_ssl_port     = CONSTANTS.MOCK_UPSTREAM_SSL_PORT,
  mock_upstream_ssl_url      = CONSTANTS.MOCK_UPSTREAM_SSL_PROTOCOL .. "://" ..
                               CONSTANTS.MOCK_UPSTREAM_HOST .. ':' ..
                               CONSTANTS.MOCK_UPSTREAM_SSL_PORT,

  mock_upstream_stream_port     = CONSTANTS.MOCK_UPSTREAM_STREAM_PORT,
  mock_upstream_stream_ssl_port = CONSTANTS.MOCK_UPSTREAM_STREAM_SSL_PORT,
  mock_grpc_upstream_proto_path = CONSTANTS.MOCK_GRPC_UPSTREAM_PROTO_PATH,

  zipkin_host = CONSTANTS.ZIPKIN_HOST,
  zipkin_port = CONSTANTS.ZIPKIN_PORT,

  otelcol_host               = CONSTANTS.OTELCOL_HOST,
  otelcol_http_port          = CONSTANTS.OTELCOL_HTTP_PORT,
  otelcol_zpages_port        = CONSTANTS.OTELCOL_ZPAGES_PORT,
  otelcol_file_exporter_path = CONSTANTS.OTELCOL_FILE_EXPORTER_PATH,

  grpcbin_host     = CONSTANTS.GRPCBIN_HOST,
  grpcbin_port     = CONSTANTS.GRPCBIN_PORT,
  grpcbin_ssl_port = CONSTANTS.GRPCBIN_SSL_PORT,
  grpcbin_url      = string.format("grpc://%s:%d", CONSTANTS.GRPCBIN_HOST, CONSTANTS.GRPCBIN_PORT),
  grpcbin_ssl_url  = string.format("grpcs://%s:%d", CONSTANTS.GRPCBIN_HOST, CONSTANTS.GRPCBIN_SSL_PORT),

  redis_host     = CONSTANTS.REDIS_HOST,
  redis_port     = CONSTANTS.REDIS_PORT,
  redis_ssl_port = CONSTANTS.REDIS_SSL_PORT,
  redis_ssl_sni  = CONSTANTS.REDIS_SSL_SNI,
  redis_auth_port = CONSTANTS.REDIS_AUTH_PORT,

  blackhole_host = CONSTANTS.BLACKHOLE_HOST,

  old_version_kong_path = CONSTANTS.OLD_VERSION_KONG_PATH,

  -- Kong testing helpers
  execute = exec,
  dns_mock = dns_mock,
  kong_exec = kong_exec,
  get_version = get_version,
  get_running_conf = get_running_conf,
  http_client = http_client,
  grpc_client = grpc_client,
  http2_client = http2_client,
  make_synchronized_clients = make_synchronized_clients,
  wait_until = wait_until,
  pwait_until = pwait_until,
  wait_pid = wait_pid,
  wait_timer = wait_timer,
  wait_for_all_config_update = wait_for_all_config_update,
  wait_for_file = wait_for_file,
  wait_for_file_contents = wait_for_file_contents,
  tcp_server = server.tcp_server,
  udp_server = server.udp_server,
  kill_tcp_server = server.kill_tcp_server,
  is_echo_server_ready = is_echo_server_ready,
  echo_server_reset = echo_server_reset,
  get_echo_server_received_data = get_echo_server_received_data,
  http_mock = server.http_mock,
  get_proxy_ip = get_proxy_ip,
  get_proxy_port = get_proxy_port,
  proxy_client = proxy_client,
  proxy_client_grpc = proxy_client_grpc,
  proxy_client_grpcs = proxy_client_grpcs,
  proxy_client_h2c = proxy_client_h2c,
  proxy_client_h2 = proxy_client_h2,
  admin_client = admin_client,
  admin_gui_client = admin_gui_client,
  proxy_ssl_client = proxy_ssl_client,
  admin_ssl_client = admin_ssl_client,
  admin_gui_ssl_client = admin_gui_ssl_client,
  prepare_prefix = prepare_prefix,
  clean_prefix = clean_prefix,
  clean_logfile = clean_logfile,
  wait_for_invalidation = wait_for_invalidation,
  each_strategy = each_strategy,
  all_strategies = all_strategies,
  validate_plugin_config_schema = validate_plugin_config_schema,
  clustering_client = clustering_client,
  tmpdir = tmpdir,
  https_server = https_server,
  stress_generator = stress_generator,
  get_fixtures_path = get_fixtures_path,

  -- miscellaneous
  intercept = misc.intercept,
  openresty_ver_num = misc.openresty_ver_num,
  unindent = misc.unindent,
  make_yaml_file = misc.make_yaml_file,
  setenv = misc.setenv,
  unsetenv = misc.unsetenv,
  deep_sort = misc.deep_sort,
  generate_keys = misc.generate_keys,

  -- launching Kong subprocesses
  start_kong = start_kong,
  stop_kong = stop_kong,
  cleanup_kong = cleanup_kong,
  restart_kong = restart_kong,
  reload_kong = reload_kong,
  get_kong_workers = get_kong_workers,
  wait_until_no_common_workers = wait_until_no_common_workers,

  start_grpc_target = grpc.start_grpc_target,
  stop_grpc_target = grpc.stop_grpc_target,
  get_grpc_target_port = grpc.get_grpc_target_port,

  -- plugin compatibility test
  use_old_plugin = use_old_plugin,

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

  with_current_ws = function(ws,fn, db)
    local old_ws = ngx.ctx.workspace
    ngx.ctx.workspace = nil
    ws = ws or {db.workspaces:select_by_name("default")}
    ngx.ctx.workspace = ws[1] and ws[1].id
    local res = fn()
    ngx.ctx.workspace = old_ws
    return res
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

  -- send signal to all Nginx workers, not including the master
  signal_workers = function(prefix, signal, pid_path)
    if not pid_path then
      local running_conf = get_running_conf(prefix)
      if not running_conf then
        error("no config file found at prefix: " .. prefix)
      end

      pid_path = running_conf.nginx_pid
    end

    local cmd = string.format("pkill %s -P `cat %s`", signal, pid_path)
    local _, _, _, _, code = shell.run(cmd)

    if not pid_dead(pid_path) then
      return false
    end

    return code
  end,
  -- returns the plugins and version list that is used by Hybrid mode tests
  get_plugins_list = function()
    assert(PLUGINS_LIST, "plugin list has not been initialized yet, " ..
                         "you must call get_db_utils first")
    return table_clone(PLUGINS_LIST)
  end,
  get_available_port = get_available_port,

  make_temp_dir = make_temp_dir,

  -- XXX EE
  is_enterprise_plugin = function(plugin_name)
    for _, ee_plugin_name in pairs(dist_constants.plugins) do
      if ee_plugin_name == plugin_name then
        return true
      end
    end
    return false
  end,

  is_fips_build = function()
    local pro = require "resty.openssl.provider"
    local p = pro.load("fips")
    if p then p:unload() end
    return p ~= nil
  end,
  -- EE
}
