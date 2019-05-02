local ffi = require "ffi"
local uuid = require("kong.tools.utils").uuid
local strategies = require "kong.tracing.strategies"
local knode  = (kong and kong.node) and kong.node or
               require "kong.pdk.node".new()

local get_node_id = knode.get_id


local at = ngx.timer.at
local floor = math.floor
local time = ngx.time
local pack = table.pack
local remove = table.remove
local unpack = table.unpack
local insert = table.insert
local tonumber = tonumber
local http_time = ngx.http_time


local empty = setmetatable({}, {
  __index = function()
    return function() end
  end,
  __newindex = function()
    return
  end,
})


local __data_mt = {
  __tostring = strategies.file_tostring
}


-- forward decl
local trace, enabled, threshold, types, debug_header, trace_data
local tracing_write_strategy, tracing_write_endpoint


local __log_prefix = "[tracing] "


ffi.cdef[[
  typedef long time_t;

  typedef struct timeval {
    time_t tv_sec;
    time_t tv_usec;
  } timeval;

  int gettimeofday(struct timeval* t, void* tzp);
]]


local gettimeofday_struct = ffi.new("timeval")


local function gettimeofday()
  ffi.C.gettimeofday(gettimeofday_struct, nil)
  return tonumber(tonumber(gettimeofday_struct.tv_sec) +
         (tonumber(gettimeofday_struct.tv_usec) / 1000000))
end


local _M = {}


local function figure_types(types)
  for _, t in ipairs(types) do
    types[t] = true
  end

  return types
end


local function configured_type(name)
  return types["all"] or types[name]
end


local function request_id()
  local ctx = ngx.ctx
  if ctx.admin_api then
    return ctx.admin_api.req_id
  end

  local ok, res = pcall(function() return ngx.var.set_request_id end)
  if ok then
    return res
  end

  return uuid()
end


local function debug_header_present()
  if not debug_header then
    return false
  end

  return ngx.req.get_headers()[debug_header] ~= nil
end


local function overwrites()

  -- legacy DAO overwrites
  local strategies = {}
  for _, strategy in ipairs({"postgres", "cassandra"}) do

    strategies[strategy] = require("kong.dao.db." .. strategy)
    local kong_dao_db_strategy_query_orig = strategies[strategy].query

    strategies[strategy].query = function(self, query, ...)
      local t = trace("legacy_query", trace_data and {
        query     = query,
        traceback = debug.traceback(),
      })

      if trace_data then
        -- c* hack
        local p = {...}
        if p[3] and p[1] then
          t:add_data("args", setmetatable(p[1], __data_mt))
        end
      end

      local r = pack(kong_dao_db_strategy_query_orig(self, query, ...))

      t:finish()

      return unpack(r)
    end
  end


  -- yayyy more legacy hacks
  local c_cluster = require "resty.cassandra.cluster"
  local iterate_orig = c_cluster.iterate
  local function iterate(self, query, args, opts)
    local t = trace("cassandra_iterate", trace_data and {
      query     = query,
      traceback = debug.traceback(),
    })

    if trace_data and args then
      t:add_data("args", setmetatable(args, __data_mt))
    end

    local r = pack(iterate_orig(self, query, args, opts))

    t:finish()

    return unpack(r)
  end
  c_cluster.iterate = iterate


  -- kong.db connector overwrite
  local function connector_query_wrap(connector)
    local query_orig = connector.query

    local function query(self, sql, ...)

      local t = trace("query", trace_data and {
        query     = sql,
        traceback = debug.traceback(),
      })

      if trace_data then
        local args = select(1, ...)
        if args then
          t:add_data("args", setmetatable(args, __data_mt))
        end
      end

      local r = pack(query_orig(self, sql, ...))

      t:finish()

      return unpack(r)
    end

    connector.query = query
  end
  _M.connector_query_wrap = connector_query_wrap


  -- plugin handlers
  -- we only care about handlers that can yield the thread
  -- (e.g. rewrite, access, etc)
  local function plugin_wrap(h, plugin)
    for _, phase in ipairs({"certificate", "rewrite", "access"}) do

    local handler_orig = h[phase]

    local w = function(self, conf)
      local t = trace("plugin", trace_data and {
        plugin      = plugin,
        plugin_conf = setmetatable(conf, __data_mt)
      })

      local r = pack(handler_orig(self, conf))

      t:finish()

      return unpack(r)
    end

    h[phase] = w

    end
  end
  _M.plugin_wrap = plugin_wrap


  -- router wrapper
  local function wrap_router(router)
    local exec_orig = router.exec

    local function exec(ngx)
      local t = trace("router")

      local r = pack(exec_orig(ngx))

      t:finish()

      return unpack(r)
    end

    router.exec = exec
  end
  _M.wrap_router = wrap_router


  -- core handler wrappers
  local handlers = {}
  local access = require("kong.runloop.handler").access
  for _, phase in ipairs({"before", "after"}) do
    handlers[phase] = access[phase]

    local function handler(ctx)
      local t = trace("access." .. phase)

      local r = pack(handlers[phase](ctx))

      t:finish()

      return unpack(r)
    end

    access[phase] = handler
  end
