local _M = {}
local _MT = { __index = _M, }


local semaphore = require("ngx.semaphore")
local jsonrpc = require("kong.clustering.rpc.json_rpc_v2")


local STATE_NEW = 1
local STATE_IN_PROGRESS = 2
local STATE_SUCCEED = 3
local STATE_ERRORED = 4


function _M.new(node_id, socket, method, params, is_notification)
  local self = {
    method = method,
    params = params,
    socket = socket,
    node_id = node_id,
    is_notification = is_notification,
  }

  if not is_notification then
    self.id = nil
    self.result = nil
    self.error = nil
    self.state = STATE_NEW -- STATE_*
    self.sema = semaphore.new()
  end

  return setmetatable(self, _MT)
end


-- start executing the future
function _M:start()
  -- notification has no callback
  if self.is_notification then
    return self.socket:call(self.node_id,
                            self.method,
                            self.params)
  end

  assert(self.state == STATE_NEW)
  self.state = STATE_IN_PROGRESS

  local callback = function(resp)
    assert(resp.jsonrpc == jsonrpc.VERSION)

    if resp.result then
      -- succeeded
      self.result = resp.result
      self.state = STATE_SUCCEED

    else
      -- errored
      self.error = resp.error
      self.state = STATE_ERRORED
    end

    self.sema:post()

    return true
  end

  return self.socket:call(self.node_id,
                          self.method,
                          self.params, callback)
end


function _M:wait(timeout)
  if self.is_notification then
    return nil, "the notification cannot be waited"
  end

  assert(self.state == STATE_IN_PROGRESS)

  local res, err = self.sema:wait(timeout)
  if not res then
    return res, err
  end

  return self.state == STATE_SUCCEED
end


return _M
