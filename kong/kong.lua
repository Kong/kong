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

do
  -- let's ensure the required shared dictionaries are
  -- declared via lua_shared_dict in the Nginx conf

  local constants = require "kong.constants"

  for _, dict in ipairs(constants.DICTS) do
    if not ngx.shared[dict] then
      return error("missing shared dict '" .. dict .. "' in Nginx "          ..
                   "configuration, are you using a custom template? "        ..
                   "Make sure the 'lua_shared_dict " .. dict .. " [SIZE];' " ..
                   "directive is defined.")
    end
  end
end

require("kong.core.globalpatches")()

local ip = require "kong.tools.ip"
local dns = require "kong.tools.dns"
local core = require "kong.core.handler"
local utils = require "kong.tools.utils"
local responses = require "kong.tools.responses"
local singletons = require "kong.singletons"
local DAOFactory = require "kong.dao.factory"
local kong_cache = require "kong.cache"
local ngx_balancer = require "ngx.balancer"
local plugins_iterator = require "kong.core.plugins_iterator"
local balancer_execute = require("kong.core.balancer").execute
local kong_cluster_events = require "kong.cluster_events"

local ipairs           = ipairs
local get_last_failure = ngx_balancer.get_last_failure
local set_current_peer = ngx_balancer.set_current_peer
local set_timeouts     = ngx_balancer.set_timeouts
local set_more_tries   = ngx_balancer.set_more_tries

local function load_plugins(kong_conf, dao)
  local in_db_plugins, sorted_plugins = {}, {}

  ngx.log(ngx.DEBUG, "Discovering used plugins")

  local rows, err_t = dao.plugins:find_all()
  if not rows then
    return nil, tostring(err_t)
  end

  for _, row in ipairs(rows) do in_db_plugins[row.name] = true end

  -- check all plugins in DB are enabled/installed
  for plugin in pairs(in_db_plugins) do
    if not kong_conf.plugins[plugin] then
      return nil, plugin .. " plugin is in use but not enabled"
    end
  end

  -- load installed plugins
  for plugin in pairs(kong_conf.plugins) do
    local ok, handler = utils.load_module_if_exists("kong.plugins." .. plugin .. ".handler")
    if not ok then
      return nil, plugin .. " plugin is enabled but not installed;\n" .. handler
    end

    local ok, schema = utils.load_module_if_exists("kong.plugins." .. plugin .. ".schema")
    if not ok then
      return nil, "no configuration schema found for plugin: " .. plugin
    end

    ngx.log(ngx.DEBUG, "Loading plugin: " .. plugin)

    sorted_plugins[#sorted_plugins+1] = {
      name = plugin,
      handler = handler(),
      schema = schema
    }
  end

  -- sort plugins by order of execution
  table.sort(sorted_plugins, function(a, b)
    local priority_a = a.handler.PRIORITY or 0
    local priority_b = b.handler.PRIORITY or 0
    return priority_a > priority_b
  end)

  -- add reports plugin if not disabled
  if kong_conf.anonymous_reports then
    local reports = require "kong.core.reports"
    reports.toggle(true)
    sorted_plugins[#sorted_plugins+1] = {
      name = "reports",
      handler = reports
    }
  end

  return sorted_plugins
end

-- Kong public context handlers.
-- @section kong_handlers

local Kong = {}

function Kong.init()
  local pl_path = require "pl.path"
  local conf_loader = require "kong.conf_loader"

  -- retrieve kong_config
  local conf_path = pl_path.join(ngx.config.prefix(), ".kong_env")
  local config = assert(conf_loader(conf_path))

  local dao = assert(DAOFactory.new(config)) -- instantiate long-lived DAO
  assert(dao:init())
  assert(dao:run_migrations()) -- migrating in case embedded in custom nginx

  -- populate singletons
  singletons.ip = ip.init(config)
  singletons.dns = dns(config)
  singletons.loaded_plugins = assert(load_plugins(config, dao))
  singletons.dao = dao
  singletons.configuration = config

  assert(core.build_router(dao, "init"))
end

