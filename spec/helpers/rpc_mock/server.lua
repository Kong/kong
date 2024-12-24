local helpers = require("spec.helpers")
local client = require("spec.helpers.rpc_mock.client")
local default_cert = require("spec.helpers.rpc_mock.default").default_cert


local _M = {}
local _MT = { __index = _M, }


-- this function will start a control plane server with the given configuration
-- and attach a debugger to it
-- set attaching to true to attach to an existing control plane
function _M.new(opts)
  opts = opts or {}
  opts.prefix = opts.prefix or "servroot_rpc_tap"
  opts.role = "control_plane"
  opts.plugins = "bundled,rpc-debug"
  opts.cluster_listen = opts.cluster_listen or "127.0.0.1:8005"
  opts.mocks = opts.mocks or {}
  opts.prehooks = opts.prehooks or {}
  opts.posthooks = opts.posthooks or {}
  opts.cluster_rpc = "on"
  opts.cluster_rpc_sync = opts.cluster_rpc_sync or "on"
  if opts.interception == nil then
    opts.interception = true
  end

  for k, v in pairs(default_cert) do
    if opts[k] == nil then
      opts[k] = v
    end
  end

  return setmetatable(opts, _MT)
end

function _M.start(self)
  if not self.attaching then
    local _, db = helpers.get_db_utils(self.database, nil, { "rpc-debug" })

    assert(db.plugins:insert({
      name = "rpc-debug",
      config = {},
    }))

    assert(helpers.start_kong(self))
  end

  self.debugger_client = client.new({
    cluster_control_plane = self.cluster_listen,
  })

  -- install default interception handlers
  if self.interception then
    self:enable_inception()
  end

  -- attached control plane will call this method when a hooked/mocked RPC is called.
  -- this RPC handles both prehook and mock, and response to the control plane:
  -- 1. if the RPC is mocked, return the mock result;
  -- 2. if the RPC has a prehook, manipulate the args and returns them, and tell if a posthook is present and pending call
  self.debugger_client.callbacks:register("kong.rpc.debug.mock", function(proxy_id, proxy_payload)
    local method, node_id, payload, call_id =
      proxy_payload.method, proxy_payload.node_id, proxy_payload.payload, proxy_payload.call_id
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
      local res, err = prehook(node_id, payload, proxy_id, self, method, call_id)
      if not res then
        return nil, err
      end

      result.args = res
    end

    return result
  end)

  self.debugger_client.callbacks:register("kong.rpc.debug.posthook", function(proxy_id, proxy_payload)
    local method, node_id, payload, call_id =
      proxy_payload.method, proxy_payload.node_id, proxy_payload.payload, proxy_payload.call_id
    local cb = self.posthooks[method] or self.posthooks["*"]
    if not cb then
      return nil, "no callback registered for method: " .. method
    end

    return cb(node_id, payload, proxy_id, self, method, call_id)
  end)

  self.debugger_client:start()
  self.debugger_client:wait_until_connected()

  if next(self.mocks) or next(self.prehooks) or next(self.posthooks) then
    return self:attach_debugger()
  end

  return true
end

function _M:attach_debugger()
  local hooked = {}
  for api_name, cb in pairs(self.mocks) do
    hooked[api_name] = true
  end
  for api_name, cb in pairs(self.prehooks) do
    hooked[api_name] = true
  end
  for api_name, cb in pairs(self.posthooks) do
    hooked[api_name] = true
  end

  local hooked_list
  if hooked["*"] then
    hooked_list = {
      "kong.sync.v2.get_delta",
    }
  else
    hooked_list = {}
    for api_name, _ in pairs(hooked) do
      hooked_list[#hooked_list + 1] = api_name
    end
  end

  return self.debugger_client:call("control_plane", "kong.rpc.debug.register", {
    proxy_apis = hooked_list,
  })
end

function _M:call(node_id, method, payload)
  return self.debugger_client:call("control_plane", "kong.rpc.debug.call", {
    method = method,
    args = payload,
    node_id = node_id,
  })
end

function _M:get_node_ids()
  return self.debugger_client:call("control_plane", "kong.rpc.debug.lua_code", [[
    local node_ids = {}
    for node_id, _ in pairs(kong.rpc.clients) do
      if type(node_id) == "string" then
        node_ids[node_id] = true
      end
    end
    return node_ids
  ]])
end

function _M:wait_for_node(node_id)
  return helpers.wait_until(function()
    local list, err = self:get_node_ids()
    if not list then
      return nil, err
    end

    return list[node_id]
  end)
end

function _M:mock(api_name, cb)
  self.mocks[api_name] = cb
end


function _M:prehook(api_name, cb)
  self.prehooks[api_name] = cb
end


function _M:posthook(api_name, cb)
  self.posthooks[api_name] = cb
end


local function get_records(server)
  local records = server.records
  if not records then
    records = {}
    server.records = records
  end
  return records
end


local function record_has_response(record)
  return record.response and true
end


function _M:wait_for_call(cond)
  cond = cond or record_has_response

  local result

  helpers.wait_until(function()
    local records = get_records(self)
    for _, record in pairs(records) do
      if cond(record) then
        result = record
        return record
      end
    end
  end)

  return result
end


local function default_inception_prehook(node_id, payload, proxy_id, server, method, call_id)
  local records = get_records(server)
  records[call_id] = {
    request = payload,
    node_id = node_id,
    proxy_id = proxy_id,
    method = method,
  }
  return payload
end


local function default_inception_posthook(node_id, payload, proxy_id, server, method, call_id)
  local records = get_records(server)
  local record = records[call_id]
  if not record then
    print("no record found for call_id: ", call_id)
    return payload
  end
  record.response = payload
  return payload
end


function _M:enable_inception()
  self.prehooks["*"] = default_inception_prehook
  self.posthooks["*"] = default_inception_posthook
end


function _M:stop(...)
  if not self.attaching then
    helpers.stop_kong(self.prefix, ...)
  end

  self.debugger_client:stop()
end


return _M