end


local invalid_phases = {
  init        = true,
  init_worker = true,
  timer       = true,
}


local function valid_phase()
  return not invalid_phases[ngx.get_phase()]
end


local function get_write_strategy()
  return strategies.writers[tracing_write_strategy],
         tracing_write_endpoint
end


local function get_flush_strategy()
  return strategies.flushers[tracing_write_strategy],
         tracing_write_endpoint
end


local __trace_mt = {}
__trace_mt.__index = __trace_mt


function __trace_mt:add_data(k, v)
  if not valid_phase() or not trace_data then
    return
  end

  self.data[k] = v

  return true
end


function __trace_mt:finish()
  assert(self.finished == nil, "attempt to finish a finished trace")

  self.done = gettimeofday()

  self.duration = floor((self.done - self.start) * 1000000)

  local trace_parent = ngx.ctx.kong_trace_parent
  remove(trace_parent)
  ngx.ctx.kong_trace_parent = trace_parent

  if self.duration > threshold then
    self:buffer()
  end

  self.finished = true
end


function __trace_mt:buffer()
  local traces = ngx.ctx.kong_trace_traces

  if not traces then
    traces = { self }

  else
    insert(traces, self)
  end

  ngx.ctx.kong_trace_traces = traces
end


function __trace_mt:write()
  local strategy, endpoint = get_write_strategy()

  local ok, err = pcall(strategy, self, endpoint)
  if not ok then
    ngx.log(ngx.ERR, __log_prefix, "failed to write trace: ", err)
  end
end


local function should_trace(name)
  return enabled
         and valid_phase()
         and configured_type(name)
         and (not debug_header or debug_header_present())
end


function _M.trace(name, ctx)
  if not should_trace(name) then
    return empty
  end

  local trace_id = uuid()

  local parent
  local trace_parent = ngx.ctx.kong_trace_parent

  if trace_parent and #trace_parent > 0 then
    parent = trace_parent[#trace_parent]
    insert(trace_parent, trace_id)

  else
    trace_parent = { trace_id }
  end

  ngx.ctx.kong_trace_parent = trace_parent

  local trace = {
    node_id = get_node_id(),
    request = request_id(),
    date    = http_time(time()),
    start   = gettimeofday(),
    name    = name,
    parent  = parent,
    id      = trace_id,
  }

  if trace_data then
    trace.data = setmetatable(ctx or {}, __data_mt)
  end

  return setmetatable(trace, __trace_mt)
end
trace = _M.trace


function _M.init(config)
  assert(type(config) == "table")
  assert(type(config.tracing) == "boolean")
  assert(type(config.tracing_types) == "table")

  enabled = config.tracing

  if config.tracing then
    overwrites()
  end

  threshold = config.tracing_time_threshold

  types = figure_types(config.tracing_types)

  if config.tracing_write_strategy == "http" then
    strategies.add_http_strategy()
  end

  tracing_write_strategy = config.tracing_write_strategy
  tracing_write_endpoint = config.tracing_write_endpoint

  if config.tracing_debug_header then
    debug_header = config.tracing_debug_header
  end

  trace_data = config.generate_trace_details

  return true
end


function _M.flush()
  local traces = ngx.ctx.kong_trace_traces
  if not traces then
    return
  end

  at(0, function()
    local strategy, endpoint = get_flush_strategy()

    local ok, err = pcall(strategy, traces, endpoint)
    if not ok then
      ngx.log(ngx.ERR, __log_prefix, "failed to flush traces: ", err)
    end
  end)
end


return setmetatable(_M, { __index = function() return function() end end })