function Kong.init_worker()
  -- special math.randomseed from kong.core.globalpatches
  -- not taking any argument. Must be called only once
  -- and in the init_worker phase, to avoid duplicated
  -- seeds.
  math.randomseed()


  -- init DAO


  local ok, err = singletons.dao:init_worker()
  if not ok then
    ngx.log(ngx.CRIT, "could not init DB: ", err)
    return
  end


  -- init inter-worker events


  local worker_events = require "resty.worker.events"


  local ok, err = worker_events.configure {
    shm = "process_events", -- defined by "lua_shared_dict"
    timeout = 5,            -- life time of event data in shm
    interval = 1,           -- poll interval (seconds)

    wait_interval = 0.010,  -- wait before retry fetching event data
    wait_max = 0.5,         -- max wait time before discarding event
  }
  if not ok then
    ngx.log(ngx.CRIT, "could not start inter-worker events: ", err)
    return
  end


  -- init cluster_events


  local cluster_events, err = kong_cluster_events.new {
    dao                     = singletons.dao,
    poll_interval           = 5,
    poll_offset             = 0,
  }
  if not cluster_events then
    ngx.log(ngx.CRIT, "could not create cluster_events: ", err)
    return
  end


  -- init cache


  local cache, err = kong_cache.new {
    cluster_events    = cluster_events,
    worker_events     = worker_events,
    propagation_delay = 0,
    ttl               = 3600,
    neg_ttl           = 300,
    resty_lock_opts   = {
      exptime = 10,
      timeout = 5,
    },
  }
  if not cache then
    ngx.log(ngx.CRIT, "could not create kong cache: ", err)
    return
  end

  local ok, err = cache:get("router:version", { ttl = 0 }, function()
    return "init"
  end)
  if not ok then
    ngx.log(ngx.CRIT, "could not set router version in cache: ", err)
    return
  end


  singletons.cache          = cache
  singletons.worker_events  = worker_events
  singletons.cluster_events = cluster_events


  singletons.dao:set_events_handler(worker_events)


  core.init_worker.before()


  -- run plugins init_worker context


  for _, plugin in ipairs(singletons.loaded_plugins) do
    plugin.handler:init_worker()
  end
end

function Kong.ssl_certificate()
  core.certificate.before()

  for plugin, plugin_conf in plugins_iterator(singletons.loaded_plugins, true) do
    plugin.handler:certificate(plugin_conf)
  end
end

function Kong.balancer()
  local addr = ngx.ctx.balancer_address
  local tries = addr.tries

  addr.try_count = addr.try_count + 1
  if addr.try_count > 1 then
    -- only call balancer on retry, first one is done in `core.access.before` which runs
    -- in the ACCESS context and hence has less limitations than this BALANCER context
    -- where the retries are executed

    -- record failure data
    local try = tries[addr.try_count - 1]
    try.state, try.code = get_last_failure()

    local ok, err = balancer_execute(addr)
    if not ok then
      ngx.log(ngx.ERR, "failed to retry the dns/balancer resolver for ",
              addr.upstream.host, "' with: ", tostring(err))

      return responses.send(500)
    end

  else
    -- first try, so set the max number of retries
    local retries = addr.retries
    if retries > 0 then
      set_more_tries(retries)
    end
  end

  tries[addr.try_count] = {
    ip    = addr.ip,
    port  = addr.port,
  }

  -- set the targets as resolved
  local ok, err = set_current_peer(addr.ip, addr.port)
  if not ok then
    ngx.log(ngx.ERR, "failed to set the current peer (address: ",
            tostring(addr.ip), " port: ", tostring(addr.port),"): ",
            tostring(err))

    return responses.send(500)
  end

  ok, err = set_timeouts(addr.connect_timeout / 1000,
                         addr.send_timeout / 1000,
                         addr.read_timeout / 1000)
  if not ok then
    ngx.log(ngx.ERR, "could not set upstream timeouts: ", err)
  end
end

function Kong.rewrite()
  core.rewrite.before()

  -- we're just using the iterator, as in this rewrite phase no consumer nor
  -- api will have been identified, hence we'll just be executing the global
  -- plugins
  for plugin, plugin_conf in plugins_iterator(singletons.loaded_plugins, true) do
    plugin.handler:rewrite(plugin_conf)
  end

  core.rewrite.after()
end

function Kong.access()
  core.access.before()

  for plugin, plugin_conf in plugins_iterator(singletons.loaded_plugins, true) do
    plugin.handler:access(plugin_conf)
  end

  core.access.after()
end

function Kong.header_filter()
  core.header_filter.before()

  for plugin, plugin_conf in plugins_iterator(singletons.loaded_plugins) do
    plugin.handler:header_filter(plugin_conf)
  end

  core.header_filter.after()
end

function Kong.body_filter()
  for plugin, plugin_conf in plugins_iterator(singletons.loaded_plugins) do
    plugin.handler:body_filter(plugin_conf)
  end

  core.body_filter.after()
end

function Kong.log()
  for plugin, plugin_conf in plugins_iterator(singletons.loaded_plugins) do
    plugin.handler:log(plugin_conf)
  end

  core.log.after()
end

return Kong
