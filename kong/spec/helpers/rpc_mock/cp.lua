--- This module provides a mock for Kong Control Plane RPC
-- @module spec.helpers.rpc_mock.cp

local helpers = require("spec.helpers")
local dp_mock = require("spec.helpers.rpc_mock.dp")
local default_cert = require("spec.helpers.rpc_mock.default").default_cert


local _M = {}
local _MT = { __index = _M, }


--- this function starts a mocked Kong CP with the given configuration
-- @tparam[opts={}] table opts the configuration options. Fields not mentioned here will be used as Kong configuration, and by default 
--                  the control plane will use the default_cert
-- @tparam[opts=false] boolean opts.attaching set to true to attach to an existing control plane (instead of starting one)
-- @tparam[opts=true] boolean opts.interception whether to enable the default interception handlers
-- @tparam[opts={}] table opts.mocks handlers for mocked RPCs
-- @tparam[opts={}] table opts.prehooks handlers for prehooks
-- @tparam[opts={}] table opts.posthooks handlers for posthooks
-- @usage local cp = cp_mock.new()
function _M.new(opts)
  opts = opts or {}
  opts.prefix = opts.prefix or "servroot_rpc_tap"
  opts.role = "control_plane"
  opts.plugins = opts.plugins or "bundled"
  opts.plugins = opts.plugins .. ",rpc-debug"
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


--- start the mocked control plane
-- throws an error if failed to start
function _M.start(self)
  if not self.attaching then
    assert(helpers.start_kong(self))
  end

  self.debugger_dp = dp_mock.new({
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
  self.debugger_dp.callbacks:register("kong.rpc.debug.call_handler", function(proxy_id, proxy_payload)
    local method, node_id, payload, call_seq =
      proxy_payload.method, proxy_payload.node_id, proxy_payload.payload, proxy_payload.call_seq
    local mock = self.mocks[method]
    if mock then
      local res, err = mock(node_id, payload, proxy_id, self)
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
      local res, err = prehook(node_id, payload, proxy_id, self, method, call_seq)
      if not res then
        return nil, err
      end

      result.args = res
    end

    return result
  end)

  self.debugger_dp.callbacks:register("kong.rpc.debug.call_handler_post", function(proxy_id, proxy_payload)
    local method, node_id, payload, call_seq =
      proxy_payload.method, proxy_payload.node_id, proxy_payload.payload, proxy_payload.call_seq
    local cb = self.posthooks[method] or self.posthooks["*"]
    if not cb then
      return nil, "no callback registered for method: " .. method
    end

    local res, err = cb(node_id, payload, proxy_id, self, method, call_seq)
    return {
      result = res,
      error = err,
    }
  end)

  self.debugger_dp:start()
  self.debugger_dp:wait_until_connected()

  return self:attach_debugger()
end


--- register mocked/hocked RPCs to the control plane
function _M:attach_debugger()
  return self.debugger_dp:call("control_plane", "kong.rpc.debug.register")
end


--- let CP make a call to a node
-- @tparam string node_id the node ID to call
-- @tparam string method the RPC method to call
-- @tparam any payload the payload to send
function _M:call(node_id, method, payload)
  local res, err = self.debugger_dp:call("control_plane", "kong.rpc.debug.call", {
    method = method,
    args = payload,
    node_id = node_id,
  })

  if err then
    return nil, "debugger error: " .. err
  end

  return res.result, res.error
end


--- get the node IDs connected to the control plane
-- @treturn table a table of node IDs
function _M:get_node_ids()
  return self.debugger_dp:call("control_plane", "kong.rpc.debug.lua_code", [[
    local node_ids = {}
    for node_id, _ in pairs(kong.rpc.clients) do
      if type(node_id) == "string" then
        node_ids[node_id] = true
      end
    end
    return node_ids
  ]])
end


--- wait until at least one node is connected to the control plane
-- throws when timeout
-- @tparam string node_id the node ID to wait for
-- @tparam[opt=15] number timeout the timeout in seconds
function _M:wait_for_node(node_id, timeout)
  return helpers.wait_until(function()
    local list, err = self:get_node_ids()
    if not list then
      return nil, err
    end

    return list[node_id]
  end, timeout)
end


--- register a mock for an RPC
-- @param api_name the RPC name
-- @param cb the callback to be called when the RPC is called
--          the callback should return the result and error
function _M:mock(api_name, cb)
  self.mocks[api_name] = cb
end


--- unregister a mock for an RPC
-- @param api_name the RPC name
function _M:unmock(api_name)
  self.mocks[api_name] = nil
end


--- register a prehook for an RPC
-- @tparam string api_name the RPC name
-- @tparam function cb the callback to be called before the RPC is called
--          the callback should return the manipulated payload
--          in form of { arg1, arg2, ... }
function _M:prehook(api_name, cb)
  self.prehooks[api_name] = cb
end


--- register a posthook for an RPC
-- @tparam string api_name the RPC name
-- @tparam function cb the callback to be called after the RPC is called
--          the callback should return the manipulated payload
--          in form of result, error (multiple return values)
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


--- wait until a call is made to the control plane. Only available if the control plane is started with interception enabled
-- @tparam[opt] function cond optional condition to wait for. Default is to wait until the call has a response
-- the record is in the form of { request = payload, response = payload, node_id = node_id, proxy_id = proxy_id, method = method }
-- and history can be accessed via `records` field of the object
-- @tparam[opt=15] number timeout the timeout in seconds
function _M:wait_for_a_call(cond, timeout)
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
  end, timeout)

  return result
end


local function default_inception_prehook(node_id, payload, proxy_id, server, method, call_seq)
  local records = get_records(server)
  records[call_seq] = {
    request = payload,
    node_id = node_id,
    proxy_id = proxy_id,
    method = method,
  }
  return payload
end


local function default_inception_posthook(node_id, payload, proxy_id, server, method, call_seq)
  local records = get_records(server)
  local record = records[call_seq]
  if not record then
    print("no record found for call_seq: ", call_seq)
    record = {
      node_id = node_id,
      proxy_id = proxy_id,
      method = method,
    }
    records[call_seq] = record
  end

  record.response = payload
  return payload.result, payload.error
end


--- enable the default interception handlers
function _M:enable_inception()
  self.prehooks["*"] = default_inception_prehook
  self.posthooks["*"] = default_inception_posthook
end


--- stop the mocked control plane
-- parameters are passed to `helpers.stop_kong`
function _M:stop(...)
  if not self.attaching then
    helpers.stop_kong(self.prefix, ...)
  end

  self.debugger_dp:stop()
end


return _M
