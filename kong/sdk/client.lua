local phase_checker = require "kong.sdk.private.phases"


local ngx = ngx
local tonumber = tonumber
local check_not_phase = phase_checker.check_not


local PHASES = phase_checker.phases


local function new(self)
  local _CLIENT = {}


  function _CLIENT.get_ip()
    check_not_phase(PHASES.init_worker)

    return ngx.var.realip_remote_addr or ngx.var.remote_addr
  end


  function _CLIENT.get_forwarded_ip()
    check_not_phase(PHASES.init_worker)

    return ngx.var.remote_addr
  end


  function _CLIENT.get_port()
    check_not_phase(PHASES.init_worker)

    return tonumber(ngx.var.realip_remote_port or ngx.var.remote_port)
  end


  function _CLIENT.get_forwarded_port()
    check_not_phase(PHASES.init_worker)

    return tonumber(ngx.var.remote_port)
  end


  return _CLIENT
end


return {
  new = new,
}
