local semaphore = require "ngx.semaphore"
local semaphore_new = semaphore.new

local ngx_log = ngx.log
local ERR = ngx.ERR
local ngx_now = ngx.now
local new_timer = ngx.timer.at
local setmetatable = setmetatable

local _M = {}
local _MT = { __index = _M, }

-- this future is no longer tracked
-- don't call this if you don't know what this means
function _M:finish()
  self.response_t[self.seq] = nil
end

local function dropWait(future)
  local ok, err = future:wait()
  if not ok then
    ngx_log(ERR, "request fail to recieve response: ", err)
  end
end

-- intentionally drop the future
-- it will wait for the response and log error if it occurs
function _M:drop()
  return new_timer(0, dropWait, self)
end

-- call to indicate the request is done.
--- @param any data the response
function _M:done(data)
  self.data = data
  self.smph:post()
  self:finish()
end

-- call to indicate the request is in error.
--- @param string etype error type enumerator
--- @param string errdesc the error description
function _M:error(etype, errdesc)
  self.data = nil
  self.etype = etype
  self.errdesc = errdesc
  self.smph:post()
  self:finish()
end

-- call to indicate the request expires.
function _M:expire()
  self:error("timeout", "timeout")
end

-- wait until the request is done or in error
--- @return any data, string err
function _M:wait()
  local ok, err = self.smph:wait(self.delay)
  if not ok then
    return nil, err
  end

  return self.data, self.errdesc
end

--- @param delay number time until deadline
--- @param wrpc_peer table wRPC peer that creates the call
function _M.new(wrpc_peer, delay)
  local new_future = setmetatable({
    seq = wrpc_peer.seq,
    smph = semaphore_new(),
    delay = delay,
    deadline = ngx_now() + delay,
    response_t = wrpc_peer.responses,
  }, _MT)

  wrpc_peer.responses[wrpc_peer.seq] = new_future

  return new_future
end

return _M
