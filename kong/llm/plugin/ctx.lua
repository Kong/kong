local _M = {}

local schemas = {
  _global = {
    accept_gzip = "boolean",
    stream_mode = "boolean",
    request_body_table = "table",
    response_body = "string",
    sse_body_buffer = "userdata",
    response_body_sent = "boolean",
    llm_format_adapter = "table",
    preserve_mode = "boolean",
  },
}

function _M.set_namespaced_ctx(namespace, key, value)
  local typ = schemas[namespace] and schemas[namespace][key]
  if not typ then
    error("key not registered in namespace: " .. namespace .. " key: " .. key, 2)
  end

  if type(value) ~= typ then
    error("value type mismatch in namespace: " .. namespace .. " key: " .. key ..
          ", expecting " .. typ .. ", got " .. type(value), 2)
  end

  local ctx = ngx.ctx.ai_namespaced_ctx
  if not ctx then
    ctx = {}
    ngx.ctx.ai_namespaced_ctx = ctx
  end

  local ns = ctx[namespace]
  if not ns then
    ns = {}
    ctx[namespace] = ns
  end

  ns[key] = value

  return true
end

function _M.get_namespaced_ctx(namespace, key)
  if not schemas[namespace] or not schemas[namespace][key] then
    error("key not registered in namespace: " .. namespace .. " key: " .. key, 2)
  end

  local ctx = ngx.ctx.ai_namespaced_ctx
  if not ctx then
    return nil
  end

  local ns = ctx[namespace]
  if not ns then
    return nil
  end

  return ns[key]
end

function _M.clear_namespaced_ctx(namespace)
  local ctx = ngx.ctx.ai_namespaced_ctx
  if not ctx then
    return
  end

  ctx[namespace] = nil

  return true
end

function _M.get_namespaced_accesors(namespace, schema)
  if schemas[namespace] then
    error("namespace already registered: " .. namespace, 2)
  end

  schemas[namespace] = schema
  return function(key) -- get
    return _M.get_namespaced_ctx(namespace, key)
  end, function(key, value) -- set
    return _M.set_namespaced_ctx(namespace, key, value)
  end
end

function _M.get_global_accessors(source)
  assert(source, "source is missing")

  local global_ns = "_global"
  return function(key) -- get
    local source_map = ngx.ctx.ai_namespaced_ctx_global_source
    if not source_map then
      source_map = {}
      ngx.ctx.ai_namespaced_ctx_global_source = source_map
    end

    local ret = _M.get_namespaced_ctx(global_ns, key)
    if not ret then
      return nil, nil
    end

    return ret, source_map[key]
  end, function(key, value) -- set
    local source_map = ngx.ctx.ai_namespaced_ctx_global_source
    if not source_map then
      source_map = {}
      ngx.ctx.ai_namespaced_ctx_global_source = source_map
    end

    _M.set_namespaced_ctx(global_ns, key, value)
    source_map[key] = source

    return true
  end
end

function _M.has_namespace(namespace)
  return schemas[namespace] ~= nil
end

-- convienient functions

function _M.immutable_table(t)
  return setmetatable({}, {
    __index = t,
    __newindex = function(_, _, v)
      if not v then
        return
      end

      error("Attempt to modify or add keys to an immutable table", 2)
    end,

    -- Allow pairs iteration
    __pairs = function(_)
        return next, t, nil
    end,
  })
end

local EMPTY_REQUEST_T = _M.immutable_table({})

function _M.set_request_body_table_inuse(t, source)
  assert(source, "source is missing")

  -- merge overlay keys into the key itself
  local mt = getmetatable(t)
  setmetatable(t, nil)
  if mt and mt.__index then
    for k, v in pairs(mt.__index) do
      if not t[k] then
        t[k] = v
      end
    end
  end

  _M.set_namespaced_ctx("_global", "request_body_table", t)
  ngx.ctx.ai_request_body_table_source = source
end

function _M.get_request_body_table_inuse()
  local value = _M.get_namespaced_ctx("_global", "request_body_table")
  if not value then
    return EMPTY_REQUEST_T, "none"
  end

  return _M.immutable_table(value), ngx.ctx.ai_request_body_table_source
end

local EMPTY_MODEL_T = _M.immutable_table({
  name = "UNSPECIFIED",
  provider = "UNSPECIFIED",
})

function _M.get_request_model_table_inuse()
  local model
  if _M.has_namespace("normalize-request") then -- has ai-proxy/ai-proxy-advanced
    model = _M.get_namespaced_ctx("normalize-request", "model")
  end

  if not model then
    model = _M.get_namespaced_ctx("parse-request", "request_model")
  end

  return model or EMPTY_MODEL_T
end

return _M