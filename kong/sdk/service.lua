local ngx = ngx


local function new()
  local service = {}


  ------------------------------------------------------------------------------
  -- Sets the internal balancer object (managed by the Upstream entity)
  -- to be used by the service to which Kong will proxy the request.
  -- The `Host` header is not set: use
  -- `kong.service.request.set_header` to set the header.
  --
  -- @param host Host name to set. Example: "example.com"
  -- @return Nothing; throws an error on invalid inputs.
  function service.set_balancer(host)
    if type(host) ~= "string" then
      error("host must be a string", 2)
    end

    ngx.var.upstream_host = host
    ngx.ctx.balancer_address.host = host
  end


  ------------------------------------------------------------------------------
  -- Sets the target host and port for the service to which Kong will
  -- proxy the request. The `Host` header is not set: use
  -- `kong.service.request.set_header` to set the header.
  --
  -- @param host Host name to set. Example: "example.com"
  -- @param port A port number between 0 and 65535.
  -- @return Nothing; throws an error on invalid inputs.
  function service.set_target(host, port)
    if type(host) ~= "string" then
      error("host must be a string", 2)
    end
    if type(port) ~= "number" or math.floor(port) ~= port then
      error("port must be an integer", 2)
    end
    if port < 0 or port > 65535 then
      error("port must be an integer between 0 and 65535: given " .. port, 2)
    end

    ngx.var.upstream_host = host
    ngx.ctx.balancer_address.host = host
    ngx.ctx.balancer_address.port = port
  end


  ------------------------------------------------------------------------------
  -- Determine if the request was proxied by to a service
  -- or if the response was produced by Kong itself.
  --
  -- @return true if the request was proxied by Kong;
  function service.was_proxied()
    return ngx.ctx.KONG_PROXIED == true
  end


  return service
end


return {
  new = new,
}
