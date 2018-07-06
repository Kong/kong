--- Client information module
-- A set of functions to retrieve information about the client connecting to
-- Kong in the context of a given request.
--
-- See also:
-- [nginx.org/en/docs/http/ngx_http_realip_module.html](http://nginx.org/en/docs/http/ngx_http_realip_module.html)
-- @module kong.client


local phase_checker = require "kong.pdk.private.phases"


local ngx = ngx
local tonumber = tonumber
local check_not_phase = phase_checker.check_not


local PHASES = phase_checker.phases


local function new(self)
  local _CLIENT = {}


  ---
  -- Returns the remote address of the client making the request. This will
  -- **always** return the address of the client directly connecting to Kong.
  -- That is, in cases when a load balancer is in front of Kong, this function
  -- will return the load balancer's address, and **not** that of the
  -- downstream client.
  --
  -- @function kong.client.get_ip
  -- @phases certificate, rewrite, access, header_filter, body_filter, log
  -- @treturn string ip The remote address of the client making the request
  -- @usage
  -- -- Given a client with IP 127.0.0.1 making connection through
  -- -- a load balancer with IP 10.0.0.1 to Kong answering the request for
  -- -- https://example.com:1234/v1/movies
  -- kong.client.get_ip() -- "10.0.0.1"
  function _CLIENT.get_ip()
    check_not_phase(PHASES.init_worker)

    return ngx.var.realip_remote_addr or ngx.var.remote_addr
  end


  ---
  -- Returns the remote address of the client making the request. Unlike
  -- `kong.client.get_ip`, this function will consider forwarded addresses in
  -- cases when a load balancer is in front of Kong. Whether this function
  -- returns a forwarded address or not depends on several Kong configuration
  -- parameters:
  --
  -- * [trusted\_ips](https://getkong.org/docs/latest/configuration/#trusted_ips)
  -- * [real\_ip\_header](https://getkong.org/docs/latest/configuration/#real_ip_header)
  -- * [real\_ip\_recursive](https://getkong.org/docs/latest/configuration/#real_ip_recursive)
  --
  -- @function kong.client.get_forwarded_ip
  -- @phases certificate, rewrite, access, header_filter, body_filter, log
  -- @treturn string ip The remote address of the client making the request,
  -- considering forwarded addresses
  --
  -- @usage
  -- -- Given a client with IP 127.0.0.1 making connection through
  -- -- a load balancer with IP 10.0.0.1 to Kong answering the request for
  -- -- https://username:password@example.com:1234/v1/movies
  --
  -- kong.request.get_forwarded_ip() -- "127.0.0.1"
  --
  -- -- Note: assuming that 10.0.0.1 is one of the trusted IPs, and that
  -- -- the load balancer adds the right headers matching with the configuration
  -- -- of `real_ip_header`, e.g. `proxy_protocol`.
  function _CLIENT.get_forwarded_ip()
    check_not_phase(PHASES.init_worker)

    return ngx.var.remote_addr
  end


  ---
  -- Returns the remote port of the client making the request. This will
  -- **always** return the port of the client directly connecting to Kong. That
  -- is, in cases when a load balancer is in front of Kong, this function will
  -- return load balancer's port, and **not** that of the downstream client.
  -- @function kong.client.get_port
  -- @phases certificate, rewrite, access, header_filter, body_filter, log
  -- @treturn number The remote client port
  -- @usage
  -- -- [client]:40000 <-> 80:[balancer]:30000 <-> 80:[kong]:20000 <-> 80:[service]
  -- kong.client.get_port() -- 30000
  function _CLIENT.get_port()
    check_not_phase(PHASES.init_worker)

    return tonumber(ngx.var.realip_remote_port or ngx.var.remote_port)
  end


  ---
  -- Returns the remote port of the client making the request. Unlike
  -- `kong.client.get_port`, this function will consider forwarded ports in cases
  -- when a load balancer is in front of Kong. Whether this function returns a
  -- forwarded port or not depends on several Kong configuration parameters:
  --
  -- * [trusted\_ips](https://getkong.org/docs/latest/configuration/#trusted_ips)
  -- * [real\_ip\_header](https://getkong.org/docs/latest/configuration/#real_ip_header)
  -- * [real\_ip\_recursive](https://getkong.org/docs/latest/configuration/#real_ip_recursive)
  -- @function kong.client.get_forwarded_port
  -- @phases certificate, rewrite, access, header_filter, body_filter, log
  -- @treturn number The remote client port, considering forwarded ports
  -- @usage
  -- -- [client]:40000 <-> 80:[balancer]:30000 <-> 80:[kong]:20000 <-> 80:[service]
  -- kong.client.get_forwarded_port() -- 40000
  --
  -- -- Note: assuming that [balancer] is one of the trusted IPs, and that
  -- -- the load balancer adds the right headers matching with the configuration
  -- -- of `real_ip_header`, e.g. `proxy_protocol`.
  function _CLIENT.get_forwarded_port()
    check_not_phase(PHASES.init_worker)

    return tonumber(ngx.var.remote_port)
  end


  return _CLIENT
end


return {
  new = new,
}
