local _M = {}
local _MT = { __index = _M, }


local semaphore = require("ngx.semaphore")


function _M.new(socket, method, params)
  local self = {
    method = method,
    params = params,
    sema = semaphore.new(),
    socket = socket,
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

  self.id = self.socket:get_next_id()

  self.socket.interest[self.id] = function(resp)
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
  end

  local res, err = self.socket.outgoing:push({
    jsonrpc = "2.0",
    method = self.method,
    params = self.params,
    id = self.id,
  })
  if not res then
    return nil, err
  end

  return true
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
