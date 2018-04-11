local ngx = ngx
local tonumber = tonumber


local function new(sdk, _SDK_REQUEST, major_version)
  function _SDK_REQUEST.get_ip()
    return ngx.var.realip_remote_addr or ngx.var.remote_addr
  end


  function _SDK_REQUEST.get_forwarded_ip()
    return ngx.var.remote_addr
  end


  function _SDK_REQUEST.get_port()
    return tonumber(ngx.var.realip_remote_port or ngx.var.remote_port)
  end


  function _SDK_REQUEST.get_forwarded_port()
    return tonumber(ngx.var.remote_port)
  end
end


return {
  namespace = "client",
  new = new,
}
