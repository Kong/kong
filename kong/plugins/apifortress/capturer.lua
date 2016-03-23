-- Captures the response payloads as they go through the wire
local _M = {}

local function capture()
  local chunk, eof = ngx.arg[1], ngx.arg[2]
  local captured_body = ngx.ctx.captured_body
  if not captured_body then
    captured_body = {}
    ngx.ctx.captured_body = captured_body
  end
  if chunk ~= "" then
    captured_body[#captured_body + 1] = chunk
  end
  if eof then
    ngx.ctx.captured_body = table.concat(captured_body)
  end
end

function _M.execute(config)
  capture()
end

return _M
