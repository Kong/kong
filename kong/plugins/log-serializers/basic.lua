local _M = {}


local kong = kong


local WARNING_SHOWN = false

-- stream log serializer is new, so no one should be depending on this proxy...
if ngx.config.subsystem == "http" then
  function _M.serialize(ongx, okong)
    if not WARNING_SHOWN then
      kong.log.warn("basic log serializer has been deprecated, please modify " ..
                    "your plugin to use the kong.log.serialize PDK function " ..
                    "instead")
      WARNING_SHOWN = true
    end

    return kong.log.serialize({ ngx = ongx, kong = okong, })
  end
end


return _M
