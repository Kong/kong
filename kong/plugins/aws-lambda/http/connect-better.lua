local ngx_re_gmatch = ngx.re.gmatch
local ngx_re_sub = ngx.re.sub
local ngx_re_find = ngx.re.find


local http = require "resty.http"

--[[
A better connection function that incorporates:
  - tcp connect
  - ssl handshake
  - http proxy
Due to this it will be better at setting up a socket pool where connections can
be kept alive.


Call it with a single options table as follows:

client:connect_better {
  scheme = "https"      -- scheme to use, or nil for unix domain socket
  host = "myhost.com",  -- target machine, or a unix domain socket
  port = nil,           -- port on target machine, will default to 80/443 based on scheme
  pool = nil,           -- connection pool name, leave blank! this function knows best!
  pool_size = nil,      -- options as per: https://github.com/openresty/lua-nginx-module#tcpsockconnect
  backlog = nil,

  ssl = {               -- ssl will be used when either scheme = https, or when ssl is truthy
    ctx = nil,          -- options as per: https://github.com/openresty/lua-nginx-module#tcpsocksslhandshake
    server_name = nil,
    ssl_verify = true,  -- defaults to true
  },

  proxy = {             -- proxy will be used only if "proxy.uri" is provided
    uri = "http://myproxy.internal:123", -- uri of the proxy
    authorization = nil, -- a "Proxy-Authorization" header value to be used
    no_proxy = nil,      -- comma separated string of domains bypassing proxy
  },
}
]]
function http.connect_better(self, options)
  local sock = self.sock
  if not sock then
    return nil, "not initialized"
  end

  local ok, err
  local proxy_scheme = options.scheme -- scheme to use; http or https
  local host = options.host -- remote host to connect to
  local port = options.port -- remote port to connect to
  local poolname = options.pool -- connection pool name to use
  local pool_size = options.pool_size
  local backlog = options.backlog
  if proxy_scheme and not port then
    port = (proxy_scheme == "https" and 443 or 80)
  elseif port and not proxy_scheme then
    return nil, "'scheme' is required when providing a port"
  end

  -- ssl settings
  local ssl, ssl_ctx, ssl_server_name, ssl_verify
  if proxy_scheme ~= "http" then
    -- either https or unix domain socket
    ssl = options.ssl
    if type(options.ssl) == "table" then
      ssl_ctx = ssl.ctx
      ssl_server_name = ssl.server_name
      ssl_verify = (ssl.verify == nil) or (not not ssl.verify) -- default to true, and force to bool
      ssl = true
    else
      if ssl then
        ssl = true
        ssl_verify = true       -- default to true
      else
        ssl = false
      end
    end
  else
    -- plain http
    ssl = false
  end

  -- proxy related settings
  local proxy, proxy_uri, proxy_uri_t, proxy_authorization, proxy_host, proxy_port
  proxy = options.proxy
  if proxy and proxy.no_proxy then
    -- Check if the no_proxy option matches this host. Implementation adapted
    -- from lua-http library (https://github.com/daurnimator/lua-http)
    if proxy.no_proxy == "*" then
      -- all hosts are excluded
      proxy = nil

    else
      local no_proxy_set = {}
      -- wget allows domains in no_proxy list to be prefixed by "."
      -- e.g. no_proxy=.mit.edu
      for host_suffix in ngx_re_gmatch(proxy.no_proxy, "\\.?([^,]+)") do
        no_proxy_set[host_suffix[1]] = true
      end

      -- From curl docs:
      -- matched as either a domain which contains the hostname, or the
      -- hostname itself. For example local.com would match local.com,
      -- local.com:80, and www.local.com, but not www.notlocal.com.
      --
      -- Therefore, we keep stripping subdomains from the host, compare
      -- them to the ones in the no_proxy list and continue until we find
      -- a match or until there's only the TLD left
      repeat
        if no_proxy_set[host] then
          proxy = nil
          break
        end

        -- Strip the next level from the domain and check if that one
        -- is on the list
        host = ngx_re_sub(host, "^[^.]+\\.", "")
      until not ngx_re_find(host, "\\.")
    end
  end

  if proxy then
    proxy_uri = proxy.uri  -- full uri to proxy (only http supported)
    proxy_authorization = proxy.authorization -- auth to send via CONNECT
    proxy_uri_t, err = self:parse_uri(proxy_uri)
    if not proxy_uri_t then
      return nil, err
    end

    local p_scheme = proxy_uri_t[1]
    if p_scheme ~= "http" then
        return nil, "protocol " .. p_scheme .. " not supported for proxy connections"
    end
    proxy_host = proxy_uri_t[2]
    proxy_port = proxy_uri_t[3]
  end

  -- construct a poolname unique within proxy and ssl info
  if not poolname then
    poolname = (proxy_scheme or "")
               .. ":" .. host
               .. ":" .. tostring(port)
               .. ":" .. tostring(ssl)
               .. ":" .. (ssl_server_name or "")
               .. ":" .. tostring(ssl_verify)
               .. ":" .. (proxy_uri or "")
               .. ":" .. (proxy_authorization or "")
  end

  -- do TCP level connection
  local tcp_opts = { pool = poolname, pool_size = pool_size, backlog = backlog }
  if proxy then
    -- proxy based connection
    ok, err = sock:connect(proxy_host, proxy_port, tcp_opts)
    if not ok then
      return nil, err
    end

    if proxy and proxy_scheme == "https" and sock:getreusedtimes() == 0 then
      -- Make a CONNECT request to create a tunnel to the destination through
      -- the proxy. The request-target and the Host header must be in the
      -- authority-form of RFC 7230 Section 5.3.3. See also RFC 7231 Section
      -- 4.3.6 for more details about the CONNECT request
      local destination = host .. ":" .. port
      local res, err = self:request({
        method = "CONNECT",
        path = destination,
        headers = {
          ["Host"] = destination,
          ["Proxy-Authorization"] = proxy_authorization,
        }
      })

      if not res then
        return nil, err
      end

      if res.status < 200 or res.status > 299 then
        return nil, "failed to establish a tunnel through a proxy: " .. res.status
      end
    end

  elseif not port then
    -- non-proxy, without port -> unix domain socket
    ok, err = sock:connect(host, tcp_opts)
    if not ok then
      return nil, err
    end

  else
    -- non-proxy, regular network tcp
    ok, err = sock:connect(host, port, tcp_opts)
    if not ok then
      return nil, err
    end
  end

  -- Now do the ssl handshake
  if ssl and sock:getreusedtimes() == 0 then
    local ok, err = self:ssl_handshake(ssl_ctx, ssl_server_name, ssl_verify)
    if not ok then
      self:close()
      return nil, err
    end
  end

  self.host = host
  self.port = port
  self.keepalive = true

  return true
end

return http
