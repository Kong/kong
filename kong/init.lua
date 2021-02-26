-- Kong, the biggest ape in town
--
--     /\  ____
--     <> ( oo )
--     <>_| ^^ |_
--     <>   @    \
--    /~~\ . . _ |
--   /~~~~\    | |
--  /~~~~~~\/ _| |
--  |[][][]/ / [m]
--  |[][][[m]
--  |[][][]|
--  |[][][]|
--  |[][][]|
--  |[][][]|
--  |[][][]|
--  |[][][]|
--  |[][][]|
--  |[][][]|
--  |[|--|]|
--  |[|  |]|
--  ========
-- ==========
-- |[[    ]]|
-- ==========

pcall(require, "luarocks.loader")


assert(package.loaded["resty.core"], "lua-resty-core must be loaded; make " ..
                                     "sure 'lua_load_resty_core' is not "..
                                     "disabled.")


local constants = require "kong.constants"
do
  -- let's ensure the required shared dictionaries are
  -- declared via lua_shared_dict in the Nginx conf

  for _, dict in ipairs(constants.DICTS) do
    if not ngx.shared[dict] then
      return error("missing shared dict '" .. dict .. "' in Nginx "          ..
                   "configuration, are you using a custom template? "        ..
                   "Make sure the 'lua_shared_dict " .. dict .. " [SIZE];' " ..
                   "directive is defined.")
    end
  end

  -- if we're running `nginx -t` then don't initialize
  if os.getenv("KONG_NGINX_CONF_CHECK") then
    return {
      init = function() end,
    }
  end
end


require("kong.globalpatches")()


local kong_global = require "kong.global"
local PHASES = kong_global.phases


_G.kong = kong_global.new() -- no versioned PDK for plugins for now


local DB = require "kong.db"
local dns = require "kong.tools.dns"
local meta = require "kong.meta"
local lapis = require "lapis"
local runloop = require "kong.runloop.handler"
local stream_api = require "kong.tools.stream_api"
local clustering = require "kong.clustering"
local singletons = require "kong.singletons"
local declarative = require "kong.db.declarative"
local ngx_balancer = require "ngx.balancer"
local kong_resty_ctx = require "kong.resty.ctx"
local certificate = require "kong.runloop.certificate"
local concurrency = require "kong.concurrency"
local cache_warmup = require "kong.cache.warmup"
local balancer_execute = require("kong.runloop.balancer").execute
local kong_error_handlers = require "kong.error_handlers"
local migrations_utils = require "kong.cmd.utils.migrations"
local plugin_servers = require "kong.runloop.plugin_servers"

local kong             = kong
local ngx              = ngx
local now              = ngx.now
local update_time      = ngx.update_time
local var              = ngx.var
local arg              = ngx.arg
local header           = ngx.header
local ngx_log          = ngx.log
local ngx_ALERT        = ngx.ALERT
local ngx_CRIT         = ngx.CRIT
local ngx_ERR          = ngx.ERR
local ngx_WARN         = ngx.WARN
local ngx_INFO         = ngx.INFO
local ngx_DEBUG        = ngx.DEBUG
local subsystem        = ngx.config.subsystem
local start_time       = ngx.req.start_time
local type             = type
local error            = error
local ipairs           = ipairs
local assert           = assert
local tostring         = tostring
local coroutine        = coroutine
local get_last_failure = ngx_balancer.get_last_failure
local set_current_peer = ngx_balancer.set_current_peer
local set_timeouts     = ngx_balancer.set_timeouts
local set_more_tries   = ngx_balancer.set_more_tries
local enable_keepalive = ngx_balancer.enable_keepalive
if not enable_keepalive then
  ngx_log(ngx_WARN, "missing method 'ngx_balancer.enable_keepalive()' ",
                    "(was the dyn_upstream_keepalive patch applied?) ",
                    "set the 'nginx_upstream_keepalive' configuration ",
                    "property instead of 'upstream_keepalive_pool_size'")
end


local WORKER_COUNT = ngx.worker.count()
local DECLARATIVE_LOAD_KEY = constants.DECLARATIVE_LOAD_KEY
local DECLARATIVE_HASH_KEY = constants.DECLARATIVE_HASH_KEY
local DECLARATIVE_FLIPS_KEY = constants.DECLARATIVE_FLIPS.name
local DECLARATIVE_FLIPS_TTL = constants.DECLARATIVE_FLIPS.ttl


local declarative_entities
local declarative_meta
local schema_state


local stash_init_worker_error
local log_init_worker_errors
do
  local init_worker_errors
  local init_worker_errors_str
  local ctx_k = {}


  stash_init_worker_error = function(err)
    if err == nil then
      return
    end

    err = tostring(err)

    if not init_worker_errors then
      init_worker_errors = {}
    end

    table.insert(init_worker_errors, err)
    init_worker_errors_str = table.concat(init_worker_errors, ", ")

    return ngx_log(ngx_CRIT, "worker initialization error: ", err,
                             "; this node must be restarted")
  end


  log_init_worker_errors = function(ctx)
    if not init_worker_errors_str or ctx[ctx_k] then
      return
    end

    ctx[ctx_k] = true

    return ngx_log(ngx_ALERT, "unsafe request processing due to earlier ",
                              "initialization errors; this node must be ",
                              "restarted (", init_worker_errors_str, ")")
  end
end


local reset_kong_shm
do
  local DECLARATIVE_PAGE_KEY = constants.DECLARATIVE_PAGE_KEY
  local preserve_keys = {
    "kong:node_id",
    "events:requests",
    "events:requests:http",
    "events:requests:https",
    "events:requests:h2c",
    "events:requests:h2",
    "events:requests:grpc",
    "events:requests:grpcs",
    "events:requests:ws",
    "events:requests:wss",
    "events:requests:go_plugins",
    "events:streams",
    "events:streams:tcp",
    "events:streams:tls",
  }

  reset_kong_shm = function(config)
    local kong_shm = ngx.shared.kong
    local dbless = config.database == "off"
    local declarative_config = dbless and config.declarative_config

    if dbless then -- prevent POST /config from happening while initializing
      kong_shm:add(DECLARATIVE_FLIPS_KEY, 0, DECLARATIVE_FLIPS_TTL)
    end

    local old_page = kong_shm:get(DECLARATIVE_PAGE_KEY)
    if old_page == nil then -- fresh node, just storing the initial page
      kong_shm:set(DECLARATIVE_PAGE_KEY, 1)
      return
    end

    local preserved = {}

    local new_page
    if declarative_config then
      new_page = old_page == 1 and 2 or 1

    else
      new_page = old_page

      if dbless then
        preserved[DECLARATIVE_LOAD_KEY] = kong_shm:get(DECLARATIVE_LOAD_KEY)
        preserved[DECLARATIVE_HASH_KEY] = kong_shm:get(DECLARATIVE_HASH_KEY)
      end
    end

    preserved[DECLARATIVE_PAGE_KEY] = new_page

    for _, key in ipairs(preserve_keys) do
      preserved[key] = kong_shm:get(key) -- ignore errors
    end

    kong_shm:flush_all()
    if dbless then
      kong_shm:add(DECLARATIVE_FLIPS_KEY, 0, DECLARATIVE_FLIPS_TTL)
    end
    for key, value in pairs(preserved) do
      kong_shm:set(key, value)
    end
    kong_shm:flush_expired(0)
  end
end


local function execute_plugins_iterator(plugins_iterator, phase, ctx)
  local old_ws
  local delay_response

  if ctx then
    old_ws = ctx.workspace
    delay_response = phase == "access" or nil
    ctx.delay_response = delay_response
  end

  for plugin, configuration in plugins_iterator:iterate(phase, ctx) do
    if ctx then
      if plugin.handler._go then
        ctx.ran_go_plugin = true
      end

      kong_global.set_named_ctx(kong, "plugin", plugin.handler)
    end

    kong_global.set_namespaced_log(kong, plugin.name)

    if not delay_response then
      plugin.handler[phase](plugin.handler, configuration)

    elseif not ctx.delayed_response then
      local co = coroutine.create(plugin.handler.access)
      local cok, cerr = coroutine.resume(co, plugin.handler, configuration)
      if not cok then
        kong.log.err(cerr)
        ctx.delayed_response = {
          status_code = 500,
          content = { message  = "An unexpected error occurred" },
        }
      end
    end

    kong_global.reset_log(kong)

    if old_ws then
      ctx.workspace = old_ws
    end
  end
end


local function execute_cache_warmup(kong_config)
  if kong_config.database == "off" then
    return true
  end

  if ngx.worker.id() == 0 then
    local ok, err = cache_warmup.execute(kong_config.db_cache_warmup_entities)
    if not ok then
      return nil, err
    end
  end

  return true
end


local function get_now_ms()
  update_time()
  return now() * 1000 -- time is kept in seconds with millisecond resolution.
end


local function flush_delayed_response(ctx)
  ctx.delay_response = nil
  ctx.buffered_proxying = nil

  if type(ctx.delayed_response_callback) == "function" then
    ctx.delayed_response_callback(ctx)
    return -- avoid tail call
  end

  kong.response.exit(ctx.delayed_response.status_code,
                     ctx.delayed_response.content,
                     ctx.delayed_response.headers)
end


local function parse_declarative_config(kong_config)
  if kong_config.database ~= "off" then
    return {}, nil, {}
  end

  local dc = declarative.new_config(kong_config)

  if not kong_config.declarative_config then
    -- return an empty configuration,
    -- including only the default workspace
    local entities, _, _, meta = dc:parse_table({ _format_version = "2.1" })
    return entities, nil, meta
  end

  local entities, err, _, meta = dc:parse_file(kong_config.declarative_config)
  if not entities then
    return nil, "error parsing declarative config file " ..
                kong_config.declarative_config .. ":\n" .. err
  end

  return entities, nil, meta
end


local function load_declarative_config(kong_config, entities, meta)
  if kong_config.database ~= "off" then
    return true
  end

  local opts = {
    name = "declarative_config",
  }

  local kong_shm = ngx.shared.kong
  local ok, err = concurrency.with_worker_mutex(opts, function()
    local value = kong_shm:get(DECLARATIVE_LOAD_KEY)
    if value then
      return true
    end

    local ok, err = declarative.load_into_cache(entities, meta)
    if not ok then
      return nil, err
    end

    if kong_config.declarative_config then
      kong.log.notice("declarative config loaded from ",
                      kong_config.declarative_config)
    end

    ok, err = kong_shm:safe_set(DECLARATIVE_LOAD_KEY, true)
    if not ok then
      kong.log.warn("failed marking declarative_config as loaded: ", err)
    end

    return true
  end)

  if ok then
    if kong_shm:get(DECLARATIVE_FLIPS_KEY) then
      local flips = kong_shm:incr(DECLARATIVE_FLIPS_KEY, 1)
      if flips and flips >= WORKER_COUNT then
        kong_shm:delete(DECLARATIVE_FLIPS_KEY)
      end
    end

    local default_ws = kong.db.workspaces:select_by_name("default")
    kong.default_workspace = default_ws and default_ws.id or kong.default_workspace

    ok, err = runloop.build_plugins_iterator("init")
    if not ok then
      return nil, "error building initial plugins iterator: " .. err
    end

    ok, err = runloop.build_router("init")
    if not ok then
      return nil, "error building initial router: " .. err
    end
  end

  return ok, err
end


local function list_migrations(migtable)
  local list = {}
  for _, t in ipairs(migtable) do
    local mignames = {}
    for _, mig in ipairs(t.migrations) do
      table.insert(mignames, mig.name)
    end
    table.insert(list, string.format("%s (%s)", t.subsystem,
                       table.concat(mignames, ", ")))
  end
  return table.concat(list, " ")
end


-- Kong public context handlers.
-- @section kong_handlers

local Kong = {}


function Kong.init()
  local pl_path = require "pl.path"
  local conf_loader = require "kong.conf_loader"

  -- check if kong global is the correct one
  if not kong.version then
    error("configuration error: make sure your template is not setting a " ..
          "global named 'kong' (please use 'Kong' instead)")
  end

  -- retrieve kong_config
  local conf_path = pl_path.join(ngx.config.prefix(), ".kong_env")
  local config = assert(conf_loader(conf_path, nil, { from_kong_env = true }))

  reset_kong_shm(config)

  -- special math.randomseed from kong.globalpatches not taking any argument.
  -- Must only be called in the init or init_worker phases, to avoid
  -- duplicated seeds.
  math.randomseed()

  kong_global.init_pdk(kong, config, nil) -- nil: latest PDK

  local db = assert(DB.new(config))
  assert(db:init_connector())

  schema_state = assert(db:schema_state())
  migrations_utils.check_state(schema_state)

  if schema_state.missing_migrations or schema_state.pending_migrations then
    if schema_state.missing_migrations then
      ngx_log(ngx_WARN, "database is missing some migrations:\n",
                        schema_state.missing_migrations)
    end

    if schema_state.pending_migrations then
      ngx_log(ngx_WARN, "database has pending migrations:\n",
                        schema_state.pending_migrations)
    end
  end

  assert(db:connect())

  -- LEGACY
  singletons.dns = dns(config)
  singletons.configuration = config
  singletons.db = db
  -- /LEGACY

  kong.db = db
  kong.dns = singletons.dns

  if config.proxy_ssl_enabled or config.stream_ssl_enabled then
    certificate.init()
  end

  if subsystem == "http" then
    clustering.init(config)
  end

  -- Load plugins as late as possible so that everything is set up
  assert(db.plugins:load_plugin_schemas(config.loaded_plugins))

  if subsystem == "stream" then
    stream_api.load_handlers()
  end

  if config.database == "off" then
    local err
    declarative_entities, err, declarative_meta = parse_declarative_config(kong.configuration)
    if not declarative_entities then
      error(err)
    end

  else
    local default_ws = db.workspaces:select_by_name("default")
    kong.default_workspace = default_ws and default_ws.id

    local ok, err = runloop.build_plugins_iterator("init")
    if not ok then
      error("error building initial plugins: " .. tostring(err))
    end

    if config.role ~= "control_plane" then
      assert(runloop.build_router("init"))
    end
  end

  db:close()
end


function Kong.init_worker()
  kong_global.set_phase(kong, PHASES.init_worker)

  -- special math.randomseed from kong.globalpatches not taking any argument.
  -- Must only be called in the init or init_worker phases, to avoid
  -- duplicated seeds.
  math.randomseed()


  -- init DB


  local ok, err = kong.db:init_worker()
  if not ok then
    stash_init_worker_error("failed to instantiate 'kong.db' module: " .. err)
    return
  end


  if ngx.worker.id() == 0 then
    if schema_state.missing_migrations then
      ngx_log(ngx_WARN, "missing migrations: ",
              list_migrations(schema_state.missing_migrations))
    end

    if schema_state.pending_migrations then
      ngx_log(ngx_INFO, "starting with pending migrations: ",
              list_migrations(schema_state.pending_migrations))
    end
  end

  local worker_events, err = kong_global.init_worker_events()
  if not worker_events then
    stash_init_worker_error("failed to instantiate 'kong.worker_events' " ..
                            "module: " .. err)
    return
  end
  kong.worker_events = worker_events

  local cluster_events, err = kong_global.init_cluster_events(kong.configuration, kong.db)
  if not cluster_events then
    stash_init_worker_error("failed to instantiate 'kong.cluster_events' " ..
                            "module: " .. err)
    return
  end
  kong.cluster_events = cluster_events

  local cache, err = kong_global.init_cache(kong.configuration, cluster_events, worker_events)
  if not cache then
    stash_init_worker_error("failed to instantiate 'kong.cache' module: " ..
                            err)
    return
  end
  kong.cache = cache

  local core_cache, err = kong_global.init_core_cache(kong.configuration, cluster_events, worker_events)
  if not core_cache then
    stash_init_worker_error("failed to instantiate 'kong.core_cache' module: " ..
                            err)
    return
  end
  kong.core_cache = core_cache

  ok, err = runloop.set_init_versions_in_cache()
  if not ok then
    stash_init_worker_error(err) -- 'err' fully formatted
    return
  end

  -- LEGACY
  singletons.cache          = cache
  singletons.core_cache     = core_cache
  singletons.worker_events  = worker_events
  singletons.cluster_events = cluster_events
  -- /LEGACY

  kong.db:set_events_handler(worker_events)

  ok, err = load_declarative_config(kong.configuration,
                                    declarative_entities,
                                    declarative_meta)
  if not ok then
    stash_init_worker_error("failed to load declarative config file: " .. err)
    return
  end

  if kong.configuration.role ~= "control_plane" then
    ok, err = execute_cache_warmup(kong.configuration)
    if not ok then
      ngx_log(ngx_ERR, "failed to warm up the DB cache: " .. err)
    end
  end

  runloop.init_worker.before()

  -- run plugins init_worker context
  ok, err = runloop.update_plugins_iterator()
  if not ok then
    stash_init_worker_error("failed to build the plugins iterator: " .. err)
    return
  end

  local plugins_iterator = runloop.get_plugins_iterator()
  execute_plugins_iterator(plugins_iterator, "init_worker")

  runloop.init_worker.after()

  if kong.configuration.role ~= "control_plane" then
    plugin_servers.start()
  end

  if subsystem == "http" then
    clustering.init_worker(kong.configuration)
  end
end


function Kong.preread()
  local ctx = ngx.ctx
  if not ctx.KONG_PROCESSING_START then
    ctx.KONG_PROCESSING_START = start_time() * 1000
  end

  if not ctx.KONG_PREREAD_START then
    ctx.KONG_PREREAD_START = get_now_ms()
  end

  kong_global.set_phase(kong, PHASES.preread)

  log_init_worker_errors(ctx)

  runloop.preread.before(ctx)

  local plugins_iterator = runloop.get_updated_plugins_iterator()
  execute_plugins_iterator(plugins_iterator, "preread", ctx)

  if not ctx.service then
    ctx.KONG_PREREAD_ENDED_AT = get_now_ms()
    ctx.KONG_PREREAD_TIME = ctx.KONG_PREREAD_ENDED_AT - ctx.KONG_PREREAD_START
    ctx.KONG_RESPONSE_LATENCY = ctx.KONG_PREREAD_ENDED_AT - ctx.KONG_PROCESSING_START

    ngx_log(ngx_WARN, "no Service found with those values")
    return ngx.exit(503)
  end

  runloop.preread.after(ctx)

  ctx.KONG_PREREAD_ENDED_AT = get_now_ms()
  ctx.KONG_PREREAD_TIME = ctx.KONG_PREREAD_ENDED_AT - ctx.KONG_PREREAD_START

  -- we intent to proxy, though balancer may fail on that
  ctx.KONG_PROXIED = true
end


function Kong.ssl_certificate()
  kong_global.set_phase(kong, PHASES.certificate)

  -- this doesn't really work across the phases currently (OpenResty 1.13.6.2),
  -- but it returns a table (rewrite phase clears it)
  local ctx = ngx.ctx
  log_init_worker_errors(ctx)

  -- this is the first phase to run on an HTTPS request
  ctx.workspace = kong.default_workspace

  runloop.certificate.before(ctx)
  local plugins_iterator = runloop.get_updated_plugins_iterator()
  execute_plugins_iterator(plugins_iterator, "certificate", ctx)
  runloop.certificate.after(ctx)
end


function Kong.rewrite()
  local proxy_mode = var.kong_proxy_mode
  if proxy_mode == "grpc" or proxy_mode == "unbuffered"  then
    kong_resty_ctx.apply_ref() -- if kong_proxy_mode is gRPC/unbuffered, this is executing
    kong_resty_ctx.stash_ref() -- after an internal redirect. Restore (and restash)
                               -- context to avoid re-executing phases

    local ctx = ngx.ctx
    ctx.KONG_REWRITE_ENDED_AT = get_now_ms()
    ctx.KONG_REWRITE_TIME = ctx.KONG_REWRITE_ENDED_AT - ctx.KONG_REWRITE_START

    return
  end

  local ctx = ngx.ctx
  if not ctx.KONG_PROCESSING_START then
    ctx.KONG_PROCESSING_START = start_time() * 1000
  end

  if not ctx.KONG_REWRITE_START then
    ctx.KONG_REWRITE_START = get_now_ms()
  end

  kong_global.set_phase(kong, PHASES.rewrite)
  kong_resty_ctx.stash_ref(ctx)

  local is_https = var.https == "on"
  if not is_https then
    log_init_worker_errors(ctx)
  end

  runloop.rewrite.before(ctx)

  if not ctx.workspace then
    ctx.workspace = kong.default_workspace
  end

  -- On HTTPS requests, the plugins iterator is already updated in the ssl_certificate phase
  local plugins_iterator
  if is_https then
    plugins_iterator = runloop.get_plugins_iterator()
  else
    plugins_iterator = runloop.get_updated_plugins_iterator()
  end

  execute_plugins_iterator(plugins_iterator, "rewrite", ctx)

  runloop.rewrite.after(ctx)

  ctx.KONG_REWRITE_ENDED_AT = get_now_ms()
  ctx.KONG_REWRITE_TIME = ctx.KONG_REWRITE_ENDED_AT - ctx.KONG_REWRITE_START
end


function Kong.access()
  local ctx = ngx.ctx
  if not ctx.KONG_ACCESS_START then
    ctx.KONG_ACCESS_START = get_now_ms()

    if ctx.KONG_REWRITE_START and not ctx.KONG_REWRITE_ENDED_AT then
      ctx.KONG_REWRITE_ENDED_AT = ctx.KONG_ACCESS_START
      ctx.KONG_REWRITE_TIME = ctx.KONG_REWRITE_ENDED_AT - ctx.KONG_REWRITE_START
    end
  end

  kong_global.set_phase(kong, PHASES.access)

  runloop.access.before(ctx)

  local plugins_iterator = runloop.get_plugins_iterator()

  execute_plugins_iterator(plugins_iterator, "access", ctx)

  if ctx.delayed_response then
    ctx.KONG_ACCESS_ENDED_AT = get_now_ms()
    ctx.KONG_ACCESS_TIME = ctx.KONG_ACCESS_ENDED_AT - ctx.KONG_ACCESS_START
    ctx.KONG_RESPONSE_LATENCY = ctx.KONG_ACCESS_ENDED_AT - ctx.KONG_PROCESSING_START

    return flush_delayed_response(ctx)
  end

  ctx.delay_response = nil

  if not ctx.service then
    ctx.KONG_ACCESS_ENDED_AT = get_now_ms()
    ctx.KONG_ACCESS_TIME = ctx.KONG_ACCESS_ENDED_AT - ctx.KONG_ACCESS_START
    ctx.KONG_RESPONSE_LATENCY = ctx.KONG_ACCESS_ENDED_AT - ctx.KONG_PROCESSING_START

    ctx.buffered_proxying = nil

    return kong.response.exit(503, { message = "no Service found with those values"})
  end

  runloop.access.after(ctx)

  ctx.KONG_ACCESS_ENDED_AT = get_now_ms()
  ctx.KONG_ACCESS_TIME = ctx.KONG_ACCESS_ENDED_AT - ctx.KONG_ACCESS_START

  -- we intent to proxy, though balancer may fail on that
  ctx.KONG_PROXIED = true

  if ctx.buffered_proxying and ngx.req.http_version() < 2 then
    return Kong.response()
  end
end

do
  local HTTP_METHODS = {
    GET       = ngx.HTTP_GET,
    HEAD      = ngx.HTTP_HEAD,
    PUT       = ngx.HTTP_PUT,
    POST      = ngx.HTTP_POST,
    DELETE    = ngx.HTTP_DELETE,
    OPTIONS   = ngx.HTTP_OPTIONS,
    MKCOL     = ngx.HTTP_MKCOL,
    COPY      = ngx.HTTP_COPY,
    MOVE      = ngx.HTTP_MOVE,
    PROPFIND  = ngx.HTTP_PROPFIND,
    PROPPATCH = ngx.HTTP_PROPPATCH,
    LOCK      = ngx.HTTP_LOCK,
    UNLOCK    = ngx.HTTP_UNLOCK,
    PATCH     = ngx.HTTP_PATCH,
    TRACE     = ngx.HTTP_TRACE,
  }

  function Kong.response()
    local plugins_iterator = runloop.get_plugins_iterator()

    local ctx = ngx.ctx

    -- buffered proxying (that also executes the balancer)
    ngx.req.read_body()

    local options = {
      always_forward_body = true,
      share_all_vars      = true,
      method              = HTTP_METHODS[ngx.req.get_method()],
      ctx                 = ctx,
    }

    local res = ngx.location.capture("/kong_buffered_http", options)
    if res.truncated then
      kong_global.set_phase(kong, PHASES.error)
      ngx.status = 502
      return kong_error_handlers(ctx)
    end

    kong_global.set_phase(kong, PHASES.response)

    local status = res.status
    local headers = res.header
    local body = res.body

    ctx.buffered_status = status
    ctx.buffered_headers = headers
    ctx.buffered_body = body

    -- fake response phase (this runs after the balancer)
    if not ctx.KONG_RESPONSE_START then
      ctx.KONG_RESPONSE_START = get_now_ms()

      if ctx.KONG_BALANCER_START and not ctx.KONG_BALANCER_ENDED_AT then
        ctx.KONG_BALANCER_ENDED_AT = ctx.KONG_RESPONSE_START
        ctx.KONG_BALANCER_TIME = ctx.KONG_BALANCER_ENDED_AT -
          ctx.KONG_BALANCER_START
      end
    end

    if not ctx.KONG_WAITING_TIME then
      ctx.KONG_WAITING_TIME = ctx.KONG_RESPONSE_START -
        (ctx.KONG_BALANCER_ENDED_AT or ctx.KONG_ACCESS_ENDED_AT)
    end

    if not ctx.KONG_PROXY_LATENCY then
      ctx.KONG_PROXY_LATENCY = ctx.KONG_RESPONSE_START - ctx.KONG_PROCESSING_START
    end

    kong.response.set_status(status)
    kong.response.set_headers(headers)

    runloop.response.before(ctx)
    execute_plugins_iterator(plugins_iterator, "response", ctx)
    runloop.response.after(ctx)

    ctx.KONG_RESPONSE_ENDED_AT = get_now_ms()
    ctx.KONG_RESPONSE_TIME = ctx.KONG_RESPONSE_ENDED_AT - ctx.KONG_RESPONSE_START

    -- buffered response
    ngx.print(body)
    -- jump over the balancer to header_filter
    ngx.exit(status)
  end
end


function Kong.balancer()
  -- This may be called multiple times, and no yielding here!
  local now_ms = get_now_ms()

  local ctx = ngx.ctx
  if not ctx.KONG_BALANCER_START then
    ctx.KONG_BALANCER_START = now_ms

    if subsystem == "stream" then
      if ctx.KONG_PREREAD_START and not ctx.KONG_PREREAD_ENDED_AT then
        ctx.KONG_PREREAD_ENDED_AT = ctx.KONG_BALANCER_START
        ctx.KONG_PREREAD_TIME = ctx.KONG_PREREAD_ENDED_AT -
                                ctx.KONG_PREREAD_START
      end

    else
      if ctx.KONG_REWRITE_START and not ctx.KONG_REWRITE_ENDED_AT then
        ctx.KONG_REWRITE_ENDED_AT = ctx.KONG_ACCESS_START or
                                    ctx.KONG_BALANCER_START
        ctx.KONG_REWRITE_TIME = ctx.KONG_REWRITE_ENDED_AT -
                                ctx.KONG_REWRITE_START
      end

      if ctx.KONG_ACCESS_START and not ctx.KONG_ACCESS_ENDED_AT then
        ctx.KONG_ACCESS_ENDED_AT = ctx.KONG_BALANCER_START
        ctx.KONG_ACCESS_TIME = ctx.KONG_ACCESS_ENDED_AT -
                               ctx.KONG_ACCESS_START
      end
    end
  end

  kong_global.set_phase(kong, PHASES.balancer)

  local balancer_data = ctx.balancer_data
  local tries = balancer_data.tries
  local current_try = {}
  balancer_data.try_count = balancer_data.try_count + 1
  tries[balancer_data.try_count] = current_try

  current_try.balancer_start = now_ms

  if balancer_data.try_count > 1 then
    -- only call balancer on retry, first one is done in `runloop.access.after`
    -- which runs in the ACCESS context and hence has less limitations than
    -- this BALANCER context where the retries are executed

    -- record failure data
    local previous_try = tries[balancer_data.try_count - 1]
    previous_try.state, previous_try.code = get_last_failure()

    -- Report HTTP status for health checks
    local balancer = balancer_data.balancer
    if balancer then
      if previous_try.state == "failed" then
        if previous_try.code == 504 then
          balancer.report_timeout(balancer_data.balancer_handle)
        else
          balancer.report_tcp_failure(balancer_data.balancer_handle)
        end

      else
        balancer.report_http_status(balancer_data.balancer_handle,
                                    previous_try.code)
      end
    end

    local ok, err, errcode = balancer_execute(balancer_data, ctx)
    if not ok then
      ngx_log(ngx_ERR, "failed to retry the dns/balancer resolver for ",
              tostring(balancer_data.host), "' with: ", tostring(err))

      ctx.KONG_BALANCER_ENDED_AT = get_now_ms()
      ctx.KONG_BALANCER_TIME = ctx.KONG_BALANCER_ENDED_AT - ctx.KONG_BALANCER_START
      ctx.KONG_PROXY_LATENCY = ctx.KONG_BALANCER_ENDED_AT - ctx.KONG_PROCESSING_START

      return ngx.exit(errcode)
    end

  else
    -- first try, so set the max number of retries
    local retries = balancer_data.retries
    if retries > 0 then
      set_more_tries(retries)
    end
  end

  local pool_opts
  local kong_conf = kong.configuration

  if enable_keepalive and kong_conf.upstream_keepalive_pool_size > 0
     and subsystem == "http"
  then
    local pool = balancer_data.ip .. "|" .. balancer_data.port

    if balancer_data.scheme == "https" then
      -- upstream_host is SNI
      pool = pool .. "|" .. var.upstream_host

      if ctx.service and ctx.service.client_certificate then
        pool = pool .. "|" .. ctx.service.client_certificate.id
      end
    end

    pool_opts = {
      pool = pool,
      pool_size = kong_conf.upstream_keepalive_pool_size,
    }
  end

  current_try.ip   = balancer_data.ip
  current_try.port = balancer_data.port

  -- set the targets as resolved
  ngx_log(ngx_DEBUG, "setting address (try ", balancer_data.try_count, "): ",
                     balancer_data.ip, ":", balancer_data.port)
  local ok, err = set_current_peer(balancer_data.ip, balancer_data.port, pool_opts)
  if not ok then
    ngx_log(ngx_ERR, "failed to set the current peer (address: ",
            tostring(balancer_data.ip), " port: ", tostring(balancer_data.port),
            "): ", tostring(err))

    ctx.KONG_BALANCER_ENDED_AT = get_now_ms()
    ctx.KONG_BALANCER_TIME = ctx.KONG_BALANCER_ENDED_AT - ctx.KONG_BALANCER_START
    ctx.KONG_PROXY_LATENCY = ctx.KONG_BALANCER_ENDED_AT - ctx.KONG_PROCESSING_START

    return ngx.exit(500)
  end

  ok, err = set_timeouts(balancer_data.connect_timeout / 1000,
                         balancer_data.send_timeout / 1000,
                         balancer_data.read_timeout / 1000)
  if not ok then
    ngx_log(ngx_ERR, "could not set upstream timeouts: ", err)
  end

  if pool_opts then
    ok, err = enable_keepalive(kong_conf.upstream_keepalive_idle_timeout,
                               kong_conf.upstream_keepalive_max_requests)
    if not ok then
      ngx_log(ngx_ERR, "could not enable connection keepalive: ", err)
    end

    ngx_log(ngx_DEBUG, "enabled connection keepalive (pool=", pool_opts.pool,
                       ", pool_size=", pool_opts.pool_size,
                       ", idle_timeout=", kong_conf.upstream_keepalive_idle_timeout,
                       ", max_requests=", kong_conf.upstream_keepalive_max_requests, ")")
  end

  -- record overall latency
  ctx.KONG_BALANCER_ENDED_AT = get_now_ms()
  ctx.KONG_BALANCER_TIME = ctx.KONG_BALANCER_ENDED_AT - ctx.KONG_BALANCER_START

  -- record try-latency
  local try_latency = ctx.KONG_BALANCER_ENDED_AT - current_try.balancer_start
  current_try.balancer_latency = try_latency

  -- time spent in Kong before sending the request to upstream
  -- start_time() is kept in seconds with millisecond resolution.
  ctx.KONG_PROXY_LATENCY = ctx.KONG_BALANCER_ENDED_AT - ctx.KONG_PROCESSING_START
end


function Kong.header_filter()
  local ctx = ngx.ctx
  if not ctx.KONG_PROCESSING_START then
    ctx.KONG_PROCESSING_START = start_time() * 1000
  end

  if not ctx.workspace then
    ctx.workspace = kong.default_workspace
  end

  if not ctx.KONG_HEADER_FILTER_START then
    ctx.KONG_HEADER_FILTER_START = get_now_ms()

    if ctx.KONG_REWRITE_START and not ctx.KONG_REWRITE_ENDED_AT then
      ctx.KONG_REWRITE_ENDED_AT = ctx.KONG_BALANCER_START or
                                  ctx.KONG_ACCESS_START or
                                  ctx.KONG_RESPONSE_START or
                                  ctx.KONG_HEADER_FILTER_START
      ctx.KONG_REWRITE_TIME = ctx.KONG_REWRITE_ENDED_AT -
                              ctx.KONG_REWRITE_START
    end

    if ctx.KONG_ACCESS_START and not ctx.KONG_ACCESS_ENDED_AT then
      ctx.KONG_ACCESS_ENDED_AT = ctx.KONG_BALANCER_START or
                                 ctx.KONG_RESPONSE_START or
                                 ctx.KONG_HEADER_FILTER_START
      ctx.KONG_ACCESS_TIME = ctx.KONG_ACCESS_ENDED_AT -
                             ctx.KONG_ACCESS_START
    end

    if ctx.KONG_BALANCER_START and not ctx.KONG_BALANCER_ENDED_AT then
      ctx.KONG_BALANCER_ENDED_AT = ctx.KONG_RESPONSE_START or
                                   ctx.KONG_HEADER_FILTER_START
      ctx.KONG_BALANCER_TIME = ctx.KONG_BALANCER_ENDED_AT -
                               ctx.KONG_BALANCER_START
    end

    if ctx.KONG_RESPONSE_START and not ctx.KONG_RESPONSE_ENDED_AT then
      ctx.KONG_RESPONSE_ENDED_AT = ctx.KONG_HEADER_FILTER_START
      ctx.KONG_RESPONSE_TIME = ctx.KONG_RESPONSE_ENDED_AT -
                               ctx.KONG_RESPONSE_START
    end
  end

  if ctx.KONG_PROXIED then
    if not ctx.KONG_WAITING_TIME then
      ctx.KONG_WAITING_TIME = (ctx.KONG_RESPONSE_START    or ctx.KONG_HEADER_FILTER_START) -
                              (ctx.KONG_BALANCER_ENDED_AT or ctx.KONG_ACCESS_ENDED_AT)
    end

    if not ctx.KONG_PROXY_LATENCY then
      ctx.KONG_PROXY_LATENCY = (ctx.KONG_RESPONSE_START or ctx.KONG_HEADER_FILTER_START) -
                                ctx.KONG_PROCESSING_START
    end

  elseif not ctx.KONG_RESPONSE_LATENCY then
    ctx.KONG_RESPONSE_LATENCY = (ctx.KONG_RESPONSE_START or ctx.KONG_HEADER_FILTER_START) -
                                 ctx.KONG_PROCESSING_START
  end

  kong_global.set_phase(kong, PHASES.header_filter)

  runloop.header_filter.before(ctx)
  local plugins_iterator = runloop.get_plugins_iterator()
  execute_plugins_iterator(plugins_iterator, "header_filter", ctx)
  runloop.header_filter.after(ctx)

  ctx.KONG_HEADER_FILTER_ENDED_AT = get_now_ms()
  ctx.KONG_HEADER_FILTER_TIME = ctx.KONG_HEADER_FILTER_ENDED_AT - ctx.KONG_HEADER_FILTER_START
end


function Kong.body_filter()
  local ctx = ngx.ctx
  if not ctx.KONG_BODY_FILTER_START then
    ctx.KONG_BODY_FILTER_START = get_now_ms()

    if ctx.KONG_REWRITE_START and not ctx.KONG_REWRITE_ENDED_AT then
      ctx.KONG_REWRITE_ENDED_AT = ctx.KONG_ACCESS_START or
                                  ctx.KONG_BALANCER_START or
                                  ctx.KONG_RESPONSE_START or
                                  ctx.KONG_HEADER_FILTER_START or
                                  ctx.KONG_BODY_FILTER_START
      ctx.KONG_REWRITE_TIME = ctx.KONG_REWRITE_ENDED_AT -
                              ctx.KONG_REWRITE_START
    end

    if ctx.KONG_ACCESS_START and not ctx.KONG_ACCESS_ENDED_AT then
      ctx.KONG_ACCESS_ENDED_AT = ctx.KONG_BALANCER_START or
                                 ctx.KONG_RESPONSE_START or
                                 ctx.KONG_HEADER_FILTER_START or
                                 ctx.KONG_BODY_FILTER_START
      ctx.KONG_ACCESS_TIME = ctx.KONG_ACCESS_ENDED_AT -
                             ctx.KONG_ACCESS_START
    end

    if ctx.KONG_BALANCER_START and not ctx.KONG_BALANCER_ENDED_AT then
      ctx.KONG_BALANCER_ENDED_AT = ctx.KONG_RESPONSE_START or
                                   ctx.KONG_HEADER_FILTER_START or
                                   ctx.KONG_BODY_FILTER_START
      ctx.KONG_BALANCER_TIME = ctx.KONG_BALANCER_ENDED_AT -
                               ctx.KONG_BALANCER_START
    end

    if ctx.KONG_RESPONSE_START and not ctx.KONG_RESPONSE_ENDED_AT then
      ctx.KONG_RESPONSE_ENDED_AT = ctx.KONG_HEADER_FILTER_START or
                                   ctx.KONG_BODY_FILTER_START
      ctx.KONG_RESPONSE_TIME = ctx.KONG_RESPONSE_ENDED_AT -
                               ctx.KONG_RESPONSE_START
    end

    if ctx.KONG_HEADER_FILTER_START and not ctx.KONG_HEADER_FILTER_ENDED_AT then
      ctx.KONG_HEADER_FILTER_ENDED_AT = ctx.KONG_BODY_FILTER_START
      ctx.KONG_HEADER_FILTER_TIME = ctx.KONG_HEADER_FILTER_ENDED_AT -
                                    ctx.KONG_HEADER_FILTER_START
    end
  end

  kong_global.set_phase(kong, PHASES.body_filter)

  if ctx.response_body then
    arg[1] = ctx.response_body
    arg[2] = true
  end

  local plugins_iterator = runloop.get_plugins_iterator()
  execute_plugins_iterator(plugins_iterator, "body_filter", ctx)

  if not arg[2] then
    return
  end

  ctx.KONG_BODY_FILTER_ENDED_AT = get_now_ms()
  ctx.KONG_BODY_FILTER_TIME = ctx.KONG_BODY_FILTER_ENDED_AT - ctx.KONG_BODY_FILTER_START

  if ctx.KONG_PROXIED then
    -- time spent receiving the response ((response +) header_filter + body_filter)
    -- we could use $upstream_response_time but we need to distinguish the waiting time
    -- from the receiving time in our logging plugins (especially ALF serializer).
    ctx.KONG_RECEIVE_TIME = ctx.KONG_BODY_FILTER_ENDED_AT - (ctx.KONG_RESPONSE_START or
                                                             ctx.KONG_HEADER_FILTER_START or
                                                             ctx.KONG_BALANCER_ENDED_AT or
                                                             ctx.KONG_BALANCER_START or
                                                             ctx.KONG_ACCESS_ENDED_AT)
  end
end


function Kong.log()
  local ctx = ngx.ctx
  if not ctx.KONG_LOG_START then
    ctx.KONG_LOG_START = get_now_ms()
    if subsystem == "stream" then
      if not ctx.KONG_PROCESSING_START then
        ctx.KONG_PROCESSING_START = start_time() * 1000
      end

      if ctx.KONG_PREREAD_START and not ctx.KONG_PREREAD_ENDED_AT then
        ctx.KONG_PREREAD_ENDED_AT = ctx.KONG_LOG_START
        ctx.KONG_PREREAD_TIME = ctx.KONG_PREREAD_ENDED_AT -
                                ctx.KONG_PREREAD_START
      end

      if ctx.KONG_BALANCER_START and not ctx.KONG_BALANCER_ENDED_AT then
        ctx.KONG_BALANCER_ENDED_AT = ctx.KONG_LOG_START
        ctx.KONG_BALANCER_TIME = ctx.KONG_BALANCER_ENDED_AT -
                                 ctx.KONG_BALANCER_START
      end

      if ctx.KONG_PROXIED then
        if not ctx.KONG_PROXY_LATENCY then
          ctx.KONG_PROXY_LATENCY = ctx.KONG_LOG_START -
                                   ctx.KONG_PROCESSING_START
        end

      elseif not ctx.KONG_RESPONSE_LATENCY then
        ctx.KONG_RESPONSE_LATENCY = ctx.KONG_LOG_START -
                                    ctx.KONG_PROCESSING_START
      end

    else
      if ctx.KONG_REWRITE_START and not ctx.KONG_REWRITE_ENDED_AT then
        ctx.KONG_REWRITE_ENDED_AT = ctx.KONG_ACCESS_START or
                                    ctx.KONG_BALANCER_START or
                                    ctx.KONG_RESPONSE_START or
                                    ctx.KONG_HEADER_FILTER_START or
                                    ctx.BODY_FILTER_START or
                                    ctx.KONG_LOG_START
        ctx.KONG_REWRITE_TIME = ctx.KONG_REWRITE_ENDED_AT -
                                ctx.KONG_REWRITE_START
      end

      if ctx.KONG_ACCESS_START and not ctx.KONG_ACCESS_ENDED_AT then
        ctx.KONG_ACCESS_ENDED_AT = ctx.KONG_BALANCER_START or
                                   ctx.KONG_RESPONSE_START or
                                   ctx.KONG_HEADER_FILTER_START or
                                   ctx.BODY_FILTER_START or
                                   ctx.KONG_LOG_START
        ctx.KONG_ACCESS_TIME = ctx.KONG_ACCESS_ENDED_AT -
                               ctx.KONG_ACCESS_START
      end

      if ctx.KONG_BALANCER_START and not ctx.KONG_BALANCER_ENDED_AT then
        ctx.KONG_BALANCER_ENDED_AT = ctx.KONG_RESPONSE_START or
                                     ctx.KONG_HEADER_FILTER_START or
                                     ctx.BODY_FILTER_START or
                                     ctx.KONG_LOG_START
        ctx.KONG_BALANCER_TIME = ctx.KONG_BALANCER_ENDED_AT -
                                 ctx.KONG_BALANCER_START
      end

      if ctx.KONG_HEADER_FILTER_START and not ctx.KONG_HEADER_FILTER_ENDED_AT then
        ctx.KONG_HEADER_FILTER_ENDED_AT = ctx.BODY_FILTER_START or
                                          ctx.KONG_LOG_START
        ctx.KONG_HEADER_FILTER_TIME = ctx.KONG_HEADER_FILTER_ENDED_AT -
                                      ctx.KONG_HEADER_FILTER_START
      end

      if ctx.KONG_BODY_FILTER_START and not ctx.KONG_BODY_FILTER_ENDED_AT then
        ctx.KONG_BODY_FILTER_ENDED_AT = ctx.KONG_LOG_START
        ctx.KONG_BODY_FILTER_TIME = ctx.KONG_BODY_FILTER_ENDED_AT -
                                    ctx.KONG_BODY_FILTER_START
      end

      if ctx.KONG_PROXIED and not ctx.KONG_WAITING_TIME then
        ctx.KONG_WAITING_TIME = ctx.KONG_LOG_START -
                                (ctx.KONG_BALANCER_ENDED_AT or ctx.KONG_ACCESS_ENDED_AT)
      end
    end
  end

  kong_global.set_phase(kong, PHASES.log)

  runloop.log.before(ctx)
  local plugins_iterator = runloop.get_plugins_iterator()
  execute_plugins_iterator(plugins_iterator, "log", ctx)
  runloop.log.after(ctx)


  -- this is not used for now, but perhaps we need it later?
  --ctx.KONG_LOG_ENDED_AT = get_now_ms()
  --ctx.KONG_LOG_TIME = ctx.KONG_LOG_ENDED_AT - ctx.KONG_LOG_START
end


function Kong.handle_error()
  kong_resty_ctx.apply_ref()
  kong_global.set_phase(kong, PHASES.error)

  local ctx = ngx.ctx
  ctx.KONG_UNEXPECTED = true

  local old_ws = ctx.workspace
  log_init_worker_errors(ctx)

  if not ctx.plugins then
    local plugins_iterator = runloop.get_updated_plugins_iterator()
    for _ in plugins_iterator:iterate("content", ctx) do
      -- just build list of plugins
      ctx.workspace = old_ws
    end
  end

  return kong_error_handlers(ctx)
end


local function serve_content(module, options)
  kong_global.set_phase(kong, PHASES.admin_api)

  local ctx = ngx.ctx
  ctx.KONG_PROCESSING_START = start_time() * 1000
  ctx.KONG_ADMIN_CONTENT_START = ctx.KONG_ADMIN_CONTENT_START or get_now_ms()


  log_init_worker_errors(ctx)

  options = options or {}

  header["Access-Control-Allow-Origin"] = options.allow_origin or "*"

  if ngx.req.get_method() == "OPTIONS" then
    header["Access-Control-Allow-Methods"] = "GET, HEAD, PUT, PATCH, POST, DELETE"
    header["Access-Control-Allow-Headers"] = "Content-Type"

    ctx.KONG_ADMIN_CONTENT_ENDED_AT = get_now_ms()
    ctx.KONG_ADMIN_CONTENT_TIME = ctx.KONG_ADMIN_CONTENT_ENDED_AT - ctx.KONG_ADMIN_CONTENT_START
    ctx.KONG_ADMIN_LATENCY = ctx.KONG_ADMIN_CONTENT_ENDED_AT - ctx.KONG_PROCESSING_START

    return ngx.exit(204)
  end

  lapis.serve(module)

  ctx.KONG_ADMIN_CONTENT_ENDED_AT = get_now_ms()
  ctx.KONG_ADMIN_CONTENT_TIME = ctx.KONG_ADMIN_CONTENT_ENDED_AT - ctx.KONG_ADMIN_CONTENT_START
  ctx.KONG_ADMIN_LATENCY = ctx.KONG_ADMIN_CONTENT_ENDED_AT - ctx.KONG_PROCESSING_START
end


function Kong.admin_content(options)
  kong.worker_events.poll()

  local ctx = ngx.ctx
  if not ctx.workspace then
    ctx.workspace = kong.default_workspace
  end

  return serve_content("kong.api", options)
end


-- TODO: deprecate the following alias
Kong.serve_admin_api = Kong.admin_content


function Kong.admin_header_filter()
  local ctx = ngx.ctx

  if not ctx.KONG_PROCESSING_START then
    ctx.KONG_PROCESSING_START = start_time() * 1000
  end

  if not ctx.KONG_ADMIN_HEADER_FILTER_START then
    ctx.KONG_ADMIN_HEADER_FILTER_START = get_now_ms()

    if ctx.KONG_ADMIN_CONTENT_START and not ctx.KONG_ADMIN_CONTENT_ENDED_AT then
      ctx.KONG_ADMIN_CONTENT_ENDED_AT = ctx.KONG_ADMIN_HEADER_FILTER_START
      ctx.KONG_ADMIN_CONTENT_TIME = ctx.KONG_ADMIN_CONTENT_ENDED_AT - ctx.KONG_ADMIN_CONTENT_START
    end

    if not ctx.KONG_ADMIN_LATENCY then
      ctx.KONG_ADMIN_LATENCY = ctx.KONG_ADMIN_HEADER_FILTER_START - ctx.KONG_PROCESSING_START
    end
  end

  local enabled_headers = kong.configuration.enabled_headers
  local headers = constants.HEADERS

  if enabled_headers[headers.ADMIN_LATENCY] then
    header[headers.ADMIN_LATENCY] = ctx.KONG_ADMIN_LATENCY
  end

  if enabled_headers[headers.SERVER] then
    header[headers.SERVER] = meta._SERVER_TOKENS

  else
    header[headers.SERVER] = nil
  end

  -- this is not used for now, but perhaps we need it later?
  --ctx.KONG_ADMIN_HEADER_FILTER_ENDED_AT = get_now_ms()
  --ctx.KONG_ADMIN_HEADER_FILTER_TIME = ctx.KONG_ADMIN_HEADER_FILTER_ENDED_AT - ctx.KONG_ADMIN_HEADER_FILTER_START
end


function Kong.status_content()
  return serve_content("kong.status")
end


Kong.status_header_filter = Kong.admin_header_filter


function Kong.serve_cluster_listener(options)
  log_init_worker_errors()

  kong_global.set_phase(kong, PHASES.cluster_listener)

  return clustering.handle_cp_websocket()
end


function Kong.stream_api()
  stream_api.handle()
end


do
  local declarative = require("kong.db.declarative")
  local cjson = require("cjson.safe")

  function Kong.stream_config_listener()
    local sock, err = ngx.req.socket()
    if not sock then
      kong.log.crit("unable to obtain request socket: ", err)
      return
    end

    local data, err = sock:receive("*a")
    if not data then
      ngx_log(ngx_CRIT, "unable to receive new config: ", err)
      return
    end

    local parsed
    parsed, err = cjson.decode(data)
    if not parsed then
      kong.log.err("unable to parse received declarative config: ", err)
      return
    end

    local ok, err = declarative.load_into_cache_with_events(parsed[1], parsed[2])
    if not ok then
      if err == "no memory" then
        kong.log.err("not enough cache space for declarative config, " ..
                     "consider raising the \"mem_cache_size\" Kong config")

      else
        kong.log.err("failed loading declarative config into cache: ", err)
      end
    end
  end
end


return Kong
