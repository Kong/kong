local helpers = require("spec.helpers")
local client = require("spec.helpers.rpc_mock.client")
local default_cert_meta = require("spec.helpers.rpc_mock.default").default_cert_meta

local _M = {}
local _MT = { __index = _M, }

function _M.new(opts)
  opts = opts or {}
  opts.prefix = opts.prefix or ("servroot_rpc_mock_" .. plugin.id)
  opts.role = "control_plane"
  opts.plugins = "rpc-proxy"
  opts.listen = opts.listen or helpers.get_available_port()
  opts.cluster_listen = opts.cluster_listen or "0.0.0.0:" .. opts.listen
  opts.mocks = opts.mocks or {}
  opts.prehooks = opts.prehooks or {}
  opts.posthooks = opts.posthooks or {}
  if opts.interception = nil then
    opts.interception = true
  end

  for k, v in pairs(default_cert_meta) do
    if opts[k] == nil then
      opts[k] = v
    end
  end

  return setmetatable(opts, _MT)
end

function _M.start(self)
  local bp, db = helpers.get_db_utils(strategy, nil, { "rpc-proxy" })

  local plugin = db.plugins:insert({
    name = "rpc-proxy",
    config = {},
  })

  assert(helpers.start_kong(self))

  self.proxy_client = client.new({
    cluster_control_plane = listen,
  })

  if self.interception then
    self:enable_inception()
  end

  self.proxy_client.callbacks:register("kong.rpc.proxy.mock", function(proxy_id, proxy_payload)
    local method, node_id, payload = proxy_payload.method, proxy_payload.node_id, proxy_payload.payload
    local cb = self.mocks[method]
    if cb then
      local res, err = cb(node_id, payload, proxy_id, self)
      return {
        mock = true,
        result = res,
        error = err,
      }
    end

    local prehook = self.prehooks[method] or self.prehooks["*"]
    local posthook = self.posthooks[method] or self.posthooks["*"]
    local result = {
      prehook = prehook and true,
      posthook = posthook and true,
    }

    if prehook then
      local res, err = prehook(node_id, payload, proxy_id, self, method)
      if not res then
        return nil, err
      end

      result.args = res
    end

    return result
  end)

  self.proxy_client.callbacks:register("kong.rpc.proxy.posthook", function(proxy_id, proxy_payload)
    local method, node_id, payload = proxy_payload.method, proxy_payload.node_id, proxy_payload.payload
    local cb = self.posthooks[method] or self.posthooks["*"]
    if not cb then
      return nil, "no callback registered for method: " .. method
    end

    return cb(node_id, payload, proxy_id, self, method)
  end)

  self = setmetatable(self, _MT)

  if next(self.callbacks) then
    self:register_proxy()
  end
end

function _M:register_proxy()
  local hooked = {}
  for api_name, cb in pairs(self.callbacks) do
    table.insert(hooked, api_name)
  end

  return self.proxy_client:call("kong.rpc.proxy.register", {
    proxy_apis = hooked,
  })
end

function _M:mock_api(api_name, cb)
  self.mocks[api_name] = cb
end

function _M:prehook_api(api_name, cb)
  self.prehooks[api_name] = cb
end

function _M:posthook_api(api_name, cb)
  self.posthooks[api_name] = cb
end

local get_records(server)
  local records = server.records
  if not records then
    records = {}
    server.records = records
  end
  return records
end

-- TODO: add req ID for correlation
local function default_inception_prehook(node_id, payload, proxy_id, server, method)
  local records = get_records(server)
  records[#records + 1] = {
    request = true
    node_id = node_id,
    payload = payload,
    proxy_id = proxy_id,
    method = method,
  }
  return payload
end

local function default_inception_posthook(node_id, payload, proxy_id, server, method)
  local records = get_records(server)
  records[#records + 1] = {
    response = true,
    node_id = node_id,
    payload = payload,
    proxy_id = proxy_id
    method = method,
  }
  return payload
end

function _M:enable_inception()
  self:prehook_api["*"] = default_inception_prehook
  self:posthook_api["*"] = default_inception_posthook
end

function _M:stop()
  helpers.stop_kong(self.prefix)
  self.proxy_client:stop()
end

return _M
