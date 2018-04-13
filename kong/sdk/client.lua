local ngx = ngx
local tonumber = tonumber


local function new(sdk, major_version)
  local _CLIENT = {}


  function _CLIENT.get_ip()
    return ngx.var.realip_remote_addr or ngx.var.remote_addr
  end


  function _CLIENT.get_forwarded_ip()
    return ngx.var.remote_addr
  end


  function _CLIENT.get_port()
    return tonumber(ngx.var.realip_remote_port or ngx.var.remote_port)
  end


  function _CLIENT.get_forwarded_port()
    return tonumber(ngx.var.remote_port)
  end


  return _CLIENT
end


return {
  new = new,
}
