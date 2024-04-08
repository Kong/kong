local _M = {}
local _MT = { __index = _M, }


local semaphore = require("ngx.semaphore")


function _M.new(node_id, socket, method, params)
  local self = {
    method = method,
    params = params,
    sema = semaphore.new(),
    socket = socket,
    node_id = node_id,
    id = nil,
    result = nil,
    ["error"] = nil,
    state = "new", -- new, in_progress, succeed, errored
  }

  return setmetatable(self, _MT)
end


-- start executing the future
function _M:start()
  assert(self.state == "new")
  self.state = "in_progress"

  local callback = function(resp)
    assert(resp.jsonrpc == "2.0")

    if resp.result then
      -- succeeded
      self.result = resp.result
      self.state = "succeed"

    else
      -- errored
      self.error = resp.error
      self.state = "errored"
    end

    self.sema:post()

    return true
  end

  return self.socket:call(self.node_id,
                          self.method,
                          self.params, callback)
end


function _M:wait(timeout)
  assert(self.state == "in_progress")

  local res, err = self.sema:wait(timeout)
  if not res then
    return res, err
  end

  return self.state == "succeed"
end


return _M
