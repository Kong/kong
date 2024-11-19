local _M = {
  NAME = "enable-buffering",
  STAGE = "REQ_INTROSPECTION",
  DESCRIPTION = "set the response to buffering mode",
}

function _M:run(_)
  if ngx.get_phase() == "access" then
    kong.service.request.enable_buffering()
  end

  return true
end

return _M