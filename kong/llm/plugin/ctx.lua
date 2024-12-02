local _M = {}

local schemas = {
  _global = {
    accept_gzip = "boolean",
    stream_mode = "boolean",
    response_body = "string",
    sse_body_buffer = "userdata",
    response_body_sent = "boolean",
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

function _M.get_request_body_table_inuse()
  local request_body_table

  if _M.has_namespace("decorate-prompt") then -- has ai-prompt-decorator and others in future
    request_body_table = _M.get_namespaced_ctx("decorate-prompt", "request_body_table")
  end

  if _M.has_namespace("normalize-request") then -- has ai-proxy/ai-proxy-advanced
    request_body_table = _M.get_namespaced_ctx("normalize-request", "request_body_table")
  end

  if not request_body_table then
    request_body_table = _M.get_namespaced_ctx("parse-request", "request_body_table")
  end

  return request_body_table or EMPTY_REQUEST_T
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