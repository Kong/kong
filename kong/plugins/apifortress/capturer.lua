-- ©2016 API Fortress Inc.
-- Captures the response payloads as they go through the wire
local _M = {}

local function read_response_body()
  local chunk, eof = ngx.arg[1], ngx.arg[2]
  local buffered = ngx.ctx.buffered
  if not buffered then
    buffered = {}
    ngx.ctx.buffered = buffered
  end
  if chunk ~= "" then
    buffered[#buffered + 1] = chunk
  end
  if eof then
    local response_body = table.concat(buffered)
    return response_body
  end
  return nil
end

local function capture()
  local body = read_response_body()
  ngx.ctx.captured_body = body
end

function _M.execute(config)
  capture()
end

return _M
